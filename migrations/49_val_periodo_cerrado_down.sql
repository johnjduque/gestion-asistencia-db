-- ============================================================================
-- MIGRACION DOWN 49: retira la regla de "periodo cerrado" (VAL-pendientes-john PRU-15)
--   1. Restaura el texto de develop (antes de la 49) de usp_validar_sesion_ventana_registro_interno, usp_cerrar_toma_asistencia,
--      usp_internal_radicar_solicitud_revision, usp_radicar_solicitud_revision_asistencia, usp_resolver_solicitud_revision_asistencia,
--      usp_retirar_solicitud_revision_asistencia y usp_ejecutar_cierre_masivo_periodo (el doble cierre vuelve a ser idempotente).
--   2. DROP de usp_validar_periodo_abierto_sesion_interno; borra PER_008 y PER_009.
--   3. DROP de la columna PeriodoAcademico.fechaCierreUtc: se pierde la marca de los periodos cerrados (la auditoria
--      CIERRE_MASIVO_PERIODO se conserva y un nuevo up la reconstruye). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 49 DOWN: retira la regla de periodo cerrado';
GO
-- ---- schema/stored-procedures/usp_validar_sesion_ventana_registro_interno.sql (texto de develop antes de la 49)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SES-01: ventana de registro ordinario de asistencia (cierre estricto, sin tolerancia).
--   * Solo se registra cuando fechaHoraInicio <= SYSUTCDATETIME() < fechaHoraFin. El reloj autoritativo es el
--     del motor (UTC); nunca el del cliente ni el del backend.
--   * Solo una procedencia confirmada (UTC_V2, UTC_GENERADOR, UTC_OWNER) prueba que los DATETIME2 son instantes
--     UTC. NULL (INDETERMINADA) no permite escribir: no se supone zona horaria alguna.
--   * Lee la fila de dbo.Sesion con UPDLOCK + HOLDLOCK: invocado dentro de la transaccion del llamador, el
--     bloqueo se mantiene hasta su COMMIT/ROLLBACK, de modo que el horario no cambia entre esta validacion y la
--     escritura, y los lotes concurrentes de la misma sesion se serializan y evaluan el reloj despues de
--     obtener el bloqueo (una solicitud iniciada antes del cierre que llega despues del cierre se rechaza).
--   * Codigos: SES_007 (sesion no iniciada), SES_008 (sesion cerrada), SES_009 (horario indeterminado).
--   * No escribe. El llamador decide la reversion y el resultset canonico.
-- CULM-001 B.1 (CONTRACT §2.7.1):
--   * @toleranciaMinutos / @margenMinutos (opcionales): ventana [inicio - tolerancia, fin + margen). NULL o negativos = 0,
--     es decir, la regla estricta de SES-01; los llamadores de 5 parametros (lote congelado, autonomo) no cambian.
--     Los valores los lee el LLAMADOR (ASISTENCIA/TOLERANCIA_MINUTOS y ASISTENCIA/MARGEN_RETARDO_MINUTOS).
--   * PASO 2.5 (todos los llamadores): una sesion con dbo.SesionCancelacion se rechaza con SES_010. Se lee despues del
--     UPDLOCK + HOLDLOCK sobre dbo.Sesion, el mismo bloqueo que toma usp_cancelar_sesion: registro y cancelacion se
--     serializan.
-- CULM-001 B.2 (CONTRACT §2.8.3, NB-4, alternativa aprobada de antemano): @bloqueoCompartido = 1 lee la sesion con HOLDLOCK
--   (bloqueo compartido) en lugar de UPDLOCK, HOLDLOCK. Solo lo usa usp_registrar_asistencia_por_token: los registros QR de un
--   grupo no se serializan entre si y la cancelacion (U/X) sigue serializada contra ellos; el registro no actualiza Sesion,
--   asi que no hay conversion de bloqueo. Por defecto 0: todos los demas llamadores conservan el bloqueo exclusivo.
-- CULM-001 / DEC-065 (2): PASO 2.6, una sesion con solicitud en espera (EstadoSolicitudSesion.esFinal = 0) se rechaza con SES_023;
--   abrir toma/QR y registrar asistencia pasan todos por este validador.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_sesion_ventana_registro_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @toleranciaMinutos       INT = NULL,
    @margenMinutos           INT = NULL,
    @bloqueoCompartido       BIT = 0
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @existe              BIT = 0;
    DECLARE @fechaHoraInicio     DATETIME2;
    DECLARE @fechaHoraFin        DATETIME2;
    DECLARE @procedenciaTemporal NVARCHAR(24);
    DECLARE @instanteActualUtc   DATETIME2;
    DECLARE @toleranciaAplicada  INT = IIF(@toleranciaMinutos IS NULL OR @toleranciaMinutos < 0, 0, @toleranciaMinutos);
    DECLARE @margenAplicado      INT = IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos);
    DECLARE @aperturaUtc         DATETIME2;
    DECLARE @cierreUtc           DATETIME2;
    DECLARE @detalleVentana      NVARCHAR(200) = IIF(@toleranciaMinutos IS NULL AND @margenMinutos IS NULL,
                                                     dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
                                                     CONCAT(' Tolerancia: ', @toleranciaAplicada, ' min; margen: ', @margenAplicado, ' min.'));

    -- Inicialización de respuesta desde parámetros del catálogo
    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Lectura bloqueada del horario y su procedencia (misma fila, una sola sentencia)
        IF @estadoResultado = 1
        BEGIN
            IF @bloqueoCompartido = 1
                SELECT TOP 1
                    @existe = 1,
                    @fechaHoraInicio = s.fechaHoraInicio,
                    @fechaHoraFin = s.fechaHoraFin,
                    @procedenciaTemporal = s.procedenciaTemporal
                FROM dbo.Sesion s WITH (HOLDLOCK)
                WHERE s.id = @idSesionDefecto;
            ELSE
                SELECT TOP 1
                    @existe = 1,
                    @fechaHoraInicio = s.fechaHoraInicio,
                    @fechaHoraFin = s.fechaHoraFin,
                    @procedenciaTemporal = s.procedenciaTemporal
                FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
                WHERE s.id = @idSesionDefecto;

            IF @existe = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_001',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2.5 (CULM-001 B.1): sesion cancelada => SES_010 (lectura despues del bloqueo de la fila de dbo.Sesion)
        IF @estadoResultado = 1
           AND EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_010',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2.6 (DEC-065 (2)): sesion extraordinaria pendiente de aprobacion del coordinador => SES_023 (no admite tomas ni asistencia)
        IF @estadoResultado = 1
           AND EXISTS (SELECT 1 FROM dbo.SesionSolicitud ss
                       INNER JOIN dbo.EstadoSolicitudSesion es ON es.id = ss.idEstado
                       WHERE ss.sesion = @idSesionDefecto AND es.esFinal = 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_023',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Procedencia temporal confirmada (NULL o desconocida = INDETERMINADA)
        IF @estadoResultado = 1
           AND (@procedenciaTemporal IS NULL OR @procedenciaTemporal NOT IN (N'UTC_V2', N'UTC_GENERADOR', N'UTC_OWNER'))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_009',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Ventana [inicio - tolerancia, fin + margen) contra el reloj UTC del motor, leído después de obtener
        --         el bloqueo. Sin tolerancia ni margen es la ventana estricta [inicio, fin) de SES-01.
        IF @estadoResultado = 1
        BEGIN
            SET @instanteActualUtc = SYSUTCDATETIME();
            SET @aperturaUtc = DATEADD(MINUTE, -@toleranciaAplicada, @fechaHoraInicio);
            SET @cierreUtc = DATEADD(MINUTE, @margenAplicado, @fechaHoraFin);

            IF @instanteActualUtc < @aperturaUtc
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_007',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, @detalleVentana, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @instanteActualUtc >= @cierreUtc
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_008',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, @detalleVentana, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
-- ---- schema/stored-procedures/usp_cerrar_toma_asistencia.sql (texto de develop antes de la 49)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cerrar_toma_asistencia (CULM-001 B.2, HU175; CONTRACT §2.8.2, DEC-013, [SUPUESTO-B-08])
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idToma, idSesion, idGrupo, fechaCierreUtc,
-- totalAusentesMarcados, totalFaltantes, yaEstabaCerrada (NULL si estadoResultado = 0).
--
-- El docente titular cierra una toma (no exige ventana para cerrar). Ya cerrada: exito idempotente TOM_011
-- (yaEstabaCerrada = 1, sin escrituras). Si no: cierra el token QR activo de la toma; con @marcarAusentes = 1 (NULL =>
-- ModoTomaAsistencia.marcaAusentesAlCerrar: MANUAL 0, QR 1) y la ventana con margen todavia abierta, inserta SJC a las
-- matriculas activas sin detalle en la toma (usp_internal_marcar_ausentes_toma); vencida la ventana se cierra sin marcar.
-- totalFaltantes = filas de uv_faltantes_toma despues del cierre. Bloqueos: Sesion -> TomaAsistencia -> TokenAsistenciaToma.
-- Exito TOM_009.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cerrar_toma_asistencia]
(
    @idToma            UNIQUEIDENTIFIER,
    @marcarAusentes    BIT = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTomaDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idToma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeDescartado       NVARCHAR(4000);
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @idSesion          UNIQUEIDENTIFIER;
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @fechaCierrePrevia DATETIME2(0);
    DECLARE @marcaPorModo      BIT;
    DECLARE @marcar            BIT;
    DECLARE @ventanaAbierta    BIT;
    DECLARE @idEstadoCerrada   UNIQUEIDENTIFIER;
    DECLARE @fechaCierre       DATETIME2(0);
    DECLARE @totalMarcados     INT = 0;
    DECLARE @totalFaltantes    INT;
    DECLARE @yaEstabaCerrada   BIT = 0;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- Toma existente (TOM_001) y titularidad sobre su sesion
        IF @estadoResultado = 1
        BEGIN
            SELECT @idSesion = t.sesion, @idGrupo = s.grupo
            FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion
            WHERE t.id = @idTomaDefecto;

            IF @idSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_001', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idSesion, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            SELECT @idEstadoCerrada = e.id FROM dbo.EstadoTomaAsistencia e WHERE e.estaAbierta = 0;
            IF @idEstadoCerrada IS NULL
                THROW 52511, 'CULM001_B2_CATALOGO_INCONSISTENTE: falta EstadoTomaAsistencia(estaAbierta = 0).', 1;

            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cerrar_toma;
                SET @savepointCreado = 1;
            END

            -- Bloqueo de la sesion (sin exigir ventana para cerrar) y luego de la toma
            SELECT @idGrupo = s.grupo FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK) WHERE s.id = @idSesion;
            SELECT @fechaCierrePrevia = t.fechaCierreUtc, @marcaPorModo = m.marcaAusentesAlCerrar, @totalMarcados = t.totalAusentesMarcados
            FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.ModoTomaAsistencia m ON m.id = t.modo
            WHERE t.id = @idTomaDefecto;

            IF @fechaCierrePrevia IS NOT NULL
            BEGIN
                SET @yaEstabaCerrada = 1;
                SET @fechaCierre = @fechaCierrePrevia;
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_011', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                SET @fechaCierre = SYSUTCDATETIME();
                SET @marcar = IIF(@marcarAusentes IS NULL, @marcaPorModo, @marcarAusentes);
                SELECT @ventanaAbierta = v.ventanaAbierta FROM dbo.uv_sesion_estado v WHERE v.idSesion = @idSesion;
                SET @totalMarcados = 0;

                UPDATE dbo.TokenAsistenciaToma SET fechaCierreUtc = @fechaCierre
                WHERE toma = @idTomaDefecto AND fechaCierreUtc IS NULL;

                IF @marcar = 1 AND @ventanaAbierta = 1
                    EXEC dbo.usp_internal_marcar_ausentes_toma
                        @idToma = @idTomaDefecto, @idSesion = @idSesion, @idGrupo = @idGrupo,
                        @fechaRegistroUtc = @fechaCierre, @totalMarcados = @totalMarcados OUTPUT;

                UPDATE dbo.TomaAsistencia
                SET estado = @idEstadoCerrada,
                    fechaCierreUtc = IIF(@fechaCierre < fechaAperturaUtc, fechaAperturaUtc, @fechaCierre),
                    totalAusentesMarcados = @totalMarcados,
                    idCorrelacionCierre = @idCorrelacionDefecto
                WHERE id = @idTomaDefecto;

                SET @p1 = CONVERT(NVARCHAR(20), @totalMarcados);
                SET @p2 = CONVERT(NVARCHAR(36), @idTomaDefecto);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_009', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeDescartado OUTPUT;
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_009', @p_param1 = @p2, @p_param2 = @p1,
                    @mensajeUsuarioResultado = @mensajeDescartado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            SELECT @totalFaltantes = COUNT(1) FROM dbo.uv_faltantes_toma f WHERE f.idToma = @idTomaDefecto;
            SELECT @fechaCierre = t.fechaCierreUtc FROM dbo.TomaAsistencia t WHERE t.id = @idTomaDefecto;

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
            ROLLBACK TRANSACTION sp_cerrar_toma;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idToma                  = IIF(@estadoResultado = 1, @idTomaDefecto, NULL),
        idSesion                = IIF(@estadoResultado = 1, @idSesion, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        fechaCierreUtc          = IIF(@estadoResultado = 1, @fechaCierre, NULL),
        totalAusentesMarcados   = IIF(@estadoResultado = 1, @totalMarcados, NULL),
        totalFaltantes          = IIF(@estadoResultado = 1, @totalFaltantes, NULL),
        yaEstabaCerrada         = IIF(@estadoResultado = 1, @yaEstabaCerrada, NULL);
END;
GO
-- ---- schema/stored-procedures/usp_internal_radicar_solicitud_revision.sql (texto de develop antes de la 49)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_radicar_solicitud_revision  (CULM-001 D.2, HU014/HU015; CONTRACT §3.2, DEC-044 (3))
--
-- Nucleo interno COMUN de la radicacion de un reclamo: NO se concede a ningun rol. Lo invocan
-- usp_radicar_solicitud_revision_asistencia_v2 (un solo soporte) y _v3 (de 0 a ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO) con
-- parametros OUTPUT, sin INSERT-EXEC (Msg 3915, DEC-036): no emite resultset; el llamador emite el suyo.
--
-- Orden (cada paso solo se evalua si los anteriores pasaron; un rechazo no escribe nada):
--   correlacion -> ejecutor -> RBAC ESTUDIANTE -> estudiante -> propiedad (H-01) -> sesion -> matricula
--   -> reejecucion idempotente por correlacion (algun soporte ya ATTACHED con la MISMA correlacion y del mismo dueno:
--      devuelve la solicitud y el total originales sin escribir)
--   -> PC (reclamo por toma, solo con @idToma; v2 y v3 no lo informan): toma de la sesion (TOM_001), SJC del estudiante en
--      esa toma con cabecera y detalle bloqueados (REV_026) y sin otra solicitud no retirada de la toma (REV_027)
--   -> plazo de excusas (usp_internal_validar_plazo_justificacion, D.1: REV_020 / REV_025; por sesion, igual para sus tomas)
--   -> categoria por codigo o por nombre (REV_021)
--   -> JSON valido (arreglo de GUID) y GUID distintos (GEN_002 / REV_024)
--   -> cantidad <= ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO (REV_023)
--   -> categoria con requiereSoporte y 0 soportes (REV_022)
--   -> cada soporte WITH (UPDLOCK, HOLDLOCK) en orden de id: dueno = ejecutor y estado ARCHIVO/ESTADO_BORRADOR
--      (inexistente, ajeno, ya vinculado u huerfano => ARC_001 identico, sin revelar el motivo)
--   -> INSERT de la solicitud (categoria y fecha LOCAL de radicacion) -> UPDATE de todos los soportes a ARCHIVO/ESTADO_ADJUNTO
--   -> verificacion por lectura de las N filas.
-- Los estados de soporte y de reclamo salen de parametros (TD-061), no de literales.
-- Ownership transaccional: transaccion propia si @@TRANCOUNT = 0, si no SAVE TRANSACTION (solo se revierte lo escrito).
-- En @estadoResultado = 1 con reejecucion idempotente no se escribe nada.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_radicar_solicitud_revision]
(
    @idEstudiante             UNIQUEIDENTIFIER,
    @idSesion                 UNIQUEIDENTIFIER,
    @categoria                NVARCHAR(50),
    @justificacion            NVARCHAR(MAX),
    @idsArchivoSoporte        NVARCHAR(MAX),
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER,
    @idSolicitudRevision      UNIQUEIDENTIFIER OUTPUT,
    @totalSoportes            INT              OUTPUT,
    @mensajeUsuarioResultado  NVARCHAR(4000)   OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000)   OUTPUT,
    @estadoResultado          BIT              OUTPUT,
    @idToma                   UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @justificacionDefecto     NVARCHAR(MAX)    = TRIM(@justificacion);
    DECLARE @categoriaDefecto         NVARCHAR(50)     = TRIM(@categoria);
    DECLARE @estadoAdjunto            VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));
    DECLARE @estadoBorrador           VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_BORRADOR') AS VARCHAR(10));
    DECLARE @codigoPendiente          NVARCHAR(5)      = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_PENDIENTE') AS NVARCHAR(5));
    DECLARE @codigoRetirado           NVARCHAR(5)      = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_RETIRADO') AS NVARCHAR(5));
    DECLARE @codigoSinJustaCausa      NVARCHAR(5)      = CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_SIN_JUSTA_CAUSA') AS NVARCHAR(5));
    DECLARE @numeroToma               INT;
    DECLARE @codigoRazonToma          NVARCHAR(5);
    DECLARE @solicitudTomaExistente   UNIQUEIDENTIFIER;
    DECLARE @textoNumeroToma          NVARCHAR(20);

    DECLARE @idAsistencia         UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @nuevaSolicitudId     UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSolicitud      NVARCHAR(50);
    DECLARE @idEstadoPendiente    UNIQUEIDENTIFIER;
    DECLARE @idCategoria          UNIQUEIDENTIFIER;
    DECLARE @nombreCategoria      NVARCHAR(50);
    DECLARE @requiereSoporte      BIT = 0;

    -- Lista de soportes: @ids en el orden recibido; @ordenados sin repetidos y por id (orden fijo de bloqueo)
    DECLARE @ids TABLE (orden INT IDENTITY(1, 1) NOT NULL, id UNIQUEIDENTIFIER NULL);
    DECLARE @ordenados TABLE (pos INT IDENTITY(1, 1) NOT NULL, id UNIQUEIDENTIFIER NOT NULL);
    DECLARE @jsonValido           BIT = 1;
    DECLARE @cantidad             INT = 0;
    DECLARE @distintos            INT = 0;
    DECLARE @maximo               INT;
    DECLARE @pos                  INT = 1;
    DECLARE @idArchivo            UNIQUEIDENTIFIER;
    DECLARE @propietarioSoporte   UNIQUEIDENTIFIER;
    DECLARE @estadoSoporte        VARCHAR(10);
    DECLARE @correlacionAdjuncion UNIQUEIDENTIFIER;
    DECLARE @solicitudSoporte     UNIQUEIDENTIFIER;
    DECLARE @esReintento          BIT = 0;
    DECLARE @fechaLimiteUtc       DATETIME2(7);
    DECLARE @zonaLocal            NVARCHAR(128);
    DECLARE @fechaLocalRadicacion DATE;
    DECLARE @filasActualizadas    INT;
    DECLARE @escrituraRealizada   BIT = 0;
    DECLARE @textoCantidad        NVARCHAR(20);
    DECLARE @textoMaximo          NVARCHAR(20);
    DECLARE @descartado           NVARCHAR(4000);

    DECLARE @conteoTransaccionesInicial INT;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    SET @idSolicitudRevision     = NULL;
    SET @totalSoportes           = 0;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado         = 1;

    BEGIN TRY
        -- PASO 1: Validacion de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (no nulo, no GUID vacio)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioEjecutorDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil RBAC ESTUDIANTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Existencia del estudiante
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno
                @idEstudiante = @idEstudianteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: El estudiante debe corresponder al ejecutor autenticado (H-01)
        IF @estadoResultado = 1
           AND NOT EXISTS (
                SELECT 1 FROM dbo.Estudiante e
                WHERE e.id = @idEstudianteDefecto AND e.usuario = @idUsuarioEjecutorDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARC_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Existencia de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 7: Matricula: el estudiante pertenece al grupo de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                @idEstudiante = @idEstudianteDefecto,
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 8: Lista de soportes (arreglo JSON de GUID). Solo se lee aqui; los errores se informan en su turno.
        IF @idsArchivoSoporte IS NOT NULL AND LEN(TRIM(@idsArchivoSoporte)) > 0
        BEGIN
            IF ISJSON(@idsArchivoSoporte) = 1 AND LEFT(LTRIM(@idsArchivoSoporte), 1) = N'['
            BEGIN
                INSERT @ids (id)
                SELECT TRY_CAST(j.[value] AS UNIQUEIDENTIFIER)
                FROM OPENJSON(@idsArchivoSoporte) j
                ORDER BY CAST(j.[key] AS INT);
                IF EXISTS (SELECT 1 FROM OPENJSON(@idsArchivoSoporte) j WHERE j.[type] <> 1)
                   OR EXISTS (SELECT 1 FROM @ids WHERE id IS NULL)
                    SET @jsonValido = 0;
            END
            ELSE
                SET @jsonValido = 0;
        END
        SELECT @cantidad = COUNT(*), @distintos = COUNT(DISTINCT id) FROM @ids;

        -- PASO 9: Transaccion propia (o savepoint si el llamador ya tiene una)
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
                SAVE TRANSACTION sp_culm001_d2_radicar;
                SET @savepointCreado = 1;
            END
        END

        -- PASO 10: Reejecucion idempotente por correlacion (antes del plazo: un reintento legitimo tras el vencimiento
        -- devuelve el exito original). Es un soporte ya vinculado con ESTA correlacion y del mismo dueno.
        IF @estadoResultado = 1 AND @jsonValido = 1 AND @cantidad > 0
        BEGIN
            SELECT TOP 1 @solicitudSoporte = a.solicitudRevisionAsistencia
            FROM dbo.ArchivoSoporte a
            INNER JOIN @ids i ON i.id = a.id
            WHERE a.estado = @estadoAdjunto
              AND a.idCorrelacionAdjuncion = @idCorrelacionDefecto
              AND a.usuarioPropietario = @idUsuarioEjecutorDefecto
            ORDER BY a.id;
            IF @solicitudSoporte IS NOT NULL
            BEGIN
                SET @esReintento = 1;
                SET @idSolicitudRevision = @solicitudSoporte;
            END
        END

        -- PASO 10b (PC, reclamo por toma): con @idToma la toma debe ser de la sesion (TOM_001), el estudiante debe tener SJC en
        -- ella (REV_026; cabecera y detalle bloqueados) y no debe existir otra solicitud no retirada de la misma toma (REV_027).
        IF @estadoResultado = 1 AND @esReintento = 0 AND @idToma IS NOT NULL
        BEGIN
            SELECT @numeroToma = t.numero FROM dbo.TomaAsistencia t WHERE t.id = @idToma AND t.sesion = @idSesionDefecto;
            IF @numeroToma IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'TOM_001', @p_param1 = @idToma,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @textoNumeroToma = CONVERT(NVARCHAR(20), @numeroToma);
                SELECT TOP 1 @idEstudianteGrupo = eg.id
                FROM dbo.Sesion s
                INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
                WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

                SELECT TOP 1 @idAsistencia = a.id, @codigoRazonToma = rc.codigo
                FROM dbo.Asistencia a WITH (UPDLOCK, HOLDLOCK)
                LEFT JOIN dbo.DetalleAsistencia d WITH (UPDLOCK, HOLDLOCK) ON d.asistencia = a.id AND d.toma = @idToma
                LEFT JOIN dbo.RazonCausa rc ON rc.id = d.razonCausa
                WHERE a.estudianteGrupo = @idEstudianteGrupo AND a.sesion = @idSesionDefecto;

                IF @codigoRazonToma IS NULL OR @codigoRazonToma <> @codigoSinJustaCausa
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'REV_026', @p_param1 = @textoNumeroToma, @p_param2 = @idSesionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
                ELSE
                BEGIN
                    SELECT TOP 1 @solicitudTomaExistente = sra.id
                    FROM dbo.SolicitudRevisionAsistencia sra WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.Estado e ON e.id = sra.estado
                    WHERE sra.asistencia = @idAsistencia AND sra.toma = @idToma AND e.codigo <> @codigoRetirado
                    ORDER BY sra.id;
                    IF @solicitudTomaExistente IS NOT NULL
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_027', @p_param1 = @textoNumeroToma, @p_param2 = @solicitudTomaExistente,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                        SET @estadoResultado = 0;
                    END
                END
            END
            IF @estadoResultado = 0
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 11: Plazo de excusas (D.1). Solo cuando NO es la reejecucion idempotente de una radicacion ya exitosa.
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            EXEC dbo.usp_internal_validar_plazo_justificacion
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @fechaLimiteUtc = @fechaLimiteUtc OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 12: Categoria por codigo o por nombre (el codigo gana si ambos coinciden con filas distintas)
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SELECT TOP 1 @idCategoria = c.id, @nombreCategoria = c.nombre, @requiereSoporte = c.requiereSoporte
            FROM dbo.CategoriaJustificacion c
            WHERE c.codigo = @categoriaDefecto OR c.nombre = @categoriaDefecto
            ORDER BY IIF(c.codigo = @categoriaDefecto, 0, 1), c.id;
            IF @idCategoria IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_021', @p_param1 = @categoriaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 13: JSON valido y soportes distintos
        IF @estadoResultado = 1 AND @esReintento = 0 AND @jsonValido = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idsArchivoSoporte',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        IF @estadoResultado = 1 AND @esReintento = 0 AND @cantidad <> @distintos
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_024',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 14: Cantidad maxima de soportes (ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO)
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SET @maximo = dbo.ufn_obtener_parametro_int(NULL, 'ARCHIVOS', 'MAXIMO_SOPORTES_POR_RECLAMO');
            IF @maximo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_002', @p_param1 = 'ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @cantidad > @maximo
            BEGIN
                SET @textoCantidad = CONVERT(NVARCHAR(20), @cantidad);
                SET @textoMaximo = CONVERT(NVARCHAR(20), @maximo);
                -- El mensaje de usuario usa solo {1} (maximo); el tecnico usa {1}=cantidad, {2}=maximo.
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_023', @p_param1 = @textoMaximo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @descartado OUTPUT;
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_023', @p_param1 = @textoCantidad, @p_param2 = @textoMaximo,
                    @mensajeUsuarioResultado = @descartado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 15: Soporte obligatorio segun la categoria (HU014)
        IF @estadoResultado = 1 AND @esReintento = 0 AND @requiereSoporte = 1 AND @cantidad = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_022', @p_param1 = @nombreCategoria,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 16: Bloqueo de cada soporte en orden de id (UPDLOCK, HOLDLOCK serializa radicaciones concurrentes con el mismo fileId)
        IF @estadoResultado = 1 AND @esReintento = 0 AND @cantidad > 0
        BEGIN
            INSERT @ordenados (id) SELECT DISTINCT id FROM @ids ORDER BY id;
            WHILE @pos <= (SELECT COUNT(*) FROM @ordenados) AND @estadoResultado = 1 AND @esReintento = 0
            BEGIN
                SELECT @idArchivo = o.id FROM @ordenados o WHERE o.pos = @pos;
                SET @propietarioSoporte = NULL; SET @estadoSoporte = NULL; SET @correlacionAdjuncion = NULL; SET @solicitudSoporte = NULL;
                SELECT @propietarioSoporte   = a.usuarioPropietario,
                       @estadoSoporte        = a.estado,
                       @correlacionAdjuncion = a.idCorrelacionAdjuncion,
                       @solicitudSoporte     = a.solicitudRevisionAsistencia
                FROM dbo.ArchivoSoporte a WITH (UPDLOCK, HOLDLOCK)
                WHERE a.id = @idArchivo;

                IF @propietarioSoporte IS NULL OR @propietarioSoporte <> @idUsuarioEjecutorDefecto
                BEGIN
                    SET @estadoResultado = 0;
                END
                ELSE IF @estadoSoporte = @estadoAdjunto AND @correlacionAdjuncion = @idCorrelacionDefecto
                BEGIN
                    -- Carrera con la misma solicitud (doble envio): la otra sesion ya confirmo; es una reejecucion
                    SET @esReintento = 1;
                    SET @idSolicitudRevision = @solicitudSoporte;
                END
                ELSE IF @estadoSoporte <> @estadoBorrador
                BEGIN
                    SET @estadoResultado = 0;
                END

                IF @estadoResultado = 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ARC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                END
                SET @pos += 1;
            END
        END

        -- PASO 17: Creacion de la solicitud y vinculo atomico de los N soportes
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SET @zonaLocal = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
            SET @fechaLocalRadicacion = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @zonaLocal AS DATE);

            SELECT TOP 1 @idEstudianteGrupo = eg.id
            FROM dbo.Sesion s
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
            WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

            SELECT TOP 1 @idAsistencia = id
            FROM dbo.Asistencia
            WHERE estudianteGrupo = @idEstudianteGrupo AND sesion = @idSesionDefecto;

            SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado WHERE codigo = @codigoPendiente ORDER BY id ASC;
            IF @idEstadoPendiente IS NULL
            BEGIN
                SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado ORDER BY id ASC;
            END

            SET @nombreSolicitud = CONCAT('REC-', UPPER(SUBSTRING(CAST(@nuevaSolicitudId AS VARCHAR(36)), 1, 8)));

            SET @escrituraRealizada = 1;
            IF @idAsistencia IS NULL
            BEGIN
                SET @idAsistencia = NEWID();
                INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
                VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
            END

            INSERT INTO dbo.SolicitudRevisionAsistencia (
                id, nombre, asistencia, fecha, estado,
                justificacionSolicitud, justificacionRespuesta, categoriaJustificacion, toma
            )
            VALUES (
                @nuevaSolicitudId,
                @nombreSolicitud,
                @idAsistencia,
                @fechaLocalRadicacion,
                @idEstadoPendiente,
                CASE WHEN @justificacionDefecto IS NOT NULL AND @justificacionDefecto <> '' THEN @justificacionDefecto ELSE 'Solicitud de revision de asistencia radicada por estudiante.' END,
                '',
                @idCategoria,
                @idToma
            );

            IF @cantidad > 0
            BEGIN
                UPDATE a
                SET estado = @estadoAdjunto,
                    solicitudRevisionAsistencia = @nuevaSolicitudId,
                    fechaAdjuncionUtc = SYSUTCDATETIME(),
                    fechaCambioEstadoUtc = SYSUTCDATETIME(),
                    idCorrelacionAdjuncion = @idCorrelacionDefecto
                FROM dbo.ArchivoSoporte a
                INNER JOIN @ordenados o ON o.id = a.id
                WHERE a.estado = @estadoBorrador
                  AND a.usuarioPropietario = @idUsuarioEjecutorDefecto;
                SET @filasActualizadas = @@ROWCOUNT;

                -- Postcondicion verificada por lectura (no solo @@ROWCOUNT): los N soportes quedaron vinculados a ESTA solicitud.
                IF @filasActualizadas <> @cantidad
                   OR (SELECT COUNT(*) FROM dbo.ArchivoSoporte a INNER JOIN @ordenados o ON o.id = a.id
                       WHERE a.estado = @estadoAdjunto AND a.solicitudRevisionAsistencia = @nuevaSolicitudId) <> @cantidad
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ARC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
            IF @estadoResultado = 1
                SET @idSolicitudRevision = @nuevaSolicitudId;
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @totalSoportes = COUNT(*) FROM dbo.uv_soporte_reclamo WHERE idSolicitud = @idSolicitudRevision;
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudRevisionAsistencia',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
        ELSE
        BEGIN
            SET @idSolicitudRevision = NULL;
            SET @totalSoportes = 0;
        END

        -- PASO 18: Finalizacion respetando ownership: commit solo si el resultado es exitoso
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            -- Solo se revierte lo escrito (un rechazo previo a las escrituras no deja nada que deshacer).
            IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @escrituraRealizada = 1
                ROLLBACK TRANSACTION sp_culm001_d2_radicar;
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_culm001_d2_radicar;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar la excepcion original al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @idSolicitudRevision = NULL;
        SET @totalSoportes = 0;
        SET @estadoResultado = 0;
    END CATCH
END;
GO
-- ---- schema/stored-procedures/usp_radicar_solicitud_revision_asistencia.sql (texto de develop antes de la 49)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @soporteNombre      NVARCHAR(250),
    @soporteUrl         NVARCHAR(500),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @categoriaDefecto         NVARCHAR(50)     = TRIM(@categoria);
    DECLARE @justificacionDefecto     NVARCHAR(MAX)    = TRIM(@justificacion);
    DECLARE @soporteNombreDefecto     NVARCHAR(250)    = TRIM(@soporteNombre);
    DECLARE @soporteUrlDefecto        NVARCHAR(500)    = TRIM(@soporteUrl);

    DECLARE @idAsistencia         UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @nuevaSolicitudId     UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSolicitud      NVARCHAR(50);
    DECLARE @idEstadoPendiente    UNIQUEIDENTIFIER;
    DECLARE @fechaLimiteUtc       DATETIME2(7);
    DECLARE @zonaLocal            NVARCHAR(128);

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    -- REC3 (auditoria BD 2026-10-28): cualquier error o cancelacion del cliente revierte la transaccion completa.
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validar existencia del estudiante
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno
                @idEstudiante = @idEstudianteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validar existencia de la sesión
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validar pertenencia del estudiante a la sesión
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                @idEstudiante = @idEstudianteDefecto,
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4.5 (CULM-001 D.1, HU026B): plazo de excusas (REV_020 vencido, REV_025 sin parametros); antes de toda escritura.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_internal_validar_plazo_justificacion
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @fechaLimiteUtc = @fechaLimiteUtc OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Radicación atómica transaccional de la solicitud
        IF @estadoResultado = 1
        BEGIN
            SET @zonaLocal = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
            SELECT TOP 1 @idEstudianteGrupo = eg.id
            FROM dbo.Sesion s
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
            WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

            SELECT TOP 1 @idAsistencia = id
            FROM dbo.Asistencia
            WHERE estudianteGrupo = @idEstudianteGrupo AND sesion = @idSesionDefecto;

            SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado WHERE codigo IN ('P', 'PEND') ORDER BY id ASC;
            IF @idEstadoPendiente IS NULL
            BEGIN
                SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado ORDER BY id ASC;
            END

            SET @nombreSolicitud = CONCAT('REC-', UPPER(SUBSTRING(CAST(@nuevaSolicitudId AS VARCHAR(36)), 1, 8)));

            BEGIN TRANSACTION;

            IF @idAsistencia IS NULL
            BEGIN
                SET @idAsistencia = NEWID();
                INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
                VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
            END

            INSERT INTO dbo.SolicitudRevisionAsistencia (
                id, nombre, asistencia, fecha, estado,
                justificacionSolicitud, justificacionRespuesta
            )
            VALUES (
                @nuevaSolicitudId,
                @nombreSolicitud,
                @idAsistencia,
                CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @zonaLocal AS DATE),
                @idEstadoPendiente,
                CASE WHEN @justificacionDefecto IS NOT NULL AND @justificacionDefecto <> '' THEN @justificacionDefecto ELSE 'Solicitud de revisión de asistencia radicada por estudiante.' END,
                ''
            );

            COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudRevisionAsistencia',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- REC3: solo se revierte si hay una transaccion viva (XACT_STATE <> 0); evita un segundo error en el CATCH.
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
-- ---- schema/stored-procedures/usp_resolver_solicitud_revision_asistencia.sql (texto de develop antes de la 49)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SES-04: resolucion del reclamo de inasistencia por el docente titular (flujo formal posterior al cierre).
--   * @accion: exactamente APROBADA o RECHAZADA (TRIM + UPPER). Cualquier otro valor => REV_001, sin escrituras.
--   * APROBADA: la asistencia queda JUSTIFICADA = RazonCausa EX con asistio = 0 (no es presencia AN). La solicitud pasa
--     a A. Si la asistencia ya era EX solo se resuelve la solicitud. Una asistencia AN no es justificable => REV_003.
--   * RECHAZADA: la solicitud pasa a R y DetalleAsistencia NO se modifica.
--   * Concurrencia: la solicitud se lee con UPDLOCK/HOLDLOCK dentro de la transaccion; dos resoluciones simultaneas se
--     serializan. Reintento con la misma decision ya aplicada => exito idempotente sin nuevas escrituras ni auditoria;
--     decision contradictoria sobre una solicitud ya resuelta => REV_002.
--   * Solicitud inexistente => REV_005; docente no titular => VAL_007 (contrato previo); sin detalle de asistencia
--     => REV_004 (no se simula una justificacion ni se crean filas).
--   * Auditoria oficial (dbo.AuditoriaEvento) en la MISMA transaccion: actor, accion, estado previo y nuevo de la
--     solicitud y del detalle, respuesta y correlacion.
--   * No usa la ventana de registro ordinario (SES-01): la rectificacion por reclamo es valida despues del cierre.
--   * Resultset canonico de 4 columnas sin cambio.
-- PC (puntos de control, reclamo por toma): parametro opcional al final @codigoResultadoAprobacion (NULL = EX):
--   * valores validos ASISTENCIA/CODIGO_RAZON_PRESENTE (AN, "si estuvo presente") y ASISTENCIA/CODIGO_RAZON_EXCUSA (EX,
--     "ausencia justificada"); cualquier otro => REV_028, sin escrituras.
--   * Solicitud CON toma: se bloquea y modifica solo el detalle (asistencia, toma). APROBADA + AN => AN con asistio = 1;
--     APROBADA + EX => EX con asistio = 0, solo en esa toma; RECHAZADA no toca el detalle. Sin detalle REV_004; detalle AN REV_003.
--   * Solicitud SIN toma (reclamo de la sesion, legado): APROBADA + AN => REV_029; EX conserva SES-04 (todos los SJC pasan a EX).
--   * La aprobacion guarda razonCausaResolucion. Reintento con la misma accion y el mismo resultado => exito sin escrituras;
--     resultado distinto sobre una solicitud ya aprobada (sin resultado guardado cuenta como EX) => REV_002.
--   * La auditoria agrega idToma y resultadoAprobacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_solicitud_revision_asistencia]
(
    @idSolicitud        UNIQUEIDENTIFIER,
    @idDocente          UNIQUEIDENTIFIER,
    @accion             NVARCHAR(20),
    @respuestaDocente   NVARCHAR(MAX),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL,
    @codigoResultadoAprobacion NVARCHAR(5) = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto         UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @accionDefecto            NVARCHAR(20)     = UPPER(TRIM(@accion));
    DECLARE @respuestaDefecto         NVARCHAR(MAX)    = TRIM(@respuestaDocente);
    -- DEC-073: limites de la respuesta del docente (RECLAMO/RESPUESTA_*); al rechazar es obligatoria.
    DECLARE @respuestaRechazoMinimo   INT = dbo.ufn_obtener_parametro_int(NULL, 'RECLAMO', 'RESPUESTA_RECHAZO_LONGITUD_MINIMA');
    DECLARE @respuestaMaximo          INT = dbo.ufn_obtener_parametro_int(NULL, 'RECLAMO', 'RESPUESTA_LONGITUD_MAXIMA');
    DECLARE @respuestaLongitud        INT = ISNULL(LEN(TRIM(@respuestaDocente)), 0);

    DECLARE @docenteTitularGrupo   UNIQUEIDENTIFIER;
    DECLARE @idAsistencia          UNIQUEIDENTIFIER;
    DECLARE @idDetalle             UNIQUEIDENTIFIER;
    DECLARE @asistioAnterior       BIT;
    DECLARE @codigoCausaAnterior   NVARCHAR(5);
    DECLARE @codigoEstadoActual    CHAR(1);
    DECLARE @codigoEstadoNuevo     CHAR(1);
    DECLARE @idEstadoNuevo         UNIQUEIDENTIFIER;
    DECLARE @idRazonJustificada    UNIQUEIDENTIFIER;
    DECLARE @modificaDetalle       BIT = 0;
    DECLARE @codigoPresente        NVARCHAR(5) = CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_PRESENTE') AS NVARCHAR(5));
    DECLARE @codigoExcusa          NVARCHAR(5) = CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_EXCUSA') AS NVARCHAR(5));
    DECLARE @codigoResultado       NVARCHAR(5);
    DECLARE @codigoResultadoPrevio NVARCHAR(5);
    DECLARE @idTomaSolicitud       UNIQUEIDENTIFIER;
    DECLARE @idRazonResultado      UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    -- REC3 (auditoria BD 2026-10-28): cualquier error o cancelacion del cliente revierte la transaccion completa.
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: El ejecutor es obligatorio y debe tener perfil DOCENTE
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.6 (SES-04): solo las acciones contractuales; ningun otro valor se interpreta como rechazo
        IF @estadoResultado = 1 AND (@accionDefecto IS NULL OR @accionDefecto NOT IN (N'APROBADA', N'RECHAZADA'))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_001',
                @p_param1 = @accion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 1.7 (PC): resultado de la aprobacion (NULL = EX); solo AN o EX
        SET @codigoResultado = UPPER(TRIM(ISNULL(@codigoResultadoAprobacion, @codigoExcusa)));
        IF @estadoResultado = 1 AND (@codigoResultado IS NULL OR @codigoResultado NOT IN (@codigoPresente, @codigoExcusa))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_028',
                @p_param1 = @codigoResultadoAprobacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 1.8 (DEC-073): la respuesta (sin espacios laterales) no supera RESPUESTA_LONGITUD_MAXIMA y, al rechazar, tiene
        --          al menos RESPUESTA_RECHAZO_LONGITUD_MINIMA caracteres. Limites ausentes: fail-closed (se rechaza).
        IF @estadoResultado = 1
           AND (@respuestaRechazoMinimo IS NULL OR @respuestaMaximo IS NULL
                OR @respuestaLongitud > @respuestaMaximo
                OR (@accionDefecto = N'RECHAZADA' AND @respuestaLongitud < @respuestaRechazoMinimo))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ERR_RESPUESTA_RECLAMO_LONGITUD_INVALIDA',
                @p_param1 = @respuestaRechazoMinimo,
                @p_param2 = @respuestaMaximo,
                @p_param3 = @respuestaMaximo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: Resolución atómica. La solicitud, su estado y su detalle se leen bajo bloqueo dentro de la
        --         transacción; los rechazos de negocio confirman una transacción sin escrituras (así no hay ROLLBACK
        --         dentro de un INSERT ... EXEC del llamador).
        IF @estadoResultado = 1
        BEGIN
            BEGIN TRANSACTION;

            SELECT TOP 1
                @docenteTitularGrupo = g.docente,
                @idAsistencia = sra.asistencia,
                @codigoEstadoActual = e.codigo,
                @idTomaSolicitud = sra.toma,
                @codigoResultadoPrevio = rcr.codigo
            FROM dbo.SolicitudRevisionAsistencia sra WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Estado e ON e.id = sra.estado
            LEFT JOIN dbo.RazonCausa rcr ON rcr.id = sra.razonCausaResolucion
            INNER JOIN dbo.Asistencia ast ON sra.asistencia = ast.id
            INNER JOIN dbo.Sesion s ON ast.sesion = s.id
            INNER JOIN dbo.Grupo g ON s.grupo = g.id
            WHERE sra.id = @idSolicitudDefecto;

            -- 2.1: solicitud existente con relacion solicitud -> asistencia -> sesion -> grupo
            IF @docenteTitularGrupo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_005',
                    @p_param1 = @idSolicitudDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            -- 2.2: titularidad del docente sobre el grupo de la sesion
            ELSE IF @docenteTitularGrupo <> @idDocenteDefecto
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_007',
                    @p_param1 = 'DocenteAmbitoRevision',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            -- 2.2b (PC): "si estuvo presente" solo aplica a un reclamo de una toma
            ELSE IF @accionDefecto = N'APROBADA' AND @idTomaSolicitud IS NULL AND @codigoResultado = @codigoPresente
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_029',
                    @p_param1 = @idSolicitudDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1
            BEGIN
                SET @codigoEstadoNuevo = CASE WHEN @accionDefecto = N'APROBADA' THEN 'A' ELSE 'R' END;

                -- 2.3: solo una solicitud pendiente se resuelve. La misma decision ya aplicada es un reintento
                --      idempotente (sin escrituras); una decision distinta es un conflicto. PC: una aprobacion con otro
                --      resultado tambien es un conflicto (sin resultado guardado, la aprobacion anterior fue EX).
                IF @codigoEstadoActual <> 'P'
                BEGIN
                    IF @codigoEstadoActual <> @codigoEstadoNuevo
                       OR (@codigoEstadoNuevo = 'A' AND ISNULL(@codigoResultadoPrevio, @codigoExcusa) <> @codigoResultado)
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_002',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END
                END
                ELSE
                BEGIN
                    -- 2.4: detalle de la asistencia (bloqueado). Sin detalle no se simula una justificacion.
                    -- CULM-001 B.2 (CONTRACT §2.9): con varias tomas se bloquean todos los detalles de la asistencia y el
                    -- representativo es el de estado consolidado (SJC antes que EX antes que AN): con una toma, el mismo de antes.
                    SELECT TOP 1
                        @idDetalle = d.id,
                        @asistioAnterior = d.asistio,
                        @codigoCausaAnterior = rc.codigo
                    -- PC: con toma, solo el detalle de esa toma.
                    FROM dbo.DetalleAsistencia d WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.RazonCausa rc ON rc.id = d.razonCausa
                    WHERE d.asistencia = @idAsistencia
                      AND (@idTomaSolicitud IS NULL OR d.toma = @idTomaSolicitud)
                    ORDER BY CASE rc.codigo WHEN N'SJC' THEN 0 WHEN N'EX' THEN 1 ELSE 2 END, d.id;

                    IF @idDetalle IS NULL
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_004',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END
                    -- 2.5: solo una ausencia es justificable; una presencia (AN / asistio = 1) no se aprueba
                    ELSE IF @codigoEstadoNuevo = 'A' AND (@asistioAnterior = 1 OR @codigoCausaAnterior = N'AN')
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_003',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END

                    -- 2.6: catalogos cerrados (Estado A/R, RazonCausa EX); nunca se elige otra fila
                    IF @estadoResultado = 1
                    BEGIN
                        SELECT @idEstadoNuevo = id FROM dbo.Estado WHERE codigo = @codigoEstadoNuevo;
                        SELECT @idRazonJustificada = id FROM dbo.RazonCausa WHERE codigo = @codigoResultado;
                        IF @idEstadoNuevo IS NULL OR (@codigoEstadoNuevo = 'A' AND @idRazonJustificada IS NULL)
                            THROW 52401, 'SES04_CATALOGO_INCONSISTENTE: falta Estado A/R o RazonCausa EX.', 1;

                        SET @modificaDetalle = CASE WHEN @codigoEstadoNuevo = 'A' AND @codigoCausaAnterior <> @codigoResultado THEN 1 ELSE 0 END;

                        -- 2.7: la solicitud queda resuelta con la respuesta del docente (PC: y el resultado si se aprueba)
                        UPDATE dbo.SolicitudRevisionAsistencia
                        SET estado = @idEstadoNuevo,
                            justificacionRespuesta = CASE WHEN @respuestaDefecto IS NOT NULL THEN @respuestaDefecto ELSE '' END,
                            razonCausaResolucion = CASE WHEN @codigoEstadoNuevo = 'A' THEN @idRazonJustificada ELSE razonCausaResolucion END
                        WHERE id = @idSolicitudDefecto;

                        -- 2.8: aprobacion => resultado (EX con asistio = 0, o AN con asistio = 1 si el reclamo es de una toma).
                        --      Sin toma (legado) todos los SJC pasan a EX; con toma solo su detalle. El rechazo no toca DetalleAsistencia.
                        IF @modificaDetalle = 1
                        BEGIN
                            UPDATE d
                            SET razonCausa = @idRazonJustificada,
                                asistio = IIF(@codigoResultado = @codigoPresente, 1, 0)
                            FROM dbo.DetalleAsistencia d
                            INNER JOIN dbo.RazonCausa rc ON rc.id = d.razonCausa
                            WHERE d.asistencia = @idAsistencia
                              AND (d.id = @idDetalle OR (@idTomaSolicitud IS NULL AND rc.codigo = N'SJC'));
                        END

                        -- 2.9: auditoria oficial con estado previo y nuevo, en la misma transaccion
                        INSERT INTO dbo.AuditoriaEvento (
                            id, occurredAt, actorId, actorType, action,
                            resourceType, resourceId, result, correlationId,
                            httpMethod, path, httpStatus, metadata
                        ) VALUES (
                            NEWID(),
                            SYSDATETIMEOFFSET(),
                            CAST(@idUsuarioEjecutorDefecto AS NVARCHAR(120)),
                            'USER',
                            'RESOLVER_SOLICITUD_REVISION_ASISTENCIA',
                            'SolicitudRevisionAsistencia',
                            CAST(@idSolicitudDefecto AS NVARCHAR(120)),
                            'SUCCESS',
                            @idCorrelacionDefecto,
                            'PATCH',
                            N'/api/v1/docente/reclamos/{id}',
                            200,
                            (SELECT accion = @accionDefecto,
                                    estadoSolicitudAnterior = @codigoEstadoActual,
                                    estadoSolicitudNuevo = @codigoEstadoNuevo,
                                    idAsistencia = CAST(@idAsistencia AS NVARCHAR(36)),
                                    idDetalleAsistencia = CAST(@idDetalle AS NVARCHAR(36)),
                                    razonCausaAnterior = @codigoCausaAnterior,
                                    asistioAnterior = @asistioAnterior,
                                    razonCausaNueva = CASE WHEN @modificaDetalle = 1 THEN @codigoResultado ELSE @codigoCausaAnterior END,
                                    asistioNuevo = CASE WHEN @modificaDetalle = 1 THEN CAST(IIF(@codigoResultado = @codigoPresente, 1, 0) AS BIT) ELSE @asistioAnterior END,
                                    respuestaDocente = @respuestaDefecto,
                                    idToma = CAST(@idTomaSolicitud AS NVARCHAR(36)),
                                    resultadoAprobacion = CASE WHEN @codigoEstadoNuevo = 'A' THEN @codigoResultado END
                             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
                        );
                    END
                END
            END

            COMMIT TRANSACTION;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'SolicitudRevisionAsistencia',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
        END

    END TRY
    BEGIN CATCH
        -- REC3: solo se revierte si hay una transaccion viva (XACT_STATE <> 0); evita un segundo error en el CATCH.
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
-- ---- schema/stored-procedures/usp_retirar_solicitud_revision_asistencia.sql (texto de develop antes de la 49)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_retirar_solicitud_revision_asistencia (CULM-001 A.2-7; F-EST-003; CONTRACT §8.2.3 A2-DB-3)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con resultset canonico de 4 columnas.
-- El ESTUDIANTE retira su propio reclamo (solicitud de revision de asistencia) mientras esta pendiente:
--   * RBAC ESTUDIANTE (SEC_001). Ambito dentro del SP: el reclamo debe ser del ejecutor
--     (asistencia -> EstudianteGrupo -> Estudiante.usuario); inexistente o ajeno => REV_006 (no revela que existe).
--   * Bajo UPDLOCK, HOLDLOCK su estado debe ser el codigo de RECLAMO/ESTADO_PENDIENTE; si no (ya resuelto o retirado),
--     REV_007. Pasa al estado con el codigo de RECLAMO/ESTADO_RETIRADO (X "retirada", A2-C4). Exito REV_008.
--   * El soporte (ArchivoSoporte) se conserva (almacenamiento WORM y auditoria). Sin notificacion.
-- SET XACT_ABORT ON; transaccion propia o savepoint; un rechazo de negocio no escribe ni hace ROLLBACK.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_retirar_solicitud_revision_asistencia]
(
    @idSolicitudRevision UNIQUEIDENTIFIER,
    @idCorrelacion       UNIQUEIDENTIFIER,
    @idUsuarioEjecutor   UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoPendiente      NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_PENDIENTE') AS NVARCHAR(10));
    DECLARE @codigoRetirado       NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_RETIRADO') AS NVARCHAR(10));
    DECLARE @idEstadoRetirado     UNIQUEIDENTIFIER;
    DECLARE @idSolicitudBloqueada UNIQUEIDENTIFIER;
    DECLARE @codigoEstadoActual   NVARCHAR(10);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @codigoRechazo           VARCHAR(20) = NULL;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorios
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

        -- PASO 2: RBAC ESTUDIANTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutor,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: estados por catalogo (parametros RECLAMO/*)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idEstadoRetirado = e.id FROM dbo.Estado e WHERE e.codigo = @codigoRetirado;
            IF @idEstadoRetirado IS NULL OR @codigoPendiente IS NULL OR @codigoPendiente = N''
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'Estado de reclamo (RECLAMO/ESTADO_*)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: transaccion, propiedad y estado bajo bloqueo
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
                SAVE TRANSACTION sp_retirar_solicitud_revision;
                SET @savepointCreado = 1;
            END

            SELECT @idSolicitudBloqueada = r.id, @codigoEstadoActual = est.codigo
            FROM dbo.SolicitudRevisionAsistencia r WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Estado est ON est.id = r.estado
            INNER JOIN dbo.Asistencia a ON a.id = r.asistencia
            INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
            INNER JOIN dbo.Estudiante e ON e.id = eg.estudiante
            WHERE r.id = @idSolicitudRevision
              AND e.usuario = @idUsuarioEjecutor;

            IF @idSolicitudBloqueada IS NULL
                SET @codigoRechazo = 'REV_006';
            ELSE IF @codigoEstadoActual <> @codigoPendiente
                SET @codigoRechazo = 'REV_007';
            ELSE
            BEGIN
                UPDATE dbo.SolicitudRevisionAsistencia
                SET estado = @idEstadoRetirado
                WHERE id = @idSolicitudBloqueada;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_008', @p_param1 = @idSolicitudBloqueada,
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
            END
        END

        -- PASO 5: mensaje de rechazo por catalogo (sin escrituras)
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @idSolicitudRevision,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_retirar_solicitud_revision;

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
        estadoResultado         = @estadoResultado;
END;
GO
-- ---- schema/stored-procedures/usp_ejecutar_cierre_masivo_periodo.sql (texto de develop antes de la 49)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_ejecutar_cierre_masivo_periodo (HU174; CULM-001 C.1, CONTRACT §2.6, SUPUESTO-C-10, DEC-041 C-10, DEC-043, N-1, N-4)
--
-- Cierre masivo del periodo. Ya NO escribe CI por conteo de faltas: CI solo nace de una revision de cancelacion aprobada.
--   Motor activo (ALERTA_INASISTENCIA/HABILITADA = true y los dos umbrales validos): el SP NO ejecuta el motor (lo hace antes el
--   caso de uso del backend, N-1) y, dentro de su transaccion y con bloqueos, se bloquea con RCN_012 si hay revisiones que esperan
--   al docente o al resolutor, o perdidas por horas sin revision, de matriculas activas del periodo; sin crear revisiones.
--   Si no (o con el motor apagado / umbrales invalidos, que no bloquean y quedan auditados): matriculas A -> F (parametro
--   MATRICULA/ESTADO_FINALIZADA), contadores de Grupo (cantidadEstudiantesCancelaronAutomaticamente = matriculas en CI al cierre,
--   SUPUESTO-C-20) y AuditoriaEvento CIERRE_MASIVO_PERIODO con motorHabilitado, umbralesValidos, perdidasSinRevision y
--   revisionesPendientes. Devuelve SIEMPRE una sola fila (tupla canonica), tambien con INSERT ... EXEC.
-- FIX-CIERRE-001: el periodo se resuelve solo por @codigoPeriodo (nombre o codigo). Sin codigo -> GEN_002; codigo que no existe -> PER_001;
-- en ambos casos no se cierra nada (antes se cerraba el periodo mas reciente).
-- FIX-CIERRE-002: solo se cierra un periodo que ya termino (uv_periodo_academico.estado = CERRADO: fecha local institucional
-- estrictamente posterior a fechaFin; el dia de fechaFin aun cuenta como vigente). Un periodo vigente o en planeacion responde PER_007 con su
-- fecha de fin, antes de abrir la transaccion y sin cerrar ni auditar nada. El cierre sigue siendo manual (administrador).
-- Bloqueos (orden de §2.0): RevisionCancelacion -> EstudianteGrupo (UPDLOCK, HOLDLOCK) -> lectura de uv_resumen_* sin pistas ->
-- Grupo. Transaccion propia o savepoint si hay una externa.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_ejecutar_cierre_masivo_periodo]
(
    @codigoPeriodo          NVARCHAR(50),
    @idActor                NVARCHAR(100),
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoPeriodoDefecto     NVARCHAR(50)     = TRIM(@codigoPeriodo);
    DECLARE @idActorDefecto           NVARCHAR(100)    = TRIM(@idActor);

    DECLARE @idPeriodoTarget               UNIQUEIDENTIFIER;
    DECLARE @estadoPeriodo                 VARCHAR(20);
    DECLARE @estadoPeriodoTerminado        VARCHAR(20) = 'CERRADO'; -- mismo valor que calcula uv_periodo_academico para un periodo ya terminado
    DECLARE @fechaFinPeriodo               DATE;
    DECLARE @idEstadoActivo                UNIQUEIDENTIFIER;
    DECLARE @idEstadoFinalizado            UNIQUEIDENTIFIER;
    DECLARE @idEstadoCanceladoInasistencia UNIQUEIDENTIFIER;
    DECLARE @codigoActiva                  NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @codigoFinalizada              NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_FINALIZADA') AS NVARCHAR(10));
    DECLARE @codigoCancelada               NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_CANCELADA_INASISTENCIA') AS NVARCHAR(10));
    DECLARE @motorHabilitado               BIT = IIF(LOWER(TRIM(CAST(dbo.ufn_obtener_parametro('ALERTA_INASISTENCIA', 'HABILITADA') AS NVARCHAR(20)))) = N'true', 1, 0);
    DECLARE @umbralesValidos               BIT = 1;
    DECLARE @umbralPerdida                 DECIMAL(5,2);
    DECLARE @motorActivo                   BIT = 0;
    DECLARE @totalEstudiantes              INT = 0;
    DECLARE @totalFinalizados              INT = 0;
    DECLARE @totalCancelados               INT = 0;
    DECLARE @revisionesPendientes          INT = 0;
    DECLARE @perdidasSinRevision           INT = 0;
    DECLARE @transaccionPropia             BIT = 0;
    DECLARE @savepointCreado               BIT = 0;
    DECLARE @estadoTransaccionCatch        INT;
    DECLARE @bloqueado                     BIT = 0;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500), @p3 NVARCHAR(500);
    DECLARE @mensajeDescartado NVARCHAR(4000);

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    -- REC3 (auditoria BD 2026-10-28): cualquier error o cancelacion del cliente revierte la transaccion completa.
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Buscar período académico objetivo consultando uv_periodo_academico
        -- FIX-CIERRE-001: el periodo se resuelve SOLO por el codigo indicado (nombre o codigo numerico). Sin codigo (nulo o vacio) o con un
        -- codigo que no coincide con ningun periodo NO se cierra nada: antes caia al periodo mas reciente y lo cerraba (accion destructiva).
        IF @estadoResultado = 1
        BEGIN
            IF @codigoPeriodoDefecto IS NULL OR @codigoPeriodoDefecto = ''
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_002',
                    @p_param1 = 'codigoPeriodo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id, @estadoPeriodo = estado, @fechaFinPeriodo = fechaFin
                FROM [dbo].[uv_periodo_academico]
                WHERE nombre = @codigoPeriodoDefecto
                   OR CAST(codigo AS NVARCHAR(50)) = @codigoPeriodoDefecto
                ORDER BY anio DESC;

                IF @idPeriodoTarget IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'PER_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Periodo indicado: ', @codigoPeriodoDefecto, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
                ELSE IF @estadoPeriodo IS NULL OR @estadoPeriodo <> @estadoPeriodoTerminado
                BEGIN
                    -- FIX-CIERRE-002: el periodo aun no termino (vigente o en planeacion): no se cierra ni se audita nada
                    SELECT @p1 = CONVERT(NVARCHAR(10), @fechaFinPeriodo, 103);
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'PER_007',
                        @p_param1 = @p1,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Periodo: ', CONVERT(NVARCHAR(50), @idPeriodoTarget), ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END

        -- PASO 3: Ejecución transaccional de Cierre Masivo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoActivo = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = @codigoActiva ORDER BY id ASC;
            SELECT TOP 1 @idEstadoFinalizado = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = @codigoFinalizada ORDER BY id ASC;
            SELECT TOP 1 @idEstadoCanceladoInasistencia = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = @codigoCancelada ORDER BY id ASC;

            -- Umbrales: el motor solo bloquea con los dos validos (O-3)
            IF EXISTS (SELECT 1 FROM dbo.TipoAlertaInasistencia t WHERE dbo.ufn_umbral_alerta_inasistencia(t.id) IS NULL)
                SET @umbralesValidos = 0;
            SELECT TOP 1 @umbralPerdida = dbo.ufn_umbral_alerta_inasistencia(t.id) FROM dbo.TipoAlertaInasistencia t WHERE t.creaRevisionCancelacion = 1;
            SET @motorActivo = IIF(@motorHabilitado = 1 AND @umbralesValidos = 1 AND @umbralPerdida IS NOT NULL, 1, 0);

            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cierre_masivo;
                SET @savepointCreado = 1;
            END

            -- (1) RevisionCancelacion y (2) EstudianteGrupo del periodo, en el orden de bloqueos de §2.0 (N-4)
            SELECT @revisionesPendientes = COUNT(1)
            FROM dbo.RevisionCancelacion r WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo
            INNER JOIN dbo.Grupo g ON g.id = eg.grupo AND g.periodoAcademico = @idPeriodoTarget
            INNER JOIN dbo.EstadoRevisionCancelacion es ON es.id = r.estado AND (es.requiereAccionDocente = 1 OR es.requiereAccionResolutor = 1)
            WHERE eg.estado = @idEstadoActivo;

            SELECT @totalEstudiantes = COUNT(eg.id)
            FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            WHERE g.periodoAcademico = @idPeriodoTarget;

            -- (3) Perdidas por horas sin revision (lectura sin pistas: bloqueos compartidos que no se retienen)
            IF @umbralPerdida IS NOT NULL
                SELECT @perdidasSinRevision = COUNT(1)
                FROM dbo.uv_resumen_asistencia_estudiante_grupo rs
                WHERE rs.idPeriodoAcademico = @idPeriodoTarget AND rs.codigoEstadoEstudiante = @codigoActiva
                  AND rs.porcentajeInasistencia >= @umbralPerdida
                  AND NOT EXISTS (SELECT 1 FROM dbo.RevisionCancelacion r WHERE r.estudianteGrupo = rs.idEstudianteGrupo);

            IF @motorActivo = 1 AND (@revisionesPendientes + @perdidasSinRevision) > 0
            BEGIN
                SET @bloqueado = 1;
                SELECT @p1 = CONVERT(NVARCHAR(20), @revisionesPendientes + @perdidasSinRevision);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCN_012', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeDescartado OUTPUT;
                SELECT @p1 = CONVERT(NVARCHAR(50), @idPeriodoTarget), @p2 = CONVERT(NVARCHAR(20), @revisionesPendientes), @p3 = CONVERT(NVARCHAR(20), @perdidasSinRevision);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCN_012', @p_param1 = @p1, @p_param2 = @p2, @p_param3 = @p3,
                    @mensajeUsuarioResultado = @mensajeDescartado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
                -- No se escribio nada (solo bloqueos y lecturas): se libera con COMMIT y no con ROLLBACK, porque este SP debe poder
                -- ejecutarse dentro de INSERT ... EXEC (C-DB-47) y SQL Server prohibe ROLLBACK en ese contexto.
                IF @transaccionPropia = 1
                BEGIN
                    IF XACT_STATE() = 1 COMMIT TRANSACTION;
                    SET @transaccionPropia = 0;
                END
            END
            ELSE
            BEGIN
                -- (4) A -> F (incluye MANTENIDA/RECHAZADA y, con el motor apagado, cualquier perdida)
                UPDATE eg
                SET eg.estado = @idEstadoFinalizado
                FROM dbo.EstudianteGrupo eg
                INNER JOIN dbo.Grupo g ON eg.grupo = g.id
                WHERE g.periodoAcademico = @idPeriodoTarget
                  AND eg.estado = @idEstadoActivo;
                SET @totalFinalizados = @@ROWCOUNT;

                -- Contadores de Grupo ("cancelaron automaticamente" = matriculas en CI al cierre, SUPUESTO-C-20)
                UPDATE g
                SET
                    cantidadEstudiantesFinalizaron = (
                        SELECT COUNT(1) FROM dbo.EstudianteGrupo eg
                        WHERE eg.grupo = g.id AND eg.estado = @idEstadoFinalizado
                    ),
                    cantidadEstudiantesCancelaronAutomaticamente = (
                        SELECT COUNT(1) FROM dbo.EstudianteGrupo eg
                        WHERE eg.grupo = g.id AND eg.estado = @idEstadoCanceladoInasistencia
                    )
                FROM dbo.Grupo g
                WHERE g.periodoAcademico = @idPeriodoTarget;

                SELECT @totalCancelados = COUNT(1)
                FROM dbo.EstudianteGrupo eg INNER JOIN dbo.Grupo g ON g.id = eg.grupo
                WHERE g.periodoAcademico = @idPeriodoTarget AND eg.estado = @idEstadoCanceladoInasistencia;

                -- (5) Auditoría de evento
                INSERT INTO dbo.AuditoriaEvento (
                    id, occurredAt, actorId, actorType, action,
                    resourceType, resourceId, result, correlationId,
                    httpMethod, path, httpStatus, metadata
                ) VALUES (
                    NEWID(),
                    SYSDATETIMEOFFSET(),
                    CASE WHEN @idActorDefecto IS NOT NULL AND @idActorDefecto <> '' THEN @idActorDefecto ELSE 'ADMIN_SISTEMA' END,
                    CASE WHEN @idActorDefecto IS NOT NULL AND @idActorDefecto <> '' THEN 'USER' ELSE 'SYSTEM' END,
                    'CIERRE_MASIVO_PERIODO',
                    'PeriodoAcademico',
                    CAST(@idPeriodoTarget AS NVARCHAR(50)),
                    'SUCCESS',
                    @idCorrelacionDefecto,
                    'POST',
                    '/api/v1/admin/cierre-masivo',
                    200,
                    (SELECT procesados = @totalEstudiantes, finalizados = @totalFinalizados, canceladosPorInasistencia = @totalCancelados,
                            motorHabilitado = @motorHabilitado, umbralesValidos = @umbralesValidos,
                            perdidasSinRevision = @perdidasSinRevision, revisionesPendientes = @revisionesPendientes
                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
                );

                IF @transaccionPropia = 1
                BEGIN
                    IF XACT_STATE() = 1 COMMIT TRANSACTION; ELSE IF XACT_STATE() = -1 ROLLBACK TRANSACTION;
                    SET @transaccionPropia = 0;
                END

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'CierreMasivoPeriodo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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
            ROLLBACK TRANSACTION sp_cierre_masivo;

        -- Con una transaccion externa condenada (XACT_STATE = -1) solo el llamador puede revertirla
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados (una sola fila, N-1)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
IF OBJECT_ID(N'dbo.usp_validar_periodo_abierto_sesion_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_periodo_abierto_sesion_interno];
GO
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo IN ('PER_008', 'PER_009');
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo IN ('PER_008', 'PER_009');
GO
IF COL_LENGTH('dbo.PeriodoAcademico', 'fechaCierreUtc') IS NOT NULL
    ALTER TABLE [dbo].[PeriodoAcademico] DROP COLUMN [fechaCierreUtc];
GO
PRINT 'MIGRACION 49 DOWN OK';
GO
