USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_resolver_periodo_kpi_interno]
-- HU065-HU070 (D8): periodo explicito (debe existir: PER_001) o el vigente del programa (grupo habilitado); NULL si no hay vigente.
-- =============================================================================
-- SKILLS-BD lote 10 (2026-11-26): DECLARE en la cabecera, PASO n y TRY/CATCH que relanza el mismo error. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_periodo_kpi_interno]
(
    @idPrograma          UNIQUEIDENTIFIER,
    @idPeriodoSolicitado UNIQUEIDENTIFIER = NULL,
    @idPeriodo           UNIQUEIDENTIFIER OUTPUT
)
AS
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Periodo solicitado: debe existir (PER_001)
        SET @idPeriodo = NULL;

        IF @idPeriodoSolicitado IS NOT NULL
        BEGIN
            SELECT @idPeriodo = pa.id FROM dbo.uv_periodo_academico pa WHERE pa.id = @idPeriodoSolicitado;
            IF @idPeriodo IS NULL
            BEGIN
                SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idPeriodoSolicitado) AS NVARCHAR(500));
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PER_001',
                    @p_param1 = @msgP1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                THROW 51000, @mensajeTecnicoResultado, 1;
            END

            RETURN;
        END

        -- PASO 2: Sin periodo solicitado: el mas reciente con grupos habilitados (NULL si no hay)
        SELECT TOP 1 @idPeriodo = gp.idPeriodoAcademico
        FROM dbo.uv_grupo_programa gp
        INNER JOIN dbo.uv_periodo_academico pa ON pa.id = gp.idPeriodoAcademico
        WHERE gp.idPrograma = @idPrograma AND gp.grupoEstaHablitado = 1
        ORDER BY pa.fechaInicio DESC, pa.id ASC;
    END TRY
    BEGIN CATCH
        -- PASO 3: el error, incluido el rechazo PER_001 (THROW 51000), se propaga igual al llamador (sin triplete propio,
        -- como antes).
        THROW;
    END CATCH
END;
GO
