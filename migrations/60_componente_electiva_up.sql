-- ============================================================================
-- MIGRACION UP 60: COMP-ELE componente de formacion "electivas" (ELE) (docs/work-items/COMP-ELE-componente-electiva/PLAN.md)
--   Agrega la fila ELE a dbo.Componente (mismo formato que basicas/institucionales/especificas). Seed:
--   schema/seed/11_institucion_infraestructura.sql. Sin cambios de objetos: usp_resolver_area_componente_asignatura_interno ya
--   resuelve el componente por codigo o nombre y uv_componente / usp_consultar_componentes_formacion listan todas las filas.
--   La regla de inscripcion en el programa al matricular (R7, PASO 3.7 de usp_registrar_estudiante_en_grupo_interno) NO cambia.
-- Idempotente (MERGE por id). Down: 60_componente_electiva_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 60 UP: COMP-ELE componente electivas';
GO
MERGE INTO [dbo].[Componente] AS Target
USING (VALUES
    ('9A0EFAA3-9840-4FE3-BC04-048FD0E83C4E', 'electivas', 'ELE')
) AS Source (id, nombre, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO
PRINT 'MIGRACION 60 UP: completada';
GO
