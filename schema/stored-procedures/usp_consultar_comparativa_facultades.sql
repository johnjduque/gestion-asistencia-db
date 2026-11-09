USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_comparativa_facultades (HU139). READ_QUERY_RESULTSET sin paginar. Solo lectura.
-- Una fila por facultad de la institucion (activas e inactivas, D4). Mismas definiciones que usp_consultar_kpis_institucion.
-- Orden: ausentismo descendente (NULL al final), luego nombre.
-- CULM-001 D.8 (CONTRACT D 9.2, DEC-012/DEC-024, HU139): porcentajeAusentismo por HORAS = ROUND(100 x SUM(horasFalta) / SUM(horasDictadas), 2)
-- (NULL si no hay horas dictadas) sobre las matriculas activas con vinculo en la facultad (cada matricula una sola vez);
-- sesionesEjecutadas y faltasSinJustaCausa siguen en sesiones. Columnas nuevas al final: horasDictadas y horasFalta (horas, 2 decimales).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_comparativa_facultades]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_institucion_administrador_interno)
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idInstitucion = @idInstitucion OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_institucion_interno)
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 3: Consulta y retorno de resultados
    WITH persona AS (
        SELECT  p.idFacultad, r.idEstudiante,
                peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
        FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idInstitucion = @idInstitucion AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = @codigoInscrita
        GROUP BY p.idFacultad, r.idEstudiante
    ),
    conteo AS (
        SELECT  idFacultad,
                total = COUNT(*),
                regulares = SUM(IIF(peor = 1, 1, 0)),
                riesgo = SUM(IIF(peor = 2, 1, 0)),
                perdida = SUM(IIF(peor = 3, 1, 0))
        FROM    persona
        GROUP BY idFacultad
    ),
    asistencia AS (
        SELECT  p.idFacultad,
                sesiones = SUM(r.sesionesEjecutadas),
                faltas = SUM(r.sesionesConFaltaSinJustaCausa),
                -- CULM-001 D.8: horas dictadas y de falta sin justa causa de las mismas matriculas
                horasDictadas = CAST(SUM(r.horasDictadas) AS DECIMAL(19,6)),
                horasFalta = CAST(SUM(r.horasFalta) AS DECIMAL(19,6))
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN (SELECT DISTINCT p.idFacultad, idEstudianteGrupo = egp.id
                    FROM dbo.uv_estudiante_grupo_programa egp
                    INNER JOIN dbo.uv_programa p ON p.id = egp.idPrograma
                    WHERE p.idInstitucion = @idInstitucion) p ON p.idEstudianteGrupo = r.idEstudianteGrupo
        WHERE   r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = @codigoInscrita
        GROUP BY p.idFacultad
    ),
    programas AS (
        SELECT idFacultad, total = COUNT(*) FROM dbo.uv_programa WHERE idInstitucion = @idInstitucion GROUP BY idFacultad
    ),
    resultado AS (
        SELECT
            idFacultad = f.id,
            nombreFacultad = f.nombreFacultad,
            estaActivaFacultad = CAST(f.estaActivaFacultad AS BIT),
            totalProgramas = ISNULL(pr.total, 0),
            totalEstudiantes = ISNULL(c.total, 0),
            estudiantesRiesgo = ISNULL(c.riesgo, 0),
            estudiantesPerdida = ISNULL(c.perdida, 0),
            tasaRetencion = CAST(IIF(ISNULL(c.total, 0) = 0, NULL, 100.0 * (c.regulares + c.riesgo) / c.total) AS DECIMAL(5,2)),
            sesionesEjecutadas = ISNULL(a.sesiones, 0),
            faltasSinJustaCausa = ISNULL(a.faltas, 0),
            porcentajeAusentismo = CAST(IIF(ISNULL(a.horasDictadas, 0) = 0, NULL, ROUND(100.0 * a.horasFalta / a.horasDictadas, 2)) AS DECIMAL(5,2)),
            horasDictadas = CAST(ISNULL(a.horasDictadas, 0) AS DECIMAL(12,2)),
            horasFalta = CAST(ISNULL(a.horasFalta, 0) AS DECIMAL(12,2))
        FROM dbo.uv_facultad f
        LEFT JOIN programas pr ON pr.idFacultad = f.id
        LEFT JOIN conteo c ON c.idFacultad = f.id
        LEFT JOIN asistencia a ON a.idFacultad = f.id
        WHERE f.idInstitucion = @idInstitucion
    )
    -- PASO 4: Consulta y retorno de resultados
    SELECT idFacultad, nombreFacultad, estaActivaFacultad, totalProgramas, totalEstudiantes, estudiantesRiesgo, estudiantesPerdida,
           tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, horasDictadas, horasFalta
    FROM resultado
    ORDER BY IIF(porcentajeAusentismo IS NULL, 1, 0) ASC, porcentajeAusentismo DESC, nombreFacultad ASC, idFacultad ASC;
END;
GO
