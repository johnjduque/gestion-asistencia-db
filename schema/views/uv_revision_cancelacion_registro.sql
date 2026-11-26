USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 9 (2026-11-26): vista delgada de lectura sobre dbo.RevisionCancelacion (uv_revision_cancelacion une 11 tablas;
-- los SP que solo necesitan las llaves leen por esta vista; las lecturas con bloqueo y las escrituras siguen en la tabla).
-- SKILLS-BD lote 11 (2026-11-26): agrega AL FINAL el resto de columnas de la tabla (la vista es del lote 9, aun no publicada en
-- develop; las columnas previas no cambian). Sigue siendo una tabla, sin filtros ni calculos: devuelve las mismas filas.
CREATE OR ALTER VIEW [dbo].[uv_revision_cancelacion_registro]
AS
SELECT		id,
			idEstudianteGrupo = estudianteGrupo,
			idEstado = estado,
			idAlertaOrigen = alertaOrigen,
			fechaCreacionUtc,
			fechaActualizacionUtc,
			porcentajeCreacion,
			horasFaltaCreacion,
			horasDictadasCreacion,
			idCorrelacionCreacion,
			codigoDecisionDocente,
			motivoDocente,
			idUsuarioDecisionDocente = usuarioDecisionDocente,
			porcentajeDecisionDocente,
			fechaDecisionDocenteUtc,
			codigoPerfilResolutorActual,
			huellaResolutoresActual,
			fechaEscalamientoUtc,
			codigoDecisionResolucion,
			motivoResolucion,
			idUsuarioResolucion = usuarioResolucion,
			codigoPerfilResolucion,
			idProgramaResolucion = programaResolucion,
			porcentajeResolucion,
			fechaResolucionUtc,
			idEstadoMatriculaAnterior = estadoMatriculaAnterior
FROM		dbo.RevisionCancelacion
GO
