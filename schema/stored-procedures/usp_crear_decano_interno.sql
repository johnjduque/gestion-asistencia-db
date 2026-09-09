USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_decano_interno]
(
    @idDecano                UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @idFacultad              UNIQUEIDENTIFIER,
    @nombreFacultad          NVARCHAR(150),
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDecanoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDecano, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idFacultadDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idFacultad, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @primerNombreDefecto   NVARCHAR(50)     = TRIM(@primerNombre);
    DECLARE @segundoNombreDefecto  NVARCHAR(50)     = TRIM(@segundoNombre);
    DECLARE @primerApellidoDefecto NVARCHAR(50)     = TRIM(@primerApellido);
    DECLARE @segundoApellidoDefecto NVARCHAR(50)    = TRIM(@segundoApellido);
    DECLARE @correoDefecto         NVARCHAR(100)    = LOWER(TRIM(@correo));
    DECLARE @nombreFacultadDefecto NVARCHAR(150)    = TRIM(@nombreFacultad);
    DECLARE @passwordDefecto       NVARCHAR(500)    = TRIM(@password);

    DECLARE @idUsuarioNuevo  UNIQUEIDENTIFIER = NEWID();
    DECLARE @idTipoIdCC      UNIQUEIDENTIFIER;
    DECLARE @hashPassword    NVARCHAR(500);

BEGIN
    SET NOCOUNT ON;
    SET @estadoResultado = 1;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');

    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Resolver facultad destino si se suministra el nombre
        IF @estadoResultado = 1 AND @idFacultadDefecto IS NULL AND @nombreFacultadDefecto IS NOT NULL AND @nombreFacultadDefecto <> ''
        BEGIN
            SELECT TOP 1 @idFacultadDefecto = id
            FROM dbo.Facultad
            WHERE LOWER(nombre) = LOWER(@nombreFacultadDefecto)
               OR LOWER(nombre) LIKE LOWER(CONCAT('%', @nombreFacultadDefecto, '%'))
            ORDER BY nombre ASC;
        END

        -- PASO 3: Validar unicidad de número de identificación
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroIdentificacion)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_006',
                    @p_param1 = 'UsuarioIdentificacion',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Validar unicidad de correo
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE LOWER(TRIM(correo)) = @correoDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_006',
                    @p_param1 = 'UsuarioCorreo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: Registro atómico transaccional de Usuario, Decano y asignación a Facultad
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC' ORDER BY id ASC;
            IF @idTipoIdCC IS NULL
            BEGIN
                SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion ORDER BY id ASC;
            END

            -- Hash BCrypt corregido y completo con sal válida
            SET @hashPassword = CASE WHEN @passwordDefecto IS NOT NULL AND @passwordDefecto <> '' THEN @passwordDefecto ELSE '{bcrypt}$2a$10$uNkTXVK.dj59Y3JfLR3I1usSJO1OGyHvEghbMXCAH.E.kXVapPDcO' END;

            BEGIN TRANSACTION;

            INSERT INTO dbo.Usuario (
                id, tipoIdIdentificacion, numeroIdentificacion,
                primerApellido, segundoApellido, primerNombre, segundoNombre,
                correo, correoConfirmado, estado, password
            )
            VALUES (
                @idUsuarioNuevo,
                @idTipoIdCC,
                @numeroIdentificacion,
                @primerApellidoDefecto,
                CASE WHEN @segundoApellidoDefecto IS NOT NULL THEN @segundoApellidoDefecto ELSE '' END,
                @primerNombreDefecto,
                CASE WHEN @segundoNombreDefecto IS NOT NULL THEN @segundoNombreDefecto ELSE '' END,
                @correoDefecto,
                1, 1, @hashPassword
            );

            INSERT INTO dbo.Decano (id, usuario)
            VALUES (@idDecanoDefecto, @idUsuarioNuevo);

            IF @idFacultadDefecto IS NOT NULL
            BEGIN
                UPDATE dbo.Facultad
                SET decano = @idDecanoDefecto
                WHERE id = @idFacultadDefecto;
            END

            COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Decano',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
