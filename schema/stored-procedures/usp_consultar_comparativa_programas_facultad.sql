USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_comparativa_programas_facultad (HU103). READ_QUERY_RESULTSET sin paginar (D6). Solo lectura.
-- Una fila por programa de la facultad (activos e inactivos, D5). Mismas definiciones que usp_consultar_kpis_decano.
-- Orden: ausentismo descendente (NULL al final), luego nombre.
-- CULM-001 D.8 (CONTRACT D 9.2, DEC-012/DEC-024, HU103): porcentajeAusentismo por HORAS = ROUND(100 x SUM(horasFalta) / SUM(horasDictadas), 2)
-- (NULL si no hay horas dictadas) por programa sobre uv_resumen_asistencia_estudiante_programa_grupo; sesionesEjecutadas y
-- faltasSinJustaCausa siguen en sesiones. Columnas nuevas al final: horasDictadas y horasFalta (horas, 2 decimales).
-- ATA D2 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS B): el denominador del porcentaje pasa a horasPeriodo (horas de todas las sesiones del periodo:
-- programadas, vencidas y futuras; sin canceladas ni solicitudes no aprobadas). horasDictadas se sigue mostrando como lo dictado hasta hoy.
-- BD-7 (2026-11-22): columna AL FINAL horasPeriodo = la base real del porcentaje: porcentajeAusentismo = ROUND(100 x horasFalta / horasPeriodo, 2). La
-- etiqueta de la interfaz debe decir 'X h de falta sobre Y h del periodo' con horasPeriodo (no horasDictadas, que es solo lo dictado hasta hoy).
-- ============================================================================
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): DECLARE en la cabecera (uno por variable), PASO n y TRY/CATCH de lectura que relanza (antes, sin TRY).
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_comparativa_programas_facultad]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idFacultad UNIQUEIDENTIFIER;
    DECLARE @idPeriodo UNIQUEIDENTIFIER;
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Resolver ambito del ejecutor (usp_resolver_facultad_decano_interno)
        EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idFacultad = @idFacultad OUTPUT;
        -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_facultad_interno)
        EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @idFacultad, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

        -- PASO 3: indicadores por programa (ISNULL sobre agregacion (permitido): conteos y sumas de los CTE agregados; sin filas valen 0)
        WITH persona AS (
            SELECT  r.idPrograma, r.idEstudiante,
                    peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
            FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
            INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
            WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = @codigoInscrita
            GROUP BY r.idPrograma, r.idEstudiante
        ),
        conteo AS (
            SELECT  idPrograma,
                    total = COUNT(*),
                    regulares = SUM(IIF(peor = 1, 1, 0)),
                    riesgo = SUM(IIF(peor = 2, 1, 0)),
                    perdida = SUM(IIF(peor = 3, 1, 0))
            FROM    persona
            GROUP BY idPrograma
        ),
        asistencia AS (
            SELECT  r.idPrograma,
                    sesiones = SUM(r.sesionesEjecutadas),
                    faltas = SUM(r.sesionesConFaltaSinJustaCausa),
                    -- CULM-001 D.8: horas dictadas y de falta sin justa causa de las mismas matriculas
                    horasDictadas = CAST(SUM(r.horasDictadas) AS DECIMAL(19,6)),
                    horasFalta = CAST(SUM(r.horasFalta) AS DECIMAL(19,6)),
                    horasPeriodo = CAST(SUM(r.horasPeriodo) AS DECIMAL(19,6))
            FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
            INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
            WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = @codigoInscrita
            GROUP BY r.idPrograma
        ),
        resultado AS (
            SELECT
                idPrograma = p.id,
                nombrePrograma = p.nombrePrograma,
                estaActivoPrograma = CAST(p.estaActivoPrograma AS BIT),
                totalEstudiantes = ISNULL(c.total, 0),
                estudiantesRiesgo = ISNULL(c.riesgo, 0),
                estudiantesPerdida = ISNULL(c.perdida, 0),
                tasaRetencion = CAST(IIF(ISNULL(c.total, 0) = 0, NULL, 100.0 * (c.regulares + c.riesgo) / c.total) AS DECIMAL(5,2)),
                sesionesEjecutadas = ISNULL(a.sesiones, 0),
                faltasSinJustaCausa = ISNULL(a.faltas, 0),
                porcentajeAusentismo = CAST(IIF(ISNULL(a.horasPeriodo, 0) = 0, NULL, ROUND(100.0 * a.horasFalta / a.horasPeriodo, 2)) AS DECIMAL(5,2)),
                horasDictadas = CAST(ISNULL(a.horasDictadas, 0) AS DECIMAL(12,2)),
                horasFalta = CAST(ISNULL(a.horasFalta, 0) AS DECIMAL(12,2)),
                horasPeriodo = CAST(ISNULL(a.horasPeriodo, 0) AS DECIMAL(12,2))
            FROM dbo.uv_programa p
            LEFT JOIN conteo c ON c.idPrograma = p.id
            LEFT JOIN asistencia a ON a.idPrograma = p.id
            WHERE p.idFacultad = @idFacultad
        )
        -- PASO 4: retorno ordenado por ausentismo
        SELECT idPrograma, nombrePrograma, estaActivoPrograma, totalEstudiantes, estudiantesRiesgo, estudiantesPerdida,
               tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, horasDictadas, horasFalta, horasPeriodo
        FROM resultado
        ORDER BY IIF(porcentajeAusentismo IS NULL, 1, 0) ASC, porcentajeAusentismo DESC, nombrePrograma ASC, idPrograma ASC;
    END TRY
    BEGIN CATCH
        -- PASO 5: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
