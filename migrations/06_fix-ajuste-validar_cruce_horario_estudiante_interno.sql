USE [gestionasistenciadb]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_cruce_horario_estudiante]    Script Date: 24/07/2026 7:08:45 p. m. ******/
DROP PROCEDURE IF EXISTS [dbo].[usp_validar_cruce_horario_estudiante]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_cruce_horario_estudiante]    Script Date: 24/07/2026 7:08:45 p. m. ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  OR  ALTER  PROCEDURE [dbo].[usp_validar_cruce_horario_estudiante_interno]
(
    @idEstudiante UNIQUEIDENTIFIER,
    @idGrupo UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS

    DECLARE @idEstudianteDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idEstudiante,'00000000-0000-0000-0000-000000000000'))));
    DECLARE @idGrupoDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idGrupo,'00000000-0000-0000-0000-000000000000'))));
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion,'00000000-0000-0000-0000-000000000000'))));

    -- Inicialización
    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- 1. Validar correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 1. Validaciones previas de existencia
        IF @estadoResultado = 1 BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id @idEstudiante = @idEstudianteDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id @idGrupo = @idGrupoDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        --------------------------------------------------------------------
        -- 2. Detección de Cruce de Horario
        --------------------------------------------------------------------
        IF @estadoResultado = 1 
        BEGIN
            DECLARE @nombreGrupoConflicto NVARCHAR(200);
            DECLARE @diaConflicto NVARCHAR(50);

            -- Buscamos si existe un cruce entre el horario del nuevo grupo y los grupos ya matriculados
            SELECT TOP 1 
                @estadoResultado = 0,
                @nombreGrupoConflicto = gExistente.nombre,
                @diaConflicto = hNuevo.nombreDia -- Asumiendo que uv_horario tiene el nombre del día
            FROM uv_horario hNuevo
            INNER JOIN uv_horario hExistente ON hNuevo.idDia = hExistente.idDia 
                AND hNuevo.idPeriodoAcademico = hExistente.idPeriodoAcademico
            INNER JOIN uv_estudiante_grupo eg ON hExistente.idGrupo = eg.idGrupo
            INNER JOIN uv_grupo gExistente ON eg.idGrupo = gExistente.id
            WHERE hNuevo.idGrupo = @idGrupoDefecto
                AND eg.idEstudiante = @idEstudianteDefecto
                AND hNuevo.idGrupo <> hExistente.idGrupo
                -- Lógica de traslape: (InicioA < FinB) AND (FinA > InicioB)
                AND hNuevo.horaInicio < hExistente.horaFin
                AND hNuevo.horaFin > hExistente.horaInicio;

            IF @estadoResultado = 0
            BEGIN
                SELECT @mensajeUsuarioResultado = CONCAT('No es posible realizar el registro. Existe un cruce de horario el día ', @diaConflicto, ' con el grupo: ', @nombreGrupoConflicto, '.'),
                       @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Cruce detectado en uv_horario para Estudiante: ', @idEstudianteDefecto, ' Conflicto con GrupoID: ', @idGrupoDefecto));
            END
        END

    END TRY
    BEGIN CATCH
        SELECT @mensajeUsuarioResultado = 'Error al validar disponibilidad de horario.',
               @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_validar_cruce_horario_estudiante_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
               @estadoResultado = 0;
    END CATCH
END
GO


