USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: Días de la semana
MERGE INTO [dbo].[Dia] AS Target
USING (VALUES
    ('B1B2C3D4-0000-0000-0000-000000000001', 'Lunes', 'LU'),
    ('B1B2C3D4-0000-0000-0000-000000000002', 'Martes', 'MA'),
    ('B1B2C3D4-0000-0000-0000-000000000003', 'Miercoles', 'MI'),
    ('B1B2C3D4-0000-0000-0000-000000000004', 'Jueves', 'JU'),
    ('B1B2C3D4-0000-0000-0000-000000000005', 'Viernes', 'VI'),
    ('B1B2C3D4-0000-0000-0000-000000000006', 'Sabado', 'SA'),
    ('B1B2C3D4-0000-0000-0000-000000000007', 'Domingo', 'DO')
) AS Source (id, nombre, codigo)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO
