USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_cruce_horario_docente_interno]
(
    @idDocente UNIQUEIDENTIFIER,
    @idGrupo UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS
BEGIN
    DECLARE @idDocenteDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idDocente,'00000000-0000-0000-0000-000000000000'))));
    DECLARE @idGrupoDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idGrupo,'00000000-0000-0000-0000-000000000000'))));
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion,'00000000-0000-0000-0000-000000000000'))));

    -- Inicialización
    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1;

    SET NOCOUNT ON;
    BEGIN TRY

        -- 1. Validar correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validaciones previas de existencia
        IF @estadoResultado = 1 BEGIN
            EXEC dbo.usp_validar_docente_exista_por_id_interno @idDocente = @idDocenteDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 BEGIN
            EXEC dbo.usp_validar_grupo_exista_para_docente_interno @idGrupo = @idGrupoDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        --------------------------------------------------------------------
        -- 3. Detección de Cruce de Horario
        --------------------------------------------------------------------
        IF @estadoResultado = 1 
        BEGIN
            DECLARE @nombreGrupoConflicto NVARCHAR(200);
            DECLARE @diaConflicto NVARCHAR(50);

            -- Buscamos si existe un cruce entre el horario del nuevo grupo y los grupos ya asignados al docente
            SELECT TOP 1 
                @estadoResultado = 0,
                @nombreGrupoConflicto = gExistente.nombre,
                @diaConflicto = hNuevo.nombreDia
            FROM uv_horario hNuevo
            INNER JOIN uv_horario hExistente ON hNuevo.idDia = hExistente.idDia 
                AND hNuevo.idPeriodoAcademico = hExistente.idPeriodoAcademico
            INNER JOIN uv_grupo gExistente ON hExistente.idGrupo = gExistente.id
            WHERE hNuevo.idGrupo = @idGrupoDefecto
                AND gExistente.idDocente = @idDocenteDefecto
                AND hNuevo.idGrupo <> hExistente.idGrupo
                -- Lógica de traslape: (InicioA < FinB) AND (FinA > InicioB)
                AND hNuevo.horaInicio < hExistente.horaFin
                AND hNuevo.horaFin > hExistente.horaInicio;

            IF @estadoResultado = 0
            BEGIN
                SELECT @mensajeUsuarioResultado = CONCAT('No es posible realizar el registro. Existe un cruce de horario el día ', @diaConflicto, ' con el grupo: ', @nombreGrupoConflicto, '.'),
                       @mensajeTecnicoResultado = CONCAT('Cruce detectado en uv_horario para Docente: ', @idDocenteDefecto, ' Conflicto con Grupo: ', @nombreGrupoConflicto);
            END
        END

    END TRY
    BEGIN CATCH
        SELECT @mensajeUsuarioResultado = 'Error al validar disponibilidad de horario del docente.',
               @mensajeTecnicoResultado = CONCAT('Error crítico en orquestador [usp_validar_cruce_horario_docente_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
               @estadoResultado = 0;
    END CATCH
END;
GO
