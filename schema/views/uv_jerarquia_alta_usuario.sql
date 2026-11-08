USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, HU171): vista de jerarquia de alta masiva de usuarios.
-- ============================================================================
CREATE OR ALTER VIEW dbo.uv_jerarquia_alta_usuario
AS
SELECT 
    j.id,
    j.perfilEjecutor,
    pe.codigo AS codigoPerfilEjecutor,
    pe.nombre AS nombrePerfilEjecutor,
    j.perfilDestino,
    pd.codigo AS codigoPerfilDestino,
    pd.nombre AS nombrePerfilDestino
FROM dbo.JerarquiaAltaUsuario j
INNER JOIN dbo.Perfil pe ON pe.id = j.perfilEjecutor
INNER JOIN dbo.Perfil pd ON pd.id = j.perfilDestino;
GO
