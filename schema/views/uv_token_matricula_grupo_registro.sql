USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SKILLS-BD lote 14 (2026-11-26): vista delgada de lectura sobre dbo.TokenMatriculaGrupo (uv_token_matricula_grupo une grupo,
-- docente y usuario, calcula vigencia y no expone programaPorDefecto). Sin filtros ni calculos. NO expone tokenHash,
-- tokenHashAnterior, pin ni pinAnterior (excepcion E7: el rol de runtime tiene SELECT sobre todas las uv_%).
CREATE OR ALTER VIEW [dbo].[uv_token_matricula_grupo_registro]
AS
SELECT		id,
			idGrupo = grupo,
			idDocenteEmisor = docenteEmisor,
			estado,
			fechaEmisionUtc,
			fechaRotacionUtc,
			fechaExpiracionUtc,
			fechaCierreUtc,
			totalMatriculas,
			idProgramaPorDefecto = programaPorDefecto
FROM		dbo.TokenMatriculaGrupo
GO
