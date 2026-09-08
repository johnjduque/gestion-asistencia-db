USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_eliminar_asignatura]
(
    @id                 UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER = NULL,
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

        -- Validar si tiene grupos académicos creados
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.Grupo WHERE asignatura = @id)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'No es posible eliminar la asignatura porque ya cuenta con grupos académicos ofertados.';
            SET @mensajeTecnicoResultado = 'Integridad referencial restringida: existen registros en dbo.Grupo.';
        END

        IF @estadoResultado = 1
        BEGIN
            -- Eliminar relaciones de prerrequisito donde sea requisito o dependiente
            DELETE FROM dbo.PrerrequisitoAsignatura WHERE asignatura = @id OR asignaturaRequisito = @id;

            -- Eliminar la asignatura
            DELETE FROM dbo.Asignatura WHERE id = @id;

            SET @mensajeUsuarioResultado = 'Asignatura eliminada exitosamente del sistema.';
            SET @mensajeTecnicoResultado = 'Eliminacion completada en dbo.Asignatura.';
        END

    END TRY
    BEGIN CATCH
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Error al eliminar la asignatura de la base de datos.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    SELECT
        idCorrelacion = @idCorrelacion,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado,
        @id AS idAsignatura,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
