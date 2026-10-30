USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- Decision de John (2026-10-30): elimina usp_validar_grupo_exista_para_docente_interno de las bases ya desplegadas.
-- Quedo sin callers cuando usp_validar_cruce_horario_docente_interno dejo de invocarlo (#70): exigia que el
-- grupo estuviera en el periodo vigente. deploy_schema.ps1 no borra objetos. Idempotente.
IF OBJECT_ID(N'dbo.usp_validar_grupo_exista_para_docente_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_grupo_exista_para_docente_interno];
GO
