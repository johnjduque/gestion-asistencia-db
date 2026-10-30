USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_plantilla_notificacion_activa_interno]
-- Capacidad: Plantillas de Notificacion (NOTIF-002A)
-- Ambito: Consulta interna atomica de plantilla activa y marcadores del tipo.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_plantilla_notificacion_activa_interno]
(
    @tipo   VARCHAR(60),
    @idioma CHAR(2)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Result set 2: Plantilla activa (0 o 1 fila)
    SELECT TOP 1
        [version] = p.[version],
        [asunto]  = p.[asunto],
        [cuerpo]  = p.[cuerpo]
    FROM dbo.PlantillaNotificacion p
    WHERE p.tipo = @tipo
      AND p.idioma = @idioma
      AND p.activa = 1;

    -- Result set 3: Marcadores declarados para el tipo
    SELECT
        [marcador]    = m.[marcador],
        [obligatorio] = m.[obligatorio]
    FROM dbo.PlantillaNotificacionMarcador m
    WHERE m.tipo = @tipo
    ORDER BY m.marcador ASC;
END;
GO
