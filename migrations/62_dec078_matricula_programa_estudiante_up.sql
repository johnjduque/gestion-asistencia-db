-- ============================================================================
-- MIGRACION UP 62: DEC-078 (2026-11-20) - en un grupo compartido el estudiante elige su programa al matricularse por QR
--   Antes el docente elegia, al abrir la ventana de matricula, un programa para TODOS los que escanearan el codigo.
--   1. Mensaje MQR_008 (usuario y tecnico): pide al estudiante elegir el programa (seed 38_mensajes_asignatura_plan.sql).
--   Los cuerpos de usp_abrir_ventana_matricula_grupo (sin EST_005 en la apertura), usp_validar_token_matricula_publico (columna
--   programasElegibles, JSON), usp_internal_matricular_por_token (parametro aditivo @idProgramaElegido, EST_006 antes de escribir),
--   usp_matricular_estudiante_por_token y usp_registrar_estudiante_por_token_publico (parametro aditivo @idPrograma) se despliegan
--   con deploy_schema.ps1 (CREATE OR ALTER), como en la 48, la 49, la 56 y la 61.
-- Sin cambios de tablas. Idempotente. Down: 62_dec078_matricula_programa_estudiante_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 62 UP: DEC-078 programa elegido por el estudiante en la matricula por QR';
GO
UPDATE dbo.CatalogoMensajeUsuario
SET contenido = N'Este grupo lo comparten varios programas: elige el programa al que perteneces para matricularte.', fechaModificacion = SYSUTCDATETIME()
WHERE codigo = 'MQR_008';
UPDATE dbo.CatalogoMensajeTecnico
SET contenido = N'Regla S3/DEC-078: el grupo tiene varios programas, la ventana no fija programa, el estudiante no eligio uno (@idPrograma) y no pertenece a ninguno del grupo.', fechaModificacion = SYSUTCDATETIME()
WHERE codigo = 'MQR_008';
GO
PRINT 'MIGRACION 62 UP OK (ejecute deploy_schema.ps1 para los cuerpos de los SP de la matricula por QR)';
GO
