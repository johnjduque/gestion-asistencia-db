USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: Perfil
MERGE INTO [dbo].[Perfil] AS Target
USING (VALUES
    ('AFDBD36B-B82E-45E2-89CB-593521DEA688', 'administrador', 1, 'AD'),
    ('2096A7FC-1CE1-4FE0-A27A-F1CE4EC25837', 'decano', 2, 'DE'),
    ('B867516F-CE5C-46CA-905C-E3DCEC5830C8', 'coordinador', 3, 'CD'),
    ('D740A705-5E91-4302-830E-E4639EE6FA83', 'docente', 4, 'DO'),
    ('3EA68C47-5EDF-43B5-A8D2-040694B65250', 'estudiante', 5, 'ES')
) AS Source (id, nombre, nivel_acceso, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.nivel_acceso = Source.nivel_acceso, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, nivel_acceso, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.nivel_acceso, Source.codigo);
GO
