USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitud_recuperacion_clave (HU177)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (0..1 fila: idUsuario, primerNombre, correo).
-- Publico sin ejecutor: lo llama el backend cuando alguien pide el enlace para definir una contrasena nueva.
-- Devuelve la fila solo si el correo corresponde a UN usuario activo y ya paso la espera minima desde el ultimo enlace
-- emitido (RECUPERACION_CLAVE/REENVIO_ESPERA_MINUTOS). En cualquier otro caso devuelve 0 filas y no lanza: el llamador
-- responde siempre lo mismo, exista o no la cuenta, para no revelar quien esta registrado.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitud_recuperacion_clave]
(
    @correo        NVARCHAR(100),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @correoLimpio  NVARCHAR(100) = NULLIF(LTRIM(RTRIM(@correo)), N'');
    DECLARE @esperaMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'RECUPERACION_CLAVE', 'REENVIO_ESPERA_MINUTOS');
    DECLARE @ahoraUtc      DATETIME2(0) = SYSUTCDATETIME();

    SELECT idUsuario    = u.id,
           primerNombre = u.primerNombre,
           correo       = u.correo
    FROM dbo.Usuario u
    WHERE u.correo = @correoLimpio
      AND u.estado = 1
      AND (SELECT COUNT(*) FROM dbo.Usuario d WHERE d.correo = @correoLimpio AND d.estado = 1) = 1
      AND NOT EXISTS (SELECT 1
                      FROM dbo.TokenRecuperacionClave t
                      WHERE t.usuario = u.id
                        AND t.fechaEmisionUtc > DATEADD(MINUTE, -ISNULL(@esperaMinutos, 0), @ahoraUtc));
END;
GO
