USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- 1. Sembrado Idempotente: Facultad
MERGE INTO [dbo].[Facultad] AS Target
USING (VALUES
    ('A2B3C4D5-0000-0000-0000-000000000001', 'Facultad de Ingenieria', 'B1C2D3E4-0000-0000-0000-000000000001', 'F1A2B3C4-0000-0000-0000-000000000001', 1)
) AS Source (id, nombre, institucion, decano, estado)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.estado = Source.estado
WHEN NOT MATCHED THEN
    INSERT (id, nombre, institucion, decano, estado)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, TRY_CAST(Source.institucion AS UNIQUEIDENTIFIER), TRY_CAST(Source.decano AS UNIQUEIDENTIFIER), Source.estado);
GO

-- 2. Sembrado Idempotente: Programa
DECLARE @TipoPRE UNIQUEIDENTIFIER;
SELECT TOP 1 @TipoPRE = id FROM [dbo].[TipoPrograma] WHERE codigo = 'PRE';

MERGE INTO [dbo].[Programa] AS Target
USING (VALUES
    ('B2C3D4E5-0000-0000-0000-000000000001', 'A2B3C4D5-0000-0000-0000-000000000001', @TipoPRE, 'Ingenieria de Sistemas', 'F1A2B3C4-0000-0000-0000-000000000002', 1)
) AS Source (id, facultad, tipoDePrograma, nombre, coordinador, estado)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.estado = Source.estado
WHEN NOT MATCHED THEN
    INSERT (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.facultad AS UNIQUEIDENTIFIER), Source.tipoDePrograma, Source.nombre, TRY_CAST(Source.coordinador AS UNIQUEIDENTIFIER), Source.estado);
GO

-- 3. Sembrado Idempotente: PlanEstudio
MERGE INTO [dbo].[PlanEstudio] AS Target
USING (VALUES
    ('C2D3E4F5-0000-0000-0000-000000000001', 'B2C3D4E5-0000-0000-0000-000000000001', 2024, 1)
) AS Source (id, programa, inp, estado)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.inp = Source.inp, Target.estado = Source.estado
WHEN NOT MATCHED THEN
    INSERT (id, programa, inp, estado)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.programa AS UNIQUEIDENTIFIER), Source.inp, Source.estado);
GO

-- 4. Sembrado Idempotente: SemestrePlanEstudio
DECLARE @Semestre8 UNIQUEIDENTIFIER;
SELECT TOP 1 @Semestre8 = id FROM [dbo].[Semestre] WHERE codigo = 'S8';

MERGE INTO [dbo].[SemestrePlanEstudio] AS Target
USING (VALUES
    ('D2E3F4A5-0000-0000-0000-000000000001', 'C2D3E4F5-0000-0000-0000-000000000001', @Semestre8)
) AS Source (id, planEstudio, semestre)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN NOT MATCHED THEN
    INSERT (id, planEstudio, semestre)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.planEstudio AS UNIQUEIDENTIFIER), Source.semestre);
GO

-- 5. Sembrado Idempotente: Asignatura (CULM-001 B2NM: sin semestrePlanEstudio; el vinculo vive en AsignaturaPlanEstudio)
MERGE INTO [dbo].[Asignatura] AS Target
USING (VALUES
    ('E2F3A4B5-0000-0000-0000-000000000001', 'ARQ-402', 'Arquitectura de Software', 3, 'C1D2E3F4-0000-0000-0000-000000000001', '04ED2BC1-2C56-4116-855F-E2789125FBD2', 1)
) AS Source (id, codigo, nombre, credito, area, componente, estado)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo, Target.estado = Source.estado
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, credito, area, componente, estado)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.codigo, Source.nombre, Source.credito, TRY_CAST(Source.area AS UNIQUEIDENTIFIER), TRY_CAST(Source.componente AS UNIQUEIDENTIFIER), Source.estado);
GO

-- 5b. Catalogo de caracter (mismo MERGE que 37_caracter_asignatura_plan.sql: esta semilla corre antes) y vinculo ARQ-402 <-> SPE, caracter OBL por codigo.
MERGE INTO [dbo].[CaracterAsignaturaPlan] AS Target
USING (VALUES
    ('E1B2C3D4-0001-4B2A-9A00-000000000001', N'OBL', N'Obligatoria', 1, 1),
    ('E1B2C3D4-0001-4B2A-9A00-000000000002', N'OPT', N'Optativa', 2, 1)
) AS Source (id, codigo, nombre, orden, estado)
ON (Target.codigo = Source.codigo)
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, orden, estado)
    VALUES (CAST(Source.id AS UNIQUEIDENTIFIER), Source.codigo, Source.nombre, Source.orden, Source.estado);
GO

MERGE INTO [dbo].[AsignaturaPlanEstudio] AS Target
USING (SELECT id = CAST('E2F3A4B5-0001-0000-0000-000000000001' AS UNIQUEIDENTIFIER),
              asignatura = CAST('E2F3A4B5-0000-0000-0000-000000000001' AS UNIQUEIDENTIFIER),
              semestrePlanEstudio = CAST('D2E3F4A5-0000-0000-0000-000000000001' AS UNIQUEIDENTIFIER),
              caracter = (SELECT id FROM [dbo].[CaracterAsignaturaPlan] WHERE codigo = N'OBL'),
              -- Vigencia S1 (CONTRACT B2 §2.1): el vinculo sembrado se fecha al inicio del periodo sembrado (2026-2, 2026-08-01),
              -- igual que el backfill de la migracion 17 (MIN(fechaInicio) de los periodos). Con el DEFAULT (hoy) un despliegue
              -- desde cero dejaba fuera de ambito los grupos de periodos ya vencidos y divergia de una BD migrada.
              fechaVinculacionUtc = CAST('2026-08-01' AS DATETIME2(3))) AS Source
ON (Target.asignatura = Source.asignatura AND Target.semestrePlanEstudio = Source.semestrePlanEstudio)
WHEN NOT MATCHED THEN
    INSERT (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc)
    VALUES (Source.id, Source.asignatura, Source.semestrePlanEstudio, Source.caracter, 1, Source.fechaVinculacionUtc);
GO

-- 6. Sembrado Idempotente: PeriodoAcademico
MERGE INTO [dbo].[PeriodoAcademico] AS Target
USING (VALUES
    ('F2A3B4C5-0000-0000-0000-000000000001', 'B1C2D3E4-0000-0000-0000-000000000001', '2026-2', 20262, '2026-08-01', '2026-12-15', 2026)
) AS Source (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo, Target.fechaInicio = CAST(Source.fechaInicio AS DATE), Target.fechaFin = CAST(Source.fechaFin AS DATE)
WHEN NOT MATCHED THEN
    INSERT (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.institucion AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo, CAST(Source.fechaInicio AS DATE), CAST(Source.fechaFin AS DATE), Source.anio);
GO
