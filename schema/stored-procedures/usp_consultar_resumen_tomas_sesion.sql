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
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_tomas_sesion]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idSesionDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoActiva     NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000);
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000);
    DECLARE @estadoResultado BIT;

    EXEC dbo.usp_validar_docente_titular_sesion_interno
        @idSesion = @idSesion, @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT
        idEstudiante                 = eg.idEstudiante,
        nombreCompletoEstudiante     = eg.nombreCompletoEstudiante,
        minutosSesion                = ms.minutosSesion,
        minutosAsistidos             = ISNULL(h.minutosAsistidos, 0),
        minutosFalta                 = ISNULL(h.minutosFalta, 0),
        minutosExcusa                = ISNULL(h.minutosExcusa, 0),
        minutosSinRegistro           = ISNULL(h.minutosSinRegistro, ms.minutosSesion),
        codigoEstadoSesionEstudiante = ISNULL(h.codigoEstadoSesionEstudiante, CAST(N'NO_DISPONIBLE' AS NVARCHAR(20))),
        tomasAusentes                = ISNULL(h.tomasAusentes, 0)
    FROM dbo.Sesion s
    CROSS APPLY (SELECT minutosSesion = IIF(s.fechaHoraFin > s.fechaHoraInicio, DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin), 0)) ms
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = s.grupo AND eg.codigoEstadoEstudiante = @codigoActiva
    LEFT JOIN dbo.uv_asistencia_sesion_horas h ON h.idSesion = s.id AND h.idEstudianteGrupo = eg.id
    WHERE s.id = @idSesionDefecto
    ORDER BY eg.nombreCompletoEstudiante ASC, eg.idEstudiante ASC;
END;
GO
