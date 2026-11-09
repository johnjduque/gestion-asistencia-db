USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del estado de una alerta de inasistencia.
CREATE OR ALTER VIEW [dbo].[uv_estado_alerta_inasistencia]
AS
SELECT  id = e.id, codigo = e.codigo, nombre = e.nombre, estaVigente = e.estaVigente
FROM    dbo.EstadoAlertaInasistencia e;
GO
