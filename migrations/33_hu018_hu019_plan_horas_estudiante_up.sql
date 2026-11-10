-- ============================================================================
-- MIGRACION UP 30: HU018 / HU019 - plan de estudios por semestres y horas programadas de las materias del estudiante
-- Crea usp_consultar_plan_estudio_estudiante (HU018) y usp_consultar_horas_programadas_estudiante (HU019) y concede EXECUTE al
-- rol runtime. No modifica objetos existentes ni datos. Idempotente. Down: 33_hu018_hu019_plan_horas_estudiante_down.sql.
-- ============================================================================
PRINT 'MIGRACION 30 UP: HU018 / HU019 - plan de estudios y horas programadas del estudiante';
GO
-- ---- schema/stored-procedures/usp_consultar_plan_estudio_estudiante.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_plan_estudio_estudiante (HU018)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Estructura curricular por semestres para el ESTUDIANTE ejecutor (GET /api/v1/estudiante/plan-estudio). El estudiante
-- sale del ejecutor (Estudiante.usuario); sin estudiante o sin programa, 0 filas. Privacidad: solo los planes de los
-- programas en que el propio estudiante esta inscrito (EstudiantePrograma); nunca datos de otro estudiante.
--   - Planes: los ACTIVOS (uv_plan_estudio.estaActivoPlanEstudio = 1: plan y programa activos) de sus programas.
--   - Una fila por semestre del plan y asignatura vinculada (vinculo activo, asignatura activa). Un semestre sin
--     asignaturas devuelve UNA fila con las columnas de la asignatura en NULL, para que la estructura se vea completa.
--   - cursando = 1 si el estudiante tiene matricula inscrita (parametro MATRICULA/ESTADO_INSCRITA) en un grupo de esa
--     asignatura: la misma regla de usp_consultar_materias_estudiante ("Mis materias"). idGrupoCursando y
--     nombreGrupoCursando identifican ese grupo (si hay varios, el de menor codigo).
-- Orden: nombrePrograma, inp, numeroSemestre, orden del caracter, nombre de la asignatura. Sin paginacion (a lo sumo
-- la malla de sus programas). Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_plan_estudio_estudiante]
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
    DECLARE @idEstudiante UNIQUEIDENTIFIER;

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

    -- PASO 3: estudiante del ejecutor (sin estudiante, 0 filas)
    SET @idEstudiante = (SELECT TOP 1 e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioEjecutor);

    -- PASO 4: semestres y asignaturas de los planes activos de sus programas
    SELECT
        idPrograma              = sp.idPrograma,
        nombrePrograma          = sp.nombrePrograma,
        idPlanEstudio           = sp.idPlanEstudio,
        inpPlanEstudio          = sp.inp,
        idSemestrePlanEstudio   = sp.id,
        numeroSemestre          = sp.numeroSemestre,
        idAsignaturaPlanEstudio = v.idAsignaturaPlanEstudio,
        idAsignatura            = v.idAsignatura,
        codigoAsignatura        = v.codigoAsignatura,
        nombreAsignatura        = v.nombreAsignatura,
        creditos                = v.credito,
        codigoComponente        = CAST(v.codigoComponente AS NVARCHAR(3)),
        nombreComponente        = v.nombreComponente,
        codigoCaracter          = CAST(v.codigoCaracter AS NVARCHAR(3)),
        nombreCaracter          = CAST(v.nombreCaracter AS NVARCHAR(50)),
        cursando                = CAST(IIF(cur.idGrupo IS NULL, 0, 1) AS BIT),
        idGrupoCursando         = cur.idGrupo,
        nombreGrupoCursando     = cur.nombreGrupo
    FROM dbo.uv_semestre_plan_estudio sp
    INNER JOIN dbo.uv_plan_estudio pe
        ON pe.id = sp.idPlanEstudio AND pe.estaActivoPlanEstudio = 1
    LEFT JOIN dbo.uv_asignatura_plan_estudio v
        ON v.idSemestrePlanEstudio = sp.id AND v.estaActivoVinculo = 1 AND v.estaActivaAsignatura = 1
    OUTER APPLY (SELECT TOP 1 idGrupo = eg.idGrupo, nombreGrupo = eg.nombreGrupo
                 FROM dbo.uv_estudiante_grupo eg
                 INNER JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
                 WHERE eg.idEstudiante = @idEstudiante
                   AND eg.codigoEstadoEstudiante = @codigoInscrita
                   AND g.idAsignatura = v.idAsignatura
                 ORDER BY eg.codigoGrupo ASC, eg.idGrupo ASC) cur
    WHERE @idEstudiante IS NOT NULL
      AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = @idEstudiante AND ep.programa = sp.idPrograma)
    ORDER BY sp.nombrePrograma ASC, sp.idPrograma ASC, sp.inp ASC, sp.idPlanEstudio ASC, sp.numeroSemestre ASC, sp.id ASC,
             v.ordenCaracter ASC, v.nombreAsignatura ASC, v.idAsignatura ASC;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_horas_programadas_estudiante.sql
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
GO
-- ---- schema/security/rol_asistencias_runtime_hu018_hu019.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU018 / HU019: permisos de las consultas del estudiante (plan de estudios por semestres y horas programadas de sus
-- materias). EXECUTE sobre los dos SP publicos nuevos. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_plan_estudio_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_plan_estudio_estudiante] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_horas_programadas_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_horas_programadas_estudiante] TO [rol_asistencias_runtime];
GO
GO
PRINT 'MIGRACION 30 UP OK';
GO
