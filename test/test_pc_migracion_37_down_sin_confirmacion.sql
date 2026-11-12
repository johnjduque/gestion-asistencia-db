-- PC puntos de control: el down de la migracion 37 se niega a retirar el reclamo por toma sin confirmacion.
-- Con una solicitud de revision de una toma (fixture en linea) y CONFIRMAR_RETIRO_RECLAMO_TOMA = 0, el down debe abortar con THROW 50037
-- sin cambiar nada. Lo ejecuta test/test_pc_migracion_37.ps1 (wrapper componible con :on error exit); la transaccion nunca se confirma
-- (la conexion termina en el error).
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
:r $(MIGDIR)/37_pc_tomas_puntos_control_up.sql
GO
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idAsig UNIQUEIDENTIFIER = (SELECT TOP 1 a.id FROM dbo.uv_asignatura a ORDER BY a.id);
DECLARE @idPer UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.PeriodoAcademico ORDER BY id);
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @estadoP UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Estado WHERE codigo = 'P');
DECLARE @modo UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @cerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @uE UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID(), @e UNIQUEIDENTIFIER = NEWID();
DECLARE @g UNIQUEIDENTIFIER = NEWID(), @eg UNIQUEIDENTIFIER = NEWID(), @s UNIQUEIDENTIFIER = NEWID(), @t UNIQUEIDENTIFIER = NEWID(), @a UNIQUEIDENTIFIER = NEWID();
DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
VALUES (@uD, @tipoCC, 981000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Mig', N'PC', N'Doc', N'PC', CONCAT(N'pcmig.d.', @tag, N'@test.local'), 1, 1, N'HashBackend_PC'),
       (@uE, @tipoCC, 982000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Mig', N'PC', N'Est', N'PC', CONCAT(N'pcmig.e.', @tag, N'@test.local'), 1, 1, N'HashBackend_PC');
INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
INSERT INTO dbo.Estudiante (id, usuario) VALUES (@e, @uE);
INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
    cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
VALUES (@g, @idAsig, @idPer, 951000 + ABS(CHECKSUM(NEWID()) % 9999), N'PC Mig grupo', 30, 0, 0, 0, @d);
INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@eg, @estadoA, @e, @g);
INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
VALUES (@s, N'PC Mig sesion', 1, CONCAT(N'PCM-', @tag), 1, @g, DATEADD(DAY, -1, SYSUTCDATETIME()), DATEADD(MINUTE, 120, DATEADD(DAY, -1, SYSUTCDATETIME())), N'UTC_V2');
INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
VALUES (@t, @s, 1, @modo, @cerrada, 0, @d, DATEADD(DAY, -1, SYSUTCDATETIME()), DATEADD(MINUTE, 10, DATEADD(DAY, -1, SYSUTCDATETIME())), NEWID());
INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@a, @eg, @s);
EXEC sys.sp_executesql N'INSERT INTO dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta, toma)
                         VALUES (NEWID(), N''REC-PCMIG'', @a, CAST(SYSUTCDATETIME() AS DATE), @estadoP, ''Reclamo de una toma'', '''', @t);',
    N'@a UNIQUEIDENTIFIER, @estadoP UNIQUEIDENTIFIER, @t UNIQUEIDENTIFIER', @a = @a, @estadoP = @estadoP, @t = @t;
IF NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE asistencia = @a)
    THROW 59920, 'TEST FAILED: PC_MIG_02 no se pudo crear el reclamo por toma del fixture.', 1;
PRINT 'PC_DOWN_SIN_CONFIRMACION_FIXTURE_OK';
GO
:r $(MIGDIR)/37_pc_tomas_puntos_control_down.sql
GO
PRINT 'PC_DOWN_SIN_CONFIRMACION_NOT_ENFORCED';
GO
ROLLBACK TRANSACTION;
GO
