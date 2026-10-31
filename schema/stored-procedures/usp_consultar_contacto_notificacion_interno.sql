USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_contacto_notificacion_interno]
-- Capacidad: Resolucion de Contacto para Notificaciones (NOTIF-002A)
-- Ambito: Consulta interna atomica por lote acotado (<=100 UUID) sobre Usuario
--         habilitado (estado = 1). Excepcion a paginacion documentada en CONTRACT §2.3.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_contacto_notificacion_interno]
(
    @usuariosJson NVARCHAR(MAX)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ;WITH Solicitados AS (
        SELECT DISTINCT
            idUsuario = TRY_CONVERT(UNIQUEIDENTIFIER, j.[value])
        FROM OPENJSON(@usuariosJson) j
        WHERE TRY_CONVERT(UNIQUEIDENTIFIER, j.[value]) IS NOT NULL
    )
    SELECT
        idUsuario        = u.id,
        correo           = u.correo,
        correoConfirmado = u.correoConfirmado
    FROM dbo.Usuario u
    INNER JOIN Solicitados s ON s.idUsuario = u.id
    WHERE u.estado = 1
    ORDER BY u.id ASC;
END;
GO
