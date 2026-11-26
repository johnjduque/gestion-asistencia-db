USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_docentes_programa (HU095)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Consolidado del directorio docente del programa del COORDINADOR: UNA fila con los vinculos activos e inactivos (mismo
-- criterio estaActivoDocentePrograma del directorio HU062/HU089).
--   - el programa se resuelve del ejecutor (usp_resolver_programa_coordinador_interno; KPI_001 si no coordina);
--   - MEJORAS-SERGIO-2026-11-18 (migracion 56): ya no se agrupa por tipo de vinculacion (retirado); sin vinculos => 0 y 0.
-- Solo lectura: sin XACT_ABORT.
-- ============================================================================
-- SKILLS-BD lote 10 (2026-11-26): TRY/CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_docentes_programa]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
,
    @idPrograma UNIQUEIDENTIFIER = NULL)
AS

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.

BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
        EXEC dbo.usp_resolver_programa_coordinador_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @validarUmbrales = 0,
            @idPrograma = @idPrograma OUTPUT, @idProgramaSolicitado = @idPrograma;

        -- PASO 2: Consulta y retorno de resultados (una sola fila)
        SELECT
            totalActivos   = COUNT(CASE WHEN d.estaActivoDocentePrograma = 1 THEN 1 END),
            totalInactivos = COUNT(CASE WHEN d.estaActivoDocentePrograma = 0 THEN 1 END)
        FROM dbo.uv_docente_programa d
        WHERE d.idPrograma = @idPrograma;
    END TRY
    BEGIN CATCH
        -- PASO 3: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
