USE [gestionasistenciadb];
GO
-- DEC-076 (periodo al crear un grupo) y DEC-077 (programa responsable del grupo), 2026-11-20.
-- Usa el fixture de asignatura compartida de B2NM: @asigOPT en los planes de A (coordinador CA) y B (coordinador CB), grupo @grupoG.
--   R1  Grupo.programaResponsable = A: ufn_programas_grupo_responsable devuelve solo A; gestiona CA y el titular; CB y un
--       coordinador ajeno reciben SEC_002 (usp_validar_gestion_grupo_coordinador_o_titular_interno).
--   R2  Sesiones del grupo: solo CA aprueba/cancela (usp_validar_coordinador_sesion_interno) y el aviso de sesion sin toma va
--       solo a CA (usp_consultar_destinatarios_aviso_sin_toma).
--   R3  Sin responsable guardado (grupos anteriores): el programa con mas estudiantes del grupo; a igualdad, el de menor nombre.
--   R4  usp_crear_grupo: CB crea un grupo de la asignatura compartida y queda con B como responsable; CB pidiendo A -> SEC_002;
--       un coordinador sin programas de la asignatura -> SEC_002 y no queda fila.
--   P1  usp_crear_grupo sin periodo usa el periodo ACTIVO de inicio mas reciente (no el de mayor anio).
--   P2  usp_crear_grupo en un periodo CERRADO -> PER_010 y no queda fila.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_dec076_dec077_creacion_grupo';
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @esCoord BIT, @docTitular UNIQUEIDENTIFIER, @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @grupoSesion UNIQUEIDENTIFIER;
    -- Coordinador ajeno: coordina un programa propio que no tiene la asignatura (la semilla limpia no trae otro coordinador).
    DECLARE @uC0 UNIQUEIDENTIFIER = NEWID(), @coordC0 UNIQUEIDENTIFIER = NEWID(), @progC0 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES (@uC0, @tipoCC, 1950000077, N'DEC077', N'', N'Coord0', N'', N'dec077.coord0@fixture.invalid', 1, 1);
    INSERT INTO dbo.Coordinador (id, usuario, estado, facultad) VALUES (@coordC0, @uC0, 1, @fac);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES (@progC0, @fac, @tipoProg, N'DEC077-Programa C0', @coordC0, 1);

    -- R1: responsable guardado = A
    UPDATE dbo.Grupo SET programaResponsable = @progA WHERE id = @grupoG;
    IF (SELECT COUNT(*) FROM dbo.ufn_programas_grupo_responsable(@grupoG)) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo_responsable(@grupoG) WHERE idPrograma = @progA)
        THROW 54002, 'TEST FAILED: DEC-077 R1 el responsable del grupo debe ser solo A.', 1;

    EXEC dbo.usp_validar_gestion_grupo_coordinador_o_titular_interno @idGrupo = @grupoG, @idUsuarioEjecutor = @uCA, @idCorrelacion = @c,
        @ejecutorEsCoordinador = @esCoord OUTPUT, @idDocenteTitular = @docTitular OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 0 OR @esCoord = 0 THROW 54003, 'TEST FAILED: DEC-077 R1 CA (programa responsable) debe gestionar el grupo.', 1;
    EXEC dbo.usp_validar_gestion_grupo_coordinador_o_titular_interno @idGrupo = @grupoG, @idUsuarioEjecutor = @uCB, @idCorrelacion = @c,
        @ejecutorEsCoordinador = @esCoord OUTPUT, @idDocenteTitular = @docTitular OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 1 OR @mt NOT LIKE N'%SEC_002%' THROW 54004, 'TEST FAILED: DEC-077 R1 CB (otro programa del grupo) debe recibir SEC_002.', 1;
    EXEC dbo.usp_validar_gestion_grupo_coordinador_o_titular_interno @idGrupo = @grupoG, @idUsuarioEjecutor = @uC0, @idCorrelacion = @c,
        @ejecutorEsCoordinador = @esCoord OUTPUT, @idDocenteTitular = @docTitular OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 1 OR @mt NOT LIKE N'%SEC_002%' THROW 54005, 'TEST FAILED: DEC-077 R1 un coordinador ajeno debe recibir SEC_002.', 1;
    EXEC dbo.usp_validar_gestion_grupo_coordinador_o_titular_interno @idGrupo = @grupoG, @idUsuarioEjecutor = @uT, @idCorrelacion = @c,
        @ejecutorEsCoordinador = @esCoord OUTPUT, @idDocenteTitular = @docTitular OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 0 THROW 54006, 'TEST FAILED: DEC-077 R1 el titular debe gestionar el grupo.', 1;

    -- R2: sesion manual (procedencia NULL) del grupo, terminada, sin toma
    DECLARE @sesion UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@sesion, N'DEC-077 S1', 1, N'DEC077-S1', 1, @grupoG, DATEADD(HOUR, -3, SYSUTCDATETIME()), DATEADD(HOUR, -1, SYSUTCDATETIME()));

    EXEC dbo.usp_validar_coordinador_sesion_interno @idSesion = @sesion, @idUsuarioEjecutor = @uCA, @idCorrelacion = @c,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @idGrupo = @grupoSesion;
    IF @ok = 0 OR @grupoSesion <> @grupoG THROW 54007, 'TEST FAILED: DEC-077 R2 CA debe poder resolver las sesiones del grupo.', 1;
    EXEC dbo.usp_validar_coordinador_sesion_interno @idSesion = @sesion, @idUsuarioEjecutor = @uCB, @idCorrelacion = @c,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @idGrupo = @grupoSesion;
    IF @ok = 1 OR @mt NOT LIKE N'%SEC_002%' THROW 54008, 'TEST FAILED: DEC-077 R2 CB no debe aprobar ni cancelar sesiones del grupo (SEC_002).', 1;

    DECLARE @aviso TABLE (idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(200),
        nombreGrupo NVARCHAR(200), nombreDocente NVARCHAR(400), fechaHoraInicioUtc DATETIME2, fechaHoraFinUtc DATETIME2,
        idUsuarioCoordinador UNIQUEIDENTIFIER, nombreCoordinador NVARCHAR(400), correoCoordinador NVARCHAR(200));
    INSERT INTO @aviso EXEC dbo.usp_consultar_destinatarios_aviso_sin_toma @idSesion = @sesion, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM @aviso) <> 1 OR NOT EXISTS (SELECT 1 FROM @aviso WHERE idUsuarioCoordinador = @uCA)
        THROW 54009, 'TEST FAILED: DEC-077 R2 el aviso de sesion sin toma debe ir solo al coordinador responsable (CA).', 1;

    -- R3: sin responsable guardado. Empate (EA en A, EB en B): menor nombre. Con un segundo estudiante de B: gana B.
    UPDATE dbo.Grupo SET programaResponsable = NULL WHERE id = @grupoG;
    DECLARE @porNombre UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Programa WHERE id IN (@progA, @progB) ORDER BY nombre, id);
    IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo_responsable(@grupoG) WHERE idPrograma = @porNombre)
        THROW 54010, 'TEST FAILED: DEC-077 R3 a igualdad de estudiantes el responsable es el programa de menor nombre.', 1;
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @e0, @progB);
    IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo_responsable(@grupoG) WHERE idPrograma = @progB)
        THROW 54011, 'TEST FAILED: DEC-077 R3 sin responsable guardado gana el programa con mas estudiantes del grupo.', 1;

    -- R4: creacion por el coordinador
    DECLARE @res TABLE (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @g1 UNIQUEIDENTIFIER = NEWID(), @g2 UNIQUEIDENTIFIER = NEWID(), @g3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @cod1 INT = @codGrupo + 1, @cod2 INT = @codGrupo + 2, @cod3 INT = @codGrupo + 3;

    INSERT INTO @res EXEC dbo.usp_crear_grupo @idGrupo = @g1, @idAsignatura = @asigOPT, @idPeriodoAcademico = @periodo, @codigo = @cod1,
        @nombre = N'DEC077-G1', @idDocente = @docT, @idCorrelacion = @c, @idUsuarioEjecutor = @uCB;
    IF NOT EXISTS (SELECT 1 FROM @res WHERE estadoResultado = 1) THROW 54012, 'TEST FAILED: DEC-077 R4 CB debe crear el grupo de la asignatura compartida.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @g1 AND programaResponsable = @progB)
        THROW 54013, 'TEST FAILED: DEC-077 R4 el grupo creado por CB debe tener a B como programa responsable.', 1;

    DELETE FROM @res;
    INSERT INTO @res EXEC dbo.usp_crear_grupo @idGrupo = @g2, @idAsignatura = @asigOPT, @idPeriodoAcademico = @periodo, @codigo = @cod2,
        @nombre = N'DEC077-G2', @idDocente = @docT, @idCorrelacion = @c, @idUsuarioEjecutor = @uCB, @idProgramaResponsable = @progA;
    IF NOT EXISTS (SELECT 1 FROM @res WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'%SEC_002%')
        THROW 54014, 'TEST FAILED: DEC-077 R4 CB no puede dejar como responsable un programa que no coordina (SEC_002).', 1;
    IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @g2) THROW 54015, 'TEST FAILED: DEC-077 R4 el grupo rechazado no debe persistir.', 1;

    DELETE FROM @res;
    INSERT INTO @res EXEC dbo.usp_crear_grupo @idGrupo = @g3, @idAsignatura = @asigOPT, @idPeriodoAcademico = @periodo, @codigo = @cod3,
        @nombre = N'DEC077-G3', @idDocente = @docT, @idCorrelacion = @c, @idUsuarioEjecutor = @uC0;
    IF NOT EXISTS (SELECT 1 FROM @res WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'%SEC_002%')
        THROW 54016, 'TEST FAILED: DEC-077 R4 un coordinador sin programas de la asignatura debe recibir SEC_002.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @g3) THROW 54017, 'TEST FAILED: DEC-077 R4 el grupo rechazado no debe persistir.', 1;

    -- P1: sin periodo se usa el ACTIVO de inicio mas reciente
    DECLARE @periodoEnCurso UNIQUEIDENTIFIER = (SELECT TOP (1) id FROM dbo.uv_periodo_academico WHERE estado = 'ACTIVO' ORDER BY fechaInicio DESC, id);
    IF @periodoEnCurso IS NOT NULL
    BEGIN
        DECLARE @g4 UNIQUEIDENTIFIER = NEWID(), @cod4 INT = @codGrupo + 4;
        DELETE FROM @res;
        INSERT INTO @res EXEC dbo.usp_crear_grupo @idGrupo = @g4, @idAsignatura = @asigOPT, @idPeriodoAcademico = NULL, @codigo = @cod4,
            @nombre = N'DEC076-G4', @idDocente = @docT, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
        IF NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @g4 AND periodoAcademico = @periodoEnCurso)
            THROW 54018, 'TEST FAILED: DEC-076 P1 sin periodo el grupo debe quedar en el periodo en curso.', 1;
    END

    -- P2: periodo CERRADO
    DECLARE @periodoCerrado UNIQUEIDENTIFIER = NEWID(), @g5 UNIQUEIDENTIFIER = NEWID(), @cod5 INT = @codGrupo + 5;
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@periodoCerrado, @inst, N'DEC076-2001-1', 990761, '2001-02-01', '2001-06-30', 2001);
    DELETE FROM @res;
    INSERT INTO @res EXEC dbo.usp_crear_grupo @idGrupo = @g5, @idAsignatura = @asigOPT, @idPeriodoAcademico = @periodoCerrado, @codigo = @cod5,
        @nombre = N'DEC076-G5', @idDocente = @docT, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM @res WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'%PER_010%' AND mensajeUsuarioResultado LIKE N'%DEC076-2001-1%')
        THROW 54019, 'TEST FAILED: DEC-076 P2 un periodo cerrado debe dar PER_010 con el nombre del periodo.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @g5) THROW 54020, 'TEST FAILED: DEC-076 P2 el grupo rechazado no debe persistir.', 1;

    PRINT 'TEST_PASS:DEC076_DEC077_CREACION_GRUPO';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 54099, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
