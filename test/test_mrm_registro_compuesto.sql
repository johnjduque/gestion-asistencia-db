USE [gestionasistenciadb];
GO
-- CULM-001 / DEC-065 (5) / HU116, HU076, F-ADM-024: registro compuesto en una sola transaccion.
--   REG_00 objetos, EXECUTE del rol runtime solo en los dos SP publicos nuevos (los nucleos *_interno no)
--   REG_01 decano + facultad: persona, rol, facultad y vinculo creados; salida con idDecano, idFacultad y nombreFacultad
--   REG_02 facultad duplicada (GEN_003), nombre invalido (GEN_002) e institucion inexistente (GEN_001): error y NINGUNA persona ni rol creados
--   REG_03 la persona ya es decano activo (DEC_020): error sin crear facultad
--   REG_04 RBAC de decano + facultad: solo el administrador (SEC_001); ejecutor obligatorio (GEN_002)
--   REG_05 coordinador + programa: persona, rol (con facultad), programa activo con ese coordinador; el decano recien creado ya es titular
--   REG_06 programa invalido (tipo PROG_004, nombre repetido PROG_003, modalidad PROG_006, nombre GEN_002): error y NINGUNA persona creada
--   REG_07 RBAC y titularidad de coordinador + programa: SEC_001 para docente/coordinador/administrador, SEC_002 para el decano de otra facultad
--   REG_08 un fallo posterior a la escritura (PROG_005: usuario inactivo) revierte la persona, el rol y el programa
--   REG_09 los SP publicos anteriores siguen funcionando (usp_crear_decano, usp_crear_coordinador)
--   REG_10 @@TRANCOUNT = 0 al terminar
-- Todo dentro de transacciones revertidas.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_mrm_registro_compuesto';
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @tran INT = @@TRANCOUNT;
    DECLARE @pwd NVARCHAR(500) = N'HashBackend_RegCompuesto1234567890';

    -- Actores y datos base tomados de la semilla (sin identificadores quemados)
    DECLARE @uAdm UNIQUEIDENTIFIER = (SELECT TOP 1 usuario FROM dbo.Administrador ORDER BY usuario);
    DECLARE @uDoc UNIQUEIDENTIFIER = (SELECT TOP 1 usuario FROM dbo.Docente ORDER BY usuario);
    DECLARE @uCoo UNIQUEIDENTIFIER = (SELECT TOP 1 usuario FROM dbo.Coordinador ORDER BY usuario);
    DECLARE @uDec UNIQUEIDENTIFIER, @facDec UNIQUEIDENTIFIER, @idDecDec UNIQUEIDENTIFIER;
    SELECT TOP 1 @uDec = di.idUsuario, @idDecDec = di.id, @facDec = f.id
    FROM dbo.uv_decano_identidad di INNER JOIN dbo.uv_facultad f ON f.idDecano = di.id
    WHERE f.estaActivaFacultad = 1 ORDER BY f.id;
    DECLARE @ins UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1 ORDER BY id);
    DECLARE @tipo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_programa WHERE estaActivoTipoPrograma = 1 ORDER BY id);
    DECLARE @modalidad UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_modalidad WHERE estaActivoModalidad = 1 ORDER BY id);
    DECLARE @jornada UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_jornada WHERE estaActivoJornada = 1 ORDER BY id);
    IF @uAdm IS NULL OR @uDoc IS NULL OR @uCoo IS NULL OR @uDec IS NULL OR @facDec IS NULL OR @ins IS NULL OR @tipo IS NULL
        THROW 59101, 'TEST FAILED CULM001_MRM_REG: falta la semilla (administrador, docente, coordinador, decano con facultad, institucion o tipo de programa).', 1;

    CREATE TABLE #reg_d (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL,
        idDecano UNIQUEIDENTIFIER NULL, idFacultad UNIQUEIDENTIFIER NULL, nombreFacultad NVARCHAR(150) NULL);
    CREATE TABLE #reg_c (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL,
        idCoordinador UNIQUEIDENTIFIER NULL, idPrograma UNIQUEIDENTIFIER NULL, nombrePrograma NVARCHAR(100) NULL);

    -- REG_00: objetos y permisos
    IF OBJECT_ID(N'dbo.usp_crear_decano_con_facultad', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_crear_coordinador_con_programa', N'P') IS NULL
       OR OBJECT_ID(N'dbo.usp_crear_decano_interno', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_crear_coordinador_interno', N'P') IS NULL
        THROW 59102, 'TEST FAILED CULM001_MRM_REG_00: faltan los SP compuestos o sus nucleos (migracion 32).', 1;
    IF (SELECT COUNT(*) FROM sys.database_permissions dp WHERE dp.class = 1 AND dp.permission_name = N'EXECUTE' AND dp.state IN ('G', 'W')
          AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
          AND dp.major_id IN (OBJECT_ID(N'dbo.usp_crear_decano_con_facultad'), OBJECT_ID(N'dbo.usp_crear_coordinador_con_programa'))) <> 2
       OR EXISTS (SELECT 1 FROM sys.database_permissions dp WHERE dp.class = 1 AND dp.permission_name = N'EXECUTE' AND dp.state IN ('G', 'W')
          AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
          AND dp.major_id IN (OBJECT_ID(N'dbo.usp_crear_decano_interno'), OBJECT_ID(N'dbo.usp_crear_coordinador_interno')))
        THROW 59103, 'TEST FAILED CULM001_MRM_REG_00: EXECUTE al rol runtime solo en los dos SP compuestos, nunca en los nucleos.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_REG_00_OBJETOS_Y_PERMISOS';

    -- REG_01: decano + facultad
    DECLARE @decanosAntes INT = (SELECT COUNT(*) FROM dbo.Decano), @facultadesAntes INT = (SELECT COUNT(*) FROM dbo.Facultad), @usuariosAntes INT = (SELECT COUNT(*) FROM dbo.Usuario);
    INSERT #reg_d EXEC dbo.usp_crear_decano_con_facultad @numeroIdentificacion = 990100001, @primerNombre = N'Ana', @segundoNombre = N'Maria', @primerApellido = N'Registro',
        @segundoApellido = N'Compuesto', @correo = N'reg.decano1@test.local', @password = @pwd, @nombreFacultad = N'  Facultad Registro Compuesto  ', @codigoFacultad = N'FRC',
        @idInstitucion = @ins, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    DECLARE @idDec1 UNIQUEIDENTIFIER = (SELECT idDecano FROM #reg_d), @idFac1 UNIQUEIDENTIFIER = (SELECT idFacultad FROM #reg_d);
    IF NOT EXISTS (SELECT 1 FROM #reg_d WHERE estadoResultado = 1 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]004|%'
                     AND idDecano IS NOT NULL AND idFacultad IS NOT NULL AND nombreFacultad = N'Facultad Registro Compuesto')
        THROW 59110, 'TEST FAILED CULM001_MRM_REG_01: el compuesto debe responder GEN_004 con idDecano, idFacultad y el nombre recortado.', 1;
    IF (SELECT COUNT(*) FROM dbo.Decano) <> @decanosAntes + 1 OR (SELECT COUNT(*) FROM dbo.Facultad) <> @facultadesAntes + 1 OR (SELECT COUNT(*) FROM dbo.Usuario) <> @usuariosAntes + 1
        THROW 59111, 'TEST FAILED CULM001_MRM_REG_01: debe crear exactamente una persona, un decano y una facultad.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Decano d INNER JOIN dbo.uv_usuario u ON u.id = d.usuario WHERE d.id = @idDec1 AND u.correo = N'reg.decano1@test.local'
                     AND u.numeroIdentificacion = N'990100001' AND u.estaActivoUsuario = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.Facultad f WHERE f.id = @idFac1 AND f.nombre = N'Facultad Registro Compuesto' AND f.decano = @idDec1 AND f.institucion = @ins AND f.estado = 1)
        THROW 59112, 'TEST FAILED CULM001_MRM_REG_01: la persona, el decano y la facultad deben quedar vinculados y activos.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE id = @idFac1 AND idDecano = @idDec1 AND estaActivaFacultad = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_decano_identidad WHERE id = @idDec1)
        THROW 59113, 'TEST FAILED CULM001_MRM_REG_01: las vistas deben exponer la facultad y el decano nuevos.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_REG_01_DECANO_CON_FACULTAD';

    -- REG_02: fallos de la facultad => nada creado
    SET @decanosAntes = (SELECT COUNT(*) FROM dbo.Decano); SET @facultadesAntes = (SELECT COUNT(*) FROM dbo.Facultad); SET @usuariosAntes = (SELECT COUNT(*) FROM dbo.Usuario);
    TRUNCATE TABLE #reg_d;
    INSERT #reg_d EXEC dbo.usp_crear_decano_con_facultad @numeroIdentificacion = 990100002, @primerNombre = N'Ana', @segundoNombre = N'Maria', @primerApellido = N'Registro',
        @segundoApellido = N'Dos', @correo = N'reg.decano2@test.local', @password = @pwd, @nombreFacultad = N'FACULTAD registro COMPUESTO', @idInstitucion = @ins, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #reg_d WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]003|%' AND idDecano IS NULL AND idFacultad IS NULL AND nombreFacultad IS NULL)
        THROW 59120, 'TEST FAILED CULM001_MRM_REG_02: la facultad duplicada (sin distinguir mayusculas) debe responder GEN_003 con salidas NULL.', 1;
    TRUNCATE TABLE #reg_d;
    INSERT #reg_d EXEC dbo.usp_crear_decano_con_facultad @numeroIdentificacion = 990100002, @primerNombre = N'Ana', @segundoNombre = N'Maria', @primerApellido = N'Registro',
        @segundoApellido = N'Dos', @correo = N'reg.decano2@test.local', @password = @pwd, @nombreFacultad = N'ab', @idInstitucion = @ins, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #reg_d WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]002|%')
        THROW 59121, 'TEST FAILED CULM001_MRM_REG_02: un nombre de menos de 3 caracteres debe responder GEN_002.', 1;
    TRUNCATE TABLE #reg_d;
    DECLARE @nombreLargo NVARCHAR(150) = REPLICATE(N'X', 51);
    INSERT #reg_d EXEC dbo.usp_crear_decano_con_facultad @numeroIdentificacion = 990100002, @primerNombre = N'Ana', @segundoNombre = N'Maria', @primerApellido = N'Registro',
        @segundoApellido = N'Dos', @correo = N'reg.decano2@test.local', @password = @pwd, @nombreFacultad = @nombreLargo, @idInstitucion = @ins, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #reg_d WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]002|%')
        THROW 59122, 'TEST FAILED CULM001_MRM_REG_02: un nombre de mas de 50 caracteres debe responder GEN_002.', 1;
    TRUNCATE TABLE #reg_d;
    DECLARE @insFalsa UNIQUEIDENTIFIER = NEWID();
    INSERT #reg_d EXEC dbo.usp_crear_decano_con_facultad @numeroIdentificacion = 990100002, @primerNombre = N'Ana', @segundoNombre = N'Maria', @primerApellido = N'Registro',
        @segundoApellido = N'Dos', @correo = N'reg.decano2@test.local', @password = @pwd, @nombreFacultad = N'Facultad Sin Institucion', @idInstitucion = @insFalsa, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #reg_d WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]001|%' AND idDecano IS NULL)
        THROW 59123, 'TEST FAILED CULM001_MRM_REG_02: la institucion inexistente debe responder GEN_001.', 1;
    IF (SELECT COUNT(*) FROM dbo.Decano) <> @decanosAntes OR (SELECT COUNT(*) FROM dbo.Facultad) <> @facultadesAntes OR (SELECT COUNT(*) FROM dbo.Usuario) <> @usuariosAntes
       OR EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE correo = N'reg.decano2@test.local')
        THROW 59124, 'TEST FAILED CULM001_MRM_REG_02: un fallo de la facultad no debe dejar persona, decano ni facultad.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_REG_02_FALLO_FACULTAD_NO_DEJA_PERSONA';

    -- REG_03: la persona ya es decano activo
    DECLARE @correoDecanoExistente NVARCHAR(100) = (SELECT correo FROM dbo.uv_usuario WHERE id = @uDec);
    TRUNCATE TABLE #reg_d;
    INSERT #reg_d EXEC dbo.usp_crear_decano_con_facultad @numeroIdentificacion = 990100003, @primerNombre = N'Ana', @segundoNombre = N'Maria', @primerApellido = N'Registro',
        @segundoApellido = N'Tres', @correo = @correoDecanoExistente, @password = @pwd, @nombreFacultad = N'Facultad Decano Repetido', @idInstitucion = @ins, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #reg_d WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=DEC[_]020|%')
       OR EXISTS (SELECT 1 FROM dbo.Facultad WHERE nombre = N'Facultad Decano Repetido') OR (SELECT COUNT(*) FROM dbo.Decano) <> @decanosAntes
        THROW 59130, 'TEST FAILED CULM001_MRM_REG_03: un decano activo repetido debe responder DEC_020 sin crear la facultad.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_REG_03_DEC_020';

    -- REG_04: RBAC (solo el administrador)
    DECLARE @quien TABLE (k INT, u UNIQUEIDENTIFIER);
    INSERT @quien VALUES (1, @uDoc), (2, @uCoo), (3, @uDec);
    DECLARE @k INT = 1, @uEj UNIQUEIDENTIFIER;
    WHILE @k <= 3
    BEGIN
        SELECT @uEj = u FROM @quien WHERE k = @k;
        TRUNCATE TABLE #reg_d;
        INSERT #reg_d EXEC dbo.usp_crear_decano_con_facultad @numeroIdentificacion = 990100004, @primerNombre = N'Ana', @segundoNombre = N'Maria', @primerApellido = N'Registro',
            @segundoApellido = N'Cuatro', @correo = N'reg.decano4@test.local', @password = @pwd, @nombreFacultad = N'Facultad Sin Permiso', @idInstitucion = @ins, @idCorrelacion = @c, @idUsuarioEjecutor = @uEj;
        IF NOT EXISTS (SELECT 1 FROM #reg_d WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%')
            THROW 59140, 'TEST FAILED CULM001_MRM_REG_04: el docente, el coordinador y el decano no pueden crear decano + facultad (SEC_001).', 1;
        SET @k += 1;
    END
    TRUNCATE TABLE #reg_d;
    INSERT #reg_d EXEC dbo.usp_crear_decano_con_facultad @numeroIdentificacion = 990100004, @primerNombre = N'Ana', @segundoNombre = N'Maria', @primerApellido = N'Registro',
        @segundoApellido = N'Cuatro', @correo = N'reg.decano4@test.local', @password = @pwd, @nombreFacultad = N'Facultad Sin Permiso', @idInstitucion = @ins, @idCorrelacion = @c, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #reg_d WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]002|%')
       OR EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE correo = N'reg.decano4@test.local') OR EXISTS (SELECT 1 FROM dbo.Facultad WHERE nombre = N'Facultad Sin Permiso')
        THROW 59141, 'TEST FAILED CULM001_MRM_REG_04: sin ejecutor debe responder GEN_002 sin crear nada.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_REG_04_RBAC_DECANO_CON_FACULTAD';

    -- REG_05: coordinador + programa en la facultad del decano recien creado (el nuevo decano ya es titular)
    DECLARE @uDec1 UNIQUEIDENTIFIER = (SELECT usuario FROM dbo.Decano WHERE id = @idDec1);
    DECLARE @coordAntes INT = (SELECT COUNT(*) FROM dbo.Coordinador), @programasAntes INT = (SELECT COUNT(*) FROM dbo.Programa);
    SET @usuariosAntes = (SELECT COUNT(*) FROM dbo.Usuario);
    INSERT #reg_c EXEC dbo.usp_crear_coordinador_con_programa @numeroIdentificacion = 990200001, @primerNombre = N'Luis', @segundoNombre = N'Fernando', @primerApellido = N'Registro',
        @segundoApellido = N'Compuesto', @correo = N'reg.coord1@test.local', @password = @pwd, @nombrePrograma = N'  Programa Registro Compuesto  ', @idTipoPrograma = @tipo,
        @idModalidad = @modalidad, @idJornada = @jornada, @idFacultad = @idFac1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    DECLARE @idCoo1 UNIQUEIDENTIFIER = (SELECT idCoordinador FROM #reg_c), @idPro1 UNIQUEIDENTIFIER = (SELECT idPrograma FROM #reg_c);
    IF NOT EXISTS (SELECT 1 FROM #reg_c WHERE estadoResultado = 1 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]004|%'
                     AND idCoordinador IS NOT NULL AND idPrograma IS NOT NULL AND nombrePrograma = N'Programa Registro Compuesto')
        THROW 59150, 'TEST FAILED CULM001_MRM_REG_05: el compuesto debe responder GEN_004 con idCoordinador, idPrograma y el nombre recortado.', 1;
    IF (SELECT COUNT(*) FROM dbo.Coordinador) <> @coordAntes + 1 OR (SELECT COUNT(*) FROM dbo.Programa) <> @programasAntes + 1 OR (SELECT COUNT(*) FROM dbo.Usuario) <> @usuariosAntes + 1
        THROW 59151, 'TEST FAILED CULM001_MRM_REG_05: debe crear exactamente una persona, un coordinador y un programa.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Coordinador co INNER JOIN dbo.uv_usuario u ON u.id = co.usuario WHERE co.id = @idCoo1 AND co.facultad = @idFac1
                     AND u.correo = N'reg.coord1@test.local' AND u.numeroIdentificacion = N'990200001' AND u.estaActivoUsuario = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.Programa p WHERE p.id = @idPro1 AND p.nombre = N'Programa Registro Compuesto' AND p.facultad = @idFac1 AND p.coordinador = @idCoo1
                        AND p.tipoDePrograma = @tipo AND p.estado = 1 AND (p.modalidad = @modalidad OR @modalidad IS NULL) AND (p.jornada = @jornada OR @jornada IS NULL))
        THROW 59152, 'TEST FAILED CULM001_MRM_REG_05: la persona, el coordinador (con su facultad) y el programa deben quedar vinculados y activos.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @idPro1 AND idFacultad = @idFac1 AND estaActivoPrograma = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador_identidad WHERE id = @idCoo1 AND estaActivoRolCoordinador = 1 AND idFacultadCoordinador = @idFac1)
        THROW 59153, 'TEST FAILED CULM001_MRM_REG_05: las vistas deben exponer el programa y el coordinador nuevos.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_REG_05_COORDINADOR_CON_PROGRAMA';

    -- REG_06: programa invalido => nada creado
    SET @coordAntes = (SELECT COUNT(*) FROM dbo.Coordinador); SET @programasAntes = (SELECT COUNT(*) FROM dbo.Programa); SET @usuariosAntes = (SELECT COUNT(*) FROM dbo.Usuario);
    DECLARE @tipoFalso UNIQUEIDENTIFIER = NEWID(), @modFalsa UNIQUEIDENTIFIER = NEWID();
    TRUNCATE TABLE #reg_c;
    INSERT #reg_c EXEC dbo.usp_crear_coordinador_con_programa @numeroIdentificacion = 990200002, @primerNombre = N'Luis', @segundoNombre = N'Fernando', @primerApellido = N'Registro',
        @segundoApellido = N'Dos', @correo = N'reg.coord2@test.local', @password = @pwd, @nombrePrograma = N'Programa Tipo Falso', @idTipoPrograma = @tipoFalso, @idFacultad = @idFac1,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #reg_c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PROG[_]004|%' AND idCoordinador IS NULL AND idPrograma IS NULL AND nombrePrograma IS NULL)
        THROW 59160, 'TEST FAILED CULM001_MRM_REG_06: el tipo de programa invalido debe responder PROG_004 con salidas NULL.', 1;
    TRUNCATE TABLE #reg_c;
    INSERT #reg_c EXEC dbo.usp_crear_coordinador_con_programa @numeroIdentificacion = 990200002, @primerNombre = N'Luis', @segundoNombre = N'Fernando', @primerApellido = N'Registro',
        @segundoApellido = N'Dos', @correo = N'reg.coord2@test.local', @password = @pwd, @nombrePrograma = N'PROGRAMA registro COMPUESTO', @idTipoPrograma = @tipo, @idFacultad = @idFac1,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #reg_c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PROG[_]003|%')
        THROW 59161, 'TEST FAILED CULM001_MRM_REG_06: el nombre repetido en la facultad debe responder PROG_003.', 1;
    TRUNCATE TABLE #reg_c;
    INSERT #reg_c EXEC dbo.usp_crear_coordinador_con_programa @numeroIdentificacion = 990200002, @primerNombre = N'Luis', @segundoNombre = N'Fernando', @primerApellido = N'Registro',
        @segundoApellido = N'Dos', @correo = N'reg.coord2@test.local', @password = @pwd, @nombrePrograma = N'Programa Modalidad Falsa', @idTipoPrograma = @tipo, @idModalidad = @modFalsa,
        @idFacultad = @idFac1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #reg_c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PROG[_]006|%')
        THROW 59162, 'TEST FAILED CULM001_MRM_REG_06: la modalidad inexistente debe responder PROG_006.', 1;
    TRUNCATE TABLE #reg_c;
    INSERT #reg_c EXEC dbo.usp_crear_coordinador_con_programa @numeroIdentificacion = 990200002, @primerNombre = N'Luis', @segundoNombre = N'Fernando', @primerApellido = N'Registro',
        @segundoApellido = N'Dos', @correo = N'reg.coord2@test.local', @password = @pwd, @nombrePrograma = N'   ', @idTipoPrograma = @tipo, @idFacultad = @idFac1,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #reg_c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]002|%')
        THROW 59163, 'TEST FAILED CULM001_MRM_REG_06: el nombre vacio debe responder GEN_002.', 1;
    IF (SELECT COUNT(*) FROM dbo.Coordinador) <> @coordAntes OR (SELECT COUNT(*) FROM dbo.Programa) <> @programasAntes OR (SELECT COUNT(*) FROM dbo.Usuario) <> @usuariosAntes
       OR EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE correo = N'reg.coord2@test.local')
        THROW 59164, 'TEST FAILED CULM001_MRM_REG_06: un fallo del programa no debe dejar persona, coordinador ni programa.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_REG_06_FALLO_PROGRAMA_NO_DEJA_PERSONA';

    -- REG_07: RBAC y titularidad de coordinador + programa
    DELETE @quien;
    INSERT @quien VALUES (1, @uDoc), (2, @uCoo), (3, @uAdm);
    SET @k = 1;
    WHILE @k <= 3
    BEGIN
        SELECT @uEj = u FROM @quien WHERE k = @k;
        TRUNCATE TABLE #reg_c;
        INSERT #reg_c EXEC dbo.usp_crear_coordinador_con_programa @numeroIdentificacion = 990200003, @primerNombre = N'Luis', @segundoNombre = N'Fernando', @primerApellido = N'Registro',
            @segundoApellido = N'Tres', @correo = N'reg.coord3@test.local', @password = @pwd, @nombrePrograma = N'Programa Sin Permiso', @idTipoPrograma = @tipo, @idFacultad = @facDec,
            @idCorrelacion = @c, @idUsuarioEjecutor = @uEj;
        IF NOT EXISTS (SELECT 1 FROM #reg_c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%')
            THROW 59170, 'TEST FAILED CULM001_MRM_REG_07: el docente, el coordinador y el administrador no pueden crear coordinador + programa (SEC_001).', 1;
        SET @k += 1;
    END
    -- el decano de otra facultad (el original) sobre la facultad nueva => titularidad
    TRUNCATE TABLE #reg_c;
    INSERT #reg_c EXEC dbo.usp_crear_coordinador_con_programa @numeroIdentificacion = 990200003, @primerNombre = N'Luis', @segundoNombre = N'Fernando', @primerApellido = N'Registro',
        @segundoApellido = N'Tres', @correo = N'reg.coord3@test.local', @password = @pwd, @nombrePrograma = N'Programa Ajeno', @idTipoPrograma = @tipo, @idFacultad = @idFac1,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDec;
    IF NOT EXISTS (SELECT 1 FROM #reg_c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]002|%')
        THROW 59171, 'TEST FAILED CULM001_MRM_REG_07: el decano de otra facultad debe responder SEC_002 (titularidad).', 1;
    -- y el decano nuevo sobre la facultad original
    TRUNCATE TABLE #reg_c;
    INSERT #reg_c EXEC dbo.usp_crear_coordinador_con_programa @numeroIdentificacion = 990200003, @primerNombre = N'Luis', @segundoNombre = N'Fernando', @primerApellido = N'Registro',
        @segundoApellido = N'Tres', @correo = N'reg.coord3@test.local', @password = @pwd, @nombrePrograma = N'Programa Ajeno', @idTipoPrograma = @tipo, @idFacultad = @facDec,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #reg_c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]002|%')
        THROW 59172, 'TEST FAILED CULM001_MRM_REG_07: el decano nuevo sobre la facultad original debe responder SEC_002.', 1;
    TRUNCATE TABLE #reg_c;
    INSERT #reg_c EXEC dbo.usp_crear_coordinador_con_programa @numeroIdentificacion = 990200003, @primerNombre = N'Luis', @segundoNombre = N'Fernando', @primerApellido = N'Registro',
        @segundoApellido = N'Tres', @correo = N'reg.coord3@test.local', @password = @pwd, @nombrePrograma = N'Programa Sin Facultad', @idTipoPrograma = @tipo, @idFacultad = NULL,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #reg_c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]002|%')
        THROW 59173, 'TEST FAILED CULM001_MRM_REG_07: sin facultad debe responder GEN_002.', 1;
    IF (SELECT COUNT(*) FROM dbo.Coordinador) <> @coordAntes OR (SELECT COUNT(*) FROM dbo.Programa) <> @programasAntes OR EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE correo = N'reg.coord3@test.local')
        THROW 59174, 'TEST FAILED CULM001_MRM_REG_07: los rechazos de RBAC y titularidad no deben crear nada.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_REG_07_RBAC_Y_TITULARIDAD_COORDINADOR_CON_PROGRAMA';

    -- REG_08: fallo posterior a la escritura. Un usuario inactivo existente (creado en la prueba) pasa la validacion previa del programa (no depende del coordinador), el nucleo le crea la
    -- fila Coordinador y la revalidacion con el coordinador ya creado responde PROG_005 (coordinador inactivo): se revierte la fila Coordinador. Se invoca con EXEC
    -- directo porque el ROLLBACK a savepoint no esta permitido dentro de INSERT ... EXEC.
    DECLARE @uInactivo UNIQUEIDENTIFIER = NEWID();
    DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion ORDER BY id);
    INSERT dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uInactivo, @tipoId, 990200009, N'Inactivo', N'Registro', N'Persona', N'Sin rol', N'reg.inactivo@test.local', 1, 0, @pwd);
    DECLARE @correoInactivo NVARCHAR(100) = (SELECT correo FROM dbo.uv_usuario WHERE id = @uInactivo);
    DECLARE @numInactivo INT = 990200009;
    SET @coordAntes = (SELECT COUNT(*) FROM dbo.Coordinador); SET @programasAntes = (SELECT COUNT(*) FROM dbo.Programa);
    EXEC dbo.usp_crear_coordinador_con_programa @numeroIdentificacion = @numInactivo, @primerNombre = N'Persona', @segundoNombre = N'Inactiva', @primerApellido = N'Registro',
        @segundoApellido = N'Ocho', @correo = @correoInactivo, @password = @pwd, @nombrePrograma = N'Programa Coordinador Inactivo', @idTipoPrograma = @tipo, @idFacultad = @idFac1,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF (SELECT COUNT(*) FROM dbo.Coordinador) <> @coordAntes OR (SELECT COUNT(*) FROM dbo.Programa) <> @programasAntes
       OR EXISTS (SELECT 1 FROM dbo.Coordinador WHERE usuario = @uInactivo) OR EXISTS (SELECT 1 FROM dbo.Programa WHERE nombre = N'Programa Coordinador Inactivo')
        THROW 59180, 'TEST FAILED CULM001_MRM_REG_08: un fallo posterior a la escritura debe revertir el coordinador y el programa.', 1;
    IF @@TRANCOUNT <> @tran
        THROW 59181, 'TEST FAILED CULM001_MRM_REG_08: el compuesto debe dejar la transaccion del llamador intacta.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_REG_08_FALLO_POSTERIOR_REVIERTE_TODO';

    -- REG_09: los publicos anteriores siguen funcionando
    CREATE TABLE #reg_o (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL);
    INSERT #reg_o EXEC dbo.usp_crear_decano @numeroIdentificacion = 990300001, @primerNombre = N'Pablo', @segundoNombre = N'Andres', @primerApellido = N'Anterior', @segundoApellido = N'Decano',
        @correo = N'reg.anterior.decano@test.local', @password = @pwd, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #reg_o WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]004|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Decano d INNER JOIN dbo.uv_usuario u ON u.id = d.usuario WHERE u.correo = N'reg.anterior.decano@test.local')
        THROW 59190, 'TEST FAILED CULM001_MRM_REG_09: usp_crear_decano debe seguir creando persona + decano.', 1;
    TRUNCATE TABLE #reg_o;
    INSERT #reg_o EXEC dbo.usp_crear_decano @numeroIdentificacion = 990300001, @primerNombre = N'Pablo', @segundoNombre = N'Andres', @primerApellido = N'Anterior', @segundoApellido = N'Decano',
        @correo = N'reg.anterior.decano@test.local', @password = @pwd, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdm;
    IF NOT EXISTS (SELECT 1 FROM #reg_o WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=DEC[_]020|%')
        THROW 59191, 'TEST FAILED CULM001_MRM_REG_09: usp_crear_decano debe seguir respondiendo DEC_020 al repetir el decano.', 1;
    TRUNCATE TABLE #reg_o;
    INSERT #reg_o EXEC dbo.usp_crear_coordinador @numeroIdentificacion = 990300002, @primerNombre = N'Marta', @segundoNombre = N'Elena', @primerApellido = N'Anterior', @segundoApellido = N'Coordinador',
        @correo = N'reg.anterior.coord@test.local', @idFacultad = @idFac1, @password = @pwd, @idCorrelacion = @c, @idUsuarioEjecutor = @uDec1;
    IF NOT EXISTS (SELECT 1 FROM #reg_o WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]004|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Coordinador co INNER JOIN dbo.uv_usuario u ON u.id = co.usuario WHERE u.correo = N'reg.anterior.coord@test.local' AND co.facultad = @idFac1)
        THROW 59192, 'TEST FAILED CULM001_MRM_REG_09: usp_crear_coordinador debe seguir creando persona + coordinador con su facultad.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_REG_09_PUBLICOS_ANTERIORES';

    -- REG_10: transaccionalidad
    IF @@TRANCOUNT <> @tran
        THROW 59199, 'TEST FAILED CULM001_MRM_REG_10: el compuesto no debe cambiar @@TRANCOUNT del llamador.', 1;
    ROLLBACK TRANSACTION;
    IF @@TRANCOUNT <> 0
        THROW 59200, 'TEST FAILED CULM001_MRM_REG_10: la prueba debe terminar con @@TRANCOUNT = 0.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE correo LIKE N'reg.%@test.local') OR EXISTS (SELECT 1 FROM dbo.Facultad WHERE nombre = N'Facultad Registro Compuesto')
        THROW 59201, 'TEST FAILED CULM001_MRM_REG_10: la prueba no debe dejar datos tras revertir.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_REG_10_TRANCOUNT_ZERO';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('TEST FAILED: ', ERROR_MESSAGE());
    THROW;
END CATCH
GO
