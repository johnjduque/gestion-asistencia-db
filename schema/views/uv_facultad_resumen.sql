USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Facultad con sus totales para el listado del administrador. Los totales se calculan aqui y no en el cliente:
--   * totalProgramas: programas de la facultad.
--   * totalEstudiantes: estudiantes distintos con matricula inscrita en el periodo mas reciente con grupos habilitados de
--     la institucion (misma regla que usp_consultar_comparativa_facultades, sin calcular asistencia).
-- Vista aparte de uv_facultad porque uv_programa depende de uv_facultad (referencia circular).
CREATE OR ALTER VIEW [dbo].[uv_facultad_resumen]
AS
SELECT		f.id,
			f.nombreFacultad,
			f.idInstitucion,
			f.nombreInstitucion,
			f.idDecano,
			f.nombreCompletoDecano,
			f.estaActivaFacultad,
			f.estaActivaTextoFacultad,
			totalProgramas = (SELECT COUNT(*) FROM uv_programa p WHERE p.idFacultad = f.id),
			totalEstudiantes = (SELECT COUNT(DISTINCT egp.idEstudiante)
			                    FROM uv_estudiante_grupo_programa egp
			                    INNER JOIN uv_grupo_programa gp ON gp.idGrupo = egp.idGrupo AND gp.idPrograma = egp.idPrograma
			                    INNER JOIN uv_programa p ON p.id = egp.idPrograma
			                    WHERE p.idFacultad = f.id
			                      AND egp.codigoEstadoEstudiante = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10))
			                      AND gp.idPeriodoAcademico = (SELECT TOP 1 gp2.idPeriodoAcademico
			                                                   FROM uv_grupo_programa gp2
			                                                   INNER JOIN uv_programa p2 ON p2.id = gp2.idPrograma
			                                                   INNER JOIN uv_periodo_academico pa ON pa.id = gp2.idPeriodoAcademico
			                                                   WHERE p2.idInstitucion = f.idInstitucion AND gp2.grupoEstaHablitado = 1
			                                                   ORDER BY pa.fechaInicio DESC, pa.id ASC))
FROM		uv_facultad f
GO
