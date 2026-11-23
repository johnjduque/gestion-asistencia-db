USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: EstadoEstudianteGrupo
MERGE INTO [dbo].[EstadoEstudianteGrupo] AS Target
USING (VALUES
    ('382109E2-E532-469C-887A-083607C21046', 'Cancelado por voluntad propia', 'CVP'),
    ('9251DDDA-E3CC-4127-81C4-208451B37B6F', 'Activo', 'A'),
    ('A7F1B3E0-1234-4567-8901-208451B37B7E', 'Inactivo', 'I'),
    ('28DBE539-7421-4D00-9FFE-A82CF5F6A350', 'Cancelado por inasistencia', 'CI'),
    ('2DC630F5-DF12-4D52-95E3-F40F85FCB1DA', 'Finalizado', 'F')
) AS Source (id, nombre, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO
