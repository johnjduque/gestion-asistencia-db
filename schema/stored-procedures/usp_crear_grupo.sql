USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_grupo]
(
    @id                      UNIQUEIDENTIFIER = NULL,
    @idAsignatura            UNIQUEIDENTIFIER,
    @idPeriodoAcademico      UNIQUEIDENTIFIER = NULL,
    @codigo                  INT,
    @nombre                  NVARCHAR(50),
    @idDocente               UNIQUEIDENTIFIER,
    @cupoMaximo              INT = 35,
    @aula                    NVARCHAR(100) = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER = NULL,
    @idGrupoResultado        UNIQUEIDENTIFIER = NULL OUTPUT,
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

    DECLARE @grupoId UNIQUEIDENTIFIER = ISNULL(@id, NEWID());
    DECLARE @periodoId UNIQUEIDENTIFIER = @idPeriodoAcademico;

    BEGIN TRY
        -- 1. Validar asignatura
        IF NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @idAsignatura)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'La asignatura especificada no existe en el catálogo.';
            SET @mensajeTecnicoResultado = 'FK @idAsignatura no encontrada en dbo.Asignatura.';
        END

        -- 2. Validar período académico (si es nulo, tomar el más reciente o activo)
        IF @estadoResultado = 1 AND @periodoId IS NULL
        BEGIN
            SELECT TOP 1 @periodoId = id FROM dbo.PeriodoAcademico ORDER BY fechaInicio DESC;
            IF @periodoId IS NULL
            BEGIN
                SET @estadoResultado = 0;
                SET @mensajeUsuarioResultado = 'No hay períodos académicos activos registrados.';
                SET @mensajeTecnicoResultado = 'No se encontró registro en dbo.PeriodoAcademico.';
            END
        END
        ELSE IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @periodoId)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'El período académico especificado no existe.';
            SET @mensajeTecnicoResultado = 'FK @idPeriodoAcademico no encontrada.';
        END

        -- 3. Validar docente
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.Docente WHERE id = @idDocente)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'El docente asignado no existe.';
            SET @mensajeTecnicoResultado = 'FK @idDocente no encontrada en dbo.Docente.';
        END

        -- 4. Validar cupo
        IF @estadoResultado = 1 AND ISNULL(@cupoMaximo, 0) <= 0
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'El cupo máximo del grupo debe ser mayor a cero.';
            SET @mensajeTecnicoResultado = 'Cupo inválido.';
        END

        -- 5. Validar unicidad del código de grupo para la asignatura en el período
        IF @estadoResultado = 1 AND EXISTS (
            SELECT 1 FROM dbo.Grupo
            WHERE asignatura = @idAsignatura AND periodoAcademico = @periodoId AND codigo = @codigo
        )
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = CONCAT('Ya existe un grupo con el código ', @codigo, ' para esta asignatura en el período.');
            SET @mensajeTecnicoResultado = 'Conflicto de unicidad en dbo.Grupo.';
        END

        -- Inserción
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.Grupo (
                id, asignatura, periodoAcademico, codigo, nombre,
                cantidadEstudiantes, cantidadEstudiantesFinalizaron,
                cantidadEstudiantesCancelaronVoluntadPropia,
                cantidadEstudiantesCancelaronAutomaticamente,
                docente, aula
            )
            VALUES (
                @grupoId, @idAsignatura, @periodoId, @codigo, LTRIM(RTRIM(@nombre)),
                @cupoMaximo, 0, 0, 0,
                @idDocente, ISNULL(@aula, 'Aula Por Asignar')
            );

            SET @idGrupoResultado = @grupoId;
            SET @mensajeUsuarioResultado = CONCAT('Grupo ', @nombre, ' creado exitosamente.');
            SET @mensajeTecnicoResultado = 'Inserción completada en dbo.Grupo.';
        END

    END TRY
    BEGIN CATCH
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Error al registrar el grupo académico en la base de datos.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    SELECT
        idCorrelacion = @idCorrelacion,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado,
        @grupoId AS idGrupo,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
