USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    PROCEDURE [dbo].[usp_sincronizar_estudiante_interno]
(
    @idUsuario UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Estandarizaci??n y cura de variables
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER;
    DECLARE @idUsuarioDefecto UNIQUEIDENTIFIER;
    DECLARE @idPerfilBusquedad UNIQUEIDENTIFIER;

    -- Asignaci??n segura con validaci??n de nulos
    SET @idCorrelacionDefecto = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
    SET @idUsuarioDefecto = ISNULL(@idUsuario, '00000000-0000-0000-0000-000000000000');

    -- Inicializaci??n estricta de respuestas
    SELECT 
        @mensajeUsuarioResultado = '', 
        @mensajeTecnicoResultado = '', 
        @estadoResultado = 1;

    BEGIN TRY

        --------------------------------------------------------------------
        -- VALIDACI??N DE CORRELACI??N
        --------------------------------------------------------------------
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;
        
        --------------------------------------------------------------------
        -- VALIDAR PERFIL (Busca el ID por el c??digo 'ES')
        --------------------------------------------------------------------
        IF @estadoResultado = 1
        BEGIN
         
            EXEC dbo.usp_validar_perfil_existe_por_codigo_interno 
                @codigoPerfil = N'ES',
                @idCorrelacion = @idCorrelacionDefecto, 
                @idPerfilEncontrado = @idPerfilBusquedad OUTPUT, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END
       
        --------------------------------------------------------------------
        -- VALIDAR USUARIO (Existencia y Estado en el Sistema)
        --------------------------------------------------------------------
        IF @estadoResultado = 1
        BEGIN
        
            EXEC dbo.usp_validar_usuario_existe_por_id_interno 
                @idUsuario = @idUsuarioDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        --------------------------------------------------------------------
        -- VALIDAR UNICIDAD (Que el usuario NO sea ya un estudiante)
        --------------------------------------------------------------------
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Estudiante WHERE usuario = @idUsuarioDefecto)
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'El usuario ya se encuentra registrado como estudiante.',
                    @mensajeTecnicoResultado = CONCAT('Fallo unicidad: El idUsuario [', CAST(@idUsuarioDefecto AS NVARCHAR(50)), '] ya existe en la tabla dbo.Estudiante. Correlaci??n: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50))),
                    @estadoResultado = 0;
            END
        END

        --------------------------------------------------------------------
        -- INSERCI??N FINAL
        --------------------------------------------------------------------
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.Estudiante (id, usuario)
            VALUES (NEWID(), @idUsuarioDefecto);

            SELECT 
                @mensajeUsuarioResultado = 'Registro de estudiante completado exitosamente.',
                @mensajeTecnicoResultado = CONCAT('Inserci??n exitosa en dbo.Estudiante para idUsuario [', CAST(@idUsuarioDefecto AS NVARCHAR(50)), ']. Correlaci??n: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50))),
                @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Ocurri?? un error al intentar agregar el estudiante.',
            @mensajeTecnicoResultado = CONCAT('Error cr??tico en [usp_sincronizar_estudiante_interno]: ', ERROR_MESSAGE(), '. Correlaci??n: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50))),
            @estadoResultado = 0;
    END CATCH
END;
GO
