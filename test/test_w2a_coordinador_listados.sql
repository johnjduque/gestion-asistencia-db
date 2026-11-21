USE [gestionasistenciadb];
GO
-- ============================================================================
-- CIERRE-W2A (decision de producto 2026-11-16): listados del coordinador resueltos en la base.
--   W2A_ASI_01..05  usp_consultar_asignaturas_coordinador_paginado: @codigoCaracter (filtro por codigo, total y aislamiento)
--   W2A_OPC_01..05  usp_consultar_{asignaturas,docentes}_ambito_consolidado: opciones del filtro con ambito y periodo
--   W2A_PER_01..02  uv_periodo_academico.estado: PLANEACION / ACTIVO / CERRADO con la fecha local institucional
-- Corre en UNA transaccion con ROLLBACK final. Los THROW esperados se capturan; los de fallo van al final.
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_w2a_coordinador_listados';
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @otroPeriodo UNIQUEIDENTIFIER = NEWID();

    -- ======================================================= Asignaturas del coordinador por caracter
    DECLARE @a TABLE (idAsignatura UNIQUEIDENTIFIER, codigo NVARCHAR(50), nombre NVARCHAR(200), credito INT, idArea UNIQUEIDENTIFIER, nombreArea NVARCHAR(200),
        idComponente UNIQUEIDENTIFIER, nombreComponente NVARCHAR(200), idPlanEstudio UNIQUEIDENTIFIER, inpPlanEstudio INT, idPrograma UNIQUEIDENTIFIER,
        nombrePrograma NVARCHAR(200), idSemestrePlanEstudio UNIQUEIDENTIFIER, numeroSemestre INT, codigoSemestre NVARCHAR(10), codigoCaracter NVARCHAR(3),
        nombreCaracter NVARCHAR(100), estaActivoVinculo BIT, estaActivaAsignatura BIT, compartida BIT,
        horasSemanales INT NULL,   -- SES-GEN-01: columna agregada al resultset antes de totalRegistros
        totalRegistros INT);
    DECLARE @totalTodos INT, @totalOpt INT, @totalObl INT;

    -- Un coordinador de dos programas ve ambos; el filtro por caracter se aplica en la base
    UPDATE dbo.Programa SET coordinador = (SELECT c.id FROM dbo.Coordinador c WHERE c.usuario = @uCA) WHERE id = @progB;
    INSERT INTO @a EXEC dbo.usp_consultar_asignaturas_coordinador_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    SELECT @totalTodos = MAX(totalRegistros) FROM @a;
    DELETE FROM @a;
    INSERT INTO @a EXEC dbo.usp_consultar_asignaturas_coordinador_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @codigoCaracter = N'OPT';
    SELECT @totalOpt = MAX(totalRegistros) FROM @a;
    IF NOT EXISTS (SELECT 1 FROM @a WHERE idAsignatura = @asigOPT AND idPrograma = @progA)
       OR NOT EXISTS (SELECT 1 FROM @a WHERE idAsignatura = @asigOPT AND idPrograma = @progB)
        THROW 56001, 'TEST FAILED W2A_ASI_01: con caracter OPT deben salir las dos filas de la optativa compartida.', 1;
    IF EXISTS (SELECT 1 FROM @a WHERE codigoCaracter <> N'OPT') OR @totalOpt <> (SELECT COUNT(*) FROM @a)
        THROW 56002, 'TEST FAILED W2A_ASI_01: el filtro OPT solo debe devolver filas OPT y su total.', 1;
    PRINT 'TEST_PASS:W2A_ASI_01_FILTRO_CARACTER';

    DELETE FROM @a;
    INSERT INTO @a EXEC dbo.usp_consultar_asignaturas_coordinador_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @codigoCaracter = N'OBL';
    SELECT @totalObl = MAX(totalRegistros) FROM @a;
    IF EXISTS (SELECT 1 FROM @a WHERE idAsignatura = @asigOPT) OR EXISTS (SELECT 1 FROM @a WHERE codigoCaracter <> N'OBL')
        THROW 56003, 'TEST FAILED W2A_ASI_02: con caracter OBL no debe salir la optativa.', 1;
    IF @totalOpt + ISNULL(@totalObl, 0) <> @totalTodos
        THROW 56004, 'TEST FAILED W2A_ASI_02: los totales por caracter deben sumar el total sin filtro.', 1;
    PRINT 'TEST_PASS:W2A_ASI_02_TOTAL_POR_CARACTER';

    DELETE FROM @a;
    INSERT INTO @a EXEC dbo.usp_consultar_asignaturas_coordinador_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @codigoCaracter = N'   ';
    IF (SELECT MAX(totalRegistros) FROM @a) <> @totalTodos
        THROW 56005, 'TEST FAILED W2A_ASI_03: un caracter vacio equivale a sin filtro.', 1;
    DELETE FROM @a;
    INSERT INTO @a EXEC dbo.usp_consultar_asignaturas_coordinador_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @codigoCaracter = N'ZZZ';
    IF EXISTS (SELECT 1 FROM @a) THROW 56006, 'TEST FAILED W2A_ASI_03: un caracter inexistente no devuelve filas.', 1;
    PRINT 'TEST_PASS:W2A_ASI_03_VACIO_E_INEXISTENTE';

    -- Aislamiento: el coordinador de B (sin el programa A) no ve filas del programa A con ningun filtro
    UPDATE dbo.Programa SET coordinador = @coordB WHERE id = @progB;
    DELETE FROM @a;
    INSERT INTO @a EXEC dbo.usp_consultar_asignaturas_coordinador_paginado @idUsuarioEjecutor = @uCB, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @codigoCaracter = N'OPT';
    IF EXISTS (SELECT 1 FROM @a WHERE idPrograma <> @progB) OR NOT EXISTS (SELECT 1 FROM @a WHERE idAsignatura = @asigOPT AND idPrograma = @progB)
        THROW 56007, 'TEST FAILED W2A_ASI_04: el coordinador de B solo ve filas de su programa.', 1;
    PRINT 'TEST_PASS:W2A_ASI_04_AISLAMIENTO';

    -- ======================================================= Opciones del consolidado
    DECLARE @oa TABLE (id UNIQUEIDENTIFIER, nombre NVARCHAR(200));
    DECLARE @od TABLE (id UNIQUEIDENTIFIER, nombre NVARCHAR(400));

    INSERT INTO @oa EXEC dbo.usp_consultar_asignaturas_ambito_consolidado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c;
    INSERT INTO @od EXEC dbo.usp_consultar_docentes_ambito_consolidado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c;
    IF NOT EXISTS (SELECT 1 FROM @oa WHERE id = @asigOPT) OR NOT EXISTS (SELECT 1 FROM @od WHERE id = @docT)
        THROW 56011, 'TEST FAILED W2A_OPC_01: el coordinador A debe ver la asignatura y el docente del grupo de su programa.', 1;
    IF EXISTS (SELECT 1 FROM (SELECT id FROM @oa GROUP BY id HAVING COUNT(*) > 1) x) OR EXISTS (SELECT 1 FROM (SELECT id FROM @od GROUP BY id HAVING COUNT(*) > 1) x)
        THROW 56012, 'TEST FAILED W2A_OPC_01: las opciones no se repiten.', 1;
    IF EXISTS (SELECT 1 FROM @oa o WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v WHERE v.idAsignatura = o.id AND v.idPrograma = @progA))
        THROW 56013, 'TEST FAILED W2A_OPC_01: las asignaturas del coordinador A deben pertenecer a su programa.', 1;
    PRINT 'TEST_PASS:W2A_OPC_01_AMBITO_COORDINADOR';

    -- Aislamiento: el coordinador B solo ve opciones de grupos de asignaturas de su programa y no ve las exclusivas de A
    DECLARE @ob TABLE (id UNIQUEIDENTIFIER, nombre NVARCHAR(200));
    DECLARE @odb TABLE (id UNIQUEIDENTIFIER, nombre NVARCHAR(400));
    INSERT INTO @ob EXEC dbo.usp_consultar_asignaturas_ambito_consolidado @idUsuarioEjecutor = @uCB, @idCorrelacion = @c;
    INSERT INTO @odb EXEC dbo.usp_consultar_docentes_ambito_consolidado @idUsuarioEjecutor = @uCB, @idCorrelacion = @c;
    IF EXISTS (SELECT 1 FROM @ob o WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v WHERE v.idAsignatura = o.id AND v.idPrograma = @progB))
        THROW 56014, 'TEST FAILED W2A_OPC_02: el coordinador B solo ve asignaturas de su programa.', 1;
    IF NOT EXISTS (SELECT 1 FROM @oa o WHERE NOT EXISTS (SELECT 1 FROM @ob b WHERE b.id = o.id))
        THROW 56015, 'TEST FAILED W2A_OPC_02: debe haber opciones del programa A que el coordinador B no ve.', 1;
    IF EXISTS (SELECT 1 FROM @odb d WHERE NOT EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.uv_asignatura_plan_estudio v ON v.idAsignatura = g.asignatura AND v.idPrograma = @progB WHERE g.docente = d.id))
        THROW 56016, 'TEST FAILED W2A_OPC_02: el coordinador B solo ve docentes con grupos de su programa.', 1;
    PRINT 'TEST_PASS:W2A_OPC_02_AISLAMIENTO';

    -- Periodo: con el periodo del grupo sale la optativa; con otro periodo no sale nada
    DELETE FROM @oa; DELETE FROM @od;
    INSERT INTO @oa EXEC dbo.usp_consultar_asignaturas_ambito_consolidado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @idPeriodoAcademico = @periodo;
    INSERT INTO @od EXEC dbo.usp_consultar_docentes_ambito_consolidado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @idPeriodoAcademico = @periodo;
    IF NOT EXISTS (SELECT 1 FROM @oa WHERE id = @asigOPT) OR NOT EXISTS (SELECT 1 FROM @od WHERE id = @docT)
        THROW 56017, 'TEST FAILED W2A_OPC_03: con el periodo del grupo deben salir la asignatura y el docente.', 1;
    DELETE FROM @oa; DELETE FROM @od;
    INSERT INTO @oa EXEC dbo.usp_consultar_asignaturas_ambito_consolidado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @idPeriodoAcademico = @otroPeriodo;
    INSERT INTO @od EXEC dbo.usp_consultar_docentes_ambito_consolidado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @idPeriodoAcademico = @otroPeriodo;
    IF EXISTS (SELECT 1 FROM @oa) OR EXISTS (SELECT 1 FROM @od)
        THROW 56018, 'TEST FAILED W2A_OPC_03: un periodo sin grupos no devuelve opciones.', 1;
    PRINT 'TEST_PASS:W2A_OPC_03_PERIODO';

    -- Decano (su facultad) y administrador (su institucion) ven al menos lo del coordinador
    DELETE FROM @oa; DELETE FROM @od;
    DECLARE @oaDec TABLE (id UNIQUEIDENTIFIER, nombre NVARCHAR(200));
    DECLARE @oaAdm TABLE (id UNIQUEIDENTIFIER, nombre NVARCHAR(200));
    INSERT INTO @oa EXEC dbo.usp_consultar_asignaturas_ambito_consolidado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c;
    INSERT INTO @oaDec EXEC dbo.usp_consultar_asignaturas_ambito_consolidado @idUsuarioEjecutor = @uDec, @idCorrelacion = @c;
    INSERT INTO @oaAdm EXEC dbo.usp_consultar_asignaturas_ambito_consolidado @idUsuarioEjecutor = @uAdm, @idCorrelacion = @c;
    IF EXISTS (SELECT 1 FROM @oa o WHERE NOT EXISTS (SELECT 1 FROM @oaDec d WHERE d.id = o.id))
       OR EXISTS (SELECT 1 FROM @oaDec d WHERE NOT EXISTS (SELECT 1 FROM @oaAdm a WHERE a.id = d.id))
        THROW 56019, 'TEST FAILED W2A_OPC_04: coordinador <= decano <= administrador en las opciones.', 1;
    PRINT 'TEST_PASS:W2A_OPC_04_DECANO_Y_ADMINISTRADOR';

    -- Un docente no tiene perfil para el consolidado y un ejecutor nulo tampoco: ambos rechazados
    DECLARE @rechazo BIT = 0, @rechazo2 BIT = 0;
    BEGIN TRY
        INSERT INTO @oa EXEC dbo.usp_consultar_asignaturas_ambito_consolidado @idUsuarioEjecutor = @uT, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @rechazo = 1;
    END CATCH
    BEGIN TRY
        INSERT INTO @od EXEC dbo.usp_consultar_docentes_ambito_consolidado @idUsuarioEjecutor = NULL, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @rechazo2 = 1;
    END CATCH
    IF @rechazo = 0 OR @rechazo2 = 0 THROW 56020, 'TEST FAILED W2A_OPC_05: un docente o un ejecutor nulo deben ser rechazados.', 1;
    PRINT 'TEST_PASS:W2A_OPC_05_RECHAZOS';

    -- ======================================================= Estado del periodo desde la base
    DECLARE @pPlan UNIQUEIDENTIFIER = NEWID(), @pAct UNIQUEIDENTIFIER = NEWID(), @pCerr UNIQUEIDENTIFIER = NEWID();
    DECLARE @maxCodigo INT = (SELECT ISNULL(MAX(codigo), 0) FROM dbo.PeriodoAcademico);
    DECLARE @hoyUtc DATE = CAST(SYSUTCDATETIME() AS DATE);
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@pPlan, @inst, N'W2A-PLAN', @maxCodigo + 101, DATEADD(DAY, 30, @hoyUtc), DATEADD(DAY, 120, @hoyUtc), 2999),
           (@pAct, @inst, N'W2A-ACT', @maxCodigo + 102, DATEADD(DAY, -30, @hoyUtc), DATEADD(DAY, 30, @hoyUtc), 2998),
           (@pCerr, @inst, N'W2A-CERR', @maxCodigo + 103, DATEADD(DAY, -120, @hoyUtc), DATEADD(DAY, -30, @hoyUtc), 2997);
    IF (SELECT estado FROM dbo.uv_periodo_academico WHERE id = @pPlan) <> 'PLANEACION'
       OR (SELECT estado FROM dbo.uv_periodo_academico WHERE id = @pAct) <> 'ACTIVO'
       OR (SELECT estado FROM dbo.uv_periodo_academico WHERE id = @pCerr) <> 'CERRADO'
        THROW 56021, 'TEST FAILED W2A_PER_01: el estado del periodo debe ser PLANEACION, ACTIVO o CERRADO segun la fecha.', 1;
    PRINT 'TEST_PASS:W2A_PER_01_ESTADO';

    IF EXISTS (SELECT 1 FROM dbo.uv_periodo_academico WHERE estado IS NULL OR estado NOT IN ('PLANEACION', 'ACTIVO', 'CERRADO'))
        THROW 56022, 'TEST FAILED W2A_PER_02: ningun periodo queda sin estado.', 1;
    PRINT 'TEST_PASS:W2A_PER_02_SIEMPRE_CON_ESTADO';

    -- El rechazo COO_003 lo lanza un SP con XACT_ABORT ON: invalida la transaccion de la prueba, por eso va al final.
    DECLARE @ajeno BIT = 0;
    BEGIN TRY
        EXEC dbo.usp_consultar_asignaturas_coordinador_paginado @idUsuarioEjecutor = @uCB, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10, @idPrograma = @progA, @codigoCaracter = N'OPT';
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE N'%COO_003%' SET @ajeno = 1;
    END CATCH
    IF @ajeno = 0 THROW 56008, 'TEST FAILED W2A_ASI_04: pedir un programa ajeno con caracter debe responder COO_003.', 1;
    PRINT 'TEST_PASS:W2A_ASI_05_PROGRAMA_AJENO';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 56099, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 56098, 'TEST FAILED W2A_TRANCOUNT: la transaccion no se revirtio.', 1;
PRINT 'TEST_PASS:W2A_TRANCOUNT_ZERO';
GO
