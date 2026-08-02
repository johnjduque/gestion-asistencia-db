USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER        PROCEDURE [dbo].[usp_registrar_estudiante_en_programa_interno]
(
    @idEstudiante UNIQUEIDENTIFIER,
    @idPrograma UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))));
    
    -- Variables para capturar y comparar las instituciones
    DECLARE @idInstitucionEstudiante UNIQUEIDENTIFIER;
    DECLARE @idInstitucionPrograma UNIQUEIDENTIFIER;
    DECLARE @idInstitucionFacultad UNIQUEIDENTIFIER;

    -- Inicializacion de respuestas
    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            -- 1. Obtener la institucion del estudiante desde su vista completa
            SELECT TOP 1 @idInstitucionEstudiante = idInstitucion 
            FROM [dbo].[uv_estudiante] 
            WHERE id = @idEstudiante;

            -- 2. Obtener la institucion del programa y de la facultad desde uv_programa
            SELECT TOP 1 
                @idInstitucionPrograma = idInstitucion,
                @idInstitucionFacultad = idInstitucion -- uv_programa ya hereda internamente la de uv_facultad
            FROM [dbo].[uv_programa] 
            WHERE id = @idPrograma;

            -- 3. Validar consistencia institucional cruzada
            IF @idInstitucionEstudiante IS NULL OR @idInstitucionPrograma IS NULL
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'No se pudo verificar la consistencia institucional del estudiante o programa.',
                    @mensajeTecnicoResultado = CONCAT('Fallo: Datos institucionales NULL. Estudiante: ', ISNULL(CAST(@idInstitucionEstudiante AS VARCHAR(36)), 'NULL'), ' - Programa: ', ISNULL(CAST(@idInstitucionPrograma AS VARCHAR(36)), 'NULL'), '. Correlacion: ', @idCorrelacionDefecto),
                    @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1 AND (@idInstitucionEstudiante <> @idInstitucionPrograma OR @idInstitucionPrograma <> @idInstitucionFacultad)
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'El estudiante no pertenece a la misma institucion del programa academico seleccionado.',
                @mensajeTecnicoResultado = CONCAT('Violacion de integridad: InstEstudiante, InstPrograma o InstFacultad no coinciden. Correlacion: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
        END

        -- 4. Validar si ya esta matriculado en el programa para evitar duplicados en EstudiantePrograma
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM [dbo].[EstudiantePrograma] WHERE estudiante = @idEstudiante AND programa = @idPrograma)
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'El estudiante ya se encuentra vinculado a este programa academico.',
                @mensajeTecnicoResultado = CONCAT('Aviso: Registro existente en EstudiantePrograma. Saltando insercion. Correlacion: ', @idCorrelacionDefecto),
                @estadoResultado = 1; -- No corta el proceso mayor
        END
        ELSE IF @estadoResultado = 1
        BEGIN
            -- 5. Insercion fosica en la tabla solicitada
            INSERT INTO [dbo].[EstudiantePrograma] (id, estudiante, programa)
            VALUES (NEWID(), @idEstudiante, @idPrograma);

            SELECT 
                @mensajeUsuarioResultado = 'Estudiante vinculado al programa exitosamente.',
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Operacion exitosa completa. Orquestador finalizado para Estudiante: ', @idEstudiante, ' en Programa: ', @idPrograma)),
                @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Ocurrio un error inesperado al vincular al estudiante con el programa.',
            @mensajeTecnicoResultado = CONCAT('Error critico en orquestador [usp_registrar_estudiante_en_programa_interno]: ', ERROR_MESSAGE(), '. Linea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO
