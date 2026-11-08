USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, [SUPUESTO-D-15], HU171): jerarquia de alta masiva.
-- Pares:
--   COORDINADOR (CD)   -> DOCENTE (DO)
--   DECANO (DE)        -> COORDINADOR (CD)
--   ADMINISTRADOR (AD) -> DECANO (DE)
-- ============================================================================
MERGE INTO dbo.JerarquiaAltaUsuario AS Target
USING (
    SELECT 
        NEWID() AS id,
        pe.id AS perfilEjecutor,
        pd.id AS perfilDestino
    FROM (VALUES
        ('CD', 'DO'),
        ('DE', 'CD'),
        ('AD', 'DE')
    ) AS v(codEjecutor, codDestino)
    INNER JOIN dbo.Perfil pe ON (pe.codigo = v.codEjecutor OR UPPER(pe.nombre) = CASE v.codEjecutor WHEN 'CD' THEN 'COORDINADOR' WHEN 'DE' THEN 'DECANO' WHEN 'AD' THEN 'ADMINISTRADOR' END)
    INNER JOIN dbo.Perfil pd ON (pd.codigo = v.codDestino OR UPPER(pd.nombre) = CASE v.codDestino WHEN 'DO' THEN 'DOCENTE' WHEN 'CD' THEN 'COORDINADOR' WHEN 'DE' THEN 'DECANO' END)
) AS Source
ON (Target.perfilEjecutor = Source.perfilEjecutor AND Target.perfilDestino = Source.perfilDestino)
WHEN NOT MATCHED THEN
    INSERT (id, perfilEjecutor, perfilDestino)
    VALUES (Source.id, Source.perfilEjecutor, Source.perfilDestino);
GO
