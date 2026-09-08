USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_asignatura]
(
    @id                 UNIQUEIDENTIFIER,
    @codigo             NVARCHAR(50),
    @nombre             NVARCHAR(50),
    @creditos           INT,
    @idPlanEstudio      UNIQUEIDENTIFIER = NULL,
    @semestreNumero     INT = NULL,
    @nombreArea         NVARCHAR(100) = NULL,
    @nombreComponente   NVARCHAR(100) = NULL,
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

        -- Validar si el nuevo código entra en conflicto con otra asignatura
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.Asignatura WHERE LOWER(codigo) = LOWER(LTRIM(RTRIM(@codigo))) AND id <> @id)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = CONCAT('El código ', @codigo, ' ya está en uso por otra asignatura.');
            SET @mensajeTecnicoResultado = 'Conflicto de codigo en dbo.Asignatura.';
        END

        IF @estadoResultado = 1
        BEGIN
            -- Resolver SemestrePlanEstudio si se pasa semestre y plan
            IF @idPlanEstudio IS NOT NULL AND @semestreNumero IS NOT NULL
            BEGIN
                DECLARE @idSemestre UNIQUEIDENTIFIER;
                DECLARE @idSpe UNIQUEIDENTIFIER;

                SELECT TOP 1 @idSemestre = id FROM dbo.Semestre WHERE numero = @semestreNumero;
                IF @idSemestre IS NULL SELECT TOP 1 @idSemestre = id FROM dbo.Semestre;

                SELECT TOP 1 @idSpe = id FROM dbo.SemestrePlanEstudio WHERE planEstudio = @idPlanEstudio AND semestre = @idSemestre;
                IF @idSpe IS NULL
                BEGIN
                    SET @idSpe = NEWID();
                    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES (@idSpe, @idPlanEstudio, @idSemestre);
                END

                UPDATE dbo.Asignatura SET semestrePlanEstudio = @idSpe WHERE id = @id;
            END

            -- Resolver Área si se especifica
            IF @nombreArea IS NOT NULL AND LTRIM(RTRIM(@nombreArea)) <> ''
            BEGIN
                DECLARE @idArea UNIQUEIDENTIFIER;
                SELECT TOP 1 @idArea = id FROM dbo.Area WHERE LOWER(nombre) LIKE '%' + LOWER(LTRIM(RTRIM(@nombreArea))) + '%';
                IF @idArea IS NOT NULL
                BEGIN
                    UPDATE dbo.Asignatura SET area = @idArea WHERE id = @id;
                END
            END

            -- Actualizar campos básicos
            UPDATE dbo.Asignatura
            SET codigo = UPPER(LTRIM(RTRIM(@codigo))),
                nombre = LTRIM(RTRIM(@nombre)),
                credito = ISNULL(@creditos, credito)
            WHERE id = @id;

            SET @mensajeUsuarioResultado = CONCAT('Asignatura ', @nombre, ' actualizada exitosamente.');
            SET @mensajeTecnicoResultado = 'Actualizacion exitosa en dbo.Asignatura.';
        END

    END TRY
    BEGIN CATCH
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Error al actualizar los datos de la asignatura.';
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
