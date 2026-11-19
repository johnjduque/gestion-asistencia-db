-- ============================================================================
-- MIGRACION UP 51: ATA D1 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C), aviso de falta por sesion (un correo por estudiante y sesion)
--   Tabla AvisoFaltaSesion (marca de sesion avisada, FK a Sesion), parametros AVISO_FALTA_SESION/HABILITADO|LOTE|HORAS_MAXIMAS_ATRASO (no
--   editables), plantilla FALTA_ASISTENCIA_SESION_ESTUDIANTE (es, v1) con sus marcadores, los SP de sistema
--   usp_consultar_sesiones_pendientes_aviso_falta, usp_consultar_faltas_sesion_aviso y usp_registrar_aviso_falta_sesion y su EXECUTE para
--   rol_asistencias_runtime. Mismo texto que schema/ (CREATE OR ALTER / MERGE idempotentes). Down: 51_ata_aviso_falta_sesion_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 51 UP: ATA D1 (aviso de falta por sesion)';
GO
-- ---- schema/tables/AvisoFaltaSesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D1 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C): marca de que una sesion terminada ya fue avisada por correo a los estudiantes con falta
-- (un aviso por estudiante y sesion). Una fila = sesion ya avisada; la escribe usp_registrar_aviso_falta_sesion (idempotente) y la lee
-- usp_consultar_sesiones_pendientes_aviso_falta. La FK a Sesion esta en zz_foreign_keys.sql.
IF OBJECT_ID('dbo.[AvisoFaltaSesion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AvisoFaltaSesion (
        sesion                   UNIQUEIDENTIFIER NOT NULL,
        fechaAvisoUtc            DATETIME2(3)     NOT NULL,
        totalEstudiantesAvisados INT              NOT NULL,
        idCorrelacion            UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_AvisoFaltaSesion PRIMARY KEY CLUSTERED (sesion),
        CONSTRAINT CK_AvisoFaltaSesion_total CHECK (totalEstudiantesAvisados >= 0)
    );
END
GO
GO
-- ATA D1: marca de aviso de falta por sesion
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_AvisoFaltaSesion_Sesion')
BEGIN
    ALTER TABLE [dbo].[AvisoFaltaSesion] ADD CONSTRAINT [FK_AvisoFaltaSesion_Sesion] FOREIGN KEY ([sesion]) REFERENCES [dbo].[Sesion] ([id]);
END
GO
-- ---- schema/seed/66_ata_parametros_aviso_falta.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D1 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C): parametros del aviso de falta por sesion (grupo AVISO_FALTA_SESION). Sin fila en
-- CatalogoParametroEdicion: no son editables por el administrador. Idempotente y sin pisar el valor administrado (WHEN MATCHED solo
-- actualiza tipoDato y valorDefecto).
--   HABILITADO             apaga el aviso sin desplegar (false => usp_consultar_sesiones_pendientes_aviso_falta devuelve 0 filas).
--   LOTE                   maximo de sesiones por pasada del job.
--   HORAS_MAXIMAS_ATRASO   no se avisan sesiones cuya ventana cerro hace mas de N horas (evita correos masivos al desplegar o recargar datos).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('AVISO_FALTA_SESION', 'HABILITADO',           N'true', 'BOOLEAN', N'true'),
    ('AVISO_FALTA_SESION', 'LOTE',                 N'50',   'INT',     N'50'),
    ('AVISO_FALTA_SESION', 'HORAS_MAXIMAS_ATRASO', N'24',   'INT',     N'24')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- ---- schema/seed/67_ata_plantilla_falta_sesion.sql
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
-- ---- schema/stored-procedures/usp_consultar_sesiones_pendientes_aviso_falta.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_pendientes_aviso_falta (ATA D1, ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C; HU175)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema (sin usuario, como usp_cerrar_tomas_vencidas). Resultset:
-- idSesion, idGrupo, fechaHoraFinUtc de las sesiones que el job debe avisar en esta pasada (orden fechaHoraFin, id).
-- Una sesion esta pendiente cuando: no esta cancelada, tiene procedencia temporal confirmada, tiene al menos una toma y todas estan
-- cerradas, su ventana de registro ya cerro (ventanaCierreUtc <= ahora), no cerro hace mas de AVISO_FALTA_SESION/HORAS_MAXIMAS_ATRASO
-- horas (evita correos masivos al desplegar o recargar datos) y no tiene fila en AvisoFaltaSesion.
-- Lote: @tamanoLote o, si es NULL, AVISO_FALTA_SESION/LOTE. Con AVISO_FALTA_SESION/HABILITADO = false devuelve 0 filas.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_pendientes_aviso_falta]
(
    @idCorrelacion UNIQUEIDENTIFIER,
    @tamanoLote    INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @habilitado NVARCHAR(20) = LOWER(TRIM(CAST(dbo.ufn_obtener_parametro('AVISO_FALTA_SESION', 'HABILITADO') AS NVARCHAR(20))));
    DECLARE @lote INT = ISNULL(@tamanoLote, dbo.ufn_obtener_parametro_int(NULL, 'AVISO_FALTA_SESION', 'LOTE'));
    DECLARE @horasAtraso INT = dbo.ufn_obtener_parametro_int(NULL, 'AVISO_FALTA_SESION', 'HORAS_MAXIMAS_ATRASO');
    DECLARE @margenMinutos INT = ISNULL(dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS'), 0);
    DECLARE @ahora DATETIME2(7) = SYSUTCDATETIME();

    IF @habilitado IS NULL OR @habilitado <> N'true' OR @lote IS NULL OR @lote < 1 OR @horasAtraso IS NULL OR @horasAtraso < 0
        SET @lote = 0;

    SELECT TOP (@lote)
        idSesion        = se.idSesion,
        idGrupo         = se.idGrupo,
        fechaHoraFinUtc = se.fechaHoraFin
    FROM dbo.uv_sesion_estado se
    WHERE se.estaCancelada = 0
      AND se.procedenciaTemporal IS NOT NULL
      AND se.totalTomas >= 1
      AND se.tieneTomaAbierta = 0
      -- Prefiltro por la fecha de fin (sargable): ventanaCierreUtc = fin + margen, asi que fin <= ahora y fin >= ahora - atraso - margen
      AND se.fechaHoraFin <= @ahora
      AND se.fechaHoraFin >= DATEADD(MINUTE, -(@horasAtraso * 60 + IIF(@margenMinutos < 0, 0, @margenMinutos)), @ahora)
      AND se.ventanaCierreUtc <= @ahora
      AND se.ventanaCierreUtc >= DATEADD(HOUR, -@horasAtraso, @ahora)
      AND NOT EXISTS (SELECT 1 FROM dbo.AvisoFaltaSesion a WHERE a.sesion = se.idSesion)
    ORDER BY se.fechaHoraFin ASC, se.idSesion ASC;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_faltas_sesion_aviso.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_faltas_sesion_aviso (ATA D1, ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C; HU175)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema (sin usuario). Resultset: una fila por (estudiante con al menos una toma en SJC,
-- toma en SJC) de la sesion: idSesion, idGrupo, idAsignatura, nombreAsignatura, nombreGrupo, fechaHoraInicioUtc, fechaHoraFinUtc,
-- idUsuarioEstudiante, nombreEstudiante, correoEstudiante, numeroToma, fechaPuntoControlUtc, totalTomasSesion, totalTomasEnFalta,
-- minutosFalta (minutos de falta del estudiante en la sesion, por tramos) y fechaLimiteReclamoUtc (ufn_calcular_fecha_limite_justificacion).
-- Solo matriculas activas (MATRICULA/ESTADO_INSCRITA) con usuario activo y correo. Las tomas sin registro o con AN/EX no generan fila.
-- Una sesion cancelada o inexistente devuelve 0 filas. Los correos son de uso interno del NotificacionPort; el backend no los expone ni los registra.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_faltas_sesion_aviso]
(
    @idSesion      UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    SELECT
        idSesion            = se.idSesion,
        idGrupo             = se.idGrupo,
        idAsignatura        = g.idAsignatura,
        nombreAsignatura    = g.nombreAsignatura,
        nombreGrupo         = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
        fechaHoraInicioUtc  = se.fechaHoraInicio,
        fechaHoraFinUtc     = se.fechaHoraFin,
        idUsuarioEstudiante = ei.idUsuario,
        nombreEstudiante    = CAST(ei.nombreCompleto AS NVARCHAR(400)),
        correoEstudiante    = u.correo,
        numeroToma          = tf.numeroToma,
        fechaPuntoControlUtc = tf.fechaPuntoControlUtc,
        totalTomasSesion    = se.totalTomas,
        totalTomasEnFalta   = COUNT(*) OVER (PARTITION BY tf.idEstudianteGrupo),
        minutosFalta        = CAST(ISNULL(sh.minutosFalta, 0) AS INT),
        fechaLimiteReclamoUtc = dbo.ufn_calcular_fecha_limite_justificacion(se.fechaHoraFin)
    FROM dbo.uv_sesion_estado se
    INNER JOIN dbo.uv_grupo g                    ON g.id = se.idGrupo
    INNER JOIN dbo.uv_asistencia_toma_estudiante tf ON tf.idSesion = se.idSesion AND tf.codigoRazonCausa = N'SJC'
    INNER JOIN dbo.uv_estudiante_grupo eg        ON eg.id = tf.idEstudianteGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
    INNER JOIN dbo.uv_estudiante_identidad ei    ON ei.id = eg.idEstudiante AND ei.estaActivoUsuario = 1
    INNER JOIN dbo.uv_usuario u                  ON u.id = ei.idUsuario
    LEFT JOIN  dbo.uv_asistencia_sesion_horas sh ON sh.idAsistencia = tf.idAsistencia
    WHERE se.idSesion = @idSesionDefecto
      AND se.estaCancelada = 0
      AND u.correo IS NOT NULL AND LEN(TRIM(u.correo)) > 0
    ORDER BY ei.nombreCompleto ASC, eg.idEstudiante ASC, tf.numeroToma ASC;
END;
GO
-- ---- schema/stored-procedures/usp_registrar_aviso_falta_sesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_aviso_falta_sesion (ATA D1, ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C; HU175)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema (sin usuario) con la tupla canonica (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado). Marca la sesion como ya avisada (AvisoFaltaSesion) con el total de estudiantes avisados.
-- Transaccional e idempotente: si la fila ya existe responde exito sin escribir (el total y la fecha originales se conservan); dos
-- instancias del job que avisen la misma sesion no duplican la marca. Validaciones: correlacion, GEN_002 (sesion o total nulos o
-- negativos) y SES_001 (sesion inexistente).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_aviso_falta_sesion]
(
    @idSesion                 UNIQUEIDENTIFIER,
    @totalEstudiantesAvisados INT,
    @idCorrelacion            UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @transaccionPropia       BIT = 0;
    DECLARE @savepointCreado         BIT = 0;
    DECLARE @estadoTransaccionCatch  INT;
    DECLARE @parametro               NVARCHAR(500);
    DECLARE @idSesionTexto           NVARCHAR(36) = CONVERT(NVARCHAR(36), @idSesion);

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idSesion IS NULL OR @totalEstudiantesAvisados IS NULL OR @totalEstudiantesAvisados < 0)
        BEGIN
            SET @parametro = IIF(@idSesion IS NULL, N'idSesion', N'totalEstudiantesAvisados');
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = @parametro,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.Sesion s WHERE s.id = @idSesion)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_001', @p_param1 = @idSesionTexto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_registrar_aviso_falta_sesion;
                SET @savepointCreado = 1;
            END

            -- Idempotente bajo concurrencia: la lectura bloquea la clave (UPDLOCK, HOLDLOCK) hasta confirmar
            IF NOT EXISTS (SELECT 1 FROM dbo.AvisoFaltaSesion a WITH (UPDLOCK, HOLDLOCK) WHERE a.sesion = @idSesion)
                INSERT INTO dbo.AvisoFaltaSesion (sesion, fechaAvisoUtc, totalEstudiantesAvisados, idCorrelacion)
                VALUES (@idSesion, SYSUTCDATETIME(), @totalEstudiantesAvisados, @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() <> 0
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_registrar_aviso_falta_sesion;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
-- ---- schema/security/rol_asistencias_runtime_ata_p1.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D1 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C): permisos del rol runtime para el aviso de falta por sesion. Aditivo e idempotente.
--   EXECUTE: usp_consultar_sesiones_pendientes_aviso_falta, usp_consultar_faltas_sesion_aviso y usp_registrar_aviso_falta_sesion
--   (comandos de sistema que invoca el job del backend). AvisoFaltaSesion no recibe permisos directos: se escribe solo por el SP.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_falta', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_pendientes_aviso_falta] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_faltas_sesion_aviso', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_faltas_sesion_aviso] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_registrar_aviso_falta_sesion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_registrar_aviso_falta_sesion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.AvisoFaltaSesion', N'U') IS NULL
   OR OBJECT_ID(N'dbo.usp_registrar_aviso_falta_sesion', N'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametro WHERE grupo = 'AVISO_FALTA_SESION') <> 3
   OR NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'FALTA_ASISTENCIA_SESION_ESTUDIANTE' AND idioma = 'es' AND version = 1)
    THROW 55101, 'MIGRACION 51: faltan la tabla, los SP, los parametros o la plantilla del aviso de falta por sesion.', 1;
GO
PRINT 'MIGRACION 51 UP OK';
GO
