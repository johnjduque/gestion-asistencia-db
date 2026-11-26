USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_recesos_periodo (DEC-081) — READ_QUERY_RESULTSET: dias de receso activos de un periodo, ordenados por fecha.
-- Lectura permitida a ADMINISTRADOR, DECANO, COORDINADOR y DOCENTE cuya institucion sea la del periodo (administrador: Administrador.institucion;
-- decano: su facultad; coordinador: un programa que coordina; docente: vinculo activo a un programa o grupo titular en el periodo).
-- Sin perfil => SEC_001; periodo inexistente o fuera del ambito => PER_001. Las fallas se propagan con THROW 51000.
-- Columnas: id, idPeriodoAcademico, fecha, motivo, sesionesCanceladas (INT), estaAplicado (BIT), puedeRetirarse (BIT: no aplicado y periodo
-- sin cerrar), fechaCreacionUtc, totalRegistros.
-- ============================================================================
-- SKILLS-BD lote 9 (2026-11-26): PASO n, IF con BEGIN/END, periodo y ambito por uv_periodo_academico_fechas, uv_administrador, uv_decano_identidad, uv_facultad, uv_coordinador_identidad, uv_programa, uv_docente_programa, uv_docente_identidad y uv_grupo_registro (antes, las tablas) y TRY/CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_recesos_periodo]
(
    @idPeriodo         UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPeriodoDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPeriodo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucion        UNIQUEIDENTIFIER;
    DECLARE @fechaCierreUtc       DATETIME2(7);
    DECLARE @enAmbito             BIT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil ADMINISTRADOR, DECANO, COORDINADOR o DOCENTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ADMINISTRADOR,DECANO,COORDINADOR,DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Ambito sobre la institucion del periodo (PER_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idInstitucion = pa.idInstitucion, @fechaCierreUtc = pa.fechaCierreUtc
            FROM dbo.uv_periodo_academico_fechas pa WHERE pa.id = @idPeriodoDefecto;

            IF @idInstitucion IS NOT NULL
               AND (EXISTS (SELECT 1 FROM dbo.uv_administrador a WHERE a.idUsuario = @idUsuarioDefecto AND a.idInstitucion = @idInstitucion)
                 OR EXISTS (SELECT 1 FROM dbo.uv_decano_identidad d INNER JOIN dbo.uv_facultad f ON f.idDecano = d.id
                            WHERE d.idUsuario = @idUsuarioDefecto AND f.idInstitucion = @idInstitucion)
                 OR EXISTS (SELECT 1 FROM dbo.uv_coordinador_identidad c INNER JOIN dbo.uv_programa p ON p.idCoordinador = c.id
                            WHERE c.idUsuario = @idUsuarioDefecto AND p.idInstitucion = @idInstitucion)
                 OR EXISTS (SELECT 1 FROM dbo.uv_docente_programa dp
                            WHERE dp.idUsuario = @idUsuarioDefecto AND dp.estaActivoVinculacion = 1 AND dp.idInstitucion = @idInstitucion)
                 OR EXISTS (SELECT 1 FROM dbo.uv_docente_identidad dc INNER JOIN dbo.uv_grupo_registro g ON g.idDocente = dc.id AND g.idPeriodoAcademico = @idPeriodoDefecto
                            WHERE dc.idUsuario = @idUsuarioDefecto))
            BEGIN
                SET @enAmbito = 1;
            END

            IF @enAmbito = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PER_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: Rechazo: THROW 51000 con el mensaje tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 6: Recesos activos del periodo
        SELECT
            id                 = r.id,
            idPeriodoAcademico = r.idPeriodoAcademico,
            fecha              = r.fecha,
            motivo             = r.motivo,
            sesionesCanceladas = r.sesionesCanceladas,
            estaAplicado       = r.estaAplicado,
            puedeRetirarse     = CAST(IIF(r.estaAplicado = 0 AND @fechaCierreUtc IS NULL, 1, 0) AS BIT),
            fechaCreacionUtc   = r.fechaCreacionUtc,
            totalRegistros     = COUNT(1) OVER()
        FROM dbo.uv_periodo_receso_academico r
        WHERE r.idPeriodoAcademico = @idPeriodoDefecto
        ORDER BY r.fecha, r.id;
    END TRY
    BEGIN CATCH
        -- PASO 7: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
