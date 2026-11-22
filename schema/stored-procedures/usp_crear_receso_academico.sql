USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_crear_receso_academico (DEC-081) — registra un dia de receso academico en un periodo y CANCELA de inmediato las sesiones de ese
-- dia en todos los grupos del periodo. Solo el ADMINISTRADOR de la institucion del periodo (usp_resolver_institucion_gestor_periodo_interno:
-- SEC_001 si no es administrador, PER_005 si no tiene institucion). Un periodo de otra institucion o inexistente responde PER_001.
-- Validaciones y mensajes: usp_validar_receso_academico_interno (REC_003..REC_008). Cancelacion: usp_internal_cancelar_sesiones_receso
-- (@soloFuturas = 1; una sesion con asistencia o toma no se toca y se informa en sesionesConAsistencia).
--
-- CONTRATO DE RESULTSETS (comando NON_GOLDEN_PATH_EXTENSION):
--   Resultset 1 (siempre): idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado,
--                          idReceso (UNIQUEIDENTIFIER; NULL si estadoResultado = 0), sesionesCanceladas (INT; NULL si falla),
--                          sesionesConAsistencia (INT; NULL si falla).
--   Resultset 2 (solo si estadoResultado = 1 y @incluirDetalle = 1): una fila por sesion cancelada, ordenada por inicioUtc:
--                          idSesion, idGrupo (UNIQUEIDENTIFIER), fecha (DATE, fecha local institucional = la del receso), inicioUtc (DATETIME2).
--                          Con 0 sesiones canceladas el resultset 2 va vacio. El backend lo usa para armar los correos
--                          (destinatarios: usp_consultar_destinatarios_receso_academico).
--   @incluirDetalle = 0 omite el resultset 2 (las pruebas T-SQL lo usan porque INSERT ... EXEC no admite dos resultsets distintos).
-- @idReceso opcional: NULL => el SP genera el identificador. Mensaje de exito REC_001 (fecha dd/MM/yyyy, clases canceladas).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_receso_academico]
(
    @idPeriodo               UNIQUEIDENTIFIER,
    @fecha                   DATE,
    @motivo                  NVARCHAR(4000),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL,
    @idReceso                UNIQUEIDENTIFIER = NULL,
    @incluirDetalle          BIT = 1
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucion            UNIQUEIDENTIFIER;
    DECLARE @idRecesoNuevo            UNIQUEIDENTIFIER = COALESCE(@idReceso, NEWID());
    DECLARE @motivoNormalizado        NVARCHAR(200);
    DECLARE @sesionesCanceladas       INT = 0;
    DECLARE @sesionesConAsistencia    INT = 0;
    DECLARE @p1                       NVARCHAR(500);
    DECLARE @p2                       NVARCHAR(500);
    DECLARE @p3                       NVARCHAR(500);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: ambito del ejecutor (ADMINISTRADOR de la institucion)
        IF @estadoResultado = 1
            EXEC dbo.usp_resolver_institucion_gestor_periodo_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idCorrelacion = @idCorrelacionDefecto,
                @idInstitucion = @idInstitucion OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 4: transaccion (propia o savepoint), validacion, alta y cancelacion
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_crear_receso;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_validar_receso_academico_interno
                @idPeriodo = @idPeriodo, @fecha = @fecha, @motivo = @motivo, @idInstitucion = @idInstitucion,
                @idCorrelacion = @idCorrelacionDefecto, @motivoNormalizado = @motivoNormalizado OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                INSERT INTO dbo.PeriodoRecesoAcademico (id, periodoAcademico, fecha, motivo, estaActivo, fechaCreacionUtc, usuarioCreador, idCorrelacion)
                VALUES (@idRecesoNuevo, @idPeriodo, @fecha, @motivoNormalizado, 1, SYSUTCDATETIME(), @idUsuarioEjecutorDefecto, @idCorrelacionDefecto);

                EXEC dbo.usp_internal_cancelar_sesiones_receso
                    @idGrupo = NULL, @idReceso = @idRecesoNuevo, @soloFuturas = 1,
                    @idCorrelacion = @idCorrelacionDefecto, @idUsuarioEjecutor = @idUsuarioEjecutorDefecto,
                    @sesionesCanceladas = @sesionesCanceladas OUTPUT, @sesionesConAsistencia = @sesionesConAsistencia OUTPUT,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF XACT_STATE() = -1
                    THROW 51000, @mensajeTecnicoResultado, 1;

                IF @estadoResultado = 1
                BEGIN
                    -- REC_001: usuario (fecha, clases canceladas); tecnico (id, canceladas, con asistencia)
                    SELECT @p1 = CONVERT(NVARCHAR(10), @fecha, 103), @p2 = CONVERT(NVARCHAR(20), @sesionesCanceladas);
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'REC_001', @p_param1 = @p1, @p_param2 = @p2,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SELECT @p1 = CONVERT(NVARCHAR(36), @idRecesoNuevo), @p2 = CONVERT(NVARCHAR(20), @sesionesCanceladas),
                           @p3 = CONVERT(NVARCHAR(20), @sesionesConAsistencia);
                    DECLARE @mensajeUsuarioExito NVARCHAR(4000) = @mensajeUsuarioResultado;
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'REC_001', @p_param1 = @p1, @p_param2 = @p2, @p_param3 = @p3,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeUsuarioResultado = @mensajeUsuarioExito;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                END
            END

            -- Un rechazo no escribio nada: se cierra la transaccion propia con COMMIT (solo libera bloqueos; un ROLLBACK no es valido dentro de
            -- INSERT ... EXEC) y un savepoint no necesita reversion
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
        BEGIN
            ROLLBACK TRANSACTION sp_crear_receso;
        END
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- Resultset 1: tupla canonica + datos del comando
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idReceso                = CAST(IIF(@estadoResultado = 1, @idRecesoNuevo, NULL) AS UNIQUEIDENTIFIER),
        sesionesCanceladas      = CAST(IIF(@estadoResultado = 1, @sesionesCanceladas, NULL) AS INT),
        sesionesConAsistencia   = CAST(IIF(@estadoResultado = 1, @sesionesConAsistencia, NULL) AS INT);

    -- Resultset 2: sesiones canceladas por este receso (solo en exito)
    IF @estadoResultado = 1 AND @incluirDetalle = 1
        SELECT
            idSesion  = s.id,
            idGrupo   = s.grupo,
            fecha     = @fecha,
            inicioUtc = s.fechaHoraInicio
        FROM dbo.SesionCancelacion sc
        INNER JOIN dbo.Sesion s ON s.id = sc.sesion
        WHERE sc.recesoAcademico = @idRecesoNuevo
        ORDER BY s.fechaHoraInicio, s.id;
END;
GO
