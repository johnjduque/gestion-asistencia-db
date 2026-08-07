USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: Tipos de Identificación
MERGE INTO [dbo].[TipoIdentificacion] AS Target
USING (VALUES
    ('A1B2C3D4-0000-0000-0000-000000000001', 'CC', 'Cedula de ciudadania'),
    ('A1B2C3D4-0000-0000-0000-000000000002', 'TI', 'Tarjeta de identidad'),
    ('A1B2C3D4-0000-0000-0000-000000000003', 'PA', 'Pasaporte'),
    ('A1B2C3D4-0000-0000-0000-000000000004', 'CE', 'Cedula de extranjeria'),
    ('A1B2C3D4-0000-0000-0000-000000000005', 'PEP', 'Permiso especial de permanencia')
) AS Source (id, tipoIdentificacion, nombre)
ON (Target.tipoIdentificacion = Source.tipoIdentificacion)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre
WHEN NOT MATCHED THEN
    INSERT (id, tipoIdentificacion, nombre)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.tipoIdentificacion, Source.nombre);
GO
