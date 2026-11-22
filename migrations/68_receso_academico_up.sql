-- ============================================================================
-- MIGRACION UP 68: DEC-081 - receso academico del periodo
--   Decisiones del responsable (2026-11-21): un periodo puede tener dias de receso academico (un dia completo sin clase para toda la
--   institucion; un dia por registro con fecha y motivo). Al registrarlo se cancelan de inmediato las sesiones de ese dia en todos los grupos
--   del periodo; los grupos nuevos las crean canceladas. Un dia aplicado (que cancelo sesiones) no se retira.
--   1. Tabla dbo.PeriodoRecesoAcademico (indice unico filtrado periodo+fecha activos), columna dbo.SesionCancelacion.recesoAcademico (FK,
--      indice filtrado) y CK_SesionCancelacion_origen ampliado (diaFestivo, recesoAcademico o usuarioEjecutor).
--   2. dbo.TipoCancelacionSesion: se retira UQ_TipoCancelacionSesion_esAutomatica (impedia dos tipos automaticos) y se siembra RECESO
--      (id fijo ...0003, esAutomatica = 1). El tipo FESTIVO ahora se resuelve por codigo (SESION/CODIGO_TIPO_CANCELACION_FESTIVO).
--   3. Parametros RECESO/* y SESION/CODIGO_TIPO_CANCELACION_FESTIVO; mensajes REC_001..REC_011; plantillas RECESO_CLASES_CANCELADAS_ESTUDIANTE y
--      RECESO_CLASES_CANCELADAS_DOCENTE (con sus marcadores).
--   Los cuerpos de vistas y SP (uv_periodo_receso_academico, usp_crear/retirar_receso_academico, usp_consultar_recesos_periodo,
--   usp_consultar_destinatarios_receso_academico, usp_validar_receso_academico_interno, usp_internal_cancelar_sesiones_receso y los cambios en
--   usp_internal_aplicar_festivos_grupo, usp_precargar_sesiones_grupo_interno, usp_generar_sesiones_grupo_v2 y usp_previsualizar_horario_grupo)
--   y los permisos del rol runtime se despliegan con deploy_schema.ps1 (CREATE OR ALTER).
-- Idempotente. Down: 68_receso_academico_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 68 UP: receso academico del periodo';
GO
IF OBJECT_ID('dbo.[PeriodoRecesoAcademico]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PeriodoRecesoAcademico (
        id                 UNIQUEIDENTIFIER NOT NULL,
        periodoAcademico   UNIQUEIDENTIFIER NOT NULL,
        fecha              DATE             NOT NULL,
        motivo             NVARCHAR(200)    NOT NULL,
        estaActivo         BIT              NOT NULL CONSTRAINT DF_PeriodoRecesoAcademico_estaActivo DEFAULT 1,
        fechaCreacionUtc   DATETIME2(0)     NOT NULL CONSTRAINT DF_PeriodoRecesoAcademico_fecha DEFAULT SYSUTCDATETIME(),
        usuarioCreador     UNIQUEIDENTIFIER NOT NULL,
        idCorrelacion      UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_PeriodoRecesoAcademico PRIMARY KEY CLUSTERED (id),
        CONSTRAINT CK_PeriodoRecesoAcademico_motivo CHECK (LEN(LTRIM(RTRIM(motivo))) > 0)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.PeriodoRecesoAcademico') AND name = 'UX_PeriodoRecesoAcademico_periodo_fecha')
    CREATE UNIQUE NONCLUSTERED INDEX UX_PeriodoRecesoAcademico_periodo_fecha
    ON dbo.PeriodoRecesoAcademico (periodoAcademico, fecha) WHERE estaActivo = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_PeriodoRecesoAcademico_PeriodoAcademico')
    ALTER TABLE [dbo].[PeriodoRecesoAcademico] ADD CONSTRAINT [FK_PeriodoRecesoAcademico_PeriodoAcademico] FOREIGN KEY ([periodoAcademico]) REFERENCES [dbo].[PeriodoAcademico] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_PeriodoRecesoAcademico_Usuario')
    ALTER TABLE [dbo].[PeriodoRecesoAcademico] ADD CONSTRAINT [FK_PeriodoRecesoAcademico_Usuario] FOREIGN KEY ([usuarioCreador]) REFERENCES [dbo].[Usuario] ([id]);
GO
IF COL_LENGTH('dbo.SesionCancelacion', 'recesoAcademico') IS NULL
    ALTER TABLE dbo.SesionCancelacion ADD recesoAcademico UNIQUEIDENTIFIER NULL;
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SesionCancelacion_origen' AND parent_object_id = OBJECT_ID('dbo.SesionCancelacion')
           AND definition NOT LIKE N'%recesoAcademico%')
    ALTER TABLE dbo.SesionCancelacion DROP CONSTRAINT CK_SesionCancelacion_origen;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SesionCancelacion_origen' AND parent_object_id = OBJECT_ID('dbo.SesionCancelacion'))
    ALTER TABLE dbo.SesionCancelacion ADD CONSTRAINT CK_SesionCancelacion_origen
        CHECK (diaFestivo IS NOT NULL OR recesoAcademico IS NOT NULL OR usuarioEjecutor IS NOT NULL);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SesionCancelacion') AND name = 'IX_SesionCancelacion_recesoAcademico')
    CREATE NONCLUSTERED INDEX IX_SesionCancelacion_recesoAcademico ON dbo.SesionCancelacion (recesoAcademico) WHERE recesoAcademico IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SesionCancelacion_PeriodoRecesoAcademico')
    ALTER TABLE [dbo].[SesionCancelacion] ADD CONSTRAINT [FK_SesionCancelacion_PeriodoRecesoAcademico] FOREIGN KEY ([recesoAcademico]) REFERENCES [dbo].[PeriodoRecesoAcademico] ([id]);
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_TipoCancelacionSesion_esAutomatica' AND parent_object_id = OBJECT_ID('dbo.TipoCancelacionSesion'))
    ALTER TABLE dbo.TipoCancelacionSesion DROP CONSTRAINT UQ_TipoCancelacionSesion_esAutomatica;
GO
MERGE INTO [dbo].[TipoCancelacionSesion] AS Target
USING (VALUES
    (CAST('7C1E0B10-5E51-4C0A-9A01-000000000003' AS UNIQUEIDENTIFIER), N'RECESO', N'Receso académico', CAST(1 AS BIT))
) AS Source (id, codigo, nombre, esAutomatica)
ON (Target.id = Source.id)
WHEN MATCHED THEN
    UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.esAutomatica = Source.esAutomatica
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, esAutomatica)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.esAutomatica);
GO
-- DEC-081 (2026-11-21): parametros del receso academico y del tipo de cancelacion por festivo. Patron 34_parametros_sesion_festivos.sql:
-- idempotente y sin pisar el valor administrado (WHEN MATCHED solo actualiza tipoDato y valorDefecto). 
--   RECESO/PREFIJO_MOTIVO_CANCELACION: prefijo del motivo de la cancelacion automatica (motivo final = prefijo + motivo del receso).
--   RECESO/CODIGO_TIPO_CANCELACION y SESION/CODIGO_TIPO_CANCELACION_FESTIVO: codigo de TipoCancelacionSesion con que cada mecanismo
--   automatico cancela sus sesiones (ya no se distingue por esAutomatica = 1, que ahora cubre dos tipos).
--   RECESO/MOTIVO_LONGITUD_MAXIMA: largo maximo del motivo (PeriodoRecesoAcademico.motivo es NVARCHAR(200)).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('RECESO',   'PREFIJO_MOTIVO_CANCELACION', N'Receso académico: ', 'STRING', N'Receso académico: '),
    ('RECESO',   'CODIGO_TIPO_CANCELACION',    N'RECESO',             'STRING', N'RECESO'),
    ('RECESO',   'MOTIVO_LONGITUD_MAXIMA',     N'200',                'INT',    N'200'),
    ('SESION',   'CODIGO_TIPO_CANCELACION_FESTIVO', N'FESTIVO',       'STRING', N'FESTIVO')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- DEC-081 (2026-11-21): mensajes del receso academico del periodo. Idempotente (MERGE por codigo). 
--   REC_001 exito al crear (fecha, clases canceladas)      REC_002 exito al retirar (fecha)
--   REC_003 fecha fuera del periodo (inicio, fin)          REC_004 fecha de hoy o pasada (fecha, hoy)
--   REC_005 la fecha es festivo (nombre)                   REC_006 fecha repetida en el periodo
--   REC_007 periodo cerrado (nombre)                       REC_008 motivo vacio o largo (maximo)
--   REC_009 receso inexistente o ya retirado               REC_010 ya cancelo sesiones: no se retira (n)
--   REC_011 informativo de la previsualizacion del horario (horas, sesiones)
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('REC_001', 'SUCCESS', 'BAJO', N'Se registró el receso académico del {}; se cancelaron {} clases.'),
    ('REC_002', 'SUCCESS', 'BAJO', N'Se retiró el receso académico del {}.'),
    ('REC_003', 'VALIDATION_ERROR', 'BAJO', N'La fecha del receso debe estar dentro del período académico, del {} al {}.'),
    ('REC_004', 'VALIDATION_ERROR', 'BAJO', N'La fecha del receso debe ser posterior a hoy; elige una fecha desde mañana.'),
    ('REC_005', 'BUSINESS_ERROR', 'MEDIO', N'Ese día ya es festivo ({}); no necesita receso académico.'),
    ('REC_006', 'BUSINESS_ERROR', 'MEDIO', N'Ya hay un receso académico registrado para esa fecha en este período.'),
    ('REC_007', 'BUSINESS_ERROR', 'MEDIO', N'El período académico {} está cerrado; no se pueden registrar ni retirar días de receso.'),
    ('REC_008', 'VALIDATION_ERROR', 'BAJO', N'El motivo del receso es obligatorio y puede tener hasta {} caracteres.'),
    ('REC_009', 'BUSINESS_ERROR', 'MEDIO', N'El día de receso académico no existe o ya fue retirado.'),
    ('REC_010', 'BUSINESS_ERROR', 'MEDIO', N'Este día de receso ya canceló {} clases y no se puede retirar ni cambiar.'),
    ('REC_011', 'INFORMATIVO', 'BAJO', N'{} h caen en días de receso académico ({} sesión(es)); esas sesiones quedan canceladas.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('REC_001', 'SUCCESS', 'BAJO', N'Receso academico [{}] creado. Sesiones canceladas: {}. Sesiones con asistencia que no se tocaron: {}.'),
    ('REC_002', 'SUCCESS', 'BAJO', N'Receso academico [{}] retirado (estaActivo = 0); no habia cancelado ninguna sesion.'),
    ('REC_003', 'VALIDATION_ERROR', 'BAJO', N'Fecha del receso fuera de PeriodoAcademico.fechaInicio..fechaFin ({}..{}).'),
    ('REC_004', 'VALIDATION_ERROR', 'BAJO', N'Fecha del receso [{}] no es posterior a la fecha local institucional de hoy [{}] (TIEMPO/ZONA_HORARIA_SQLSERVER).'),
    ('REC_005', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la fecha coincide con un DiaFestivo activo ({}); un receso en un festivo es redundante.'),
    ('REC_006', 'BUSINESS_ERROR', 'MEDIO', N'Unicidad: ya existe un PeriodoRecesoAcademico activo para el periodo y la fecha [{}].'),
    ('REC_007', 'BUSINESS_ERROR', 'MEDIO', N'Regla: PeriodoAcademico.fechaCierreUtc no es nula (periodo [{}] cerrado).'),
    ('REC_008', 'VALIDATION_ERROR', 'BAJO', N'Validacion: motivo vacio o mayor que RECESO/MOTIVO_LONGITUD_MAXIMA ({}).'),
    ('REC_009', 'BUSINESS_ERROR', 'MEDIO', N'Existencia: no hay PeriodoRecesoAcademico activo con el id [{}] en la institucion del ejecutor.'),
    ('REC_010', 'BUSINESS_ERROR', 'MEDIO', N'Regla: el receso tiene {} SesionCancelacion enlazadas; el retiro se rechaza sin escrituras.'),
    ('REC_011', 'INFORMATIVO', 'BAJO', N'Horas perdidas por receso academico: {} h en {} sesion(es).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- DEC-081 (2026-11-21): plantillas del aviso de clases canceladas por un dia de receso academico (un correo por persona con el resumen
-- de sus clases canceladas). Patron 60_sesiones_manuales_plantillas.sql (MERGE idempotente; version 1 creada por el sistema; no pisa
-- ediciones del administrador). El mismo texto por defecto vive en los recursos de plantillas del backend. 
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
PRINT 'MIGRACION 68 UP OK (ejecute deploy_schema.ps1 para los cuerpos de vistas y SP y los permisos)';
GO
