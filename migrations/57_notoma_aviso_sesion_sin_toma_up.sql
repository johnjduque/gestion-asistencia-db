-- ============================================================================
-- MIGRACION UP 57: NOTOMA-001, aviso a la coordinacion cuando el docente no toma asistencia en una sesion (un correo por sesion)
--   Tabla AvisoSesionSinToma (marca de sesion avisada, FK a Sesion), parametros AVISO_SESION_SIN_TOMA/HABILITADO|LOTE|HORAS_MAXIMAS_ATRASO (no
--   editables), plantilla SESION_SIN_TOMA_COORDINADOR (es, v1) con sus marcadores, los SP de sistema
--   usp_consultar_sesiones_pendientes_aviso_sin_toma, usp_consultar_destinatarios_aviso_sin_toma y usp_registrar_aviso_sesion_sin_toma y su
--   EXECUTE para rol_asistencias_runtime. Mismo texto que schema/ (CREATE OR ALTER / MERGE idempotentes). Down: 57_notoma_aviso_sesion_sin_toma_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 57 UP: NOTOMA-001 (aviso de sesion sin toma al coordinador)';
GO
-- ---- schema/tables/AvisoSesionSinToma.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- NOTOMA-001 (AsistenciasUCO-Infra/docs/work-items/NOTOMA-001-aviso-coordinador-sesion-sin-toma): marca de que una sesion terminada sin ninguna toma
-- de asistencia ya fue avisada por correo a la coordinacion del programa (un aviso por sesion). Una fila = sesion ya avisada; la escribe
-- usp_registrar_aviso_sesion_sin_toma (idempotente) y la lee usp_consultar_sesiones_pendientes_aviso_sin_toma. La FK a Sesion esta en zz_foreign_keys.sql.
IF OBJECT_ID('dbo.[AvisoSesionSinToma]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AvisoSesionSinToma (
        sesion                     UNIQUEIDENTIFIER NOT NULL,
        fechaAvisoUtc              DATETIME2(3)     NOT NULL,
        totalCoordinadoresAvisados INT              NOT NULL,
        idCorrelacion              UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_AvisoSesionSinToma PRIMARY KEY CLUSTERED (sesion),
        CONSTRAINT CK_AvisoSesionSinToma_total CHECK (totalCoordinadoresAvisados >= 0)
    );
END
GO

-- ---- FK de schema/tables/zz_foreign_keys.sql
-- NOTOMA-001: marca de aviso de sesion sin toma al coordinador
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_AvisoSesionSinToma_Sesion')
BEGIN
    ALTER TABLE [dbo].[AvisoSesionSinToma] ADD CONSTRAINT [FK_AvisoSesionSinToma_Sesion] FOREIGN KEY ([sesion]) REFERENCES [dbo].[Sesion] ([id]);
END
GO

-- ---- schema/seed/69_notoma_parametros_plantilla.sql
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

-- ---- schema/stored-procedures/usp_consultar_sesiones_pendientes_aviso_sin_toma.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_pendientes_aviso_sin_toma (NOTOMA-001)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema (sin usuario, como usp_consultar_sesiones_pendientes_aviso_falta). Resultset:
-- idSesion, idGrupo, fechaHoraFinUtc de las sesiones que el job debe avisar a la coordinacion en esta pasada (orden fechaHoraFin, id).
-- Una sesion esta pendiente cuando: no esta cancelada (una solicitud rechazada ya queda cancelada), tiene procedencia temporal confirmada,
-- no tiene una solicitud en espera de aprobacion, el docente titular del grupo tiene el usuario activo, el grupo tiene al menos un estudiante
-- activo (matricula MATRICULA/ESTADO_INSCRITA con usuario activo), NO tiene ninguna toma (todo registro de asistencia cuelga de una toma), su ventana de registro ya cerro
-- (ventanaCierreUtc <= ahora), no cerro hace mas de AVISO_SESION_SIN_TOMA/HORAS_MAXIMAS_ATRASO horas (evita correos masivos al desplegar o
-- recargar datos) y no tiene fila en AvisoSesionSinToma.
-- Los grupos sin estudiantes activos y los de docente inactivo NO se seleccionan y NO se marcan: si el grupo recibe estudiantes o el docente se
-- reactiva dentro de HORAS_MAXIMAS_ATRASO, la sesion se avisa en una pasada posterior (la exclusion no oculta el problema con una marca).
-- Lote: @tamanoLote o, si es NULL, AVISO_SESION_SIN_TOMA/LOTE. Con AVISO_SESION_SIN_TOMA/HABILITADO = false devuelve 0 filas.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_pendientes_aviso_sin_toma]
(
    @idCorrelacion UNIQUEIDENTIFIER,
    @tamanoLote    INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @habilitado NVARCHAR(20) = LOWER(TRIM(CAST(dbo.ufn_obtener_parametro('AVISO_SESION_SIN_TOMA', 'HABILITADO') AS NVARCHAR(20))));
    DECLARE @lote INT = ISNULL(@tamanoLote, dbo.ufn_obtener_parametro_int(NULL, 'AVISO_SESION_SIN_TOMA', 'LOTE'));
    DECLARE @horasAtraso INT = dbo.ufn_obtener_parametro_int(NULL, 'AVISO_SESION_SIN_TOMA', 'HORAS_MAXIMAS_ATRASO');
    DECLARE @margenMinutos INT = ISNULL(dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS'), 0);
    DECLARE @codigoMatriculaActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
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
      AND ISNULL(se.pendienteAprobacion, 0) = 0
      AND se.totalTomas = 0
      -- Prefiltro por la fecha de fin (sargable): ventanaCierreUtc = fin + margen, asi que fin <= ahora y fin >= ahora - atraso - margen
      AND se.fechaHoraFin <= @ahora
      AND se.fechaHoraFin >= DATEADD(MINUTE, -(@horasAtraso * 60 + IIF(@margenMinutos < 0, 0, @margenMinutos)), @ahora)
      AND se.ventanaCierreUtc <= @ahora
      AND se.ventanaCierreUtc >= DATEADD(HOUR, -@horasAtraso, @ahora)
      AND NOT EXISTS (SELECT 1 FROM dbo.AvisoSesionSinToma a WHERE a.sesion = se.idSesion)
      AND EXISTS (SELECT 1 FROM dbo.uv_grupo g
                  INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente AND di.estaActivoUsuario = 1
                  WHERE g.id = se.idGrupo)
      AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo eg
                  INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante AND ei.estaActivoUsuario = 1
                  WHERE eg.idGrupo = se.idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva)
    ORDER BY se.fechaHoraFin ASC, se.idSesion ASC;
END;
GO

-- ---- schema/stored-procedures/usp_consultar_destinatarios_aviso_sin_toma.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_aviso_sin_toma (NOTOMA-001)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema (sin usuario). Resultset: una fila por coordinador destinatario del aviso
-- "el docente no tomo asistencia en la sesion": idSesion, idGrupo, idAsignatura, nombreAsignatura, nombreGrupo, nombreDocente,
-- fechaHoraInicioUtc, fechaHoraFinUtc, idUsuarioCoordinador, nombreCoordinador, correoCoordinador.
-- Destinatarios: coordinador(es) activo(s) de TODOS los programas vigentes del grupo (ufn_programas_grupo; en un grupo compartido, uno por
-- programa) con usuario activo y correo; una persona que coordina dos de esos programas sale una sola vez.
-- Una sesion inexistente, cancelada, o con alguna toma devuelve 0 filas (el aviso ya no aplica).
-- Los correos son de uso interno del NotificacionPort; el backend no los expone ni los registra.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_aviso_sin_toma]
(
    @idSesion      UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    SELECT
        idSesion             = se.idSesion,
        idGrupo              = se.idGrupo,
        idAsignatura         = g.idAsignatura,
        nombreAsignatura     = g.nombreAsignatura,
        nombreGrupo          = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
        nombreDocente        = CAST(di.nombreCompleto AS NVARCHAR(400)),
        fechaHoraInicioUtc   = se.fechaHoraInicio,
        fechaHoraFinUtc      = se.fechaHoraFin,
        idUsuarioCoordinador = co.idUsuario,
        nombreCoordinador    = CAST(co.nombreCompleto AS NVARCHAR(400)),
        correoCoordinador    = co.correo
    FROM dbo.uv_sesion_estado se
    INNER JOIN dbo.uv_grupo g              ON g.id = se.idGrupo
    INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
    CROSS APPLY (
        SELECT DISTINCT ci.idUsuario, ci.nombreCompleto, ci.correo
        FROM dbo.ufn_programas_grupo(se.idGrupo) pg
        INNER JOIN dbo.Programa p                   ON p.id = pg.idPrograma
        INNER JOIN dbo.uv_coordinador_identidad ci  ON ci.id = p.coordinador
                                                   AND ci.estaActivoRolCoordinador = 1 AND ci.estaActivoUsuario = 1
        WHERE ci.correo IS NOT NULL AND LEN(TRIM(ci.correo)) > 0
    ) co
    WHERE se.idSesion = @idSesionDefecto
      AND se.estaCancelada = 0
      AND se.totalTomas = 0
    ORDER BY co.nombreCompleto ASC, co.idUsuario ASC;
END;
GO

-- ---- schema/stored-procedures/usp_registrar_aviso_sesion_sin_toma.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_aviso_sesion_sin_toma (NOTOMA-001)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema (sin usuario) con la tupla canonica (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado). Marca la sesion como ya avisada (AvisoSesionSinToma) con el total de coordinadores avisados.
-- Transaccional e idempotente: si la fila ya existe responde exito sin escribir (el total y la fecha originales se conservan); dos
-- instancias del job que avisen la misma sesion no duplican la marca. Validaciones: correlacion, GEN_002 (sesion o total nulos o
-- negativos) y SES_001 (sesion inexistente).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_aviso_sesion_sin_toma]
(
    @idSesion                 UNIQUEIDENTIFIER,
    @totalCoordinadoresAvisados INT,
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

        IF @estadoResultado = 1 AND (@idSesion IS NULL OR @totalCoordinadoresAvisados IS NULL OR @totalCoordinadoresAvisados < 0)
        BEGIN
            SET @parametro = IIF(@idSesion IS NULL, N'idSesion', N'totalCoordinadoresAvisados');
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
                SAVE TRANSACTION sp_reg_aviso_sesion_sin_toma;
                SET @savepointCreado = 1;
            END

            -- Idempotente bajo concurrencia: la lectura bloquea la clave (UPDLOCK, HOLDLOCK) hasta confirmar
            IF NOT EXISTS (SELECT 1 FROM dbo.AvisoSesionSinToma a WITH (UPDLOCK, HOLDLOCK) WHERE a.sesion = @idSesion)
                INSERT INTO dbo.AvisoSesionSinToma (sesion, fechaAvisoUtc, totalCoordinadoresAvisados, idCorrelacion)
                VALUES (@idSesion, SYSUTCDATETIME(), @totalCoordinadoresAvisados, @idCorrelacionDefecto);

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
            ROLLBACK TRANSACTION sp_reg_aviso_sesion_sin_toma;

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

-- ---- schema/security/rol_asistencias_runtime_notoma.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- NOTOMA-001: permisos del rol runtime para el aviso al coordinador de la sesion sin toma. Aditivo e idempotente.
--   EXECUTE: usp_consultar_sesiones_pendientes_aviso_sin_toma, usp_consultar_destinatarios_aviso_sin_toma y usp_registrar_aviso_sesion_sin_toma
--   (comandos de sistema que invoca el job del backend). AvisoSesionSinToma no recibe permisos directos: se escribe solo por el SP.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_sesiones_pendientes_aviso_sin_toma', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_pendientes_aviso_sin_toma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_aviso_sin_toma', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_aviso_sin_toma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_registrar_aviso_sesion_sin_toma', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_registrar_aviso_sesion_sin_toma] TO [rol_asistencias_runtime];
GO

PRINT 'MIGRACION 57 UP OK';
GO
