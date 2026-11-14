-- ============================================================================
-- MIGRACION DOWN 43: revierte DEC-073 en la base de datos. Restaura los 13 SP tal como estaban antes de la migracion 43,
-- retira los dos validadores internos nuevos, sus parametros y sus mensajes. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 43 DOWN: retira DEC-073';
GO

-- ---- usp_crear_sesion_interno (version anterior) ----
-- UTC-D06-POST-FREEZE: nucleo unico de creacion de sesion compartido por
--   * usp_crear_sesion    (v1, firma congelada DB-GP-001C) -> @procedenciaTemporal = NULL
--   * usp_crear_sesion_v2 (v2, instantes UTC confirmados)   -> @procedenciaTemporal = 'UTC_V2'
-- Las horas y la marca se escriben en el MISMO INSERT. Este SP no es publico: el rol runtime
-- tiene DENY EXECUTE directo y solo se alcanza por encadenamiento de propiedad desde los wrappers.
-- UTC_GENERADOR y UTC_OWNER NO se aceptan por esta via (generador y clasificacion propios).
-- CULM-001 A.2-10 (F-DOC-017): dentro de la transaccion y antes del INSERT, una sesion que se cruce con otra del grupo o
-- de otro grupo del mismo docente se rechaza con SES_017 (usp_validar_solape_sesion_interno); el rechazo no escribe.
-- CULM-001 / DEC-065 (2): la sesion creada por el docente nace con una solicitud PENDIENTE (SesionSolicitud, estado con esFinal = 0)
-- de aprobacion del coordinador, en la misma transaccion; el exito es SES_022. El ejecutor siempre es DOCENTE titular (PASOS 0-2.1).
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_sesion_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @procedenciaTemporal     NVARCHAR(24),
    @idCorrelacionResultado  UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idNuevoSesion   UNIQUEIDENTIFIER = NEWID();
    DECLARE @numeroSiguiente INT = 1;
    DECLARE @codigoSesion    NVARCHAR(50);
    DECLARE @idEstadoPendiente UNIQUEIDENTIFIER;

    -- Ownership transaccional (propia o savepoint bajo transacción externa)
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET @idCorrelacionResultado = @idCorrelacionDefecto;

    BEGIN TRY
        -- PASOS 0-1.6: procedencia, correlacion y seguridad antes de consultar el grupo.
        EXEC dbo.usp_validar_sesion_operacion_interno
            @idCorrelacion = @idCorrelacion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @procedenciaTemporal = @procedenciaTemporal,
            @fechaHoraInicio = @fechaHoraInicio,
            @fechaHoraFin = @fechaHoraFin,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @faseValidacion = 0;

        -- PASO 2: Validación de existencia del grupo académico
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.1: Titularidad del docente ejecutor sobre el grupo.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idGrupoDefecto,
                @tipoEntidadPadre = 'GRUPO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.5: conservar la prioridad contractual de entidad antes de fechas.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_operacion_interno
                @idCorrelacion = @idCorrelacion,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @procedenciaTemporal = @procedenciaTemporal,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @faseValidacion = 2;
        END

        -- PASO 3: Cálculo transaccional del correlativo de sesión e inserción
        -- (ownership transaccional: propia o savepoint bajo transacción externa)
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_crear_sesion;
                SET @savepointCreado = 1;
            END

            -- PASO 2.8 (CULM-001 A.2-10): solape con sesiones del grupo o del docente, bajo bloqueo
            EXEC dbo.usp_validar_solape_sesion_interno
                @idGrupo = @idGrupoDefecto,
                @idSesionExcluir = NULL,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.9 (DEC-065 (2)): estado en espera de la solicitud (catalogo; se resuelve por bandera, no por texto)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoPendiente = e.id
            FROM dbo.uv_estado_solicitud_sesion e
            WHERE e.esFinal = 0
            ORDER BY e.orden;

            IF @idEstadoPendiente IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'EstadoSolicitudSesion(esFinal = 0)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @numeroSiguiente = COALESCE(MAX(numero), 0) + 1
            FROM [dbo].[Sesion] WITH (UPDLOCK, HOLDLOCK)
            WHERE grupo = @idGrupoDefecto;

            SET @codigoSesion = CASE
                WHEN @numeroSiguiente < 100 THEN CONCAT('SES-', RIGHT('0' + CAST(@numeroSiguiente AS VARCHAR(10)), 2))
                ELSE CONCAT('SES-', CAST(@numeroSiguiente AS VARCHAR(10)))
            END;

            -- Horas y procedencia en la MISMA sentencia (UTC-D06).
            INSERT INTO dbo.Sesion (
                id, nombre, numero, codigo, numeroSemana, grupo,
                fechaHoraInicio, fechaHoraFin, procedenciaTemporal
            )
            VALUES (
                @idNuevoSesion,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Sesión #', @numeroSiguiente) END,
                @numeroSiguiente,
                @codigoSesion,
                @numeroSiguiente,
                @idGrupoDefecto,
                @fechaHoraInicio,
                @fechaHoraFin,
                @procedenciaTemporal
            );

            INSERT INTO dbo.SesionSolicitud (sesion, idEstado, usuarioSolicitante, fechaSolicitudUtc, idCorrelacion)
            VALUES (@idNuevoSesion, @idEstadoPendiente, @idUsuarioEjecutorDefecto, SYSUTCDATETIME(), @idCorrelacionDefecto);
        END

        -- Cierre de la transaccion propia (el rechazo por solape no escribe)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_022', @p_param1 = @idNuevoSesion, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones y reversión respetando ownership transaccional
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_crear_sesion;
        END

        -- Transacción externa condenada (XACT_STATE = -1) que no nos pertenece: propagar al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

-- ---- usp_actualizar_sesion_interno (version anterior) ----
-- UTC-D06-POST-FREEZE: nucleo unico de actualizacion de sesion compartido por
--   * usp_actualizar_sesion    (v1, firma congelada DB-GP-001C) -> @procedenciaTemporal = NULL
--   * usp_actualizar_sesion_v2 (v2, instantes UTC confirmados)   -> @procedenciaTemporal = 'UTC_V2'
-- PUT completo de horas: horas y marca se escriben en el MISMO UPDATE. Una actualizacion v1 de una
-- sesion confirmada la vuelve INDETERMINADA aunque el valor temporal sea identico, porque v1 no
-- declara zona. Solo NULL o UTC_V2 se aceptan por esta via.
-- CULM-001 A.2-10 (F-DOC-017): si cambian fechaHoraInicio o fechaHoraFin respecto de la fila guardada (N6), la sesion no
-- puede cruzarse con otra del grupo o de otro grupo del mismo docente (SES_017, excluida ella misma); un cambio de solo
-- nombre no se valida, asi una sesion con un solape heredado puede seguir renombrandose. Transaccion propia o savepoint.
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_sesion_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @procedenciaTemporal     NVARCHAR(24),
    @idCorrelacionResultado  UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idGrupoSesion UNIQUEIDENTIFIER;
    DECLARE @inicioActual  DATETIME2;
    DECLARE @finActual     DATETIME2;

    -- Ownership transaccional (propia o savepoint bajo transaccion externa)
    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

BEGIN
    SET NOCOUNT ON;
    SET @idCorrelacionResultado = @idCorrelacionDefecto;

    BEGIN TRY
        -- PASOS 0-1.6: procedencia, correlacion y seguridad antes de consultar la sesión.
        EXEC dbo.usp_validar_sesion_operacion_interno
            @idCorrelacion = @idCorrelacion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @procedenciaTemporal = @procedenciaTemporal,
            @fechaHoraInicio = @fechaHoraInicio,
            @fechaHoraFin = @fechaHoraFin,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @faseValidacion = 0;

        -- PASO 2: Validar existencia de la sesión con código semántico SES_001
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @idGrupoSesion = grupo
            FROM [dbo].[Sesion]
            WHERE id = @idSesionDefecto;

            IF @idGrupoSesion IS NULL
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

        -- PASO 3: Titularidad del docente ejecutor sobre la sesión.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idSesionDefecto,
                @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: conservar la prioridad contractual de entidad antes de fechas.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_operacion_interno
                @idCorrelacion = @idCorrelacion,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @procedenciaTemporal = @procedenciaTemporal,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @faseValidacion = 2;
        END

        -- PASO 5 (CULM-001 A.2-10): transaccion y solape solo si cambia el horario guardado (N6)
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_actualizar_sesion;
                SET @savepointCreado = 1;
            END

            SELECT @inicioActual = s.fechaHoraInicio, @finActual = s.fechaHoraFin
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            IF @inicioActual IS NULL OR @finActual IS NULL OR @inicioActual <> @fechaHoraInicio OR @finActual <> @fechaHoraFin
            BEGIN
                EXEC dbo.usp_validar_solape_sesion_interno
                    @idGrupo = @idGrupoSesion,
                    @idSesionExcluir = @idSesionDefecto,
                    @fechaHoraInicio = @fechaHoraInicio,
                    @fechaHoraFin = @fechaHoraFin,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            -- Horas y procedencia en la MISMA sentencia (UTC-D06).
            UPDATE dbo.Sesion
            SET nombre = CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE nombre END,
                fechaHoraInicio = @fechaHoraInicio,
                fechaHoraFin = @fechaHoraFin,
                procedenciaTemporal = @procedenciaTemporal
            WHERE id = @idSesionDefecto;
        END

        -- Cierre de la transaccion propia (el rechazo por solape no escribe)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Sesion', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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
            ROLLBACK TRANSACTION usp_actualizar_sesion;
        END

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

-- ---- usp_resolver_solicitud_revision_asistencia (version anterior) ----
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

-- ---- usp_crear_asignatura (version anterior) ----
-- ============================================================================
-- usp_crear_asignatura
-- Reglas de negocio (decisiones de John, 2026-11-04):
--   * P5: el area y el componente deben existir en sus tablas (GEN_001); nunca se asigna uno "cualquiera".
--   * Creditos obligatorios y mayores que cero (ASI_001); no hay valor por defecto.
--   * El semestre debe existir en el plan de estudios (PLA_004); la malla del plan no se amplia desde aqui.
--   * El coordinador solo crea asignaturas en planes de su propio programa (PLA_002 si el plan no existe,
--     SEC_002 por usp_validar_titularidad_jerarquica_interno si el programa no es suyo).
-- Salida canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_asignatura]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @codigo             NVARCHAR(50),
    @nombre             NVARCHAR(50),
    @creditos           INT,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @semestreNumero     INT,
    @nombreArea         NVARCHAR(100),
    @nombreComponente   NVARCHAR(100),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL,
    @codigoCaracter     NVARCHAR(3) = NULL   -- CULM-001 B2NM (R1): NULL -> ASIGNATURA_PLAN/CARACTER_DEFECTO
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPlanEstudioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPlanEstudio, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDefecto            NVARCHAR(50)     = UPPER(TRIM(@codigo));
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);
    DECLARE @nombreAreaDefecto        NVARCHAR(100)    = TRIM(@nombreArea);
    DECLARE @nombreCompDefecto        NVARCHAR(100)    = TRIM(@nombreComponente);

    DECLARE @idAreaResolved       UNIQUEIDENTIFIER;
    DECLARE @idComponenteResolved UNIQUEIDENTIFIER;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @idProgramaPlan       UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación del identificador de correlación
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
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validación de parámetros obligatorios
        IF @estadoResultado = 1 AND (@codigoDefecto IS NULL OR @codigoDefecto = '' OR @nombreDefecto IS NULL OR @nombreDefecto = '')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Codigo y Nombre son obligatorios. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2.1: Creditos obligatorios y mayores que cero (ASI_001), sin valor por defecto
        IF @estadoResultado = 1 AND (@creditos IS NULL OR @creditos <= 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ASI_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2.2: El plan existe (PLA_002) y pertenece al programa del coordinador (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idProgramaPlan = idPrograma FROM [dbo].[uv_plan_estudio] WHERE id = @idPlanEstudioDefecto;

            IF @idProgramaPlan IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PLA_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idProgramaPlan,
                @tipoEntidadPadre = 'PROGRAMA',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3 (CULM-001 B2NM, R2): unicidad del codigo contra la tabla (UX_Asignatura_codigo); existente -> ASI_002.
        --         La proteccion de concurrencia (UPDLOCK, HOLDLOCK) se toma dentro de la transaccion del PASO 5.
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[Asignatura] WHERE UPPER(TRIM(codigo)) = @codigoDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ASI_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Resolución de Área y Componente desde las tablas (P5, 2026-11-04): coincidencia exacta con su código
        -- o nombre; si no existen se rechaza con GEN_001. Nunca se asigna uno "cualquiera".
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_resolver_area_componente_asignatura_interno
                @area = @nombreAreaDefecto,
                @componente = @nombreCompDefecto,
                @obligatorios = 1,
                @idCorrelacion = @idCorrelacionDefecto,
                @idArea = @idAreaResolved OUTPUT,
                @idComponente = @idComponenteResolved OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4.9 (CULM-001 B2NM): el semestre del plan (PLA_004) y el caracter (ASI_007) se validan ANTES de escribir; asi un rechazo
        --          no necesita ROLLBACK (prohibido bajo INSERT ... EXEC) ni deja el catalogo a medias dentro de una transaccion ajena.
        IF @estadoResultado = 1
        BEGIN
            DECLARE @codigoRechazoPlan NVARCHAR(10);
            IF NOT EXISTS (SELECT 1 FROM dbo.SemestrePlanEstudio spe INNER JOIN dbo.Semestre sm ON sm.id = spe.semestre
                           WHERE spe.planEstudio = @idPlanEstudioDefecto AND sm.numero = @semestreNumero)
                SET @codigoRechazoPlan = 'PLA_004';
            ELSE IF NOT EXISTS (SELECT 1 FROM dbo.CaracterAsignaturaPlan c
                                WHERE c.estado = 1 AND c.codigo = COALESCE(NULLIF(TRIM(@codigoCaracter), N''),
                                      CAST(dbo.ufn_obtener_parametro('ASIGNATURA_PLAN', 'CARACTER_DEFECTO') AS NVARCHAR(3))))
                SET @codigoRechazoPlan = 'ASI_007';
            IF @codigoRechazoPlan IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @codigoRechazoPlan,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5 (CULM-001 B2NM, R3): catalogo + primer vinculo en una sola transaccion.
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            IF EXISTS (SELECT 1 FROM [dbo].[Asignatura] WITH (UPDLOCK, HOLDLOCK) WHERE UPPER(TRIM(codigo)) = @codigoDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ASI_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1
            BEGIN
                INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, estado)
                VALUES (@idAsignaturaDefecto, @codigoDefecto, @nombreDefecto, @creditos, @idAreaResolved, @idComponenteResolved, 1);

                EXEC dbo.usp_internal_asociar_asignatura_plan
                    @idAsignatura = @idAsignaturaDefecto,
                    @idPlanEstudio = @idPlanEstudioDefecto,
                    @semestreNumero = @semestreNumero,
                    @codigoCaracter = @codigoCaracter,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'Asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                IF @transaccionPropia = 1 COMMIT TRANSACTION;
            END
            ELSE IF @transaccionPropia = 1
                ROLLBACK TRANSACTION;

        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;
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

-- ---- usp_actualizar_asignatura (version anterior) ----
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_asignatura]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @codigo             NVARCHAR(50),
    @nombre             NVARCHAR(50),
    @creditos           INT,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @semestreNumero     INT,
    @nombreArea         NVARCHAR(100),
    @nombreComponente   NVARCHAR(100),
    @idCorrelacion      UNIQUEIDENTIFIER,
    -- REC2 (auditoria BD 2026-10-28): ejecutor obligatorio (GEN_002 si llega NULL). El DEFAULT solo conserva la
    -- compatibilidad de firma; RBAC COORDINADOR + titularidad del PROGRAMA se validan en usp_validar_gestion_asignatura_coordinador_interno.
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL,
    @codigoCaracter     NVARCHAR(3) = NULL   -- CULM-001 B2NM: NULL conserva el caracter actual del vinculo
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDefecto        NVARCHAR(50)     = UPPER(TRIM(@codigo));
    DECLARE @nombreDefecto        NVARCHAR(50)     = TRIM(@nombre);
    DECLARE @idAreaResolved       UNIQUEIDENTIFIER;
    DECLARE @idComponenteResolved UNIQUEIDENTIFIER;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @idSpeNuevo           UNIQUEIDENTIFIER;
    DECLARE @idCaracterNuevo      UNIQUEIDENTIFIER;
    DECLARE @cambiaCatalogo       BIT = 0;
    DECLARE @codigoRechazo        NVARCHAR(10);

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio, perfil COORDINADOR, existencia de la asignatura y titularidad del
        --         programa (REC2: logica comun en usp_validar_gestion_asignatura_coordinador_interno)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno
                @idAsignatura = @idAsignaturaDefecto,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @idCorrelacion = @idCorrelacionDefecto,
                @idPlanEstudio = @idPlanEstudio,   -- CULM-001 B2NM: ambito por el plan indicado (SEC_002 / ASI_004)
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.1: Creditos (decision de John 2026-11-04): si llegan deben ser mayores que cero (ASI_001); nulos
        --           conservan los actuales (actualizacion parcial, como el resto de campos)
        IF @estadoResultado = 1 AND @creditos IS NOT NULL AND @creditos <= 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ASI_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar unicidad del código si cambia
        IF @estadoResultado = 1 AND @codigoDefecto IS NOT NULL AND @codigoDefecto <> ''
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[Asignatura] WHERE UPPER(TRIM(codigo)) = @codigoDefecto AND id <> @idAsignaturaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ASI_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Actualización de la Asignatura
        -- P5 (2026-11-04): el área y el componente, si llegan, deben existir en sus tablas (GEN_001); vacíos conservan el actual.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_resolver_area_componente_asignatura_interno
                @area = @nombreArea,
                @componente = @nombreComponente,
                @obligatorios = 0,
                @idCorrelacion = @idCorrelacionDefecto,
                @idArea = @idAreaResolved OUTPUT,
                @idComponente = @idComponenteResolved OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4.1 (CULM-001 B2NM, S2): semestre y caracter del vinculo en el plan indicado. NULL conserva el actual.
        IF @estadoResultado = 1 AND @semestreNumero IS NOT NULL
        BEGIN
            SELECT @idSpeNuevo = spe.id
            FROM dbo.SemestrePlanEstudio spe
            INNER JOIN dbo.Semestre sm ON sm.id = spe.semestre
            WHERE spe.planEstudio = @idPlanEstudio AND sm.numero = @semestreNumero;
            IF @idSpeNuevo IS NULL
                SET @codigoRechazo = 'PLA_004';
        END
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND NULLIF(TRIM(@codigoCaracter), N'') IS NOT NULL
        BEGIN
            SELECT @idCaracterNuevo = c.id FROM dbo.CaracterAsignaturaPlan c WHERE c.codigo = TRIM(@codigoCaracter) AND c.estado = 1;
            IF @idCaracterNuevo IS NULL
                SET @codigoRechazo = 'ASI_007';
        END

        -- PASO 4.2: los datos de catalogo de una asignatura compartida solo los cambia quien coordina todos sus programas (ASI_006)
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            SELECT @cambiaCatalogo = IIF(
                   (@codigoDefecto IS NOT NULL AND @codigoDefecto <> '' AND a.codigo <> @codigoDefecto)
                OR (@nombreDefecto IS NOT NULL AND @nombreDefecto <> '' AND a.nombre <> @nombreDefecto)
                OR (@creditos IS NOT NULL AND a.credito <> @creditos)
                OR (@idAreaResolved IS NOT NULL AND a.area <> @idAreaResolved)
                OR (@idComponenteResolved IS NOT NULL AND a.componente <> @idComponenteResolved), 1, 0)
            FROM dbo.Asignatura a WHERE a.id = @idAsignaturaDefecto;

            IF @cambiaCatalogo = 1
               AND EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
                           WHERE v.idAsignatura = @idAsignaturaDefecto AND v.estaActivoVinculo = 1
                             AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE cp.idPrograma = v.idPrograma))
                SET @codigoRechazo = 'ASI_006';
        END

        -- PASO 4.3: un vinculo (inactivo) ya ocupa el semestre destino -> ASI_003
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idSpeNuevo IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape
                       WHERE ape.asignatura = @idAsignaturaDefecto AND ape.semestrePlanEstudio = @idSpeNuevo)
           AND NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape2
                           WHERE ape2.asignatura = @idAsignaturaDefecto AND ape2.semestrePlanEstudio = @idSpeNuevo AND ape2.estaActivo = 1)
            SET @codigoRechazo = 'ASI_003';

        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            IF @cambiaCatalogo = 1
                UPDATE dbo.Asignatura
                SET codigo = CASE WHEN @codigoDefecto IS NOT NULL AND @codigoDefecto <> '' THEN @codigoDefecto ELSE codigo END,
                    nombre = CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE nombre END,
                    credito = CASE WHEN @creditos IS NOT NULL THEN @creditos ELSE credito END,
                    area = CASE WHEN @idAreaResolved IS NOT NULL THEN @idAreaResolved ELSE area END,
                    componente = CASE WHEN @idComponenteResolved IS NOT NULL THEN @idComponenteResolved ELSE componente END
                WHERE id = @idAsignaturaDefecto;

            -- La MISMA fila de la tabla puente cambia de semestre / caracter (no se crea otra: la asignatura de un solo plan sigue 1:1)
            UPDATE ape
            SET ape.semestrePlanEstudio = COALESCE(@idSpeNuevo, ape.semestrePlanEstudio),
                ape.caracter = COALESCE(@idCaracterNuevo, ape.caracter)
            FROM dbo.AsignaturaPlanEstudio ape
            INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
            WHERE ape.asignatura = @idAsignaturaDefecto AND spe.planEstudio = @idPlanEstudio AND ape.estaActivo = 1;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Asignatura',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            IF @transaccionPropia = 1 COMMIT TRANSACTION;
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;
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

-- ---- usp_crear_grupo (version anterior) ----
-- CULM-001 / DEC-065 (4): solo el COORDINADOR crea grupos; el DOCENTE recibe SEC_001 (perfil requerido COORDINADOR).
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idAsignatura            UNIQUEIDENTIFIER,
    @idPeriodoAcademico      UNIQUEIDENTIFIER,
    @codigo                  INT,
    @nombre                  NVARCHAR(50),
    @idDocente               UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPeriodoAcademicoDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPeriodoAcademico, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto             NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idPeriodoResolved         UNIQUEIDENTIFIER = @idPeriodoAcademicoDefecto;
    DECLARE @capacidadMaximaDefecto    INT;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
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
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.6 (DEC-065 (4)): solo el COORDINADOR crea grupos (el docente ya no los crea; el PASO 1.5 lo rechaza con SEC_001)

        -- PASO 2: Validar asignatura en uv_asignatura
        IF @estadoResultado = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[uv_asignatura] WHERE id = @idAsignaturaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'Asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Resolver período académico si viene nulo/guid defecto
        IF @estadoResultado = 1
        BEGIN
            IF @idPeriodoResolved IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_periodo_academico] WHERE id = @idPeriodoResolved)
            BEGIN
                SELECT TOP 1 @idPeriodoResolved = id 
                FROM [dbo].[uv_periodo_academico] 
                ORDER BY anio DESC;
            END

            IF @idPeriodoResolved IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_periodo_academico] WHERE id = @idPeriodoResolved)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'PeriodoAcademico',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Validar docente mediante procedimiento interno estandarizado
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_docente_exista_por_id_interno
                @idDocente = @idDocenteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4B (HU093/D12): el titular no puede tener su vinculo con el programa inactivado
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_docente_vinculo_activo_programa_interno
                @idDocente = @idDocenteDefecto,
                @idAsignatura = @idAsignaturaDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Validar unicidad de código de grupo en el período consultando uv_grupo
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (
                SELECT 1 FROM [dbo].[uv_grupo]
                WHERE idAsignatura = @idAsignaturaDefecto AND idPeriodoAcademico = @idPeriodoResolved AND codigo = @codigo
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_006',
                    @p_param1 = 'Grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 6: Resolver capacidad máxima por defecto desde el catálogo de parámetros (GRUPO/CAPACIDAD_MAXIMA_DEFECTO)
        IF @estadoResultado = 1
        BEGIN
            SET @capacidadMaximaDefecto = dbo.ufn_obtener_parametro_int(NULL, 'GRUPO', 'CAPACIDAD_MAXIMA_DEFECTO');

            IF @capacidadMaximaDefecto IS NULL OR @capacidadMaximaDefecto <= 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ERR_CAPACIDAD_GRUPO_INVALIDA',
                    @p_param1 = @capacidadMaximaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: Inserción directa de Grupo con capacidad máxima proveniente del catálogo
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.Grupo (
                id, asignatura, periodoAcademico, codigo, nombre,
                cantidadEstudiantes, cantidadEstudiantesFinalizaron,
                cantidadEstudiantesCancelaronVoluntadPropia,
                cantidadEstudiantesCancelaronAutomaticamente,
                docente
            )
            VALUES (
                @idGrupoDefecto,
                @idAsignaturaDefecto,
                @idPeriodoResolved,
                @codigo,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Grupo ', @codigo) END,
                @capacidadMaximaDefecto, 0, 0, 0,
                @idDocenteDefecto
            );

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

-- ---- usp_actualizar_grupo (version anterior) ----
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @codigo                  INT,
    @nombre                  NVARCHAR(50),
    @idDocente               UNIQUEIDENTIFIER,
    @cupoMaximo              INT,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto         UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idAsigCurrent        UNIQUEIDENTIFIER;
    DECLARE @idPeriodoCurrent     UNIQUEIDENTIFIER;
    DECLARE @estudiantesActivos   INT;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
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
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validar existencia del grupo en uv_grupo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 
                @idAsigCurrent = idAsignatura,
                @idPeriodoCurrent = idPeriodoAcademico
            FROM [dbo].[uv_grupo] 
            WHERE id = @idGrupoDefecto;

            IF @idAsigCurrent IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'Grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Validar docente si se modifica (se usa el parámetro crudo: @idDocenteDefecto
        -- resuelve a un GUID centinela vía ufn_obtener_parametro_guid incluso cuando no se envía)
        IF @estadoResultado = 1 AND @idDocente IS NOT NULL
        BEGIN
            EXEC dbo.usp_validar_docente_exista_por_id_interno
                @idDocente = @idDocenteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3B (HU093/D12): un titular NUEVO no puede tener su vinculo con el programa inactivado.
        -- Si el titular no cambia no se revalida (editar cupo u otros datos de un grupo ya asignado sigue permitido).
        IF @estadoResultado = 1 AND @idDocente IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM [dbo].[uv_grupo] WHERE id = @idGrupoDefecto AND idDocente = @idDocenteDefecto)
        BEGIN
            EXEC dbo.usp_validar_docente_vinculo_activo_programa_interno
                @idDocente = @idDocenteDefecto,
                @idAsignatura = @idAsigCurrent,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3C: un docente no puede tener dos grupos a la misma hora. Si el titular cambia, los horarios
        -- del grupo no pueden cruzarse con los de otro grupo del nuevo titular en el mismo período (HOR_002).
        IF @estadoResultado = 1 AND @idDocente IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM [dbo].[uv_grupo] WHERE id = @idGrupoDefecto AND idDocente = @idDocenteDefecto)
        BEGIN
            EXEC dbo.usp_validar_cruce_horario_docente_interno
                @idDocente = @idDocenteDefecto,
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validar conflicto de unicidad de código
        IF @estadoResultado = 1 AND @codigo IS NOT NULL AND @codigo > 0
        BEGIN
            IF EXISTS (
                SELECT 1 FROM [dbo].[uv_grupo]
                WHERE idAsignatura = @idAsigCurrent AND idPeriodoAcademico = @idPeriodoCurrent AND codigo = @codigo AND id <> @idGrupoDefecto
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_006',
                    @p_param1 = 'Grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: Validar que el nuevo cupo máximo no sea inferior a la ocupación actual del grupo
        IF @estadoResultado = 1 AND @cupoMaximo IS NOT NULL AND @cupoMaximo > 0
        BEGIN
            SELECT @estudiantesActivos = cantidadActivos
            FROM [dbo].[uv_estadistica_grupo]
            WHERE id = @idGrupoDefecto;

            IF @estudiantesActivos IS NOT NULL AND @cupoMaximo < @estudiantesActivos
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ERR_CUPO_INFERIOR_OCUPACION',
                    @p_param1 = @idGrupoDefecto,
                    @p_param2 = @cupoMaximo,
                    @p_param3 = @estudiantesActivos,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 6: Actualización del Grupo
        IF @estadoResultado = 1
        BEGIN
            UPDATE dbo.Grupo
            SET codigo = CASE WHEN @codigo IS NOT NULL AND @codigo > 0 THEN @codigo ELSE codigo END,
                nombre = CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE nombre END,
                docente = CASE WHEN @idDocente IS NOT NULL THEN @idDocenteDefecto ELSE docente END,
                cantidadEstudiantes = CASE WHEN @cupoMaximo IS NOT NULL AND @cupoMaximo > 0 THEN @cupoMaximo ELSE cantidadEstudiantes END
            WHERE id = @idGrupoDefecto;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

-- ---- usp_crear_decano (version anterior) ----
-- CULM-001 D.9-a (F-ADM-024): DEC_020 si la persona ya es decano activo (sobre la firma con @idTipoIdIdentificacion de D.5).
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_decano]
(
    @idDecano               UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @nombreFacultad          NVARCHAR(150)    = NULL,
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDecanoDefecto          UNIQUEIDENTIFIER = @idDecano;
    DECLARE @idFacultadDefecto        UNIQUEIDENTIFIER = @idFacultad;
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreFacultadDef        NVARCHAR(150)    = TRIM(@nombreFacultad);


    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    -- Control de ownership transaccional (ver docs/procedimiento-transacciones)
    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de presencia del identificador de correlación
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

        -- PASO 2: Resolver facultad destino si se suministra el nombre
        IF @estadoResultado = 1 AND @idFacultadDefecto IS NULL AND @nombreFacultadDef IS NOT NULL AND @nombreFacultadDef <> ''
        BEGIN
            SELECT TOP 1 @idFacultadDefecto = id
            FROM [dbo].[uv_facultad]
            WHERE LOWER(nombreFacultad) = LOWER(@nombreFacultadDef)
               OR LOWER(nombreFacultad) LIKE LOWER(CONCAT('%', @nombreFacultadDef, '%'))
            ORDER BY nombreFacultad ASC;
        END

        -- PASO 2.5 (D.9-a, F-ADM-024): la persona ya es decano activo. Se decide ANTES de abrir la transaccion o el savepoint:
        -- no hay escrituras que revertir y el SP puede invocarse con INSERT ... EXEC sin ROLLBACK interno (DEC-036).
        IF @estadoResultado = 1
        BEGIN
            DECLARE @idUsuarioExistente UNIQUEIDENTIFIER;
            SELECT TOP 1 @idUsuarioExistente = id
            FROM [dbo].[uv_usuario]
            WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = CAST(@numeroIdentificacion AS VARCHAR(20));

            IF @idUsuarioExistente IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.Decano d WHERE d.usuario = @idUsuarioExistente AND d.estado = 1)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DEC_020',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: apertura de transaccion (o savepoint) y delegacion de persona + rol Decano al nucleo usp_crear_decano_interno (DEC-065 (5))
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
                SAVE TRANSACTION usp_crear_decano;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_crear_decano_interno
                @idDecano = @idDecanoDefecto OUTPUT,
                @numeroIdentificacion = @numeroIdentificacion,
                @primerNombre = @primerNombre,
                @segundoNombre = @segundoNombre,
                @primerApellido = @primerApellido,
                @segundoApellido = @segundoApellido,
                @correo = @correo,
                @password = @password,
                @idFacultad = @idFacultadDefecto,
                @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Finalización de la transacción respetando ownership (ver docs/procedimiento-transacciones)
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
            IF XACT_STATE() = 1 AND @estadoResultado = 0
                ROLLBACK TRANSACTION usp_crear_decano;
            -- XACT_STATE() = -1 con transacción externa: no es propietaria, no se toca (ver PASO 10 del contrato)
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
            ROLLBACK TRANSACTION usp_crear_decano;
        END

        -- Transacción externa quedó doomed y no nos pertenece: propagar la excepción original al propietario
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

-- ---- usp_crear_decano_con_facultad (version anterior) ----
-- ============================================================================
-- usp_crear_decano_con_facultad (CULM-001 / DEC-065 (5); HU116, F-ADM-024)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con la tupla canonica (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado) + idDecano, idFacultad, nombreFacultad (NULL si estadoResultado = 0).
--
-- El administrador registra, en UNA transaccion, a la persona decano y la facultad que titulara. Las validaciones de la facultad y del decano
-- (que no escriben) se resuelven ANTES de abrir la transaccion; el resto de la escritura es todo o nada:
--   * RBAC ADMINISTRADOR (SEC_001), igual que usp_crear_decano y usp_crear_facultad; ejecutor obligatorio (GEN_002);
--   * nombre de la facultad de 3 a 50 caracteres (GEN_002) y unico (GEN_003), como usp_crear_facultad;
--   * institucion existente (GEN_001); si se omite, la primera activa (misma regla de usp_crear_facultad);
--   * la persona no puede ser ya decano activo (DEC_020).
--   Luego, dentro de la transaccion: usp_crear_decano_interno (persona + rol) y usp_crear_facultad_interno (con ese decano). Cualquier error
--   revierte persona, rol y facultad: no queda ninguna persona huerfana.
-- @codigoFacultad se acepta por compatibilidad con el formulario; dbo.Facultad no tiene columna de codigo, de modo que no se persiste.
-- Transaccion propia o SAVE TRANSACTION cuando el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_decano_con_facultad]
(
    @idDecano               UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion   INT,
    @primerNombre           NVARCHAR(50),
    @segundoNombre          NVARCHAR(50),
    @primerApellido         NVARCHAR(50),
    @segundoApellido        NVARCHAR(50),
    @correo                 NVARCHAR(100),
    @password               NVARCHAR(500),
    @nombreFacultad         NVARCHAR(150),
    @codigoFacultad         NVARCHAR(20)     = NULL,
    @idInstitucion          UNIQUEIDENTIFIER,
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor      UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucionDefecto     UNIQUEIDENTIFIER = @idInstitucion;
    DECLARE @idDecanoDefecto          UNIQUEIDENTIFIER = @idDecano;
    DECLARE @idFacultadNueva          UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreFacultadDef        NVARCHAR(150)    = TRIM(@nombreFacultad);
    DECLARE @idUsuarioExistente       UNIQUEIDENTIFIER;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio y perfil ADMINISTRADOR
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

        -- PASO 3: institucion por defecto (primera activa), igual que usp_crear_facultad
        IF @estadoResultado = 1 AND @idInstitucionDefecto IS NULL
        BEGIN
            SELECT TOP 1 @idInstitucionDefecto = id
            FROM dbo.uv_institucion
            WHERE estaActivaInstitucion = 1
            ORDER BY id ASC;
        END

        -- PASO 4: validaciones de la facultad (mismos codigos que usp_crear_facultad), ANTES de crear la persona
        IF @estadoResultado = 1 AND (@nombreFacultadDef IS NULL OR LEN(@nombreFacultadDef) < 3 OR LEN(@nombreFacultadDef) > 50)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Nombre de Facultad',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Longitud invalida (3-50). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE LOWER(nombreFacultad) = LOWER(@nombreFacultadDef))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003',
                @p_param1 = 'Facultad',
                @p_param2 = 'nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Conflicto de unicidad para nombre: ', @nombreFacultadDef, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@idInstitucionDefecto IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_institucion WHERE id = @idInstitucionDefecto))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Institucion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5 (D.9-a, F-ADM-024): la persona ya es decano activo; se decide antes de abrir la transaccion (no hay escrituras que revertir)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idUsuarioExistente = id
            FROM [dbo].[uv_usuario]
            WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = CAST(@numeroIdentificacion AS VARCHAR(20));

            IF @idUsuarioExistente IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.Decano d WHERE d.usuario = @idUsuarioExistente AND d.estado = 1)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DEC_020',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 6: transaccion unica (propia o savepoint): persona + rol Decano y despues la facultad con ese decano
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION svp_crear_decano_facultad;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_crear_decano_interno
                @idDecano = @idDecanoDefecto OUTPUT,
                @numeroIdentificacion = @numeroIdentificacion,
                @primerNombre = @primerNombre,
                @segundoNombre = @segundoNombre,
                @primerApellido = @primerApellido,
                @segundoApellido = @segundoApellido,
                @correo = @correo,
                @password = @password,
                @idFacultad = NULL,
                @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_crear_facultad_interno
                    @id = @idFacultadNueva,
                    @nombre = @nombreFacultadDef,
                    @idInstitucion = @idInstitucionDefecto,
                    @idDecano = @idDecanoDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'Decano y facultad',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' IdDecano: ', @idDecanoDefecto, ' IdFacultad: ', @idFacultadNueva, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- Cierre respetando el ownership: un fallo tras abrir la transaccion revierte persona, rol y facultad
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
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
            ELSE IF @savepointCreado = 1 AND XACT_STATE() = 1 AND @estadoResultado = 0
                ROLLBACK TRANSACTION svp_crear_decano_facultad;
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
            ROLLBACK TRANSACTION svp_crear_decano_facultad;

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
        idDecano                = IIF(@estadoResultado = 1, @idDecanoDefecto, NULL),
        idFacultad              = IIF(@estadoResultado = 1, @idFacultadNueva, NULL),
        nombreFacultad          = IIF(@estadoResultado = 1, @nombreFacultadDef, NULL);
END;
GO

-- ---- usp_crear_coordinador (version anterior) ----
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_coordinador]
(
    @idCoordinador           UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @idPrograma              UNIQUEIDENTIFIER = NULL,
    @idFacultad              UNIQUEIDENTIFIER,
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idCoordinadorDefecto     UNIQUEIDENTIFIER = @idCoordinador;
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = @idPrograma;
    DECLARE @idFacultadDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idFacultad, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');


    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    -- Control de ownership transaccional (ver docs/procedimiento-transacciones)
    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de presencia del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de presencia del ejecutor y perfil RBAC
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
                @codigoPerfilRequerido = 'DECANO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        END

        -- PASO 2: Validar programa académico consultando uv_programa (cuando se suministra @idPrograma)
        IF @estadoResultado = 1 AND @idProgramaDefecto IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[uv_programa] WHERE id = @idProgramaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PROG_001',
                    @p_param1 = 'Programa',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2B: Validar existencia de la facultad indicada consultando uv_facultad
        IF @estadoResultado = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[uv_facultad] WHERE id = @idFacultadDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001',
                    @p_param1 = 'Facultad',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2C: Validar que el Programa pertenezca a la Facultad indicada (cuando se suministra @idPrograma)
        IF @estadoResultado = 1 AND @idProgramaDefecto IS NOT NULL
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM [dbo].[uv_programa]
                WHERE id = @idProgramaDefecto AND idFacultad = @idFacultadDefecto
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ERR_PROGRAMA_FACULTAD_INCONSISTENTE',
                    @p_param1 = @idProgramaDefecto,
                    @p_param2 = @idFacultadDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2D: Validar titularidad jerárquica sobre la Facultad ya existente y coherente
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idFacultadDefecto,
                @tipoEntidadPadre = 'FACULTAD',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: apertura de transaccion (o savepoint) y delegacion de persona + rol Coordinador al nucleo usp_crear_coordinador_interno (DEC-065 (5))
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
                SAVE TRANSACTION usp_crear_coordinador;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_crear_coordinador_interno
                @idCoordinador = @idCoordinadorDefecto OUTPUT,
                @numeroIdentificacion = @numeroIdentificacion,
                @primerNombre = @primerNombre,
                @segundoNombre = @segundoNombre,
                @primerApellido = @primerApellido,
                @segundoApellido = @segundoApellido,
                @correo = @correo,
                @password = @password,
                @idFacultad = @idFacultadDefecto,
                @idPrograma = @idProgramaDefecto,
                @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Finalización de la transacción respetando ownership (ver docs/procedimiento-transacciones)
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
            IF XACT_STATE() = 1 AND @estadoResultado = 0
                ROLLBACK TRANSACTION usp_crear_coordinador;
            -- XACT_STATE() = -1 con transacción externa: no es propietaria, no se toca (ver PASO 10 del contrato)
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
            ROLLBACK TRANSACTION usp_crear_coordinador;
        END

        -- Transacción externa quedó doomed y no nos pertenece: propagar la excepción original al propietario
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

-- ---- usp_crear_coordinador_con_programa (version anterior) ----
-- ============================================================================
-- usp_crear_coordinador_con_programa (CULM-001 / DEC-065 (5); HU076, HU121)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con la tupla canonica (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado) + idCoordinador, idPrograma, nombrePrograma (NULL si estadoResultado = 0).
--
-- El decano registra, en UNA transaccion, a la persona coordinadora y el programa academico que coordinara en su facultad. Las validaciones
-- que no escriben se resuelven ANTES de abrir la transaccion; el resto de la escritura es todo o nada:
--   * RBAC DECANO (SEC_001), ejecutor obligatorio (GEN_002), facultad obligatoria (GEN_002);
--   * titularidad del decano sobre @idFacultad (SEC_002), como usp_crear_programa_academico y usp_crear_coordinador;
--   * facultad existente y activa (GEN_001);
--   * programa: nombre (GEN_002), unico en la facultad (PROG_003), tipo (PROG_004), modalidad y jornada (PROG_006). Son las reglas de
--     usp_validar_programa_academico_interno, que se invoca sin coordinador y cuyo unico rechazo esperado (PROG_005, aun no existe) se descarta;
--   Luego, dentro de la transaccion: usp_crear_coordinador_interno (persona + rol, con la facultad) y usp_insertar_programa_academico_interno
--   (que revalida el programa ya con el coordinador: PROG_005 si ya tiene otro programa). Cualquier error revierte persona, rol y programa.
-- Transaccion propia o SAVE TRANSACTION cuando el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_coordinador_con_programa]
(
    @idCoordinador          UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion   INT,
    @primerNombre           NVARCHAR(50),
    @segundoNombre          NVARCHAR(50),
    @primerApellido         NVARCHAR(50),
    @segundoApellido        NVARCHAR(50),
    @correo                 NVARCHAR(100),
    @password               NVARCHAR(500),
    @nombrePrograma         NVARCHAR(100),
    @idTipoPrograma         UNIQUEIDENTIFIER,
    @idModalidad            UNIQUEIDENTIFIER = NULL,
    @idJornada              UNIQUEIDENTIFIER = NULL,
    @idFacultad             UNIQUEIDENTIFIER,
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor      UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idCoordinadorDefecto     UNIQUEIDENTIFIER = @idCoordinador;
    DECLARE @idProgramaNuevo          UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreProgramaDef        NVARCHAR(100)    = TRIM(@nombrePrograma);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio y perfil DECANO
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
                @codigoPerfilRequerido = 'DECANO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: facultad obligatoria y titularidad del decano sobre ella
        IF @estadoResultado = 1 AND @idFacultad IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idFacultad',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idFacultad,
                @tipoEntidadPadre = 'FACULTAD',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_facultad f WHERE f.id = @idFacultad AND f.estaActivaFacultad = 1)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Facultad',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: reglas del programa (nombre, unicidad, tipo, modalidad, jornada) ANTES de crear la persona. Sin coordinador el validador termina
        -- siempre en PROG_005; ese unico rechazo es el esperado y se descarta, cualquier otro es el error real.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_programa_academico_interno
                @idPrograma = NULL,
                @idFacultad = @idFacultad,
                @nombre = @nombreProgramaDef,
                @idTipoPrograma = @idTipoPrograma,
                @idCoordinador = NULL,
                @idModalidad = @idModalidad,
                @idJornada = @idJornada,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 0 AND @mensajeTecnicoResultado LIKE N'DBCODE=PROG[_]005|%'
            BEGIN
                SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
                SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
                SET @estadoResultado = 1;
            END
        END

        -- PASO 5: transaccion unica (propia o savepoint): persona + rol Coordinador (con la facultad) y despues el programa con ese coordinador
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION svp_crear_coord_programa;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_crear_coordinador_interno
                @idCoordinador = @idCoordinadorDefecto OUTPUT,
                @numeroIdentificacion = @numeroIdentificacion,
                @primerNombre = @primerNombre,
                @segundoNombre = @segundoNombre,
                @primerApellido = @primerApellido,
                @segundoApellido = @segundoApellido,
                @correo = @correo,
                @password = @password,
                @idFacultad = @idFacultad,
                @idPrograma = NULL,
                @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_insertar_programa_academico_interno
                    @idPrograma = @idProgramaNuevo,
                    @idFacultad = @idFacultad,
                    @nombre = @nombreProgramaDef,
                    @idTipoPrograma = @idTipoPrograma,
                    @idCoordinador = @idCoordinadorDefecto,
                    @idModalidad = @idModalidad,
                    @idJornada = @idJornada,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'Coordinador y programa',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' IdCoordinador: ', @idCoordinadorDefecto, ' IdPrograma: ', @idProgramaNuevo, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- Cierre respetando el ownership: un fallo tras abrir la transaccion revierte persona, rol y programa
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
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
            ELSE IF @savepointCreado = 1 AND XACT_STATE() = 1 AND @estadoResultado = 0
                ROLLBACK TRANSACTION svp_crear_coord_programa;
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
            ROLLBACK TRANSACTION svp_crear_coord_programa;

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
        idCoordinador           = IIF(@estadoResultado = 1, @idCoordinadorDefecto, NULL),
        idPrograma              = IIF(@estadoResultado = 1, @idProgramaNuevo, NULL),
        nombrePrograma          = IIF(@estadoResultado = 1, @nombreProgramaDef, NULL);
END;
GO

-- ---- usp_vincular_docente_programa (version anterior) ----
-- HU091: vincula un docente al programa del coordinador. Tres modos excluyentes:
--   (a) @idDocente        docente existente (p. ej. de otro programa de la misma institucion)
--   (b) @idUsuario        usuario existente que aun no es docente
--   (c) datos de persona  alta nueva (usuario + docente + vinculo); documento/correo existentes => DOC_003
-- RBAC COORDINADOR + titularidad PROGRAMA se validan DENTRO del SP. @password es el HASH (nunca texto plano).
-- Una sola transaccion con ownership (transaccion propia o savepoint si el llamador ya tiene una).
CREATE OR ALTER PROCEDURE [dbo].[usp_vincular_docente_programa]
(
    @idDocente              UNIQUEIDENTIFIER = NULL,
    @idUsuario              UNIQUEIDENTIFIER = NULL,
    @idTipoIdentificacion   UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion   INT              = NULL,
    @primerNombre           NVARCHAR(50)     = NULL,
    @segundoNombre          NVARCHAR(50)     = NULL,
    @primerApellido         NVARCHAR(50)     = NULL,
    @segundoApellido        NVARCHAR(50)     = NULL,
    @correo                 NVARCHAR(100)    = NULL,
    @password               NVARCHAR(500)    = NULL,
    @idTipoVinculacion      UNIQUEIDENTIFIER,
    @idPrograma             UNIQUEIDENTIFIER,
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor      UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @modoDocente BIT = IIF(@idDocente IS NULL, 0, 1);
    DECLARE @modoUsuario BIT = IIF(@idUsuario IS NULL, 0, 1);
    DECLARE @modoNuevo   BIT = IIF(@numeroIdentificacion IS NULL AND @correo IS NULL AND @idTipoIdentificacion IS NULL
                                   AND @primerNombre IS NULL AND @primerApellido IS NULL AND @password IS NULL, 0, 1);
    DECLARE @idUsuarioResuelto  UNIQUEIDENTIFIER;
    DECLARE @idDocenteResuelto  UNIQUEIDENTIFIER;
    DECLARE @idInstitucion      UNIQUEIDENTIFIER;
    DECLARE @correoNormalizado  NVARCHAR(100) = LOWER(TRIM(@correo));

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

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

        -- PASO 2: ejecutor obligatorio
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: RBAC COORDINADOR
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

        -- PASO 4: titularidad sobre el programa
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idProgramaDefecto,
                @tipoEntidadPadre = 'PROGRAMA',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4B: programa activo
        IF @estadoResultado = 1
        BEGIN
            SELECT @idInstitucion = idInstitucion FROM dbo.uv_programa WHERE id = @idProgramaDefecto AND estaActivoPrograma = 1;
            IF @idInstitucion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PROG_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: exactamente un modo (DOC_005)
        IF @estadoResultado = 1 AND (CAST(@modoDocente AS INT) + CAST(@modoUsuario AS INT) + CAST(@modoNuevo AS INT)) <> 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'DOC_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: tipo de vinculacion antes de tocar datos (DOC_004)
        IF @estadoResultado = 1
           AND (@idTipoVinculacion IS NULL
                OR NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_vinculacion WHERE id = @idTipoVinculacion AND estaActivoTipoVinculacion = 1))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'DOC_004',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 7: validaciones de solo lectura ANTES de abrir la transaccion (sin escrituras no hay rollback que hacer)
        IF @estadoResultado = 1
        BEGIN
            IF @modoNuevo = 1
            BEGIN
                IF EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE numeroIdentificacion = @numeroIdentificacion OR correo = @correoNormalizado)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_003',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
            END
            ELSE IF @modoUsuario = 1
            BEGIN
                SELECT TOP 1 @idUsuarioResuelto = id FROM dbo.uv_usuario WHERE id = @idUsuario AND estaActivoUsuario = 1;
                IF @idUsuarioResuelto IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
                ELSE
                    SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE idUsuario = @idUsuarioResuelto;
            END
            ELSE
            BEGIN
                SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE id = @idDocente AND estaActivoUsuario = 1;
                IF @idDocenteResuelto IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
            END

            -- El docente no puede pertenecer solo a otra institucion
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.uv_docente_programa WHERE idDocente = @idDocenteResuelto AND idInstitucion <> @idInstitucion)
               AND NOT EXISTS (SELECT 1 FROM dbo.uv_docente_programa WHERE idDocente = @idDocenteResuelto AND idInstitucion = @idInstitucion)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DOC_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END

            -- Vinculo duplicado
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @idDocenteResuelto AND programa = @idProgramaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DOC_006',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 0
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 8: escrituras en una sola transaccion con ownership
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
                SAVE TRANSACTION usp_vincular_docente_programa;
                SET @savepointCreado = 1;
            END

            -- 8A: persona nueva
            IF @modoNuevo = 1
            BEGIN
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correo,
                    @password = @password,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                    SELECT TOP 1 @idUsuarioResuelto = id FROM dbo.uv_usuario WHERE correo = @correoNormalizado;
            END

            -- 8B: rol Docente para la persona (modos nuevo y usuario sin rol)
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NULL
            BEGIN
                EXEC dbo.usp_sincronizar_docente_interno
                    @idUsuario = @idUsuarioResuelto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
                IF @estadoResultado = 1
                    SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE idUsuario = @idUsuarioResuelto;
            END

            -- 8C: vinculo (revalida tipo y unicidad bajo UPDLOCK, HOLDLOCK)
            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_vincular_docente_programa_interno
                    @idDocente = @idDocenteResuelto,
                    @idPrograma = @idProgramaDefecto,
                    @idTipoVinculacion = @idTipoVinculacion,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            -- PASO 9: cierre respetando ownership
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    IF @estadoResultado = 1 COMMIT TRANSACTION; ELSE ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
            ELSE IF @savepointCreado = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 0
                    ROLLBACK TRANSACTION usp_vincular_docente_programa;
            END
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0 ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_vincular_docente_programa;
        END

        -- Transaccion externa doomed: no nos pertenece, se propaga al propietario.
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

-- ---- usp_actualizar_coordinador (version anterior) ----
-- HU121: edita nombres, apellidos y correo de un coordinador de la facultad del decano ejecutor.
-- Fachada transaccional: valida RBAC y titularidad, y delega la escritura en usp_actualizar_datos_usuario_interno.
-- HU159 (decision de John 2026-11-05): tambien corrige el tipo y el numero de documento, opcionales (NULL conserva el
-- actual), con usp_corregir_documento_usuario_interno; si el documento cambia, el motivo es obligatorio y se audita
-- CORREGIR_DOCUMENTO_COORDINADOR con los valores anteriores y nuevos.
-- Devuelve idUsuario para que el backend sincronice la cuenta de identidad (y el username si cambio el documento).
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_coordinador]
(
    @idCoordinador      UNIQUEIDENTIFIER,
    @primerNombre       NVARCHAR(50),
    @segundoNombre      NVARCHAR(50) = NULL,
    @primerApellido     NVARCHAR(50),
    @segundoApellido    NVARCHAR(50) = NULL,
    @correo             NVARCHAR(100),
    @idFacultad         UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion   INT = NULL,
    @motivo                 NVARCHAR(500) = NULL
)
AS
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @idUsuarioCoordinador    UNIQUEIDENTIFIER = NULL;
    DECLARE @identidadAnterior       NVARCHAR(MAX) = NULL;
    DECLARE @documentoCambiado       BIT = 0;

    -- Control de ownership transaccional (ver docs/procedimiento-transacciones)
    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    -- Solo se hace ROLLBACK si hubo escritura. Un rechazo de negocio antes de escribir no necesita rollback,
    -- y SQL Server prohibe ROLLBACK dentro de INSERT ... EXEC (3915), que es como se consume este SP en las pruebas.
    DECLARE @mutacionRealizada          BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: correlacion y ejecutor presentes
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacion,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC (perfil DECANO) y titularidad sobre la facultad indicada
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutor,
                @codigoPerfilRequerido = 'DECANO',
                @idCorrelacion = @idCorrelacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutor,
                @idEntidadPadre = @idFacultad,
                @tipoEntidadPadre = 'FACULTAD',
                @idCorrelacion = @idCorrelacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: el coordinador existe y es de esa facultad (GEN_001 en ambos casos)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_coordinador_de_facultad_interno
                @idCoordinador = @idCoordinador,
                @idFacultad = @idFacultad,
                @idCorrelacion = @idCorrelacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: escritura dentro de una transaccion (propia o savepoint si el llamador ya tiene una)
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
                SAVE TRANSACTION usp_actualizar_coordinador;
                SET @savepointCreado = 1;
            END

            SELECT TOP 1 @idUsuarioCoordinador = idUsuario
            FROM dbo.uv_coordinador_identidad
            WHERE id = @idCoordinador;

            -- Documento: se valida antes de escribir (un rechazo no necesita ROLLBACK)
            SET @identidadAnterior = dbo.ufn_obtener_identidad_usuario_json(@idUsuarioCoordinador);
            EXEC dbo.usp_corregir_documento_usuario_interno
                @idUsuario = @idUsuarioCoordinador,
                @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                @numeroIdentificacion = @numeroIdentificacion,
                @motivo = @motivo,
                @idCorrelacion = @idCorrelacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @documentoCambiado = @documentoCambiado OUTPUT,
                @soloValidar = 1;

            IF @estadoResultado = 1
            EXEC dbo.usp_actualizar_datos_usuario_interno
                @idUsuario = @idUsuarioCoordinador,
                @primerNombre = @primerNombre,
                @segundoNombre = @segundoNombre,
                @primerApellido = @primerApellido,
                @segundoApellido = @segundoApellido,
                @correo = @correo,
                @idCorrelacion = @idCorrelacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1 AND @documentoCambiado = 1
            BEGIN
                EXEC dbo.usp_corregir_documento_usuario_interno
                    @idUsuario = @idUsuarioCoordinador,
                    @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @motivo = @motivo,
                    @idCorrelacion = @idCorrelacion,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT,
                    @documentoCambiado = @documentoCambiado OUTPUT;

                IF @estadoResultado = 1
                    EXEC dbo.usp_registrar_auditoria_identidad_interno
                        @idUsuario = @idUsuarioCoordinador,
                        @identidadAnterior = @identidadAnterior,
                        @motivo = @motivo,
                        @accion = 'CORREGIR_DOCUMENTO_COORDINADOR',
                        @tipoRecurso = 'Coordinador',
                        @idRecurso = @idCoordinador,
                        @ruta = N'/api/v1/decano/coordinadores/{id}',
                        @idUsuarioEjecutor = @idUsuarioEjecutor,
                        @idCorrelacion = @idCorrelacion;
            END

            IF @estadoResultado = 1
            BEGIN
                SET @mutacionRealizada = 1;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_005',
                    @p_param1 = 'Coordinador',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            END
        END

        -- PASO 5: cierre de la transaccion respetando el ownership
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1 OR @mutacionRealizada = 0
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
            IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @mutacionRealizada = 1
                ROLLBACK TRANSACTION usp_actualizar_coordinador;
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
            ROLLBACK TRANSACTION usp_actualizar_coordinador;
        END

        -- Transaccion externa condenada que no nos pertenece: se propaga la excepcion al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacion);
        SET @estadoResultado = 0;
    END CATCH

    -- Resultado unificado
    SELECT
        idCorrelacion           = @idCorrelacion,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idUsuario               = IIF(@estadoResultado = 1, @idUsuarioCoordinador, NULL);
END;
GO

IF OBJECT_ID(N'dbo.usp_validar_sesion_mismo_dia_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_sesion_mismo_dia_interno];
GO
IF OBJECT_ID(N'dbo.usp_validar_correo_institucional_personal_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_correo_institucional_personal_interno];
GO
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('VCE_008', 'SES_028', 'ASI_008', 'ERR_CODIGO_GRUPO_INVALIDO', 'ERR_RESPUESTA_RECLAMO_LONGITUD_INVALIDA');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('VCE_008', 'SES_028', 'ASI_008', 'ERR_CODIGO_GRUPO_INVALIDO', 'ERR_RESPUESTA_RECLAMO_LONGITUD_INVALIDA');
DELETE FROM dbo.CatalogoParametro
WHERE (grupo = 'RECLAMO' AND clave IN ('RESPUESTA_RECHAZO_LONGITUD_MINIMA', 'RESPUESTA_LONGITUD_MAXIMA'))
   OR (grupo = 'ASIGNATURA' AND clave = 'CREDITOS_MAXIMO');
GO
PRINT 'MIGRACION 43 DOWN OK';
GO
