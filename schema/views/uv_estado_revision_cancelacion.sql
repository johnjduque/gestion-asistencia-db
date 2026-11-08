USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del estado de una revision de cancelacion.
CREATE OR ALTER VIEW [dbo].[uv_estado_revision_cancelacion]
AS
SELECT  id = e.id, codigo = e.codigo, nombre = e.nombre, orden = e.orden, esInicial = e.esInicial,
        requiereAccionDocente = e.requiereAccionDocente, requiereAccionResolutor = e.requiereAccionResolutor,
        conservaMatricula = e.conservaMatricula, cancelaMatricula = e.cancelaMatricula, esFinal = e.esFinal
FROM    dbo.EstadoRevisionCancelacion e;
GO
