-- ============================================================================
-- MIGRACION UP 30: CULM-001 / DEC-065 (2), (3) y (4) - solicitud de sesion extraordinaria con aval del coordinador y grupos solo por coordinador
-- Crea EstadoSolicitudSesion y SesionSolicitud (1:0..1 con Sesion) con sus FK, las vistas uv_estado_solicitud_sesion y uv_solicitud_sesion y los SP
-- usp_aprobar_solicitud_sesion, usp_rechazar_solicitud_sesion, usp_consultar_solicitudes_sesion_coordinador_paginado,
-- usp_consultar_destinatarios_solicitud_sesion y usp_validar_coordinador_sesion_interno; siembra los estados, el parametro
-- SESION/PREFIJO_MOTIVO_SOLICITUD_RECHAZADA, los mensajes SES_022..SES_027 y las plantillas SESION_SOLICITUD_* (MERGE); concede EXECUTE/SELECT al rol
-- runtime. Modifica (CREATE OR ALTER) uv_sesion_manual, uv_sesion_estado, uv_sesion_estudiante_reclamo, usp_validar_sesion_ventana_registro_interno,
-- usp_crear_sesion_interno (crea la solicitud PENDIENTE), usp_crear_grupo (solo COORDINADOR), usp_consultar_destinatarios_sesion_manual (fila DOCENTE)
-- y usp_consultar_sesiones_grupo_paginado (oculta al estudiante las no aprobadas). Idempotente. Down: 30_..._down.sql.
-- ============================================================================
PRINT 'MIGRACION 30 UP: solicitud de sesion extraordinaria con aval del coordinador';
GO
-- ---- schema/tables/EstadoSolicitudSesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (2): catalogo de estados de la solicitud de una sesion extraordinaria (aval previo del coordinador).
-- esFinal = 0 identifica el estado en espera (PENDIENTE); esAprobada distingue APROBADA de RECHAZADA entre los finales. Los SP
-- resuelven los estados por estas banderas, no por el texto del codigo. Filas en la semilla 60_sesiones_manuales_catalogos.sql.
IF OBJECT_ID('dbo.[EstadoSolicitudSesion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EstadoSolicitudSesion (
        id         UNIQUEIDENTIFIER NOT NULL,
        codigo     NVARCHAR(30)     NOT NULL,
        nombre     NVARCHAR(100)    NOT NULL,
        orden      INT              NOT NULL,
        esFinal    BIT              NOT NULL,
        esAprobada BIT              NOT NULL CONSTRAINT DF_EstadoSolicitudSesion_esAprobada DEFAULT 0,
        CONSTRAINT PK_EstadoSolicitudSesion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_EstadoSolicitudSesion_codigo UNIQUE (codigo),
        CONSTRAINT CK_EstadoSolicitudSesion_nombre CHECK (LEN(LTRIM(RTRIM(nombre))) > 0),
        CONSTRAINT CK_EstadoSolicitudSesion_aprobada CHECK (esAprobada = 0 OR esFinal = 1)
    );
END
GO
GO
-- ---- schema/tables/SesionSolicitud.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (2): solicitud de una sesion extraordinaria (1:0..1 con dbo.Sesion, que no se modifica: su guard 50004 prohibe
-- columnas de estado). La crea usp_crear_sesion_interno cuando el docente crea una sesion manual; la resuelven
-- usp_aprobar_solicitud_sesion / usp_rechazar_solicitud_sesion (el coordinador del programa). Las sesiones sin fila (generadas,
-- anteriores a este cambio) no tienen solicitud. Las FK estan en zz_foreign_keys.sql.
IF OBJECT_ID('dbo.[SesionSolicitud]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.SesionSolicitud (
        sesion              UNIQUEIDENTIFIER NOT NULL,
        idEstado            UNIQUEIDENTIFIER NOT NULL,
        usuarioSolicitante  UNIQUEIDENTIFIER NOT NULL,
        fechaSolicitudUtc   DATETIME2(0)     NOT NULL CONSTRAINT DF_SesionSolicitud_fechaSolicitud DEFAULT SYSUTCDATETIME(),
        usuarioResolucion   UNIQUEIDENTIFIER NULL,
        fechaResolucionUtc  DATETIME2(0)     NULL,
        observacion         NVARCHAR(500)    NULL,
        idCorrelacion       UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_SesionSolicitud PRIMARY KEY CLUSTERED (sesion),
        CONSTRAINT CK_SesionSolicitud_resolucion CHECK ((usuarioResolucion IS NULL AND fechaResolucionUtc IS NULL)
                                                      OR (usuarioResolucion IS NOT NULL AND fechaResolucionUtc IS NOT NULL))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SesionSolicitud') AND name = 'IX_SesionSolicitud_idEstado')
    CREATE NONCLUSTERED INDEX IX_SesionSolicitud_idEstado ON dbo.SesionSolicitud (idEstado) INCLUDE (fechaSolicitudUtc);
GO
GO
-- ---- schema/tables/zz_foreign_keys.sql (solo las FK de SesionSolicitud)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- CULM-001 / DEC-065 (2): solicitud de sesion extraordinaria con aval del coordinador
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SesionSolicitud_Sesion')
BEGIN
    ALTER TABLE [dbo].[SesionSolicitud] ADD CONSTRAINT [FK_SesionSolicitud_Sesion] FOREIGN KEY ([sesion]) REFERENCES [dbo].[Sesion] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SesionSolicitud_EstadoSolicitudSesion')
BEGIN
    ALTER TABLE [dbo].[SesionSolicitud] ADD CONSTRAINT [FK_SesionSolicitud_EstadoSolicitudSesion] FOREIGN KEY ([idEstado]) REFERENCES [dbo].[EstadoSolicitudSesion] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SesionSolicitud_UsuarioSolicitante')
BEGIN
    ALTER TABLE [dbo].[SesionSolicitud] ADD CONSTRAINT [FK_SesionSolicitud_UsuarioSolicitante] FOREIGN KEY ([usuarioSolicitante]) REFERENCES [dbo].[Usuario] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SesionSolicitud_UsuarioResolucion')
BEGIN
    ALTER TABLE [dbo].[SesionSolicitud] ADD CONSTRAINT [FK_SesionSolicitud_UsuarioResolucion] FOREIGN KEY ([usuarioResolucion]) REFERENCES [dbo].[Usuario] ([id]);
END
GO
GO
-- ---- schema/views/uv_estado_solicitud_sesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (2): vista de catalogo (solo consulta) de los estados de la solicitud de sesion extraordinaria.
CREATE OR ALTER VIEW [dbo].[uv_estado_solicitud_sesion]
AS
SELECT  id = e.id,
        codigo = e.codigo,
        nombre = e.nombre,
        orden = e.orden,
        esFinal = e.esFinal,
        esAprobada = e.esAprobada
FROM    dbo.EstadoSolicitudSesion e;
GO
GO
-- ---- schema/views/uv_sesion_manual.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: sesiones creadas manualmente por el docente (fuera de la precarga por horario). Los dos endpoints de creacion
-- (usp_crear_sesion v1 -> procedenciaTemporal NULL; usp_crear_sesion_v2 -> UTC_V2) son manuales; la precarga y el generador marcan
-- UTC_GENERADOR y la clasificacion administrativa de historicos UTC_OWNER: esas NO son manuales. Limitaciones conocidas: NULL tambien
-- es una fila historica anterior a UTC-D06 (se trata como manual; una sesion con asistencia no se puede cancelar de todos modos) y una
-- sesion generada que el docente edita por la via v2 pasa a UTC_V2.
-- CULM-001 / DEC-065 (2): estadoSolicitud (NULL sin solicitud) y pendienteAprobacion (solicitud en espera de aval del coordinador).
CREATE OR ALTER VIEW [dbo].[uv_sesion_manual]
AS
SELECT  idSesion = s.id,
        idGrupo = s.grupo,
        numero = s.numero,
        nombre = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estadoSolicitud = esol.codigo,
        pendienteAprobacion = CAST(IIF(esol.esFinal = 0, 1, 0) AS BIT)
FROM    dbo.Sesion s
LEFT JOIN dbo.SesionSolicitud ssol ON ssol.sesion = s.id
LEFT JOIN dbo.EstadoSolicitudSesion esol ON esol.id = ssol.idEstado
WHERE   s.procedenciaTemporal IS NULL OR s.procedenciaTemporal = N'UTC_V2';
GO
GO
-- ---- schema/views/uv_sesion_estado.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.5): una fila por sesion (sobre uv_sesion_v2, que no se modifica) con su estado de
-- cancelacion (dbo.SesionCancelacion, LEFT) y la ventana de registro con tolerancia:
--   ventanaAperturaUtc = inicio - ASISTENCIA/TOLERANCIA_MINUTOS (NULL si la procedencia temporal es INDETERMINADA)
--   ventanaCierreUtc   = fin + ASISTENCIA/MARGEN_RETARDO_MINUTOS
--   ventanaAbierta     = no cancelada, procedencia confirmada y apertura <= SYSUTCDATETIME() < cierre
-- Los dos parametros se leen una sola vez (CROSS APPLY); un parametro ausente o negativo vale 0 (regla estricta).
-- horasSesion = minutos de la sesion / 60 (0 si fin <= inicio).
-- CULM-001 / DEC-065 (2): estadoSolicitud (codigo de EstadoSolicitudSesion; NULL si la sesion no tiene solicitud: generadas y manuales
-- anteriores a DEC-065) y pendienteAprobacion (solicitud en espera): una sesion pendiente no tiene ventana abierta ni admite tomas.
-- CULM-001 B.2 (CONTRACT §2.5): totalTomas (tomas de la sesion), tieneTomaAbierta e idTomaAbierta (la toma sin fechaCierreUtc).
CREATE OR ALTER VIEW [dbo].[uv_sesion_estado]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        numero = s.numero,
        nombre = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        procedenciaTemporal = s.procedenciaTemporal,
        estaCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT),
        idTipoCancelacion = tc.id,
        codigoTipoCancelacion = tc.codigo,
        nombreTipoCancelacion = tc.nombre,
        esCancelacionAutomatica = tc.esAutomatica,
        motivoCancelacion = sc.motivo,
        idDiaFestivo = sc.diaFestivo,
        nombreDiaFestivo = df.nombre,
        fechaCancelacionUtc = sc.fechaCancelacionUtc,
        idUsuarioCancelacion = sc.usuarioEjecutor,
        ventanaAperturaUtc = IIF(s.procedenciaTemporal IS NULL, NULL, DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio)),
        ventanaCierreUtc = DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin),
        ventanaAbierta = CAST(IIF(sc.sesion IS NULL
                                  AND s.procedenciaTemporal IS NOT NULL
                                  AND (esol.esFinal IS NULL OR esol.esFinal = 1)
                                  AND DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio) <= SYSUTCDATETIME()
                                  AND SYSUTCDATETIME() < DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin), 1, 0) AS BIT),
        horasSesion = CAST(IIF(s.fechaHoraFin > s.fechaHoraInicio,
                               CAST(DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin) AS DECIMAL(12,6)) / 60, 0) AS DECIMAL(12,6)),
        totalTomas = tm.totalTomas,
        tieneTomaAbierta = CAST(IIF(tm.idTomaAbierta IS NULL, 0, 1) AS BIT),
        idTomaAbierta = tm.idTomaAbierta,
        estadoSolicitud = esol.codigo,
        pendienteAprobacion = CAST(IIF(esol.esFinal = 0, 1, 0) AS BIT)
FROM    dbo.uv_sesion_v2 s
CROSS APPLY (
        SELECT  toleranciaMinutos = IIF(t.valor IS NULL OR t.valor < 0, 0, t.valor),
                margenMinutos = IIF(m.valor IS NULL OR m.valor < 0, 0, m.valor)
        FROM    (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS')) t
        CROSS JOIN (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS')) m
) p
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = s.id
LEFT JOIN dbo.uv_tipo_cancelacion_sesion tc
ON      tc.id = sc.tipoCancelacion
LEFT JOIN dbo.DiaFestivo df
ON      df.id = sc.diaFestivo
LEFT JOIN dbo.SesionSolicitud ssol
ON      ssol.sesion = s.id
LEFT JOIN dbo.EstadoSolicitudSesion esol
ON      esol.id = ssol.idEstado
OUTER APPLY (
        SELECT  totalTomas = COUNT(1),
                idTomaAbierta = MAX(IIF(t.fechaCierreUtc IS NULL, CAST(t.id AS NVARCHAR(36)), NULL))
        FROM    dbo.TomaAsistencia t
        WHERE   t.sesion = s.id
) tm0
CROSS APPLY (SELECT totalTomas = ISNULL(tm0.totalTomas, 0), idTomaAbierta = CAST(tm0.idTomaAbierta AS UNIQUEIDENTIFIER)) tm;
GO
GO
-- ---- schema/views/uv_sesion_estudiante_reclamo.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.1 (CONTRACT §2.2, DEC-044 (2); HU026B): una fila por (sesion, matricula del estudiante) con la fecha limite
-- para justificar. Sobre uv_sesion_v2 + uv_sesion_estado (B.1) + uv_estudiante_grupo; uv_sesion (congelada) no se toca.
--   fechaLimiteJustificacionUtc = ufn_calcular_fecha_limite_justificacion(fechaHoraFin)  (limite exclusivo; NULL si falta
--                                 ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER)
--   plazoJustificacionVigente   = 1 solo si la sesion NO esta cancelada y SYSUTCDATETIME() < limite
-- idAsignatura, codigo, numeroSemana, codigoGrupo, nombreGrupo y codigoEstadoEstudiante completan las columnas que hoy
-- entrega la consulta de sesiones de la materia y permiten al SP filtrar la matricula inscrita.
-- CULM-001 / DEC-065 (2): el estudiante solo ve las sesiones sin solicitud (generadas y manuales anteriores) y las extraordinarias
-- aprobadas por el coordinador; las pendientes y las rechazadas (nunca se le anunciaron) no se listan.
CREATE OR ALTER VIEW [dbo].[uv_sesion_estudiante_reclamo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        idAsignatura = g.idAsignatura,
        numero = s.numero,
        nombre = s.nombre,
        codigo = s.codigo,
        numeroSemana = s.numeroSemana,
        codigoGrupo = s.codigoGrupo,
        nombreGrupo = s.nombreGrupo,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaCancelada = se.estaCancelada,
        fechaLimiteJustificacionUtc = lim.fechaLimiteUtc,
        plazoJustificacionVigente = CAST(IIF(se.estaCancelada = 0 AND lim.fechaLimiteUtc IS NOT NULL
                                             AND SYSUTCDATETIME() < lim.fechaLimiteUtc, 1, 0) AS BIT)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_sesion_estado se
ON      se.idSesion = s.id
INNER JOIN dbo.uv_estudiante_grupo eg
ON      eg.idGrupo = s.idGrupo
INNER JOIN dbo.uv_grupo g
ON      g.id = s.idGrupo
LEFT JOIN dbo.SesionSolicitud ssol
ON      ssol.sesion = s.id
LEFT JOIN dbo.EstadoSolicitudSesion esol
ON      esol.id = ssol.idEstado
CROSS APPLY (SELECT fechaLimiteUtc = dbo.ufn_calcular_fecha_limite_justificacion(s.fechaHoraFin)) lim
WHERE   esol.id IS NULL OR esol.esAprobada = 1;
GO
GO
-- ---- schema/views/uv_solicitud_sesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (2): solicitudes de sesion extraordinaria. Una fila por (sesion, programa vigente del grupo): en un grupo
-- mixto la solicitud aparece para cada programa y el SP de consulta del coordinador la colapsa a una fila por sesion.
--   pendienteAprobacion = estado en espera (esFinal = 0) y sesion no cancelada (una cancelacion del docente cierra el tramite)
--   estaCancelada       = la sesion tiene SesionCancelacion (rechazada por el coordinador o cancelada por el docente)
CREATE OR ALTER VIEW [dbo].[uv_solicitud_sesion]
AS
SELECT  idSesion = ss.sesion,
        nombreSesion = s.nombre,
        codigoSesion = s.codigo,
        idGrupo = s.grupo,
        nombreGrupo = g.nombre,
        nombreAsignatura = g.nombreAsignatura,
        idPrograma = p.id,
        nombrePrograma = p.nombre,
        idDocente = g.idDocente,
        nombreDocente = di.nombreCompleto,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estadoSolicitud = e.codigo,
        nombreEstadoSolicitud = e.nombre,
        fechaSolicitudUtc = ss.fechaSolicitudUtc,
        fechaResolucionUtc = ss.fechaResolucionUtc,
        observacion = ss.observacion,
        usuarioSolicitante = ss.usuarioSolicitante,
        pendienteAprobacion = CAST(IIF(e.esFinal = 0 AND sc.sesion IS NULL, 1, 0) AS BIT),
        estaCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT)
FROM    dbo.SesionSolicitud ss
INNER JOIN dbo.Sesion s                  ON s.id = ss.sesion
INNER JOIN dbo.uv_grupo g                ON g.id = s.grupo
INNER JOIN dbo.uv_docente_identidad di   ON di.id = g.idDocente
INNER JOIN dbo.EstadoSolicitudSesion e   ON e.id = ss.idEstado
LEFT JOIN  dbo.SesionCancelacion sc      ON sc.sesion = ss.sesion
CROSS APPLY dbo.ufn_programas_grupo(s.grupo) pg
INNER JOIN dbo.Programa p                ON p.id = pg.idPrograma;
GO
GO
-- ---- schema/stored-procedures/usp_validar_coordinador_sesion_interno.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_validar_coordinador_sesion_interno (CULM-001 / DEC-065 (2))
--
-- Validacion compartida por las operaciones del coordinador sobre una sesion: aprobar / rechazar una solicitud de sesion
-- extraordinaria y consultar sus destinatarios. Mantiene en un unico punto la regla de ambito de usp_cancelar_sesion_coordinador:
--   * RBAC COORDINADOR (SEC_001);
--   * sesion existente (SES_001);
--   * ambito: el coordinador coordina AL MENOS UNO de los programas vigentes del grupo de la sesion (ufn_programas_grupo
--     INTERSECT ufn_programas_coordinador); si no, SEC_002.
-- Devuelve el grupo de la sesion en @idGrupo. No escribe ni abre transacciones (compatible con INSERT ... EXEC del llamador).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_coordinador_sesion_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @idGrupo                 UNIQUEIDENTIFIER OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
BEGIN
    SET NOCOUNT ON;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado         = 1,
        @idGrupo                 = NULL;

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
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
GO
-- ---- schema/stored-procedures/usp_aprobar_solicitud_sesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_aprobar_solicitud_sesion (CULM-001 / DEC-065 (2); HU030, HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con la tupla canonica (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado) + idSesion, idGrupo, fechaHoraInicio, totalEstudiantesActivos (NULL si estadoResultado = 0).
--
-- El coordinador del programa aprueba la solicitud de una sesion extraordinaria creada por el docente. Reglas:
--   * RBAC COORDINADOR (SEC_001); sesion existente (SES_001); ambito = programa del grupo INTERSECT programas del coordinador
--     (SEC_002) - usp_validar_coordinador_sesion_interno;
--   * observacion opcional recortada <= SESION/OBSERVACION_CANCELACION_COORDINADOR_MAXIMA (SES_021);
--   * la sesion debe tener una solicitud (SES_025), en estado en espera (SES_024 si ya fue resuelta) y no estar cancelada (SES_011);
--   * la solicitud pasa al estado final con esAprobada = 1 (catalogo EstadoSolicitudSesion), con usuario, fecha y observacion.
--     Desde ese momento la sesion admite tomas y asistencia, y los estudiantes la ven. El aviso a los estudiantes y al docente lo
--     publica el backend (usp_consultar_destinatarios_solicitud_sesion).
-- Transaccion propia o SAVE TRANSACTION; la fila de dbo.Sesion se bloquea (UPDLOCK, HOLDLOCK) antes de leer la solicitud.
-- Las ramas de rechazo no escriben: solo confirman la transaccion propia (compatible con INSERT ... EXEC).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_aprobar_solicitud_sesion]
(
    @idSesion          UNIQUEIDENTIFIER,
    @observacion       NVARCHAR(500) = NULL,
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

    DECLARE @observacionLimpia NVARCHAR(500) = NULLIF(LTRIM(RTRIM(@observacion)), N'');
    DECLARE @observacionMaxima INT = dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'OBSERVACION_CANCELACION_COORDINADOR_MAXIMA');
    DECLARE @observacionMaximaTexto NVARCHAR(20);
    DECLARE @codigoMatriculaActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @fechaHoraInicio   DATETIME2;
    DECLARE @existeSolicitud   BIT = 0;
    DECLARE @solicitudFinal    BIT = 0;
    DECLARE @idEstadoAprobada  UNIQUEIDENTIFIER;
    DECLARE @totalActivos      INT = NULL;
    DECLARE @codigoRechazo     VARCHAR(20) = NULL;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASOS 1-4: correlacion, ejecutor, RBAC COORDINADOR, sesion existente y ambito (compartido)
        EXEC dbo.usp_validar_coordinador_sesion_interno
            @idSesion = @idSesionDefecto,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idGrupo = @idGrupo OUTPUT;

        -- PASO 5: observacion recortada dentro del maximo parametrizado (SES_021)
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

        -- PASO 6: estado final de aprobacion del catalogo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoAprobada = e.id
            FROM dbo.uv_estado_solicitud_sesion e
            WHERE e.esFinal = 1 AND e.esAprobada = 1
            ORDER BY e.orden;

            IF @idEstadoAprobada IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'EstadoSolicitudSesion(esFinal = 1, esAprobada = 1)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: escritura atomica bajo el bloqueo de la sesion
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_aprobar_solicitud_sesion;
                SET @savepointCreado = 1;
            END

            SELECT @fechaHoraInicio = s.fechaHoraInicio
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            SELECT @existeSolicitud = 1, @solicitudFinal = e.esFinal
            FROM dbo.SesionSolicitud ss
            INNER JOIN dbo.EstadoSolicitudSesion e ON e.id = ss.idEstado
            WHERE ss.sesion = @idSesionDefecto;

            IF @existeSolicitud = 0
                SET @codigoRechazo = 'SES_025';
            ELSE IF @solicitudFinal = 1
                SET @codigoRechazo = 'SES_024';
            ELSE IF EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
                SET @codigoRechazo = 'SES_011';

            IF @codigoRechazo IS NULL
            BEGIN
                UPDATE dbo.SesionSolicitud
                SET idEstado = @idEstadoAprobada,
                    usuarioResolucion = @idUsuarioEjecutorDefecto,
                    fechaResolucionUtc = SYSUTCDATETIME(),
                    observacion = @observacionLimpia
                WHERE sesion = @idSesionDefecto;

                SELECT @totalActivos = COUNT(1)
                FROM dbo.uv_estudiante_grupo eg
                WHERE eg.idGrupo = @idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_026', @p_param1 = @idSesionDefecto,
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
            ROLLBACK TRANSACTION sp_aprobar_solicitud_sesion;

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
        fechaHoraInicio         = IIF(@estadoResultado = 1, @fechaHoraInicio, NULL),
        totalEstudiantesActivos = IIF(@estadoResultado = 1, @totalActivos, NULL);
END;
GO
GO
-- ---- schema/stored-procedures/usp_rechazar_solicitud_sesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_rechazar_solicitud_sesion (CULM-001 / DEC-065 (2); HU030, HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con la misma tupla que usp_cancelar_sesion_coordinador: canonica + idSesion,
-- idGrupo, fechaCancelacionUtc, totalEstudiantesActivos (NULL si estadoResultado = 0).
--
-- El coordinador del programa rechaza la solicitud de una sesion extraordinaria. Mismas validaciones de entrada que
-- usp_aprobar_solicitud_sesion (RBAC COORDINADOR, ambito SEC_002, solicitud en espera SES_024/SES_025, no cancelada SES_011) y las de
-- usp_cancelar_sesion_coordinador para el motivo (catalogo MotivoCancelacionSesion activo: SES_019) y la observacion (SES_021).
-- La solicitud pasa al estado final con esAprobada = 0 y la sesion queda CANCELADA (SesionCancelacion, tipo manual, usuarioEjecutor =
-- el coordinador) para que todo el sistema la trate como cancelada. SesionCancelacion.motivo = SESION/PREFIJO_MOTIVO_SOLICITUD_RECHAZADA
-- + ': ' + nombre del motivo [+ ': ' + observacion]. Una sesion pendiente no tiene asistencia ni tomas (SES_023), por lo que no aplican
-- SES_012/SES_016. El aviso al docente lo publica el backend (usp_consultar_destinatarios_solicitud_sesion).
-- Transaccion propia o SAVE TRANSACTION; la fila de dbo.Sesion se bloquea (UPDLOCK, HOLDLOCK) antes de leer la solicitud.
-- Las ramas de rechazo no escriben: solo confirman la transaccion propia (compatible con INSERT ... EXEC).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_rechazar_solicitud_sesion]
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
    DECLARE @observacionMaximaTexto NVARCHAR(20);
    DECLARE @prefijoMotivo     NVARCHAR(200) = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'SESION', 'PREFIJO_MOTIVO_SOLICITUD_RECHAZADA') AS NVARCHAR(200));
    DECLARE @codigoMatriculaActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idTipoManual      UNIQUEIDENTIFIER;
    DECLARE @nombreMotivo      NVARCHAR(200);
    DECLARE @motivoTexto       NVARCHAR(500);
    DECLARE @idEstadoRechazada UNIQUEIDENTIFIER;
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @existeSolicitud   BIT = 0;
    DECLARE @solicitudFinal    BIT = 0;
    DECLARE @fechaCancelacion  DATETIME2(0) = NULL;
    DECLARE @totalActivos      INT = NULL;
    DECLARE @codigoRechazo     VARCHAR(20) = NULL;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASOS 1-4: correlacion, ejecutor, RBAC COORDINADOR, sesion existente y ambito (compartido)
        EXEC dbo.usp_validar_coordinador_sesion_interno
            @idSesion = @idSesionDefecto,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idGrupo = @idGrupo OUTPUT;

        -- PASO 5: motivo del catalogo (SES_019)
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

        -- PASO 6: observacion recortada dentro del maximo parametrizado (SES_021)
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

        -- PASO 7: tipo manual de cancelacion y estado final de rechazo (por bandera de catalogo)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idTipoManual = t.id
            FROM dbo.uv_tipo_cancelacion_sesion t
            WHERE t.esAutomatica = 0;

            SELECT TOP 1 @idEstadoRechazada = e.id
            FROM dbo.uv_estado_solicitud_sesion e
            WHERE e.esFinal = 1 AND e.esAprobada = 0
            ORDER BY e.orden;

            IF @idTipoManual IS NULL OR @idEstadoRechazada IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TipoCancelacionSesion(esAutomatica = 0)/EstadoSolicitudSesion(esFinal = 1, esAprobada = 0)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 8: escritura atomica bajo el bloqueo de la sesion
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_rechazar_solicitud_sesion;
                SET @savepointCreado = 1;
            END

            SELECT @idGrupo = s.grupo
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            SELECT @existeSolicitud = 1, @solicitudFinal = e.esFinal
            FROM dbo.SesionSolicitud ss
            INNER JOIN dbo.EstadoSolicitudSesion e ON e.id = ss.idEstado
            WHERE ss.sesion = @idSesionDefecto;

            IF @existeSolicitud = 0
                SET @codigoRechazo = 'SES_025';
            ELSE IF @solicitudFinal = 1
                SET @codigoRechazo = 'SES_024';
            ELSE IF EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
                SET @codigoRechazo = 'SES_011';

            IF @codigoRechazo IS NULL
            BEGIN
                SET @fechaCancelacion = SYSUTCDATETIME();
                SET @motivoTexto = CONCAT(@prefijoMotivo, N': ', @nombreMotivo, IIF(@observacionLimpia IS NULL, N'', CONCAT(N': ', @observacionLimpia)));

                INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, fechaCancelacionUtc, idCorrelacion)
                VALUES (@idSesionDefecto, @idTipoManual, @motivoTexto, NULL, @idUsuarioEjecutorDefecto, @fechaCancelacion, @idCorrelacionDefecto);

                UPDATE dbo.SesionSolicitud
                SET idEstado = @idEstadoRechazada,
                    usuarioResolucion = @idUsuarioEjecutorDefecto,
                    fechaResolucionUtc = @fechaCancelacion,
                    observacion = @observacionLimpia
                WHERE sesion = @idSesionDefecto;

                SELECT @totalActivos = COUNT(1)
                FROM dbo.uv_estudiante_grupo eg
                WHERE eg.idGrupo = @idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_027', @p_param1 = @idSesionDefecto,
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
            ROLLBACK TRANSACTION sp_rechazar_solicitud_sesion;

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
-- ---- schema/stored-procedures/usp_consultar_solicitudes_sesion_coordinador_paginado.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_sesion_coordinador_paginado (CULM-001 / DEC-065 (2); HU030, HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET paginado (PAG_001 + totalRegistros).
-- Solicitudes de sesion extraordinaria de los programas que coordina el usuario (uv_solicitud_sesion INTERSECT ufn_programas_coordinador),
-- una fila por sesion (en un grupo mixto, el programa alfabeticamente primero entre los que coordina el usuario), ordenadas por
-- fechaSolicitudUtc DESC. @soloPendientes = 1 (por defecto) deja solo las solicitudes en espera de aval que no fueron canceladas;
-- 0 incluye aprobadas, rechazadas y canceladas. Filtros opcionales por programa y por grupo. RBAC COORDINADOR dentro del SP
-- (THROW 51000 con el mensaje tecnico si falla). Paginacion normalizada (pagina >= 1; tamano 1..100, por defecto 20).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_sesion_coordinador_paginado]
(
    @idUsuario      UNIQUEIDENTIFIER,
    @soloPendientes BIT              = 1,
    @idPrograma     UNIQUEIDENTIFIER = NULL,
    @idGrupo        UNIQUEIDENTIFIER = NULL,
    @numeroPagina   INT              = 1,
    @tamanoPagina   INT              = 20,
    @idCorrelacion  UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuario, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @soloEnEspera BIT = IIF(@soloPendientes IS NULL, 1, @soloPendientes);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND @idUsuario IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuario',
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

    ;WITH ambito AS (
        SELECT  v.idSesion, v.nombreSesion, v.codigoSesion, v.idGrupo, v.nombreGrupo, v.nombreAsignatura,
                v.idPrograma, v.nombrePrograma, v.idDocente, v.nombreDocente, v.fechaHoraInicio, v.fechaHoraFin,
                v.estadoSolicitud, v.nombreEstadoSolicitud, v.fechaSolicitudUtc, v.fechaResolucionUtc, v.observacion,
                v.usuarioSolicitante, v.pendienteAprobacion, v.estaCancelada,
                rn = ROW_NUMBER() OVER (PARTITION BY v.idSesion ORDER BY v.nombrePrograma, v.idPrograma)
        FROM    dbo.uv_solicitud_sesion v
        WHERE   v.idPrograma IN (SELECT pc.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioDefecto) pc)
          AND   (@idPrograma IS NULL OR v.idPrograma = @idPrograma)
          AND   (@idGrupo IS NULL OR v.idGrupo = @idGrupo)
          AND   (@soloEnEspera = 0 OR v.pendienteAprobacion = 1)
    )
    SELECT  a.idSesion, a.nombreSesion, a.codigoSesion, a.idGrupo, a.nombreGrupo, a.nombreAsignatura,
            a.idPrograma, a.nombrePrograma, a.idDocente, a.nombreDocente, a.fechaHoraInicio, a.fechaHoraFin,
            a.estadoSolicitud, a.nombreEstadoSolicitud, a.fechaSolicitudUtc, a.fechaResolucionUtc, a.observacion,
            a.usuarioSolicitante, a.pendienteAprobacion, a.estaCancelada,
            totalRegistros = COUNT(*) OVER()
    FROM    ambito a
    WHERE   a.rn = 1
    ORDER BY a.fechaSolicitudUtc DESC, a.idSesion ASC
    OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_destinatarios_solicitud_sesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_solicitud_sesion (CULM-001 / DEC-065 (2); HU030, HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET sin paginacion (<= cupo del grupo + docente).
-- Destinatarios del aviso de la DECISION del coordinador sobre una solicitud de sesion extraordinaria (aprobada o rechazada). Lo
-- consulta el coordinador (usp_consultar_destinatarios_sesion_manual es del docente titular):
--   * DOCENTE:    el docente titular del grupo (usuario activo), siempre;
--   * ESTUDIANTE: matriculas activas (MATRICULA/ESTADO_INSCRITA) del grupo con usuario activo; el backend los avisa solo cuando la
--                 solicitud fue aprobada.
-- Solo sesiones con solicitud (SesionSolicitud); una sesion sin solicitud devuelve 0 filas. Ambito: RBAC COORDINADOR + programa del
-- grupo (usp_validar_coordinador_sesion_interno; THROW 51000 con el mensaje tecnico si falla). Mismas 9 columnas que
-- usp_consultar_destinatarios_sesion_manual. El correo es de uso interno del NotificacionPort.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_solicitud_sesion]
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
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @idGrupo UNIQUEIDENTIFIER;

    IF @idSesion IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idSesion',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_coordinador_sesion_interno
            @idSesion = @idSesionDefecto,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idGrupo = @idGrupo OUTPUT;
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
        SELECT  tipoDestinatario = CAST(N'DOCENTE' AS NVARCHAR(20)),
                ordenTipo        = 1,
                idUsuario        = di.idUsuario,
                nombreCompleto   = CAST(di.nombreCompleto AS NVARCHAR(400)),
                correo           = ud.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = s.fechaHoraInicio,
                fechaHoraFin     = s.fechaHoraFin
        FROM dbo.SesionSolicitud ss
        INNER JOIN dbo.Sesion s                ON s.id = ss.sesion
        INNER JOIN dbo.uv_grupo g              ON g.id = s.grupo
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente AND di.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario ud           ON ud.id = di.idUsuario
        WHERE ss.sesion = @idSesionDefecto
        UNION ALL
        SELECT  tipoDestinatario = CAST(N'ESTUDIANTE' AS NVARCHAR(20)),
                ordenTipo        = 2,
                idUsuario        = ei.idUsuario,
                nombreCompleto   = CAST(ei.nombreCompleto AS NVARCHAR(400)),
                correo           = ue.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = s.fechaHoraInicio,
                fechaHoraFin     = s.fechaHoraFin
        FROM dbo.SesionSolicitud ss
        INNER JOIN dbo.Sesion s                   ON s.id = ss.sesion
        INNER JOIN dbo.uv_grupo g                 ON g.id = s.grupo
        INNER JOIN dbo.uv_docente_identidad di    ON di.id = g.idDocente
        INNER JOIN dbo.uv_estudiante_grupo eg     ON eg.idGrupo = s.grupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante AND ei.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario ue              ON ue.id = ei.idUsuario
        WHERE ss.sesion = @idSesionDefecto
    ) x
    ORDER BY x.ordenTipo, x.nombreCompleto, x.idUsuario;
END;
GO
GO
-- ---- schema/stored-procedures/usp_validar_sesion_ventana_registro_interno.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SES-01: ventana de registro ordinario de asistencia (cierre estricto, sin tolerancia).
--   * Solo se registra cuando fechaHoraInicio <= SYSUTCDATETIME() < fechaHoraFin. El reloj autoritativo es el
--     del motor (UTC); nunca el del cliente ni el del backend.
--   * Solo una procedencia confirmada (UTC_V2, UTC_GENERADOR, UTC_OWNER) prueba que los DATETIME2 son instantes
--     UTC. NULL (INDETERMINADA) no permite escribir: no se supone zona horaria alguna.
--   * Lee la fila de dbo.Sesion con UPDLOCK + HOLDLOCK: invocado dentro de la transaccion del llamador, el
--     bloqueo se mantiene hasta su COMMIT/ROLLBACK, de modo que el horario no cambia entre esta validacion y la
--     escritura, y los lotes concurrentes de la misma sesion se serializan y evaluan el reloj despues de
--     obtener el bloqueo (una solicitud iniciada antes del cierre que llega despues del cierre se rechaza).
--   * Codigos: SES_007 (sesion no iniciada), SES_008 (sesion cerrada), SES_009 (horario indeterminado).
--   * No escribe. El llamador decide la reversion y el resultset canonico.
-- CULM-001 B.1 (CONTRACT §2.7.1):
--   * @toleranciaMinutos / @margenMinutos (opcionales): ventana [inicio - tolerancia, fin + margen). NULL o negativos = 0,
--     es decir, la regla estricta de SES-01; los llamadores de 5 parametros (lote congelado, autonomo) no cambian.
--     Los valores los lee el LLAMADOR (ASISTENCIA/TOLERANCIA_MINUTOS y ASISTENCIA/MARGEN_RETARDO_MINUTOS).
--   * PASO 2.5 (todos los llamadores): una sesion con dbo.SesionCancelacion se rechaza con SES_010. Se lee despues del
--     UPDLOCK + HOLDLOCK sobre dbo.Sesion, el mismo bloqueo que toma usp_cancelar_sesion: registro y cancelacion se
--     serializan.
-- CULM-001 B.2 (CONTRACT §2.8.3, NB-4, alternativa aprobada de antemano): @bloqueoCompartido = 1 lee la sesion con HOLDLOCK
--   (bloqueo compartido) en lugar de UPDLOCK, HOLDLOCK. Solo lo usa usp_registrar_asistencia_por_token: los registros QR de un
--   grupo no se serializan entre si y la cancelacion (U/X) sigue serializada contra ellos; el registro no actualiza Sesion,
--   asi que no hay conversion de bloqueo. Por defecto 0: todos los demas llamadores conservan el bloqueo exclusivo.
-- CULM-001 / DEC-065 (2): PASO 2.6, una sesion con solicitud en espera (EstadoSolicitudSesion.esFinal = 0) se rechaza con SES_023;
--   abrir toma/QR y registrar asistencia pasan todos por este validador.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_sesion_ventana_registro_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @toleranciaMinutos       INT = NULL,
    @margenMinutos           INT = NULL,
    @bloqueoCompartido       BIT = 0
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @existe              BIT = 0;
    DECLARE @fechaHoraInicio     DATETIME2;
    DECLARE @fechaHoraFin        DATETIME2;
    DECLARE @procedenciaTemporal NVARCHAR(24);
    DECLARE @instanteActualUtc   DATETIME2;
    DECLARE @toleranciaAplicada  INT = IIF(@toleranciaMinutos IS NULL OR @toleranciaMinutos < 0, 0, @toleranciaMinutos);
    DECLARE @margenAplicado      INT = IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos);
    DECLARE @aperturaUtc         DATETIME2;
    DECLARE @cierreUtc           DATETIME2;
    DECLARE @detalleVentana      NVARCHAR(200) = IIF(@toleranciaMinutos IS NULL AND @margenMinutos IS NULL,
                                                     dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
                                                     CONCAT(' Tolerancia: ', @toleranciaAplicada, ' min; margen: ', @margenAplicado, ' min.'));

    -- Inicialización de respuesta desde parámetros del catálogo
    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Lectura bloqueada del horario y su procedencia (misma fila, una sola sentencia)
        IF @estadoResultado = 1
        BEGIN
            IF @bloqueoCompartido = 1
                SELECT TOP 1
                    @existe = 1,
                    @fechaHoraInicio = s.fechaHoraInicio,
                    @fechaHoraFin = s.fechaHoraFin,
                    @procedenciaTemporal = s.procedenciaTemporal
                FROM dbo.Sesion s WITH (HOLDLOCK)
                WHERE s.id = @idSesionDefecto;
            ELSE
                SELECT TOP 1
                    @existe = 1,
                    @fechaHoraInicio = s.fechaHoraInicio,
                    @fechaHoraFin = s.fechaHoraFin,
                    @procedenciaTemporal = s.procedenciaTemporal
                FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
                WHERE s.id = @idSesionDefecto;

            IF @existe = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_001',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2.5 (CULM-001 B.1): sesion cancelada => SES_010 (lectura despues del bloqueo de la fila de dbo.Sesion)
        IF @estadoResultado = 1
           AND EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_010',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2.6 (DEC-065 (2)): sesion extraordinaria pendiente de aprobacion del coordinador => SES_023 (no admite tomas ni asistencia)
        IF @estadoResultado = 1
           AND EXISTS (SELECT 1 FROM dbo.SesionSolicitud ss
                       INNER JOIN dbo.EstadoSolicitudSesion es ON es.id = ss.idEstado
                       WHERE ss.sesion = @idSesionDefecto AND es.esFinal = 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_023',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Procedencia temporal confirmada (NULL o desconocida = INDETERMINADA)
        IF @estadoResultado = 1
           AND (@procedenciaTemporal IS NULL OR @procedenciaTemporal NOT IN (N'UTC_V2', N'UTC_GENERADOR', N'UTC_OWNER'))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_009',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Ventana [inicio - tolerancia, fin + margen) contra el reloj UTC del motor, leído después de obtener
        --         el bloqueo. Sin tolerancia ni margen es la ventana estricta [inicio, fin) de SES-01.
        IF @estadoResultado = 1
        BEGIN
            SET @instanteActualUtc = SYSUTCDATETIME();
            SET @aperturaUtc = DATEADD(MINUTE, -@toleranciaAplicada, @fechaHoraInicio);
            SET @cierreUtc = DATEADD(MINUTE, @margenAplicado, @fechaHoraFin);

            IF @instanteActualUtc < @aperturaUtc
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_007',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, @detalleVentana, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @instanteActualUtc >= @cierreUtc
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_008',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, @detalleVentana, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
GO
-- ---- schema/stored-procedures/usp_crear_sesion_interno.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: nucleo unico de creacion de sesion compartido por
--   * usp_crear_sesion    (v1, firma congelada DB-GP-001C) -> @procedenciaTemporal = NULL
--   * usp_crear_sesion_v2 (v2, instantes UTC confirmados)   -> @procedenciaTemporal = 'UTC_V2'
-- Las horas y la marca se escriben en el MISMO INSERT. Este SP no es publico: el rol runtime
-- tiene DENY EXECUTE directo y solo se alcanza por encadenamiento de propiedad desde los wrappers.
-- UTC_GENERADOR y UTC_OWNER NO se aceptan por esta via (generador y clasificacion propios).
-- CULM-001 A.2-10 (F-DOC-017): dentro de la transaccion y antes del INSERT, una sesion que se cruce con otra del grupo o
-- de otro grupo del mismo docente se rechaza con SES_017 (usp_validar_solape_sesion_interno); el rechazo no escribe.
-- CULM-001 / DEC-065 (2): la sesion creada por el docente nace con una solicitud PENDIENTE (SesionSolicitud, estado con esFinal = 0)
-- de aprobacion del coordinador, en la misma transaccion; el exito es SES_022. El ejecutor siempre es DOCENTE titular (PASOS 0-2.1).
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_sesion_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @procedenciaTemporal     NVARCHAR(24),
    @idCorrelacionResultado  UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idNuevoSesion   UNIQUEIDENTIFIER = NEWID();
    DECLARE @numeroSiguiente INT = 1;
    DECLARE @codigoSesion    NVARCHAR(50);
    DECLARE @idEstadoPendiente UNIQUEIDENTIFIER;

    -- Ownership transaccional (propia o savepoint bajo transacción externa)
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET @idCorrelacionResultado = @idCorrelacionDefecto;

    BEGIN TRY
        -- PASOS 0-1.6: procedencia, correlacion y seguridad antes de consultar el grupo.
        EXEC dbo.usp_validar_sesion_operacion_interno
            @idCorrelacion = @idCorrelacion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @procedenciaTemporal = @procedenciaTemporal,
            @fechaHoraInicio = @fechaHoraInicio,
            @fechaHoraFin = @fechaHoraFin,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @faseValidacion = 0;

        -- PASO 2: Validación de existencia del grupo académico
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.1: Titularidad del docente ejecutor sobre el grupo.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idGrupoDefecto,
                @tipoEntidadPadre = 'GRUPO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.5: conservar la prioridad contractual de entidad antes de fechas.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_operacion_interno
                @idCorrelacion = @idCorrelacion,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @procedenciaTemporal = @procedenciaTemporal,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @faseValidacion = 2;
        END

        -- PASO 3: Cálculo transaccional del correlativo de sesión e inserción
        -- (ownership transaccional: propia o savepoint bajo transacción externa)
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_crear_sesion;
                SET @savepointCreado = 1;
            END

            -- PASO 2.8 (CULM-001 A.2-10): solape con sesiones del grupo o del docente, bajo bloqueo
            EXEC dbo.usp_validar_solape_sesion_interno
                @idGrupo = @idGrupoDefecto,
                @idSesionExcluir = NULL,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.9 (DEC-065 (2)): estado en espera de la solicitud (catalogo; se resuelve por bandera, no por texto)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoPendiente = e.id
            FROM dbo.uv_estado_solicitud_sesion e
            WHERE e.esFinal = 0
            ORDER BY e.orden;

            IF @idEstadoPendiente IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'EstadoSolicitudSesion(esFinal = 0)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @numeroSiguiente = COALESCE(MAX(numero), 0) + 1
            FROM [dbo].[Sesion] WITH (UPDLOCK, HOLDLOCK)
            WHERE grupo = @idGrupoDefecto;

            SET @codigoSesion = CASE
                WHEN @numeroSiguiente < 100 THEN CONCAT('SES-', RIGHT('0' + CAST(@numeroSiguiente AS VARCHAR(10)), 2))
                ELSE CONCAT('SES-', CAST(@numeroSiguiente AS VARCHAR(10)))
            END;

            -- Horas y procedencia en la MISMA sentencia (UTC-D06).
            INSERT INTO dbo.Sesion (
                id, nombre, numero, codigo, numeroSemana, grupo,
                fechaHoraInicio, fechaHoraFin, procedenciaTemporal
            )
            VALUES (
                @idNuevoSesion,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Sesión #', @numeroSiguiente) END,
                @numeroSiguiente,
                @codigoSesion,
                @numeroSiguiente,
                @idGrupoDefecto,
                @fechaHoraInicio,
                @fechaHoraFin,
                @procedenciaTemporal
            );

            INSERT INTO dbo.SesionSolicitud (sesion, idEstado, usuarioSolicitante, fechaSolicitudUtc, idCorrelacion)
            VALUES (@idNuevoSesion, @idEstadoPendiente, @idUsuarioEjecutorDefecto, SYSUTCDATETIME(), @idCorrelacionDefecto);
        END

        -- Cierre de la transaccion propia (el rechazo por solape no escribe)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_022', @p_param1 = @idNuevoSesion, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones y reversión respetando ownership transaccional
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_crear_sesion;
        END

        -- Transacción externa condenada (XACT_STATE = -1) que no nos pertenece: propagar al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
GO
-- ---- schema/stored-procedures/usp_crear_grupo.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (4): solo el COORDINADOR crea grupos; el DOCENTE recibe SEC_001 (perfil requerido COORDINADOR).
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idAsignatura            UNIQUEIDENTIFIER,
    @idPeriodoAcademico      UNIQUEIDENTIFIER,
    @codigo                  INT,
    @nombre                  NVARCHAR(50),
    @idDocente               UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPeriodoAcademicoDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPeriodoAcademico, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto             NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idPeriodoResolved         UNIQUEIDENTIFIER = @idPeriodoAcademicoDefecto;
    DECLARE @capacidadMaximaDefecto    INT;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

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

        -- PASO 1.6 (DEC-065 (4)): solo el COORDINADOR crea grupos (el docente ya no los crea; el PASO 1.5 lo rechaza con SEC_001)

        -- PASO 2: Validar asignatura en uv_asignatura
        IF @estadoResultado = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[uv_asignatura] WHERE id = @idAsignaturaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'Asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Resolver período académico si viene nulo/guid defecto
        IF @estadoResultado = 1
        BEGIN
            IF @idPeriodoResolved IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_periodo_academico] WHERE id = @idPeriodoResolved)
            BEGIN
                SELECT TOP 1 @idPeriodoResolved = id 
                FROM [dbo].[uv_periodo_academico] 
                ORDER BY anio DESC;
            END

            IF @idPeriodoResolved IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_periodo_academico] WHERE id = @idPeriodoResolved)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'PeriodoAcademico',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Validar docente mediante procedimiento interno estandarizado
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_docente_exista_por_id_interno
                @idDocente = @idDocenteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4B (HU093/D12): el titular no puede tener su vinculo con el programa inactivado
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_docente_vinculo_activo_programa_interno
                @idDocente = @idDocenteDefecto,
                @idAsignatura = @idAsignaturaDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Validar unicidad de código de grupo en el período consultando uv_grupo
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (
                SELECT 1 FROM [dbo].[uv_grupo]
                WHERE idAsignatura = @idAsignaturaDefecto AND idPeriodoAcademico = @idPeriodoResolved AND codigo = @codigo
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_006',
                    @p_param1 = 'Grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 6: Resolver capacidad máxima por defecto desde el catálogo de parámetros (GRUPO/CAPACIDAD_MAXIMA_DEFECTO)
        IF @estadoResultado = 1
        BEGIN
            SET @capacidadMaximaDefecto = dbo.ufn_obtener_parametro_int(NULL, 'GRUPO', 'CAPACIDAD_MAXIMA_DEFECTO');

            IF @capacidadMaximaDefecto IS NULL OR @capacidadMaximaDefecto <= 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ERR_CAPACIDAD_GRUPO_INVALIDA',
                    @p_param1 = @capacidadMaximaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: Inserción directa de Grupo con capacidad máxima proveniente del catálogo
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.Grupo (
                id, asignatura, periodoAcademico, codigo, nombre,
                cantidadEstudiantes, cantidadEstudiantesFinalizaron,
                cantidadEstudiantesCancelaronVoluntadPropia,
                cantidadEstudiantesCancelaronAutomaticamente,
                docente
            )
            VALUES (
                @idGrupoDefecto,
                @idAsignaturaDefecto,
                @idPeriodoResolved,
                @codigo,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Grupo ', @codigo) END,
                @capacidadMaximaDefecto, 0, 0, 0,
                @idDocenteDefecto
            );

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
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
-- CULM-001 / DEC-065 (2): ademas devuelve la fila del DOCENTE titular (tipoDestinatario = 'DOCENTE', al final del orden) para que el backend
-- le avise la decision del coordinador; el aviso a la coordinacion al crear lo sigue dando la fila COORDINADOR.
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
        UNION ALL
        SELECT  tipoDestinatario = CAST(N'DOCENTE' AS NVARCHAR(20)),
                ordenTipo        = 3,
                idUsuario        = di.idUsuario,
                nombreCompleto   = CAST(di.nombreCompleto AS NVARCHAR(400)),
                correo           = ud.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = sm.fechaHoraInicio,
                fechaHoraFin     = sm.fechaHoraFin
        FROM dbo.uv_sesion_manual sm
        INNER JOIN dbo.uv_grupo g              ON g.id = sm.idGrupo
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente AND di.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario ud           ON ud.id = di.idUsuario
        WHERE sm.idSesion = @idSesionDefecto
    ) x
    ORDER BY x.ordenTipo, x.nombreCompleto, x.idUsuario;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_sesiones_grupo_paginado.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_grupo_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Búsqueda, programación e historial paginado de sesiones de clase para un grupo
--   académico consumiendo uv_auth_sesion. Aplica preservación estricta de SESSION_CONTEXT.
--   CULM-001 B.1 (CONTRACT §2.7.7): agrega al final estaCancelada, codigoTipoCancelacion, motivoCancelacion,
--   nombreDiaFestivo y fechaCancelacionUtc desde uv_sesion_estado (las sesiones canceladas se siguen listando).
--   CULM-001 / DEC-065 (2): un usuario que solo tiene perfil ESTUDIANTE no ve las sesiones extraordinarias pendientes de aprobacion
--   ni las rechazadas por el coordinador (nunca se le anunciaron); docente, coordinador y demas perfiles las ven (con su estado).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_grupo_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @fechaDesde              DATETIME2        = NULL,
    @fechaHasta              DATETIME2        = NULL,
    @numeroSemana            INT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginación normalizada
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroFechaDesde DATETIME2 = @fechaDesde;
    DECLARE @filtroFechaHasta DATETIME2 = @fechaHasta;
    DECLARE @filtroSemana INT = @numeroSemana;

    -- Control de diagnóstico y contexto
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @esSoloEstudiante BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        -- Paso 3: Validación obligatoria de idGrupo
        IF @estadoResultado = 1 AND (@idGrupoDefecto IS NULL OR @idGrupoDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 3.5 (DEC-065 (2)): perfil exclusivamente ESTUDIANTE => se ocultan las sesiones extraordinarias no aprobadas
        IF EXISTS (SELECT 1 FROM dbo.uv_usuario_perfil up WHERE up.idUsuario = @idUsuarioDefecto AND UPPER(up.nombrePerfil) = 'ESTUDIANTE')
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_usuario_perfil up WHERE up.idUsuario = @idUsuarioDefecto AND UPPER(up.nombrePerfil) <> 'ESTUDIANTE')
            SET @esSoloEstudiante = 1;

        -- Paso 4: Establecer identidad temporal en contexto para uv_auth_sesion
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @idUsuarioDefecto;

        -- Paso 5: Consulta optimizada de sesiones sobre la vista securizada
        SELECT
            s.id,
            s.idGrupo,
            s.codigoGrupo,
            s.nombreGrupo,
            s.nombre,
            s.numero,
            s.codigo,
            s.numeroSemana,
            s.fechaHoraInicio,
            s.fechaHoraFin,
            COUNT(1) OVER() AS totalRegistros,
            -- CULM-001 B.1 (CONTRACT §2.7.7): estado de la sesion desde uv_sesion_estado
            se.estaCancelada,
            se.codigoTipoCancelacion,
            se.motivoCancelacion,
            se.nombreDiaFestivo,
            se.fechaCancelacionUtc
        FROM dbo.uv_auth_sesion s
        INNER JOIN dbo.uv_sesion_estado se ON se.idSesion = s.id
        WHERE s.idGrupo = @idGrupoDefecto
          AND (@filtroFechaDesde IS NULL OR s.fechaHoraInicio >= @filtroFechaDesde)
          AND (@filtroFechaHasta IS NULL OR s.fechaHoraFin <= @filtroFechaHasta)
          AND (@filtroSemana IS NULL OR s.numeroSemana = @filtroSemana)
          AND (@esSoloEstudiante = 0
               OR NOT EXISTS (SELECT 1 FROM dbo.SesionSolicitud ssol
                              INNER JOIN dbo.EstadoSolicitudSesion esol ON esol.id = ssol.idEstado
                              WHERE ssol.sesion = s.id AND esol.esAprobada = 0))
        ORDER BY s.fechaHoraInicio ASC, s.numero ASC, s.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

        -- Paso 6: Restaurar el contexto previo
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;

    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
        THROW;
    END CATCH;
END;
GO
GO
-- ---- schema/seed/60_sesiones_manuales_catalogos.sql (bloque DEC-065)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- CULM-001 / DEC-065 (2): estados de la solicitud de una sesion extraordinaria (aval previo del coordinador) y el prefijo del motivo con el que
-- se registra la cancelacion al rechazarla. Los SP resuelven los estados por bandera: esFinal = 0 (en espera), esFinal = 1 y esAprobada = 1
-- (aprobada), esFinal = 1 y esAprobada = 0 (rechazada). Idempotente: el catalogo se actualiza por id; el parametro no pisa el valor administrado.
MERGE INTO [dbo].[EstadoSolicitudSesion] AS Target
USING (VALUES
    (CAST('7C1E0B10-5E51-4C0A-9B02-000000000001' AS UNIQUEIDENTIFIER), N'PENDIENTE', N'Pendiente de aprobación', 1, CAST(0 AS BIT), CAST(0 AS BIT)),
    (CAST('7C1E0B10-5E51-4C0A-9B02-000000000002' AS UNIQUEIDENTIFIER), N'APROBADA',  N'Aprobada',               2, CAST(1 AS BIT), CAST(1 AS BIT)),
    (CAST('7C1E0B10-5E51-4C0A-9B02-000000000003' AS UNIQUEIDENTIFIER), N'RECHAZADA', N'Rechazada',              3, CAST(1 AS BIT), CAST(0 AS BIT))
) AS Source (id, codigo, nombre, orden, esFinal, esAprobada)
ON (Target.id = Source.id)
WHEN MATCHED THEN
    UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.orden = Source.orden, Target.esFinal = Source.esFinal, Target.esAprobada = Source.esAprobada
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, orden, esFinal, esAprobada)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.orden, Source.esFinal, Source.esAprobada);
GO

MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('SESION', 'PREFIJO_MOTIVO_SOLICITUD_RECHAZADA', N'Solicitud rechazada', 'STRING', N'Solicitud rechazada')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
GO
-- ---- schema/seed/60_sesiones_manuales_mensajes.sql (bloque DEC-065)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- CULM-001 / DEC-065 (2): mensajes de la solicitud de sesion extraordinaria con aval del coordinador. Idempotente (MERGE por codigo).
--   SES_022 la sesion quedo registrada como solicitud pendiente (exito de la creacion por el docente).
--   SES_023 la sesion esta pendiente de aprobacion: no admite tomas ni asistencia (409).
--   SES_024 la solicitud ya fue resuelta (409).
--   SES_025 la sesion no tiene solicitud de aprobacion (409).
--   SES_026 la solicitud fue aprobada (exito).
--   SES_027 la solicitud fue rechazada y la sesion cancelada (exito).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('SES_022', 'SUCCESS',        'BAJO',  N'La sesión extraordinaria quedó registrada como solicitud pendiente de aprobación del coordinador del programa.'),
    ('SES_023', 'BUSINESS_ERROR', 'MEDIO', N'La sesión está pendiente de aprobación del coordinador.'),
    ('SES_024', 'BUSINESS_ERROR', 'MEDIO', N'La solicitud ya fue resuelta.'),
    ('SES_025', 'BUSINESS_ERROR', 'MEDIO', N'La sesión no tiene una solicitud de aprobación.'),
    ('SES_026', 'SUCCESS',        'BAJO',  N'La solicitud de sesión extraordinaria fue aprobada.'),
    ('SES_027', 'SUCCESS',        'BAJO',  N'La solicitud de sesión extraordinaria fue rechazada y la sesión quedó cancelada.')
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
    ('SES_022', 'SUCCESS',        'BAJO',  N'Sesión [{}] creada por el docente con solicitud PENDIENTE de aprobación del coordinador.'),
    ('SES_023', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la sesión [{}] tiene una solicitud en espera (EstadoSolicitudSesion.esFinal = 0); no admite tomas ni asistencia; sin escrituras.'),
    ('SES_024', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la solicitud de la sesión [{}] ya está en un estado final (aprobada o rechazada); sin escrituras.'),
    ('SES_025', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la sesión [{}] no tiene fila en SesionSolicitud (generada o anterior a DEC-065); sin escrituras.'),
    ('SES_026', 'SUCCESS',        'BAJO',  N'Solicitud de la sesión [{}] aprobada por el coordinador.'),
    ('SES_027', 'SUCCESS',        'BAJO',  N'Solicitud de la sesión [{}] rechazada por el coordinador; la sesión quedó cancelada (tipo manual).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
GO
-- ---- schema/seed/60_sesiones_manuales_plantillas.sql (bloque DEC-065)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
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
GO
-- ---- schema/security/rol_asistencias_runtime_sesiones_manuales.sql (bloque DEC-065)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- CULM-001 / DEC-065 (2): solicitud de sesion extraordinaria con aval del coordinador. EXECUTE sobre los SP publicos nuevos y SELECT sobre
-- las vistas nuevas (usp_validar_coordinador_sesion_interno no se concede: se alcanza por encadenamiento de propiedad). Aditivo e idempotente.
IF OBJECT_ID(N'dbo.usp_aprobar_solicitud_sesion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_aprobar_solicitud_sesion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_rechazar_solicitud_sesion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_rechazar_solicitud_sesion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_sesion_coordinador_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_solicitudes_sesion_coordinador_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_solicitud_sesion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_solicitud_sesion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_solicitud_sesion', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_solicitud_sesion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_estado_solicitud_sesion', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_estado_solicitud_sesion] TO [rol_asistencias_runtime];
GO
GO
PRINT 'MIGRACION 30 UP OK';
GO
