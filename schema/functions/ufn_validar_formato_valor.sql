USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- ufn_validar_formato_valor (INT-004, migracion 74)
--
-- Valida el valor propuesto de un parametro contra el formato declarado en CatalogoParametroEdicion.formato (metadato declarativo; sin
-- ramas por nombre de parametro). Devuelve NULL si cumple (o si @formato es NULL: sin formato declarado) o el codigo del mensaje:
--   PRM_017  formato CIDR_LIST: el valor no es una lista, separada por comas, de rangos CIDR IPv4 (a.b.c.d/n, n 0-32) o IPv6
--            (x:x::x/n, n 0-128). Cada elemento se recorta; un elemento vacio (coma sobrante) es invalido. El mismo criterio que
--            CidrRange.parse del backend (que ademas ignora en silencio lo invalido: por eso se rechaza aqui, no al leerlo).
-- Un formato desconocido no se valida aqui: CK_CPE_Formato impide declararlo.
-- ============================================================================
CREATE OR ALTER FUNCTION [dbo].[ufn_validar_formato_valor]
(
    @formato VARCHAR(20),
    @valor   NVARCHAR(4000)
)
RETURNS VARCHAR(20)
AS
BEGIN
    IF @formato IS NULL
        RETURN NULL;

    IF @formato = 'CIDR_LIST'
    BEGIN
        IF @valor IS NULL OR LEN(TRIM(@valor)) < 1
            RETURN 'PRM_017';
        IF EXISTS (SELECT 1 FROM STRING_SPLIT(@valor, ',') e WHERE dbo.ufn_es_cidr_valido(TRIM(e.value)) = 0)
            RETURN 'PRM_017';
    END

    RETURN NULL;
END;
GO
