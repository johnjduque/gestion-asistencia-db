USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_cerrar_toma (ATA D9, HU175; ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS I.1) - NUCLEO, no se concede EXECUTE.
--
-- Cierra UNA toma abierta que el llamador ya tiene bloqueada (Sesion -> TomaAsistencia): cierra el token QR activo; con
-- @marcarAusentes = 1 (NULL => ModoTomaAsistencia.marcaAusentesAlCerrar) y la ventana con margen de la sesion todavia abierta, marca
-- SJC a las matriculas activas sin detalle (usp_internal_marcar_ausentes_toma); pone estado CERRADA, fechaCierreUtc (nunca antes de la
-- apertura), idCorrelacionCierre y totalAusentesMarcados. Devuelve por OUTPUT el total marcado y la fecha de cierre guardada.
-- No abre transaccion ni valida titularidad ni si ya estaba cerrada: lo hace el llamador (usp_cerrar_toma_asistencia,
-- usp_abrir_toma_asistencia). Un catalogo sin estado CERRADA se reporta con THROW 52511.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_cerrar_toma]
(
    @idToma                UNIQUEIDENTIFIER,
    @idSesion              UNIQUEIDENTIFIER,
    @idGrupo               UNIQUEIDENTIFIER,
    @marcarAusentes        BIT,
    @idCorrelacion         UNIQUEIDENTIFIER,
    @totalAusentesMarcados INT OUTPUT,
    @fechaCierreUtc        DATETIME2(0) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idEstadoCerrada UNIQUEIDENTIFIER = (SELECT e.id FROM dbo.EstadoTomaAsistencia e WHERE e.estaAbierta = 0);
    DECLARE @marcaPorModo    BIT = (SELECT m.marcaAusentesAlCerrar FROM dbo.TomaAsistencia t INNER JOIN dbo.ModoTomaAsistencia m ON m.id = t.modo WHERE t.id = @idToma);
    DECLARE @marcar          BIT = IIF(@marcarAusentes IS NULL, @marcaPorModo, @marcarAusentes);
    DECLARE @ventanaAbierta  BIT = (SELECT v.ventanaAbierta FROM dbo.uv_sesion_estado v WHERE v.idSesion = @idSesion);
    DECLARE @fechaCierre     DATETIME2(0) = SYSUTCDATETIME();
    SET @totalAusentesMarcados = 0;

    IF @idEstadoCerrada IS NULL
        THROW 52511, 'CULM001_B2_CATALOGO_INCONSISTENTE: falta EstadoTomaAsistencia(estaAbierta = 0).', 1;

    UPDATE dbo.TokenAsistenciaToma SET fechaCierreUtc = @fechaCierre
    WHERE toma = @idToma AND fechaCierreUtc IS NULL;

    IF @marcar = 1 AND @ventanaAbierta = 1
        EXEC dbo.usp_internal_marcar_ausentes_toma
            @idToma = @idToma, @idSesion = @idSesion, @idGrupo = @idGrupo,
            @fechaRegistroUtc = @fechaCierre, @totalMarcados = @totalAusentesMarcados OUTPUT;

    UPDATE dbo.TomaAsistencia
    SET estado = @idEstadoCerrada,
        fechaCierreUtc = IIF(@fechaCierre < fechaAperturaUtc, fechaAperturaUtc, @fechaCierre),
        totalAusentesMarcados = @totalAusentesMarcados,
        idCorrelacionCierre = @idCorrelacion
    WHERE id = @idToma;

    SELECT @fechaCierreUtc = t.fechaCierreUtc FROM dbo.TomaAsistencia t WHERE t.id = @idToma;
END;
GO
