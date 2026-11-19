USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D1 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C): plantilla del aviso de falta por sesion al estudiante (un correo por estudiante y sesion).
-- Patron 60_sesiones_manuales_plantillas.sql: MERGE idempotente; la version 1 la crea el sistema (creadoPor NULL). El mismo texto por defecto
-- vive en PlantillaPorDefectoCatalogo del backend.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'estudiante',         N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'asignatura',         N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'grupo',              N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'fecha',              N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'horaInicio',         N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'horaFin',            N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'detalleFaltas',      N'Falta general o lista de tomas en falta con su hora (hora institucional)', N'toma 1 (08:15), toma 3 (09:40)', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'fechaLimiteReclamo', N'Fecha límite para radicar el reclamo (hora institucional)', N'16/11/2026', 1),
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'enlaceReclamo',      N'Enlace a la materia en la plataforma, donde se radica el reclamo', N'https://asistencia.uco.edu.co/app/estudiante/mis-materias/materias', 1)
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
    ('FALTA_ASISTENCIA_SESION_ESTUDIANTE', 'es', 1,
     N'Registro de inasistencia: {asignatura} ({fecha})',
     N'Hola {estudiante}. En la sesión de {asignatura} del grupo {grupo} del {fecha} de {horaInicio} a {horaFin} quedó registrada inasistencia: {detalleFaltas}. Si consideras que hay un error, puedes radicar un reclamo por cada toma hasta el {fechaLimiteReclamo} desde {enlaceReclamo}.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
