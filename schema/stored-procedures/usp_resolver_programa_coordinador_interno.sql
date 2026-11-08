USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_resolver_programa_coordinador_interno]
-- HU065-HU070: valida correlacion y ejecutor y resuelve el programa que coordina el usuario (ambito).
-- Falla con THROW (DBCODE=...): VAL_001 (ejecutor nulo), KPI_001 (no es coordinador de un programa), KPI_002 (umbral ausente).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_programa_coordinador_interno]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @validarUmbrales   BIT = 1,
    @idPrograma        UNIQUEIDENTIFIER OUTPUT,
    @idProgramaSolicitado UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @msgP1 NVARCHAR(500);

    SET @idPrograma = NULL;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0 THROW 51000, @mensajeTecnicoResultado, 1;

    IF @idUsuarioEjecutor IS NULL OR @idUsuarioEjecutor = @guidVacio
    BEGIN
        SET @msgP1 = CAST(N'UsuarioEjecutor' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- CULM-001 B2NM (R8, S4): sin TOP 1. Con @idProgramaSolicitado se valida que sea de su coordinacion (COO_003); sin el:
    -- un programa -> ese; varios -> COO_002; ninguno -> KPI_001.
    DECLARE @totalProgramasCoordinador INT = (SELECT COUNT(*) FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor));
    IF @idProgramaSolicitado IS NOT NULL
    BEGIN
        SELECT @idPrograma = x.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) x WHERE x.idPrograma = @idProgramaSolicitado;
        IF @idPrograma IS NULL AND @totalProgramasCoordinador > 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'COO_003',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            THROW 51000, @mensajeTecnicoResultado, 1;
        END
    END
    ELSE IF @totalProgramasCoordinador = 1
        SELECT @idPrograma = x.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) x;
    ELSE IF @totalProgramasCoordinador > 1
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'COO_002',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    IF @idPrograma IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'KPI_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    IF @validarUmbrales = 1 AND dbo.ufn_clasificar_permanencia(0, N'A') IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'KPI_002',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

END;
GO
