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
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_grupos_pendientes_evaluacion_alertas]
(
    @idCorrelacion       UNIQUEIDENTIFIER,
    @tamanoLote          INT = NULL,
    @idPeriodoAcademico  UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @lote INT = ISNULL(@tamanoLote, TRY_CAST(CAST(dbo.ufn_obtener_parametro('ALERTA_INASISTENCIA', 'LOTE_EVALUACION_AUTOMATICA') AS NVARCHAR(20)) AS INT));
    DECLARE @solape INT = ISNULL(TRY_CAST(CAST(dbo.ufn_obtener_parametro('ALERTA_INASISTENCIA', 'SOLAPE_MARCA_SEGUNDOS') AS NVARCHAR(20)) AS INT), 120);
    DECLARE @zona SYSNAME = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS SYSNAME);
    DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND (@lote IS NULL OR @lote < 1)
    BEGIN
        SELECT @p1 = N'1', @p2 = CONVERT(NVARCHAR(20), @lote);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    IF @idPeriodoAcademico IS NULL
    BEGIN
        SELECT TOP (@lote)
            idGrupo = g.id,
            fechaCorteUtc = ea.fechaCorteUtc,
            fechaFinSesionVencidaMasReciente = MAX(c.fechaHoraFin)
        FROM dbo.Grupo g
        INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico AND pa.fechaFin >= @hoyLocal
        LEFT JOIN dbo.EvaluacionAlertaGrupo ea ON ea.grupo = g.id
        INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idGrupo = g.id AND c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
             AND c.fechaHoraFin > DATEADD(SECOND, -@solape, ISNULL(ea.fechaCorteUtc, CAST('19000101' AS DATETIME2(3))))
        WHERE EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado AND ee.codigo = @codigoInscrita WHERE eg.grupo = g.id)
        GROUP BY g.id, ea.fechaCorteUtc
        ORDER BY CASE WHEN ea.fechaCorteUtc IS NULL THEN 0 ELSE 1 END, ea.fechaCorteUtc ASC, g.id ASC;
    END
    ELSE
    BEGIN
        SELECT TOP (@lote)
            idGrupo = g.id,
            fechaCorteUtc = ea.fechaCorteUtc,
            fechaFinSesionVencidaMasReciente = CAST(NULL AS DATETIME2(7))
        FROM dbo.Grupo g
        LEFT JOIN dbo.EvaluacionAlertaGrupo ea ON ea.grupo = g.id
        WHERE g.periodoAcademico = @idPeriodoAcademico
          AND EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado AND ee.codigo = @codigoInscrita WHERE eg.grupo = g.id)
        ORDER BY g.id ASC;
    END
END;
GO
