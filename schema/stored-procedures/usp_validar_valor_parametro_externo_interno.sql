USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_validar_valor_parametro_externo_interno (INT-004, migracion 73)
--
-- Validador interno de usp_sincronizar_parametro_catalogo_externo. Aplica al valor que trae el Catalogo de Parametros externo las mismas
-- reglas de tipo, rango y lista permitida que la edicion local (ufn_validar_valor_parametro, PRM_004/005/006), con los limites de
-- CatalogoParametroEdicion cuando el parametro tiene fila (si no la tiene, solo se valida el tipo). NO aplica la lista blanca de edicion
-- ni la regla cruzada PRM_007: la fuente de verdad del valor es el catalogo externo y una regla entre dos parametros que cambian en
-- eventos distintos rechazaria valores correctos segun el orden de llegada.
-- Formato declarativo (CatalogoParametroEdicion.formato, ufn_validar_formato_valor): tras tipo/rango/lista, un valor que no cumple el formato
-- (p. ej. una lista CIDR mal formada en RED/CIDRS_CAMPUS) se rechaza con PRM_017.
-- Salida: @codigoRechazo NULL si el valor es valido, o PRM_004 / PRM_005 / PRM_006 / PRM_017 con los marcadores del mensaje en @param1/@param2.
-- @idCorrelacion es el de la llamada (trazabilidad: este SP no registra ni escribe). No abre transacciones ni escribe.
-- ============================================================================
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): DECLARE en la cabecera, PASO n, IF con BEGIN/END, parametro y reglas de edicion por
-- uv_parametro_registro y uv_parametro_edicion_registro (antes, las tablas) y TRY/CATCH que relanza (antes, sin TRY).
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_valor_parametro_externo_interno]
(
    @idParametro    UNIQUEIDENTIFIER,
    @valor          NVARCHAR(4000),
    @idCorrelacion  UNIQUEIDENTIFIER,
    @codigoRechazo  VARCHAR(20)   OUTPUT,
    @param1         NVARCHAR(500) OUTPUT,
    @param2         NVARCHAR(500) OUTPUT
)
AS
    DECLARE @tipoDato    VARCHAR(20);
    DECLARE @valorMinimo DECIMAL(19,4);
    DECLARE @valorMaximo DECIMAL(19,4);
    DECLARE @permitidos  NVARCHAR(500);
    DECLARE @formato     VARCHAR(20);
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 0: salidas vacias
        SET @codigoRechazo = NULL;
        SET @param1 = NULL;
        SET @param2 = NULL;

        -- PASO 1: tipo y reglas de edicion del parametro (sin filtrar por estado)
        SELECT @tipoDato = p.tipoDato, @valorMinimo = e.valorMinimo, @valorMaximo = e.valorMaximo, @permitidos = e.valoresPermitidos, @formato = e.formato
        FROM dbo.uv_parametro_registro p
        LEFT JOIN dbo.uv_parametro_edicion_registro e ON e.idParametro = p.id
        WHERE p.id = @idParametro;

        -- PASO 2: tipo, rango y lista permitida; despues, el formato
        SET @codigoRechazo = dbo.ufn_validar_valor_parametro(@tipoDato, @valor, @valorMinimo, @valorMaximo, @permitidos);
        IF @codigoRechazo IS NULL
        BEGIN
            SET @codigoRechazo = dbo.ufn_validar_formato_valor(@formato, TRIM(@valor));
        END

        -- PASO 3: parametros del mensaje segun el rechazo
        IF @codigoRechazo = 'PRM_004'
        BEGIN
            SET @param1 = @tipoDato;
        END
        ELSE IF @codigoRechazo = 'PRM_005'
        BEGIN
            SET @param1 = IIF(@valorMinimo IS NULL, N'-', IIF(@valorMinimo = FLOOR(@valorMinimo), CONVERT(NVARCHAR(40), CONVERT(BIGINT, @valorMinimo)), CONVERT(NVARCHAR(40), @valorMinimo)));
            SET @param2 = IIF(@valorMaximo IS NULL, N'-', IIF(@valorMaximo = FLOOR(@valorMaximo), CONVERT(NVARCHAR(40), CONVERT(BIGINT, @valorMaximo)), CONVERT(NVARCHAR(40), @valorMaximo)));
        END
        ELSE IF @codigoRechazo = 'PRM_006'
        BEGIN
            SET @param1 = @permitidos;
        END
    END TRY
    BEGIN CATCH
        -- PASO 4: el error se propaga igual al llamador (sin triplete propio, como antes)
        THROW;
    END CATCH
END;
GO
