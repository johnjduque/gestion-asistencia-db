USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_solicitud_revision_asistencia]
(
    @idSolicitud        UNIQUEIDENTIFIER,
    @idDocente          UNIQUEIDENTIFIER,
    @accion             NVARCHAR(20),
    @respuestaDocente   NVARCHAR(MAX),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto   UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @docenteTitularGrupo UNIQUEIDENTIFIER;
    DECLARE @idAsistencia        UNIQUEIDENTIFIER;
    DECLARE @codigoEstadoNuevo   NVARCHAR(5);
    DECLARE @idEstadoNuevo       UNIQUEIDENTIFIER;

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

        -- PASO 2: Validación de existencia de la solicitud y recuperación de docente titular
        SELECT TOP 1
            @docenteTitularGrupo = g.docente,
            @idAsistencia = sra.asistencia
        FROM dbo.SolicitudRevisionAsistencia sra
        INNER JOIN dbo.Asistencia ast ON sra.asistencia = ast.id
        INNER JOIN dbo.Sesion s ON ast.sesion = s.id
        INNER JOIN dbo.Grupo g ON s.grupo = g.id
        WHERE sra.id = @idSolicitudDefecto;

        IF @docenteTitularGrupo IS NULL
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'La solicitud de revisión especificada no existe.';
            SET @mensajeTecnicoResultado = 'Solicitud de revision no encontrada por ID.';
        END
        -- PASO 3: Validación de ámbito (el docente debe ser el titular del grupo)
        ELSE IF @docenteTitularGrupo <> @idDocenteDefecto
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'Acceso denegado: Solo el docente titular del grupo puede resolver esta solicitud.';
            SET @mensajeTecnicoResultado = CONCAT('Violacion de ambito: el docente ', CAST(@idDocenteDefecto AS VARCHAR(50)), ' no es titular de la solicitud ', CAST(@idSolicitudDefecto AS VARCHAR(50)));
        END

        -- PASO 4: Resolución atómica de la solicitud
        IF @estadoResultado = 1
        BEGIN
            SET @codigoEstadoNuevo = IIF(UPPER(@accion) = 'APROBADA', 'APRO', 'RECH');

            SELECT TOP 1 @idEstadoNuevo = id
            FROM dbo.Estado
            WHERE codigo = @codigoEstadoNuevo;

            IF @idEstadoNuevo IS NULL
            BEGIN
                SELECT TOP 1 @idEstadoNuevo = id FROM dbo.Estado;
            END

            BEGIN TRANSACTION;

            -- 4.1 Actualizar solicitud
            UPDATE dbo.SolicitudRevisionAsistencia
            SET estado = @idEstadoNuevo,
                justificacionRespuesta = ISNULL(@respuestaDocente, ''),
                fechaRespuesta = CAST(CURRENT_TIMESTAMP AS DATE)
            WHERE id = @idSolicitudDefecto;

            -- 4.2 Si fue aprobada, actualizar DetalleAsistencia a JUSTIFICADA y asistio = 1
            IF UPPER(@accion) = 'APROBADA'
            BEGIN
                UPDATE dbo.DetalleAsistencia
                SET asistio = 1,
                    estado = 'JUSTIFICADA',
                    observacion = CONCAT(ISNULL(observacion + ' | ', ''), 'Justificación aprobada: ', ISNULL(@respuestaDocente, ''))
                WHERE asistencia = @idAsistencia;
            END

            COMMIT TRANSACTION;

            SET @mensajeUsuarioResultado = IIF(
                UPPER(@accion) = 'APROBADA',
                'Reclamo aprobado. Se ha actualizado la asistencia a "Justificada".',
                'Reclamo rechazado con la justificación suministrada.'
            );
            SET @mensajeTecnicoResultado = 'Solicitud y asistencia actualizadas atomicamente.';
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Ocurrió un error al resolver la solicitud de revisión.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    SELECT 
        @idSolicitudDefecto AS idSolicitud,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
