USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION [dbo].[ufn_obtener_mensaje_desde_plantilla]
	(
		@idCorrelacion  NVARCHAR(50),
		@tipo NVARCHAR(50),
		@numero NVARCHAR(50),
		@severidad NVARCHAR(50),
		@estado NVARCHAR(50),
		@procedimiento NVARCHAR(200),
		@linea NVARCHAR(50),
		@mensaje NVARCHAR(4000)
	) RETURNS NVARCHAR(MAX) AS
BEGIN   

		DECLARE @idCorrelacionDefecto AS NVARCHAR(50) = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))))
		DECLARE @tipoDefecto AS NVARCHAR(50) = TRIM(ISNULL(@tipo, ''))
		DECLARE @numeroDefecto AS NVARCHAR(50) = TRIM(ISNULL(@numero, ''))
		DECLARE @severidadDefecto AS NVARCHAR(50) =TRIM( ISNULL(@severidad, ''))
		DECLARE @estadoDefecto AS NVARCHAR(50) = TRIM(ISNULL(@estado, ''))
		DECLARE @procedimientoDefecto AS NVARCHAR(200) = TRIM(ISNULL(@procedimiento, ''))
		DECLARE @lineaDefecto NVARCHAR(50) = TRIM(ISNULL(@linea, ''))
		DECLARE @mensajeDefecto NVARCHAR(4000) = TRIM(ISNULL(@mensaje, ''))
		DECLARE @valor AS NVARCHAR(MAX) = ''
		DECLARE @plantilla AS NVARCHAR(MAX) = '[CORRELATION_ID=${1}][ORIGEN=BASE_DATOS][TYPE=${2}][NUMBER=${3}][SEVERITY=${4}][STATE=${5}][PROCEDURE=${6}][LINE=${7}][MESSAGE=${8}]'
	
		SET	@valor = REPLACE(@plantilla, '${1}', @idCorrelacionDefecto)
		SET	@valor = REPLACE(@valor, '${2}', @tipoDefecto)
		SET	@valor = REPLACE(@valor, '${3}', @numeroDefecto)
		SET	@valor = REPLACE(@valor, '${4}', @severidadDefecto)
		SET	@valor = REPLACE(@valor, '${5}', @estadoDefecto)
		SET	@valor = REPLACE(@valor, '${6}', @procedimientoDefecto)
		SET	@valor = REPLACE(@valor, '${7}', @lineaDefecto)
		SET	@valor = REPLACE(@valor, '${8}', @mensajeDefecto)
		
	RETURN @valor
END
GO
