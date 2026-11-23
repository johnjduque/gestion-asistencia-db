-- ============================================================================
-- MIGRACION UP 75: DEC-081 deduplicacion del preambulo de los SP del receso academico
--   Crea usp_validar_ejecutor_administrador_periodo_interno (PASO 1 a PASO 3 comunes: correlacion, GEN_002 y ambito ADMINISTRADOR) y recompila
--   usp_crear_receso_academico y usp_retirar_receso_academico para usarlo (CREATE OR ALTER; los permisos del rol runtime se conservan).
-- Sin cambios de columnas, datos ni comportamiento (mismos codigos, mensajes y orden de validaciones). Idempotente. Down: 75_dec081_dedup_preambulo_receso_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 75 UP: deduplicacion del preambulo de los SP del receso';
GO
-- ---- schema/stored-procedures/usp_validar_ejecutor_administrador_periodo_interno.sql

-- =============================================================================
-- Procedimiento: [dbo].[usp_validar_ejecutor_administrador_periodo_interno]   (INTERNO)
-- DEC-081: preambulo comun de usp_crear_receso_academico y usp_retirar_receso_academico (la primera validacion que falla corta):
--   PASO 1: correlacion presente (usp_validar_id_correlacion_esta_presente_interno).
--   PASO 2: ejecutor obligatorio (GEN_002); se evalua con el @idUsuarioEjecutor ORIGINAL (antes de aplicar el valor por defecto).
--   PASO 3: ambito del ejecutor, ADMINISTRADOR de la institucion (usp_resolver_institucion_gestor_periodo_interno: SEC_001 si no es
--           administrador, PER_005 si no tiene institucion); deja la institucion en @idInstitucion.
-- @idCorrelacion llega ya resuelto con su valor por defecto. Los mensajes de entrada se conservan hasta que un paso los escribe, y
-- @estadoResultado parte de 1 (no se inicializa aqui: lo fija el PASO 1). Sin transaccion propia ni TRY/CATCH: un error del sistema sube
-- al CATCH del SP publico que lo llama. Sin EXECUTE para el rol runtime.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_ejecutor_administrador_periodo_interno]
(
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idInstitucion           UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
BEGIN
    SET NOCOUNT ON;
    SET @idInstitucion = NULL;

    -- PASO 1: correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacion,
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
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
        SET @estadoResultado = 0;
    END

    -- PASO 3: ambito del ejecutor (ADMINISTRADOR de la institucion)
    IF @estadoResultado = 1
        EXEC dbo.usp_resolver_institucion_gestor_periodo_interno
            @idUsuario = @idUsuarioEjecutorDefecto, @idCorrelacion = @idCorrelacion,
            @idInstitucion = @idInstitucion OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
END;
GO

-- ---- schema/stored-procedures/usp_crear_receso_academico.sql

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
        -- PASOS 1 a 3: correlacion, ejecutor obligatorio (GEN_002) y ambito (ADMINISTRADOR de la institucion)
        EXEC dbo.usp_validar_ejecutor_administrador_periodo_interno
            @idCorrelacion = @idCorrelacionDefecto, @idUsuarioEjecutor = @idUsuarioEjecutor,
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

-- ---- schema/stored-procedures/usp_retirar_receso_academico.sql

-- ============================================================================
-- usp_retirar_receso_academico (DEC-081) — borrado logico (estaActivo = 0) de un dia de receso, solo si NO ha cancelado ninguna sesion.
-- Solo el ADMINISTRADOR de la institucion del periodo. Reglas (la primera que falla corta):
--   * receso inexistente, ya retirado o de otra institucion => REC_009;
--   * periodo cerrado (fechaCierreUtc no nula) => REC_007;
--   * el dia ya cancelo sesiones (SesionCancelacion.recesoAcademico) => REC_010 con el conteo: no se retira ni se cambia.
-- Exito: REC_002. Resultset: tupla canonica de 4 columnas. Corregir un dia = retirarlo (si no esta aplicado) y crear otro.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_retirar_receso_academico]
(
    @idReceso                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idRecesoDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idReceso, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucion            UNIQUEIDENTIFIER;
    DECLARE @idRecesoEncontrado       UNIQUEIDENTIFIER;
    DECLARE @fechaReceso              DATE;
    DECLARE @nombrePeriodo            NVARCHAR(50);
    DECLARE @fechaCierreUtc           DATETIME2(7);
    DECLARE @sesionesCanceladas       INT = 0;
    DECLARE @codigoRechazo            VARCHAR(20);
    DECLARE @p1                       NVARCHAR(500);

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
        -- PASOS 1 a 3: correlacion, ejecutor obligatorio (GEN_002) y ambito (ADMINISTRADOR de la institucion)
        EXEC dbo.usp_validar_ejecutor_administrador_periodo_interno
            @idCorrelacion = @idCorrelacionDefecto, @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idInstitucion = @idInstitucion OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 4: transaccion, bloqueo del dia y reglas del retiro
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
                SAVE TRANSACTION sp_retirar_receso;
                SET @savepointCreado = 1;
            END

            SELECT  @idRecesoEncontrado = r.id, @fechaReceso = r.fecha, @nombrePeriodo = pa.nombre, @fechaCierreUtc = pa.fechaCierreUtc
            FROM    dbo.PeriodoRecesoAcademico r WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.PeriodoAcademico pa ON pa.id = r.periodoAcademico AND pa.institucion = @idInstitucion
            WHERE   r.id = @idRecesoDefecto AND r.estaActivo = 1;

            IF @idRecesoEncontrado IS NOT NULL
                SELECT @sesionesCanceladas = COUNT(1) FROM dbo.SesionCancelacion sc WHERE sc.recesoAcademico = @idRecesoEncontrado;

            IF @idRecesoEncontrado IS NULL
            BEGIN
                SET @codigoRechazo = 'REC_009';
                SET @p1 = CONVERT(NVARCHAR(36), @idRecesoDefecto);
            END
            ELSE IF @fechaCierreUtc IS NOT NULL
            BEGIN
                SET @codigoRechazo = 'REC_007';
                SET @p1 = @nombrePeriodo;
            END
            ELSE IF @sesionesCanceladas > 0
            BEGIN
                SET @codigoRechazo = 'REC_010';
                SET @p1 = CONVERT(NVARCHAR(20), @sesionesCanceladas);
            END

            IF @codigoRechazo IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo, @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                UPDATE dbo.PeriodoRecesoAcademico SET estaActivo = 0 WHERE id = @idRecesoEncontrado;

                SET @p1 = CONVERT(NVARCHAR(10), @fechaReceso, 103);
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REC_002', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

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
            ROLLBACK TRANSACTION sp_retirar_receso;
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

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

PRINT 'MIGRACION 75 UP: completada';
GO
