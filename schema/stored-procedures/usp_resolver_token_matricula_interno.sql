USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B (D2 rotativo): resuelve la ventana ACTIVA a la que pertenece un token o un PIN y decide si es utilizable.
-- SKILLS-BD lote 2 (2026-11-25): antes usp_internal_resolver_token_matricula (renombrado, D3); DECLARE en la cabecera, PASO n,
-- triplete OUTPUT y TRY/CATCH con SYS_001 (si condeno la transaccion del llamador, relanza el error original).
-- Interno: lo invocan usp_validar_token_matricula_publico y usp_matricular_por_token_interno dentro de su transaccion.
--   * Exactamente uno de @tokenHash / @pin (si no: MQR_007).
--   * Coincide con el token/PIN VIGENTE  -> valido mientras la ventana no llegue a fechaExpiracionUtc.
--   * Coincide con el token/PIN ANTERIOR -> valido solo durante MATRICULA_QR/TOLERANCIA_SEGUNDOS desde la rotacion.
--   * Una ventana ACTIVA que ya llego a su fin se marca EXPIRADA de forma perezosa (escritura persistida por el llamador).
-- Cualquier otro caso devuelve el mismo codigo MQR_001 (anti-enumeracion: no distingue inexistente, cerrado o vencido).
-- Un rechazo deja @estadoResultado = 1 y el codigo en @codigoRechazo (el llamador arma el mensaje).
-- Toma UPDLOCK/HOLDLOCK sobre la fila para serializar matriculas y rotaciones concurrentes (excepcion de lecturas con bloqueo).
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_token_matricula_interno]
(
    @tokenHash               VARBINARY(32),
    @pin                     NCHAR(6),
    @idCorrelacion           UNIQUEIDENTIFIER = NULL,
    @idVentana               UNIQUEIDENTIFIER OUTPUT,
    @idGrupo                 UNIQUEIDENTIFIER OUTPUT,
    @idDocenteEmisor         UNIQUEIDENTIFIER OUTPUT,
    @codigoRechazo           VARCHAR(20) OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @estadoActiva       NVARCHAR(10);
    DECLARE @estadoExpirada     NVARCHAR(10);
    DECLARE @tolerancia         INT;
    DECLARE @ahora              DATETIME2(0);
    DECLARE @fechaExpiracionUtc DATETIME2(0);
    DECLARE @fechaRotacionUtc   DATETIME2(0);
    DECLARE @coincideVigente    BIT = 0;
    DECLARE @idEncontrado       UNIQUEIDENTIFIER;
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: respuesta inicial
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;
    SELECT @idVentana = NULL, @idGrupo = NULL, @idDocenteEmisor = NULL, @codigoRechazo = NULL;

    BEGIN TRY
        -- PASO 2: exactamente uno de hash o PIN (MQR_007)
        IF (@tokenHash IS NULL AND @pin IS NULL) OR (@tokenHash IS NOT NULL AND @pin IS NOT NULL)
        BEGIN
            SET @codigoRechazo = 'MQR_007';
        END

        -- PASO 3: ventana ACTIVA que coincide con el token/PIN vigente o anterior (con bloqueo)
        IF @codigoRechazo IS NULL
        BEGIN
            SET @estadoActiva = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA') AS NVARCHAR(10));
            SET @estadoExpirada = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_EXPIRADA') AS NVARCHAR(10));
            SET @tolerancia = dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'TOLERANCIA_SEGUNDOS');
            SET @ahora = SYSUTCDATETIME();

            SELECT TOP (1)
                @idEncontrado       = t.id,
                @idGrupo            = t.grupo,
                @idDocenteEmisor    = t.docenteEmisor,
                @fechaExpiracionUtc = t.fechaExpiracionUtc,
                @fechaRotacionUtc   = t.fechaRotacionUtc,
                @coincideVigente    = IIF((@tokenHash IS NOT NULL AND t.tokenHash = @tokenHash) OR (@pin IS NOT NULL AND t.pin = @pin), 1, 0)
            FROM dbo.TokenMatriculaGrupo t WITH (UPDLOCK, HOLDLOCK)
            WHERE t.estado = @estadoActiva
              AND (
                    (@tokenHash IS NOT NULL AND (t.tokenHash = @tokenHash OR t.tokenHashAnterior = @tokenHash))
                 OR (@pin IS NOT NULL AND (t.pin = @pin OR t.pinAnterior = @pin))
                  );

            IF @idEncontrado IS NULL
            BEGIN
                SET @codigoRechazo = 'MQR_001';
            END
        END

        -- PASO 4: fin de la ventana: expiracion perezosa
        IF @codigoRechazo IS NULL AND @ahora >= @fechaExpiracionUtc
        BEGIN
            UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoExpirada WHERE id = @idEncontrado;
            SELECT @idGrupo = NULL, @idDocenteEmisor = NULL;
            SET @codigoRechazo = 'MQR_001';
        END

        -- PASO 5: token anterior fuera de la tolerancia
        IF @codigoRechazo IS NULL AND @coincideVigente = 0 AND @ahora >= DATEADD(SECOND, @tolerancia, @fechaRotacionUtc)
        BEGIN
            SELECT @idGrupo = NULL, @idDocenteEmisor = NULL;
            SET @codigoRechazo = 'MQR_001';
        END

        -- PASO 6: ventana utilizable
        IF @codigoRechazo IS NULL
        BEGIN
            SET @idVentana = @idEncontrado;
        END
    END TRY
    BEGIN CATCH
        -- PASO 7: error. Sin transaccion propia: la revierte el llamador
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SELECT @idVentana = NULL, @idGrupo = NULL, @idDocenteEmisor = NULL, @codigoRechazo = NULL;
        IF XACT_STATE() = -1
        BEGIN
            THROW;
        END
    END CATCH
END;
GO
