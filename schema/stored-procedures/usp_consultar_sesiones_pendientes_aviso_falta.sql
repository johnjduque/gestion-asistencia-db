USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_pendientes_aviso_falta (ATA D1, ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C; HU175)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema (sin usuario, como usp_cerrar_tomas_vencidas). Resultset:
-- idSesion, idGrupo, fechaHoraFinUtc de las sesiones que el job debe avisar en esta pasada (orden fechaHoraFin, id).
-- Una sesion esta pendiente cuando: no esta cancelada, tiene procedencia temporal confirmada, tiene al menos una toma y todas estan
-- cerradas, su ventana de registro ya cerro (ventanaCierreUtc <= ahora), no cerro hace mas de AVISO_FALTA_SESION/HORAS_MAXIMAS_ATRASO
-- horas (evita correos masivos al desplegar o recargar datos) y no tiene fila en AvisoFaltaSesion.
-- Lote: @tamanoLote o, si es NULL, AVISO_FALTA_SESION/LOTE. Con AVISO_FALTA_SESION/HABILITADO = false devuelve 0 filas.
-- ============================================================================
-- SKILLS-BD lote 8 (2026-11-26): PASO n, IF con BEGIN/END, sin ISNULL (IIF/IF equivalentes), avisos por uv_aviso_falta_sesion (antes, la tabla) y TRY/CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_pendientes_aviso_falta]
(
    @idCorrelacion UNIQUEIDENTIFIER,
    @tamanoLote    INT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @habilitado NVARCHAR(20) = LOWER(TRIM(CAST(dbo.ufn_obtener_parametro('AVISO_FALTA_SESION', 'HABILITADO') AS NVARCHAR(20))));
    DECLARE @lote INT = IIF(@tamanoLote IS NULL, dbo.ufn_obtener_parametro_int(NULL, 'AVISO_FALTA_SESION', 'LOTE'), @tamanoLote);
    DECLARE @horasAtraso INT = dbo.ufn_obtener_parametro_int(NULL, 'AVISO_FALTA_SESION', 'HORAS_MAXIMAS_ATRASO');
    DECLARE @margenMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @ahora DATETIME2(7) = SYSUTCDATETIME();
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Sin margen configurado se usa 0
        IF @margenMinutos IS NULL
        BEGIN
            SET @margenMinutos = 0;
        END

        -- PASO 2: Deshabilitado o parametros invalidos: lote 0 (sin filas)
        IF @habilitado IS NULL OR @habilitado <> N'true' OR @lote IS NULL OR @lote < 1 OR @horasAtraso IS NULL OR @horasAtraso < 0
        BEGIN
            SET @lote = 0;
        END

        -- PASO 3: Sesiones cerradas, dentro del atraso maximo y aun sin aviso
        SELECT TOP (@lote)
            idSesion        = se.idSesion,
            idGrupo         = se.idGrupo,
            fechaHoraFinUtc = se.fechaHoraFin
        FROM dbo.uv_sesion_estado se
        WHERE se.estaCancelada = 0
          AND se.procedenciaTemporal IS NOT NULL
          AND se.totalTomas >= 1
          AND se.tieneTomaAbierta = 0
          -- Prefiltro por la fecha de fin (sargable): ventanaCierreUtc = fin + margen, asi que fin <= ahora y fin >= ahora - atraso - margen
          AND se.fechaHoraFin <= @ahora
          AND se.fechaHoraFin >= DATEADD(MINUTE, -(@horasAtraso * 60 + IIF(@margenMinutos < 0, 0, @margenMinutos)), @ahora)
          AND se.ventanaCierreUtc <= @ahora
          AND se.ventanaCierreUtc >= DATEADD(HOUR, -@horasAtraso, @ahora)
          AND NOT EXISTS (SELECT 1 FROM dbo.uv_aviso_falta_sesion a WHERE a.sesion = se.idSesion)
        ORDER BY se.fechaHoraFin ASC, se.idSesion ASC;
    END TRY
    BEGIN CATCH
        -- PASO 4: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
