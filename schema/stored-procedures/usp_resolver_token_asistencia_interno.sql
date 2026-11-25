USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_resolver_token_asistencia_interno (CULM-001 B.2, HU176; CONTRACT §2.8.3, DEC-015) - NUCLEO, no se concede EXECUTE.
-- SKILLS-BD lote 2 (2026-11-25): antes usp_internal_resolver_token_asistencia (renombrado, D3); triplete OUTPUT, TRY/CATCH con SYS_001.
--
-- Resuelve un hash de token o un PIN (exactamente uno; si no @codigoRechazo = AQR_007) contra el token VIGENTE (activo y
-- no expirado) o el ANTERIOR mientras dure ASISTENCIA_QR/TOLERANCIA_SEGUNDOS desde fechaRotacionUtc. Lectura sin UPDLOCK
-- (READ COMMITTED): 40 lecturas concurrentes no se serializan sobre la fila del token. Cualquier token/PIN desconocido,
-- cerrado o expirado devuelve el mismo AQR_001 (no revela si existio). Un rechazo deja @estadoResultado = 1 y el codigo en
-- @codigoRechazo (el llamador arma el mensaje); un error devuelve @estadoResultado = 0 con SYS_001 y, si condeno la
-- transaccion del llamador, el CATCH relanza el error original.
-- Excepcion documentada (docs/arquitectura/excepciones-skills-bd.md, E7): la busqueda por hash y la toma/sesion del token se
-- leen en la tabla. Ninguna vista expone tokenHash (no se publica al rol de runtime) y las vistas de toma y token calculan
-- totales por grupo que harian mas lento el registro QR concurrente.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_token_asistencia_interno]
(
    @tokenHash               VARBINARY(32) = NULL,
    @pin                     NCHAR(6) = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER = NULL,
    @idTokenAsistencia       UNIQUEIDENTIFIER OUTPUT,
    @idToma                  UNIQUEIDENTIFIER OUTPUT,
    @idSesion                UNIQUEIDENTIFIER OUTPUT,
    @idGrupo                 UNIQUEIDENTIFIER OUTPUT,
    @codigoRechazo           VARCHAR(20) OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @toleranciaSegundos   INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'TOLERANCIA_SEGUNDOS');
    DECLARE @ahora                DATETIME2 = SYSUTCDATETIME();
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: respuesta inicial
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;
    SELECT @idTokenAsistencia = NULL, @idToma = NULL, @idSesion = NULL, @idGrupo = NULL, @codigoRechazo = NULL;

    BEGIN TRY
        -- PASO 2: tolerancia (negativa o ausente => 0) y exactamente uno de hash o PIN
        SET @toleranciaSegundos = IIF(@toleranciaSegundos IS NULL OR @toleranciaSegundos < 0, 0, @toleranciaSegundos);

        IF (@tokenHash IS NULL AND @pin IS NULL) OR (@tokenHash IS NOT NULL AND @pin IS NOT NULL)
        BEGIN
            SET @codigoRechazo = 'AQR_007';
        END

        -- PASO 3: token vigente o anterior dentro de la tolerancia (el vigente primero)
        IF @codigoRechazo IS NULL AND @tokenHash IS NOT NULL
        BEGIN
            SELECT TOP 1 @idTokenAsistencia = tk.id, @idToma = tk.toma
            FROM dbo.TokenAsistenciaToma tk
            WHERE tk.fechaCierreUtc IS NULL
              AND @ahora < tk.fechaExpiracionUtc
              AND (tk.tokenHash = @tokenHash
                   OR (tk.tokenHashAnterior = @tokenHash AND @ahora < DATEADD(SECOND, @toleranciaSegundos, tk.fechaRotacionUtc)))
            ORDER BY IIF(tk.tokenHash = @tokenHash, 0, 1);
        END
        ELSE IF @codigoRechazo IS NULL
        BEGIN
            SELECT TOP 1 @idTokenAsistencia = tk.id, @idToma = tk.toma
            FROM dbo.TokenAsistenciaToma tk
            WHERE tk.fechaCierreUtc IS NULL
              AND @ahora < tk.fechaExpiracionUtc
              AND (tk.pin = @pin
                   OR (tk.pinAnterior = @pin AND @ahora < DATEADD(SECOND, @toleranciaSegundos, tk.fechaRotacionUtc)))
            ORDER BY IIF(tk.pin = @pin, 0, 1);
        END

        IF @codigoRechazo IS NULL AND @idTokenAsistencia IS NULL
        BEGIN
            SET @codigoRechazo = 'AQR_001';
        END

        -- PASO 4: sesion y grupo de la toma
        IF @codigoRechazo IS NULL
        BEGIN
            SELECT @idSesion = t.sesion, @idGrupo = s.grupo
            FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion
            WHERE t.id = @idToma;
        END
    END TRY
    BEGIN CATCH
        -- PASO 5: error. Sin transaccion propia: la revierte el llamador
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SELECT @idTokenAsistencia = NULL, @idToma = NULL, @idSesion = NULL, @idGrupo = NULL, @codigoRechazo = NULL;
        IF XACT_STATE() = -1
        BEGIN
            THROW;
        END
    END CATCH
END;
GO
