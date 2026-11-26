USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_tomas_sesion (PC puntos de control; docs/work-items/PC-puntos-control-tomas/CONTRACT.md §B;
-- GET /api/v1/sesiones/{sesionId}/tomas/resumen)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 con el mensaje tecnico si la validacion falla).
-- Validacion compartida usp_validar_docente_titular_sesion_interno: correlacion, ejecutor y sesion obligatorios (GEN_002),
-- RBAC DOCENTE (SEC_001) y titularidad sobre la sesion (SEC_002).
-- Filas: una por matricula activa (MATRICULA/ESTADO_INSCRITA) del grupo de la sesion, ordenadas por nombre, con los minutos de
-- la sesion por tramos entre puntos de control (uv_asistencia_sesion_horas). Sin cabecera Asistencia: minutosSinRegistro =
-- minutosSesion, los demas en 0 y estado NO_DISPONIBLE.
-- Columnas: idEstudiante, nombreCompletoEstudiante, minutosSesion, minutosAsistidos, minutosFalta, minutosExcusa,
-- minutosSinRegistro, codigoEstadoSesionEstudiante, tomasAusentes.
-- ============================================================================
-- SKILLS-BD lote 10 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, sin ISNULL (IIF equivalentes), sesion por
-- uv_sesion (antes, la tabla) y TRY/CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_tomas_sesion]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER
)
AS
    DECLARE @idSesionDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoActiva     NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000);
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000);
    DECLARE @estadoResultado BIT;
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Validar correlacion, ejecutor y docente titular de la sesion
        EXEC dbo.usp_validar_docente_titular_sesion_interno
            @idSesion = @idSesion, @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        -- PASO 2: Rechazo de validacion: se lanza con el detalle tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 3: Resumen por estudiante inscrito de los minutos de la sesion
        SELECT
            idEstudiante                 = eg.idEstudiante,
            nombreCompletoEstudiante     = eg.nombreCompletoEstudiante,
            minutosSesion                = ms.minutosSesion,
            minutosAsistidos             = IIF(h.minutosAsistidos IS NULL, 0, h.minutosAsistidos),
            minutosFalta                 = IIF(h.minutosFalta IS NULL, 0, h.minutosFalta),
            minutosExcusa                = IIF(h.minutosExcusa IS NULL, 0, h.minutosExcusa),
            minutosSinRegistro           = IIF(h.minutosSinRegistro IS NULL, ms.minutosSesion, h.minutosSinRegistro),
            codigoEstadoSesionEstudiante = IIF(h.codigoEstadoSesionEstudiante IS NULL, CAST(N'NO_DISPONIBLE' AS NVARCHAR(20)), h.codigoEstadoSesionEstudiante),
            tomasAusentes                = IIF(h.tomasAusentes IS NULL, 0, h.tomasAusentes)
        FROM dbo.uv_sesion s
        CROSS APPLY (SELECT minutosSesion = IIF(s.fechaHoraFin > s.fechaHoraInicio, DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin), 0)) ms
        INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = s.idGrupo AND eg.codigoEstadoEstudiante = @codigoActiva
        LEFT JOIN dbo.uv_asistencia_sesion_horas h ON h.idSesion = s.id AND h.idEstudianteGrupo = eg.id
        WHERE s.id = @idSesionDefecto
        ORDER BY eg.nombreCompletoEstudiante ASC, eg.idEstudiante ASC;
    END TRY
    BEGIN CATCH
        -- PASO 4: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
