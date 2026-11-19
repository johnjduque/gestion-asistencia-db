-- ============================================================================
-- MIGRACION DOWN 59: retira SES-GEN-01 (calendario de sesiones del semestre)
--   Quita Asignatura.horasSemanales (y su CHECK), los parametros PERIODO/SEMANAS_DURACION, ASIGNATURA/HORAS_SEMANALES_MAXIMO y HORARIO/*,
--   y los mensajes HOR_006..HOR_014, ASI_013, ASI_014, PER_010 y PER_011. Las horas cargadas en las asignaturas se pierden.
--   Los cuerpos de vistas y SP anteriores se restauran desplegando el texto de develop previo a la 59 (deploy_schema.ps1); el SP
--   usp_previsualizar_horario_grupo se elimina aqui. Antes del down hay que volver a desplegar los cuerpos previos de uv_asignatura,
--   uv_asignatura_plan_estudio y los SP que leen o escriben horasSemanales.
-- Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 59 DOWN: retira SES-GEN-01';
GO
IF OBJECT_ID(N'dbo.usp_previsualizar_horario_grupo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_previsualizar_horario_grupo];
GO
IF OBJECT_ID(N'dbo.uv_periodo_academico_cierre', N'V') IS NOT NULL
    DROP VIEW [dbo].[uv_periodo_academico_cierre];
GO
DELETE c FROM dbo.CambioParametro c
INNER JOIN dbo.CatalogoParametro p ON p.id = c.parametro
WHERE (p.grupo = 'PERIODO' AND p.clave = 'SEMANAS_DURACION') OR (p.grupo = 'ASIGNATURA' AND p.clave = 'HORAS_SEMANALES_MAXIMO')
   OR (p.grupo = 'HORARIO' AND p.clave IN ('DURACION_MINIMA_MINUTOS', 'DURACION_MAXIMA_MINUTOS', 'VENTANA_INICIO', 'VENTANA_FIN'));
GO
IF OBJECT_ID(N'dbo.CatalogoParametroEdicion', N'U') IS NOT NULL
    DELETE e FROM dbo.CatalogoParametroEdicion e
    INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
    WHERE (p.grupo = 'PERIODO' AND p.clave = 'SEMANAS_DURACION') OR (p.grupo = 'ASIGNATURA' AND p.clave = 'HORAS_SEMANALES_MAXIMO')
       OR (p.grupo = 'HORARIO' AND p.clave IN ('DURACION_MINIMA_MINUTOS', 'DURACION_MAXIMA_MINUTOS', 'VENTANA_INICIO', 'VENTANA_FIN'));
GO
DELETE FROM dbo.CatalogoParametro
WHERE (grupo = 'PERIODO' AND clave = 'SEMANAS_DURACION') OR (grupo = 'ASIGNATURA' AND clave = 'HORAS_SEMANALES_MAXIMO')
   OR (grupo = 'HORARIO' AND clave IN ('DURACION_MINIMA_MINUTOS', 'DURACION_MAXIMA_MINUTOS', 'VENTANA_INICIO', 'VENTANA_FIN'));
GO
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('HOR_006', 'HOR_007', 'HOR_008', 'HOR_009', 'HOR_010', 'HOR_011', 'HOR_012', 'HOR_013', 'HOR_014', 'ASI_013', 'ASI_014', 'PER_010', 'PER_011');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('HOR_006', 'HOR_007', 'HOR_008', 'HOR_009', 'HOR_010', 'HOR_011', 'HOR_012', 'HOR_013', 'HOR_014', 'ASI_013', 'ASI_014', 'PER_010', 'PER_011');
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Asignatura_horasSemanales' AND parent_object_id = OBJECT_ID(N'dbo.Asignatura'))
    ALTER TABLE [dbo].[Asignatura] DROP CONSTRAINT [CK_Asignatura_horasSemanales];
GO
IF COL_LENGTH(N'dbo.Asignatura', N'horasSemanales') IS NOT NULL
    ALTER TABLE [dbo].[Asignatura] DROP COLUMN [horasSemanales];
GO
PRINT 'MIGRACION 59 DOWN OK';
GO
