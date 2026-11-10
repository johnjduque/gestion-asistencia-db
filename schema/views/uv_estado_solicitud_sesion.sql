USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (2): vista de catalogo (solo consulta) de los estados de la solicitud de sesion extraordinaria.
CREATE OR ALTER VIEW [dbo].[uv_estado_solicitud_sesion]
AS
SELECT  id = e.id,
        codigo = e.codigo,
        nombre = e.nombre,
        orden = e.orden,
        esFinal = e.esFinal,
        esAprobada = e.esAprobada
FROM    dbo.EstadoSolicitudSesion e;
GO
