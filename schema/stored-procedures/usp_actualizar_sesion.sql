USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_sesion]
(
    @id                      UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50) = NULL,
    @fechaHoraInicio         DATETIME2 = NULL,
    @fechaHoraFin            DATETIME2 = NULL,
    @aula                    NVARCHAR(100) = NULL,
    @descripcion             NVARCHAR(MAX) = NULL,
    @idDocente               UNIQUEIDENTIFIER = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER = NULL,
    @mensajeUsuarioResultado NVARCHAR(4000) = NULL OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) = NULL OUTPUT,
    @estadoResultado         BIT = 1 OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET @estadoResultado = 1;
    SET @mensajeUsuarioResultado = '';
    SET @mensajeTecnicoResultado = '';

    DECLARE @grupoId UNIQUEIDENTIFIER;
    DECLARE @cerrada BIT;

    BEGIN TRY
        SELECT @grupoId = grupo, @cerrada = cerrada
        FROM dbo.Sesion
        WHERE id = @id;

        IF @grupoId IS NULL
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'La sesión de clase especificada no existe.';
            SET @mensajeTecnicoResultado = 'Sesión no encontrada por id.';
        END

        -- Validar que la sesión no esté cerrada
        IF @estadoResultado = 1 AND @cerrada = 1
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'No es posible modificar una sesión que ya ha sido cerrada.';
            SET @mensajeTecnicoResultado = 'Sesion cerrada=1, inmutable.';
        END

        -- Validar pertenencia del docente si se suministra
        IF @estadoResultado = 1 AND @idDocente IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupoId AND docente = @idDocente)
            BEGIN
                SET @estadoResultado = 0;
                SET @mensajeUsuarioResultado = 'Acceso denegado: No es el docente titular asignado al grupo de esta sesión.';
                SET @mensajeTecnicoResultado = 'Violacion de ambito docente.';
            END
        END

        -- Validar coherencia temporal
        DECLARE @inicio DATETIME2 = ISNULL(@fechaHoraInicio, (SELECT fechaHoraInicio FROM dbo.Sesion WHERE id = @id));
        DECLARE @fin DATETIME2 = ISNULL(@fechaHoraFin, (SELECT fechaHoraFin FROM dbo.Sesion WHERE id = @id));

        IF @estadoResultado = 1 AND @inicio >= @fin
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'La hora de inicio debe ser anterior a la hora de finalización.';
            SET @mensajeTecnicoResultado = 'Inconsistencia temporal en fechas de sesión.';
        END

        -- Actualización
        IF @estadoResultado = 1
        BEGIN
            UPDATE dbo.Sesion
            SET nombre = ISNULL(LTRIM(RTRIM(@nombre)), nombre),
                fechaHoraInicio = @inicio,
                fechaHoraFin = @fin,
                aula = ISNULL(@aula, aula),
                descripcion = ISNULL(@descripcion, descripcion)
            WHERE id = @id;

            SET @mensajeUsuarioResultado = 'Sesión de clase reprogramada / actualizada exitosamente.';
            SET @mensajeTecnicoResultado = 'Actualización completada en dbo.Sesion.';
        END

    END TRY
    BEGIN CATCH
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Error al actualizar los datos de la sesión de clase.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    SELECT
        idCorrelacion = @idCorrelacion,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado,
        @id AS idSesion,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
