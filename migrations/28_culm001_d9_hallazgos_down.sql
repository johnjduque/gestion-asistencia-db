-- ============================================================================
-- MIGRACION DOWN 28: CULM-001 D.9-a - retira los cambios de BD de los hallazgos medios (CONTRACT D §11.2, §14.2)
--   1. Restaura el texto anterior a D.9 (el de B2, D.1-D.7 y la base) de usp_reintentar_notificacion_saliente_interno,
--      usp_consultar_plantilla_notificacion_activa, usp_crear_periodo_academico, usp_consultar_sesiones_facultad_paginado y
--      usp_validar_cruce_horario_estudiante_interno. usp_crear_decano vuelve al texto de D.5 (la 28 va despues de la 24, §14.2).
--   2. DROP de usp_consultar_periodos_academicos_paginado, usp_consultar_grupo_facultad_detalle y usp_validar_acceso_reporte_grupo.
--   3. Borra los mensajes DEC_020, NTF_020 y NTF_021. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 28 DOWN: restaura los SP anteriores a D.9';
GO
-- ---- schema/stored-procedures/usp_reintentar_notificacion_saliente_interno.sql (texto anterior a D.9)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_reintentar_notificacion_saliente_interno]
-- Capacidad: Monitor de Cola Outbox (TD-069)
-- Ambito: Operacion atomica de transicion de estado a PENDIENTE para reintento manual.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_reintentar_notificacion_saliente_interno]
(
    @idNotificacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT            OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado         = 1;

    BEGIN TRY
        -- 1. Validar existencia
        IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @idNotificacion)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' IdNotificacion: ', @idNotificacion, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            RETURN;
        END

        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_reintentar_notif_saliente;
            SET @savepointCreado = 1;
        END

        -- 2. Validar estado actual con bloqueo protector (UPDLOCK, HOLDLOCK)
        DECLARE @codigoEstado VARCHAR(30);
        SELECT @codigoEstado = e.codigo
        FROM dbo.NotificacionSaliente n WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado
        WHERE n.id = @idNotificacion;

        IF @codigoEstado NOT IN ('FALLIDA_DEFINITIVA', 'FALLIDA_REINTENTABLE')
        BEGIN
            IF @savepointCreado = 1 AND XACT_STATE() = 1
                ROLLBACK TRANSACTION sp_reintentar_notif_saliente;
            ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_008',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Estado actual: ', @codigoEstado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            RETURN;
        END

        -- 3. Resetear parametros y pasar a PENDIENTE
        DECLARE @idEstadoPendiente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE');

        UPDATE dbo.NotificacionSaliente
        SET idEstado         = @idEstadoPendiente,
            intentos         = 0,
            proximoIntentoEn = SYSUTCDATETIME(),
            reservadoHasta   = NULL,
            reservadoPor     = NULL,
            codigoError      = NULL,
            detalleError     = NULL
        WHERE id = @idNotificacion;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'NTF_007',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' IdNotificacion: ', @idNotificacion, ' Correlacion: ', @idCorrelacionDefecto);

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sp_reintentar_notif_saliente;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_plantilla_notificacion_activa.sql (texto anterior a D.9)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_plantilla_notificacion_activa]
-- Capacidad: Plantillas de Notificacion (NOTIF-002A)
-- Ambito: Fachada publica tecnica para consultar la plantilla activa de un tipo
--         y sus marcadores declarados. Excepcion RBAC documentada (solo runtime,
--         igual que NOTIF-001 D9).
-- Salida:
--   Result set 1 (canonico): (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
--   Result set 2 (cuando estadoResultado=1): 0 o 1 fila (version, asunto, cuerpo)
--   Result set 3 (cuando estadoResultado=1): lista de marcadores (marcador, obligatorio)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_plantilla_notificacion_activa]
(
    @tipo          NVARCHAR(100)    = NULL,
    @idioma        CHAR(2)          = 'es',
    @idCorrelacion UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tipoDef              VARCHAR(60)      = NULL;
    DECLARE @idiomaDef            CHAR(2)          = COALESCE(NULLIF(LOWER(TRIM(@idioma)), ''), 'es');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    BEGIN TRY
        -- 1. Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar tipo (3..60 caracteres, A-Z0-9_)
        IF @estadoResultado = 1
        BEGIN
            DECLARE @tipoRaw NVARCHAR(100) = UPPER(TRIM(@tipo));
            IF @tipoRaw IS NULL OR LEN(@tipoRaw) < 3 OR LEN(@tipoRaw) > 60 OR @tipoRaw LIKE '%[^A-Z0-9_]%'
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Tipo de plantilla invalido (3-60 caracteres A-Z, 0-9, _). Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @tipoDef = CAST(@tipoRaw AS VARCHAR(60));
            END
        END

        -- 3. Preparar mensaje de exito GEN_003
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003',
                @p_param1 = 'PlantillaNotificacion',
                @p_param2 = @tipoDef,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
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

    -- Result set 1: tupla canonica
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;

    -- Result sets 2 y 3: plantilla y marcadores cuando la validacion fue exitosa
    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_consultar_plantilla_notificacion_activa_interno
            @tipo = @tipoDef,
            @idioma = @idiomaDef;
    END
END;
GO
GO
-- ---- schema/stored-procedures/usp_crear_periodo_academico.sql (texto anterior a D.9)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU096: crea un periodo academico en la institucion del ejecutor (solo ADMINISTRADOR: el periodo es unico para
-- toda la institucion; DECANO y COORDINADOR solo lo consultan). Reglas:
--   * nombre obligatorio y unico (sin distinguir mayusculas) dentro de la institucion (PER_003).
--   * fechaInicio < fechaFin (PER_002).
--   * codigo y anio se derivan de fechaInicio: anio = YEAR(fechaInicio); codigo = anio * 10 + (1 si inicia en
--     enero-junio, 2 si inicia en julio-diciembre), igual que la semilla (2026-2 => 20262).
-- Concurrencia: los periodos de la institucion se bloquean (UPDLOCK, HOLDLOCK) mientras se valida la unicidad.
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_periodo_academico]
(
    @idPeriodo               UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @fechaInicio             DATETIME2,
    @fechaFin                DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPeriodoDefecto         UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPeriodo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidDefecto              UNIQUEIDENTIFIER = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER);
    DECLARE @nombreDef                NVARCHAR(50)     = TRIM(@nombre);
    DECLARE @idInstitucion            UNIQUEIDENTIFIER;
    DECLARE @conteoBloqueo            INT;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
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
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Resolver ambito del ejecutor (usp_resolver_institucion_gestor_periodo_interno)
        IF @estadoResultado = 1
            EXEC dbo.usp_resolver_institucion_gestor_periodo_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idCorrelacion = @idCorrelacionDefecto,
                @idInstitucion = @idInstitucion OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 4: Validacion de negocio (GEN_002)
        IF @estadoResultado = 1 AND (@idPeriodoDefecto = @guidDefecto OR @nombreDef IS NULL OR @nombreDef = '')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Validacion de negocio (PER_002)
        IF @estadoResultado = 1 AND (@fechaInicio IS NULL OR @fechaFin IS NULL OR @fechaInicio >= @fechaFin)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PER_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Escritura transaccional
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
                SAVE TRANSACTION sp_crear_periodo;
                SET @savepointCreado = 1;
            END

            SELECT @conteoBloqueo = COUNT(1)
            FROM dbo.PeriodoAcademico pa WITH (UPDLOCK, HOLDLOCK)
            WHERE pa.institucion = @idInstitucion;

            IF EXISTS (SELECT 1 FROM dbo.PeriodoAcademico pa WHERE pa.id = @idPeriodoDefecto)
               OR EXISTS (SELECT 1 FROM dbo.PeriodoAcademico pa WHERE pa.institucion = @idInstitucion AND LOWER(pa.nombre) = LOWER(@nombreDef))
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PER_003',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
                VALUES (
                    @idPeriodoDefecto, @idInstitucion, @nombreDef,
                    YEAR(@fechaInicio) * 10 + IIF(MONTH(@fechaInicio) <= 6, 1, 2),
                    CAST(@fechaInicio AS DATE), CAST(@fechaFin AS DATE), YEAR(@fechaInicio)
                );

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004', @p_param1 = 'Periodo academico',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1 COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1 ROLLBACK TRANSACTION;
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
            ROLLBACK TRANSACTION sp_crear_periodo;
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
GO
-- ---- schema/stored-procedures/usp_consultar_sesiones_facultad_paginado.sql (texto anterior a D.9)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_facultad_paginado (HU145 cronograma de sesiones de la facultad)
--
-- Sesiones programadas en los grupos de la facultad del decano ejecutor, ordenadas por fecha, con filtro
-- opcional por rango de fechas (dias completos, ambos inclusive) y programa.
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de paginacion se propagan con THROW (DBCODE=PAG_001).
-- Ambito: uv_auth_sesion / uv_auth_grupo (fail-closed) restringidas a los programas de las facultades cuyo
-- decano es el ejecutor.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_facultad_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @fechaDesde         DATE             = NULL,
    @fechaHasta         DATE             = NULL,
    @idPrograma         UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = TRY_CAST(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO') AS INT);
    DECLARE @inicio               DATETIME2 = CAST(@fechaDesde AS DATETIME2);
    DECLARE @finExclusivo         DATETIME2 = DATEADD(DAY, 1, CAST(@fechaHasta AS DATETIME2));
    DECLARE @offset               INT;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
           AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
                OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PAG_001',
                @p_param1 = @numeroPagina,
                @p_param2 = @tamanoPagina,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        SET @offset = (@numeroPagina - 1) * @tamanoPagina;

        EXEC dbo.usp_establecer_contexto_usuario_ejecutor
            @p_idUsuario = @idUsuarioDefecto;

        SELECT
            s.id,
            s.nombre,
            s.codigo,
            s.numeroSemana,
            s.fechaHoraInicio,
            s.fechaHoraFin,
            s.idGrupo,
            s.codigoGrupo,
            s.nombreGrupo,
            g.idAsignatura,
            g.nombreAsignatura,
            COUNT(*) OVER()         AS totalRegistros,
            -- CULM-001 B.1 (CONTRACT §2.7.7): estado de la sesion desde uv_sesion_estado
            se.estaCancelada,
            se.codigoTipoCancelacion,
            se.motivoCancelacion,
            se.nombreDiaFestivo,
            se.fechaCancelacionUtc
        FROM dbo.uv_auth_sesion s
        INNER JOIN dbo.uv_sesion_estado se ON se.idSesion = s.id
        INNER JOIN dbo.uv_auth_grupo g ON g.id = s.idGrupo
        -- CULM-001 B2NM (R5): 1 fila por sesion; el ambito es un EXISTS sobre los programas del grupo en la facultad del decano.
        WHERE EXISTS (SELECT 1
                      FROM dbo.uv_grupo_programa gp
                      INNER JOIN dbo.uv_programa x ON x.id = gp.idPrograma
                      WHERE gp.idGrupo = s.idGrupo
                        AND x.idFacultad IN (SELECT f.id FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano WHERE d.usuario = @idUsuarioDefecto)
                        AND (@idPrograma IS NULL OR x.id = @idPrograma))
          AND (@inicio IS NULL OR s.fechaHoraInicio >= @inicio)
          AND (@finExclusivo IS NULL OR s.fechaHoraInicio < @finExclusivo)
        ORDER BY s.fechaHoraInicio ASC, s.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
        THROW;
    END CATCH;
END;
GO
GO
-- ---- schema/stored-procedures/usp_validar_cruce_horario_estudiante_interno.sql (texto anterior a D.9)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_cruce_horario_estudiante_interno]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @nombreGrupoConflicto NVARCHAR(200);
    DECLARE @diaConflicto         NVARCHAR(50);

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

        -- PASO 2: Validaciones previas de existencia de estudiante y grupo
        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno 
                @idEstudiante = @idEstudianteDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Detección de colisión / cruce de horario del estudiante
        IF @estadoResultado = 1 
        BEGIN
            SELECT TOP 1 
                @estadoResultado = 0,
                @nombreGrupoConflicto = gExistente.nombre,
                @diaConflicto = hNuevo.nombreDia
            FROM dbo.uv_horario hNuevo
            INNER JOIN dbo.uv_horario hExistente ON hNuevo.idDia = hExistente.idDia 
                AND hNuevo.idPeriodoAcademico = hExistente.idPeriodoAcademico
            INNER JOIN dbo.uv_estudiante_grupo eg ON hExistente.idGrupo = eg.idGrupo
            INNER JOIN dbo.uv_grupo gExistente ON eg.idGrupo = gExistente.id
            WHERE hNuevo.idGrupo = @idGrupoDefecto
                AND eg.idEstudiante = @idEstudianteDefecto
                AND hNuevo.idGrupo <> hExistente.idGrupo
                AND hNuevo.horaInicio < hExistente.horaFin
                AND hNuevo.horaFin > hExistente.horaInicio;

            IF @estadoResultado = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'HOR_001',
                    @p_param1 = @idGrupoDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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
GO
-- ---- schema/stored-procedures/usp_crear_decano.sql (texto de D.5, anterior a D.9)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

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

    DECLARE @idUsuarioCreado Uniqueidentifier;
    DECLARE @idTipoIdCC      UNIQUEIDENTIFIER;

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

        -- PASO 3: GESTIÓN REACTIVA DE USUARIO (Consulta en uv_usuario y delegación a usp_sincronizar_usuario_interno)
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

            SELECT TOP 1 @idUsuarioCreado = id
            FROM [dbo].[uv_usuario]
            WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = CAST(@numeroIdentificacion AS VARCHAR(20));

            IF @idUsuarioCreado IS NULL
            BEGIN
                IF @idTipoIdIdentificacion IS NOT NULL
                BEGIN
                    SET @idTipoIdCC = @idTipoIdIdentificacion;
                END
                ELSE
                BEGIN
                    DECLARE @codTipoDocDefectoDec NVARCHAR(50) = dbo.ufn_obtener_parametro_texto(NULL, 'IDENTIDAD', 'TIPO_IDENTIFICACION_DEFECTO');
                    SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = @codTipoDocDefectoDec ORDER BY id ASC;
                    IF @idTipoIdCC IS NULL SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion ORDER BY id ASC;
                END

                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdCC,
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
                BEGIN
                    SELECT TOP 1 @idUsuarioCreado = id
                    FROM [dbo].[uv_usuario]
                    WHERE correo = LOWER(TRIM(@correo));
                END
            END
        END

        -- PASO 4: Asignación reactiva de rol Decano y adscripción a la Facultad
        IF @estadoResultado = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.Decano WHERE usuario = @idUsuarioCreado)
            BEGIN
                IF @idDecanoDefecto IS NULL
                    SET @idDecanoDefecto = NEWID();

                INSERT INTO dbo.Decano (id, usuario)
                VALUES (@idDecanoDefecto, @idUsuarioCreado);
            END
            ELSE
            BEGIN
                SELECT TOP 1 @idDecanoDefecto = id FROM dbo.Decano WHERE usuario = @idUsuarioCreado;
            END

            IF @idFacultadDefecto IS NOT NULL
            BEGIN
                UPDATE dbo.Facultad
                SET decano = @idDecanoDefecto
                WHERE id = @idFacultadDefecto;
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Decano',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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
GO
IF OBJECT_ID(N'dbo.usp_consultar_periodos_academicos_paginado', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_periodos_academicos_paginado];
GO
IF OBJECT_ID(N'dbo.usp_consultar_grupo_facultad_detalle', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_grupo_facultad_detalle];
GO
IF OBJECT_ID(N'dbo.usp_validar_acceso_reporte_grupo', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_validar_acceso_reporte_grupo];
GO
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo IN ('DEC_020', 'NTF_020', 'NTF_021');
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo IN ('DEC_020', 'NTF_020', 'NTF_021');
GO
