USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 C.1 - Migracion 19 UP: cancelacion por inasistencia (HU026C) (CONTRACT §2.11, SUPUESTO-C-15).
-- Idempotente. Cubre el cambio de estructura y los catalogos de una BD existente; los SP, las semillas de parametros / mensajes /
-- plantillas, el cambio de usp_ejecutar_cierre_masivo_periodo y de usp_consultar_resumen_asistencia_grupo_docente_paginado y los
-- permisos de EXECUTE los despliega deploy_schema.ps1 (CREATE OR ALTER / MERGE). No evalua alertas: el primer pase del job lo hace.
--   0. Precondiciones (O-12): B.2 (tomas, horas) y B2 (asignatura-plan N:M, funciones de programas) aplicados; aborta con 50019.
--   1. Catalogos con sus filas (MERGE por id), tablas con indices y FKs, funciones y vistas de C, GRANT SELECT condicionados.
--   2. Resultset de control: catalogosCreados, transiciones (= 6), matriculasEnPerdidaSinRevision (solo reporte).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
-- 0. Precondiciones (O-12)
IF OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NULL OR OBJECT_ID(N'dbo.uv_asistencia_sesion_horas', N'V') IS NULL
   OR OBJECT_ID(N'dbo.AsignaturaPlanEstudio', N'U') IS NULL OR OBJECT_ID(N'dbo.ufn_programas_grupo') IS NULL
   OR OBJECT_ID(N'dbo.ufn_programas_ambito_ejecutor') IS NULL
   OR COL_LENGTH('dbo.uv_resumen_asistencia_estudiante_grupo', 'idPrograma') IS NOT NULL
    THROW 50019, 'CULM-001 C.1 migracion 19: faltan B.2 o B2 (TomaAsistencia, uv_asistencia_sesion_horas, AsignaturaPlanEstudio, ufn_programas_grupo, ufn_programas_ambito_ejecutor) o el resumen aun tiene idPrograma. Aplique las migraciones 16, 17 y 18 antes.', 1;
GO
-- ---------------------------------------------------------------------------------------------------------------
-- 1. Tablas de catalogo y de datos
-- ---------------------------------------------------------------------------------------------------------------
-- schema/tables/TipoAlertaInasistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): tipo de alerta de inasistencia (ADVERTENCIA | PERDIDA).
IF OBJECT_ID('dbo.[TipoAlertaInasistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TipoAlertaInasistencia (
        id                       UNIQUEIDENTIFIER NOT NULL,
        codigo                   NVARCHAR(20)     NOT NULL,
        nombre                   NVARCHAR(50)     NOT NULL,
        nivel                    TINYINT          NOT NULL,
        grupoParametroUmbral     VARCHAR(100)     NOT NULL,
        claveParametroUmbral     VARCHAR(100)     NOT NULL,
        tipoPlantillaEstudiante  VARCHAR(60)      NOT NULL,
        codigoMensajeUsuario     VARCHAR(100)     NOT NULL,
        creaRevisionCancelacion  BIT              NOT NULL,
        CONSTRAINT PK_TipoAlertaInasistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TipoAlertaInasistencia_codigo UNIQUE (codigo),
        CONSTRAINT UQ_TipoAlertaInasistencia_nivel UNIQUE (nivel)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TipoAlertaInasistencia') AND name = 'UX_TipoAlertaInasistencia_creaRevision')
    CREATE UNIQUE INDEX UX_TipoAlertaInasistencia_creaRevision ON dbo.TipoAlertaInasistencia (creaRevisionCancelacion) WHERE creaRevisionCancelacion = 1;
GO

-- schema/tables/EstadoAlertaInasistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): estado de una alerta de inasistencia (VIGENTE | SUPERADA), resuelto por estaVigente (unica).
IF OBJECT_ID('dbo.[EstadoAlertaInasistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EstadoAlertaInasistencia (
        id          UNIQUEIDENTIFIER NOT NULL,
        codigo      NVARCHAR(20)     NOT NULL,
        nombre      NVARCHAR(50)     NOT NULL,
        estaVigente BIT              NOT NULL,
        CONSTRAINT PK_EstadoAlertaInasistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_EstadoAlertaInasistencia_codigo UNIQUE (codigo),
        CONSTRAINT UQ_EstadoAlertaInasistencia_estaVigente UNIQUE (estaVigente)
    );
END
GO

-- schema/tables/EstadoRevisionCancelacion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): estados de la revision de cancelacion por inasistencia. Los SP resuelven por banderas, no por codigo.
IF OBJECT_ID('dbo.[EstadoRevisionCancelacion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EstadoRevisionCancelacion (
        id                       UNIQUEIDENTIFIER NOT NULL,
        codigo                   NVARCHAR(20)     NOT NULL,
        nombre                   NVARCHAR(60)     NOT NULL,
        orden                    TINYINT          NOT NULL,
        esInicial                BIT              NOT NULL,
        requiereAccionDocente    BIT              NOT NULL,
        requiereAccionResolutor  BIT              NOT NULL,
        conservaMatricula        BIT              NOT NULL,
        cancelaMatricula         BIT              NOT NULL,
        esFinal                  BIT              NOT NULL,
        CONSTRAINT PK_EstadoRevisionCancelacion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_EstadoRevisionCancelacion_codigo UNIQUE (codigo),
        CONSTRAINT CK_EstadoRevisionCancelacion_accion CHECK (NOT (requiereAccionDocente = 1 AND requiereAccionResolutor = 1))
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstadoRevisionCancelacion') AND name = 'UX_EstadoRevisionCancelacion_esInicial')
    CREATE UNIQUE INDEX UX_EstadoRevisionCancelacion_esInicial ON dbo.EstadoRevisionCancelacion (esInicial) WHERE esInicial = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.EstadoRevisionCancelacion') AND name = 'UX_EstadoRevisionCancelacion_cancela')
    CREATE UNIQUE INDEX UX_EstadoRevisionCancelacion_cancela ON dbo.EstadoRevisionCancelacion (cancelaMatricula) WHERE cancelaMatricula = 1;
GO

-- schema/tables/TransicionRevisionCancelacion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1, SUPUESTO-C-07): transiciones validas de la revision de cancelacion.
IF OBJECT_ID('dbo.[TransicionRevisionCancelacion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TransicionRevisionCancelacion (
        id                          UNIQUEIDENTIFIER NOT NULL,
        estadoOrigen                UNIQUEIDENTIFIER NOT NULL,
        codigoDecision              NVARCHAR(20)     NOT NULL,
        esDecisionResolutor         BIT              NOT NULL,
        estadoDestino               UNIQUEIDENTIFIER NOT NULL,
        exigeUmbralPerdida          BIT              NOT NULL,
        exigeResolutorDisponible    BIT              NOT NULL,
        codigoMensajeExito          VARCHAR(100)     NOT NULL,
        tipoPlantillaNotificacion   VARCHAR(60)      NULL,
        CONSTRAINT PK_TransicionRevisionCancelacion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TransicionRevisionCancelacion_origen_decision UNIQUE (estadoOrigen, codigoDecision)
    );
END
GO

-- schema/tables/AlertaInasistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.2): alerta de inasistencia. Una fila por (matricula, tipo); VIGENTE | SUPERADA. fechaLecturaUtc es de C.2.
IF OBJECT_ID('dbo.[AlertaInasistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AlertaInasistencia (
        id                          UNIQUEIDENTIFIER NOT NULL,
        estudianteGrupo             UNIQUEIDENTIFIER NOT NULL,
        tipo                        UNIQUEIDENTIFIER NOT NULL,
        estado                      UNIQUEIDENTIFIER NOT NULL,
        porcentajeCruce             DECIMAL(5,2)     NOT NULL,
        umbralCruce                 DECIMAL(5,2)     NOT NULL,
        horasFaltaCruce             DECIMAL(12,6)    NOT NULL,
        horasDictadasCruce          DECIMAL(12,6)    NOT NULL,
        fechaCruceUtc               DATETIME2(3)     NOT NULL,
        idCorrelacionCruce          UNIQUEIDENTIFIER NOT NULL,
        porcentajeUltimaEvaluacion  DECIMAL(5,2)     NOT NULL,
        fechaUltimaEvaluacionUtc    DATETIME2(3)     NOT NULL,
        fechaLecturaUtc             DATETIME2(3)     NULL,
        CONSTRAINT PK_AlertaInasistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT CK_AlertaInasistencia_porcentajes CHECK (porcentajeCruce BETWEEN 0 AND 100 AND porcentajeUltimaEvaluacion BETWEEN 0 AND 100)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.AlertaInasistencia') AND name = 'UX_AlertaInasistencia_EstudianteGrupo_Tipo')
    CREATE UNIQUE INDEX UX_AlertaInasistencia_EstudianteGrupo_Tipo ON dbo.AlertaInasistencia (estudianteGrupo, tipo);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.AlertaInasistencia') AND name = 'IX_AlertaInasistencia_noLeidas')
    CREATE INDEX IX_AlertaInasistencia_noLeidas ON dbo.AlertaInasistencia (estudianteGrupo) INCLUDE (fechaLecturaUtc, fechaCruceUtc);
GO

-- schema/tables/RevisionCancelacion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.2): revision de cancelacion por inasistencia. Una sola por matricula; la decide el docente titular y
-- la resuelve el coordinador del programa del estudiante o, por escalamiento, el decano (SUPUESTO-C-09).
IF OBJECT_ID('dbo.[RevisionCancelacion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.RevisionCancelacion (
        id                           UNIQUEIDENTIFIER NOT NULL,
        estudianteGrupo              UNIQUEIDENTIFIER NOT NULL,
        estado                       UNIQUEIDENTIFIER NOT NULL,
        alertaOrigen                 UNIQUEIDENTIFIER NOT NULL,
        porcentajeCreacion           DECIMAL(5,2)     NOT NULL,
        horasFaltaCreacion           DECIMAL(12,6)    NOT NULL,
        horasDictadasCreacion        DECIMAL(12,6)    NOT NULL,
        fechaCreacionUtc             DATETIME2(3)     NOT NULL,
        idCorrelacionCreacion        UNIQUEIDENTIFIER NOT NULL,
        codigoDecisionDocente        NVARCHAR(20)     NULL,
        motivoDocente                NVARCHAR(1000)   NULL,
        usuarioDecisionDocente       UNIQUEIDENTIFIER NULL,
        porcentajeDecisionDocente    DECIMAL(5,2)     NULL,
        fechaDecisionDocenteUtc      DATETIME2(3)     NULL,
        codigoPerfilResolutorActual  NVARCHAR(20)     NULL,
        huellaResolutoresActual      VARBINARY(32)    NULL,
        fechaEscalamientoUtc         DATETIME2(3)     NULL,
        codigoDecisionResolucion     NVARCHAR(20)     NULL,
        motivoResolucion             NVARCHAR(1000)   NULL,
        usuarioResolucion            UNIQUEIDENTIFIER NULL,
        codigoPerfilResolucion       NVARCHAR(20)     NULL,
        programaResolucion           UNIQUEIDENTIFIER NULL,
        porcentajeResolucion         DECIMAL(5,2)     NULL,
        fechaResolucionUtc           DATETIME2(3)     NULL,
        estadoMatriculaAnterior      UNIQUEIDENTIFIER NULL,
        fechaActualizacionUtc        DATETIME2(3)     NOT NULL,
        CONSTRAINT PK_RevisionCancelacion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_RevisionCancelacion_EstudianteGrupo UNIQUE (estudianteGrupo)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.RevisionCancelacion') AND name = 'IX_RevisionCancelacion_estado')
    CREATE INDEX IX_RevisionCancelacion_estado ON dbo.RevisionCancelacion (estado) INCLUDE (estudianteGrupo, fechaCreacionUtc);
GO

-- schema/tables/RevisionCancelacionHistorial.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.2, O-14): trazabilidad de cada transicion de una revision (sin vista de consulta en C).
IF OBJECT_ID('dbo.[RevisionCancelacionHistorial]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.RevisionCancelacionHistorial (
        id                      UNIQUEIDENTIFIER NOT NULL,
        revision                UNIQUEIDENTIFIER NOT NULL,
        estadoAnterior          UNIQUEIDENTIFIER NULL,
        estadoNuevo             UNIQUEIDENTIFIER NOT NULL,
        codigoEvento            NVARCHAR(20)     NOT NULL,
        motivo                  NVARCHAR(1000)   NULL,
        usuarioActor            UNIQUEIDENTIFIER NULL,
        codigoPerfilActor       NVARCHAR(20)     NULL,
        codigoPerfilResolutor   NVARCHAR(20)     NULL,
        porcentajeInasistencia  DECIMAL(5,2)     NOT NULL,
        fechaUtc                DATETIME2(3)     NOT NULL,
        idCorrelacion           UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_RevisionCancelacionHistorial PRIMARY KEY CLUSTERED (id)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.RevisionCancelacionHistorial') AND name = 'IX_RevisionCancelacionHistorial_revision')
    CREATE INDEX IX_RevisionCancelacionHistorial_revision ON dbo.RevisionCancelacionHistorial (revision, fechaUtc);
GO

-- schema/tables/EvaluacionAlertaGrupo.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.2, SUPUESTO-C-03, O-8): marca de agua de la evaluacion de alertas por grupo (instante de corte
-- capturado al INICIO de la evaluacion). Serializa las evaluaciones de un mismo grupo.
IF OBJECT_ID('dbo.[EvaluacionAlertaGrupo]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EvaluacionAlertaGrupo (
        grupo                UNIQUEIDENTIFIER NOT NULL,
        fechaCorteUtc        DATETIME2(3)     NOT NULL,
        idCorrelacionUltima  UNIQUEIDENTIFIER NOT NULL,
        totalEvaluaciones    INT              NOT NULL CONSTRAINT DF_EvaluacionAlertaGrupo_total DEFAULT (0),
        CONSTRAINT PK_EvaluacionAlertaGrupo PRIMARY KEY CLUSTERED (grupo)
    );
END
GO

-- schema/tables/zz_foreign_keys.sql (claves foraneas de C)
-- CULM-001 C.1 (CONTRACT §2.2): claves foraneas de alertas y revisiones de cancelacion por inasistencia.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_AlertaInasistencia_EstudianteGrupo')
    ALTER TABLE [dbo].[AlertaInasistencia] ADD CONSTRAINT [FK_AlertaInasistencia_EstudianteGrupo] FOREIGN KEY ([estudianteGrupo]) REFERENCES [dbo].[EstudianteGrupo] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_AlertaInasistencia_Tipo')
    ALTER TABLE [dbo].[AlertaInasistencia] ADD CONSTRAINT [FK_AlertaInasistencia_Tipo] FOREIGN KEY ([tipo]) REFERENCES [dbo].[TipoAlertaInasistencia] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_AlertaInasistencia_Estado')
    ALTER TABLE [dbo].[AlertaInasistencia] ADD CONSTRAINT [FK_AlertaInasistencia_Estado] FOREIGN KEY ([estado]) REFERENCES [dbo].[EstadoAlertaInasistencia] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_RevisionCancelacion_EstudianteGrupo')
    ALTER TABLE [dbo].[RevisionCancelacion] ADD CONSTRAINT [FK_RevisionCancelacion_EstudianteGrupo] FOREIGN KEY ([estudianteGrupo]) REFERENCES [dbo].[EstudianteGrupo] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_RevisionCancelacion_Estado')
    ALTER TABLE [dbo].[RevisionCancelacion] ADD CONSTRAINT [FK_RevisionCancelacion_Estado] FOREIGN KEY ([estado]) REFERENCES [dbo].[EstadoRevisionCancelacion] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_RevisionCancelacion_AlertaOrigen')
    ALTER TABLE [dbo].[RevisionCancelacion] ADD CONSTRAINT [FK_RevisionCancelacion_AlertaOrigen] FOREIGN KEY ([alertaOrigen]) REFERENCES [dbo].[AlertaInasistencia] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_RevisionCancelacion_UsuarioDecisionDocente')
    ALTER TABLE [dbo].[RevisionCancelacion] ADD CONSTRAINT [FK_RevisionCancelacion_UsuarioDecisionDocente] FOREIGN KEY ([usuarioDecisionDocente]) REFERENCES [dbo].[Usuario] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_RevisionCancelacion_UsuarioResolucion')
    ALTER TABLE [dbo].[RevisionCancelacion] ADD CONSTRAINT [FK_RevisionCancelacion_UsuarioResolucion] FOREIGN KEY ([usuarioResolucion]) REFERENCES [dbo].[Usuario] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_RevisionCancelacion_ProgramaResolucion')
    ALTER TABLE [dbo].[RevisionCancelacion] ADD CONSTRAINT [FK_RevisionCancelacion_ProgramaResolucion] FOREIGN KEY ([programaResolucion]) REFERENCES [dbo].[Programa] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_RevisionCancelacion_EstadoMatriculaAnterior')
    ALTER TABLE [dbo].[RevisionCancelacion] ADD CONSTRAINT [FK_RevisionCancelacion_EstadoMatriculaAnterior] FOREIGN KEY ([estadoMatriculaAnterior]) REFERENCES [dbo].[EstadoEstudianteGrupo] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_RevisionCancelacionHistorial_Revision')
    ALTER TABLE [dbo].[RevisionCancelacionHistorial] ADD CONSTRAINT [FK_RevisionCancelacionHistorial_Revision] FOREIGN KEY ([revision]) REFERENCES [dbo].[RevisionCancelacion] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_RevisionCancelacionHistorial_EstadoNuevo')
    ALTER TABLE [dbo].[RevisionCancelacionHistorial] ADD CONSTRAINT [FK_RevisionCancelacionHistorial_EstadoNuevo] FOREIGN KEY ([estadoNuevo]) REFERENCES [dbo].[EstadoRevisionCancelacion] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_RevisionCancelacionHistorial_UsuarioActor')
    ALTER TABLE [dbo].[RevisionCancelacionHistorial] ADD CONSTRAINT [FK_RevisionCancelacionHistorial_UsuarioActor] FOREIGN KEY ([usuarioActor]) REFERENCES [dbo].[Usuario] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_EvaluacionAlertaGrupo_Grupo')
    ALTER TABLE [dbo].[EvaluacionAlertaGrupo] ADD CONSTRAINT [FK_EvaluacionAlertaGrupo_Grupo] FOREIGN KEY ([grupo]) REFERENCES [dbo].[Grupo] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TransicionRevisionCancelacion_Origen')
    ALTER TABLE [dbo].[TransicionRevisionCancelacion] ADD CONSTRAINT [FK_TransicionRevisionCancelacion_Origen] FOREIGN KEY ([estadoOrigen]) REFERENCES [dbo].[EstadoRevisionCancelacion] ([id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TransicionRevisionCancelacion_Destino')
    ALTER TABLE [dbo].[TransicionRevisionCancelacion] ADD CONSTRAINT [FK_TransicionRevisionCancelacion_Destino] FOREIGN KEY ([estadoDestino]) REFERENCES [dbo].[EstadoRevisionCancelacion] ([id]);
GO

-- schema/seed/40_culm001_c_catalogos.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1, DEC-028): catalogos de alertas y revisiones de cancelacion por inasistencia. MERGE idempotente por id.
MERGE INTO [dbo].[TipoAlertaInasistencia] AS Target
USING (VALUES
    ('7C1E0C10-5E51-4C0A-9A01-000000000001', N'ADVERTENCIA', N'Riesgo de pérdida por inasistencia', 1, 'ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA', 'ALERTA_RIESGO_INASISTENCIA',  'ALR_010', 0),
    ('7C1E0C10-5E51-4C0A-9A01-000000000002', N'PERDIDA',     N'Pérdida por inasistencia',           2, 'ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA',     'ALERTA_PERDIDA_INASISTENCIA', 'ALR_011', 1)
) AS Source (id, codigo, nombre, nivel, grupoParametroUmbral, claveParametroUmbral, tipoPlantillaEstudiante, codigoMensajeUsuario, creaRevisionCancelacion)
ON (Target.id = Source.id)
WHEN MATCHED THEN UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.nivel = Source.nivel,
    Target.grupoParametroUmbral = Source.grupoParametroUmbral, Target.claveParametroUmbral = Source.claveParametroUmbral,
    Target.tipoPlantillaEstudiante = Source.tipoPlantillaEstudiante, Target.codigoMensajeUsuario = Source.codigoMensajeUsuario,
    Target.creaRevisionCancelacion = Source.creaRevisionCancelacion
WHEN NOT MATCHED THEN INSERT (id, codigo, nombre, nivel, grupoParametroUmbral, claveParametroUmbral, tipoPlantillaEstudiante, codigoMensajeUsuario, creaRevisionCancelacion)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.nivel, Source.grupoParametroUmbral, Source.claveParametroUmbral, Source.tipoPlantillaEstudiante, Source.codigoMensajeUsuario, Source.creaRevisionCancelacion);
GO

MERGE INTO [dbo].[EstadoAlertaInasistencia] AS Target
USING (VALUES
    ('7C1E0C20-5E51-4C0A-9A01-000000000001', N'VIGENTE',  N'Vigente',  1),
    ('7C1E0C20-5E51-4C0A-9A01-000000000002', N'SUPERADA', N'Superada', 0)
) AS Source (id, codigo, nombre, estaVigente)
ON (Target.id = Source.id)
WHEN MATCHED THEN UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.estaVigente = Source.estaVigente
WHEN NOT MATCHED THEN INSERT (id, codigo, nombre, estaVigente) VALUES (Source.id, Source.codigo, Source.nombre, Source.estaVigente);
GO

MERGE INTO [dbo].[EstadoRevisionCancelacion] AS Target
USING (VALUES
    ('7C1E0C30-5E51-4C0A-9A01-000000000001', N'PENDIENTE_DOCENTE', N'Pendiente de decisión del docente',   1, 1, 1, 0, 0, 0, 0),
    ('7C1E0C30-5E51-4C0A-9A01-000000000002', N'MANTENIDA',         N'Estudiante mantenido por el docente', 2, 0, 0, 0, 1, 0, 0),
    ('7C1E0C30-5E51-4C0A-9A01-000000000003', N'PROPUESTA',         N'Cancelación propuesta',               3, 0, 0, 1, 0, 0, 0),
    ('7C1E0C30-5E51-4C0A-9A01-000000000004', N'APROBADA',          N'Cancelación aprobada',                4, 0, 0, 0, 0, 1, 1),
    ('7C1E0C30-5E51-4C0A-9A01-000000000005', N'RECHAZADA',         N'Cancelación rechazada',               5, 0, 0, 0, 1, 0, 0)
) AS Source (id, codigo, nombre, orden, esInicial, requiereAccionDocente, requiereAccionResolutor, conservaMatricula, cancelaMatricula, esFinal)
ON (Target.id = Source.id)
WHEN MATCHED THEN UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.orden = Source.orden, Target.esInicial = Source.esInicial,
    Target.requiereAccionDocente = Source.requiereAccionDocente, Target.requiereAccionResolutor = Source.requiereAccionResolutor,
    Target.conservaMatricula = Source.conservaMatricula, Target.cancelaMatricula = Source.cancelaMatricula, Target.esFinal = Source.esFinal
WHEN NOT MATCHED THEN INSERT (id, codigo, nombre, orden, esInicial, requiereAccionDocente, requiereAccionResolutor, conservaMatricula, cancelaMatricula, esFinal)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.orden, Source.esInicial, Source.requiereAccionDocente, Source.requiereAccionResolutor, Source.conservaMatricula, Source.cancelaMatricula, Source.esFinal);
GO

MERGE INTO [dbo].[TransicionRevisionCancelacion] AS Target
USING (VALUES
    ('7C1E0C40-5E51-4C0A-9A01-000000000001', '7C1E0C30-5E51-4C0A-9A01-000000000001', N'MANTENER', 0, '7C1E0C30-5E51-4C0A-9A01-000000000002', 0, 0, 'RCN_007', NULL),
    ('7C1E0C40-5E51-4C0A-9A01-000000000002', '7C1E0C30-5E51-4C0A-9A01-000000000001', N'PROPONER', 0, '7C1E0C30-5E51-4C0A-9A01-000000000003', 1, 1, 'RCN_008', 'PROPUESTA_CANCELACION'),
    ('7C1E0C40-5E51-4C0A-9A01-000000000003', '7C1E0C30-5E51-4C0A-9A01-000000000002', N'PROPONER', 0, '7C1E0C30-5E51-4C0A-9A01-000000000003', 1, 1, 'RCN_008', 'PROPUESTA_CANCELACION'),
    ('7C1E0C40-5E51-4C0A-9A01-000000000004', '7C1E0C30-5E51-4C0A-9A01-000000000005', N'PROPONER', 0, '7C1E0C30-5E51-4C0A-9A01-000000000003', 1, 1, 'RCN_008', 'PROPUESTA_CANCELACION'),
    ('7C1E0C40-5E51-4C0A-9A01-000000000005', '7C1E0C30-5E51-4C0A-9A01-000000000003', N'APROBAR',  1, '7C1E0C30-5E51-4C0A-9A01-000000000004', 1, 0, 'RCN_009', 'CANCELACION_APROBADA'),
    ('7C1E0C40-5E51-4C0A-9A01-000000000006', '7C1E0C30-5E51-4C0A-9A01-000000000003', N'RECHAZAR', 1, '7C1E0C30-5E51-4C0A-9A01-000000000005', 0, 0, 'RCN_010', 'CANCELACION_RECHAZADA')
) AS Source (id, estadoOrigen, codigoDecision, esDecisionResolutor, estadoDestino, exigeUmbralPerdida, exigeResolutorDisponible, codigoMensajeExito, tipoPlantillaNotificacion)
ON (Target.id = Source.id)
WHEN MATCHED THEN UPDATE SET Target.estadoOrigen = Source.estadoOrigen, Target.codigoDecision = Source.codigoDecision, Target.esDecisionResolutor = Source.esDecisionResolutor,
    Target.estadoDestino = Source.estadoDestino, Target.exigeUmbralPerdida = Source.exigeUmbralPerdida, Target.exigeResolutorDisponible = Source.exigeResolutorDisponible,
    Target.codigoMensajeExito = Source.codigoMensajeExito, Target.tipoPlantillaNotificacion = Source.tipoPlantillaNotificacion
WHEN NOT MATCHED THEN INSERT (id, estadoOrigen, codigoDecision, esDecisionResolutor, estadoDestino, exigeUmbralPerdida, exigeResolutorDisponible, codigoMensajeExito, tipoPlantillaNotificacion)
    VALUES (Source.id, Source.estadoOrigen, Source.codigoDecision, Source.esDecisionResolutor, Source.estadoDestino, Source.exigeUmbralPerdida, Source.exigeResolutorDisponible, Source.codigoMensajeExito, Source.tipoPlantillaNotificacion);
GO

-- schema/functions/ufn_umbral_alerta_inasistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.3, O-1): umbral vigente de un tipo de alerta de inasistencia. Solo lee tablas base (las funciones se
-- despliegan antes que las vistas). Misma regla que ufn_obtener_parametro (valor, si no valorDefecto); NULL si falta o no es numerico.
CREATE OR ALTER FUNCTION [dbo].[ufn_umbral_alerta_inasistencia] (@idTipoAlerta UNIQUEIDENTIFIER)
RETURNS DECIMAL(5,2)
AS
BEGIN
    RETURN (
        SELECT TOP 1 TRY_CAST(NULLIF(TRIM(CAST(ISNULL(p.valor, p.valorDefecto) AS NVARCHAR(50))), N'') AS DECIMAL(5,2))
        FROM dbo.TipoAlertaInasistencia t
        INNER JOIN dbo.CatalogoParametro p ON p.grupo = t.grupoParametroUmbral AND p.clave = t.claveParametroUmbral AND p.estaActivo = 1
        WHERE t.id = @idTipoAlerta
    );
END;
GO

-- schema/functions/ufn_revision_cancelacion_resolutores.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.3, SUPUESTO-C-09, O-1, O-2): usuarios que pueden resolver una revision de cancelacion.
-- Programas competentes = EstudiantePrograma del estudiante que ademas son programas vigentes del grupo (regla S1 de B2,
-- replicada de ufn_programas_grupo para no depender del orden de despliegue; la paridad la prueba C-DB-63).
-- Coordinadores activos de esos programas (excluido @idUsuarioExcluido: quien propuso); si no queda ninguno, escala a los
-- decanos activos de las facultades de esos programas (esEscalamiento = 1), tambien con la exclusion. Solo tablas base.
CREATE OR ALTER FUNCTION [dbo].[ufn_revision_cancelacion_resolutores] (@idEstudianteGrupo UNIQUEIDENTIFIER, @idUsuarioExcluido UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    WITH vigentes AS (
        SELECT DISTINCT idPrograma = pe.programa, eg.estudiante
        FROM dbo.EstudianteGrupo eg
        INNER JOIN dbo.Grupo g ON g.id = eg.grupo
        INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
        INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = g.asignatura
        INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
        CROSS APPLY (SELECT zona = COALESCE((SELECT TOP 1 valor FROM dbo.CatalogoParametro
                                             WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1),
                                            'SA Pacific Standard Time')) z
        WHERE eg.id = @idEstudianteGrupo
          AND CAST(ape.fechaVinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) <= pa.fechaFin
          AND (ape.fechaDesvinculacionUtc IS NULL
               OR CAST(ape.fechaDesvinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) >= pa.fechaInicio)
    ),
    competentes AS (
        SELECT idPrograma = p.id, idFacultad = p.facultad, idCoordinador = p.coordinador
        FROM vigentes v
        INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = v.estudiante AND ep.programa = v.idPrograma
        INNER JOIN dbo.Programa p ON p.id = v.idPrograma AND p.estado = 1
    ),
    coordinadores AS (
        SELECT DISTINCT idUsuario = u.id, codigoPerfil = CAST(N'COORDINADOR' AS NVARCHAR(20)), c.idPrograma, c.idFacultad, esEscalamiento = CAST(0 AS BIT)
        FROM competentes c
        INNER JOIN dbo.Coordinador co ON co.id = c.idCoordinador AND co.estado = 1
        INNER JOIN dbo.Usuario u ON u.id = co.usuario AND u.estado = 1
        WHERE (@idUsuarioExcluido IS NULL OR u.id <> @idUsuarioExcluido)
    ),
    decanos AS (
        SELECT DISTINCT idUsuario = u.id, codigoPerfil = CAST(N'DECANO' AS NVARCHAR(20)), c.idPrograma, c.idFacultad, esEscalamiento = CAST(1 AS BIT)
        FROM competentes c
        INNER JOIN dbo.Facultad f ON f.id = c.idFacultad AND f.estado = 1
        INNER JOIN dbo.Decano d ON d.id = f.decano AND d.estado = 1
        INNER JOIN dbo.Usuario u ON u.id = d.usuario AND u.estado = 1
        WHERE NOT EXISTS (SELECT 1 FROM coordinadores)
          AND (@idUsuarioExcluido IS NULL OR u.id <> @idUsuarioExcluido)
    )
    SELECT idUsuario, codigoPerfil, idPrograma, idFacultad, esEscalamiento FROM coordinadores
    UNION
    SELECT idUsuario, codigoPerfil, idPrograma, idFacultad, esEscalamiento FROM decanos
);
GO

-- schema/views/uv_tipo_alerta_inasistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del tipo de alerta de inasistencia.
CREATE OR ALTER VIEW [dbo].[uv_tipo_alerta_inasistencia]
AS
SELECT  id = t.id, codigo = t.codigo, nombre = t.nombre, nivel = t.nivel,
        grupoParametroUmbral = t.grupoParametroUmbral, claveParametroUmbral = t.claveParametroUmbral,
        tipoPlantillaEstudiante = t.tipoPlantillaEstudiante, codigoMensajeUsuario = t.codigoMensajeUsuario,
        creaRevisionCancelacion = t.creaRevisionCancelacion
FROM    dbo.TipoAlertaInasistencia t;
GO

-- schema/views/uv_estado_alerta_inasistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del estado de una alerta de inasistencia.
CREATE OR ALTER VIEW [dbo].[uv_estado_alerta_inasistencia]
AS
SELECT  id = e.id, codigo = e.codigo, nombre = e.nombre, estaVigente = e.estaVigente
FROM    dbo.EstadoAlertaInasistencia e;
GO

-- schema/views/uv_estado_revision_cancelacion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del estado de una revision de cancelacion.
CREATE OR ALTER VIEW [dbo].[uv_estado_revision_cancelacion]
AS
SELECT  id = e.id, codigo = e.codigo, nombre = e.nombre, orden = e.orden, esInicial = e.esInicial,
        requiereAccionDocente = e.requiereAccionDocente, requiereAccionResolutor = e.requiereAccionResolutor,
        conservaMatricula = e.conservaMatricula, cancelaMatricula = e.cancelaMatricula, esFinal = e.esFinal
FROM    dbo.EstadoRevisionCancelacion e;
GO

-- schema/views/uv_transicion_revision_cancelacion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) de las transiciones de la revision de cancelacion.
CREATE OR ALTER VIEW [dbo].[uv_transicion_revision_cancelacion]
AS
SELECT  id = t.id, idEstadoOrigen = t.estadoOrigen, codigoEstadoOrigen = o.codigo, codigoDecision = t.codigoDecision,
        esDecisionResolutor = t.esDecisionResolutor, idEstadoDestino = t.estadoDestino, codigoEstadoDestino = d.codigo,
        exigeUmbralPerdida = t.exigeUmbralPerdida, exigeResolutorDisponible = t.exigeResolutorDisponible,
        codigoMensajeExito = t.codigoMensajeExito, tipoPlantillaNotificacion = t.tipoPlantillaNotificacion
FROM    dbo.TransicionRevisionCancelacion t
INNER JOIN dbo.EstadoRevisionCancelacion o ON o.id = t.estadoOrigen
INNER JOIN dbo.EstadoRevisionCancelacion d ON d.id = t.estadoDestino;
GO

-- schema/views/uv_alerta_inasistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.4): una fila por alerta de inasistencia, con el contexto de la matricula y del grupo.
-- Los ids de usuario sirven al ambito dentro de los SP; los SP de consulta del estudiante no los devuelven.
CREATE OR ALTER VIEW [dbo].[uv_alerta_inasistencia]
AS
SELECT  id = a.id,
        idEstudianteGrupo = a.estudianteGrupo,
        idEstudiante = eg.estudiante,
        idUsuarioEstudiante = ue.id,
        nombreCompletoEstudiante = CONCAT(LTRIM(RTRIM(CONCAT(ue.primerNombre, N' ', ue.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(ue.primerApellido, N' ', ue.segundoApellido)))),
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        nombreGrupo = g.nombre,
        idAsignatura = asig.id,
        nombreAsignatura = asig.nombre,
        idPeriodoAcademico = g.periodoAcademico,
        idDocenteTitular = g.docente,
        idUsuarioDocenteTitular = d.usuario,
        codigoEstadoMatricula = ee.codigo,
        idTipo = t.id,
        codigoTipo = t.codigo,
        nombreTipo = t.nombre,
        nivel = t.nivel,
        codigoMensajeUsuario = t.codigoMensajeUsuario,
        idEstado = es.id,
        codigoEstado = es.codigo,
        estaVigente = es.estaVigente,
        porcentajeCruce = a.porcentajeCruce,
        umbralCruce = a.umbralCruce,
        horasFaltaCruce = a.horasFaltaCruce,
        horasDictadasCruce = a.horasDictadasCruce,
        fechaCruceUtc = a.fechaCruceUtc,
        porcentajeUltimaEvaluacion = a.porcentajeUltimaEvaluacion,
        fechaUltimaEvaluacionUtc = a.fechaUltimaEvaluacionUtc,
        fechaLecturaUtc = a.fechaLecturaUtc,
        estaLeida = CAST(IIF(a.fechaLecturaUtc IS NULL, 0, 1) AS BIT)
FROM    dbo.AlertaInasistencia a
INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
INNER JOIN dbo.Estudiante e ON e.id = eg.estudiante
INNER JOIN dbo.Usuario ue ON ue.id = e.usuario
INNER JOIN dbo.Grupo g ON g.id = eg.grupo
INNER JOIN dbo.Asignatura asig ON asig.id = g.asignatura
INNER JOIN dbo.Docente d ON d.id = g.docente
INNER JOIN dbo.TipoAlertaInasistencia t ON t.id = a.tipo
INNER JOIN dbo.EstadoAlertaInasistencia es ON es.id = a.estado;
GO

-- schema/views/uv_revision_cancelacion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.4): una fila por revision de cancelacion con el contexto de la matricula, del docente y de la resolucion.
CREATE OR ALTER VIEW [dbo].[uv_revision_cancelacion]
AS
SELECT  id = r.id,
        idEstudianteGrupo = r.estudianteGrupo,
        idEstudiante = eg.estudiante,
        idUsuarioEstudiante = ue.id,
        nombreCompletoEstudiante = CONCAT(LTRIM(RTRIM(CONCAT(ue.primerNombre, N' ', ue.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(ue.primerApellido, N' ', ue.segundoApellido)))),
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        nombreGrupo = g.nombre,
        idAsignatura = asig.id,
        nombreAsignatura = asig.nombre,
        idPeriodoAcademico = g.periodoAcademico,
        idDocenteTitular = g.docente,
        idUsuarioDocenteTitular = ud.id,
        nombreCompletoDocente = CONCAT(LTRIM(RTRIM(CONCAT(ud.primerNombre, N' ', ud.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(ud.primerApellido, N' ', ud.segundoApellido)))),
        codigoEstadoMatricula = ee.codigo,
        idEstado = es.id,
        codigoEstado = es.codigo,
        nombreEstado = es.nombre,
        ordenEstado = es.orden,
        requiereAccionDocente = es.requiereAccionDocente,
        requiereAccionResolutor = es.requiereAccionResolutor,
        conservaMatricula = es.conservaMatricula,
        cancelaMatricula = es.cancelaMatricula,
        esFinal = es.esFinal,
        porcentajeCreacion = r.porcentajeCreacion,
        horasFaltaCreacion = r.horasFaltaCreacion,
        horasDictadasCreacion = r.horasDictadasCreacion,
        fechaCreacionUtc = r.fechaCreacionUtc,
        codigoDecisionDocente = r.codigoDecisionDocente,
        motivoDocente = r.motivoDocente,
        idUsuarioDecisionDocente = r.usuarioDecisionDocente,
        porcentajeDecisionDocente = r.porcentajeDecisionDocente,
        fechaDecisionDocenteUtc = r.fechaDecisionDocenteUtc,
        codigoPerfilResolutorActual = r.codigoPerfilResolutorActual,
        fechaEscalamientoUtc = r.fechaEscalamientoUtc,
        codigoDecisionResolucion = r.codigoDecisionResolucion,
        motivoResolucion = r.motivoResolucion,
        idUsuarioResolucion = r.usuarioResolucion,
        nombreCompletoResolucion = CASE WHEN ur.id IS NULL THEN NULL
                                        ELSE CONCAT(LTRIM(RTRIM(CONCAT(ur.primerNombre, N' ', ur.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(ur.primerApellido, N' ', ur.segundoApellido)))) END,
        codigoPerfilResolucion = r.codigoPerfilResolucion,
        idProgramaResolucion = r.programaResolucion,
        nombreProgramaResolucion = pr.nombre,
        porcentajeResolucion = r.porcentajeResolucion,
        fechaResolucionUtc = r.fechaResolucionUtc,
        fechaActualizacionUtc = r.fechaActualizacionUtc
FROM    dbo.RevisionCancelacion r
INNER JOIN dbo.EstadoRevisionCancelacion es ON es.id = r.estado
INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo
INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
INNER JOIN dbo.Estudiante e ON e.id = eg.estudiante
INNER JOIN dbo.Usuario ue ON ue.id = e.usuario
INNER JOIN dbo.Grupo g ON g.id = eg.grupo
INNER JOIN dbo.Asignatura asig ON asig.id = g.asignatura
INNER JOIN dbo.Docente d ON d.id = g.docente
INNER JOIN dbo.Usuario ud ON ud.id = d.usuario
LEFT JOIN dbo.Usuario ur ON ur.id = r.usuarioResolucion
LEFT JOIN dbo.Programa pr ON pr.id = r.programaResolucion;
GO

-- schema/views/uv_marca_inasistencia_estudiante_grupo.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.4): marca de inasistencia por matricula (alertas vigentes y estado de la revision) para la planilla
-- del docente. Una fila por matricula con alerta o revision; no lee uv_grupo_programa ni uv_resumen_*.
CREATE OR ALTER VIEW [dbo].[uv_marca_inasistencia_estudiante_grupo]
AS
SELECT  idEstudianteGrupo = k.estudianteGrupo,
        tieneAdvertenciaVigente = CAST(ISNULL(al.tieneAdvertencia, 0) AS BIT),
        fechaAdvertenciaUtc = al.fechaAdvertencia,
        tienePerdidaVigente = CAST(ISNULL(al.tienePerdida, 0) AS BIT),
        fechaPerdidaUtc = al.fechaPerdida,
        idRevisionCancelacion = r.id,
        codigoEstadoRevision = es.codigo,
        nombreEstadoRevision = es.nombre,
        requiereAccionDocente = es.requiereAccionDocente,
        requiereAccionResolutor = es.requiereAccionResolutor,
        conservaMatricula = es.conservaMatricula,
        esFinalRevision = es.esFinal,
        codigoPerfilResolutorActual = r.codigoPerfilResolutorActual
FROM    (SELECT estudianteGrupo FROM dbo.AlertaInasistencia UNION SELECT estudianteGrupo FROM dbo.RevisionCancelacion) k
LEFT JOIN dbo.RevisionCancelacion r ON r.estudianteGrupo = k.estudianteGrupo
LEFT JOIN dbo.EstadoRevisionCancelacion es ON es.id = r.estado
OUTER APPLY (
    SELECT  tieneAdvertencia = MAX(IIF(t.creaRevisionCancelacion = 0 AND s.estaVigente = 1, 1, 0)),
            fechaAdvertencia = MAX(IIF(t.creaRevisionCancelacion = 0 AND s.estaVigente = 1, a.fechaCruceUtc, NULL)),
            tienePerdida = MAX(IIF(t.creaRevisionCancelacion = 1 AND s.estaVigente = 1, 1, 0)),
            fechaPerdida = MAX(IIF(t.creaRevisionCancelacion = 1 AND s.estaVigente = 1, a.fechaCruceUtc, NULL))
    FROM    dbo.AlertaInasistencia a
    INNER JOIN dbo.TipoAlertaInasistencia t ON t.id = a.tipo
    INNER JOIN dbo.EstadoAlertaInasistencia s ON s.id = a.estado
    WHERE   a.estudianteGrupo = k.estudianteGrupo
) al;
GO

-- GRANT SELECT de las vistas nuevas (el bucle de rol_asistencias_runtime.sql esta congelado)
IF OBJECT_ID(N'dbo.uv_tipo_alerta_inasistencia', N'V') IS NOT NULL AND DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_tipo_alerta_inasistencia] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_estado_alerta_inasistencia', N'V') IS NOT NULL AND DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_estado_alerta_inasistencia] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_estado_revision_cancelacion', N'V') IS NOT NULL AND DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_estado_revision_cancelacion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_transicion_revision_cancelacion', N'V') IS NOT NULL AND DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_transicion_revision_cancelacion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_alerta_inasistencia', N'V') IS NOT NULL AND DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_alerta_inasistencia] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_revision_cancelacion', N'V') IS NOT NULL AND DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_revision_cancelacion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_marca_inasistencia_estudiante_grupo', N'V') IS NOT NULL AND DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_marca_inasistencia_estudiante_grupo] TO [rol_asistencias_runtime];
GO

-- 2. Resultset de control (no evalua; solo reporta las matriculas que ya estan en perdida y que el primer pase del job atendera)
DECLARE @catalogosCreados INT = (SELECT COUNT(1) FROM dbo.TipoAlertaInasistencia) + (SELECT COUNT(1) FROM dbo.EstadoAlertaInasistencia) + (SELECT COUNT(1) FROM dbo.EstadoRevisionCancelacion);
DECLARE @transiciones INT = (SELECT COUNT(1) FROM dbo.TransicionRevisionCancelacion);
DECLARE @sinRevision INT = 0;
DECLARE @codigoInscrita NVARCHAR(10) = N'A';
DECLARE @umbral DECIMAL(5,2) = (SELECT TOP 1 dbo.ufn_umbral_alerta_inasistencia(t.id) FROM dbo.TipoAlertaInasistencia t WHERE t.creaRevisionCancelacion = 1);
IF @umbral IS NOT NULL
    EXEC sys.sp_executesql N'SELECT @n = COUNT(1) FROM dbo.uv_resumen_asistencia_estudiante_grupo r WHERE r.codigoEstadoEstudiante = @c AND r.porcentajeInasistencia >= @u AND NOT EXISTS (SELECT 1 FROM dbo.RevisionCancelacion x WHERE x.estudianteGrupo = r.idEstudianteGrupo);',
        N'@n INT OUTPUT, @c NVARCHAR(10), @u DECIMAL(5,2)', @n = @sinRevision OUTPUT, @c = @codigoInscrita, @u = @umbral;
SELECT catalogosCreados = @catalogosCreados, transiciones = @transiciones, matriculasEnPerdidaSinRevision = @sinRevision;
PRINT CONCAT('MIGRACION 19 UP OK | transiciones=', @transiciones, ' | matriculas en perdida sin revision=', @sinRevision, ' | @@TRANCOUNT=', @@TRANCOUNT);
GO
