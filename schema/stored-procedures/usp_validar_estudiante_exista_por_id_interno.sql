USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER        PROCEDURE [dbo].[usp_validar_estudiante_exista_por_id_interno]  
(  
    @idEstudiante UNIQUEIDENTIFIER,  
    @idCorrelacion UNIQUEIDENTIFIER,  
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,  
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,  
    @estadoResultado BIT OUTPUT  
)  
AS

    DECLARE @idEstudianteDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idEstudiante,'00000000-0000-0000-0000-000000000000'))));  
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion,'00000000-0000-0000-0000-000000000000'))));  
  
    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1; 
    
BEGIN  
    SET NOCOUNT ON;  
    BEGIN TRY  
        -- 1. Validar correlaci??n  
        EXEC dbo.usp_validar_id_correlacion_esta_presente  
            @idCorrelacion = @idCorrelacionDefecto,  
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;  

        -- 2. Validar identificador Estudiante no es vac??o  
        IF @estadoResultado = 1  
        BEGIN  
            EXEC dbo.usp_validar_id   
                @id = @idEstudianteDefecto,   
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,   
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,   
                @estadoResultado = @estadoResultado OUTPUT;  
  
            SELECT  @mensajeUsuarioResultado = 'El identificador del estudiante no es v??lido o est?? vac??o.',  
                    @mensajeTecnicoResultado = CONCAT('ID Estudiante vac??o o por defecto. ID CORRELACION=[', @idCorrelacionDefecto, ']'),  
                    @estadoResultado = 0  
            WHERE   @estadoResultado = 0;  
        END  
  
        --------------------------------------------------------------------  
        -- 3. Validar Existencia en la tabla/vista base (Cambio a uv_estudiante_identidad)
        --------------------------------------------------------------------  
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM uv_estudiante_identidad WHERE id = @idEstudianteDefecto)  
        BEGIN  
            SELECT @mensajeUsuarioResultado = CONCAT('No existe un estudiante con el identificador [', @idEstudianteDefecto, '].'),  
                   @mensajeTecnicoResultado = CONCAT('No existe en uv_estudiante_identidad. ID CORRELACION=[', @idCorrelacionDefecto, ']'),  
                   @estadoResultado = 0;  
        END  
  
        --------------------------------------------------------------------  
        -- 4. Validar que est?? Activo en la identidad base
        --------------------------------------------------------------------  
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM uv_estudiante_identidad WHERE id = @idEstudianteDefecto AND estaActivoUsuario = 0)  
        BEGIN  
            SELECT @mensajeUsuarioResultado = 'El estudiante se encuentra inactivo.',  
                   @mensajeTecnicoResultado = CONCAT('estaActivoUsuario = 0 en uv_estudiante_identidad. ID CORRELACION=[', @idCorrelacionDefecto, ']'),  
                   @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('estaActivoUsuario = 0 en uv_estudiante_identidad: ', @idEstudianteDefecto)),
                   @estadoResultado = 0;  
        END  
  
    END TRY  
    BEGIN CATCH  
        SELECT @mensajeUsuarioResultado = 'Ocurri?? un error inesperado.',   
               @mensajeTecnicoResultado = CONCAT('Error cr??tico en orquestador [usp_validar_estudiante_exista_por_id_interno]: ', ERROR_MESSAGE(), '. L??nea: ', ERROR_LINE()),
               @estadoResultado = 0;  
    END CATCH  
END
GO
