USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_establecer_contexto_usuario_ejecutor
--
-- Fija SESSION_CONTEXT(N'idUsuarioEjecutor') para las vistas uv_auth_* (NULL lo limpia). Helper de las consultas
-- paginadas; no devuelve resultset ni triplete. El parametro conserva el nombre @p_idUsuario porque lo usan por nombre
-- 12 SP y las pruebas de RBAC (excepcion E8 de docs/arquitectura/excepciones-skills-bd.md).
-- SKILLS-BD lote 3 (2026-11-25): PASO n y TRY/CATCH (relanza el error al llamador); mismo comportamiento.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_establecer_contexto_usuario_ejecutor]
    @p_idUsuario UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: usuario ejecutor en el contexto de la sesion (modificable: lo cambian las consultas siguientes)
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @p_idUsuario,
            @read_only = 0;
    END TRY
    BEGIN CATCH
        -- PASO 2: sin triplete que devolver; el error se propaga al llamador, que lo traduce a SYS_001
        THROW;
    END CATCH
END;
GO
