USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 13 (2026-11-26): vista delgada de lectura sobre dbo.Programa (uv_programa une facultad, institucion y coordinador;
-- los SP que solo necesitan la fila leen por esta vista; las lecturas con bloqueo y las escrituras siguen en la tabla).
CREATE OR ALTER VIEW [dbo].[uv_programa_registro]
AS
SELECT		id,
			nombre,
			idFacultad = facultad,
			idTipoPrograma = tipoDePrograma,
			idCoordinador = coordinador,
			estado,
			idModalidad = modalidad,
			idJornada = jornada
FROM		dbo.Programa
GO
