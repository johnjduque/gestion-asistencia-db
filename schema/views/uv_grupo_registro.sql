USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 9 (2026-11-26): vista delgada de lectura sobre dbo.Grupo (uv_grupo calcula estadisticas por grupo; los SP que
-- solo necesitan las llaves leen por esta vista; las lecturas con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_grupo_registro]
AS
SELECT		id,
			idAsignatura = asignatura,
			idPeriodoAcademico = periodoAcademico,
			codigo,
			nombre,
			cantidadEstudiantes,
			cantidadEstudiantesFinalizaron,
			cantidadEstudiantesCancelaronVoluntadPropia,
			cantidadEstudiantesCancelaronAutomaticamente,
			idDocente = docente
FROM		dbo.Grupo
GO
