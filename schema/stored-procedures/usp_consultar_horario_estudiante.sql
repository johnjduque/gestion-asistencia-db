USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_horario_estudiante (CULM-001 A.2-11; F-EST-S01, F-EST-020; CONTRACT §8.2.3 A2-DB-1)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Horario del estudiante de GET /api/v1/estudiante/horario. El estudiante sale del ejecutor (Estudiante.usuario); sin
-- estudiante, 0 filas. Lee uv_horario_estudiante (que no filtra por estado de matricula, linea 24) y aplica aqui el
-- filtro: solo los grupos con matricula en el codigo de MATRICULA/ESTADO_INSCRITA. La vista no cambia.
-- Columnas de uv_horario_estudiante que lee HorarioEstudianteJpaRepository; orden dia, horaInicio, nombreMateria.
-- Horas academicas LOCALES. Solo lectura.
-- ============================================================================
-- SKILLS-BD lote 13 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, lecturas por vistas uv_* (estudiante por uv_estudiante_identidad) y
-- TRY/CATCH de lectura que relanza (READ_QUERY_RESULTSET). Mismas columnas y mismas filas.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_horario_estudiante]
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

    BEGIN TRY
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

        -- Rechazo de validacion: se propaga al llamador
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 3: horario de los grupos con matricula inscrita del estudiante del ejecutor
        SELECT
            h.id,
            h.idEstudiante,
            h.idGrupo,
            h.codigoMateria,
            h.nombreMateria,
            h.grupo,
            h.dia,
            h.horaInicio,
            h.horaFin,
            h.docente
        FROM dbo.uv_horario_estudiante h
        INNER JOIN dbo.uv_estudiante_identidad e ON e.id = h.idEstudiante
        WHERE e.idUsuario = @idUsuarioEjecutor
          AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo eg
                      WHERE eg.idEstudiante = h.idEstudiante AND eg.idGrupo = h.idGrupo
                        AND eg.codigoEstadoEstudiante = @codigoInscrita)
        ORDER BY h.dia ASC, h.horaInicio ASC, h.nombreMateria ASC;
    END TRY
    BEGIN CATCH
        -- PASO 4: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
