USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) de las transiciones de la revision de cancelacion.
CREATE OR ALTER VIEW [dbo].[uv_transicion_revision_cancelacion]
AS
SELECT  id = t.id, idEstadoOrigen = t.estadoOrigen, codigoEstadoOrigen = o.codigo, codigoDecision = t.codigoDecision,
        esDecisionResolutor = t.esDecisionResolutor, idEstadoDestino = t.estadoDestino, codigoEstadoDestino = d.codigo,
        exigeUmbralPerdida = t.exigeUmbralPerdida, exigeResolutorDisponible = t.exigeResolutorDisponible,
        codigoMensajeExito = t.codigoMensajeExito, tipoPlantillaNotificacion = t.tipoPlantillaNotificacion
FROM    dbo.TransicionRevisionCancelacion t
INNER JOIN dbo.EstadoRevisionCancelacion o ON o.id = t.estadoOrigen
INNER JOIN dbo.EstadoRevisionCancelacion d ON d.id = t.estadoDestino;
GO
