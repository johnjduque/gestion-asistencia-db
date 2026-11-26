USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_grupos_pendientes_evaluacion_alertas (CULM-001 C.1; CONTRACT §2.5.2, SUPUESTO-C-03, O-8)
--
-- Grupos que el job debe evaluar. Sin @idPeriodoAcademico: grupos de periodos no terminados (fecha local) con matriculas
-- activas y alguna sesion vencida con registro cuyo fin supera la marca de agua menos el solape
-- (ALERTA_INASISTENCIA/SOLAPE_MARCA_SEGUNDOS): re-evaluar es idempotente y nunca se salta una sesion. Con @idPeriodoAcademico
-- (lo usa el caso de uso del cierre masivo en el backend): todos los grupos del periodo con matriculas activas.
-- Filas: idGrupo, fechaCorteUtc (NULL si nunca), fechaFinSesionVencidaMasReciente. THROW 51000 si @tamanoLote < 1 (PAG_001).
-- ============================================================================
-- SKILLS-BD lote 10 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, sin ISNULL (IIF equivalentes), lecturas por
-- uv_grupo_registro, uv_periodo_academico_fechas, uv_evaluacion_alerta_grupo, uv_estudiante_grupo_registro y uv_estado_estudiante_grupo
-- (antes, las tablas) y TRY/CATCH de lectura que relanza. Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): job del servidor sin @idUsuarioEjecutor; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_grupos_pendientes_evaluacion_alertas]
(
    @idCorrelacion       UNIQUEIDENTIFIER,
    @tamanoLote          INT = NULL,
    @idPeriodoAcademico  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @lote INT = IIF(@tamanoLote IS NOT NULL, @tamanoLote, TRY_CAST(CAST(dbo.ufn_obtener_parametro('ALERTA_INASISTENCIA', 'LOTE_EVALUACION_AUTOMATICA') AS NVARCHAR(20)) AS INT));
    DECLARE @solapeParametro INT = TRY_CAST(CAST(dbo.ufn_obtener_parametro('ALERTA_INASISTENCIA', 'SOLAPE_MARCA_SEGUNDOS') AS NVARCHAR(20)) AS INT);
    DECLARE @solape INT = IIF(@solapeParametro IS NULL, 120, @solapeParametro);
    DECLARE @zona SYSNAME = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS SYSNAME);
    DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        -- PASO 2: Validar el tamano del lote (PAG_001)
        IF @estadoResultado = 1 AND (@lote IS NULL OR @lote < 1)
        BEGIN
            SELECT @p1 = N'1', @p2 = CONVERT(NVARCHAR(20), @lote);
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END
        -- PASO 3: Rechazo de validacion: se lanza con el detalle tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        IF @idPeriodoAcademico IS NULL
        BEGIN
            -- PASO 4: Sin periodo: grupos de periodos vigentes con sesiones vencidas con registro posteriores al ultimo corte (menos el solape)
            SELECT TOP (@lote)
                idGrupo = g.id,
                fechaCorteUtc = ea.fechaCorteUtc,
                fechaFinSesionVencidaMasReciente = MAX(c.fechaHoraFin)
            FROM dbo.uv_grupo_registro g
            INNER JOIN dbo.uv_periodo_academico_fechas pa ON pa.id = g.idPeriodoAcademico AND pa.fechaFin >= @hoyLocal
            LEFT JOIN dbo.uv_evaluacion_alerta_grupo ea ON ea.idGrupo = g.id
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idGrupo = g.id AND c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
                 AND c.fechaHoraFin > DATEADD(SECOND, -@solape, IIF(ea.fechaCorteUtc IS NULL, CAST('19000101' AS DATETIME2(3)), ea.fechaCorteUtc))
            WHERE EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_registro eg INNER JOIN dbo.uv_estado_estudiante_grupo ee ON ee.id = eg.idEstado AND ee.codigo = @codigoInscrita WHERE eg.idGrupo = g.id)
            GROUP BY g.id, ea.fechaCorteUtc
            ORDER BY CASE WHEN ea.fechaCorteUtc IS NULL THEN 0 ELSE 1 END, ea.fechaCorteUtc ASC, g.id ASC;
        END
        ELSE
        BEGIN
            -- PASO 5: Con periodo: todos sus grupos con matriculas inscritas
            SELECT TOP (@lote)
                idGrupo = g.id,
                fechaCorteUtc = ea.fechaCorteUtc,
                fechaFinSesionVencidaMasReciente = CAST(NULL AS DATETIME2(7))
            FROM dbo.uv_grupo_registro g
            LEFT JOIN dbo.uv_evaluacion_alerta_grupo ea ON ea.idGrupo = g.id
            WHERE g.idPeriodoAcademico = @idPeriodoAcademico
              AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_registro eg INNER JOIN dbo.uv_estado_estudiante_grupo ee ON ee.id = eg.idEstado AND ee.codigo = @codigoInscrita WHERE eg.idGrupo = g.id)
            ORDER BY g.id ASC;
        END
    END TRY
    BEGIN CATCH
        -- PASO 6: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
