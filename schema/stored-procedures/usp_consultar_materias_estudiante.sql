USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_materias_estudiante (CULM-001 A.2-11; F-EST-S01, F-EST-020; CONTRACT §8.2.3 A2-DB-1)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Materias del estudiante de GET /api/v1/estudiante/materias. El estudiante sale del ejecutor (Estudiante.usuario); sin
-- estudiante, 0 filas. Solo cuenta la matricula con el codigo del parametro MATRICULA/ESTADO_INSCRITA: las matriculas
-- retiradas, canceladas o finalizadas (I, CI, CVP, F) no aparecen. Columnas de MateriaEstudianteQueryRow
-- (idAsignatura, nombreAsignatura, idGrupo, nombreGrupo), orden nombreAsignatura, nombreGrupo. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_materias_estudiante]
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
    SET XACT_ABORT ON;

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

    -- PASO 3: materias con matricula inscrita del estudiante del ejecutor (CIERRE-W2B: la lee de uv_materia_estudiante, la misma
    -- fuente de usp_consultar_resumen_materias_estudiante)
    SELECT DISTINCT
        idAsignatura     = m.idAsignatura,
        nombreAsignatura = m.nombreAsignatura,
        idGrupo          = m.idGrupo,
        nombreGrupo      = m.nombreGrupo,
        -- CULM-001 D.9-a (F-EST-006): creditos de la asignatura (quinta columna).
        creditos         = m.creditos
    FROM dbo.uv_materia_estudiante m
    WHERE m.idUsuario = @idUsuarioEjecutor
      AND m.codigoEstadoEstudiante = @codigoInscrita
    ORDER BY m.nombreAsignatura ASC, m.nombreGrupo ASC;
END;
GO
