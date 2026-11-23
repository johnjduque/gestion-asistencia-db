USE [gestionasistenciadb];
GO
-- Migracion 63: semestre actual del estudiante en el programa (usp_actualizar_semestre_estudiante_programa y directorio del coordinador).
-- Usa el fixture de B2NM: programas A (coordina CA) y B (coordina CB); EA vinculado a A, EB a B, E0 sin vinculo.
--   S1  el coordinador de A fija el semestre de EA y el directorio devuelve idPrograma, nombrePrograma y semestreActual;
--   S2  NULL limpia el semestre;
--   S3  el coordinador de B no puede cambiar el semestre de EA en el programa A: SEC_002 y el valor no cambia;
--   S4  un estudiante sin vinculo con el programa: EST_008;
--   S5  un semestre fuera del rango del catalogo (0 y mayor al maximo): EST_009 y el valor no cambia.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_semestre_estudiante_programa';
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @fueraDeRango INT = (SELECT MAX(numero) + 1 FROM dbo.Semestre);
    DECLARE @nombreA NVARCHAR(50) = (SELECT nombre FROM dbo.Programa WHERE id = @progA);

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX) NULL, mensajeTecnicoResultado NVARCHAR(MAX) NULL, estadoResultado BIT NOT NULL);
    CREATE TABLE #dl (id UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, tipoIdentificacionId UNIQUEIDENTIFIER, numeroIdentificacion INT,
        primerApellido NVARCHAR(100), segundoApellido NVARCHAR(100), primerNombre NVARCHAR(100), segundoNombre NVARCHAR(100), nombreCompleto NVARCHAR(400),
        correo NVARCHAR(100), estaActivoUsuario BIT, totalRegistros INT, idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50), semestreActual INT);

    -- S1
    INSERT INTO #r EXEC dbo.usp_actualizar_semestre_estudiante_programa @idEstudiante = @eA, @idPrograma = @progA, @semestreActual = 3,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'%EST_007%')
       OR (SELECT semestreActual FROM dbo.EstudiantePrograma WHERE estudiante = @eA AND programa = @progA) <> 3
        THROW 55001, 'TEST FAILED: SEMESTRE S1 el coordinador de A debe fijar el semestre 3 de EA.', 1;
    INSERT INTO #dl EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @nombre = N'B2NM', @idPrograma = @progA;
    IF NOT EXISTS (SELECT 1 FROM #dl WHERE id = @eA AND idPrograma = @progA AND nombrePrograma = @nombreA AND semestreActual = 3)
        THROW 55002, 'TEST FAILED: SEMESTRE S1 el directorio debe devolver programa y semestre de EA.', 1;
    DELETE FROM #dl;
    INSERT INTO #dl EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @nombre = N'B2NM';
    IF NOT EXISTS (SELECT 1 FROM #dl WHERE id = @eA AND idPrograma = @progA AND semestreActual = 3)
       OR EXISTS (SELECT 1 FROM #dl WHERE id = @eB)
        THROW 55003, 'TEST FAILED: SEMESTRE S1 sin @idPrograma el directorio trae a EA con su programa y semestre y no a EB (programa ajeno).', 1;

    -- S2
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_semestre_estudiante_programa @idEstudiante = @eA, @idPrograma = @progA, @semestreActual = NULL,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @eA AND programa = @progA AND semestreActual IS NOT NULL)
        THROW 55004, 'TEST FAILED: SEMESTRE S2 NULL debe limpiar el semestre.', 1;
    UPDATE dbo.EstudiantePrograma SET semestreActual = 2 WHERE estudiante = @eA AND programa = @progA;

    -- S3
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_semestre_estudiante_programa @idEstudiante = @eA, @idPrograma = @progA, @semestreActual = 5,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCB;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'%SEC_002%')
       OR (SELECT semestreActual FROM dbo.EstudiantePrograma WHERE estudiante = @eA AND programa = @progA) <> 2
        THROW 55005, 'TEST FAILED: SEMESTRE S3 otro coordinador debe recibir SEC_002 sin cambiar el semestre.', 1;

    -- S4
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_semestre_estudiante_programa @idEstudiante = @e0, @idPrograma = @progA, @semestreActual = 5,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'%EST_008%')
        THROW 55006, 'TEST FAILED: SEMESTRE S4 un estudiante sin vinculo con el programa debe dar EST_008.', 1;

    -- S5
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_semestre_estudiante_programa @idEstudiante = @eA, @idPrograma = @progA, @semestreActual = 0,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    INSERT INTO #r EXEC dbo.usp_actualizar_semestre_estudiante_programa @idEstudiante = @eA, @idPrograma = @progA, @semestreActual = @fueraDeRango,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'%EST_009%') <> 2
       OR (SELECT semestreActual FROM dbo.EstudiantePrograma WHERE estudiante = @eA AND programa = @progA) <> 2
        THROW 55007, 'TEST FAILED: SEMESTRE S5 un semestre fuera del rango debe dar EST_009 sin cambiar el valor.', 1;

    PRINT 'TEST_PASS:SEMESTRE_ESTUDIANTE_PROGRAMA';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 55099, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
