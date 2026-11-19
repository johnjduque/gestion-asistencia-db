USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- NOTOMA-001: parametros del aviso al coordinador de la sesion sin toma de asistencia (grupo AVISO_SESION_SIN_TOMA). Sin fila en
-- CatalogoParametroEdicion: no son editables por el administrador. Idempotente y sin pisar el valor administrado (WHEN MATCHED solo
-- actualiza tipoDato y valorDefecto).
--   HABILITADO             apaga el aviso sin desplegar (false => usp_consultar_sesiones_pendientes_aviso_sin_toma devuelve 0 filas).
--   LOTE                   maximo de sesiones por pasada del job.
--   HORAS_MAXIMAS_ATRASO   no se avisan sesiones cuya ventana cerro hace mas de N horas (evita correos masivos al desplegar o recargar datos).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('AVISO_SESION_SIN_TOMA', 'HABILITADO',           N'true', 'BOOLEAN', N'true'),
    ('AVISO_SESION_SIN_TOMA', 'LOTE',                 N'50',   'INT',     N'50'),
    ('AVISO_SESION_SIN_TOMA', 'HORAS_MAXIMAS_ATRASO', N'24',   'INT',     N'24')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- NOTOMA-001: plantilla del aviso a la coordinacion cuando el docente no tomo asistencia en una sesion (un correo por coordinador y sesion).
-- Patron 67_ata_plantilla_falta_sesion.sql: MERGE idempotente; la version 1 la crea el sistema (creadoPor NULL). El mismo texto por defecto
-- vive en notification/templates/SESION_SIN_TOMA_COORDINADOR.es.properties del backend.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('SESION_SIN_TOMA_COORDINADOR', 'coordinador',    N'Nombre completo del coordinador destinatario', N'Laura Martínez', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'asignatura',     N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'grupo',          N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'fecha',          N'Fecha de la sesión (hora institucional)', N'10/11/2026', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'horaInicio',     N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'horaFin',        N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'docente',        N'Nombre completo del docente titular del grupo', N'María Gómez', 1),
    ('SESION_SIN_TOMA_COORDINADOR', 'enlaceSesiones', N'Enlace a la consulta de asistencia del coordinador en la plataforma', N'https://asistencia.uco.edu.co/app/coordinador/asistencia', 1)
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
    ('SESION_SIN_TOMA_COORDINADOR', 'es', 1,
     N'Sesión sin toma de asistencia: {asignatura} ({fecha})',
     N'Hola {coordinador}. El docente {docente} no tomó asistencia en la sesión de {asignatura} del grupo {grupo} del {fecha} de {horaInicio} a {horaFin}. Este aviso es solo informativo; puede revisar el grupo en {enlaceSesiones}.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
