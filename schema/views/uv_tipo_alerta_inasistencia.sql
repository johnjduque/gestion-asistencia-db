USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del tipo de alerta de inasistencia.
CREATE OR ALTER VIEW [dbo].[uv_tipo_alerta_inasistencia]
AS
SELECT  id = t.id, codigo = t.codigo, nombre = t.nombre, nivel = t.nivel,
        grupoParametroUmbral = t.grupoParametroUmbral, claveParametroUmbral = t.claveParametroUmbral,
        tipoPlantillaEstudiante = t.tipoPlantillaEstudiante, codigoMensajeUsuario = t.codigoMensajeUsuario,
        creaRevisionCancelacion = t.creaRevisionCancelacion
FROM    dbo.TipoAlertaInasistencia t;
GO
