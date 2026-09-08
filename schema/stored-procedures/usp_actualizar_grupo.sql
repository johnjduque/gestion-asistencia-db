USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_grupo]
(
    @id                      UNIQUEIDENTIFIER,
    @codigo                  INT = NULL,
    @nombre                  NVARCHAR(50) = NULL,
    @idDocente               UNIQUEIDENTIFIER = NULL,
    @cupoMaximo              INT = NULL,
    @aula                    NVARCHAR(100) = NULL,
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

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @id)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'El grupo académico especificado no existe.';
            SET @mensajeTecnicoResultado = 'Grupo no encontrado por id.';
        END

        -- Validar docente si se actualiza
        IF @estadoResultado = 1 AND @idDocente IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Docente WHERE id = @idDocente)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'El docente asignado no existe.';
            SET @mensajeTecnicoResultado = 'FK @idDocente no encontrada en dbo.Docente.';
        END

        -- Validar unicidad de código si se actualiza
        IF @estadoResultado = 1 AND @codigo IS NOT NULL
        BEGIN
            DECLARE @asigId UNIQUEIDENTIFIER;
            DECLARE @periodoId UNIQUEIDENTIFIER;
            SELECT @asigId = asignatura, @periodoId = periodoAcademico FROM dbo.Grupo WHERE id = @id;

            IF EXISTS (
                SELECT 1 FROM dbo.Grupo
                WHERE asignatura = @asigId AND periodoAcademico = @periodoId AND codigo = @codigo AND id <> @id
            )
            BEGIN
                SET @estadoResultado = 0;
                SET @mensajeUsuarioResultado = CONCAT('El código ', @codigo, ' ya está en uso por otro grupo en este período.');
                SET @mensajeTecnicoResultado = 'Conflicto de código en dbo.Grupo.';
            END
        END

        -- Actualización
        IF @estadoResultado = 1
        BEGIN
            UPDATE dbo.Grupo
            SET codigo = ISNULL(@codigo, codigo),
                nombre = ISNULL(LTRIM(RTRIM(@nombre)), nombre),
                docente = ISNULL(@idDocente, docente),
                cantidadEstudiantes = ISNULL(@cupoMaximo, cantidadEstudiantes),
                aula = ISNULL(@aula, aula)
            WHERE id = @id;

            SET @mensajeUsuarioResultado = 'Información del grupo académico actualizada exitosamente.';
            SET @mensajeTecnicoResultado = 'Actualización completada en dbo.Grupo.';
        END

    END TRY
    BEGIN CATCH
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Error al actualizar los datos del grupo.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    SELECT
        idCorrelacion = @idCorrelacion,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado,
        @id AS idGrupo,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
