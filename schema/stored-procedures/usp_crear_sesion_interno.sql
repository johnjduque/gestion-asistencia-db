USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

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
-- DEC-072/DEC-073 (PASO 2.6): una sesion que cruza la medianoche en la zona institucional se rechaza con SES_028, sin escribir.
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): DECLARE del CATCH a la cabecera, PASO n, IF con BEGIN/END, IIF en lugar de COALESCE sobre variables y grupo, periodo y
-- zona horaria por vistas uv_* (antes, las tablas); el correlativo con UPDLOCK y los INSERT siguen en las tablas.
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
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
    DECLARE @numeroSemana    INT;          -- BD-5: semana del periodo en que cae la sesion (no su numero de orden)
    DECLARE @codigoSesion    NVARCHAR(50);
    DECLARE @idEstadoPendiente UNIQUEIDENTIFIER;

    -- Ownership transaccional (propia o savepoint bajo transacción externa)
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;
    DECLARE @estadoTransaccionCatch INT;
    DECLARE @zona              NVARCHAR(100);

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

        -- PASO 2.6 (DEC-072/DEC-073): la sesion empieza y termina el mismo dia en la zona institucional (SES_028)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_mismo_dia_interno
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
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

        -- PASO 3.1: correlativo bajo bloqueo (COALESCE sobre agregacion, permitido), semana del periodo e insercion
        IF @estadoResultado = 1
        BEGIN
            SELECT @numeroSiguiente = COALESCE(MAX(numero), 0) + 1
            FROM [dbo].[Sesion] WITH (UPDLOCK, HOLDLOCK)
            WHERE grupo = @idGrupoDefecto;

            -- BD-5: numeroSemana = semana del PERIODO (bloques de 7 dias desde fechaInicio, como el generador: SES-GEN-01 B2b) segun la fecha
            -- LOCAL institucional del inicio de la sesion; antes se escribia el numero de orden de la sesion (una extraordinaria del 5-dic
            -- salia en la semana 11 en vez de la 18). Minimo 1 (una fecha anterior al inicio del periodo cae en la semana 1).
            -- Zona horaria institucional del catalogo (por defecto, SA Pacific Standard Time)
            SELECT TOP 1 @zona = valor FROM dbo.uv_parametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1;
            SET @zona = IIF(@zona IS NULL, 'SA Pacific Standard Time', @zona);

            SELECT @numeroSemana = IIF(DATEDIFF(DAY, pa.fechaInicio, f.fechaLocal) < 0, 1, DATEDIFF(DAY, pa.fechaInicio, f.fechaLocal) / 7 + 1)
            FROM dbo.uv_grupo_registro g
            INNER JOIN dbo.uv_periodo_academico_fechas pa ON pa.id = g.idPeriodoAcademico
            CROSS APPLY (SELECT fechaLocal = CAST(CAST(@fechaHoraInicio AS DATETIME2) AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE)) f
            WHERE g.id = @idGrupoDefecto;
            SET @numeroSemana = IIF(@numeroSemana IS NULL, @numeroSiguiente, @numeroSemana);

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
                @numeroSemana,
                @idGrupoDefecto,
                @fechaHoraInicio,
                @fechaHoraFin,
                @procedenciaTemporal
            );

            INSERT INTO dbo.SesionSolicitud (sesion, idEstado, usuarioSolicitante, fechaSolicitudUtc, idCorrelacion)
            VALUES (@idNuevoSesion, @idEstadoPendiente, @idUsuarioEjecutorDefecto, SYSUTCDATETIME(), @idCorrelacionDefecto);
        END

        -- PASO 4: cierre de la transaccion propia (el rechazo por solape no escribe)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                COMMIT TRANSACTION;
            END
            ELSE IF XACT_STATE() <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END

        -- PASO 5: mensaje de exito (SES_022)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_022', @p_param1 = @idNuevoSesion, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- PASO 6: captura centralizada de excepciones y reversión respetando ownership transaccional
        SET @estadoTransaccionCatch = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
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
