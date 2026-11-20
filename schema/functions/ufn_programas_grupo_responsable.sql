USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEC-077 (2026-11-20): programa responsable de un grupo (una fila, o ninguna si el grupo no tiene programas vigentes).
-- Un grupo de una asignatura compartida por varios programas tiene UN solo responsable: el coordinador de ese programa gestiona el
-- grupo (horario, sesiones, cancelaciones), aprueba sus solicitudes de sesion y recibe los avisos del grupo. Los asuntos de cada
-- estudiante (retiros, revision de cancelaciones, alertas) siguen yendo al coordinador del programa del estudiante.
-- Regla, entre los programas vigentes del grupo (ufn_programas_grupo):
--   1. Grupo.programaResponsable (lo fija usp_crear_grupo con el programa del coordinador que crea el grupo), si sigue vigente;
--   2. si es NULL (grupos anteriores a DEC-077) o el vinculo ya no esta vigente: el programa con mas estudiantes del grupo y,
--      a igualdad, el de menor nombre. Asi la regla siempre devuelve un unico programa, sin depender del orden de lectura.
-- Se despliega despues de ufn_programas_grupo (orden alfabetico de deploy_schema.ps1).
CREATE OR ALTER FUNCTION [dbo].[ufn_programas_grupo_responsable] (@idGrupo UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT  TOP (1) pg.idPrograma, pg.idPlanEstudio, pg.inpPlanEstudio
    FROM    dbo.ufn_programas_grupo(@idGrupo) pg
    INNER JOIN dbo.Programa p ON p.id = pg.idPrograma
    OUTER APPLY (SELECT g.programaResponsable FROM dbo.Grupo g WHERE g.id = @idGrupo) r
    OUTER APPLY (SELECT inscritos = COUNT(*)
                 FROM dbo.EstudianteGrupo eg
                 INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = eg.estudiante AND ep.programa = pg.idPrograma
                 WHERE eg.grupo = @idGrupo) c
    ORDER BY IIF(pg.idPrograma = r.programaResponsable, 0, 1), c.inscritos DESC, p.nombre, p.id
);
GO
