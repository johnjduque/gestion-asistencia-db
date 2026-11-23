USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- CIERRE-W1B (decision de producto 2026-11-16): directorios de personas con ambito y paginacion.
--   W1B_RBAC_01..06  usp_validar_permiso_rbac_usuario_interno: perfil por codigo o nombre exacto, sin LIKE ni elementos vacios
--   W1B_COO_01..08   usp_consultar_coordinadores_facultad_paginado: ambito del decano, filtros, paginacion y totales
--   W1B_NOM_01..03   nombres y apellidos separados en docentes, estudiantes y decanos
-- Todo corre en UNA transaccion con ROLLBACK final.
-- ============================================================================
PRINT 'TEST START: test_w1b_directorios';
GO

DECLARE @uAdmin UNIQUEIDENTIFIER, @inst UNIQUEIDENTIFIER;
SELECT TOP 1 @uAdmin = a.usuario, @inst = a.institucion FROM dbo.Administrador a ORDER BY a.id;
IF @uAdmin IS NULL OR @inst IS NULL
    THROW 55001, 'TEST FAILED W1B: falta un administrador en el seed.', 1;

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @tipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 tipoDePrograma FROM dbo.Programa ORDER BY id);
DECLARE @hash NVARCHAR(500) = N'HashBackend_QaW1b_1234567890';
DECLARE @c UNIQUEIDENTIFIER, @ok BIT, @mu NVARCHAR(4000), @mt NVARCHAR(4000), @estado BIT, @rechazos INT;
IF @tipoCC IS NULL OR @tipoProg IS NULL
    THROW 55002, 'TEST FAILED W1B: faltan catalogos del seed (tipo de identificacion o tipo de programa).', 1;

IF OBJECT_ID(N'tempdb..#coo') IS NOT NULL DROP TABLE #coo;
CREATE TABLE #coo (
    id UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, numeroIdentificacion BIGINT, nombreCompleto NVARCHAR(250),
    idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100), estaActivoCoordinador BIT,
    primerNombre NVARCHAR(100), segundoNombre NVARCHAR(100), primerApellido NVARCHAR(100), segundoApellido NVARCHAR(100),
    correo NVARCHAR(255), estaActivoRolCoordinador BIT, nombreFacultad NVARCHAR(100), totalDocentes INT, totalGrupos INT,
    totalRegistros INT);

BEGIN TRANSACTION;
BEGIN TRY
    -- ======================================================= Fixtures: dos facultades de la misma institucion
    DECLARE @uDecA UNIQUEIDENTIFIER = NEWID(), @decA UNIQUEIDENTIFIER = NEWID(), @facA UNIQUEIDENTIFIER = NEWID();
    DECLARE @uDecB UNIQUEIDENTIFIER = NEWID(), @decB UNIQUEIDENTIFIER = NEWID(), @facB UNIQUEIDENTIFIER = NEWID();
    DECLARE @uDecSin UNIQUEIDENTIFIER = NEWID(), @decSin UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES (@uDecA, @tipoCC, 915000001, N'DecanoA', N'Qa', N'Decano', N'W1b', N'decano.a.qa.w1b@uco.edu.co', 1, 1),
           (@uDecB, @tipoCC, 915000002, N'DecanoB', N'Qa', N'Decano', N'W1b', N'decano.b.qa.w1b@uco.edu.co', 1, 1),
           (@uDecSin, @tipoCC, 915000003, N'DecanoSin', N'Qa', N'Decano', N'W1b', N'decano.sin.qa.w1b@uco.edu.co', 1, 1);
    INSERT dbo.Decano (id, usuario) VALUES (@decA, @uDecA), (@decB, @uDecB), (@decSin, @uDecSin);
    INSERT dbo.Facultad (id, nombre, institucion, decano, estado)
    VALUES (@facA, N'QA W1B Facultad A', @inst, @decA, 1), (@facB, N'QA W1B Facultad B', @inst, @decB, 1);

    -- Coordinadores de A: uno con programa activo, uno sin programa y uno con programa y rol inactivo. Uno de B con programa.
    DECLARE @uCa1 UNIQUEIDENTIFIER = NEWID(), @ca1 UNIQUEIDENTIFIER = NEWID(), @pa1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @uCa2 UNIQUEIDENTIFIER = NEWID(), @ca2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @uCa3 UNIQUEIDENTIFIER = NEWID(), @ca3 UNIQUEIDENTIFIER = NEWID(), @pa3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @uCb1 UNIQUEIDENTIFIER = NEWID(), @cb1 UNIQUEIDENTIFIER = NEWID(), @pb1 UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES (@uCa1, @tipoCC, 915000011, N'Alfa', N'Uno', N'Carla', N'Maria', N'coord.a1.qa.w1b@uco.edu.co', 1, 1),
           (@uCa2, @tipoCC, 915000012, N'Beta', N'Dos', N'Pedro', N'', N'coord.a2.qa.w1b@uco.edu.co', 1, 1),
           (@uCa3, @tipoCC, 915000013, N'Gamma', N'Tres', N'Luis', N'Eduardo', N'coord.a3.qa.w1b@uco.edu.co', 1, 1),
           (@uCb1, @tipoCC, 915000014, N'Delta', N'Cuatro', N'Sofia', N'', N'coord.b1.qa.w1b@uco.edu.co', 1, 1);
    INSERT dbo.Coordinador (id, usuario, estado, facultad)
    VALUES (@ca1, @uCa1, 1, @facA), (@ca2, @uCa2, 1, @facA), (@ca3, @uCa3, 0, @facA), (@cb1, @uCb1, 1, @facB);
    INSERT dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (@pa1, @facA, @tipoProg, N'QA W1B Programa A1', @ca1, 1),
           (@pa3, @facA, @tipoProg, N'QA W1B Programa A3', @ca3, 1),
           (@pb1, @facB, @tipoProg, N'QA W1B Programa B1', @cb1, 1);

    -- ======================================================= RBAC por perfil exacto
    SET @c = NEWID();
    EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDecA, @codigoPerfilRequerido = 'DECANO', @idCorrelacion = @c,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado <> 1 THROW 55011, 'TEST FAILED W1B_RBAC_01: el nombre completo del perfil debe seguir siendo valido.', 1;
    PRINT 'TEST_PASS:W1B_RBAC_01_NOMBRE_COMPLETO';

    EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDecA, @codigoPerfilRequerido = 'de', @idCorrelacion = @c,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado <> 1 THROW 55012, 'TEST FAILED W1B_RBAC_02: el codigo del perfil debe ser valido.', 1;
    PRINT 'TEST_PASS:W1B_RBAC_02_CODIGO';

    SET @rechazos = 0;
    EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDecA, @codigoPerfilRequerido = 'DECAN', @idCorrelacion = @c,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado = 0 SET @rechazos += 1;
    EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDecA, @codigoPerfilRequerido = 'ECANO', @idCorrelacion = @c,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado = 0 SET @rechazos += 1;
    IF @rechazos <> 2 THROW 55013, 'TEST FAILED W1B_RBAC_03: una subcadena del nombre del perfil no debe validar el perfil.', 1;
    PRINT 'TEST_PASS:W1B_RBAC_03_SUBCADENA_RECHAZADA';

    EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDecA, @codigoPerfilRequerido = '%', @idCorrelacion = @c,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado <> 0
        THROW 55014, 'TEST FAILED W1B_RBAC_04: el comodin % no debe coincidir con ningun perfil.', 1;
    PRINT 'TEST_PASS:W1B_RBAC_04_COMODIN';

    EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDecA, @codigoPerfilRequerido = 'DOCENTE,', @idCorrelacion = @c,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado <> 0 THROW 55015, 'TEST FAILED W1B_RBAC_05: un elemento vacio en la lista no debe coincidir con cualquier perfil.', 1;
    PRINT 'TEST_PASS:W1B_RBAC_05_ELEMENTO_VACIO';

    EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDecA, @codigoPerfilRequerido = 'COORDINADOR, decano ,ADMINISTRADOR', @idCorrelacion = @c,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado <> 1 THROW 55016, 'TEST FAILED W1B_RBAC_06: una lista de perfiles con espacios y otra capitalizacion debe seguir validando.', 1;
    PRINT 'TEST_PASS:W1B_RBAC_06_LISTA';

    -- ======================================================= Coordinadores de la facultad del decano
    -- W1B_COO_01: el decano A ve a sus tres coordinadores, uno por fila, con los nombres separados.
    SET @c = NEWID();
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado
        @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50;
    SET @ok = IIF((SELECT COUNT(*) FROM #coo) = 3
                  AND NOT EXISTS (SELECT 1 FROM #coo WHERE totalRegistros <> 3)
                  AND EXISTS (SELECT 1 FROM #coo WHERE id = @ca1 AND idPrograma = @pa1 AND primerNombre = N'Carla' AND segundoNombre = N'Maria'
                              AND primerApellido = N'Alfa' AND segundoApellido = N'Uno' AND correo = N'coord.a1.qa.w1b@uco.edu.co'
                              AND nombreFacultad = N'QA W1B Facultad A' AND estaActivoCoordinador = 1)
                  AND EXISTS (SELECT 1 FROM #coo WHERE id = @ca2 AND idPrograma IS NULL AND nombrePrograma IS NULL AND totalDocentes = 0 AND totalGrupos = 0)
                  AND EXISTS (SELECT 1 FROM #coo WHERE id = @ca3 AND estaActivoCoordinador = 0 AND estaActivoRolCoordinador = 0), 1, 0);
    IF @ok <> 1 THROW 55021, 'TEST FAILED W1B_COO_01: el decano A debe ver sus tres coordinadores con nombres, programa, estado y total.', 1;
    PRINT 'TEST_PASS:W1B_COO_01_LISTADO';

    -- W1B_COO_02: aislamiento: el decano B solo ve el suyo y el decano A nunca ve el de B.
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado
        @idUsuarioEjecutor = @uDecB, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50;
    SET @ok = IIF((SELECT COUNT(*) FROM #coo) = 1 AND EXISTS (SELECT 1 FROM #coo WHERE id = @cb1 AND totalRegistros = 1)
                  AND NOT EXISTS (SELECT 1 FROM #coo WHERE id IN (@ca1, @ca2, @ca3)), 1, 0);
    IF @ok <> 1 THROW 55022, 'TEST FAILED W1B_COO_02: el decano B solo debe ver a su coordinador.', 1;
    PRINT 'TEST_PASS:W1B_COO_02_AISLAMIENTO';

    -- W1B_COO_03: decano sin facultad a cargo: sin filas.
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado
        @idUsuarioEjecutor = @uDecSin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50;
    IF EXISTS (SELECT 1 FROM #coo) THROW 55023, 'TEST FAILED W1B_COO_03: un decano sin facultad no debe ver coordinadores.', 1;
    PRINT 'TEST_PASS:W1B_COO_03_DECANO_SIN_FACULTAD';

    -- W1B_COO_04: busqueda por nombre, documento, correo y programa.
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = N'carla';
    SET @ok = IIF((SELECT COUNT(*) FROM #coo) = 1 AND EXISTS (SELECT 1 FROM #coo WHERE id = @ca1 AND totalRegistros = 1), 1, 0);
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = N'915000012';
    SET @ok = IIF(@ok = 1 AND (SELECT COUNT(*) FROM #coo) = 1 AND EXISTS (SELECT 1 FROM #coo WHERE id = @ca2), 1, 0);
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = N'coord.a3.qa';
    SET @ok = IIF(@ok = 1 AND (SELECT COUNT(*) FROM #coo) = 1 AND EXISTS (SELECT 1 FROM #coo WHERE id = @ca3), 1, 0);
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = N'Programa A3';
    SET @ok = IIF(@ok = 1 AND (SELECT COUNT(*) FROM #coo) = 1 AND EXISTS (SELECT 1 FROM #coo WHERE id = @ca3), 1, 0);
    -- Un texto de otra facultad no aparece y un comodin no se interpreta.
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = N'Sofia';
    SET @ok = IIF(@ok = 1 AND NOT EXISTS (SELECT 1 FROM #coo), 1, 0);
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @busqueda = N'%';
    SET @ok = IIF(@ok = 1 AND NOT EXISTS (SELECT 1 FROM #coo), 1, 0);
    IF @ok <> 1 THROW 55024, 'TEST FAILED W1B_COO_04: la busqueda por nombre, documento, correo o programa fallo o interpreto un comodin.', 1;
    PRINT 'TEST_PASS:W1B_COO_04_BUSQUEDA';

    -- W1B_COO_05: filtro por estado.
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @estaActivo = 0;
    SET @ok = IIF((SELECT COUNT(*) FROM #coo) = 1 AND EXISTS (SELECT 1 FROM #coo WHERE id = @ca3 AND totalRegistros = 1), 1, 0);
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @estaActivo = 1;
    SET @ok = IIF(@ok = 1 AND (SELECT COUNT(*) FROM #coo) = 2 AND NOT EXISTS (SELECT 1 FROM #coo WHERE id = @ca3 OR totalRegistros <> 2), 1, 0);
    IF @ok <> 1 THROW 55025, 'TEST FAILED W1B_COO_05: el filtro por estado debe separar activos de inactivos con su total.', 1;
    PRINT 'TEST_PASS:W1B_COO_05_ESTADO';

    -- W1B_COO_06: filtro sin programa.
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @sinPrograma = 1;
    SET @ok = IIF((SELECT COUNT(*) FROM #coo) = 1 AND EXISTS (SELECT 1 FROM #coo WHERE id = @ca2 AND idPrograma IS NULL AND totalRegistros = 1), 1, 0);
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @sinPrograma = 0;
    SET @ok = IIF(@ok = 1 AND (SELECT COUNT(*) FROM #coo) = 2 AND NOT EXISTS (SELECT 1 FROM #coo WHERE idPrograma IS NULL), 1, 0);
    DELETE FROM #coo;
    INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50, @sinPrograma = 1, @estaActivo = 1;
    SET @ok = IIF(@ok = 1 AND (SELECT COUNT(*) FROM #coo) = 1 AND EXISTS (SELECT 1 FROM #coo WHERE id = @ca2), 1, 0);
    IF @ok <> 1 THROW 55026, 'TEST FAILED W1B_COO_06: el filtro sin programa (y combinado con estado) devolvio filas incorrectas.', 1;
    PRINT 'TEST_PASS:W1B_COO_06_SIN_PROGRAMA';

    -- W1B_COO_07: paginacion de a una fila: el total no cambia, las paginas no se repiten y mas alla del final no hay filas.
    CREATE TABLE #pag (idPagina INT, id UNIQUEIDENTIFIER, totalRegistros INT);
    DECLARE @p INT = 1;
    WHILE @p <= 4
    BEGIN
        DELETE FROM #coo;
        INSERT #coo EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = @p, @tamanoPagina = 1;
        INSERT #pag SELECT @p, id, totalRegistros FROM #coo;
        SET @p += 1;
    END;
    SET @ok = IIF((SELECT COUNT(*) FROM #pag) = 3 AND (SELECT COUNT(DISTINCT id) FROM #pag) = 3
                  AND NOT EXISTS (SELECT 1 FROM #pag WHERE totalRegistros <> 3) AND NOT EXISTS (SELECT 1 FROM #pag WHERE idPagina = 4), 1, 0);
    DROP TABLE #pag;
    IF @ok <> 1 THROW 55027, 'TEST FAILED W1B_COO_07: la paginacion de a una fila debe repartir los 3 coordinadores sin repetir y con total 3.', 1;
    PRINT 'TEST_PASS:W1B_COO_07_PAGINACION';

    -- W1B_COO_08: perfil incorrecto, paginacion invalida y ejecutor ausente.
    SET @rechazos = 0;
    BEGIN TRY
        EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=SEC_001|%' SET @rechazos += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uCa1, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=SEC_001|%' SET @rechazos += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = @uDecA, @idCorrelacion = @c, @numeroPagina = 0, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=PAG_001|%' SET @rechazos += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_consultar_coordinadores_facultad_paginado @idUsuarioEjecutor = NULL, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=VAL_001|%' SET @rechazos += 1;
    END CATCH;
    IF @rechazos <> 4 THROW 55028, 'TEST FAILED W1B_COO_08: administrador y coordinador deben recibir SEC_001, y la paginacion invalida o el ejecutor ausente sus codigos.', 1;
    PRINT 'TEST_PASS:W1B_COO_08_RECHAZOS';

    -- ======================================================= Nombres separados
    -- W1B_NOM_01: directorio de docentes del decano (y del administrador) con los cuatro nombres y el tipo de documento.
    DECLARE @uDocente UNIQUEIDENTIFIER, @facDoc UNIQUEIDENTIFIER, @uDecDoc UNIQUEIDENTIFIER, @uAdminDoc UNIQUEIDENTIFIER;
    SELECT TOP 1 @uDocente = dp.idUsuario, @facDoc = dp.idFacultad
    FROM dbo.uv_docente_programa dp WHERE dp.estaActivoVinculacion = 1 ORDER BY dp.nombreCompleto, dp.idDocente;
    SELECT @uDecDoc = d.usuario FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano WHERE f.id = @facDoc;
    SELECT @uAdminDoc = a.usuario FROM dbo.Administrador a INNER JOIN dbo.Facultad f ON f.institucion = a.institucion WHERE f.id = @facDoc;
    IF @uDocente IS NULL OR @uAdminDoc IS NULL
        THROW 55031, 'TEST FAILED W1B_NOM_01: faltan docente vinculado o administrador en el seed.', 1;
    IF @uDecDoc IS NULL SET @uDecDoc = @uAdminDoc;
    CREATE TABLE #doc (
        idDocente UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, numeroIdentificacion BIGINT, nombreCompleto NVARCHAR(250),
        correo NVARCHAR(255), estaActivoUsuario BIT, programas NVARCHAR(MAX), totalProgramas INT, totalGrupos INT, totalRegistros INT,
        tieneVinculoActivo BIT, primerNombre NVARCHAR(100), segundoNombre NVARCHAR(100), primerApellido NVARCHAR(100),
        segundoApellido NVARCHAR(100), idTipoIdentificacion UNIQUEIDENTIFIER, codigoTipoIdentificacion NVARCHAR(50));
    INSERT #doc EXEC dbo.usp_consultar_docentes_facultad_paginado @idUsuarioEjecutor = @uAdminDoc, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #doc)
                  AND NOT EXISTS (SELECT 1 FROM #doc d INNER JOIN dbo.Usuario u ON u.id = d.idUsuario
                                  WHERE ISNULL(d.primerNombre, N'') <> ISNULL(u.primerNombre, N'') OR ISNULL(d.segundoNombre, N'') <> ISNULL(u.segundoNombre, N'')
                                     OR ISNULL(d.primerApellido, N'') <> ISNULL(u.primerApellido, N'') OR ISNULL(d.segundoApellido, N'') <> ISNULL(u.segundoApellido, N'')
                                     OR d.idTipoIdentificacion <> u.tipoIdIdentificacion OR d.codigoTipoIdentificacion IS NULL)
                  AND EXISTS (SELECT 1 FROM #doc WHERE idUsuario = @uDocente), 1, 0);
    DROP TABLE #doc;
    IF @ok <> 1 THROW 55032, 'TEST FAILED W1B_NOM_01: el directorio de docentes debe traer los nombres separados y el tipo de documento reales.', 1;
    PRINT 'TEST_PASS:W1B_NOM_01_DOCENTES';

    -- W1B_NOM_02: buscador de estudiantes del administrador con los cuatro nombres.
    CREATE TABLE #est (
        idEstudiante UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, numeroIdentificacion BIGINT, nombreCompleto NVARCHAR(250),
        correo NVARCHAR(255), estaActivoUsuario BIT, facultades NVARCHAR(MAX), programas NVARCHAR(MAX), totalGrupos INT, totalRegistros INT,
        primerNombre NVARCHAR(100), segundoNombre NVARCHAR(100), primerApellido NVARCHAR(100), segundoApellido NVARCHAR(100), tipoIdentificacion NVARCHAR(20));
    INSERT #est EXEC dbo.usp_buscar_estudiantes_institucion_paginado @idUsuarioEjecutor = @uAdminDoc, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #est)
                  AND NOT EXISTS (SELECT 1 FROM #est e INNER JOIN dbo.Usuario u ON u.id = e.idUsuario
                                  WHERE ISNULL(e.primerNombre, N'') <> ISNULL(u.primerNombre, N'') OR ISNULL(e.segundoNombre, N'') <> ISNULL(u.segundoNombre, N'')
                                     OR ISNULL(e.primerApellido, N'') <> ISNULL(u.primerApellido, N'') OR ISNULL(e.segundoApellido, N'') <> ISNULL(u.segundoApellido, N'')
                                     OR e.tipoIdentificacion IS NULL OR e.tipoIdentificacion <> (SELECT t.tipoIdentificacion FROM dbo.TipoIdentificacion t WHERE t.id = u.tipoIdIdentificacion)), 1, 0);
    DROP TABLE #est;
    IF @ok <> 1 THROW 55033, 'TEST FAILED W1B_NOM_02: el buscador de estudiantes debe traer los nombres separados reales.', 1;
    PRINT 'TEST_PASS:W1B_NOM_02_ESTUDIANTES';

    -- W1B_NOM_03: uv_decano expone los nombres separados.
    SET @ok = IIF(EXISTS (SELECT 1 FROM dbo.uv_decano WHERE idUsuario = @uDecA AND primerNombre = N'Decano' AND segundoNombre = N'W1b'
                          AND primerApellido = N'DecanoA' AND segundoApellido = N'Qa'), 1, 0);
    IF @ok <> 1 THROW 55034, 'TEST FAILED W1B_NOM_03: uv_decano debe exponer primerNombre, segundoNombre, primerApellido y segundoApellido.', 1;
    PRINT 'TEST_PASS:W1B_NOM_03_DECANOS';

    -- W1B_NOM_04: uv_decano expone el correo y el tipo de documento reales del usuario.
    SET @ok = IIF(EXISTS (SELECT 1 FROM dbo.uv_decano WHERE idUsuario = @uDecA AND correo = N'decano.a.qa.w1b@uco.edu.co'
                          AND TipoIdentificacion = (SELECT t.tipoIdentificacion FROM dbo.TipoIdentificacion t WHERE t.id = @tipoCC)), 1, 0);
    IF @ok <> 1 THROW 55035, 'TEST FAILED W1B_NOM_04: uv_decano debe exponer correo y TipoIdentificacion del usuario.', 1;
    PRINT 'TEST_PASS:W1B_NOM_04_DECANOS_CORREO_TIPO';

    IF @@TRANCOUNT <> 1 THROW 55090, 'TEST FAILED W1B: las pruebas dejaron una transaccion distinta de la propia.', 1;
    ROLLBACK TRANSACTION;
    IF @@TRANCOUNT <> 0 THROW 55091, 'TEST FAILED W1B: quedo una transaccion abierta.', 1;
    PRINT 'TEST_PASS:W1B_TRANCOUNT_ZERO';
END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msgFinal NVARCHAR(4000) = N'TEST FAILED test_w1b_directorios: ' + @msg;
    THROW 55099, @msgFinal, 1;
END CATCH;
GO
PRINT 'TEST END: test_w1b_directorios';
GO
