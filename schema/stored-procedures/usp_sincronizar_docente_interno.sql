USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_sincronizar_docente_interno]
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

    -- 1. Estandarización y cura de variables
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER;
    DECLARE @idUsuarioDefecto UNIQUEIDENTIFIER;
    DECLARE @idPerfilBusqueda UNIQUEIDENTIFIER;

    -- Asignación segura con validación de nulos
    SET @idCorrelacionDefecto = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
    SET @idUsuarioDefecto = ISNULL(@idUsuario, '00000000-0000-0000-0000-000000000000');

    -- Inicialización estricta de respuestas
    SELECT 
        @mensajeUsuarioResultado = '', 
        @mensajeTecnicoResultado = '', 
        @estadoResultado = 1;

    BEGIN TRY

        --------------------------------------------------------------------
        -- VALIDACIÓN DE CORRELACIÓN
        --------------------------------------------------------------------
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;
        
        --------------------------------------------------------------------
        -- VALIDAR PERFIL (Busca el ID por el código 'DO' de Docente)
        --------------------------------------------------------------------
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_perfil_existe_por_codigo_interno 
                @codigoPerfil = N'DO',
                @idCorrelacion = @idCorrelacionDefecto, 
                @idPerfilEncontrado = @idPerfilBusqueda OUTPUT, 
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
        -- VALIDAR UNICIDAD (Que el usuario NO sea ya un docente)
        --------------------------------------------------------------------
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Docente WHERE usuario = @idUsuarioDefecto)
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'El usuario ya se encuentra registrado como docente.',
                    @mensajeTecnicoResultado = CONCAT('Fallo unicidad: El idUsuario [', CAST(@idUsuarioDefecto AS NVARCHAR(50)), '] ya existe en la tabla dbo.Docente. Correlación: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50))),
                    @estadoResultado = 0;
            END
        END

        --------------------------------------------------------------------
        -- INSERCIÓN FINAL
        --------------------------------------------------------------------
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.Docente (id, usuario)
            VALUES (NEWID(), @idUsuarioDefecto);

            SELECT 
                @mensajeUsuarioResultado = 'Registro de docente completado exitosamente.',
                @mensajeTecnicoResultado = CONCAT('Inserción exitosa en dbo.Docente para idUsuario [', CAST(@idUsuarioDefecto AS NVARCHAR(50)), ']. Correlación: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50))),
                @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Ocurrió un error al intentar agregar el docente.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en [usp_sincronizar_docente_interno]: ', ERROR_MESSAGE(), '. Correlación: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50))),
            @estadoResultado = 0;
    END CATCH
END;
GO
