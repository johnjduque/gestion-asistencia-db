USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (R9): resumen por (matricula, programa) para los KPI por programa; las columnas son las de
-- uv_resumen_asistencia_estudiante_grupo (B.2) mas idPrograma, solo para estudiantes con vinculo en ese programa.
CREATE OR ALTER VIEW [dbo].[uv_resumen_asistencia_estudiante_programa_grupo]
AS
SELECT  r.idEstudianteGrupo,
        r.idEstudiante,
        r.idGrupo,
        r.idAsignatura,
        idPrograma = egp.idPrograma,
        r.idPeriodoAcademico,
        r.codigoEstadoEstudiante,
        r.sesionesEjecutadas,
        r.asistencias,
        r.faltasSinJustaCausa,
        r.excusas,
        r.porcentajeInasistencia,
        r.codigoPermanencia,
        r.tomasDictadas,
        r.horasDictadas,
        r.horasAsistidas,
        r.horasFalta,
        r.horasExcusa,
        r.horasSinRegistro,
        r.porcentajeAsistenciaHoras,
        r.porcentajeExcusaHoras,
        r.porcentajeSinRegistroHoras,
        r.porcentajeInasistenciaSesiones,
        r.umbralAdvertencia,
        r.umbralPerdida,
        r.sesionesAsistidas,
        r.sesionesConFaltaSinJustaCausa,
        r.sesionesConExcusa
FROM    uv_resumen_asistencia_estudiante_grupo r
INNER JOIN uv_estudiante_grupo_programa egp ON egp.id = r.idEstudianteGrupo
GO
