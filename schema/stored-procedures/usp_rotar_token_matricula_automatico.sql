USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B (D2 rotativo): rotacion AUTOMATICA del job del servidor. No tiene parametro de ejecutor: es una excepcion
-- declarada de RBAC humano (CONTRACT §2.1 y A2); solo se concede EXECUTE al rol de runtime del backend.
-- Solo rota si la ventana ya cumplio ROTACION_SEGUNDOS (o @forzar = 1); si no, responde exito sin cambios, de modo que
-- dos instancias del job no rotan doble. Ventana vencida: la marca EXPIRADA y responde MQR_001.
-- Resultset: tupla canonica + idVentana, idDocenteEmisor, fechaRotacionUtc, fechaExpiracionUtc.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): job del servidor sin @idUsuarioEjecutor; exige @idCorrelacion.
-- SKILLS-BD lote 2 (2026-11-25): TRY/CATCH con SYS_001, PASO n y nucleo usp_rotar_token_matricula_interno (antes usp_internal_*).
CREATE OR ALTER PROCEDURE [dbo].[usp_rotar_token_matricula_automatico]
(
    @idGrupo       UNIQUEIDENTIFIER,
    @tokenHash     VARBINARY(32),
    @pin           NCHAR(6),
    @forzar        BIT = 0,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @idVentana          UNIQUEIDENTIFIER = NULL;
    DECLARE @idDocenteEmisor    UNIQUEIDENTIFIER = NULL;
    DECLARE @fechaRotacionUtc   DATETIME2(0)     = NULL;
    DECLARE @fechaExpiracionUtc DATETIME2(0)     = NULL;
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: rotacion automatica (sin ejecutor): solo rota si ya vencio ROTACION_SEGUNDOS o @forzar = 1
        EXEC dbo.usp_rotar_token_matricula_interno
            @idCorrelacion = @idCorrelacionDefecto, @idGrupo = @idGrupo, @tokenHash = @tokenHash, @pin = @pin,
            @forzar = @forzar, @idUsuarioManual = NULL,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idVentana = @idVentana OUTPUT, @idDocenteEmisor = @idDocenteEmisor OUTPUT,
            @fechaRotacionUtc = @fechaRotacionUtc OUTPUT, @fechaExpiracionUtc = @fechaExpiracionUtc OUTPUT;
    END TRY
    BEGIN CATCH
        -- PASO 2: error no controlado. Si la transaccion del llamador quedo condenada (el nucleo relanza en ese caso)
        -- se relanza el error original, como antes del lote 2 (SKILLS-BD lote 16); si no, SYS_001. El nucleo gestiona y
        -- revierte su propia transaccion
        IF XACT_STATE() = -1 AND @@TRANCOUNT > 0
        BEGIN
            THROW;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SELECT @idVentana = NULL, @idDocenteEmisor = NULL, @fechaRotacionUtc = NULL, @fechaExpiracionUtc = NULL;
    END CATCH

    -- PASO 3: resultset unificado (tupla canonica + datos de la ventana)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idVentana               = @idVentana,
        idDocenteEmisor         = @idDocenteEmisor,
        fechaRotacionUtc        = @fechaRotacionUtc,
        fechaExpiracionUtc      = @fechaExpiracionUtc;
END;
GO
