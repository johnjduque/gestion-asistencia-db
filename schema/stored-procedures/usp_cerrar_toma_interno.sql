USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cerrar_toma_interno (ATA D9, HU175; ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS I.1) - NUCLEO, no se concede EXECUTE.
-- SKILLS-BD lote 2 (2026-11-25): antes usp_internal_cerrar_toma (renombrado, D3); triplete OUTPUT, TRY/CATCH con SYS_001.
--
-- Cierra UNA toma abierta que el llamador ya tiene bloqueada (Sesion -> TomaAsistencia): cierra el token QR activo; con
-- @marcarAusentes = 1 (NULL => ModoTomaAsistencia.marcaAusentesAlCerrar) y la ventana con margen de la sesion todavia abierta, marca
-- SJC a las matriculas activas sin detalle (usp_marcar_ausentes_toma_interno); pone estado CERRADA, fechaCierreUtc (nunca antes de la
-- apertura), idCorrelacionCierre y totalAusentesMarcados. Devuelve por OUTPUT el total marcado y la fecha de cierre guardada.
-- No abre transaccion ni valida titularidad ni si ya estaba cerrada: lo hace el llamador (usp_cerrar_toma_asistencia,
-- usp_abrir_toma_asistencia). Un error (incluido un catalogo sin estado CERRADA) devuelve @estadoResultado = 0 con SYS_001 y el
-- llamador lo relanza a su CATCH; si condeno la transaccion del llamador, el CATCH relanza el error original.
-- La lectura de la toma va a la tabla con UPDLOCK/HOLDLOCK: la fila ya la bloqueo el llamador.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cerrar_toma_interno]
(
    @idToma                  UNIQUEIDENTIFIER,
    @idSesion                UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @marcarAusentes          BIT,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @totalAusentesMarcados   INT OUTPUT,
    @fechaCierreUtc          DATETIME2(0) OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstadoCerrada      UNIQUEIDENTIFIER;
    DECLARE @marcaPorModo         BIT;
    DECLARE @marcar               BIT;
    DECLARE @ventanaAbierta       BIT;
    DECLARE @fechaCierre          DATETIME2(0);
    DECLARE @mensajeErrorInterno  NVARCHAR(2048);
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: respuesta inicial
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;
    SET @totalAusentesMarcados = 0;

    BEGIN TRY
        -- PASO 2: estado CERRADA, modo de la toma, ventana de la sesion y hora de cierre
        SELECT @idEstadoCerrada = e.id FROM dbo.uv_estado_toma_asistencia e WHERE e.estaAbierta = 0;
        SELECT @marcaPorModo = m.marcaAusentesAlCerrar
        FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.uv_modo_toma_asistencia m ON m.id = t.modo
        WHERE t.id = @idToma;
        SET @marcar = IIF(@marcarAusentes IS NULL, @marcaPorModo, @marcarAusentes);
        SELECT @ventanaAbierta = v.ventanaAbierta FROM dbo.uv_sesion_estado v WHERE v.idSesion = @idSesion;
        SET @fechaCierre = SYSUTCDATETIME();

        IF @idEstadoCerrada IS NULL
        BEGIN
            THROW 52511, 'CULM001_B2_CATALOGO_INCONSISTENTE: falta EstadoTomaAsistencia(estaAbierta = 0).', 1;
        END

        -- PASO 3: cierre del token QR activo
        UPDATE dbo.TokenAsistenciaToma SET fechaCierreUtc = @fechaCierre
        WHERE toma = @idToma AND fechaCierreUtc IS NULL;

        -- PASO 4: ausentes (SJC) si corresponde y la ventana sigue abierta
        IF @marcar = 1 AND @ventanaAbierta = 1
        BEGIN
            EXEC dbo.usp_marcar_ausentes_toma_interno
                @idToma = @idToma, @idSesion = @idSesion, @idGrupo = @idGrupo,
                @fechaRegistroUtc = @fechaCierre, @idCorrelacion = @idCorrelacionDefecto,
                @totalMarcados = @totalAusentesMarcados OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 0
            BEGIN
                SET @mensajeErrorInterno = LEFT(@mensajeTecnicoResultado, 2048);
                THROW 52521, @mensajeErrorInterno, 1;
            END
        END

        -- PASO 5: cierre de la toma
        UPDATE dbo.TomaAsistencia
        SET estado = @idEstadoCerrada,
            fechaCierreUtc = IIF(@fechaCierre < fechaAperturaUtc, fechaAperturaUtc, @fechaCierre),
            totalAusentesMarcados = @totalAusentesMarcados,
            idCorrelacionCierre = @idCorrelacion
        WHERE id = @idToma;

        SELECT @fechaCierreUtc = t.fechaCierreUtc FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK) WHERE t.id = @idToma;
    END TRY
    BEGIN CATCH
        -- PASO 6: error. Sin transaccion propia: la revierte el llamador
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        -- Transaccion del llamador condenada: se relanza el error original a su CATCH (mismo comportamiento que antes del lote 2)
        IF XACT_STATE() = -1
        BEGIN
            THROW;
        END
    END CATCH
END;
GO
