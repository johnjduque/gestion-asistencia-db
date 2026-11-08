-- CULM-001 B2NM (CONTRACT §2.9): fixture de asignatura compartida. Se incluye con :r DENTRO de una transaccion de prueba (no hace COMMIT)
-- y deja declaradas estas variables en el lote del llamador:
--   @progA/@planA/@speA (programa sembrado), @progB/@planB/@speB (segundo programa de la MISMA facultad), @uCA/@uCB (coordinadores),
--   @uDec (decano), @uAdm (administrador), @uT/@docT (docente con DocentePrograma en A y B), @asigOPT (optativa en los dos planes),
--   @grupoG (grupo de OPT, periodo vigente), @eA/@eB/@e0 (estudiantes: vinculo A, vinculo B, sin vinculo) con matricula activa en G.
DECLARE @progA UNIQUEIDENTIFIER = 'B2C3D4E5-0000-0000-0000-000000000001', @planA UNIQUEIDENTIFIER = 'C2D3E4F5-0000-0000-0000-000000000001', @speA UNIQUEIDENTIFIER = 'D2E3F4A5-0000-0000-0000-000000000001';
DECLARE @progB UNIQUEIDENTIFIER = NEWID(), @planB UNIQUEIDENTIFIER = NEWID(), @speB UNIQUEIDENTIFIER = NEWID();
DECLARE @fac UNIQUEIDENTIFIER = (SELECT facultad FROM dbo.Programa WHERE id = @progA);
DECLARE @inst UNIQUEIDENTIFIER = (SELECT institucion FROM dbo.Facultad WHERE id = @fac);
DECLARE @uCA UNIQUEIDENTIFIER = (SELECT c.usuario FROM dbo.Programa p JOIN dbo.Coordinador c ON c.id = p.coordinador WHERE p.id = @progA);
DECLARE @uDec UNIQUEIDENTIFIER = (SELECT d.usuario FROM dbo.Facultad f JOIN dbo.Decano d ON d.id = f.decano WHERE f.id = @fac);
DECLARE @uAdm UNIQUEIDENTIFIER = (SELECT TOP 1 usuario FROM dbo.Administrador WHERE institucion = @inst ORDER BY id);
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @tipoProg UNIQUEIDENTIFIER = (SELECT tipoDePrograma FROM dbo.Programa WHERE id = @progA);
DECLARE @semB UNIQUEIDENTIFIER = (SELECT TOP 1 s.id FROM dbo.Semestre s WHERE s.numero = 7);
DECLARE @area UNIQUEIDENTIFIER = (SELECT area FROM dbo.Asignatura WHERE id = 'E2F3A4B5-0000-0000-0000-000000000001');
DECLARE @comp UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'ESP');
DECLARE @estA UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A');
DECLARE @caracterOPT UNIQUEIDENTIFIER = (SELECT id FROM dbo.CaracterAsignaturaPlan WHERE codigo = N'OPT');
DECLARE @periodo UNIQUEIDENTIFIER = 'F2A3B4C5-0000-0000-0000-000000000001';
DECLARE @uCB UNIQUEIDENTIFIER = NEWID(), @coordB UNIQUEIDENTIFIER = NEWID(), @uT UNIQUEIDENTIFIER = NEWID(), @docT UNIQUEIDENTIFIER = NEWID();
DECLARE @uEA UNIQUEIDENTIFIER = NEWID(), @uEB UNIQUEIDENTIFIER = NEWID(), @uE0 UNIQUEIDENTIFIER = NEWID();
DECLARE @eA UNIQUEIDENTIFIER = NEWID(), @eB UNIQUEIDENTIFIER = NEWID(), @e0 UNIQUEIDENTIFIER = NEWID();
DECLARE @asigOPT UNIQUEIDENTIFIER = NEWID(), @grupoG UNIQUEIDENTIFIER = NEWID();
DECLARE @codGrupo INT = (SELECT ISNULL(MAX(codigo), 0) + 1000 FROM dbo.Grupo);
IF @uCA IS NULL OR @uDec IS NULL OR @uAdm IS NULL OR @semB IS NULL OR @caracterOPT IS NULL OR @estA IS NULL
    THROW 53850, 'TEST FAILED: B2NM fixture: semilla (coordinador, decano, administrador, semestre 7, caracter OPT) ausente; aplique la migracion 17.', 1;

INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
VALUES (@uCB, @tipoCC, 1950000001, N'B2NM', N'', N'CoordB', N'', N'b2nm.coordb@fixture.invalid', 1, 1, N'FIXTURE_DISABLED_ACCOUNT'),
       (@uT,  @tipoCC, 1950000002, N'B2NM', N'', N'DocT', N'', N'b2nm.doct@fixture.invalid', 1, 1, N'FIXTURE_DISABLED_ACCOUNT'),
       (@uEA, @tipoCC, 1950000003, N'B2NM', N'', N'EstA', N'', N'b2nm.esta@fixture.invalid', 1, 1, N'FIXTURE_DISABLED_ACCOUNT'),
       (@uEB, @tipoCC, 1950000004, N'B2NM', N'', N'EstB', N'', N'b2nm.estb@fixture.invalid', 1, 1, N'FIXTURE_DISABLED_ACCOUNT'),
       (@uE0, @tipoCC, 1950000005, N'B2NM', N'', N'Est0', N'', N'b2nm.est0@fixture.invalid', 1, 1, N'FIXTURE_DISABLED_ACCOUNT');
INSERT INTO dbo.Coordinador (id, usuario, estado, facultad) VALUES (@coordB, @uCB, 1, @fac);
INSERT INTO dbo.Docente (id, usuario) VALUES (@docT, @uT);
INSERT INTO dbo.Estudiante (id, usuario) VALUES (@eA, @uEA), (@eB, @uEB), (@e0, @uE0);

INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES (@progB, @fac, @tipoProg, N'B2NM-Programa B', @coordB, 1);
INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@planB, @progB, 99191, 1);
INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES (@speB, @planB, @semB);
INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
SELECT NEWID(), @docT, p.id, tv.id, 1, SYSUTCDATETIME() FROM (VALUES (@progA), (@progB)) p (id) CROSS JOIN dbo.TipoVinculacion tv WHERE tv.codigo = 'PLA';

INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, estado) VALUES (@asigOPT, N'B2NM-OPT', N'B2NM Optativa', 3, @area, @comp, 1);
INSERT INTO dbo.AsignaturaPlanEstudio (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc)
VALUES (NEWID(), @asigOPT, @speA, @caracterOPT, 1, '2020-01-01'), (NEWID(), @asigOPT, @speB, @caracterOPT, 1, '2020-01-01');
INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
    cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
VALUES (@grupoG, @asigOPT, @periodo, @codGrupo, N'B2NM-G', 30, 0, 0, 0, @docT);
INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (NEWID(), @estA, @eA, @grupoG), (NEWID(), @estA, @eB, @grupoG), (NEWID(), @estA, @e0, @grupoG);
INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @eA, @progA), (NEWID(), @eB, @progB);
