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
