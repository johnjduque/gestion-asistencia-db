-- ============================================================================
-- MIGRACION UP 49: VAL-pendientes-john PRU-15, regla de "periodo cerrado" (decision del responsable 2026-11-18)
--   1. Columna PeriodoAcademico.fechaCierreUtc (NULL = no cerrado). Relleno: los periodos con una auditoria CIERRE_MASIVO_PERIODO
--      SUCCESS cuya fecha local (TIEMPO/ZONA_HORARIA_SQLSERVER) es posterior a fechaFin quedan cerrados con el instante de ese primer
--      cierre. Un cierre auditado antes de que el periodo terminara (posible antes de FIX-CIERRE-002) NO cierra el periodo.
--   2. Mensajes PER_008 (operacion sobre un periodo cerrado) y PER_009 (segundo cierre), los mismos de
--      schema/seed/17_mensajes_periodo_academico.sql.
--   3. Los cuerpos de los SP (nucleo nuevo usp_validar_periodo_abierto_sesion_interno sin GRANT, y usp_validar_sesion_ventana_registro_interno,
--      usp_cerrar_toma_asistencia, usp_internal_radicar_solicitud_revision, usp_radicar_solicitud_revision_asistencia,
--      usp_resolver_solicitud_revision_asistencia, usp_retirar_solicitud_revision_asistencia y usp_ejecutar_cierre_masivo_periodo) se
--      despliegan con deploy_schema.ps1 (CREATE OR ALTER), como en la 48: dependen de vistas que otras ramas cambiaron solo por despliegue
--      (uv_periodo_academico.estado) y no se pueden aplicar sobre una base vieja. Firmas y resultsets sin cambio.
-- Idempotente. Down: 49_val_periodo_cerrado_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 49 UP: VAL-pendientes-john PRU-15 (periodo cerrado)';
GO
-- ---- schema/tables/PeriodoAcademico.sql (solo la columna fechaCierreUtc)
IF COL_LENGTH('dbo.PeriodoAcademico', 'fechaCierreUtc') IS NULL
    ALTER TABLE [dbo].[PeriodoAcademico] ADD [fechaCierreUtc] datetime2(7) NULL;
GO
-- ---- relleno desde la auditoria del cierre masivo (solo cierres exitosos de periodos ya terminados; el primero gana)
DECLARE @zonaParametro NVARCHAR(128) = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
DECLARE @zona NVARCHAR(128) = IIF(@zonaParametro IS NULL OR @zonaParametro = N'', N'SA Pacific Standard Time', @zonaParametro);
UPDATE pa
SET    pa.fechaCierreUtc = c.primerCierreUtc
FROM   dbo.PeriodoAcademico pa
CROSS APPLY (
    SELECT primerCierreUtc = MIN(CAST(a.occurredAt AT TIME ZONE 'UTC' AS DATETIME2(7)))
    FROM   dbo.AuditoriaEvento a
    WHERE  a.action = 'CIERRE_MASIVO_PERIODO'
      AND  a.result = 'SUCCESS'
      AND  a.resourceId = CAST(pa.id AS NVARCHAR(50))
      AND  CAST(a.occurredAt AT TIME ZONE @zona AS DATE) > pa.fechaFin
) c
WHERE  pa.fechaCierreUtc IS NULL
  AND  c.primerCierreUtc IS NOT NULL;
PRINT CONCAT('MIGRACION 49 UP: periodos marcados como cerrados desde la auditoria: ', @@ROWCOUNT);
GO
-- ---- mensajes PER_008 y PER_009 (schema/seed/17_mensajes_periodo_academico.sql)
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PER_008', 'BUSINESS_ERROR', 'MEDIO', N'El período académico {} ya fue cerrado; no se pueden registrar ni modificar tomas, asistencias ni reclamos de sus sesiones.'),
    ('PER_009', 'BUSINESS_ERROR', 'MEDIO', N'El período académico ya fue cerrado el {}; el cierre masivo no se puede repetir.')
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
    ('PER_008', 'BUSINESS_ERROR', 'MEDIO', N'Regla: PeriodoAcademico.fechaCierreUtc no es nula (periodo {} cerrado el {} UTC); no se registran ni modifican tomas, lotes ni reclamos de sus sesiones.'),
    ('PER_009', 'BUSINESS_ERROR', 'MEDIO', N'Regla: PeriodoAcademico.fechaCierreUtc ya registrada (cierre del {}, fecha local institucional); usp_ejecutar_cierre_masivo_periodo no repite el cierre ni audita nada.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
IF COL_LENGTH('dbo.PeriodoAcademico', 'fechaCierreUtc') IS NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'PER_009')
    THROW 54901, 'MIGRACION 49: faltan la columna fechaCierreUtc o los mensajes PER_008/PER_009.', 1;
GO
PRINT 'MIGRACION 49 UP OK';
GO
