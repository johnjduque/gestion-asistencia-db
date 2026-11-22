USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  FUNCTION [dbo].[ufn_obtener_detalle_error] (@idCorrelacion UNIQUEIDENTIFIER) RETURNS NVARCHAR(MAX) AS
BEGIN     
	DECLARE @tipo AS NVARCHAR(50) = 'ERROR'
	DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION')
	RETURN [dbo].[ufn_obtener_mensaje_desde_plantilla](@idCorrelacionDefecto, @tipo, ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE())
END
GO
