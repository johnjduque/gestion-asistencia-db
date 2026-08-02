USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_docente_en_grupo_interno]
(
    @docente UNIQUEIDENTIFIER,
    @grupo UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS
BEGIN
    -- 1. Estandarizacion de identificadores
    DECLARE @docenteDefecto UNIQUEIDENTIFIER = ISNULL(@docente,'00000000-0000-0000-0000-000000000000');
    DECLARE @grupoDefecto UNIQUEIDENTIFIER = ISNULL(@grupo,'00000000-0000-0000-0000-000000000000');
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');

    -- Inicializacion de respuesta
    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1;

    SET NOCOUNT ON;
    BEGIN TRY
        --------------------------------------------------------------------
        -- 2. CADENA DE VALIDACIONES
        --------------------------------------------------------------------
        
        -- Validacion de Correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- Validacion de Docente
        IF @estadoResultado = 1 BEGIN
            EXEC dbo.usp_validar_docente_exista_por_id_interno 
                @idDocente = @docenteDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- Validacion de Grupo
        IF @estadoResultado = 1 BEGIN
            EXEC dbo.usp_validar_grupo_exista_para_docente_interno 
                @idGrupo = @grupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END
            
        -- Validacion de Horario (Cruce)
        IF @estadoResultado = 1 BEGIN
            EXEC dbo.usp_validar_cruce_horario_docente_interno 
                @idDocente = @docenteDefecto, 
                @idGrupo = @grupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        --------------------------------------------------------------------
        -- 3. REGISTRO/ASIGNACION FINAL (UPDATE)
        --------------------------------------------------------------------
        IF @estadoResultado = 1 
        BEGIN
            UPDATE dbo.Grupo 
            SET docente = @docenteDefecto 
            WHERE id = @grupoDefecto;

            SELECT 
                @mensajeUsuarioResultado = 'La asignacion del docente al grupo se ha realizado exitosamente.',
                @mensajeTecnicoResultado = CONCAT('Asignacion exitosa. Se actualizo el docente del grupo [', CAST(@grupoDefecto AS NVARCHAR(50)), '] con el docente [', CAST(@docenteDefecto AS NVARCHAR(50)), ']. Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50))),
                @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        SELECT @mensajeUsuarioResultado = 'No se pudo completar la asignacion del docente al grupo.',
               @mensajeTecnicoResultado = CONCAT('Error critico en [usp_registrar_docente_en_grupo_interno]: ', ERROR_MESSAGE(), '. Linea: ', ERROR_LINE()),
               @estadoResultado = 0;
    END CATCH
END;
GO
