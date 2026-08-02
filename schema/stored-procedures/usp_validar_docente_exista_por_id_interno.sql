USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_docente_exista_por_id_interno]  
(  
    @idDocente UNIQUEIDENTIFIER,  
    @idCorrelacion UNIQUEIDENTIFIER,  
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,  
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,  
    @estadoResultado BIT OUTPUT  
)  
AS
BEGIN
    DECLARE @idDocenteDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idDocente,'00000000-0000-0000-0000-000000000000'))));  
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion,'00000000-0000-0000-0000-000000000000'))));  
  
    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1; 
    
    SET NOCOUNT ON;  
    BEGIN TRY  
        -- 1. Validar correlación  
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto,  
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;  

        -- 2. Validar identificador Docente no es vacío  
        IF @estadoResultado = 1  
        BEGIN  
            EXEC dbo.usp_validar_id_interno 
                @id = @idDocenteDefecto,   
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,   
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,   
                @estadoResultado = @estadoResultado OUTPUT;  
  
            SELECT  @mensajeUsuarioResultado = 'El identificador del docente no es válido o está vacío.',  
                    @mensajeTecnicoResultado = CONCAT('ID Docente vacío o por defecto. ID CORRELACION=[', @idCorrelacionDefecto, ']'),  
                    @estadoResultado = 0  
            WHERE   @estadoResultado = 0;  
        END  
  
        --------------------------------------------------------------------  
        -- 3. Validar Existencia en la vista base uv_docente_identidad
        --------------------------------------------------------------------  
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM uv_docente_identidad WHERE id = @idDocenteDefecto)  
        BEGIN  
            SELECT @mensajeUsuarioResultado = CONCAT('No existe un docente con el identificador [', @idDocenteDefecto, '].'),  
                   @mensajeTecnicoResultado = CONCAT('No existe en uv_docente_identidad. ID CORRELACION=[', @idCorrelacionDefecto, ']'),  
                   @estadoResultado = 0;  
        END  
  
        --------------------------------------------------------------------  
        -- 4. Validar que esté Activo en la identidad base
        --------------------------------------------------------------------  
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM uv_docente_identidad WHERE id = @idDocenteDefecto AND estaActivoUsuario = 0)  
        BEGIN  
            SELECT @mensajeUsuarioResultado = 'El docente se encuentra inactivo.',  
                   @mensajeTecnicoResultado = CONCAT('estaActivoUsuario = 0 en uv_docente_identidad. ID CORRELACION=[', @idCorrelacionDefecto, ']'),  
                   @estadoResultado = 0;  
        END  
  
    END TRY  
    BEGIN CATCH  
        SELECT @mensajeUsuarioResultado = 'Ocurrió un error inesperado al validar el docente.',   
               @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_validar_docente_exista_por_id_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
               @estadoResultado = 0;  
    END CATCH  
END;
GO
