USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.8.3, §3.5): tomas cuyo token de asistencia ya debe rotar (uv_token_asistencia_toma.debeRotar = 1).
-- Uso exclusivo del job de rotacion del backend; sin ejecutor (consulta tecnica, sin credenciales). Acotada por
-- ASISTENCIA_QR/LOTE_ROTACION. READ_QUERY_RESULTSET: NON_GOLDEN_PATH_EXTENSION (ver test/test_contract_closure.sql).
-- SKILLS-BD lote 12 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, lecturas por vistas uv_* (antes, las tablas)
-- y TRY/CATCH de lectura que relanza. Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): job del servidor sin @idUsuarioEjecutor; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_tomas_qr_por_rotar]
(
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @lote INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'LOTE_ROTACION');
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Tamano del lote (ASISTENCIA_QR/LOTE_ROTACION, 200 por defecto)
        SET @lote = IIF(@lote IS NULL OR @lote < 1, 200, @lote);

        -- PASO 2: Tomas cuyo token debe rotar
        SELECT TOP (@lote)
            idToma          = v.idToma,
            idGrupo         = v.idGrupo,
            idDocenteEmisor = v.idDocenteEmisor
        FROM dbo.uv_token_asistencia_toma v
        WHERE v.debeRotar = 1
        ORDER BY v.fechaRotacionUtc ASC, v.idToma ASC;
    END TRY
    BEGIN CATCH
        -- PASO 3: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
