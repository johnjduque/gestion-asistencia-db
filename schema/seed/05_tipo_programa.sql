USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: TipoPrograma
MERGE INTO [dbo].[TipoPrograma] AS Target
USING (VALUES
    ('83E61FB8-F400-4503-88D7-ECA7E775F7EB', 'pregrado', 1, 'PRE'),
    ('0C901262-EFED-4A1B-8CDC-FFB804F8C9D2', 'postgrado', 1, 'POS')
) AS Source (id, nombre, estado, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.estado = Source.estado, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, estado, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.estado, Source.codigo);
GO
