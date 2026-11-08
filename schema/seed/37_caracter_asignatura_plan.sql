USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (DEC-019, CONTRACT §2.1): catalogo del caracter de la asignatura en el plan. Ids fijos, resueltos por codigo.
MERGE INTO [dbo].[CaracterAsignaturaPlan] AS Target
USING (VALUES
    ('E1B2C3D4-0001-4B2A-9A00-000000000001', N'OBL', N'Obligatoria', 1, 1),
    ('E1B2C3D4-0001-4B2A-9A00-000000000002', N'OPT', N'Optativa', 2, 1)
) AS Source (id, codigo, nombre, orden, estado)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.orden = Source.orden, Target.estado = Source.estado
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, orden, estado)
    VALUES (CAST(Source.id AS UNIQUEIDENTIFIER), Source.codigo, Source.nombre, Source.orden, Source.estado);
GO
