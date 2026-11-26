USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 10 (plan por lotes 2026-11-25): indicadores y consultas.
-- Fija el comportamiento de los 3 internos que resuelven el periodo de los KPI (no tenian prueba directa), antes de refactorizarlos.
-- Los SP publicos del lote siguen cubiertos por sus pruebas de dominio. Solo lee.
--   SKL10_R01_PERIODO_KPI_PROGRAMA     usp_resolver_periodo_kpi_interno: periodo explicito, explicito inexistente (51000 PER_001),
--                                      vigente del programa (el mas reciente con grupo habilitado) y programa sin grupos (NULL)
--   SKL10_R02_PERIODO_KPI_FACULTAD     usp_resolver_periodo_kpi_facultad_interno: los mismos 4 casos por facultad
--   SKL10_R03_PERIODO_KPI_INSTITUCION  usp_resolver_periodo_kpi_institucion_interno: los mismos 4 casos por institucion
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote10_caracterizacion';

DECLARE @prog UNIQUEIDENTIFIER, @fac UNIQUEIDENTIFIER, @inst UNIQUEIDENTIFIER, @paCualquiera UNIQUEIDENTIFIER;
SELECT TOP 1 @prog = gp.idPrograma, @fac = p.idFacultad, @inst = p.idInstitucion
FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
WHERE gp.grupoEstaHablitado = 1 ORDER BY gp.idPrograma;
SELECT TOP 1 @paCualquiera = id FROM dbo.PeriodoAcademico ORDER BY id;
IF @prog IS NULL OR @paCualquiera IS NULL
    THROW 56000, 'TEST FAILED: SKL10 faltan fixtures del seed (programa con grupo habilitado y un periodo).', 1;

DECLARE @esperado UNIQUEIDENTIFIER, @r UNIQUEIDENTIFIER, @err NVARCHAR(4000), @num INT;
DECLARE @inexistente UNIQUEIDENTIFIER = '5C6A0000-0000-0000-0000-0000000010E9';

-- ================================================================= R01
EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @prog, @idPeriodoSolicitado = @paCualquiera, @idPeriodo = @r OUTPUT;
IF @r IS NULL OR @r <> @paCualquiera THROW 56010, 'TEST FAILED: SKL10_R01_PERIODO_KPI_PROGRAMA (explicito)', 1;
SELECT @err = NULL, @num = NULL;
BEGIN TRY
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @prog, @idPeriodoSolicitado = @inexistente, @idPeriodo = @r OUTPUT;
END TRY
BEGIN CATCH
    SELECT @err = ERROR_MESSAGE(), @num = ERROR_NUMBER();
END CATCH
IF @num IS NULL OR @num <> 51000 OR @err NOT LIKE N'DBCODE=PER[_]001|%' THROW 56011, 'TEST FAILED: SKL10_R01_PERIODO_KPI_PROGRAMA (PER_001)', 1;
SELECT TOP 1 @esperado = g.periodoAcademico
FROM dbo.Grupo g INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
WHERE EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp WHERE gp.idGrupo = g.id AND gp.idPrograma = @prog AND gp.grupoEstaHablitado = 1)
ORDER BY pa.fechaInicio DESC, pa.id ASC;
SET @r = @inexistente;
EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @prog, @idPeriodoSolicitado = NULL, @idPeriodo = @r OUTPUT;
IF @r IS NULL OR @r <> @esperado THROW 56012, 'TEST FAILED: SKL10_R01_PERIODO_KPI_PROGRAMA (vigente)', 1;
SET @r = @inexistente;
EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @inexistente, @idPeriodoSolicitado = NULL, @idPeriodo = @r OUTPUT;
IF @r IS NOT NULL THROW 56013, 'TEST FAILED: SKL10_R01_PERIODO_KPI_PROGRAMA (sin grupos: NULL)', 1;
PRINT 'TEST_PASS:SKL10_R01_PERIODO_KPI_PROGRAMA';

-- ================================================================= R02
EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @fac, @idPeriodoSolicitado = @paCualquiera, @idPeriodo = @r OUTPUT;
IF @r IS NULL OR @r <> @paCualquiera THROW 56020, 'TEST FAILED: SKL10_R02_PERIODO_KPI_FACULTAD (explicito)', 1;
SELECT @err = NULL, @num = NULL;
BEGIN TRY
    EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @fac, @idPeriodoSolicitado = @inexistente, @idPeriodo = @r OUTPUT;
END TRY
BEGIN CATCH
    SELECT @err = ERROR_MESSAGE(), @num = ERROR_NUMBER();
END CATCH
IF @num IS NULL OR @num <> 51000 OR @err NOT LIKE N'DBCODE=PER[_]001|%' THROW 56021, 'TEST FAILED: SKL10_R02_PERIODO_KPI_FACULTAD (PER_001)', 1;
SELECT TOP 1 @esperado = g.periodoAcademico
FROM dbo.Grupo g INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
WHERE EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
              WHERE gp.idGrupo = g.id AND p.idFacultad = @fac AND gp.grupoEstaHablitado = 1)
ORDER BY pa.fechaInicio DESC, pa.id ASC;
SET @r = @inexistente;
EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @fac, @idPeriodoSolicitado = NULL, @idPeriodo = @r OUTPUT;
IF @r IS NULL OR @r <> @esperado THROW 56022, 'TEST FAILED: SKL10_R02_PERIODO_KPI_FACULTAD (vigente)', 1;
SET @r = @inexistente;
EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @inexistente, @idPeriodoSolicitado = NULL, @idPeriodo = @r OUTPUT;
IF @r IS NOT NULL THROW 56023, 'TEST FAILED: SKL10_R02_PERIODO_KPI_FACULTAD (sin grupos: NULL)', 1;
PRINT 'TEST_PASS:SKL10_R02_PERIODO_KPI_FACULTAD';

-- ================================================================= R03
EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @inst, @idPeriodoSolicitado = @paCualquiera, @idPeriodo = @r OUTPUT;
IF @r IS NULL OR @r <> @paCualquiera THROW 56030, 'TEST FAILED: SKL10_R03_PERIODO_KPI_INSTITUCION (explicito)', 1;
SELECT @err = NULL, @num = NULL;
BEGIN TRY
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @inst, @idPeriodoSolicitado = @inexistente, @idPeriodo = @r OUTPUT;
END TRY
BEGIN CATCH
    SELECT @err = ERROR_MESSAGE(), @num = ERROR_NUMBER();
END CATCH
IF @num IS NULL OR @num <> 51000 OR @err NOT LIKE N'DBCODE=PER[_]001|%' THROW 56031, 'TEST FAILED: SKL10_R03_PERIODO_KPI_INSTITUCION (PER_001)', 1;
SELECT TOP 1 @esperado = g.periodoAcademico
FROM dbo.Grupo g INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
WHERE EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
              WHERE gp.idGrupo = g.id AND p.idInstitucion = @inst AND gp.grupoEstaHablitado = 1)
ORDER BY pa.fechaInicio DESC, pa.id ASC;
SET @r = @inexistente;
EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @inst, @idPeriodoSolicitado = NULL, @idPeriodo = @r OUTPUT;
IF @r IS NULL OR @r <> @esperado THROW 56032, 'TEST FAILED: SKL10_R03_PERIODO_KPI_INSTITUCION (vigente)', 1;
SET @r = @inexistente;
EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @inexistente, @idPeriodoSolicitado = NULL, @idPeriodo = @r OUTPUT;
IF @r IS NOT NULL THROW 56033, 'TEST FAILED: SKL10_R03_PERIODO_KPI_INSTITUCION (sin grupos: NULL)', 1;
PRINT 'TEST_PASS:SKL10_R03_PERIODO_KPI_INSTITUCION';

PRINT 'TEST END: test_skills_lote10_caracterizacion';
GO
