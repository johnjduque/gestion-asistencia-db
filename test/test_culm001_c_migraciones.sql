USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- CULM-001 C.1 (CONTRACT §2.13.1 C-DB-60, O-6): migracion 19 sobre la base B2. up -> up (idempotente), up -> down -> up, archivos zz_* con
-- las mismas filas, matriculas CI intactas, SP restaurados y resumen del docente ejecutable sin las columnas de C. Todo dentro de una
-- transaccion que se revierte (el DDL de SQL Server es transaccional). Variable sqlcmd MIGDIR = carpeta migrations/ (la define test_culm001_c.ps1).
PRINT 'TEST START: test_culm001_c_migraciones';
GO
BEGIN TRANSACTION;
GO
:r $(MIGDIR)/19_culm001_c_cancelacion_inasistencia_up.sql
:r $(MIGDIR)/19_culm001_c_cancelacion_inasistencia_up.sql
GO
IF (SELECT COUNT(*) FROM dbo.TipoAlertaInasistencia) <> 2 OR (SELECT COUNT(*) FROM dbo.EstadoAlertaInasistencia) <> 2
   OR (SELECT COUNT(*) FROM dbo.EstadoRevisionCancelacion) <> 5 OR (SELECT COUNT(*) FROM dbo.TransicionRevisionCancelacion) <> 6
    THROW 58500, 'TEST FAILED: C-DB-60 up -> up debe dejar 2/2/5/6 filas de catalogo (idempotente).', 1;
-- Datos propios para comprobar el archivo del down
DECLARE @eg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstudianteGrupo ORDER BY id);
DECLARE @tipo UNIQUEIDENTIFIER = '7C1E0C10-5E51-4C0A-9A01-000000000002', @estAl UNIQUEIDENTIFIER = '7C1E0C20-5E51-4C0A-9A01-000000000001', @estRev UNIQUEIDENTIFIER = '7C1E0C30-5E51-4C0A-9A01-000000000001';
DECLARE @al UNIQUEIDENTIFIER = NEWID(), @rv UNIQUEIDENTIFIER = NEWID(), @ahora DATETIME2(3) = SYSUTCDATETIME();
IF @eg IS NULL THROW 58501, 'TEST FAILED: C-DB-60 falta una matricula sembrada.', 1;
INSERT INTO dbo.AlertaInasistencia (id, estudianteGrupo, tipo, estado, porcentajeCruce, umbralCruce, horasFaltaCruce, horasDictadasCruce, fechaCruceUtc, idCorrelacionCruce, porcentajeUltimaEvaluacion, fechaUltimaEvaluacionUtc)
VALUES (@al, @eg, @tipo, @estAl, 25, 20, 5, 20, @ahora, NEWID(), 25, @ahora);
INSERT INTO dbo.RevisionCancelacion (id, estudianteGrupo, estado, alertaOrigen, porcentajeCreacion, horasFaltaCreacion, horasDictadasCreacion, fechaCreacionUtc, idCorrelacionCreacion, fechaActualizacionUtc)
VALUES (@rv, @eg, @estRev, @al, 25, 5, 20, @ahora, NEWID(), @ahora);
INSERT INTO dbo.RevisionCancelacionHistorial (id, revision, estadoAnterior, estadoNuevo, codigoEvento, porcentajeInasistencia, fechaUtc, idCorrelacion)
VALUES (NEWID(), @rv, NULL, @estRev, N'CREAR', 25, @ahora, NEWID());
DECLARE @ci INT = (SELECT COUNT(*) FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo e ON e.id = eg.estado WHERE e.codigo = N'CI');
CREATE TABLE #c1mig (clave NVARCHAR(40) PRIMARY KEY, valor INT);
INSERT INTO #c1mig VALUES (N'ci', @ci);
GO
:r $(MIGDIR)/19_culm001_c_cancelacion_inasistencia_down.sql
GO
IF OBJECT_ID(N'dbo.AlertaInasistencia', N'U') IS NOT NULL OR OBJECT_ID(N'dbo.RevisionCancelacion', N'U') IS NOT NULL OR OBJECT_ID(N'dbo.TipoAlertaInasistencia', N'U') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_evaluar_alertas_inasistencia_grupo', N'P') IS NOT NULL OR OBJECT_ID(N'dbo.uv_revision_cancelacion', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.ufn_revision_cancelacion_resolutores') IS NOT NULL
    THROW 58502, 'TEST FAILED: C-DB-60 el down debe retirar tablas, SP, vistas y funciones de C.', 1;
IF (SELECT COUNT(*) FROM dbo.zz_archivo_AlertaInasistencia_culm001_c) <> 1 OR (SELECT COUNT(*) FROM dbo.zz_archivo_RevisionCancelacion_culm001_c) <> 1
   OR (SELECT COUNT(*) FROM dbo.zz_archivo_RevisionCancelacionHistorial_culm001_c) <> 1
    THROW 58503, 'TEST FAILED: C-DB-60 los archivos zz_* deben conservar las mismas filas.', 1;
IF (SELECT valor FROM #c1mig WHERE clave = N'ci') <> (SELECT COUNT(*) FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo e ON e.id = eg.estado WHERE e.codigo = N'CI')
    THROW 58504, 'TEST FAILED: C-DB-60 las matriculas CI deben quedar intactas.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo IN ('ALERTA_INASISTENCIA', 'REVISION_CANCELACION') AND ISNULL(valor, N'') = ISNULL(valorDefecto, N''))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'RCN[_]%' OR codigo LIKE 'ALR[_]%')
    THROW 58505, 'TEST FAILED: C-DB-60 el down borra parametros y mensajes de C en su valor por defecto.', 1;
-- El resumen del docente (version B2) ejecuta sin error y sin las columnas de C
IF COL_LENGTH('dbo.usp_consultar_resumen_asistencia_grupo_docente_paginado', 'x') IS NULL
   AND EXISTS (SELECT 1 FROM sys.dm_exec_describe_first_result_set(N'EXEC dbo.usp_consultar_resumen_asistencia_grupo_docente_paginado @idUsuarioEjecutor = ''00000000-0000-0000-0000-000000000001'', @idCorrelacion = ''00000000-0000-0000-0000-000000000001'', @idGrupo = ''00000000-0000-0000-0000-000000000001''', NULL, 0) WHERE name IN (N'accionesPermitidasRevision', N'tieneAdvertenciaVigente'))
    THROW 58506, 'TEST FAILED: C-DB-60 tras el down el resumen del docente no debe tener las columnas de C.', 1;
-- SP restaurados con el texto anterior a C: el cierre vuelve a contar faltas (sin motor ni revisiones) y el resumen pierde la marca de C
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ejecutar_cierre_masivo_periodo')) LIKE N'%RevisionCancelacion%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_ejecutar_cierre_masivo_periodo')) NOT LIKE N'%InasistenciasPorEstudiante%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_consultar_resumen_asistencia_grupo_docente_paginado')) LIKE N'%uv_marca_inasistencia%'
    THROW 58508, 'TEST FAILED: C-DB-60 el down debe restaurar el cierre masivo (B.2) y el resumen del docente (B2).', 1;
GO
:r $(MIGDIR)/19_culm001_c_cancelacion_inasistencia_up.sql
GO
IF (SELECT COUNT(*) FROM dbo.TipoAlertaInasistencia) <> 2 OR (SELECT COUNT(*) FROM dbo.TransicionRevisionCancelacion) <> 6 OR OBJECT_ID(N'dbo.uv_marca_inasistencia_estudiante_grupo', N'V') IS NULL
    THROW 58507, 'TEST FAILED: C-DB-60 up -> down -> up debe reconstruir los catalogos y las vistas.', 1;
PRINT 'TEST_PASS:CULM001_C_MIG_19_UP_DOWN_UP';
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
