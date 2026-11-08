USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.3, O-1): umbral vigente de un tipo de alerta de inasistencia. Solo lee tablas base (las funciones se
-- despliegan antes que las vistas). Misma regla que ufn_obtener_parametro (valor, si no valorDefecto); NULL si falta o no es numerico.
CREATE OR ALTER FUNCTION [dbo].[ufn_umbral_alerta_inasistencia] (@idTipoAlerta UNIQUEIDENTIFIER)
RETURNS DECIMAL(5,2)
AS
BEGIN
    RETURN (
        SELECT TOP 1 TRY_CAST(NULLIF(TRIM(CAST(ISNULL(p.valor, p.valorDefecto) AS NVARCHAR(50))), N'') AS DECIMAL(5,2))
        FROM dbo.TipoAlertaInasistencia t
        INNER JOIN dbo.CatalogoParametro p ON p.grupo = t.grupoParametroUmbral AND p.clave = t.claveParametroUmbral AND p.estaActivo = 1
        WHERE t.id = @idTipoAlerta
    );
END;
GO
