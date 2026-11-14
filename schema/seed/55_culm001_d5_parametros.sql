USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 D.5: tipo de documento por defecto de la alta individual (IDENTIDAD/TIPO_IDENTIFICACION_DEFECTO).
-- DEC-074 (2026-11-13): se retiro la carga masiva por CSV (HU171); sus parametros ya no se siembran.
-- ============================================================================
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('IDENTIDAD',    'TIPO_IDENTIFICACION_DEFECTO',   N'CC',      'STRING', N'CC')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
