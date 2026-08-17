USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: Institucion
MERGE INTO [dbo].[Institucion] AS Target
USING (VALUES
    ('B1C2D3E4-0000-0000-0000-000000000001', 'Universidad Catolica de Oriente', 1)
) AS Source (id, nombre, estado)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.estado = Source.estado
WHEN NOT MATCHED THEN
    INSERT (id, nombre, estado)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.estado);
GO

-- Sembrado Idempotente: Area
MERGE INTO [dbo].[Area] AS Target
USING (VALUES
    ('C1D2E3F4-0000-0000-0000-000000000001', 'Ingenieria de Software', 'ISW')
) AS Source (id, nombre, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO

-- Sembrado Idempotente: Componente
MERGE INTO [dbo].[Componente] AS Target
USING (VALUES
    ('63A26358-4651-4A3B-8B94-9481DDA60EC6', 'basicas', 'BAS'),
    ('412B5540-4CA2-4746-9476-E1DEC7B42BDB', 'institucionales', 'INS'),
    ('04ED2BC1-2C56-4116-855F-E2789125FBD2', 'especificas', 'ESP')
) AS Source (id, nombre, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO

