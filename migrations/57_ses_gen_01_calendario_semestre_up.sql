-- ============================================================================
-- MIGRACION UP 57: SES-GEN-01 - calendario de sesiones del semestre al definir el grupo
--   Decisiones del responsable (2026-11-19):
--   1. Asignatura.horasSemanales INT NULL (1..HORAS_SEMANALES_MAXIMO): horas semanales de 60 min de reloj. Las filas existentes quedan
--      en NULL (B5/B8 no se evaluan y se avisa).
--   2. Parametros: PERIODO/SEMANAS_DURACION = 16 (el semestre dura 112 dias; fechaFin = fechaInicio + 111), ASIGNATURA/HORAS_SEMANALES_MAXIMO
--      = 40 y HORARIO/* (duracion minima 60 y maxima 240 minutos por franja; ventana 06:00-22:00).
--   3. Mensajes HOR_006..HOR_014, ASI_009, ASI_010, PER_010, PER_011 y VAL_APP_076 (usuario y tecnico).
--   Los cuerpos de vistas y SP (uv_asignatura, uv_asignatura_plan_estudio, usp_*_asignatura*, usp_*_periodo_academico,
--   usp_guardar_horarios_grupo, usp_crear_grupo, usp_actualizar_grupo, usp_precargar_sesiones_grupo_interno y el nuevo
--   usp_previsualizar_horario_grupo) se despliegan con deploy_schema.ps1 (CREATE OR ALTER).
-- Idempotente. Down: 57_ses_gen_01_calendario_semestre_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 57 UP: SES-GEN-01 calendario de sesiones del semestre';
GO
IF COL_LENGTH(N'dbo.Asignatura', N'horasSemanales') IS NULL
    ALTER TABLE [dbo].[Asignatura] ADD [horasSemanales] INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Asignatura_horasSemanales' AND parent_object_id = OBJECT_ID(N'dbo.Asignatura'))
    ALTER TABLE [dbo].[Asignatura] ADD CONSTRAINT [CK_Asignatura_horasSemanales] CHECK ([horasSemanales] IS NULL OR [horasSemanales] > 0);
GO
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('PERIODO', 'SEMANAS_DURACION', '16', 'INT', '16'),
    ('ASIGNATURA', 'HORAS_SEMANALES_MAXIMO', '40', 'INT', '40'),
    ('HORARIO', 'DURACION_MINIMA_MINUTOS', '60', 'INT', '60'),
    ('HORARIO', 'DURACION_MAXIMA_MINUTOS', '240', 'INT', '240'),
    ('HORARIO', 'VENTANA_INICIO', '06:00', 'STRING', '06:00'),
    ('HORARIO', 'VENTANA_FIN', '22:00', 'STRING', '22:00')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON Target.grupo = Source.grupo AND Target.clave = Source.clave
WHEN NOT MATCHED THEN
    INSERT (id, grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (NEWID(), Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('HOR_006', 'BUSINESS_ERROR', 'ALTO', N'Las horas semanales del horario ({} h) no coinciden con las de la materia ({} h). Ajusta las franjas para que sumen exactamente las horas de la materia.'),
    ('HOR_007', 'BUSINESS_ERROR', 'MEDIO', N'La franja {} debe durar entre {} y {} minutos.'),
    ('HOR_008', 'BUSINESS_ERROR', 'MEDIO', N'La franja {} debe estar dentro del horario permitido ({}).'),
    ('HOR_009', 'BUSINESS_ERROR', 'ALTO', N'El nuevo horario se cruza con otros grupos de {} estudiante(s) inscrito(s) en la franja {}.'),
    ('HOR_010', 'INFORMATIVO', 'BAJO', N'El horario programa {} h en el período y la materia espera {} h.'),
    ('HOR_011', 'INFORMATIVO', 'BAJO', N'{} h caen en días festivos ({} sesión(es)); esas sesiones quedan canceladas.'),
    ('HOR_012', 'INFORMATIVO', 'BAJO', N'{} h ya no se pueden programar porque el período ya inició; las sesiones se programan desde {}.'),
    ('HOR_013', 'INFORMATIVO', 'MEDIO', N'La materia aún no tiene horas semanales cargadas: no se valida el total del horario.'),
    ('HOR_014', 'INFORMATIVO', 'BAJO', N'Se conservan {} sesión(es) ya dictadas o con asistencia ({} h).'),
    ('ASI_009', 'BUSINESS_ERROR', 'MEDIO', N'Las horas semanales de la materia deben ser un entero entre 1 y {}.'),
    ('ASI_010', 'BUSINESS_ERROR', 'ALTO', N'La asignatura no está disponible para crear grupos: debe estar activa y vinculada a un plan activo de tus programas.'),
    ('PER_010', 'BUSINESS_ERROR', 'ALTO', N'El período académico {} no está vigente: ya terminó, está cerrado o no es de tu institución.'),
    ('PER_011', 'BUSINESS_ERROR', 'MEDIO', N'El período debe durar {} semanas: la fecha de fin debe ser {}.'),
    ('VAL_APP_076', 'VALIDATION_ERROR', 'BAJO', N'El horario del grupo es obligatorio: envía al menos una franja.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON Target.codigo = Source.codigo
WHEN MATCHED THEN
    UPDATE SET tipoMensaje = Source.tipoMensaje, severidad = Source.severidad, contenido = Source.contenido, fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (id, codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (NEWID(), Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('HOR_006', 'BUSINESS_ERROR', 'ALTO', N'Suma de minutos de las franjas distinta de horasSemanales*60 de la asignatura. Franjas: {} h; materia: {} h.'),
    ('HOR_007', 'BUSINESS_ERROR', 'MEDIO', N'Duracion de franja fuera de HORARIO/DURACION_MINIMA_MINUTOS..DURACION_MAXIMA_MINUTOS. Franja {}; minimo {}; maximo {}.'),
    ('HOR_008', 'BUSINESS_ERROR', 'MEDIO', N'Franja fuera de la ventana HORARIO/VENTANA_INICIO..VENTANA_FIN. Franja {}; ventana {}.'),
    ('HOR_009', 'BUSINESS_ERROR', 'ALTO', N'El horario nuevo cruza con otros grupos de estudiantes inscritos. Estudiantes: {}; franja {}.'),
    ('HOR_010', 'INFORMATIVO', 'BAJO', N'Total programado {} h frente a {} h esperadas de la materia.'),
    ('HOR_011', 'INFORMATIVO', 'BAJO', N'Horas perdidas por festivo: {} h en {} sesion(es).'),
    ('HOR_012', 'INFORMATIVO', 'BAJO', N'Horas no programables por inicio tardio: {} h; se programa desde {}.'),
    ('HOR_013', 'INFORMATIVO', 'MEDIO', N'Asignatura sin horasSemanales: B5 y B8 no se evaluan.'),
    ('HOR_014', 'INFORMATIVO', 'BAJO', N'Sesiones conservadas por estar dictadas o con asistencia: {}; horas: {}.'),
    ('ASI_009', 'BUSINESS_ERROR', 'MEDIO', N'horasSemanales invalida: debe ser entero entre 1 y {}.'),
    ('ASI_010', 'BUSINESS_ERROR', 'ALTO', N'Asignatura inactiva, sin vinculo activo con un plan activo, o de un programa que el ejecutor no coordina.'),
    ('PER_010', 'BUSINESS_ERROR', 'ALTO', N'Periodo {} inexistente, de otra institucion, cerrado o terminado.'),
    ('PER_011', 'BUSINESS_ERROR', 'MEDIO', N'Duracion de periodo invalida: se exigen {} semanas; fecha de fin calculada {}.'),
    ('VAL_APP_076', 'VALIDATION_ERROR', 'BAJO', N'Backend (VALIDATION_ERROR): El horario del grupo es obligatorio: envía al menos una franja.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON Target.codigo = Source.codigo
WHEN MATCHED THEN
    UPDATE SET tipoMensaje = Source.tipoMensaje, severidad = Source.severidad, contenido = Source.contenido, fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (id, codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (NEWID(), Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
IF COL_LENGTH(N'dbo.Asignatura', N'horasSemanales') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro
       WHERE (grupo = 'PERIODO' AND clave = 'SEMANAS_DURACION') OR (grupo = 'ASIGNATURA' AND clave = 'HORAS_SEMANALES_MAXIMO')
          OR (grupo = 'HORARIO' AND clave IN ('DURACION_MINIMA_MINUTOS', 'DURACION_MAXIMA_MINUTOS', 'VENTANA_INICIO', 'VENTANA_FIN'))) <> 6
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('HOR_006', 'HOR_007', 'HOR_008', 'HOR_009', 'HOR_010', 'HOR_011', 'HOR_012', 'HOR_013', 'HOR_014', 'ASI_009', 'ASI_010', 'PER_010', 'PER_011', 'VAL_APP_076')) <> 14
    THROW 55701, 'MIGRACION 57: faltan la columna, los parametros o los mensajes de SES-GEN-01.', 1;
GO
PRINT 'MIGRACION 57 UP OK (ejecute deploy_schema.ps1 para los cuerpos de vistas y SP)';
GO
