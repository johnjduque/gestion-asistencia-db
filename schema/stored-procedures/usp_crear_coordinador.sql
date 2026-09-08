USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_coordinador]
(
    @id                      UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50) = NULL,
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50) = NULL,
    @correo                  NVARCHAR(100),
    @idPrograma              UNIQUEIDENTIFIER,
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @password                NVARCHAR(500) = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER = NULL,
    @idCoordinadorResultado  UNIQUEIDENTIFIER = NULL OUTPUT,
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

    DECLARE @coordId UNIQUEIDENTIFIER = ISNULL(@id, NEWID());
    DECLARE @usuarioId UNIQUEIDENTIFIER = NEWID();
    DECLARE @tipoId UNIQUEIDENTIFIER;

    BEGIN TRY
        -- 1. Validar programa académico
        IF NOT EXISTS (SELECT 1 FROM dbo.Programa WHERE id = @idPrograma)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'El programa académico especificado no existe.';
            SET @mensajeTecnicoResultado = 'FK @idPrograma no encontrada en dbo.Programa.';
        END

        -- 2. Validar pertenencia a la facultad si se envía @idFacultad (validación de ámbito de decano)
        IF @estadoResultado = 1 AND @idFacultad IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.Programa WHERE id = @idPrograma AND facultad = @idFacultad)
            BEGIN
                SET @estadoResultado = 0;
                SET @mensajeUsuarioResultado = 'Acceso denegado: El programa académico no pertenece a su facultad.';
                SET @mensajeTecnicoResultado = 'Violación de ámbito de Decanatura.';
            END
        END

        -- 3. Validar unicidad de identificación y correo
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.Usuario WHERE numeroIdentificacion = @numeroIdentificacion)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = CONCAT('Ya existe un usuario registrado con el documento ', @numeroIdentificacion, '.');
            SET @mensajeTecnicoResultado = 'Unicidad violada en dbo.Usuario.numeroIdentificacion.';
        END

        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.Usuario WHERE LOWER(correo) = LOWER(LTRIM(RTRIM(@correo))))
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = CONCAT('El correo electrónico ', @correo, ' ya está registrado en el sistema.');
            SET @mensajeTecnicoResultado = 'Unicidad violada en dbo.Usuario.correo.';
        END

        -- Inserción
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @tipoId = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC';
            IF @tipoId IS NULL SELECT TOP 1 @tipoId = id FROM dbo.TipoIdentificacion;

            -- Inserción en dbo.Usuario con hash activo
            DECLARE @passCoordinador NVARCHAR(500) = ISNULL(NULLIF(TRIM(@password), ''), '{bcrypt}$2a$10$uNkTXVK.dj59Y3JfLR3I1usSJO1OGyHvEghbMXCAH.E.kXVapPDcO');

            INSERT INTO dbo.Usuario (
                id, tipoIdIdentificacion, numeroIdentificacion,
                primerApellido, segundoApellido, primerNombre, segundoNombre,
                correo, correoConfirmado, estado, password
            )
            VALUES (
                @usuarioId, @tipoId, @numeroIdentificacion,
                LTRIM(RTRIM(@primerApellido)), ISNULL(LTRIM(RTRIM(@segundoApellido)), ''),
                LTRIM(RTRIM(@primerNombre)), ISNULL(LTRIM(RTRIM(@segundoNombre)), ''),
                LOWER(LTRIM(RTRIM(@correo))), 1, 1, @passCoordinador
            );

            -- Inserción en dbo.Coordinador
            INSERT INTO dbo.Coordinador (id, usuario)
            VALUES (@coordId, @usuarioId);

            -- Asignación de coordinador en dbo.Programa
            UPDATE dbo.Programa
            SET coordinador = @coordId
            WHERE id = @idPrograma;

            SET @idCoordinadorResultado = @coordId;
            SET @mensajeUsuarioResultado = CONCAT('Coordinador ', @primerNombre, ' ', @primerApellido, ' registrado y asignado exitosamente al programa.');
            SET @mensajeTecnicoResultado = 'Coordinador registrado en dbo.Coordinador y asignado en dbo.Programa.';
        END

    END TRY
    BEGIN CATCH
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Error al registrar al coordinador en la base de datos.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    SELECT
        idCorrelacion = @idCorrelacion,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado,
        @coordId AS idCoordinador,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
