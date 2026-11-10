-- ============================================================================
-- MIGRACION UP 32: CULM-001 / DEC-065 (5) - registro compuesto en una sola transaccion: decano + facultad (administrador) y coordinador + programa (decano)
-- Crea usp_crear_decano_interno y usp_crear_coordinador_interno (nucleos persona + rol, sin control transaccional propio), modifica (CREATE OR ALTER)
-- usp_crear_decano y usp_crear_coordinador para que deleguen en ellos conservando firma y comportamiento, crea usp_crear_decano_con_facultad y
-- usp_crear_coordinador_con_programa y concede EXECUTE de estos dos al rol runtime. No cambia tablas ni mensajes. Idempotente. Down: 32_..._down.sql.
-- ============================================================================
PRINT 'MIGRACION 32 UP: registro compuesto decano + facultad y coordinador + programa';
GO
-- ---- schema/stored-procedures/usp_crear_decano_interno.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_crear_decano_interno]
-- CULM-001 / DEC-065 (5): nucleo de creacion de persona + rol Decano, extraido de usp_crear_decano para componerlo con la facultad
-- (usp_crear_decano_con_facultad). SIN control transaccional propio: DEBE invocarse dentro de la transaccion (o savepoint) del llamador.
-- No valida correlacion, RBAC ni ambito (lo hace el llamador). Ejecuta, en orden:
--   1. DEC_020 si la persona ya es decano activo (no escribe nada).
--   2. Reutiliza el usuario existente (correo o identificacion) o lo crea con usp_sincronizar_usuario_interno.
--   3. Crea la fila Decano si la persona no la tenia y, si recibe @idFacultad, la deja como titular de esa facultad.
-- @idDecano es de entrada/salida: NULL genera el identificador; al terminar con exito contiene el id del decano.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_decano_interno]
(
    @idDecano                UNIQUEIDENTIFIER OUTPUT,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @password                NVARCHAR(500),
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioCreado      UNIQUEIDENTIFIER;
    DECLARE @idTipoIdCC           UNIQUEIDENTIFIER;
BEGIN
    SET NOCOUNT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    -- PASO 1 (D.9-a, F-ADM-024): la persona ya es decano activo
    SELECT TOP 1 @idUsuarioCreado = id
    FROM [dbo].[uv_usuario]
    WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = CAST(@numeroIdentificacion AS VARCHAR(20));

    IF @idUsuarioCreado IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.Decano d WHERE d.usuario = @idUsuarioCreado AND d.estado = 1)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'DEC_020',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 2: gestion reactiva de usuario (consulta en uv_usuario y delegacion a usp_sincronizar_usuario_interno)
    IF @estadoResultado = 1 AND @idUsuarioCreado IS NULL
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

    -- PASO 3: asignacion reactiva del rol Decano y adscripcion a la facultad
    IF @estadoResultado = 1
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.Decano WHERE usuario = @idUsuarioCreado)
        BEGIN
            IF @idDecano IS NULL
                SET @idDecano = NEWID();

            INSERT INTO dbo.Decano (id, usuario)
            VALUES (@idDecano, @idUsuarioCreado);
        END
        ELSE
        BEGIN
            SELECT TOP 1 @idDecano = id FROM dbo.Decano WHERE usuario = @idUsuarioCreado;
        END

        IF @idFacultad IS NOT NULL
        BEGIN
            UPDATE dbo.Facultad
            SET decano = @idDecano
            WHERE id = @idFacultad;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_004',
            @p_param1 = 'Decano',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
    END
END;
GO
GO
-- ---- schema/stored-procedures/usp_crear_coordinador_interno.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_crear_coordinador_interno]
-- CULM-001 / DEC-065 (5): nucleo de creacion de persona + rol Coordinador, extraido de usp_crear_coordinador para componerlo con el programa
-- (usp_crear_coordinador_con_programa). SIN control transaccional propio: DEBE invocarse dentro de la transaccion (o savepoint) del llamador.
-- No valida correlacion, RBAC, facultad ni titularidad (lo hace el llamador). Ejecuta, en orden:
--   1. Reutiliza el usuario existente (correo o identificacion) o lo crea con usp_sincronizar_usuario_interno.
--   2. Crea la fila Coordinador (con su facultad) si la persona no la tenia; si ya la tenia, solo completa la facultad cuando era NULL.
--   3. Si recibe @idPrograma, deja al coordinador como titular de ese programa.
-- @idCoordinador es de entrada/salida: NULL genera el identificador; al terminar con exito contiene el id del coordinador.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_coordinador_interno]
(
    @idCoordinador           UNIQUEIDENTIFIER OUTPUT,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @password                NVARCHAR(500),
    @idFacultad              UNIQUEIDENTIFIER,
    @idPrograma              UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioCreado      UNIQUEIDENTIFIER;
    DECLARE @idTipoIdCC           UNIQUEIDENTIFIER;
BEGIN
    SET NOCOUNT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    -- PASO 1: gestion reactiva de usuario (consulta en uv_usuario y delegacion a usp_sincronizar_usuario_interno)
    SELECT TOP 1 @idUsuarioCreado = id
    FROM [dbo].[uv_usuario]
    WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = @numeroIdentificacion;

    IF @idUsuarioCreado IS NULL
    BEGIN
        IF @idTipoIdIdentificacion IS NOT NULL
        BEGIN
            SET @idTipoIdCC = @idTipoIdIdentificacion;
        END
        ELSE
        BEGIN
            DECLARE @codTipoDocDefectoCoord NVARCHAR(50) = dbo.ufn_obtener_parametro_texto(NULL, 'IDENTIDAD', 'TIPO_IDENTIFICACION_DEFECTO');
            SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = @codTipoDocDefectoCoord ORDER BY id ASC;
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

    -- PASO 2: asignacion reactiva del rol Coordinador y adscripcion opcional al programa
    IF @estadoResultado = 1
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.Coordinador WHERE usuario = @idUsuarioCreado)
        BEGIN
            IF @idCoordinador IS NULL
            BEGIN
                SET @idCoordinador = NEWID();
            END

            -- HU121/HU122 (D2): el coordinador conserva su facultad aunque aun no tenga programa
            INSERT INTO dbo.Coordinador (id, usuario, facultad)
            VALUES (@idCoordinador, @idUsuarioCreado, @idFacultad);
        END
        ELSE
        BEGIN
            SELECT TOP 1 @idCoordinador = id FROM dbo.Coordinador WHERE usuario = @idUsuarioCreado;

            UPDATE dbo.Coordinador SET facultad = @idFacultad
            WHERE id = @idCoordinador AND facultad IS NULL;
        END

        IF @idPrograma IS NOT NULL
        BEGIN
            UPDATE dbo.Programa
            SET coordinador = @idCoordinador
            WHERE id = @idPrograma;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_004',
            @p_param1 = 'Coordinador',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
    END
END;
GO
GO
-- ---- schema/stored-procedures/usp_crear_decano.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

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
GO
-- ---- schema/stored-procedures/usp_crear_coordinador.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

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
GO
-- ---- schema/stored-procedures/usp_crear_decano_con_facultad.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

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
GO
-- ---- schema/stored-procedures/usp_crear_coordinador_con_programa.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

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
GO
-- ---- schema/security/rol_asistencias_runtime_mrm_registro_compuesto.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (5): permisos del registro compuesto. EXECUTE sobre los dos SP publicos nuevos (los nucleos usp_*_interno no se conceden).
-- Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_crear_decano_con_facultad', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_crear_decano_con_facultad] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_crear_coordinador_con_programa', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_crear_coordinador_con_programa] TO [rol_asistencias_runtime];
GO
PRINT 'MIGRACION 32 UP OK';
GO
