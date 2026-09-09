USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_solicitud_matricula_interno]
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
    DECLARE @accionDefecto         NVARCHAR(20)     = UPPER(TRIM(@accion));
    DECLARE @respuestaDefecto      NVARCHAR(MAX)    = TRIM(@respuestaCoordinador);

    DECLARE @idProgramaCoordinador UNIQUEIDENTIFIER;
    DECLARE @idProgramaGrupo       UNIQUEIDENTIFIER;
    DECLARE @idEstudiante          UNIQUEIDENTIFIER;
    DECLARE @idGrupo               UNIQUEIDENTIFIER;
    DECLARE @idEstadoActivoEst     UNIQUEIDENTIFIER;

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
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idProgramaCoordinador = p.id
            FROM dbo.Programa p
            WHERE p.coordinador = @idCoordinadorDefecto;

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
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'SolicitudMatricula',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @idProgramaCoordinador IS NOT NULL AND @idProgramaGrupo IS NOT NULL AND @idProgramaCoordinador <> @idProgramaGrupo
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_007',
                    @p_param1 = 'CoordinadorAmbitoMatricula',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Resolución atómica transaccional de la solicitud
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoActivoEst = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A' ORDER BY id ASC;

            BEGIN TRANSACTION;

            UPDATE dbo.SolicitudMatricula
            SET estado = @accionDefecto,
                respuestaCoordinador = CASE WHEN @respuestaDefecto IS NOT NULL THEN @respuestaDefecto ELSE '' END,
                fechaRespuesta = CAST(CURRENT_TIMESTAMP AS DATE)
            WHERE id = @idSolicitudDefecto;

            IF @accionDefecto = 'APROBADA'
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE estudiante = @idEstudiante AND grupo = @idGrupo)
                BEGIN
                    INSERT INTO dbo.EstudianteGrupo (id, estudiante, grupo, estado)
                    VALUES (
                        NEWID(),
                        @idEstudiante,
                        @idGrupo,
                        @idEstadoActivoEst
                    );

                    UPDATE dbo.Grupo
                    SET cantidadEstudiantes = cantidadEstudiantes + 1
                    WHERE id = @idGrupo;
                END
            END

            COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudMatricula',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
