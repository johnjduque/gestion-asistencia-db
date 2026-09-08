USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_asignatura]
(
    @id                 UNIQUEIDENTIFIER = NULL,
    @codigo             NVARCHAR(50),
    @nombre             NVARCHAR(50),
    @creditos           INT,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @semestreNumero     INT = 1,
    @nombreArea         NVARCHAR(100) = NULL,
    @nombreComponente   NVARCHAR(100) = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER = NULL,
    @idAsignaturaResultado   UNIQUEIDENTIFIER = NULL OUTPUT,
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

    DECLARE @asigId UNIQUEIDENTIFIER = ISNULL(@id, NEWID());
    DECLARE @idArea UNIQUEIDENTIFIER;
    DECLARE @idComponente UNIQUEIDENTIFIER;
    DECLARE @idSemestrePlanEstudio UNIQUEIDENTIFIER;
    DECLARE @idSemestre UNIQUEIDENTIFIER;

    BEGIN TRY
        -- Validar código obligatorio
        IF @codigo IS NULL OR LTRIM(RTRIM(@codigo)) = ''
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'El código de la asignatura es obligatorio.';
            SET @mensajeTecnicoResultado = 'Parametro @codigo es nulo o vacio.';
        END

        -- Validar nombre obligatorio
        IF @estadoResultado = 1 AND (@nombre IS NULL OR LTRIM(RTRIM(@nombre)) = '')
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'El nombre de la asignatura es obligatorio.';
            SET @mensajeTecnicoResultado = 'Parametro @nombre es nulo o vacio.';
        END

        -- Validar créditos positivos
        IF @estadoResultado = 1 AND (ISNULL(@creditos, 0) <= 0)
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = 'Los créditos académicos deben ser mayores a cero.';
            SET @mensajeTecnicoResultado = 'Parametro @creditos debe ser mayor a 0.';
        END

        -- Validar unicidad del código
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.Asignatura WHERE LOWER(codigo) = LOWER(LTRIM(RTRIM(@codigo))))
        BEGIN
            SET @estadoResultado = 0;
            SET @mensajeUsuarioResultado = CONCAT('Ya existe una asignatura registrada con el código ', @codigo, '.');
            SET @mensajeTecnicoResultado = 'Violacion de unicidad de codigo en dbo.Asignatura.';
        END

        -- Resolver Área
        IF @estadoResultado = 1
        BEGIN
            IF @nombreArea IS NOT NULL AND LTRIM(RTRIM(@nombreArea)) <> ''
            BEGIN
                SELECT TOP 1 @idArea = id FROM dbo.Area WHERE LOWER(nombre) LIKE '%' + LOWER(LTRIM(RTRIM(@nombreArea))) + '%';
            END

            IF @idArea IS NULL
            BEGIN
                SELECT TOP 1 @idArea = id FROM dbo.Area;
            END

            IF @idArea IS NULL
            BEGIN
                SET @idArea = NEWID();
                INSERT INTO dbo.Area (id, nombre) VALUES (@idArea, ISNULL(@nombreArea, 'Ciencias de la Computación'));
            END
        END

        -- Resolver Componente
        IF @estadoResultado = 1
        BEGIN
            IF @nombreComponente IS NOT NULL AND LTRIM(RTRIM(@nombreComponente)) <> ''
            BEGIN
                SELECT TOP 1 @idComponente = id FROM dbo.Componente WHERE LOWER(nombre) LIKE '%' + LOWER(LTRIM(RTRIM(@nombreComponente))) + '%';
            END

            IF @idComponente IS NULL
            BEGIN
                SELECT TOP 1 @idComponente = id FROM dbo.Componente;
            END

            IF @idComponente IS NULL
            BEGIN
                SET @idComponente = NEWID();
                INSERT INTO dbo.Componente (id, nombre) VALUES (@idComponente, ISNULL(@nombreComponente, 'especificas'));
            END
        END

        -- Resolver Semestre y SemestrePlanEstudio
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idSemestre = id FROM dbo.Semestre WHERE numero = @semestreNumero;
            IF @idSemestre IS NULL
            BEGIN
                SELECT TOP 1 @idSemestre = id FROM dbo.Semestre;
            END

            SELECT TOP 1 @idSemestrePlanEstudio = id 
            FROM dbo.SemestrePlanEstudio 
            WHERE planEstudio = @idPlanEstudio AND semestre = @idSemestre;

            IF @idSemestrePlanEstudio IS NULL
            BEGIN
                SET @idSemestrePlanEstudio = NEWID();
                INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) 
                VALUES (@idSemestrePlanEstudio, @idPlanEstudio, @idSemestre);
            END
        END

        -- Inserción de la Asignatura
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.Asignatura (
                id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado
            )
            VALUES (
                @asigId,
                UPPER(LTRIM(RTRIM(@codigo))),
                LTRIM(RTRIM(@nombre)),
                @creditos,
                @idArea,
                @idComponente,
                @idSemestrePlanEstudio,
                1
            );

            SET @idAsignaturaResultado = @asigId;
            SET @mensajeUsuarioResultado = CONCAT('Asignatura ', @nombre, ' (', @codigo, ') creada exitosamente.');
            SET @mensajeTecnicoResultado = 'Asignatura insertada con exito en dbo.Asignatura.';
        END

    END TRY
    BEGIN CATCH
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Error al registrar la asignatura en la base de datos.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    -- Retorno en conjunto de resultados para JDBC
    SELECT
        idCorrelacion = @idCorrelacion,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado,
        @asigId AS idAsignatura,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
