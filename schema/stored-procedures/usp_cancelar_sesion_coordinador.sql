USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cancelar_sesion_coordinador (CULM-001 / DEC-064; HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con la misma tupla que usp_cancelar_sesion: canonica + idSesion, idGrupo,
-- fechaCancelacionUtc, totalEstudiantesActivos (NULL si estadoResultado = 0).
--
-- El coordinador del programa cancela una sesion creada manualmente por el docente (uv_sesion_manual, procedenciaTemporal UTC_V2).
-- No cambia la firma publica de usp_cancelar_sesion (docente). Reglas:
--   * RBAC COORDINADOR (SEC_001); sesion existente (SES_001);
--   * ambito: el coordinador coordina AL MENOS UNO de los programas vigentes del grupo (ufn_programas_grupo INTERSECT
--     ufn_programas_coordinador); si no, SEC_002. En un grupo mixto lo reciben (y pueden cancelar) los coordinadores de ambos programas;
--   * solo sesiones manuales: SES_018; motivo del catalogo MotivoCancelacionSesion activo: SES_019; observacion recortada <=
--     SESION/OBSERVACION_CANCELACION_COORDINADOR_MAXIMA: SES_021;
--   * mismas reglas de escritura que usp_cancelar_sesion: doble cancelacion SES_011 (se conserva el motivo original); con asistencia o
--     toma SES_012 (ventana vigente) o SES_016 (terminada);
--   * SesionCancelacion.motivo = nombre del motivo [+ ': ' + observacion]; tipo = el manual (TipoCancelacionSesion.esAutomatica = 0);
--     usuarioEjecutor = el coordinador (auditoria). Evento y aviso a estudiantes los publica el backend (SESION_CANCELADA).
-- Transaccion propia o SAVE TRANSACTION; la fila de dbo.Sesion se bloquea (UPDLOCK, HOLDLOCK) antes de leer la cancelacion y la
-- asistencia. Las ramas de rechazo no escriben: solo confirman la transaccion propia (compatible con INSERT ... EXEC).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cancelar_sesion_coordinador]
(
    @idSesion          UNIQUEIDENTIFIER,
    @codigoMotivo      NVARCHAR(50),
    @observacion       NVARCHAR(4000) = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @observacionLimpia NVARCHAR(4000) = NULLIF(LTRIM(RTRIM(@observacion)), N'');
    DECLARE @observacionMaxima INT = dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'OBSERVACION_CANCELACION_COORDINADOR_MAXIMA');
    DECLARE @margenMinutos     INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @codigoMatriculaActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idTipoManual      UNIQUEIDENTIFIER;
    DECLARE @codigoTipoManual  NVARCHAR(20);
    DECLARE @nombreMotivo      NVARCHAR(200);
    DECLARE @motivoTexto       NVARCHAR(500);
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @fechaHoraFin      DATETIME2;
    DECLARE @fechaCancelacion  DATETIME2(0) = NULL;
    DECLARE @totalActivos      INT = NULL;
    DECLARE @codigoRechazo     VARCHAR(20) = NULL;
    DECLARE @observacionMaximaTexto NVARCHAR(20);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC (COORDINADOR)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: sesion existente (SES_001)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: ambito del coordinador sobre el grupo de la sesion (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idGrupo = s.grupo FROM dbo.Sesion s WHERE s.id = @idSesionDefecto;

            IF NOT EXISTS (SELECT idPrograma FROM dbo.ufn_programas_grupo(@idGrupo)
                           INTERSECT
                           SELECT idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto))
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: solo sesiones creadas manualmente por el docente (SES_018)
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_manual sm WHERE sm.idSesion = @idSesionDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_018', @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: motivo del catalogo (SES_019)
        IF @estadoResultado = 1
        BEGIN
            SELECT @nombreMotivo = m.nombre
            FROM dbo.uv_motivo_cancelacion_sesion m
            WHERE m.codigo = LTRIM(RTRIM(@codigoMotivo)) AND m.estaActivo = 1;

            IF @nombreMotivo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_019', @p_param1 = @codigoMotivo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: observacion recortada dentro del maximo parametrizado (SES_021)
        IF @estadoResultado = 1
           AND (@observacionMaxima IS NULL OR LEN(@observacionLimpia) > @observacionMaxima)
        BEGIN
            SET @observacionMaximaTexto = CONVERT(NVARCHAR(20), @observacionMaxima);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_021', @p_param1 = @observacionMaximaTexto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 8: tipo manual de cancelacion por bandera de catalogo
        IF @estadoResultado = 1
        BEGIN
            SELECT @idTipoManual = t.id, @codigoTipoManual = t.codigo
            FROM dbo.uv_tipo_cancelacion_sesion t
            WHERE t.esAutomatica = 0;

            IF @idTipoManual IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TipoCancelacionSesion(esAutomatica = 0)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 9: escritura atomica bajo el bloqueo de la sesion
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cancelar_sesion_coordinador;
                SET @savepointCreado = 1;
            END

            SELECT @fechaHoraFin = s.fechaHoraFin
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            IF EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
                SET @codigoRechazo = 'SES_011';
            ELSE IF EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = @idSesionDefecto)
                 OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = @idSesionDefecto)
                SET @codigoRechazo = IIF(SYSUTCDATETIME() >= DATEADD(MINUTE, IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos), @fechaHoraFin),
                                         'SES_016', 'SES_012');

            IF @codigoRechazo IS NULL
            BEGIN
                SET @fechaCancelacion = SYSUTCDATETIME();
                SET @motivoTexto = IIF(@observacionLimpia IS NULL, @nombreMotivo, CONCAT(@nombreMotivo, N': ', @observacionLimpia));

                INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, fechaCancelacionUtc, idCorrelacion)
                VALUES (@idSesionDefecto, @idTipoManual, @motivoTexto, NULL, @idUsuarioEjecutorDefecto, @fechaCancelacion, @idCorrelacionDefecto);

                SELECT @totalActivos = COUNT(1)
                FROM dbo.uv_estudiante_grupo eg
                WHERE eg.idGrupo = @idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_020', @p_param1 = @idSesionDefecto, @p_param2 = @codigoTipoManual,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo, @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- La rama de rechazo no escribe: solo se confirma la transaccion propia (libera el bloqueo).
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_cancelar_sesion_coordinador;

        -- Transaccion externa condenada que no nos pertenece: se propaga al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idSesion                = IIF(@estadoResultado = 1, @idSesionDefecto, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        fechaCancelacionUtc     = IIF(@estadoResultado = 1, @fechaCancelacion, NULL),
        totalEstudiantesActivos = IIF(@estadoResultado = 1, @totalActivos, NULL);
END;
GO
