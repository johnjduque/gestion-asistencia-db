USE [gestionasistenciadb];
GO
-- CULM-001 B2NM (B2NM-09, 11 parcial): R7 en la matricula. usp_internal_asegurar_estudiante_programa_grupo garantiza que toda matricula
-- tenga EstudiantePrograma en un programa del grupo: un programa -> lo crea; varios -> exige el programa (EST_005 / EST_006);
-- con vinculo previo no crea otro. Transaccion revertida; no deja datos.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_culm001_b2nm_matricula';
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID(), @prog UNIQUEIDENTIFIER, @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT;

    -- grupo G (2 programas), E0 sin vinculo, sin programa elegido -> EST_005 y no crea nada
    EXEC dbo.usp_internal_asegurar_estudiante_programa_grupo @idEstudiante = @e0, @idGrupo = @grupoG, @idProgramaElegido = NULL, @idCorrelacion = @c,
        @idProgramaResultado = @prog OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 1 OR @mt NOT LIKE N'%EST_005%' THROW 53871, 'TEST FAILED: B2NM-09 grupo con varios programas sin programa debe dar EST_005.', 1;
    IF EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @e0) THROW 53872, 'TEST FAILED: B2NM-09 EST_005 no debe crear vinculo.', 1;

    -- programa ajeno al grupo -> EST_006
    EXEC dbo.usp_internal_asegurar_estudiante_programa_grupo @idEstudiante = @e0, @idGrupo = @grupoG, @idProgramaElegido = @fac, @idCorrelacion = @c,
        @idProgramaResultado = @prog OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 1 OR @mt NOT LIKE N'%EST_006%' THROW 53873, 'TEST FAILED: B2NM-09 programa ajeno debe dar EST_006.', 1;

    -- programa B del grupo -> crea el vinculo con B
    EXEC dbo.usp_internal_asegurar_estudiante_programa_grupo @idEstudiante = @e0, @idGrupo = @grupoG, @idProgramaElegido = @progB, @idCorrelacion = @c,
        @idProgramaResultado = @prog OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 0 OR @prog <> @progB OR NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @e0 AND programa = @progB)
        THROW 53874, 'TEST FAILED: B2NM-09 con programa del grupo debe crear el vinculo.', 1;

    -- con vinculo previo no crea otro (aunque se pida el otro programa)
    EXEC dbo.usp_internal_asegurar_estudiante_programa_grupo @idEstudiante = @e0, @idGrupo = @grupoG, @idProgramaElegido = @progA, @idCorrelacion = @c,
        @idProgramaResultado = @prog OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 0 OR (SELECT COUNT(*) FROM dbo.EstudiantePrograma WHERE estudiante = @e0) <> 1 THROW 53875, 'TEST FAILED: B2NM-09 con vinculo previo no debe crear otro.', 1;

    -- grupo de un solo programa (ARQ-402): crea el vinculo con ese programa sin pedir programa
    DECLARE @grupo1 UNIQUEIDENTIFIER = NEWID(), @cod1 INT = (SELECT ISNULL(MAX(codigo), 0) + 1 FROM dbo.Grupo);
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@grupo1, 'E2F3A4B5-0000-0000-0000-000000000001', @periodo, @cod1, N'B2NM-G1', 30, 0, 0, 0, @docT);
    EXEC dbo.usp_internal_asegurar_estudiante_programa_grupo @idEstudiante = @eB, @idGrupo = @grupo1, @idProgramaElegido = NULL, @idCorrelacion = @c,
        @idProgramaResultado = @prog OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 0 OR @prog <> @progA OR NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @eB AND programa = @progA)
        THROW 53876, 'TEST FAILED: B2NM-09 grupo de un programa debe crear el vinculo con ese programa.', 1;

    PRINT 'TEST_PASS:CULM001_B2NM_MATRICULA';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 53899, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
