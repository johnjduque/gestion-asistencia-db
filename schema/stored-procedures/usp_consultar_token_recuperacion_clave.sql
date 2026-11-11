USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_token_recuperacion_clave (HU177)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (0..1 fila: idUsuario). No consume el enlace.
-- Devuelve el usuario dueno de un enlace que todavia sirve (sin usar, sin revocar, sin vencer y de un usuario activo).
-- Para cualquier otro enlace devuelve 0 filas: el llamador no distingue inexistente, vencido, usado o revocado.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_token_recuperacion_clave]
(
    @tokenHash     VARBINARY(32),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT idUsuario = r.usuario
    FROM dbo.TokenRecuperacionClave r
    WHERE r.tokenHash = @tokenHash
      AND r.fechaUsoUtc IS NULL
      AND r.fechaRevocacionUtc IS NULL
      AND r.fechaExpiracionUtc > SYSUTCDATETIME()
      AND EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = r.usuario AND u.estado = 1);
END;
GO
