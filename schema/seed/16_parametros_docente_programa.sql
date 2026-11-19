USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Parametros de la vertical de docentes (HU091). MEJORAS-SERGIO-2026-11-18 (migracion 50): se retiraron el catalogo
-- TipoVinculacion y el parametro DOCENTE/TIPO_VINCULACION_DEFECTO (el sistema no administra el tipo de vinculacion).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('DOCENTE', 'MAX_CANDIDATOS_BUSQUEDA', '20', 'INT', '20'),
    ('DOCENTE', 'BUSQUEDA_MIN_CARACTERES', '3', 'INT', '3')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.valor = Source.valor, Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- R2 (backfill idempotente): todo par (docente, programa) que hoy existe via grupos queda vinculado.
INSERT INTO [dbo].[DocentePrograma] (id, docente, programa, estado, fechaVinculacionUtc)
SELECT NEWID(), par.idDocente, par.idPrograma, 1, SYSUTCDATETIME()
FROM (SELECT DISTINCT id AS idDocente, idPrograma FROM [dbo].[uv_docente]) par
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[DocentePrograma] dp WHERE dp.docente = par.idDocente AND dp.programa = par.idPrograma);
GO
