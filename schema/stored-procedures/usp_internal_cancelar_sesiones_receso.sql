USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_cancelar_sesiones_receso (DEC-081) — nucleo, sin EXECUTE para el rol runtime.
--
-- Marca como canceladas por RECESO las sesiones cuya fecha LOCAL (TIEMPO/ZONA_HORARIA_SQLSERVER) es un dia de receso activo del
-- periodo de su grupo. No abre transaccion: la controla el llamador (usp_crear_receso_academico, la precarga o la generacion v2).
--   * Alcance: @idReceso (un dia, todos los grupos de su periodo) y/o @idGrupo (todos los recesos activos del periodo del grupo).
--     Al menos uno es obligatorio (GEN_002). Con los dos, solo ese dia en ese grupo.
--   * Solo sesiones con procedencia temporal confirmada y sin SesionCancelacion (idempotente; un festivo ya aplicado gana).
--   * @soloFuturas = 1 limita a fechaHoraInicio > SYSUTCDATETIME(); 0 (generacion y precarga) cancela tambien una sesion nueva ya pasada.
--   * Una candidata con Asistencia o TomaAsistencia no se toca: se cuenta en @sesionesConAsistencia.
--   * Tipo = TipoCancelacionSesion con codigo RECESO/CODIGO_TIPO_CANCELACION; motivo = RECESO/PREFIJO_MOTIVO_CANCELACION + motivo del dia
--     (recortado a 500). usuarioEjecutor puede ser NULL (generacion automatica): el origen lo da recesoAcademico.
-- Bloqueo: dbo.Sesion WITH (UPDLOCK, HOLDLOCK) sobre las candidatas antes de escribir (mismo orden que los festivos).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_cancelar_sesiones_receso]
(
    @idGrupo                  UNIQUEIDENTIFIER = NULL,
    @idReceso                 UNIQUEIDENTIFIER = NULL,
    @soloFuturas              BIT,
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER,
    @sesionesCanceladas       INT OUTPUT,
    @sesionesConAsistencia    INT OUTPUT,
    @mensajeUsuarioResultado  NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000) OUTPUT,
    @estadoResultado          BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @prefijoMotivo        NVARCHAR(200)    = dbo.ufn_obtener_parametro('RECESO', 'PREFIJO_MOTIVO_CANCELACION');
    DECLARE @codigoTipo           NVARCHAR(20)     = CAST(dbo.ufn_obtener_parametro('RECESO', 'CODIGO_TIPO_CANCELACION') AS NVARCHAR(20));
    DECLARE @zonaHorariaSqlServer SYSNAME;
    DECLARE @idTipoReceso         UNIQUEIDENTIFIER;
    DECLARE @ahoraUtc             DATETIME2 = SYSUTCDATETIME();

    DECLARE @candidatas TABLE (
        idSesion        UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        idReceso        UNIQUEIDENTIFIER NOT NULL,
        motivo          NVARCHAR(200)    NOT NULL,
        tieneAsistencia BIT              NOT NULL
    );

    SELECT
        @sesionesCanceladas = 0,
        @sesionesConAsistencia = 0,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: alcance obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idGrupo IS NULL AND @idReceso IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idGrupo/idReceso',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: zona horaria institucional valida (GEN_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @zonaHorariaSqlServer = CONVERT(SYSNAME, p.valor)
            FROM dbo.uv_parametro p
            WHERE p.grupo = 'TIEMPO' AND p.clave = 'ZONA_HORARIA_SQLSERVER' AND p.estaActivo = 1;

            IF @zonaHorariaSqlServer IS NULL
               OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE [name] = @zonaHorariaSqlServer)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TIEMPO/ZONA_HORARIA_SQLSERVER',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: tipo de cancelacion del receso, por el codigo del parametro (GEN_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idTipoReceso = t.id FROM dbo.uv_tipo_cancelacion_sesion t WHERE t.codigo = @codigoTipo;

            IF @idTipoReceso IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TipoCancelacionSesion(RECESO/CODIGO_TIPO_CANCELACION)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: candidatas bloqueadas (fecha local en un receso activo del periodo del grupo, sin cancelacion previa)
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO @candidatas (idSesion, idReceso, motivo, tieneAsistencia)
            SELECT  s.id, r.id, r.motivo,
                    CAST(IIF(EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = s.id)
                             OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id), 1, 0) AS BIT)
            FROM    dbo.PeriodoRecesoAcademico r
            INNER JOIN dbo.Grupo g
            ON      g.periodoAcademico = r.periodoAcademico
            INNER JOIN dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            ON      s.grupo = g.id
            AND     s.fechaHoraInicio >= DATEADD(DAY, -1, CAST(r.fecha AS DATETIME2))
            AND     s.fechaHoraInicio <  DATEADD(DAY, 2, CAST(r.fecha AS DATETIME2))
            AND     CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zonaHorariaSqlServer AS DATE) = r.fecha
            WHERE   r.estaActivo = 1
              AND   (@idReceso IS NULL OR r.id = @idReceso)
              AND   (@idGrupo IS NULL OR g.id = @idGrupo)
              AND   s.procedenciaTemporal IS NOT NULL
              AND   (@soloFuturas = 0 OR s.fechaHoraInicio > @ahoraUtc)
              AND   NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id);

            SET @sesionesConAsistencia = (SELECT COUNT(1) FROM @candidatas WHERE tieneAsistencia = 1);

            INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, recesoAcademico, usuarioEjecutor, fechaCancelacionUtc, idCorrelacion)
            SELECT  c.idSesion, @idTipoReceso, LEFT(CONCAT(@prefijoMotivo, c.motivo), 500), c.idReceso,
                    @idUsuarioEjecutor, SYSUTCDATETIME(), @idCorrelacionDefecto
            FROM    @candidatas c
            WHERE   c.tieneAsistencia = 0;
            SET @sesionesCanceladas = @@ROWCOUNT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SELECT @estadoResultado = 0, @sesionesCanceladas = 0, @sesionesConAsistencia = 0;
    END CATCH
END;
GO
