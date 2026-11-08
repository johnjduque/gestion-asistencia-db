USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU078 / CULM-001 B2NM (DEC-019, R5): relacion grupo -> programas por la tabla puente (ufn_programas_grupo, regla S1).
-- GRANO 1:N por (grupo, programa): todo consumidor que cuente o pagine grupos, sesiones o estudiantes debe usar EXISTS o
-- DISTINCT sobre la clave de negocio. El plan es el del programa con vinculo vigente; si hay varios: activo primero,
-- mayor inp, menor id. PlanEstudio.estado = 0 NO saca un grupo de la vista (conserva la historia, O-N10).
CREATE OR ALTER VIEW [dbo].[uv_grupo_programa]
AS
SELECT  idGrupo = g.id,
        idPrograma = pg.idPrograma,
        idPeriodoAcademico = g.idPeriodoAcademico,
        grupoEstaHablitado = g.grupoEstaHablitado,
        idPlanEstudio = pg.idPlanEstudio,
        inpPlanEstudio = pg.inpPlanEstudio
FROM    uv_grupo g
CROSS APPLY dbo.ufn_programas_grupo(g.id) pg
GO
