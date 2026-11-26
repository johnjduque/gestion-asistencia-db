USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_resolver_facultad_decano_interno]
-- HU102/HU103/HU106/HU144: valida correlacion y ejecutor y resuelve la facultad que dirige el decano (ambito).
-- Falla con THROW (DBCODE=...): CORR_001, VAL_001 (ejecutor nulo), KPI_003 (no es decano de una facultad), KPI_002 (umbral ausente).
-- =============================================================================
-- SKILLS-BD lote 4 (2026-11-25): DECLARE en la cabecera, PASO n, IF con BEGIN/END, rol por uv_decano_rol (antes, la
-- tabla) y TRY/CATCH que relanza; misma firma y mismos rechazos.
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_facultad_decano_interno]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @validarUmbrales   BIT = 1,
    @idFacultad        UNIQUEIDENTIFIER OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @msgP1 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: respuesta inicial y correlacion obligatoria
        SET @idFacultad = NULL;
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 2: ejecutor obligatorio (VAL_001)
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

        -- PASO 3: facultad del decano con el rol activo (KPI_003 si no tiene)
        SELECT TOP 1 @idFacultad = f.id
        FROM dbo.uv_facultad f
        INNER JOIN dbo.uv_decano_identidad di ON di.id = f.idDecano
        WHERE di.idUsuario = @idUsuarioEjecutor
          -- CULM-001 A.2-8 (A2-T-12): un rol de decano desactivado (Decano.estado = 0) no resuelve facultad (KPI_003).
          AND EXISTS (SELECT 1 FROM dbo.uv_decano_rol d WHERE d.id = di.id AND d.estaActivoRolDecano = 1)
        ORDER BY f.estaActivaFacultad DESC, f.nombreFacultad ASC, f.id ASC;

        IF @idFacultad IS NULL
        BEGIN
            SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idUsuarioEjecutor) AS NVARCHAR(500));
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'KPI_003',
                @p_param1 = @msgP1,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 4: umbrales de permanencia configurados (KPI_002)
        IF @validarUmbrales = 1 AND dbo.ufn_clasificar_permanencia(0, N'A') IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'KPI_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            THROW 51000, @mensajeTecnicoResultado, 1;
        END
    END TRY
    BEGIN CATCH
        -- PASO 5: resolvedor de ambito sin triplete (lo consumen las lecturas): el rechazo (THROW 51000) y
        -- cualquier otro error se propagan al llamador, que es una consulta READ_QUERY_RESULTSET
        THROW;
    END CATCH
END;
GO
