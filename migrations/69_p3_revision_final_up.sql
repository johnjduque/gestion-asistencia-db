-- ============================================================================
-- MIGRACION UP 69: revision final P3 (2026-11-22), defectos de base de datos BD-1..BD-10
--   1. Mensajes nuevos (los mismos de schema/seed/73_p3_revision_final_mensajes.sql): PER_012 (periodos con fechas solapadas, BD-3), EST_010 y
--      EST_011 (matricula manual sin programa comun con el grupo, BD-4).
--   2. BD-5: las sesiones manuales (extraordinarias, con SesionSolicitud) guardaban en numeroSemana su numero de orden; se recalcula como la semana del
--      PERIODO (bloques de 7 dias desde fechaInicio, fecha LOCAL institucional del inicio, minimo 1) solo donde numeroSemana = numero.
--   Los cuerpos de SP y vistas (usp_validar_solape_periodo_academico_interno, usp_validar_programa_comun_estudiante_grupo_interno,
--   usp_crear/actualizar/eliminar_periodo_academico, usp_registrar_estudiante_en_grupo, usp_crear_sesion_interno, usp_previsualizar_horario_grupo,
--   usp_actualizar_grupo, usp_consultar_grupos_paginado, usp_consultar_resumen_sesiones_grupo_docente, usp_consultar_sesiones_grupo_paginado,
--   usp_consultar_kpis_decano, usp_consultar_comparativa_programas_facultad, usp_consultar_consolidado_asistencia_grupos_paginado y la vista
--   uv_sesion_estado) se despliegan con deploy_schema.ps1 (CREATE OR ALTER).
-- Idempotente. Down: 69_p3_revision_final_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 69 UP: revision final P3 (mensajes PER_012/EST_010/EST_011 y semana de sesiones manuales)';
GO
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PER_012', 'BUSINESS_ERROR', 'MEDIO', N'Las fechas del período se cruzan con el período {}; los períodos de la institución no pueden solaparse.'),
    ('EST_010', 'BUSINESS_ERROR', 'MEDIO', N'El estudiante no pertenece a ningún programa de este grupo; solo puedes matricular estudiantes de los programas del grupo.'),
    ('EST_011', 'BUSINESS_ERROR', 'MEDIO', N'El programa indicado no es uno de los programas del estudiante; elige uno de sus programas del grupo.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('PER_012', 'BUSINESS_ERROR', 'MEDIO', N'Regla: las fechas se solapan con dbo.PeriodoAcademico [{}] de la misma institucion (inicio <= fin existente y fin >= inicio existente); sin escrituras.'),
    ('EST_010', 'BUSINESS_ERROR', 'MEDIO', N'Regla BD-4: el estudiante tiene dbo.EstudiantePrograma pero ninguno es programa del grupo (ufn_programas_grupo); sin escrituras.'),
    ('EST_011', 'BUSINESS_ERROR', 'MEDIO', N'Regla BD-4: idPrograma esta en el grupo pero no figura en dbo.EstudiantePrograma del estudiante; sin escrituras.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- BD-5: semana del periodo de las sesiones manuales con el valor anterior (numeroSemana = numero)
DECLARE @zona NVARCHAR(100) = COALESCE((SELECT TOP 1 valor FROM dbo.CatalogoParametro
                                        WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1), 'SA Pacific Standard Time');
UPDATE s
SET s.numeroSemana = x.semana
FROM dbo.Sesion s
INNER JOIN dbo.Grupo g ON g.id = s.grupo
INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
CROSS APPLY (SELECT fechaLocal = CAST(CAST(s.fechaHoraInicio AS DATETIME2) AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE)) f
CROSS APPLY (SELECT semana = IIF(DATEDIFF(DAY, pa.fechaInicio, f.fechaLocal) < 0, 1, DATEDIFF(DAY, pa.fechaInicio, f.fechaLocal) / 7 + 1)) x
WHERE s.numeroSemana = s.numero
  AND EXISTS (SELECT 1 FROM dbo.SesionSolicitud ss WHERE ss.sesion = s.id)   -- solo las sesiones manuales (nacen con solicitud, DEC-065)
  AND x.semana <> s.numeroSemana;
GO
PRINT 'MIGRACION 69 UP: completada';
GO
