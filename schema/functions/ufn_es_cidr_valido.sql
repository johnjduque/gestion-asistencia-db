USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- ufn_es_cidr_valido (INT-004, migracion 74)
--
-- 1 si @cidr es un rango CIDR IPv4 (a.b.c.d/n: cuatro octetos 0-255, n 0-32) o IPv6 (grupos hexadecimales de 1 a 4 digitos, un
-- unico "::" opcional, 8 grupos sin "::" o a lo sumo 7 con el, n 0-128). 0 en cualquier otro caso (incluye NULL y vacio).
-- Solo direcciones literales; no se aceptan nombres ni la forma IPv6 con IPv4 incrustada.
-- ============================================================================
CREATE OR ALTER FUNCTION [dbo].[ufn_es_cidr_valido]
(
    @cidr NVARCHAR(100)
)
RETURNS BIT
AS
BEGIN
    DECLARE @texto     NVARCHAR(100) = TRIM(@cidr);
    DECLARE @barra     INT;
    DECLARE @direccion NVARCHAR(100);
    DECLARE @prefijoTx NVARCHAR(100);
    DECLARE @prefijo   INT;
    DECLARE @i         INT;
    DECLARE @octeto    NVARCHAR(100);

    IF @texto IS NULL OR LEN(@texto) < 3
        RETURN 0;

    SET @barra = CHARINDEX('/', @texto);
    IF @barra < 2 OR @barra = LEN(@texto) OR LEN(@texto) - LEN(REPLACE(@texto, '/', '')) <> 1
        RETURN 0;

    SET @direccion = SUBSTRING(@texto, 1, @barra - 1);
    SET @prefijoTx = SUBSTRING(@texto, @barra + 1, LEN(@texto));
    IF @prefijoTx LIKE '%[^0-9]%' OR LEN(@prefijoTx) > 3
        RETURN 0;
    SET @prefijo = CONVERT(INT, @prefijoTx);

    -- IPv4: solo digitos y puntos, exactamente tres puntos y cuatro octetos de 1 a 3 digitos con valor <= 255
    IF @direccion NOT LIKE '%[^0-9.]%'
    BEGIN
        IF @prefijo > 32 OR LEN(@direccion) - LEN(REPLACE(@direccion, '.', '')) <> 3
            RETURN 0;
        SET @i = 1;
        WHILE @i <= 4
        BEGIN
            SET @octeto = PARSENAME(@direccion, @i);
            IF @octeto IS NULL OR LEN(@octeto) < 1 OR LEN(@octeto) > 3 OR CONVERT(INT, @octeto) > 255
                RETURN 0;
            SET @i += 1;
        END
        RETURN 1;
    END

    -- IPv6: solo hexadecimales y dos puntos, con al menos un ":"
    IF @prefijo > 128 OR @direccion LIKE '%[^0-9a-fA-F:]%' OR CHARINDEX(':', @direccion) = 0 OR @direccion LIKE '%:::%'
        RETURN 0;

    DECLARE @dobles INT = (LEN(@direccion) - LEN(REPLACE(@direccion, '::', ''))) / 2;
    IF @dobles > 1
        RETURN 0;
    -- Un ":" inicial o final solo es valido como parte de "::"
    IF (@direccion LIKE ':%' AND @direccion NOT LIKE '::%') OR (@direccion LIKE '%:' AND @direccion NOT LIKE '%::')
        RETURN 0;

    DECLARE @grupos INT = (SELECT COUNT(1) FROM STRING_SPLIT(@direccion, ':') g WHERE LEN(g.value) > 0);
    IF EXISTS (SELECT 1 FROM STRING_SPLIT(@direccion, ':') g WHERE LEN(g.value) > 4)
        RETURN 0;
    IF @dobles = 0
        RETURN IIF(@grupos = 8 AND NOT EXISTS (SELECT 1 FROM STRING_SPLIT(@direccion, ':') g WHERE LEN(g.value) = 0), 1, 0);
    RETURN IIF(@grupos <= 7, 1, 0);
END;
GO
