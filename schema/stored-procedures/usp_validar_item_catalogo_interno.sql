USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento interno: [dbo].[usp_validar_item_catalogo_interno]
-- Migracion 65: validacion de texto compartida por crear y actualizar categorias de justificacion y motivos de cancelacion.
--   * @nombre: obligatorio, hasta @maxNombre caracteres y solo letras, numeros, espacio y . , - _ ( ) / # : (regla DEC-073 del
--     backend, TextoSeguro) -> CTG_001.
--   * @maxCodigo NULL = no se valida el codigo (actualizar: el codigo no cambia). Si no es NULL: obligatorio, hasta @maxCodigo y
--     solo A-Z, 0-9 y guion bajo -> CTG_002.
--   * @maxDescripcion NULL = el catalogo no tiene descripcion. Si no es NULL y @descripcion trae texto: hasta @maxDescripcion y sin
--     los simbolos < ni > -> CTG_004.
-- Los limites los calcula el SP publico desde el tamano real de las columnas (sin cifras quemadas).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_item_catalogo_interno]
(
    @codigo                  NVARCHAR(4000),
    @maxCodigo               INT,
    @nombre                  NVARCHAR(4000),
    @maxNombre               INT,
    @descripcion             NVARCHAR(4000),
    @maxDescripcion          INT,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @codigoMensaje VARCHAR(20) = NULL;
    DECLARE @parametro1    NVARCHAR(500) = NULL;
    DECLARE @parametro2    NVARCHAR(500) = NULL;
BEGIN
    SET NOCOUNT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    IF NULLIF(TRIM(@nombre), N'') IS NULL OR LEN(TRIM(@nombre)) > @maxNombre
       OR PATINDEX(N'%[^A-Za-z0-9 .,_()/#:-]%' COLLATE Latin1_General_100_CI_AI, TRIM(@nombre)) > 0
    BEGIN
        SELECT @codigoMensaje = 'CTG_001', @parametro1 = N'nombre', @parametro2 = CONVERT(NVARCHAR(10), @maxNombre);
    END
    ELSE IF @maxCodigo IS NOT NULL
        AND (NULLIF(TRIM(@codigo), N'') IS NULL OR LEN(TRIM(@codigo)) > @maxCodigo
             OR PATINDEX(N'%[^A-Z0-9_]%' COLLATE Latin1_General_100_BIN2, TRIM(@codigo)) > 0)
    BEGIN
        SELECT @codigoMensaje = 'CTG_002', @parametro1 = CONVERT(NVARCHAR(10), @maxCodigo);
    END
    ELSE IF @maxDescripcion IS NOT NULL AND NULLIF(TRIM(@descripcion), N'') IS NOT NULL
        AND (LEN(TRIM(@descripcion)) > @maxDescripcion OR CHARINDEX(N'<', @descripcion) > 0 OR CHARINDEX(N'>', @descripcion) > 0)
    BEGIN
        SELECT @codigoMensaje = 'CTG_004', @parametro1 = CONVERT(NVARCHAR(10), @maxDescripcion);
    END

    IF @codigoMensaje IS NOT NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = @codigoMensaje,
            @p_param1 = @parametro1,
            @p_param2 = @parametro2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
        SET @estadoResultado = 0;
    END
END;
GO
