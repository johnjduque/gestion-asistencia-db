USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- IDENT-001: consulta de solo lectura del token de verificacion (no lo consume). Devuelve 0..1 fila con el usuario
-- dueno del token vigente (no usado, no revocado, no vencido, usuario activo y correo aun sin verificar). Para cualquier
-- token invalido devuelve 0 filas: el llamador no puede distinguir inexistente, vencido, usado o revocado.
-- READ_QUERY_RESULTSET: NON_GOLDEN_PATH_EXTENSION (ver test/test_contract_closure.sql).
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_token_verificacion_correo]
(
    @tokenHash     VARBINARY(32),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1) t.usuario AS idUsuario
    FROM dbo.TokenVerificacionCorreo t
    INNER JOIN dbo.Usuario u ON u.id = t.usuario
    WHERE t.tokenHash = @tokenHash
      AND t.fechaUsoUtc IS NULL
      AND t.fechaRevocacionUtc IS NULL
      AND SYSUTCDATETIME() < t.fechaExpiracionUtc
      AND u.estado = 1
      AND u.correoConfirmado = 0;
END;
GO
