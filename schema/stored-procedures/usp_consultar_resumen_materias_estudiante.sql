USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_materias_estudiante (CIERRE-W2B; GET /api/v1/estudiante/materias/resumen)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001). RBAC
-- ESTUDIANTE; el estudiante sale del ejecutor y solo se cuentan sus propias matriculas. Una sola fila con los indicadores del
-- tablero, calculados en la base con el MISMO conjunto de materias que usp_consultar_materias_estudiante (ambos leen
-- uv_materia_estudiante y exigen MATRICULA/ESTADO_INSCRITA), por lo que el tablero y el listado no pueden discrepar:
--   totalMaterias    materias del listado (una por asignatura y grupo con matricula inscrita)
--   materiasEnRiesgo materias con codigoPermanencia RIESGO o PERDIDA en uv_resumen_asistencia_estudiante_grupo (regla
--                    ufn_clasificar_permanencia y umbrales ASISTENCIA/UMBRAL_ALERTA_ADVERTENCIA y _PERDIDA del catalogo de
--                    parametros: los mismos de las alertas). NULL si hay materias pero ningun umbral esta configurado
--                    (sin dato: nunca se inventa un cero); 0 si no hay materias
--   totalHorasFalta  suma de horasFalta (horas de falta sin justa causa) de esas materias, cada una redondeada a 2 decimales
--                    como la muestra el listado (el total coincide con la suma de lo que ve el estudiante); 0 sin materias
--   totalCreditos    suma de los creditos de esas materias (una vez por materia del listado); 0 sin materias
-- Solo lectura.
-- ============================================================================
-- SKILLS-BD lote 10 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END y TRY/CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_materias_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita       NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        -- PASO 2: Validar parametros obligatorios (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        -- PASO 3: Validar perfil del ejecutor
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ESTUDIANTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
        -- PASO 4: Rechazo de validacion: se lanza con el detalle tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 5: Totales de las materias inscritas del estudiante (ISNULL sobre agregacion (permitido): SUM sin filas es NULL)
        SELECT
            totalMaterias    = COUNT(1),
            materiasEnRiesgo = CASE WHEN COUNT(1) > 0 AND COUNT(r.codigoPermanencia) = 0 THEN NULL
                                    ELSE ISNULL(SUM(IIF(r.codigoPermanencia IN (N'RIESGO', N'PERDIDA'), 1, 0)), 0) END,
            totalHorasFalta  = CAST(ISNULL(SUM(ROUND(r.horasFalta, 2)), 0) AS DECIMAL(12, 2)),
            totalCreditos    = CAST(ISNULL(SUM(m.creditos), 0) AS INT)
        FROM (
            -- una fila por materia del listado (asignatura y grupo), igual que el DISTINCT de usp_consultar_materias_estudiante
            SELECT DISTINCT x.idEstudianteGrupo, x.idAsignatura, x.idGrupo, x.creditos
            FROM dbo.uv_materia_estudiante x
            WHERE x.idUsuario = @idUsuarioDefecto
              AND x.codigoEstadoEstudiante = @codigoInscrita
        ) m
        LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo r ON r.idEstudianteGrupo = m.idEstudianteGrupo;
    END TRY
    BEGIN CATCH
        -- PASO 6: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
