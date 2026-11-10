USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_horas_programadas_estudiante (HU019)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Carga horaria programada de cada materia del ESTUDIANTE ejecutor, para la barra de horas de "Mis materias"
-- (GET /api/v1/estudiante/materias): horas asistidas y dictadas salen de usp_consultar_resumen_asistencia_estudiante;
-- aqui sale el total programado. El estudiante sale del ejecutor (Estudiante.usuario); sin estudiante, 0 filas.
--   - Una fila por matricula inscrita (parametro MATRICULA/ESTADO_INSCRITA): el mismo universo de
--     usp_consultar_materias_estudiante.
--   - sesionesProgramadas / horasProgramadas: todas las sesiones del grupo que no estan canceladas, ya dictadas o por
--     dictar (uv_cumplimiento_sesion_grupo, que excluye dbo.SesionCancelacion), con ufn_horas_sesion. Las horas dictadas
--     del resumen son un subconjunto de estas (sesiones vencidas con registro), asi que nunca las superan.
--   - Un grupo sin sesiones devuelve 0 y 0.
-- Orden: idGrupo. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_horas_programadas_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 3: sesiones y horas programadas de cada grupo con matricula inscrita del estudiante del ejecutor
    SELECT
        idEstudianteGrupo   = eg.id,
        idGrupo             = eg.idGrupo,
        sesionesProgramadas = ISNULL(pr.sesionesProgramadas, 0),
        horasProgramadas    = CAST(ISNULL(pr.horasProgramadas, 0) AS DECIMAL(12,6))
    FROM dbo.Estudiante e
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idEstudiante = e.id
    LEFT JOIN (
                SELECT  c.idGrupo,
                        sesionesProgramadas = COUNT(*),
                        horasProgramadas = SUM(c.horasSesion)
                FROM    dbo.uv_cumplimiento_sesion_grupo c
                GROUP BY c.idGrupo
              ) pr
        ON pr.idGrupo = eg.idGrupo
    WHERE e.usuario = @idUsuarioEjecutor
      AND eg.codigoEstadoEstudiante = @codigoInscrita
    ORDER BY eg.idGrupo ASC, eg.id ASC;
END;
GO
