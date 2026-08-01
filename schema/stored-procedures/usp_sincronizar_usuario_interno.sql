USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    PROCEDURE [dbo].[usp_sincronizar_usuario_interno]
(
    @tipoIdIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion INT,
    @primerApellido NVARCHAR(255),
    @segundoApellido NVARCHAR(255),
    @primerNombre NVARCHAR(255),
    @segundoNombre NVARCHAR(255),
    @correo NVARCHAR(255),
    @password NVARCHAR(MAX),
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS

    -- 1. Estandarizaci??n e inicializaci??n de Variables Defecto
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))));
    DECLARE @tipoIdIdentificacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@tipoIdIdentificacion, '00000000-0000-0000-0000-000000000000'))));
    
    DECLARE @numeroIdentificacionDefecto INT = UPPER(LTRIM(RTRIM(ISNULL(@numeroIdentificacion, 0))));
    DECLARE @primerApellidoDefecto NVARCHAR(255) = UPPER(LTRIM(RTRIM(ISNULL(@primerApellido,''))));
    DECLARE @segundoApellidoDefecto NVARCHAR(255) = UPPER(LTRIM(RTRIM(ISNULL(@segundoApellido,''))));
    DECLARE @primerNombreDefecto NVARCHAR(255) = UPPER(LTRIM(RTRIM(ISNULL(@primerNombre,''))));
    DECLARE @segundoNombreDefecto NVARCHAR(255) = UPPER(LTRIM(RTRIM(ISNULL(@segundoNombre,''))));
    DECLARE @correoDefecto NVARCHAR(255) = LOWER(LTRIM(RTRIM(ISNULL(@correo,''))));
    
    -- El password por defecto es el n??mero de identificaci??n
    DECLARE @passwordDefecto NVARCHAR(MAX) = UPPER(LTRIM(RTRIM(ISNULL(@password, CAST(@numeroIdentificacionDefecto AS NVARCHAR(MAX))))));

    -- Inicializaci??n de respuesta
    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        --------------------------------------------------------------------
        -- 2. VALIDACI??N DE CORRELACI??N
        --------------------------------------------------------------------
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        --------------------------------------------------------------------
        -- VALIDACIONES DE REGLAS DE NEGOCIO (Sub-procedimientos)
        --------------------------------------------------------------------
        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_tipo_identificacion_exista_por_id_interno
                @idTipoId = @tipoIdIdentificacionDefecto, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_unicidad_usuario_interno 
                @tipoIdIdentificacion = @tipoIdIdentificacionDefecto, @numeroIdentificacion = @numeroIdentificacionDefecto, @correo = @correoDefecto, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        --------------------------------------------------------------------
        -- 3. VALIDACI??N DE FORMATOS (UFN)
        --------------------------------------------------------------------
        
        -- A. Validar Tipo Identificaci??n (GUID)
        IF @estadoResultado = 1 AND @tipoIdIdentificacionDefecto = '00000000-0000-0000-0000-000000000000'
        BEGIN
            SELECT @mensajeUsuarioResultado = 'Debe seleccionar un tipo de identificaci??n v??lido.',
                   @mensajeTecnicoResultado = CONCAT('Fallo: @tipoIdIdentificacionDefecto es el GUID vac??o. Correlaci??n: ', @idCorrelacionDefecto),
                   @estadoResultado = 0;
        END

        -- B. Validar N??mero Identificaci??n
        IF @estadoResultado = 1 AND dbo.ufn_validar_numero(@numeroIdentificacionDefecto) = 0
        BEGIN
            SET @estadoResultado = 0;
            SELECT @mensajeUsuarioResultado = CASE WHEN @numeroIdentificacionDefecto <= 0 THEN 'El n??mero de identificaci??n es obligatorio.' ELSE 'El n??mero de identificaci??n debe tener entre 6 y 10 d??gitos.' END,
                   @mensajeTecnicoResultado = CONCAT('Fallo en ufn_validar_numero para valor: ', @numeroIdentificacionDefecto, '. Correlaci??n: ', @idCorrelacionDefecto);
        END

        -- C. Validar Textos Obligatorios (Nombre y Apellido)
        IF @estadoResultado = 1 AND dbo.ufn_validar_texto(@primerNombreDefecto) = 0
        BEGIN
            SET @estadoResultado = 0;
            SELECT @mensajeUsuarioResultado = CASE WHEN @primerNombreDefecto = '' THEN 'El primer nombre es obligatorio.' ELSE 'El primer nombre tiene caracteres no permitidos.' END,
                   @mensajeTecnicoResultado = CONCAT('Fallo ufn_validar_texto en @primerNombreDefecto. Correlaci??n: ', @idCorrelacionDefecto);
        END

        IF @estadoResultado = 1 AND dbo.ufn_validar_texto(@primerApellidoDefecto) = 0
        BEGIN
            SET @estadoResultado = 0;
            SELECT @mensajeUsuarioResultado = CASE WHEN @primerApellidoDefecto = '' THEN 'El primer apellido es obligatorio.' ELSE 'El primer apellido tiene caracteres no permitidos.' END,
                   @mensajeTecnicoResultado = CONCAT('Fallo ufn_validar_texto en @primerApellidoDefecto. Correlaci??n: ', @idCorrelacionDefecto);
        END

        -- D. Validar Textos Opcionales (Segundo Nombre y Apellido)
        IF @estadoResultado = 1 AND @segundoNombreDefecto <> '' AND dbo.ufn_validar_texto(@segundoNombreDefecto) = 0
        BEGIN
            SELECT @mensajeUsuarioResultado = 'El segundo nombre tiene un formato inv??lido.',
                   @mensajeTecnicoResultado = CONCAT('Fallo ufn_validar_texto en @segundoNombreDefecto. Correlaci??n: ', @idCorrelacionDefecto),
                   @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND @segundoApellidoDefecto <> '' AND dbo.ufn_validar_texto(@segundoApellidoDefecto) = 0
        BEGIN
            SELECT @mensajeUsuarioResultado = 'El segundo apellido tiene un formato inv??lido.',
                   @mensajeTecnicoResultado = CONCAT('Fallo ufn_validar_texto en @segundoApellidoDefecto. Correlaci??n: ', @idCorrelacionDefecto),
                   @estadoResultado = 0;
        END

        -- E. Validar Correo
        IF @estadoResultado = 1 AND dbo.ufn_validar_correo(@correoDefecto) = 0
        BEGIN
            SET @estadoResultado = 0;
            SELECT @mensajeUsuarioResultado = CASE WHEN @correoDefecto = '' THEN 'El correo electr??nico es obligatorio.' ELSE 'El formato del correo no es v??lido.' END,
                   @mensajeTecnicoResultado = CONCAT('Fallo ufn_validar_correo para: ', @correoDefecto, '. Correlaci??n: ', @idCorrelacionDefecto);
        END

        -- F. Validar Password (Seguridad vs Defecto)
        IF @estadoResultado = 1 AND dbo.ufn_validar_password(@passwordDefecto, @numeroIdentificacionDefecto) = 0
        BEGIN
            SELECT @mensajeUsuarioResultado = 'La contrase??a no cumple con los requisitos m??nimos de seguridad.',
                   @mensajeTecnicoResultado = CONCAT('Fallo ufn_validar_password. No cumple complejidad y no es valor defecto. Correlaci??n: ', @idCorrelacionDefecto),
                   @estadoResultado = 0;
        END

        --------------------------------------------------------------------
        -- 4. REGISTRO FINAL
        --------------------------------------------------------------------
        IF @estadoResultado = 1 
        BEGIN
            INSERT INTO dbo.Usuario (
                id, tipoIdIdentificacion, numeroIdentificacion, 
                primerApellido, segundoApellido, primerNombre, segundoNombre, 
                correo, correoConfirmado, estado, password
            )
            VALUES (
                NEWID(), @tipoIdIdentificacionDefecto, @numeroIdentificacionDefecto,
                @primerApellidoDefecto, @segundoApellidoDefecto, 
                @primerNombreDefecto, @segundoNombreDefecto,
                @correoDefecto, 0, 1, @passwordDefecto
            );

            SELECT 
                @mensajeUsuarioResultado = 'Usuario registrado exitosamente.',
                @mensajeTecnicoResultado = CONCAT('Registro insertado correctamente en dbo.Usuario. Correlaci??n: ', @idCorrelacionDefecto),
                @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        SELECT @mensajeUsuarioResultado = 'No se pudo completar el registro del usuario.',
               @mensajeTecnicoResultado = CONCAT('Error t??cnico en usp_registrar_usuario: ', ERROR_MESSAGE(), '. Correlaci??n: ', @idCorrelacionDefecto),
               @estadoResultado = 0;
    END CATCH
END;
GO
