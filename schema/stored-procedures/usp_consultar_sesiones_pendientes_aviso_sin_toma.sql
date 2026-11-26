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
-- no tiene una solicitud en espera de aprobacion, el docente titular del grupo tiene el usuario activo, el grupo tiene al menos un estudiante
-- activo (matricula MATRICULA/ESTADO_INSCRITA con usuario activo), NO tiene ninguna toma (todo registro de asistencia cuelga de una toma), su ventana de registro ya cerro
-- (ventanaCierreUtc <= ahora), no cerro hace mas de AVISO_SESION_SIN_TOMA/HORAS_MAXIMAS_ATRASO horas (evita correos masivos al desplegar o
-- recargar datos) y no tiene fila en AvisoSesionSinToma.
-- Los grupos sin estudiantes activos y los de docente inactivo NO se seleccionan y NO se marcan: si el grupo recibe estudiantes o el docente se
-- reactiva dentro de HORAS_MAXIMAS_ATRASO, la sesion se avisa en una pasada posterior (la exclusion no oculta el problema con una marca).
-- Lote: @tamanoLote o, si es NULL, AVISO_SESION_SIN_TOMA/LOTE. Con AVISO_SESION_SIN_TOMA/HABILITADO = false devuelve 0 filas.
-- ============================================================================
-- SKILLS-BD lote 12 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, lecturas por vistas uv_* (antes, las tablas)
-- y TRY/CATCH de lectura que relanza. Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): job del servidor sin @idUsuarioEjecutor; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_pendientes_aviso_sin_toma]
(
    @idCorrelacion UNIQUEIDENTIFIER,
    @tamanoLote    INT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @habilitado NVARCHAR(20) = LOWER(TRIM(CAST(dbo.ufn_obtener_parametro('AVISO_SESION_SIN_TOMA', 'HABILITADO') AS NVARCHAR(20))));
    DECLARE @lote INT = IIF(@tamanoLote IS NULL, dbo.ufn_obtener_parametro_int(NULL, 'AVISO_SESION_SIN_TOMA', 'LOTE'), @tamanoLote);
    DECLARE @horasAtraso INT = dbo.ufn_obtener_parametro_int(NULL, 'AVISO_SESION_SIN_TOMA', 'HORAS_MAXIMAS_ATRASO');
    DECLARE @margenMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @codigoMatriculaActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @ahora DATETIME2(7) = SYSUTCDATETIME();
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Margen (0 por defecto) y lote (0 si el aviso esta deshabilitado o los parametros no son validos)
        SET @margenMinutos = IIF(@margenMinutos IS NULL, 0, @margenMinutos);
        IF @habilitado IS NULL OR @habilitado <> N'true' OR @lote IS NULL OR @lote < 1 OR @horasAtraso IS NULL OR @horasAtraso < 0
        BEGIN
            SET @lote = 0;
        END

        -- PASO 2: Sesiones sin tomas cuya ventana cerro dentro del atraso maximo y sin aviso
        SELECT TOP (@lote)
            idSesion        = se.idSesion,
            idGrupo         = se.idGrupo,
            fechaHoraFinUtc = se.fechaHoraFin
        FROM dbo.uv_sesion_estado se
        WHERE se.estaCancelada = 0
          AND se.procedenciaTemporal IS NOT NULL
          AND (se.pendienteAprobacion IS NULL OR se.pendienteAprobacion = 0)
          AND se.totalTomas = 0
          -- Prefiltro por la fecha de fin (sargable): ventanaCierreUtc = fin + margen, asi que fin <= ahora y fin >= ahora - atraso - margen
          AND se.fechaHoraFin <= @ahora
          AND se.fechaHoraFin >= DATEADD(MINUTE, -(@horasAtraso * 60 + IIF(@margenMinutos < 0, 0, @margenMinutos)), @ahora)
          AND se.ventanaCierreUtc <= @ahora
          AND se.ventanaCierreUtc >= DATEADD(HOUR, -@horasAtraso, @ahora)
          AND NOT EXISTS (SELECT 1 FROM dbo.uv_aviso_sesion_sin_toma a WHERE a.idSesion = se.idSesion)
          AND EXISTS (SELECT 1 FROM dbo.uv_grupo g
                      INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente AND di.estaActivoUsuario = 1
                      WHERE g.id = se.idGrupo)
          AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo eg
                      INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante AND ei.estaActivoUsuario = 1
                      WHERE eg.idGrupo = se.idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva)
        ORDER BY se.fechaHoraFin ASC, se.idSesion ASC;
    END TRY
    BEGIN CATCH
        -- PASO 3: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
