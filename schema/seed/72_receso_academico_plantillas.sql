USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEC-081 (2026-11-21): plantillas del aviso de clases canceladas por un dia de receso academico (un correo por persona con el resumen
-- de sus clases canceladas). Patron 60_sesiones_manuales_plantillas.sql (MERGE idempotente; version 1 creada por el sistema; no pisa
-- ediciones del administrador). El mismo texto por defecto vive en los recursos de plantillas del backend. Migracion 68.
-- {clases} es una sola linea: las clases separadas por "; " (el motor no convierte saltos de linea dentro de un valor).
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('RECESO_CLASES_CANCELADAS_ESTUDIANTE', 'estudiante', N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('RECESO_CLASES_CANCELADAS_ESTUDIANTE', 'fecha',      N'Fecha del receso académico (dd/MM/yyyy, hora institucional)', N'10/11/2026', 1),
    ('RECESO_CLASES_CANCELADAS_ESTUDIANTE', 'motivo',     N'Motivo del receso académico', N'Jornada institucional', 1),
    ('RECESO_CLASES_CANCELADAS_ESTUDIANTE', 'clases',     N'Clases canceladas del estudiante ese día (asignatura, grupo y hora), separadas por punto y coma', N'Ingeniería de Software, G01, 08:00 a 10:00; Bases de Datos, G02, 10:00 a 12:00', 1),
    ('RECESO_CLASES_CANCELADAS_DOCENTE', 'docente',       N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('RECESO_CLASES_CANCELADAS_DOCENTE', 'fecha',         N'Fecha del receso académico (dd/MM/yyyy, hora institucional)', N'10/11/2026', 1),
    ('RECESO_CLASES_CANCELADAS_DOCENTE', 'motivo',        N'Motivo del receso académico', N'Jornada institucional', 1),
    ('RECESO_CLASES_CANCELADAS_DOCENTE', 'clases',        N'Clases canceladas del docente ese día (asignatura, grupo y hora), separadas por punto y coma', N'Ingeniería de Software, G01, 08:00 a 10:00; Bases de Datos, G02, 10:00 a 12:00', 1)
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
    ('RECESO_CLASES_CANCELADAS_ESTUDIANTE', 'es', 1,
     N'Clases canceladas por receso académico ({fecha})',
     N'Hola {estudiante}. La institución declaró receso académico el {fecha}. Motivo: {motivo}. Estas clases quedaron canceladas y no cuentan como inasistencia: {clases}.',
     1),
    ('RECESO_CLASES_CANCELADAS_DOCENTE', 'es', 1,
     N'Clases canceladas por receso académico ({fecha})',
     N'Hola {docente}. La institución declaró receso académico el {fecha}. Motivo: {motivo}. Estas clases suyas quedaron canceladas y no requieren toma de asistencia: {clases}.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
