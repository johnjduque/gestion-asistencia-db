-- ============================================================================
-- MIGRACION UP 29: CULM-001 / DEC-064 - sesiones creadas manualmente por el docente: aviso y cancelacion por el coordinador
-- Crea la tabla MotivoCancelacionSesion y las vistas uv_motivo_cancelacion_sesion y uv_sesion_manual; siembra los motivos, el parametro
-- SESION/OBSERVACION_CANCELACION_COORDINADOR_MAXIMA, los mensajes SES_018..SES_021 y las plantillas SESION_MANUAL_CREADA_ESTUDIANTE y
-- SESION_MANUAL_CREADA_COORDINADOR (MERGE); crea usp_consultar_destinatarios_sesion_manual, usp_consultar_motivos_cancelacion_sesion y
-- usp_cancelar_sesion_coordinador y concede EXECUTE/SELECT al rol runtime. No modifica objetos existentes. Idempotente. Down: 29_..._down.sql.
-- ============================================================================
PRINT 'MIGRACION 29 UP: sesiones manuales - notificacion y cancelacion por el coordinador';
GO
-- ---- schema/tables/MotivoCancelacionSesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: catalogo de motivos con los que el coordinador del programa cancela una sesion creada manualmente por el
-- docente (usp_cancelar_sesion_coordinador). El codigo es estable (lo envia el cliente); el nombre es el texto institucional que
-- queda en SesionCancelacion.motivo. Filas en la semilla 60_sesiones_manuales_catalogos.sql (ids fijos).
IF OBJECT_ID('dbo.[MotivoCancelacionSesion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MotivoCancelacionSesion (
        id         UNIQUEIDENTIFIER NOT NULL,
        codigo     NVARCHAR(50)     NOT NULL,
        nombre     NVARCHAR(200)    NOT NULL,
        orden      INT              NOT NULL,
        estaActivo BIT              NOT NULL CONSTRAINT DF_MotivoCancelacionSesion_estaActivo DEFAULT 1,
        CONSTRAINT PK_MotivoCancelacionSesion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_MotivoCancelacionSesion_codigo UNIQUE (codigo),
        CONSTRAINT CK_MotivoCancelacionSesion_nombre CHECK (LEN(LTRIM(RTRIM(nombre))) > 0)
    );
END
GO
GO
-- ---- schema/views/uv_motivo_cancelacion_sesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: vista de catalogo (solo consulta) de los motivos de cancelacion de una sesion manual por el coordinador.
CREATE OR ALTER VIEW [dbo].[uv_motivo_cancelacion_sesion]
AS
SELECT  id = m.id,
        codigo = m.codigo,
        nombre = m.nombre,
        orden = m.orden,
        estaActivo = m.estaActivo
FROM    dbo.MotivoCancelacionSesion m;
GO
GO
-- ---- schema/views/uv_sesion_manual.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: sesiones creadas manualmente por el docente (fuera de la precarga por horario). La procedencia temporal las
-- distingue: usp_crear_sesion_v2 / usp_actualizar_sesion_v2 marcan UTC_V2; la precarga y el generador marcan UTC_GENERADOR; la
-- clasificacion administrativa UTC_OWNER y la historica (NULL) no son manuales. Una sesion generada que el docente edita por la
-- via v2 pasa a UTC_V2 (limitacion conocida: se trata como manual desde ese momento).
CREATE OR ALTER VIEW [dbo].[uv_sesion_manual]
AS
SELECT  idSesion = s.id,
        idGrupo = s.grupo,
        numero = s.numero,
        nombre = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin
FROM    dbo.Sesion s
WHERE   s.procedenciaTemporal = N'UTC_V2';
GO
GO
-- ---- schema/seed/60_sesiones_manuales_catalogos.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: catalogo de motivos con los que el coordinador cancela una sesion creada manualmente por el docente, y el
-- limite parametrizado de su observacion libre (SES_021). Idempotente: el catalogo se actualiza por id; el parametro no pisa el
-- valor administrado (WHEN MATCHED solo actualiza tipoDato y valorDefecto).
MERGE INTO [dbo].[MotivoCancelacionSesion] AS Target
USING (VALUES
    (CAST('7C1E0B10-5E51-4C0A-9B01-000000000001' AS UNIQUEIDENTIFIER), N'SESION_NO_AUTORIZADA',     N'Sesión no autorizada por la coordinación', 1),
    (CAST('7C1E0B10-5E51-4C0A-9B01-000000000002' AS UNIQUEIDENTIFIER), N'FUERA_DE_CALENDARIO',      N'Sesión fuera del calendario académico', 2),
    (CAST('7C1E0B10-5E51-4C0A-9B01-000000000003' AS UNIQUEIDENTIFIER), N'DUPLICADA',                N'Sesión duplicada', 3),
    (CAST('7C1E0B10-5E51-4C0A-9B01-000000000004' AS UNIQUEIDENTIFIER), N'CONFLICTO_INSTITUCIONAL',  N'Conflicto con una actividad institucional', 4),
    (CAST('7C1E0B10-5E51-4C0A-9B01-000000000005' AS UNIQUEIDENTIFIER), N'OTRO',                     N'Otro motivo', 5)
) AS Source (id, codigo, nombre, orden)
ON (Target.id = Source.id)
WHEN MATCHED THEN
    UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.orden = Source.orden
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, orden, estaActivo)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.orden, 1);
GO

MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('SESION', 'OBSERVACION_CANCELACION_COORDINADOR_MAXIMA', N'250', 'INT', N'250')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
GO
-- ---- schema/seed/60_sesiones_manuales_mensajes.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: mensajes de la cancelacion de una sesion manual por el coordinador. Idempotente (MERGE por codigo).
--   SES_018 la sesion no fue creada manualmente por el docente (409).
--   SES_019 el motivo no existe en el catalogo (400).
--   SES_020 la sesion fue cancelada por la coordinacion (exito).
--   SES_021 la observacion supera el maximo parametrizado (400).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('SES_018', 'BUSINESS_ERROR',   'MEDIO', N'Solo las sesiones creadas manualmente por el docente pueden ser canceladas por el coordinador.'),
    ('SES_019', 'VALIDATION_ERROR', 'BAJO',  N'El motivo de cancelación no es válido.'),
    ('SES_020', 'SUCCESS',          'BAJO',  N'La sesión fue cancelada por la coordinación del programa.'),
    ('SES_021', 'VALIDATION_ERROR', 'BAJO',  N'La observación no puede superar {} caracteres.')
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
    ('SES_018', 'BUSINESS_ERROR',   'MEDIO', N'Regla: la sesión [{}] no es manual (procedenciaTemporal distinta de UTC_V2); el coordinador no puede cancelarla; sin escrituras.'),
    ('SES_019', 'VALIDATION_ERROR', 'BAJO',  N'Validación: codigoMotivo [{}] ausente o fuera de MotivoCancelacionSesion activo; sin escrituras.'),
    ('SES_020', 'SUCCESS',          'BAJO',  N'Sesión [{}] cancelada por el coordinador; tipo [{}].'),
    ('SES_021', 'VALIDATION_ERROR', 'BAJO',  N'Validación: la observación recortada supera SESION/OBSERVACION_CANCELACION_COORDINADOR_MAXIMA ({}); sin escrituras.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
GO
-- ---- schema/seed/60_sesiones_manuales_plantillas.sql
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
GO
-- ---- schema/stored-procedures/usp_consultar_destinatarios_sesion_manual.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_sesion_manual (CULM-001 / DEC-064; HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET sin paginacion (<= cupo del grupo + coordinadores).
-- Destinatarios del aviso de una sesion creada manualmente por el docente (uv_sesion_manual; una sesion no manual devuelve 0 filas):
--   * ESTUDIANTE:  matriculas activas (MATRICULA/ESTADO_INSCRITA) del grupo con usuario activo;
--   * COORDINADOR: coordinador(es) activo(s) de TODOS los programas vigentes del grupo (ufn_programas_grupo). Un coordinador de dos
--                  programas del mismo grupo es UNA fila; un grupo mixto devuelve ambos coordinadores.
-- Ambito: RBAC DOCENTE + titularidad 'SESION' dentro del SP (THROW 51000 con el mensaje tecnico si falla). El correo es de uso
-- interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs. Mismo formato que
-- usp_consultar_destinatarios_sesion_cancelada.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_sesion_manual]
(
    @idSesion          UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idSesion IS NULL)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idSesion',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto,
            @codigoPerfilRequerido = 'DOCENTE',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @idUsuarioDefecto,
            @idEntidadPadre = @idSesionDefecto,
            @tipoEntidadPadre = 'SESION',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT  tipoDestinatario = x.tipoDestinatario,
            idUsuario        = x.idUsuario,
            nombreCompleto   = x.nombreCompleto,
            correo           = x.correo,
            nombreAsignatura = x.nombreAsignatura,
            nombreGrupo      = x.nombreGrupo,
            nombreDocente    = x.nombreDocente,
            fechaHoraInicio  = x.fechaHoraInicio,
            fechaHoraFin     = x.fechaHoraFin
    FROM (
        SELECT  tipoDestinatario = CAST(N'ESTUDIANTE' AS NVARCHAR(20)),
                ordenTipo        = 1,
                idUsuario        = ei.idUsuario,
                nombreCompleto   = CAST(ei.nombreCompleto AS NVARCHAR(400)),
                correo           = u.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = sm.fechaHoraInicio,
                fechaHoraFin     = sm.fechaHoraFin
        FROM dbo.uv_sesion_manual sm
        INNER JOIN dbo.uv_grupo g                 ON g.id = sm.idGrupo
        INNER JOIN dbo.uv_docente_identidad di    ON di.id = g.idDocente
        INNER JOIN dbo.uv_estudiante_grupo eg     ON eg.idGrupo = sm.idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante AND ei.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario u               ON u.id = ei.idUsuario
        WHERE sm.idSesion = @idSesionDefecto

        UNION ALL

        SELECT  tipoDestinatario = CAST(N'COORDINADOR' AS NVARCHAR(20)),
                ordenTipo        = 2,
                idUsuario        = ci.idUsuario,
                nombreCompleto   = CAST(ci.nombreCompleto AS NVARCHAR(400)),
                correo           = ci.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = sm.fechaHoraInicio,
                fechaHoraFin     = sm.fechaHoraFin
        FROM dbo.uv_sesion_manual sm
        INNER JOIN dbo.uv_grupo g              ON g.id = sm.idGrupo
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        INNER JOIN (
            SELECT DISTINCT ci2.idUsuario, ci2.nombreCompleto, ci2.correo
            FROM dbo.ufn_programas_grupo(
                     (SELECT s.idGrupo FROM dbo.uv_sesion_manual s WHERE s.idSesion = @idSesionDefecto)) pg
            INNER JOIN dbo.Programa p                    ON p.id = pg.idPrograma
            INNER JOIN dbo.uv_coordinador_identidad ci2  ON ci2.id = p.coordinador
                                                        AND ci2.estaActivoRolCoordinador = 1 AND ci2.estaActivoUsuario = 1
        ) ci ON 1 = 1
        WHERE sm.idSesion = @idSesionDefecto
    ) x
    ORDER BY x.ordenTipo, x.nombreCompleto, x.idUsuario;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_motivos_cancelacion_sesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_motivos_cancelacion_sesion (CULM-001 / DEC-064)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET sin paginacion (catalogo acotado).
-- Motivos activos con los que el coordinador cancela una sesion manual, en el orden del catalogo. RBAC COORDINADOR dentro del SP
-- (THROW 51000 con el mensaje tecnico si falla). Mismo patron que usp_consultar_destinatarios_sesion_cancelada.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_motivos_cancelacion_sesion]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto,
            @codigoPerfilRequerido = 'COORDINADOR',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT  codigo = m.codigo,
            nombre = m.nombre
    FROM dbo.uv_motivo_cancelacion_sesion m
    WHERE m.estaActivo = 1
    ORDER BY m.orden, m.codigo;
END;
GO
GO
-- ---- schema/stored-procedures/usp_cancelar_sesion_coordinador.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cancelar_sesion_coordinador (CULM-001 / DEC-064; HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con la misma tupla que usp_cancelar_sesion: canonica + idSesion, idGrupo,
-- fechaCancelacionUtc, totalEstudiantesActivos (NULL si estadoResultado = 0).
--
-- El coordinador del programa cancela una sesion creada manualmente por el docente (uv_sesion_manual, procedenciaTemporal UTC_V2).
-- No cambia la firma publica de usp_cancelar_sesion (docente). Reglas:
--   * RBAC COORDINADOR (SEC_001); sesion existente (SES_001);
--   * ambito: el coordinador coordina AL MENOS UNO de los programas vigentes del grupo (ufn_programas_grupo INTERSECT
--     ufn_programas_coordinador); si no, SEC_002. En un grupo mixto lo reciben (y pueden cancelar) los coordinadores de ambos programas;
--   * solo sesiones manuales: SES_018; motivo del catalogo MotivoCancelacionSesion activo: SES_019; observacion recortada <=
--     SESION/OBSERVACION_CANCELACION_COORDINADOR_MAXIMA: SES_021;
--   * mismas reglas de escritura que usp_cancelar_sesion: doble cancelacion SES_011 (se conserva el motivo original); con asistencia o
--     toma SES_012 (ventana vigente) o SES_016 (terminada);
--   * SesionCancelacion.motivo = nombre del motivo [+ ': ' + observacion]; tipo = el manual (TipoCancelacionSesion.esAutomatica = 0);
--     usuarioEjecutor = el coordinador (auditoria). Evento y aviso a estudiantes los publica el backend (SESION_CANCELADA).
-- Transaccion propia o SAVE TRANSACTION; la fila de dbo.Sesion se bloquea (UPDLOCK, HOLDLOCK) antes de leer la cancelacion y la
-- asistencia. Las ramas de rechazo no escriben: solo confirman la transaccion propia (compatible con INSERT ... EXEC).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cancelar_sesion_coordinador]
(
    @idSesion          UNIQUEIDENTIFIER,
    @codigoMotivo      NVARCHAR(50),
    @observacion       NVARCHAR(4000) = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @observacionLimpia NVARCHAR(4000) = NULLIF(LTRIM(RTRIM(@observacion)), N'');
    DECLARE @observacionMaxima INT = dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'OBSERVACION_CANCELACION_COORDINADOR_MAXIMA');
    DECLARE @margenMinutos     INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @codigoMatriculaActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idTipoManual      UNIQUEIDENTIFIER;
    DECLARE @codigoTipoManual  NVARCHAR(20);
    DECLARE @nombreMotivo      NVARCHAR(200);
    DECLARE @motivoTexto       NVARCHAR(500);
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @fechaHoraFin      DATETIME2;
    DECLARE @fechaCancelacion  DATETIME2(0) = NULL;
    DECLARE @totalActivos      INT = NULL;
    DECLARE @codigoRechazo     VARCHAR(20) = NULL;
    DECLARE @observacionMaximaTexto NVARCHAR(20);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC (COORDINADOR)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: sesion existente (SES_001)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: ambito del coordinador sobre el grupo de la sesion (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idGrupo = s.grupo FROM dbo.Sesion s WHERE s.id = @idSesionDefecto;

            IF NOT EXISTS (SELECT idPrograma FROM dbo.ufn_programas_grupo(@idGrupo)
                           INTERSECT
                           SELECT idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto))
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: solo sesiones creadas manualmente por el docente (SES_018)
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_manual sm WHERE sm.idSesion = @idSesionDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_018', @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: motivo del catalogo (SES_019)
        IF @estadoResultado = 1
        BEGIN
            SELECT @nombreMotivo = m.nombre
            FROM dbo.uv_motivo_cancelacion_sesion m
            WHERE m.codigo = LTRIM(RTRIM(@codigoMotivo)) AND m.estaActivo = 1;

            IF @nombreMotivo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_019', @p_param1 = @codigoMotivo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: observacion recortada dentro del maximo parametrizado (SES_021)
        IF @estadoResultado = 1
           AND (@observacionMaxima IS NULL OR LEN(@observacionLimpia) > @observacionMaxima)
        BEGIN
            SET @observacionMaximaTexto = CONVERT(NVARCHAR(20), @observacionMaxima);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_021', @p_param1 = @observacionMaximaTexto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 8: tipo manual de cancelacion por bandera de catalogo
        IF @estadoResultado = 1
        BEGIN
            SELECT @idTipoManual = t.id, @codigoTipoManual = t.codigo
            FROM dbo.uv_tipo_cancelacion_sesion t
            WHERE t.esAutomatica = 0;

            IF @idTipoManual IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TipoCancelacionSesion(esAutomatica = 0)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 9: escritura atomica bajo el bloqueo de la sesion
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cancelar_sesion_coordinador;
                SET @savepointCreado = 1;
            END

            SELECT @fechaHoraFin = s.fechaHoraFin
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            IF EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
                SET @codigoRechazo = 'SES_011';
            ELSE IF EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = @idSesionDefecto)
                 OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = @idSesionDefecto)
                SET @codigoRechazo = IIF(SYSUTCDATETIME() >= DATEADD(MINUTE, IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos), @fechaHoraFin),
                                         'SES_016', 'SES_012');

            IF @codigoRechazo IS NULL
            BEGIN
                SET @fechaCancelacion = SYSUTCDATETIME();
                SET @motivoTexto = IIF(@observacionLimpia IS NULL, @nombreMotivo, CONCAT(@nombreMotivo, N': ', @observacionLimpia));

                INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, fechaCancelacionUtc, idCorrelacion)
                VALUES (@idSesionDefecto, @idTipoManual, @motivoTexto, NULL, @idUsuarioEjecutorDefecto, @fechaCancelacion, @idCorrelacionDefecto);

                SELECT @totalActivos = COUNT(1)
                FROM dbo.uv_estudiante_grupo eg
                WHERE eg.idGrupo = @idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_020', @p_param1 = @idSesionDefecto, @p_param2 = @codigoTipoManual,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo, @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- La rama de rechazo no escribe: solo se confirma la transaccion propia (libera el bloqueo).
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
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
            ROLLBACK TRANSACTION sp_cancelar_sesion_coordinador;

        -- Transaccion externa condenada que no nos pertenece: se propaga al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idSesion                = IIF(@estadoResultado = 1, @idSesionDefecto, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        fechaCancelacionUtc     = IIF(@estadoResultado = 1, @fechaCancelacion, NULL),
        totalEstudiantesActivos = IIF(@estadoResultado = 1, @totalActivos, NULL);
END;
GO
GO
-- ---- schema/security/rol_asistencias_runtime_sesiones_manuales.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: permisos de las sesiones manuales. EXECUTE sobre los SP publicos nuevos y SELECT sobre las vistas nuevas
-- (los nucleos usp_*_interno no se conceden). Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_manual', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_sesion_manual] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_cancelar_sesion_coordinador] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_motivos_cancelacion_sesion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_motivos_cancelacion_sesion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_sesion_manual', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_sesion_manual] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_motivo_cancelacion_sesion', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_motivo_cancelacion_sesion] TO [rol_asistencias_runtime];
GO
GO
PRINT 'MIGRACION 29 UP OK';
GO
