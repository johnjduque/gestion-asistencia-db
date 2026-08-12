USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: Semestre
MERGE INTO [dbo].[Semestre] AS Target
USING (VALUES
    ('25D4F947-86CF-4F90-89F6-89633777E3E5', 'semestre uno', 1, 'S1'),
    ('A56F3A14-E2E6-4A18-ADA1-46036581A63D', 'semestre dos', 2, 'S2'),
    ('A55AFD55-FC2E-4F1C-A2AC-837D026F7407', 'semestre tres', 3, 'S3'),
    ('27D1A42E-142B-43A4-B22B-5CBAABD015B3', 'semestre cuatro', 4, 'S4'),
    ('00D9E101-BA8E-4193-B6AB-B9BE2345EB0E', 'semestre cinco', 5, 'S5'),
    ('C6F407FA-04A1-4569-B541-2EF6670BBC6A', 'semestre seis', 6, 'S6'),
    ('5F129E17-1C38-4824-8657-9191FF563393', 'semestre siete', 7, 'S7'),
    ('BBFEAF8F-97F9-4180-AB33-8D89B64DED9B', 'semestre ocho', 8, 'S8'),
    ('EAD25AA4-A90A-4A84-8891-B3B48C77929B', 'semestre nueve', 9, 'S9'),
    ('AF9B338B-B0CD-4858-9882-78F3BD850157', 'semestre diez', 10, 'S10')
) AS Source (id, nombre, numero, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo OR Target.numero = Source.numero)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.numero = Source.numero, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, numero, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.numero, Source.codigo);
GO
