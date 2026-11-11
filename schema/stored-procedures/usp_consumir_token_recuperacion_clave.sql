USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consumir_token_recuperacion_clave (HU177)
--
-- Marca como usado el enlace para definir una contrasena nueva. Publico sin ejecutor: la credencial es el SHA-256 del
-- token. La marca es una sola sentencia UPDATE con UPDLOCK: de dos intentos simultaneos solo uno gana. Cualquier enlace
-- que ya no sirve (inexistente, vencido, usado, revocado o de usuario inactivo) responde igual: RCL_002.
-- La contrasena no vive en la base de datos: el backend la cambia en el proveedor de identidad antes de consumir.
-- Resultset canonico de 4 columnas.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consumir_token_recuperacion_clave]
(
    @tokenHash     VARBINARY(32),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoMensaje   VARCHAR(20);
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        UPDATE r
        SET r.fechaUsoUtc = SYSUTCDATETIME()
        FROM dbo.TokenRecuperacionClave r WITH (UPDLOCK, HOLDLOCK)
        WHERE r.tokenHash = @tokenHash
          AND r.fechaUsoUtc IS NULL
          AND r.fechaRevocacionUtc IS NULL
          AND r.fechaExpiracionUtc > SYSUTCDATETIME()
          AND EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = r.usuario AND u.estado = 1);

        SELECT @codigoMensaje = IIF(@@ROWCOUNT = 1, 'RCL_003', 'RCL_002');
        SET @estadoResultado = IIF(@codigoMensaje = 'RCL_003', 1, 0);

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = @codigoMensaje,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
    END TRY
    BEGIN CATCH
        IF XACT_STATE() = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT idCorrelacion           = @idCorrelacionDefecto,
           mensajeUsuarioResultado = @mensajeUsuarioResultado,
           mensajeTecnicoResultado = @mensajeTecnicoResultado,
           estadoResultado         = @estadoResultado;
END;
GO
