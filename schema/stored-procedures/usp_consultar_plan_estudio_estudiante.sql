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
