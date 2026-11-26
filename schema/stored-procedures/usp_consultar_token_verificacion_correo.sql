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
-- SKILLS-BD lote 12 (2026-11-26): PASO n, usuario por uv_usuario (antes, la tabla; el token sigue en la tabla, excepcion E7) y
-- TRY/CATCH de lectura que relanza. Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): notificaciones y correo: lo invoca el backend sin usuario con perfil; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_token_verificacion_correo]
(
    @tokenHash     VARBINARY(32),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Dueno del token vigente (0..1 fila)
        -- El token se busca por su hash en la tabla (excepcion E7: ninguna vista expone tokenHash); el usuario, por vista
        SELECT TOP (1) t.usuario AS idUsuario
        FROM dbo.TokenVerificacionCorreo t
        INNER JOIN dbo.uv_usuario u ON u.id = t.usuario
        WHERE t.tokenHash = @tokenHash
          AND t.fechaUsoUtc IS NULL
          AND t.fechaRevocacionUtc IS NULL
          AND SYSUTCDATETIME() < t.fechaExpiracionUtc
          AND u.estaActivoUsuario = 1
          AND u.correoConfirmado = 0;
    END TRY
    BEGIN CATCH
        -- PASO 2: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
