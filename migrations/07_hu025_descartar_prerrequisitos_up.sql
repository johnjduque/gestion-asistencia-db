USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- HU025 descartada (decision de John, 2026-10-29): los prerrequisitos y correquisitos no existen en la aplicacion.
-- Elimina el stub usp_validar_prerrequisitos_asignatura_estudiante_interno de las bases ya desplegadas
-- (deploy_schema.ps1 crea objetos pero no borra los que salen de schema/). Nadie lo invocaba. Idempotente.
IF OBJECT_ID(N'dbo.usp_validar_prerrequisitos_asignatura_estudiante_interno', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_prerrequisitos_asignatura_estudiante_interno];
GO
