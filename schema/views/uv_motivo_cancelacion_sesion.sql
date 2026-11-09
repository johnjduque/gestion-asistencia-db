USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: vista de catalogo (solo consulta) de los motivos de cancelacion de una sesion manual por el coordinador.
CREATE OR ALTER VIEW [dbo].[uv_motivo_cancelacion_sesion]
AS
SELECT  id = m.id,
        codigo = m.codigo,
        nombre = m.nombre,
        orden = m.orden,
        estaActivo = m.estaActivo
FROM    dbo.MotivoCancelacionSesion m;
GO
