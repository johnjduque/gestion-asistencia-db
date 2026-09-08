USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_toggle_estado_asignatura]
(
    @id                 UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER = NULL,
    @nuevoEstado        BIT = NULL OUTPUT,
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

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @id)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'La asignatura especificada no existe.';
            SET @mensajeTecnicoResultado = 'Asignatura no encontrada por id.';
        END

        IF @estadoResultado = 1
        BEGIN
            UPDATE dbo.Asignatura
            SET estado = CASE WHEN estado = 1 THEN 0 ELSE 1 END
            WHERE id = @id;

            SELECT @nuevoEstado = estado FROM dbo.Asignatura WHERE id = @id;

            SET @mensajeUsuarioResultado = CONCAT('Estado de la asignatura actualizado a ', CASE WHEN @nuevoEstado = 1 THEN 'ACTIVO' ELSE 'INACTIVO' END, '.');
            SET @mensajeTecnicoResultado = 'Cambio de estado completado en dbo.Asignatura.';
        END

    END TRY
    BEGIN CATCH
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Error al cambiar el estado de la asignatura.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    SELECT
        idCorrelacion = @idCorrelacion,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado,
        @id AS idAsignatura,
        @nuevoEstado AS estadoActualizado,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
