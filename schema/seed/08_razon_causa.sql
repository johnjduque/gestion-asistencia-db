USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: RazonCausa
MERGE INTO [dbo].[RazonCausa] AS Target
USING (VALUES
    ('00000000-0000-0000-0000-000000000001', 'Asistencia normal', 'AN'),
    ('00000000-0000-0000-0000-000000000002', 'Sin justa causa', 'SJC'),
    ('00000000-0000-0000-0000-000000000003', 'Excusa', 'EX'),
    ('00000000-0000-0000-0000-000000000004', 'Cancelado por voluntad propia', 'CPVP'),
    ('00000000-0000-0000-0000-000000000005', 'Cancelado por inasistencia', 'CPI')
) AS Source (id, nombre, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO
