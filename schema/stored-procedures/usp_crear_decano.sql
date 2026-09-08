USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_decano]
(
    @id                      UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50) = NULL,
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50) = NULL,
    @correo                  NVARCHAR(100),
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @nombreFacultad          NVARCHAR(150) = NULL,
    @password                NVARCHAR(500) = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER = NULL,
    @idDecanoResultado       UNIQUEIDENTIFIER = NULL OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) = NULL OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) = NULL OUTPUT,
    @estadoResultado         BIT = 1 OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET @estadoResultado = 1;
    SET @mensajeUsuarioResultado = '';
    SET @mensajeTecnicoResultado = '';

    DECLARE @decanoId UNIQUEIDENTIFIER = ISNULL(@id, NEWID());
    DECLARE @usuarioId UNIQUEIDENTIFIER = NEWID();
    DECLARE @tipoId UNIQUEIDENTIFIER;
    DECLARE @facultadDestinoId UNIQUEIDENTIFIER = @idFacultad;

    BEGIN TRY
        -- 1. Validar facultad si se envia nombre
        IF @facultadDestinoId IS NULL AND @nombreFacultad IS NOT NULL AND TRIM(@nombreFacultad) <> ''
        BEGIN
            SELECT TOP 1 @facultadDestinoId = id
            FROM dbo.Facultad
            WHERE LOWER(nombre) = LOWER(TRIM(@nombreFacultad))
               OR LOWER(nombre) LIKE LOWER(CONCAT('%', TRIM(@nombreFacultad), '%'));
        END

        -- 2. Validar unicidad de documento
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroIdentificacion)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = CONCAT('Ya existe un usuario registrado con el documento ', @numeroIdentificacion, '.');
            SET @mensajeTecnicoResultado = 'Unicidad violada en dbo.Usuario.numeroIdentificacion.';
        END

        -- 3. Validar unicidad de correo
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.Usuario WHERE LOWER(correo) = LOWER(LTRIM(RTRIM(@correo))))
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = CONCAT('El correo electrónico ', @correo, ' ya está registrado en el sistema.');
            SET @mensajeTecnicoResultado = 'Unicidad violada en dbo.Usuario.correo.';
        END

        -- 4. Insercion
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @tipoId = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC';
            IF @tipoId IS NULL SELECT TOP 1 @tipoId = id FROM dbo.TipoIdentificacion;

            DECLARE @passDecano NVARCHAR(500) = ISNULL(NULLIF(TRIM(@password), ''), '{bcrypt}.dj59Y3JfLR3I1usSJO1OGyHvEghbMXCAH.E.kXVapPDcO');

            INSERT INTO dbo.Usuario (
                id, tipoIdIdentificacion, numeroIdentificacion,
                primerApellido, segundoApellido, primerNombre, segundoNombre,
                correo, correoConfirmado, estado, password
            )
            VALUES (
                @usuarioId, @tipoId, @numeroIdentificacion,
                LTRIM(RTRIM(@primerApellido)), ISNULL(LTRIM(RTRIM(@segundoApellido)), ''),
                LTRIM(RTRIM(@primerNombre)), ISNULL(LTRIM(RTRIM(@segundoNombre)), ''),
                LOWER(LTRIM(RTRIM(@correo))), 1, 1, @passDecano
            );

            INSERT INTO dbo.Decano (id, usuario)
            VALUES (@decanoId, @usuarioId);

            IF @facultadDestinoId IS NOT NULL
            BEGIN
                UPDATE dbo.Facultad
                SET decano = @decanoId
                WHERE id = @facultadDestinoId;
            END

            SET @idDecanoResultado = @decanoId;
            SET @mensajeUsuarioResultado = CONCAT('Decano ', @primerNombre, ' ', @primerApellido, ' registrado exitosamente.');
            SET @mensajeTecnicoResultado = 'Decano registrado en dbo.Decano.';
        END

    END TRY
    BEGIN CATCH
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Error al registrar al decano en la base de datos.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    SELECT
        idCorrelacion = @idCorrelacion,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado,
        @decanoId AS idDecano,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
