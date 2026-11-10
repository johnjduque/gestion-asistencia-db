USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: plantillas de notificacion de una sesion creada manualmente por el docente. Patron 34_plantilla_sesion_cancelada.sql
-- (MERGE idempotente; la version 1 la crea el sistema, creadoPor NULL; no pisa ediciones del administrador). El mismo texto por defecto
-- vive en PlantillaPorDefectoCatalogo del backend.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'estudiante',  N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'asignatura',  N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'grupo',       N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'fecha',       N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'horaInicio',  N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'horaFin',     N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'docente',     N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'coordinador', N'Nombre completo del coordinador', N'Ana Gómez', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'asignatura',  N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'grupo',       N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'fecha',       N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'horaInicio',  N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'horaFin',     N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'docente',     N'Nombre completo del docente titular', N'María Rostagno', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET Target.descripcion = Source.descripcion, Target.ejemplo = Source.ejemplo, Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO

MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('SESION_MANUAL_CREADA_ESTUDIANTE', 'es', 1,
     N'Nueva sesión de clase: {asignatura} ({fecha})',
     N'Hola {estudiante}. El docente {docente} programó una sesión adicional de {asignatura} del grupo {grupo} para el {fecha} de {horaInicio} a {horaFin}.',
     1),
    ('SESION_MANUAL_CREADA_COORDINADOR', 'es', 1,
     N'Sesión creada manualmente: {asignatura} ({fecha})',
     N'Hola {coordinador}. El docente {docente} creó manualmente una sesión de {asignatura} del grupo {grupo} para el {fecha} de {horaInicio} a {horaFin}. Si no corresponde, puede cancelarla desde su vista de sesiones.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO

-- CULM-001 / DEC-065 (2): plantillas de la solicitud de sesion extraordinaria con aval del coordinador (mismo formato y marcadores que las
-- de DEC-064). SESION_SOLICITUD_CREADA_COORDINADOR avisa al coordinador la solicitud; SESION_SOLICITUD_APROBADA_DOCENTE y
-- SESION_SOLICITUD_RECHAZADA_DOCENTE avisan al docente la decision (la rechazada agrega motivo y observacion). Idempotente.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'coordinador', N'Nombre completo del coordinador', N'Ana Gómez', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'asignatura',  N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'grupo',       N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'fecha',       N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'horaInicio',  N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'horaFin',     N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'docente',     N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'docente',      N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'asignatura',   N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'grupo',        N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'fecha',        N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'horaInicio',   N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'horaFin',      N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'coordinador',  N'Nombre completo del coordinador que decidió', N'Ana Gómez', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'docente',     N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'asignatura',  N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'grupo',       N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'fecha',       N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'horaInicio',  N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'horaFin',     N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'coordinador', N'Nombre completo del coordinador que decidió', N'Ana Gómez', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'motivo',      N'Motivo del rechazo (catálogo de motivos)', N'Sesión fuera del calendario académico', 1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'observacion', N'Observación del coordinador (puede ir vacía)', N'Reprogramar la próxima semana', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET Target.descripcion = Source.descripcion, Target.ejemplo = Source.ejemplo, Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO

MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('SESION_SOLICITUD_CREADA_COORDINADOR', 'es', 1,
     N'Solicitud de sesión extraordinaria: {asignatura} ({fecha})',
     N'Hola {coordinador}. El docente {docente} solicitó una sesión extraordinaria de {asignatura} del grupo {grupo} para el {fecha} de {horaInicio} a {horaFin}. La sesión queda pendiente de su aprobación; puede aprobarla o rechazarla desde su vista de solicitudes.',
     1),
    ('SESION_SOLICITUD_APROBADA_DOCENTE', 'es', 1,
     N'Solicitud aprobada: {asignatura} ({fecha})',
     N'Hola {docente}. {coordinador} aprobó su solicitud de sesión extraordinaria de {asignatura} del grupo {grupo} para el {fecha} de {horaInicio} a {horaFin}. Ya puede tomar asistencia en ella y los estudiantes fueron notificados.',
     1),
    ('SESION_SOLICITUD_RECHAZADA_DOCENTE', 'es', 1,
     N'Solicitud rechazada: {asignatura} ({fecha})',
     N'Hola {docente}. {coordinador} rechazó su solicitud de sesión extraordinaria de {asignatura} del grupo {grupo} para el {fecha} de {horaInicio} a {horaFin}. Motivo: {motivo}. {observacion}',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
