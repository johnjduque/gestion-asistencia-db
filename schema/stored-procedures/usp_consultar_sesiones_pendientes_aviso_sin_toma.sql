USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_pendientes_aviso_sin_toma (NOTOMA-001)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema (sin usuario, como usp_consultar_sesiones_pendientes_aviso_falta). Resultset:
-- idSesion, idGrupo, fechaHoraFinUtc de las sesiones que el job debe avisar a la coordinacion en esta pasada (orden fechaHoraFin, id).
-- Una sesion esta pendiente cuando: no esta cancelada (una solicitud rechazada ya queda cancelada), tiene procedencia temporal confirmada,
-- no tiene una solicitud en espera de aprobacion, NO tiene ninguna toma (todo registro de asistencia cuelga de una toma), su ventana de registro ya cerro
-- (ventanaCierreUtc <= ahora), no cerro hace mas de AVISO_SESION_SIN_TOMA/HORAS_MAXIMAS_ATRASO horas (evita correos masivos al desplegar o
-- recargar datos) y no tiene fila en AvisoSesionSinToma.
-- Lote: @tamanoLote o, si es NULL, AVISO_SESION_SIN_TOMA/LOTE. Con AVISO_SESION_SIN_TOMA/HABILITADO = false devuelve 0 filas.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_pendientes_aviso_sin_toma]
(
    @idCorrelacion UNIQUEIDENTIFIER,
    @tamanoLote    INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @habilitado NVARCHAR(20) = LOWER(TRIM(CAST(dbo.ufn_obtener_parametro('AVISO_SESION_SIN_TOMA', 'HABILITADO') AS NVARCHAR(20))));
    DECLARE @lote INT = ISNULL(@tamanoLote, dbo.ufn_obtener_parametro_int(NULL, 'AVISO_SESION_SIN_TOMA', 'LOTE'));
    DECLARE @horasAtraso INT = dbo.ufn_obtener_parametro_int(NULL, 'AVISO_SESION_SIN_TOMA', 'HORAS_MAXIMAS_ATRASO');
    DECLARE @margenMinutos INT = ISNULL(dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS'), 0);
    DECLARE @ahora DATETIME2(7) = SYSUTCDATETIME();

    IF @habilitado IS NULL OR @habilitado <> N'true' OR @lote IS NULL OR @lote < 1 OR @horasAtraso IS NULL OR @horasAtraso < 0
        SET @lote = 0;

    SELECT TOP (@lote)
        idSesion        = se.idSesion,
        idGrupo         = se.idGrupo,
        fechaHoraFinUtc = se.fechaHoraFin
    FROM dbo.uv_sesion_estado se
    WHERE se.estaCancelada = 0
      AND se.procedenciaTemporal IS NOT NULL
      AND ISNULL(se.pendienteAprobacion, 0) = 0
      AND se.totalTomas = 0
      -- Prefiltro por la fecha de fin (sargable): ventanaCierreUtc = fin + margen, asi que fin <= ahora y fin >= ahora - atraso - margen
      AND se.fechaHoraFin <= @ahora
      AND se.fechaHoraFin >= DATEADD(MINUTE, -(@horasAtraso * 60 + IIF(@margenMinutos < 0, 0, @margenMinutos)), @ahora)
      AND se.ventanaCierreUtc <= @ahora
      AND se.ventanaCierreUtc >= DATEADD(HOUR, -@horasAtraso, @ahora)
      AND NOT EXISTS (SELECT 1 FROM dbo.AvisoSesionSinToma a WHERE a.sesion = se.idSesion)
    ORDER BY se.fechaHoraFin ASC, se.idSesion ASC;
END;
GO
