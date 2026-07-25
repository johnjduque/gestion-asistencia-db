USE [gestionasistenciadb]
GO

/****** Object:  StoredProcedure [dbo].[usp_registrar_estudiante_en_grupo_interno]    Script Date: 24/07/2026 8:33:54 p. m. ******/
DROP PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo_interno]
GO

/****** Object:  StoredProcedure [dbo].[usp_registrar_estudiante_en_grupo_interno]    Script Date: 24/07/2026 8:33:54 p. m. ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE  OR  ALTER   PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo_interno]
    (
        @estudiante UNIQUEIDENTIFIER,
        @grupo UNIQUEIDENTIFIER,
        @idCorrelacion UNIQUEIDENTIFIER,
        @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
        @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
        @estadoResultado BIT OUTPUT
    )
AS
    -- 1. Estandarización de identificadores
    DECLARE @estudianteDefecto UNIQUEIDENTIFIER = ISNULL(@estudiante,'00000000-0000-0000-0000-000000000000');
    DECLARE @grupoDefecto UNIQUEIDENTIFIER = ISNULL(@grupo,'00000000-0000-0000-0000-000000000000');
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
    
    -- Variable para almacenar el ID que encontraremos por código
    DECLARE @idEstadoActivo UNIQUEIDENTIFIER;

    -- Inicialización de respuesta
    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1;
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        --------------------------------------------------------------------
        -- 2. OBTENER ID DEL ESTADO POR SU CÓDIGO 'A' (Activo)
        --------------------------------------------------------------------
        SELECT @idEstadoActivo = id 
        FROM uv_estado_estudiante_grupo 
        WHERE codigo = 'A'; 

        IF @idEstadoActivo IS NULL
        BEGIN
            SELECT @mensajeUsuarioResultado = 'Error de configuración del sistema.',
                   @mensajeTecnicoResultado = 'No se encontró el ID para el código de estado [A].',
                   @estadoResultado = 0;
            RETURN;
        END

        --------------------------------------------------------------------
        -- 3. CADENA DE VALIDACIONES (Solo si @estadoResultado = 1)
        --------------------------------------------------------------------
        
        -- Validación de Correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;

        -- Validación de Estudiante
        IF @estadoResultado = 1 BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno @idEstudiante = @estudianteDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- Validación de Grupo
        IF @estadoResultado = 1 BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno @idGrupo = @grupoDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END
            
        -- Validación de Horario (Cruce)
        IF @estadoResultado = 1 BEGIN
            EXEC dbo.usp_validar_cruce_horario_estudiante_interno @idEstudiante = @estudianteDefecto, @idGrupo = @grupoDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- Validación de Duplicidad
        IF @estadoResultado = 1 BEGIN
            EXEC dbo.usp_validar_registro_estudiante_en_grupo_interno @idEstudiante = @estudianteDefecto, @idGrupo = @grupoDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        --------------------------------------------------------------------
        -- 4. REGISTRO FINAL (INSERT)
        --------------------------------------------------------------------
        IF @estadoResultado = 1 
        BEGIN
            INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
            VALUES (NEWID(), @idEstadoActivo, @estudianteDefecto, @grupoDefecto);

            SELECT 
                @mensajeUsuarioResultado = 'Tu registro se ha realizado exitosamente.',
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Operación exitosa completa, Registro completado con estado [A]. Orquestador finalizado para Estudiante: ', @estudianteDefecto, ' en Grupo: ', @grupoDefecto)),
                @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        SELECT @mensajeUsuarioResultado = 'No se pudo completar el registro.',
               @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_registrar_estudiante_en_grupo]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
               @estadoResultado = 0;
    END CATCH

    SELECT  mensajeUsuarioResultado = @mensajeUsuarioResultado,
            mensajeTecnicoResultado = @mensajeTecnicoResultado,
            estadoResultado = @estadoResultado
END
GO


