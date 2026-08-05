USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: Parámetros del sistema
MERGE INTO [dbo].[Parametro] AS Target
USING (VALUES
    ('GENERAL', 'UUID_DEFECTO', '00000000-0000-0000-0000-000000000000', 'UUID comodin por defecto para representar valores nulos o no especificados')
) AS Source (grupo, clave, valor, descripcion)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.valor = Source.valor, Target.descripcion = Source.descripcion
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, descripcion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.descripcion);
GO
