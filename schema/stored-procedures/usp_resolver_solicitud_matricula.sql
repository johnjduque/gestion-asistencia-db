USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_solicitud_matricula]
(
    @idSolicitud            UNIQUEIDENTIFIER,
    @idCoordinador          UNIQUEIDENTIFIER,
    @accion                 NVARCHAR(20),
    @respuestaCoordinador   NVARCHAR(MAX),
    @idCorrelacion          UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idCoordinadorDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCoordinador, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @idProgramaCoordinador UNIQUEIDENTIFIER;
    DECLARE @idProgramaGrupo       UNIQUEIDENTIFIER;
    DECLARE @idEstudiante          UNIQUEIDENTIFIER;
    DECLARE @idGrupo               UNIQUEIDENTIFIER;

BEGIN
    SET NOCOUNT ON;
    SET @estadoResultado = 1;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');

    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Recuperar programa del coordinador
        SELECT TOP 1 @idProgramaCoordinador = p.id
        FROM dbo.Programa p
        WHERE p.coordinador = @idCoordinadorDefecto;

        -- PASO 3: Recuperar datos de la solicitud y programa de la asignatura
        SELECT TOP 1
            @idEstudiante = sm.estudiante,
            @idGrupo = sm.grupo,
            @idProgramaGrupo = pe.programa
        FROM dbo.SolicitudMatricula sm
        INNER JOIN dbo.Grupo g ON sm.grupo = g.id
        INNER JOIN dbo.Asignatura a ON g.asignatura = a.id
        INNER JOIN dbo.SemestrePlanEstudio spe ON a.semestrePlanEstudio = spe.id
        INNER JOIN dbo.PlanEstudio pe ON spe.planEstudio = pe.id
        WHERE sm.id = @idSolicitudDefecto;

        IF @idEstudiante IS NULL
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'La solicitud de matrícula especificada no existe.';
            SET @mensajeTecnicoResultado = 'Solicitud de matricula no encontrada por ID.';
        END
        -- PASO 4: Validación de ámbito (el grupo solicitado pertenece al programa del coordinador)
        ELSE IF @idProgramaCoordinador IS NOT NULL AND @idProgramaGrupo IS NOT NULL AND @idProgramaCoordinador <> @idProgramaGrupo
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'Acceso denegado: Solo el coordinador del programa puede autorizar este cupo.';
            SET @mensajeTecnicoResultado = CONCAT('Violacion de ambito: el coordinador ', CAST(@idCoordinadorDefecto AS VARCHAR(50)), ' no administra el programa del grupo ', CAST(@idGrupo AS VARCHAR(50)));
        END

        -- PASO 5: Actualización de la solicitud y matrícula efectiva si fue aprobada
        IF @estadoResultado = 1
        BEGIN
            BEGIN TRANSACTION;

            UPDATE dbo.SolicitudMatricula
            SET estado = UPPER(@accion),
                respuestaCoordinador = ISNULL(@respuestaCoordinador, ''),
                fechaRespuesta = CAST(CURRENT_TIMESTAMP AS DATE)
            WHERE id = @idSolicitudDefecto;

            IF UPPER(@accion) = 'APROBADA'
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE estudiante = @idEstudiante AND grupo = @idGrupo)
                BEGIN
                    INSERT INTO dbo.EstudianteGrupo (id, estudiante, grupo, estado)
                    VALUES (
                        NEWID(),
                        @idEstudiante,
                        @idGrupo,
                        (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A')
                    );
                END
            END

            COMMIT TRANSACTION;

            SET @mensajeUsuarioResultado = CONCAT('Solicitud de matrícula ', LOWER(@accion), ' correctamente.');
            SET @mensajeTecnicoResultado = 'Solicitud resuelta y estudiante enrolado en EstudianteGrupo si fue aprobada.';
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Ocurrió un error al resolver la solicitud de matrícula.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    SELECT 
        @idSolicitudDefecto AS idSolicitud,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
