USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.9): plantillas de notificacion de la cancelacion por inasistencia. Patron 34_plantilla_sesion_cancelada.sql.
-- Marcadores: MERGE idempotente. Plantillas nuevas: solo se insertan (no pisan ediciones del administrador). Las dos ALERTA_*
-- existentes pasan a {umbral}/{limite} unicamente si conservan el texto por defecto anterior (SUPUESTO-C-16).
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('ALERTA_RIESGO_INASISTENCIA',  'limite',      N'Límite reglamentario de pérdida por inasistencia', N'20', 0),
    ('REVISION_CANCELACION_PENDIENTE', 'docente',     N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('REVISION_CANCELACION_PENDIENTE', 'estudiante',  N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('REVISION_CANCELACION_PENDIENTE', 'grupo',       N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('REVISION_CANCELACION_PENDIENTE', 'porcentaje',  N'Porcentaje de inasistencia acumulado', N'21.5', 1),
    ('REVISION_CANCELACION_PENDIENTE', 'limite',      N'Límite reglamentario de pérdida por inasistencia', N'20', 0),
    ('PROPUESTA_CANCELACION', 'resolutor',    N'Nombre completo de quien resuelve', N'Ana Gómez', 1),
    ('PROPUESTA_CANCELACION', 'estudiante',   N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('PROPUESTA_CANCELACION', 'grupo',        N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('PROPUESTA_CANCELACION', 'docente',      N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('PROPUESTA_CANCELACION', 'porcentaje',   N'Porcentaje de inasistencia acumulado', N'21.5', 1),
    ('PROPUESTA_CANCELACION', 'limite',       N'Límite reglamentario de pérdida por inasistencia', N'20', 0),
    ('PROPUESTA_CANCELACION', 'motivo',       N'Motivo registrado por el docente', N'Sin asistencia en las últimas semanas', 1),
    ('PROPUESTA_CANCELACION', 'escalamiento', N'Texto que explica la asignación a la decanatura (vacío si no aplica)', N'', 0),
    ('CANCELACION_APROBADA', 'destinatario',  N'Nombre completo de quien recibe el correo', N'Juan Pérez', 1),
    ('CANCELACION_APROBADA', 'estudiante',    N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('CANCELACION_APROBADA', 'grupo',         N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('CANCELACION_APROBADA', 'porcentaje',    N'Porcentaje de inasistencia acumulado', N'21.5', 1),
    ('CANCELACION_APROBADA', 'motivo',        N'Motivo de la resolución', N'Pérdida por inasistencia', 1),
    ('CANCELACION_APROBADA', 'resolutor',     N'Nombre completo de quien resolvió', N'Ana Gómez', 1),
    ('CANCELACION_RECHAZADA', 'docente',      N'Nombre completo del docente titular', N'María Rostagno', 1),
    ('CANCELACION_RECHAZADA', 'estudiante',   N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('CANCELACION_RECHAZADA', 'grupo',        N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('CANCELACION_RECHAZADA', 'motivo',       N'Motivo de la resolución', N'Se acepta una justificación', 1),
    ('CANCELACION_RECHAZADA', 'resolutor',    N'Nombre completo de quien resolvió', N'Ana Gómez', 1)
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
    ('REVISION_CANCELACION_PENDIENTE', 'es', 1,
     N'Revisión de cancelación pendiente: {estudiante} en {grupo}',
     N'Hola {docente}. El estudiante {estudiante} alcanzó el {porcentaje}% de inasistencia en {grupo} (límite {limite}%). Revisa el caso desde la planilla del grupo: puedes mantenerlo o proponer su cancelación con un motivo.',
     1),
    ('PROPUESTA_CANCELACION', 'es', 1,
     N'Propuesta de cancelación por inasistencia: {estudiante} en {grupo}',
     N'Hola {resolutor}. El docente {docente} propone cancelar por inasistencia a {estudiante} en {grupo}: {porcentaje}% de inasistencia (límite {limite}%). Motivo: {motivo}. {escalamiento}',
     1),
    ('CANCELACION_APROBADA', 'es', 1,
     N'Cancelación por inasistencia en {grupo}',
     N'Hola {destinatario}. Se aprobó la cancelación por inasistencia de {estudiante} en {grupo} ({porcentaje}% de inasistencia). Motivo: {motivo}. Resolvió: {resolutor}.',
     1),
    ('CANCELACION_RECHAZADA', 'es', 1,
     N'Propuesta de cancelación rechazada: {estudiante} en {grupo}',
     N'Hola {docente}. Se rechazó la propuesta de cancelación de {estudiante} en {grupo}; el estudiante sigue activo. Motivo: {motivo}. Resolvió: {resolutor}.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO

-- SUPUESTO-C-16: cuerpo de las ALERTA_* a {umbral}/{limite} solo si conserva el texto por defecto de 26_plantillas_notificacion.sql.
UPDATE [dbo].[PlantillaNotificacion]
SET cuerpo = N'Estimado(a) {estudiante}, se informa que acumula un {porcentaje}% de inasistencias en la asignatura {grupo}. Le recordamos que el límite institucional de inasistencia no justificada es del {limite}%.'
WHERE tipo = 'ALERTA_RIESGO_INASISTENCIA' AND idioma = 'es' AND version = 1
  AND cuerpo = N'Estimado(a) {estudiante}, se informa que acumula un {porcentaje}% de inasistencias en la asignatura {grupo}. Le recordamos que el límite institucional de inasistencia no justificada es del 20%.';
GO
UPDATE [dbo].[PlantillaNotificacion]
SET cuerpo = N'Estimado(a) {estudiante}, se informa que ha alcanzado el {porcentaje}% de inasistencias en la asignatura {grupo}, superando el límite institucional permitido del {limite}%. Por favor contacte a su docente o coordinación académica.'
WHERE tipo = 'ALERTA_PERDIDA_INASISTENCIA' AND idioma = 'es' AND version = 1
  AND cuerpo = N'Estimado(a) {estudiante}, se informa que ha alcanzado el {porcentaje}% de inasistencias en la asignatura {grupo}, superando el límite institucional permitido. Por favor contacte a su docente o coordinación académica.';
GO
