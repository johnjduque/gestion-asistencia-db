USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  FUNCTION [dbo].[ufn_obtener_mensaje_exito]
(
	@idCorrelacion  NVARCHAR(50),
	@procedimiento NVARCHAR(200),
	@mensaje NVARCHAR(4000)
) RETURNS NVARCHAR(MAX) AS
BEGIN     
	DECLARE @tipo AS NVARCHAR(50) = 'EXITO'
	DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))))
	RETURN [dbo].[ufn_obtener_mensaje_desde_plantilla](@idCorrelacionDefecto, @tipo,'0', '0', '', @procedimiento, '0', @mensaje)
END
GO
