-- 04_flujos.sql  (GENERADO). Usa los SP reales con el ejecutor del rol que corresponde.
USE [gestionasistenciadb];
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;

DECLARE @p20262 UNIQUEIDENTIFIER = 'F2A3B4C5-0000-0000-0000-000000000001';
DECLARE @g UNIQUEIDENTIFIER, @c UNIQUEIDENTIFIER, @rev UNIQUEIDENTIFIER, @sol UNIQUEIDENTIFIER, @ses UNIQUEIDENTIFIER, @toma UNIQUEIDENTIFIER;

-- 1. Alertas de inasistencia (riesgo 15 %, perdida 20 %) de cada grupo de 2026-2
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT id FROM dbo.Grupo WHERE periodoAcademico = @p20262;
OPEN cur; FETCH NEXT FROM cur INTO @g;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @c = NEWID();
    EXEC dbo.usp_evaluar_alertas_inasistencia_grupo @idGrupo = @g, @idCorrelacion = @c;
    FETCH NEXT FROM cur INTO @g;
END
CLOSE cur; DEALLOCATE cur;

-- 2. Revisiones de cancelacion: Santiago (BDA-1) propuesta por el docente, pendiente del coordinador de Sistemas;
--    Kevin (CAL-3) propuesta y aprobada por la coordinadora de Tec. Software (queda cancelado por inasistencia);
--    Brayan (ETI-2) queda pendiente de la decision del docente.
SET @rev = NULL;
SELECT @rev = rc.id FROM dbo.RevisionCancelacion rc WHERE rc.estudianteGrupo = 'FD42ECB7-8CC4-5557-A7D7-A4B0DE85A2A0';
IF @rev IS NOT NULL BEGIN SET @c = NEWID(); EXEC dbo.usp_decidir_revision_cancelacion @idRevision = @rev, @codigoDecision = N'PROPONER', @motivo = N'Supera el 20 % de inasistencia sin justificación y no respondió a las alertas.', @idCorrelacion = @c, @idUsuarioEjecutor = '9949011E-05A6-572D-9F4C-74989A28F1BC'; END ELSE PRINT N'Sin revision para Santiago';
SET @rev = NULL;
SELECT @rev = rc.id FROM dbo.RevisionCancelacion rc WHERE rc.estudianteGrupo = 'AAD3C379-2B66-5346-A979-58BC1E0DDE85';
IF @rev IS NOT NULL BEGIN SET @c = NEWID(); EXEC dbo.usp_decidir_revision_cancelacion @idRevision = @rev, @codigoDecision = N'PROPONER', @motivo = N'Inasistencia del 30 % sin justificación.', @idCorrelacion = @c, @idUsuarioEjecutor = '75937ED4-6991-525F-A4B6-9D2BDFF899AF';
    SET @c = NEWID(); EXEC dbo.usp_resolver_revision_cancelacion @idRevision = @rev, @codigoDecision = N'APROBAR', @motivo = N'Se confirma la cancelación por inasistencia según el reglamento.', @idCorrelacion = @c, @idUsuarioEjecutor = '7530B035-EC7A-59B3-B944-D827EF3CD5D2'; END ELSE PRINT N'Sin revision para Kevin';

-- 3. Retiro de un estudiante por el docente (Isabella, Algebra Lineal)
SET @c = NEWID();
EXEC dbo.usp_retirar_estudiante_grupo @idGrupo = '6269A9FC-73F0-5E18-84C4-B1B4EADB59AD', @idEstudiante = 'D5C7E04D-4104-5A0B-BE84-62DEC58AE9FC', @motivo = N'La estudiante solicitó el retiro de la asignatura por cruce con su práctica laboral.', @idCorrelacion = @c, @idUsuarioEjecutor = '9949011E-05A6-572D-9F4C-74989A28F1BC';

-- 4. Reclamos de asistencia radicados por los estudiantes sobre su ultima falta (dentro del plazo)
SELECT TOP 1 @ses = a.sesion, @toma = da.toma FROM dbo.Asistencia a JOIN dbo.DetalleAsistencia da ON da.asistencia = a.id
  JOIN dbo.RazonCausa r ON r.id = da.razonCausa JOIN dbo.Sesion s ON s.id = a.sesion
  WHERE a.estudianteGrupo = '71A14ADF-004D-5BE7-B5A8-2292B4DC729D' AND r.codigo = 'SJC' ORDER BY s.fechaHoraInicio DESC;
SET @c = NEWID();
EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = '3053AED5-F33D-53E6-8D65-2A5103D8644D', @idSesion = @ses, @idToma = @toma, @categoria = N'CAL', @justificacion = N'Mi abuela fue hospitalizada de urgencia y tuve que acompañarla.', @idsArchivoSoporte = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = '07EE46D8-7DB1-5F23-BB1D-E1E3EA8C8B17';
SET @sol = (SELECT TOP 1 sr.id FROM dbo.SolicitudRevisionAsistencia sr JOIN dbo.Asistencia a ON a.id = sr.asistencia WHERE a.estudianteGrupo = '71A14ADF-004D-5BE7-B5A8-2292B4DC729D');

SELECT TOP 1 @ses = a.sesion, @toma = da.toma FROM dbo.Asistencia a JOIN dbo.DetalleAsistencia da ON da.asistencia = a.id
  JOIN dbo.RazonCausa r ON r.id = da.razonCausa JOIN dbo.Sesion s ON s.id = a.sesion
  WHERE a.estudianteGrupo = 'EE5EE52A-3E1A-5B12-83F4-78A099216343' AND r.codigo = 'SJC' ORDER BY s.fechaHoraInicio DESC;
SET @c = NEWID();
EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = 'C3A2F093-A564-5E98-B7B3-8AF69F770C0C', @idSesion = @ses, @idToma = @toma, @categoria = N'FMA', @justificacion = N'Hubo cierre de la vía Rionegro–Marinilla por un derrumbe y no pude llegar.', @idsArchivoSoporte = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = '303BCD11-165F-5883-901D-5622B6B5771C';
SET @sol = (SELECT TOP 1 sr.id FROM dbo.SolicitudRevisionAsistencia sr JOIN dbo.Asistencia a ON a.id = sr.asistencia WHERE a.estudianteGrupo = 'EE5EE52A-3E1A-5B12-83F4-78A099216343');
SET @c = NEWID();
EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = '3A7BB4A7-6CFA-52A1-8150-F4032204B268', @accion = N'APROBADA', @respuestaDocente = N'Se valida el soporte del cierre vial reportado.', @idCorrelacion = @c, @idUsuarioEjecutor = '75937ED4-6991-525F-A4B6-9D2BDFF899AF';

SELECT TOP 1 @ses = a.sesion, @toma = da.toma FROM dbo.Asistencia a JOIN dbo.DetalleAsistencia da ON da.asistencia = a.id
  JOIN dbo.RazonCausa r ON r.id = da.razonCausa JOIN dbo.Sesion s ON s.id = a.sesion
  WHERE a.estudianteGrupo = 'F401F285-33DE-5031-873D-818B01821B4E' AND r.codigo = 'SJC' ORDER BY s.fechaHoraInicio DESC;
SET @c = NEWID();
EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = '5824A7F4-5693-53A9-BEF0-600D36E642BA', @idSesion = @ses, @idToma = @toma, @categoria = N'OTR', @justificacion = N'Me quedé dormida porque trabajé hasta tarde.', @idsArchivoSoporte = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = 'B6A51196-5EDE-5DF4-9A83-45CE23C63A25';
SET @sol = (SELECT TOP 1 sr.id FROM dbo.SolicitudRevisionAsistencia sr JOIN dbo.Asistencia a ON a.id = sr.asistencia WHERE a.estudianteGrupo = 'F401F285-33DE-5031-873D-818B01821B4E');
SET @c = NEWID();
EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @sol, @idDocente = 'EFC62B2F-AAC6-509F-B1FB-493BBE3EB0B2', @accion = N'RECHAZADA', @respuestaDocente = N'El motivo no corresponde a una justa causa según el reglamento.', @idCorrelacion = @c, @idUsuarioEjecutor = '60619138-0A1D-57A5-86A5-352DB8BB007B';

SELECT TOP 1 @ses = a.sesion, @toma = da.toma FROM dbo.Asistencia a JOIN dbo.DetalleAsistencia da ON da.asistencia = a.id
  JOIN dbo.RazonCausa r ON r.id = da.razonCausa JOIN dbo.Sesion s ON s.id = a.sesion
  WHERE a.estudianteGrupo = '839EAC2E-8541-534A-A0A2-B3473BB32773' AND r.codigo = 'SJC' ORDER BY s.fechaHoraInicio DESC;
SET @c = NEWID();
EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = 'A026538D-D91A-5FF5-BBBF-0A166FC69509', @idSesion = @ses, @idToma = @toma, @categoria = N'OTR', @justificacion = N'Tuve un problema de transporte.', @idsArchivoSoporte = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = '2620B2EB-0E91-532E-BF5E-6556A10F8C9D';
SET @sol = (SELECT TOP 1 sr.id FROM dbo.SolicitudRevisionAsistencia sr JOIN dbo.Asistencia a ON a.id = sr.asistencia WHERE a.estudianteGrupo = '839EAC2E-8541-534A-A0A2-B3473BB32773');
SET @c = NEWID();
EXEC dbo.usp_retirar_solicitud_revision_asistencia @idSolicitudRevision = @sol, @idCorrelacion = @c, @idUsuarioEjecutor = '2620B2EB-0E91-532E-BF5E-6556A10F8C9D';

SELECT TOP 1 @ses = a.sesion, @toma = da.toma FROM dbo.Asistencia a JOIN dbo.DetalleAsistencia da ON da.asistencia = a.id
  JOIN dbo.RazonCausa r ON r.id = da.razonCausa JOIN dbo.Sesion s ON s.id = a.sesion
  WHERE a.estudianteGrupo = 'A2E902B2-7322-5002-91D0-A43DB54E0F10' AND r.codigo = 'SJC' ORDER BY s.fechaHoraInicio DESC;
SET @c = NEWID();
EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = '854E7760-1B03-597E-B1AC-3D27EA3A7453', @idSesion = @ses, @idToma = @toma, @categoria = N'FMA', @justificacion = N'Se presentó un corte de energía en el sector durante la sesión.', @idsArchivoSoporte = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = 'F1464179-73AB-5E73-A153-5FB1297000F8';
SET @sol = (SELECT TOP 1 sr.id FROM dbo.SolicitudRevisionAsistencia sr JOIN dbo.Asistencia a ON a.id = sr.asistencia WHERE a.estudianteGrupo = 'A2E902B2-7322-5002-91D0-A43DB54E0F10');

SELECT TOP 1 @ses = a.sesion, @toma = da.toma FROM dbo.Asistencia a JOIN dbo.DetalleAsistencia da ON da.asistencia = a.id
  JOIN dbo.RazonCausa r ON r.id = da.razonCausa JOIN dbo.Sesion s ON s.id = a.sesion
  WHERE a.estudianteGrupo = 'C2709EB0-BC1B-519C-8D03-5C22CEAE8B53' AND r.codigo = 'SJC' ORDER BY s.fechaHoraInicio DESC;
SET @c = NEWID();
EXEC dbo.usp_radicar_solicitud_revision_asistencia_v4 @idEstudiante = 'ED32805D-B182-5F26-8014-D90A72813015', @idSesion = @ses, @idToma = @toma, @categoria = N'CAL', @justificacion = N'Fallecimiento de un familiar cercano.', @idsArchivoSoporte = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = 'F76930F7-37CD-57C6-A190-E02CFA9CF247';
SET @sol = (SELECT TOP 1 sr.id FROM dbo.SolicitudRevisionAsistencia sr JOIN dbo.Asistencia a ON a.id = sr.asistencia WHERE a.estudianteGrupo = 'C2709EB0-BC1B-519C-8D03-5C22CEAE8B53');

-- 5. Solicitudes de sesion extraordinaria creadas por docentes (pendientes del coordinador)
SET @c = NEWID();
EXEC dbo.usp_crear_sesion_v2 @idGrupo = 'FC36AEF9-BBC4-532B-921E-660DCD9CD7DF', @nombre = N'Taller de refuerzo de ciclos', @fechaHoraInicio = '2026-11-21T13:00:00', @fechaHoraFin = '2026-11-21T15:00:00', @idCorrelacion = @c, @idUsuarioEjecutor = 'E1F2A3B4-0000-0000-0000-000000000003';
SET @c = NEWID();
EXEC dbo.usp_crear_sesion_v2 @idGrupo = 'BD01E6A9-52B5-55A7-B0D1-4382B3721852', @nombre = N'Repaso para el examen final', @fechaHoraInicio = '2026-11-20T23:00:00', @fechaHoraFin = '2026-11-21T01:00:00', @idCorrelacion = @c, @idUsuarioEjecutor = '75937ED4-6991-525F-A4B6-9D2BDFF899AF';

SELECT alertas = (SELECT COUNT(*) FROM dbo.AlertaInasistencia), revisiones = (SELECT COUNT(*) FROM dbo.RevisionCancelacion),
       reclamos = (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia), solicitudesSesion = (SELECT COUNT(*) FROM dbo.SesionSolicitud);
