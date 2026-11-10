USE [gestionasistenciadb];
GO
-- CULM-001 / DEC-065 (2), (3) y (4) / HU030, HU047: solicitud de sesion extraordinaria con aval previo del coordinador.
--   MRM_00 objetos, catalogos, mensajes SES_022..SES_027 y plantillas de la solicitud
--   MRM_01 el docente crea la sesion manual (v1 y v2) => solicitud PENDIENTE y SES_022; la sesion del generador no lleva solicitud
--   MRM_02 uv_sesion_estado y uv_sesion_manual exponen estadoSolicitud y pendienteAprobacion; una pendiente no tiene ventana abierta
--   MRM_03 el estudiante no ve la pendiente (ni la rechazada) y si la aprobada; el docente la ve con su estado
--   MRM_04 una sesion pendiente no admite abrir tomas (SES_023)
--   MRM_05 aprobar: ambito (SEC_001 docente, SEC_002 fuera de ambito), SES_025 sin solicitud, aprobada, SES_024 si ya fue resuelta
--   MRM_06 rechazar: motivo (SES_019), observacion (SES_021), RECHAZADA + SesionCancelacion con el prefijo, SES_024 si ya fue resuelta
--   MRM_07 consulta paginada del coordinador: ambito, pendientes/todas, OFFSET/FETCH y totalRegistros, una fila por sesion en grupo mixto
--   MRM_08 destinatarios: la fila DOCENTE en usp_consultar_destinatarios_sesion_manual y usp_consultar_destinatarios_solicitud_sesion (coordinador)
--   MRM_09 el docente ya no crea grupos (SEC_001); el coordinador si
-- Todo dentro de transacciones revertidas; @@TRANCOUNT = 0 al terminar.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_mrm_solicitud_sesion';
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @tran INT = @@TRANCOUNT;

    -- MRM_00: objetos, catalogos y mensajes
    IF OBJECT_ID(N'dbo.SesionSolicitud', N'U') IS NULL OR OBJECT_ID(N'dbo.EstadoSolicitudSesion', N'U') IS NULL
       OR OBJECT_ID(N'dbo.uv_estado_solicitud_sesion', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_solicitud_sesion', N'V') IS NULL
       OR OBJECT_ID(N'dbo.usp_aprobar_solicitud_sesion', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_rechazar_solicitud_sesion', N'P') IS NULL
       OR OBJECT_ID(N'dbo.usp_consultar_solicitudes_sesion_coordinador_paginado', N'P') IS NULL
       OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_solicitud_sesion', N'P') IS NULL
        THROW 59001, 'TEST FAILED CULM001_MRM_00: faltan objetos de la solicitud de sesion (migracion 30).', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_estado_solicitud_sesion) <> 3
       OR (SELECT COUNT(*) FROM dbo.uv_estado_solicitud_sesion WHERE esFinal = 0) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estado_solicitud_sesion WHERE codigo = N'PENDIENTE' AND esFinal = 0 AND esAprobada = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estado_solicitud_sesion WHERE codigo = N'APROBADA' AND esFinal = 1 AND esAprobada = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estado_solicitud_sesion WHERE codigo = N'RECHAZADA' AND esFinal = 1 AND esAprobada = 0)
        THROW 59002, 'TEST FAILED CULM001_MRM_00: el catalogo EstadoSolicitudSesion debe tener PENDIENTE/APROBADA/RECHAZADA con sus banderas.', 1;
    IF EXISTS (SELECT 1 FROM (VALUES ('SES_022'), ('SES_023'), ('SES_024'), ('SES_025'), ('SES_026'), ('SES_027')) m(codigo)
               WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario u WHERE u.codigo = m.codigo) OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = m.codigo))
        THROW 59003, 'TEST FAILED CULM001_MRM_00: mensajes SES_022..SES_027 ausentes.', 1;
    IF (SELECT COUNT(*) FROM dbo.PlantillaNotificacion WHERE activa = 1 AND tipo IN ('SESION_SOLICITUD_CREADA_COORDINADOR', 'SESION_SOLICITUD_APROBADA_DOCENTE', 'SESION_SOLICITUD_RECHAZADA_DOCENTE')) <> 3
       OR (SELECT COUNT(*) FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN ('SESION_SOLICITUD_CREADA_COORDINADOR', 'SESION_SOLICITUD_APROBADA_DOCENTE', 'SESION_SOLICITUD_RECHAZADA_DOCENTE')) <> 23
        THROW 59004, 'TEST FAILED CULM001_MRM_00: plantillas SESION_SOLICITUD_* (3) o sus 23 marcadores ausentes.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_00_OBJETOS_Y_SEMILLAS';

    CREATE TABLE #mrm_r (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL);
    CREATE TABLE #mrm_can (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL,
        estadoResultado BIT NOT NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaCancelacionUtc DATETIME2(0) NULL, totalEstudiantesActivos INT NULL);
    CREATE TABLE #mrm_apr (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL,
        estadoResultado BIT NOT NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaHoraInicio DATETIME2 NULL, totalEstudiantesActivos INT NULL);

    -- MRM_01: el docente crea sesiones manuales por v2 y v1 => PENDIENTE + SES_022
    DECLARE @i1 DATETIME2 = DATEADD(DAY, 3, SYSUTCDATETIME()), @i2 DATETIME2 = DATEADD(DAY, 4, SYSUTCDATETIME());
    DECLARE @f1 DATETIME2 = DATEADD(HOUR, 2, @i1), @f2 DATETIME2 = DATEADD(HOUR, 2, @i2), @fMala DATETIME2 = DATEADD(HOUR, -2, @i1), @fk DATETIME2;
    DECLARE @msg022 NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SES_022');
    INSERT #mrm_r EXEC dbo.usp_crear_sesion_v2 @idGrupo = @grupoG, @nombre = N'MRM v2', @fechaHoraInicio = @i1, @fechaHoraFin = @f1, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF NOT EXISTS (SELECT 1 FROM #mrm_r WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]022|%' AND mensajeUsuarioResultado = @msg022 AND idCorrelacion = @c)
        THROW 59010, 'TEST FAILED CULM001_MRM_01: la creacion v2 del docente debe responder SES_022 (solicitud pendiente).', 1;
    TRUNCATE TABLE #mrm_r;
    INSERT #mrm_r EXEC dbo.usp_crear_sesion @idGrupo = @grupoG, @nombre = N'MRM v1', @fechaHoraInicio = @i2, @fechaHoraFin = @f2, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF NOT EXISTS (SELECT 1 FROM #mrm_r WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]022|%' AND mensajeUsuarioResultado = @msg022)
        THROW 59011, 'TEST FAILED CULM001_MRM_01: la creacion v1 del docente debe responder SES_022 (solicitud pendiente).', 1;
    TRUNCATE TABLE #mrm_r;
    DECLARE @sV2 UNIQUEIDENTIFIER = (SELECT id FROM dbo.Sesion WHERE grupo = @grupoG AND nombre = N'MRM v2');
    DECLARE @sV1 UNIQUEIDENTIFIER = (SELECT id FROM dbo.Sesion WHERE grupo = @grupoG AND nombre = N'MRM v1');
    IF @sV2 IS NULL OR @sV1 IS NULL THROW 59012, 'TEST FAILED CULM001_MRM_01: las sesiones creadas deben existir.', 1;
    IF (SELECT COUNT(*) FROM dbo.SesionSolicitud ss JOIN dbo.EstadoSolicitudSesion e ON e.id = ss.idEstado
        WHERE ss.sesion IN (@sV2, @sV1) AND e.codigo = N'PENDIENTE' AND e.esFinal = 0 AND ss.usuarioSolicitante = @uT AND ss.idCorrelacion = @c
          AND ss.usuarioResolucion IS NULL AND ss.fechaResolucionUtc IS NULL AND ss.observacion IS NULL) <> 2
        THROW 59013, 'TEST FAILED CULM001_MRM_01: cada sesion creada por el docente debe tener una solicitud PENDIENTE sin resolucion.', 1;

    -- una creacion rechazada (fechas invertidas) no deja ni sesion ni solicitud
    DECLARE @solicitudesAntes INT = (SELECT COUNT(*) FROM dbo.SesionSolicitud);
    INSERT #mrm_r EXEC dbo.usp_crear_sesion_v2 @idGrupo = @grupoG, @nombre = N'MRM mala', @fechaHoraInicio = @i1, @fechaHoraFin = @fMala, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF NOT EXISTS (SELECT 1 FROM #mrm_r WHERE estadoResultado = 0) OR (SELECT COUNT(*) FROM dbo.SesionSolicitud) <> @solicitudesAntes OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE nombre = N'MRM mala')
        THROW 59014, 'TEST FAILED CULM001_MRM_01: una creacion rechazada no debe dejar sesion ni solicitud.', 1;
    TRUNCATE TABLE #mrm_r;

    -- la sesion del generador (UTC_GENERADOR) no lleva solicitud
    DECLARE @sGen UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sGen, N'MRM generada', 902, N'MRM902', 1, @grupoG, DATEADD(DAY, 8, SYSUTCDATETIME()), DATEADD(MINUTE, 8 * 1440 + 120, SYSUTCDATETIME()), N'UTC_GENERADOR');
    IF EXISTS (SELECT 1 FROM dbo.SesionSolicitud WHERE sesion = @sGen)
        THROW 59015, 'TEST FAILED CULM001_MRM_01: la sesion del generador no debe tener solicitud.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_01_DOCENTE_CREA_SOLICITUD_PENDIENTE';

    -- MRM_02: vistas
    IF (SELECT COUNT(*) FROM dbo.uv_sesion_estado WHERE idSesion IN (@sV2, @sV1) AND estadoSolicitud = N'PENDIENTE' AND pendienteAprobacion = 1 AND ventanaAbierta = 0) <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sGen AND estadoSolicitud IS NULL AND pendienteAprobacion = 0)
        THROW 59020, 'TEST FAILED CULM001_MRM_02: uv_sesion_estado debe exponer estadoSolicitud/pendienteAprobacion (NULL/0 sin solicitud).', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_sesion_manual WHERE idSesion IN (@sV2, @sV1) AND estadoSolicitud = N'PENDIENTE' AND pendienteAprobacion = 1) <> 2
        THROW 59021, 'TEST FAILED CULM001_MRM_02: uv_sesion_manual debe exponer estadoSolicitud/pendienteAprobacion.', 1;
    -- una sesion pendiente en curso (ventana que si abriria sin solicitud) sigue con ventanaAbierta = 0
    DECLARE @sAhora UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sAhora, N'MRM ahora', 903, N'MRM903', 1, @grupoG, DATEADD(MINUTE, -10, SYSUTCDATETIME()), DATEADD(MINUTE, 110, SYSUTCDATETIME()), N'UTC_V2');
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sAhora AND ventanaAbierta = 1 AND estadoSolicitud IS NULL)
        THROW 59022, 'TEST FAILED CULM001_MRM_02: una sesion en curso sin solicitud debe tener la ventana abierta.', 1;
    INSERT dbo.SesionSolicitud (sesion, idEstado, usuarioSolicitante, idCorrelacion)
    SELECT @sAhora, e.id, @uT, @c FROM dbo.EstadoSolicitudSesion e WHERE e.esFinal = 0;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sAhora AND ventanaAbierta = 0 AND pendienteAprobacion = 1)
        THROW 59023, 'TEST FAILED CULM001_MRM_02: la misma sesion en curso pero pendiente no debe tener la ventana abierta.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_02_VISTAS_ESTADO_SOLICITUD';

    -- MRM_03: el estudiante no ve la pendiente
    CREATE TABLE #mrm_sm (id UNIQUEIDENTIFIER, nombre NVARCHAR(200), numero INT, codigo NVARCHAR(50), numeroSemana INT, idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
        nombreGrupo NVARCHAR(200), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2, fechaLimiteJustificacionUtc DATETIME2 NULL, plazoJustificacionVigente BIT NULL, totalRegistros INT);
    INSERT #mrm_sm EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uEA, @idCorrelacion = @c, @idMateria = @asigOPT;
    IF EXISTS (SELECT 1 FROM #mrm_sm WHERE id IN (@sV2, @sV1, @sAhora)) OR NOT EXISTS (SELECT 1 FROM #mrm_sm WHERE id = @sGen)
        THROW 59030, 'TEST FAILED CULM001_MRM_03: el estudiante no debe ver las sesiones pendientes y si la del generador.', 1;
    TRUNCATE TABLE #mrm_sm;
    CREATE TABLE #mrm_sg (id UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(200), nombre NVARCHAR(200), numero INT, codigo NVARCHAR(50),
        numeroSemana INT, fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2, totalRegistros INT, estaCancelada BIT, codigoTipoCancelacion NVARCHAR(50), motivoCancelacion NVARCHAR(500),
        nombreDiaFestivo NVARCHAR(200), fechaCancelacionUtc DATETIME2 NULL);
    INSERT #mrm_sg EXEC dbo.usp_consultar_sesiones_grupo_paginado @idUsuarioEjecutor = @uT, @idCorrelacion = @c, @idGrupo = @grupoG, @numeroPagina = 1, @tamanoPagina = 50;
    IF NOT EXISTS (SELECT 1 FROM #mrm_sg WHERE id = @sV2) OR NOT EXISTS (SELECT 1 FROM #mrm_sg WHERE id = @sV1) OR NOT EXISTS (SELECT 1 FROM #mrm_sg WHERE id = @sGen)
        THROW 59031, 'TEST FAILED CULM001_MRM_03: el docente debe ver sus sesiones pendientes y las demas.', 1;
    TRUNCATE TABLE #mrm_sg;
    INSERT #mrm_sg EXEC dbo.usp_consultar_sesiones_grupo_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @idGrupo = @grupoG, @numeroPagina = 1, @tamanoPagina = 50;
    IF NOT EXISTS (SELECT 1 FROM #mrm_sg WHERE id = @sV2)
        THROW 59032, 'TEST FAILED CULM001_MRM_03: el coordinador debe ver las sesiones pendientes del grupo.', 1;
    TRUNCATE TABLE #mrm_sg;
    INSERT #mrm_sg EXEC dbo.usp_consultar_sesiones_grupo_paginado @idUsuarioEjecutor = @uEA, @idCorrelacion = @c, @idGrupo = @grupoG, @numeroPagina = 1, @tamanoPagina = 50;
    IF EXISTS (SELECT 1 FROM #mrm_sg WHERE id IN (@sV2, @sV1, @sAhora))
        THROW 59033, 'TEST FAILED CULM001_MRM_03: la consulta por grupo no debe mostrar al estudiante las sesiones pendientes.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_03_ESTUDIANTE_NO_VE_PENDIENTE';

    -- MRM_04: una sesion pendiente no admite abrir tomas (SES_023), aun en curso
    DECLARE @modo NVARCHAR(20) = (SELECT TOP 1 codigo FROM dbo.ModoTomaAsistencia ORDER BY codigo);
    CREATE TABLE #mrm_tom (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL,
        idToma UNIQUEIDENTIFIER NULL, numero INT NULL, codigoModo NVARCHAR(20) NULL, usaCodigoQr BIT NULL, fechaAperturaUtc DATETIME2 NULL, ventanaCierreUtc DATETIME2 NULL,
        totalTomasSesion INT NULL, horasToma DECIMAL(12,6) NULL);
    INSERT #mrm_tom EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sAhora, @codigoModo = @modo, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF NOT EXISTS (SELECT 1 FROM #mrm_tom WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]023|%') OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia WHERE sesion = @sAhora)
        THROW 59040, 'TEST FAILED CULM001_MRM_04: abrir una toma en una sesion pendiente debe responder SES_023 sin escrituras.', 1;
    TRUNCATE TABLE #mrm_tom;
    PRINT 'TEST_PASS:CULM001_MRM_04_PENDIENTE_NO_ADMITE_TOMAS';

    -- MRM_05: aprobar
    DECLARE @uCX UNIQUEIDENTIFIER = NEWID(), @coordCX UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uCX, @tipoCC, 1950000098, N'MRM', N'', N'CoordX', N'', N'mrm.coordx@fixture.invalid', 1, 1, N'FIXTURE_DISABLED_ACCOUNT');
    INSERT INTO dbo.Coordinador (id, usuario, estado, facultad) VALUES (@coordCX, @uCX, 1, @fac);

    INSERT #mrm_apr EXEC dbo.usp_aprobar_solicitud_sesion @idSesion = @sV2, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF NOT EXISTS (SELECT 1 FROM #mrm_apr WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%' AND idSesion IS NULL)
        THROW 59050, 'TEST FAILED CULM001_MRM_05: el docente no puede aprobar (SEC_001).', 1;
    TRUNCATE TABLE #mrm_apr;
    INSERT #mrm_apr EXEC dbo.usp_aprobar_solicitud_sesion @idSesion = @sV2, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCX;
    IF NOT EXISTS (SELECT 1 FROM #mrm_apr WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]002|%' AND idSesion IS NULL)
        THROW 59051, 'TEST FAILED CULM001_MRM_05: un coordinador fuera de ambito debe recibir SEC_002.', 1;
    TRUNCATE TABLE #mrm_apr;
    INSERT #mrm_apr EXEC dbo.usp_aprobar_solicitud_sesion @idSesion = @sGen, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #mrm_apr WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]025|%')
        THROW 59052, 'TEST FAILED CULM001_MRM_05: aprobar una sesion sin solicitud debe responder SES_025.', 1;
    TRUNCATE TABLE #mrm_apr;
    IF EXISTS (SELECT 1 FROM dbo.SesionSolicitud ss JOIN dbo.EstadoSolicitudSesion e ON e.id = ss.idEstado WHERE ss.sesion = @sV2 AND e.esFinal = 1)
        THROW 59053, 'TEST FAILED CULM001_MRM_05: los rechazos de validacion no deben escribir.', 1;

    INSERT #mrm_apr EXEC dbo.usp_aprobar_solicitud_sesion @idSesion = @sV2, @observacion = N'  Autorizada por calendario  ', @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #mrm_apr WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]026|%' AND idSesion = @sV2 AND idGrupo = @grupoG
                   AND fechaHoraInicio IS NOT NULL AND totalEstudiantesActivos = 3 AND idCorrelacion = @c)
        THROW 59054, 'TEST FAILED CULM001_MRM_05: aprobar debe responder SES_026 con sesion, grupo, fecha de inicio y 3 estudiantes activos.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.SesionSolicitud ss JOIN dbo.EstadoSolicitudSesion e ON e.id = ss.idEstado
                   WHERE ss.sesion = @sV2 AND e.codigo = N'APROBADA' AND ss.usuarioResolucion = @uCA AND ss.fechaResolucionUtc IS NOT NULL AND ss.observacion = N'Autorizada por calendario')
        THROW 59055, 'TEST FAILED CULM001_MRM_05: la solicitud debe quedar APROBADA con usuario, fecha y observacion recortada.', 1;
    IF EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sV2)
        THROW 59056, 'TEST FAILED CULM001_MRM_05: aprobar no cancela la sesion.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sV2 AND estadoSolicitud = N'APROBADA' AND pendienteAprobacion = 0)
        THROW 59057, 'TEST FAILED CULM001_MRM_05: uv_sesion_estado debe reflejar APROBADA.', 1;
    IF @@TRANCOUNT <> @tran THROW 59058, 'TEST FAILED CULM001_MRM_05: el SP no debe alterar el nivel de transacciones.', 1;
    TRUNCATE TABLE #mrm_apr;
    INSERT #mrm_apr EXEC dbo.usp_aprobar_solicitud_sesion @idSesion = @sV2, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #mrm_apr WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]024|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.SesionSolicitud WHERE sesion = @sV2 AND observacion = N'Autorizada por calendario')
        THROW 59059, 'TEST FAILED CULM001_MRM_05: aprobar una solicitud ya resuelta debe responder SES_024 sin cambiar nada.', 1;
    TRUNCATE TABLE #mrm_apr;
    -- aprobada: el estudiante ya la ve y la pendiente de abrir toma deja de bloquear
    INSERT #mrm_sm EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uEA, @idCorrelacion = @c, @idMateria = @asigOPT;
    IF NOT EXISTS (SELECT 1 FROM #mrm_sm WHERE id = @sV2) OR EXISTS (SELECT 1 FROM #mrm_sm WHERE id = @sV1)
        THROW 59060, 'TEST FAILED CULM001_MRM_05: el estudiante ve la aprobada y sigue sin ver la pendiente.', 1;
    TRUNCATE TABLE #mrm_sm;
    PRINT 'TEST_PASS:CULM001_MRM_05_APROBAR';

    -- aprobar con observacion larga => SES_021 (sobre otra pendiente, sin escrituras)
    DECLARE @obsLarga NVARCHAR(500) = REPLICATE(N'y', 500);
    INSERT #mrm_apr EXEC dbo.usp_aprobar_solicitud_sesion @idSesion = @sV1, @observacion = @obsLarga, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #mrm_apr WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]021|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sV1 AND pendienteAprobacion = 1)
        THROW 59061, 'TEST FAILED CULM001_MRM_05: una observacion demasiado larga debe responder SES_021 sin escrituras.', 1;
    TRUNCATE TABLE #mrm_apr;

    -- MRM_06: rechazar (el otro coordinador del grupo mixto, CB)
    DECLARE @motivo NVARCHAR(50) = (SELECT TOP 1 codigo FROM dbo.uv_motivo_cancelacion_sesion WHERE estaActivo = 1 ORDER BY orden);
    DECLARE @nombreMotivo NVARCHAR(200) = (SELECT TOP 1 nombre FROM dbo.uv_motivo_cancelacion_sesion WHERE estaActivo = 1 ORDER BY orden);
    DECLARE @prefijo NVARCHAR(200) = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'SESION', 'PREFIJO_MOTIVO_SOLICITUD_RECHAZADA') AS NVARCHAR(200));
    INSERT #mrm_can EXEC dbo.usp_rechazar_solicitud_sesion @idSesion = @sV1, @codigoMotivo = N'NO_EXISTE', @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCB;
    IF NOT EXISTS (SELECT 1 FROM #mrm_can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]019|%') OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sV1)
        THROW 59070, 'TEST FAILED CULM001_MRM_06: un motivo fuera del catalogo debe responder SES_019 sin escrituras.', 1;
    TRUNCATE TABLE #mrm_can;
    INSERT #mrm_can EXEC dbo.usp_rechazar_solicitud_sesion @idSesion = @sV1, @codigoMotivo = @motivo, @observacion = @obsLarga, @idCorrelacion = @c, @idUsuarioEjecutor = @uCB;
    IF NOT EXISTS (SELECT 1 FROM #mrm_can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]021|%') OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sV1)
        THROW 59071, 'TEST FAILED CULM001_MRM_06: una observacion demasiado larga debe responder SES_021 sin escrituras.', 1;
    TRUNCATE TABLE #mrm_can;
    INSERT #mrm_can EXEC dbo.usp_rechazar_solicitud_sesion @idSesion = @sV1, @codigoMotivo = @motivo, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCX;
    IF NOT EXISTS (SELECT 1 FROM #mrm_can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]002|%') OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sV1)
        THROW 59072, 'TEST FAILED CULM001_MRM_06: un coordinador fuera de ambito debe recibir SEC_002.', 1;
    TRUNCATE TABLE #mrm_can;
    INSERT #mrm_can EXEC dbo.usp_rechazar_solicitud_sesion @idSesion = @sV1, @codigoMotivo = @motivo, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF NOT EXISTS (SELECT 1 FROM #mrm_can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%')
        THROW 59073, 'TEST FAILED CULM001_MRM_06: el docente no puede rechazar (SEC_001).', 1;
    TRUNCATE TABLE #mrm_can;
    INSERT #mrm_can EXEC dbo.usp_rechazar_solicitud_sesion @idSesion = @sGen, @codigoMotivo = @motivo, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #mrm_can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]025|%') OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sGen)
        THROW 59074, 'TEST FAILED CULM001_MRM_06: rechazar una sesion sin solicitud debe responder SES_025 y no cancelarla.', 1;
    TRUNCATE TABLE #mrm_can;

    INSERT #mrm_can EXEC dbo.usp_rechazar_solicitud_sesion @idSesion = @sV1, @codigoMotivo = @motivo, @observacion = N'  Reprogramar  ', @idCorrelacion = @c, @idUsuarioEjecutor = @uCB;
    IF NOT EXISTS (SELECT 1 FROM #mrm_can WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]027|%' AND idSesion = @sV1 AND idGrupo = @grupoG
                   AND fechaCancelacionUtc IS NOT NULL AND totalEstudiantesActivos = 3 AND idCorrelacion = @c)
        THROW 59075, 'TEST FAILED CULM001_MRM_06: rechazar debe responder SES_027 con la sesion, el grupo y 3 estudiantes activos.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.SesionSolicitud ss JOIN dbo.EstadoSolicitudSesion e ON e.id = ss.idEstado
                   WHERE ss.sesion = @sV1 AND e.codigo = N'RECHAZADA' AND ss.usuarioResolucion = @uCB AND ss.fechaResolucionUtc IS NOT NULL AND ss.observacion = N'Reprogramar')
        THROW 59076, 'TEST FAILED CULM001_MRM_06: la solicitud debe quedar RECHAZADA con usuario, fecha y observacion.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.TipoCancelacionSesion t ON t.id = sc.tipoCancelacion
                   WHERE sc.sesion = @sV1 AND t.esAutomatica = 0 AND sc.usuarioEjecutor = @uCB AND sc.diaFestivo IS NULL AND sc.idCorrelacion = @c
                     AND sc.motivo = CONCAT(@prefijo, N': ', @nombreMotivo, N': Reprogramar'))
        THROW 59077, 'TEST FAILED CULM001_MRM_06: SesionCancelacion debe tener el motivo con el prefijo de solicitud rechazada, el motivo del catalogo y la observacion.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sV1 AND estaCancelada = 1 AND estadoSolicitud = N'RECHAZADA' AND pendienteAprobacion = 0 AND idUsuarioCancelacion = @uCB)
        THROW 59078, 'TEST FAILED CULM001_MRM_06: uv_sesion_estado debe reflejar la sesion cancelada y la solicitud RECHAZADA.', 1;
    TRUNCATE TABLE #mrm_can;
    INSERT #mrm_can EXEC dbo.usp_rechazar_solicitud_sesion @idSesion = @sV1, @codigoMotivo = @motivo, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCB;
    INSERT #mrm_apr EXEC dbo.usp_aprobar_solicitud_sesion @idSesion = @sV1, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCB;
    IF NOT EXISTS (SELECT 1 FROM #mrm_can WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]024|%')
       OR NOT EXISTS (SELECT 1 FROM #mrm_apr WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]024|%')
        THROW 59079, 'TEST FAILED CULM001_MRM_06: rechazar o aprobar una solicitud ya resuelta debe responder SES_024.', 1;
    TRUNCATE TABLE #mrm_can; TRUNCATE TABLE #mrm_apr;
    -- la rechazada no la ve el estudiante
    INSERT #mrm_sm EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @uEA, @idCorrelacion = @c, @idMateria = @asigOPT;
    IF EXISTS (SELECT 1 FROM #mrm_sm WHERE id = @sV1)
        THROW 59080, 'TEST FAILED CULM001_MRM_06: el estudiante no debe ver la sesion rechazada.', 1;
    TRUNCATE TABLE #mrm_sm;
    PRINT 'TEST_PASS:CULM001_MRM_06_RECHAZAR';

    -- MRM_07: consulta paginada del coordinador (3 pendientes nuevas + la en curso ya existente = 4; una aprobada, una rechazada)
    DECLARE @k INT = 0, @ik DATETIME2;
    WHILE @k < 3
    BEGIN
        SET @ik = DATEADD(DAY, 10 + @k, SYSUTCDATETIME());
        SET @fk = DATEADD(HOUR, 2, @ik);
        INSERT #mrm_r EXEC dbo.usp_crear_sesion_v2 @idGrupo = @grupoG, @nombre = N'MRM pag', @fechaHoraInicio = @ik, @fechaHoraFin = @fk, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
        SET @k += 1;
    END
    IF (SELECT COUNT(*) FROM #mrm_r WHERE estadoResultado = 1) <> 3 THROW 59090, 'TEST FAILED CULM001_MRM_07: las 3 sesiones de paginacion debieron crearse.', 1;
    TRUNCATE TABLE #mrm_r;
    -- CA coordina tambien el programa B: el grupo mixto no duplica filas
    DECLARE @coordCA UNIQUEIDENTIFIER = (SELECT id FROM dbo.Coordinador WHERE usuario = @uCA);
    UPDATE dbo.Programa SET coordinador = @coordCA WHERE id = @progB;
    CREATE TABLE #mrm_sol (idSesion UNIQUEIDENTIFIER, nombreSesion NVARCHAR(200), codigoSesion NVARCHAR(50), idGrupo UNIQUEIDENTIFIER, nombreGrupo NVARCHAR(200), nombreAsignatura NVARCHAR(200),
        idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(200), idDocente UNIQUEIDENTIFIER, nombreDocente NVARCHAR(400), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2,
        estadoSolicitud NVARCHAR(30), nombreEstadoSolicitud NVARCHAR(100), fechaSolicitudUtc DATETIME2, fechaResolucionUtc DATETIME2 NULL, observacion NVARCHAR(500) NULL,
        usuarioSolicitante UNIQUEIDENTIFIER, pendienteAprobacion BIT, estaCancelada BIT, totalRegistros INT);
    INSERT #mrm_sol EXEC dbo.usp_consultar_solicitudes_sesion_coordinador_paginado @idUsuario = @uCA, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #mrm_sol) <> 4 OR EXISTS (SELECT 1 FROM #mrm_sol WHERE totalRegistros <> 4 OR pendienteAprobacion <> 1 OR estadoSolicitud <> N'PENDIENTE')
       OR EXISTS (SELECT 1 FROM #mrm_sol GROUP BY idSesion HAVING COUNT(*) > 1) OR EXISTS (SELECT 1 FROM #mrm_sol WHERE idSesion IN (@sV2, @sV1, @sGen))
       OR EXISTS (SELECT 1 FROM #mrm_sol WHERE nombreAsignatura IS NULL OR nombreDocente IS NULL OR nombrePrograma IS NULL OR nombreGrupo IS NULL)
        THROW 59091, 'TEST FAILED CULM001_MRM_07: por defecto solo las 4 pendientes del ambito, una fila por sesion aunque el grupo sea mixto.', 1;
    IF EXISTS (SELECT 1 FROM (SELECT fechaSolicitudUtc, prev = LAG(fechaSolicitudUtc) OVER (ORDER BY (SELECT NULL)) FROM #mrm_sol) x WHERE prev < fechaSolicitudUtc)
        THROW 59092, 'TEST FAILED CULM001_MRM_07: el orden debe ser fechaSolicitudUtc DESC.', 1;
    TRUNCATE TABLE #mrm_sol;
    INSERT #mrm_sol EXEC dbo.usp_consultar_solicitudes_sesion_coordinador_paginado @idUsuario = @uCA, @soloPendientes = 0, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #mrm_sol) <> 6 OR NOT EXISTS (SELECT 1 FROM #mrm_sol WHERE idSesion = @sV2 AND estadoSolicitud = N'APROBADA' AND fechaResolucionUtc IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM #mrm_sol WHERE idSesion = @sV1 AND estadoSolicitud = N'RECHAZADA' AND estaCancelada = 1 AND pendienteAprobacion = 0)
       OR EXISTS (SELECT 1 FROM #mrm_sol WHERE totalRegistros <> 6)
        THROW 59093, 'TEST FAILED CULM001_MRM_07: con soloPendientes = 0 se listan las 6 solicitudes (aprobada y rechazada incluidas).', 1;
    TRUNCATE TABLE #mrm_sol;
    INSERT #mrm_sol EXEC dbo.usp_consultar_solicitudes_sesion_coordinador_paginado @idUsuario = @uCA, @soloPendientes = 0, @numeroPagina = 1, @tamanoPagina = 4, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #mrm_sol) <> 4 OR EXISTS (SELECT 1 FROM #mrm_sol WHERE totalRegistros <> 6)
        THROW 59094, 'TEST FAILED CULM001_MRM_07: la pagina 1 de tamano 4 trae 4 filas y totalRegistros = 6.', 1;
    TRUNCATE TABLE #mrm_sol;
    INSERT #mrm_sol EXEC dbo.usp_consultar_solicitudes_sesion_coordinador_paginado @idUsuario = @uCA, @soloPendientes = 0, @numeroPagina = 2, @tamanoPagina = 4, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #mrm_sol) <> 2 OR EXISTS (SELECT 1 FROM #mrm_sol WHERE totalRegistros <> 6)
        THROW 59095, 'TEST FAILED CULM001_MRM_07: la pagina 2 de tamano 4 trae las 2 filas restantes y totalRegistros = 6.', 1;
    TRUNCATE TABLE #mrm_sol;
    INSERT #mrm_sol EXEC dbo.usp_consultar_solicitudes_sesion_coordinador_paginado @idUsuario = @uCA, @soloPendientes = 1, @idPrograma = @progB, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #mrm_sol) <> 4 OR EXISTS (SELECT 1 FROM #mrm_sol WHERE idPrograma <> @progB)
        THROW 59096, 'TEST FAILED CULM001_MRM_07: el filtro por programa devuelve las pendientes del programa B.', 1;
    TRUNCATE TABLE #mrm_sol;
    INSERT #mrm_sol EXEC dbo.usp_consultar_solicitudes_sesion_coordinador_paginado @idUsuario = @uCA, @soloPendientes = 0, @idGrupo = @grupoG, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #mrm_sol) <> 6
        THROW 59097, 'TEST FAILED CULM001_MRM_07: el filtro por grupo devuelve las 6 solicitudes del grupo.', 1;
    TRUNCATE TABLE #mrm_sol;
    INSERT #mrm_sol EXEC dbo.usp_consultar_solicitudes_sesion_coordinador_paginado @idUsuario = @uCX, @soloPendientes = 0, @idCorrelacion = @c;
    IF EXISTS (SELECT 1 FROM #mrm_sol)
        THROW 59098, 'TEST FAILED CULM001_MRM_07: un coordinador sin programas del grupo no ve solicitudes ajenas.', 1;
    TRUNCATE TABLE #mrm_sol;
    UPDATE dbo.Programa SET coordinador = (SELECT id FROM dbo.Coordinador WHERE usuario = @uCB) WHERE id = @progB;
    -- un coordinador que solo coordina B ve las mismas solicitudes del grupo mixto (los dos programas lo incluyen)
    INSERT #mrm_sol EXEC dbo.usp_consultar_solicitudes_sesion_coordinador_paginado @idUsuario = @uCB, @soloPendientes = 1, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #mrm_sol) <> 4 OR EXISTS (SELECT 1 FROM #mrm_sol WHERE idPrograma <> @progB)
        THROW 59099, 'TEST FAILED CULM001_MRM_07: el otro coordinador del grupo mixto ve las mismas 4 pendientes por el programa B.', 1;
    TRUNCATE TABLE #mrm_sol;
    PRINT 'TEST_PASS:CULM001_MRM_07_CONSULTA_PAGINADA_COORDINADOR';

    -- MRM_08: destinatarios
    CREATE TABLE #mrm_dest (tipoDestinatario NVARCHAR(20), idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(200),
        nombreAsignatura NVARCHAR(200), nombreGrupo NVARCHAR(300), nombreDocente NVARCHAR(400), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2);
    INSERT #mrm_dest EXEC dbo.usp_consultar_destinatarios_sesion_manual @idSesion = @sV2, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF (SELECT COUNT(*) FROM #mrm_dest WHERE tipoDestinatario = N'DOCENTE') <> 1 OR NOT EXISTS (SELECT 1 FROM #mrm_dest WHERE tipoDestinatario = N'DOCENTE' AND idUsuario = @uT AND correo IS NOT NULL AND nombreCompleto IS NOT NULL)
       OR (SELECT COUNT(*) FROM #mrm_dest WHERE tipoDestinatario = N'ESTUDIANTE') <> 3 OR (SELECT COUNT(*) FROM #mrm_dest WHERE tipoDestinatario = N'COORDINADOR') <> 2
        THROW 59100, 'TEST FAILED CULM001_MRM_08: los destinatarios de la sesion manual incluyen al DOCENTE titular (1), 3 estudiantes y 2 coordinadores.', 1;
    TRUNCATE TABLE #mrm_dest;
    INSERT #mrm_dest EXEC dbo.usp_consultar_destinatarios_solicitud_sesion @idSesion = @sV2, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF (SELECT COUNT(*) FROM #mrm_dest WHERE tipoDestinatario = N'DOCENTE') <> 1 OR NOT EXISTS (SELECT 1 FROM #mrm_dest WHERE tipoDestinatario = N'DOCENTE' AND idUsuario = @uT AND correo IS NOT NULL)
       OR (SELECT COUNT(*) FROM #mrm_dest WHERE tipoDestinatario = N'ESTUDIANTE') <> 3 OR EXISTS (SELECT 1 FROM #mrm_dest WHERE tipoDestinatario NOT IN (N'DOCENTE', N'ESTUDIANTE'))
       OR EXISTS (SELECT 1 FROM #mrm_dest WHERE nombreAsignatura IS NULL OR nombreDocente IS NULL OR fechaHoraInicio IS NULL OR fechaHoraFin IS NULL)
        THROW 59101, 'TEST FAILED CULM001_MRM_08: el coordinador obtiene el DOCENTE titular y los 3 estudiantes activos de la solicitud.', 1;
    TRUNCATE TABLE #mrm_dest;
    INSERT #mrm_dest EXEC dbo.usp_consultar_destinatarios_solicitud_sesion @idSesion = @sV1, @idCorrelacion = @c, @idUsuarioEjecutor = @uCB;
    IF (SELECT COUNT(*) FROM #mrm_dest) <> 4
        THROW 59102, 'TEST FAILED CULM001_MRM_08: el segundo coordinador del grupo mixto tambien obtiene los destinatarios (docente + 3 estudiantes).', 1;
    TRUNCATE TABLE #mrm_dest;
    INSERT #mrm_dest EXEC dbo.usp_consultar_destinatarios_solicitud_sesion @idSesion = @sGen, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF EXISTS (SELECT 1 FROM #mrm_dest)
        THROW 59103, 'TEST FAILED CULM001_MRM_08: una sesion sin solicitud no tiene destinatarios de solicitud.', 1;
    TRUNCATE TABLE #mrm_dest;
    PRINT 'TEST_PASS:CULM001_MRM_08_DESTINATARIOS';

    -- MRM_09: el docente ya no crea grupos; el coordinador si
    DECLARE @gNuevo UNIQUEIDENTIFIER = NEWID(), @gNuevo2 UNIQUEIDENTIFIER = NEWID(), @codNuevo INT = (SELECT ISNULL(MAX(codigo), 0) + 1 FROM dbo.Grupo);
    DECLARE @msgSec001 NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'SEC_001');
    INSERT #mrm_r EXEC dbo.usp_crear_grupo @idGrupo = @gNuevo, @idAsignatura = @asigOPT, @idPeriodoAcademico = @periodo, @codigo = @codNuevo, @nombre = N'MRM docente',
        @idDocente = @docT, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF NOT EXISTS (SELECT 1 FROM #mrm_r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%') OR EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @gNuevo)
        THROW 59110, 'TEST FAILED CULM001_MRM_09: el docente no puede crear grupos (SEC_001) ni a su propio nombre.', 1;
    TRUNCATE TABLE #mrm_r;
    INSERT #mrm_r EXEC dbo.usp_crear_grupo @idGrupo = @gNuevo2, @idAsignatura = @asigOPT, @idPeriodoAcademico = @periodo, @codigo = @codNuevo, @nombre = N'MRM coordinador',
        @idDocente = @docT, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #mrm_r WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @gNuevo2 AND docente = @docT)
        THROW 59111, 'TEST FAILED CULM001_MRM_09: el coordinador si crea grupos.', 1;
    TRUNCATE TABLE #mrm_r;
    PRINT 'TEST_PASS:CULM001_MRM_09_GRUPOS_SOLO_COORDINADOR';

    IF @@TRANCOUNT <> @tran THROW 59119, 'TEST FAILED CULM001_MRM: los SP no deben alterar el nivel de transacciones.', 1;
    PRINT 'TEST_PASS:CULM001_MRM_SOLICITUD_SESION';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 59199, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

-- MRM_08/MRM_07 (rechazos por THROW 51000): fuera de la transaccion principal, porque el THROW de un SP de consulta con SET XACT_ABORT ON
-- condena la transaccion del llamador. Cada caso corre en su propia transaccion que se revierte.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c1 UNIQUEIDENTIFIER = NEWID(), @s1 UNIQUEIDENTIFIER = NEWID(), @err1 NVARCHAR(4000) = NULL;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s1, N'MRM thr', 951, N'MRM951', 1, @grupoG, DATEADD(DAY, 3, SYSUTCDATETIME()), DATEADD(MINUTE, 3 * 1440 + 120, SYSUTCDATETIME()), N'UTC_V2');
    INSERT dbo.SesionSolicitud (sesion, idEstado, usuarioSolicitante, idCorrelacion) SELECT @s1, e.id, @uT, @c1 FROM dbo.EstadoSolicitudSesion e WHERE e.esFinal = 0;
    CREATE TABLE #mrm_d1 (tipoDestinatario NVARCHAR(20), idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(200),
        nombreAsignatura NVARCHAR(200), nombreGrupo NVARCHAR(300), nombreDocente NVARCHAR(400), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2);
    -- el docente no consulta los destinatarios de la solicitud (SEC_001: es del coordinador)
    BEGIN TRY
        INSERT #mrm_d1 EXEC dbo.usp_consultar_destinatarios_solicitud_sesion @idSesion = @s1, @idCorrelacion = @c1, @idUsuarioEjecutor = @uT;
    END TRY
    BEGIN CATCH
        SET @err1 = ERROR_MESSAGE();
    END CATCH;
    IF @err1 IS NULL OR @err1 NOT LIKE N'%DBCODE=SEC[_]001|%' OR EXISTS (SELECT 1 FROM #mrm_d1)
        THROW 59120, 'TEST FAILED CULM001_MRM_08: el docente no consulta los destinatarios de la solicitud (SEC_001).', 1;
    PRINT 'TEST_PASS:CULM001_MRM_08_DESTINATARIOS_SOLO_COORDINADOR';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg1 NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 59198, @msg1, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c2 UNIQUEIDENTIFIER = NEWID(), @s2 UNIQUEIDENTIFIER = NEWID(), @err2 NVARCHAR(4000) = NULL;
    DECLARE @uCX2 UNIQUEIDENTIFIER = NEWID(), @coordCX2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uCX2, @tipoCC, 1950000097, N'MRM', N'', N'CoordX2', N'', N'mrm.coordx2@fixture.invalid', 1, 1, N'FIXTURE_DISABLED_ACCOUNT');
    INSERT INTO dbo.Coordinador (id, usuario, estado, facultad) VALUES (@coordCX2, @uCX2, 1, @fac);
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@s2, N'MRM thr', 951, N'MRM951', 1, @grupoG, DATEADD(DAY, 3, SYSUTCDATETIME()), DATEADD(MINUTE, 3 * 1440 + 120, SYSUTCDATETIME()), N'UTC_V2');
    INSERT dbo.SesionSolicitud (sesion, idEstado, usuarioSolicitante, idCorrelacion) SELECT @s2, e.id, @uT, @c2 FROM dbo.EstadoSolicitudSesion e WHERE e.esFinal = 0;
    CREATE TABLE #mrm_d2 (tipoDestinatario NVARCHAR(20), idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(200),
        nombreAsignatura NVARCHAR(200), nombreGrupo NVARCHAR(300), nombreDocente NVARCHAR(400), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2);
    -- un coordinador fuera de ambito recibe SEC_002
    BEGIN TRY
        INSERT #mrm_d2 EXEC dbo.usp_consultar_destinatarios_solicitud_sesion @idSesion = @s2, @idCorrelacion = @c2, @idUsuarioEjecutor = @uCX2;
    END TRY
    BEGIN CATCH
        SET @err2 = ERROR_MESSAGE();
    END CATCH;
    IF @err2 IS NULL OR @err2 NOT LIKE N'%DBCODE=SEC[_]002|%' OR EXISTS (SELECT 1 FROM #mrm_d2)
        THROW 59121, 'TEST FAILED CULM001_MRM_08: un coordinador fuera de ambito no consulta los destinatarios (SEC_002).', 1;
    PRINT 'TEST_PASS:CULM001_MRM_08_DESTINATARIOS_AMBITO_SEC002';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg2 NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 59197, @msg2, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c3 UNIQUEIDENTIFIER = NEWID(), @err3 NVARCHAR(4000) = NULL;
    CREATE TABLE #mrm_s3 (idSesion UNIQUEIDENTIFIER, nombreSesion NVARCHAR(200), codigoSesion NVARCHAR(50), idGrupo UNIQUEIDENTIFIER, nombreGrupo NVARCHAR(200), nombreAsignatura NVARCHAR(200),
        idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(200), idDocente UNIQUEIDENTIFIER, nombreDocente NVARCHAR(400), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2,
        estadoSolicitud NVARCHAR(30), nombreEstadoSolicitud NVARCHAR(100), fechaSolicitudUtc DATETIME2, fechaResolucionUtc DATETIME2 NULL, observacion NVARCHAR(500) NULL,
        usuarioSolicitante UNIQUEIDENTIFIER, pendienteAprobacion BIT, estaCancelada BIT, totalRegistros INT);
    -- la consulta de solicitudes es solo del coordinador (SEC_001 para el docente)
    BEGIN TRY
        INSERT #mrm_s3 EXEC dbo.usp_consultar_solicitudes_sesion_coordinador_paginado @idUsuario = @uT, @idCorrelacion = @c3;
    END TRY
    BEGIN CATCH
        SET @err3 = ERROR_MESSAGE();
    END CATCH;
    IF @err3 IS NULL OR @err3 NOT LIKE N'%DBCODE=SEC[_]001|%' OR EXISTS (SELECT 1 FROM #mrm_s3)
        THROW 59122, 'TEST FAILED CULM001_MRM_07: la consulta de solicitudes es solo del coordinador (SEC_001).', 1;
    PRINT 'TEST_PASS:CULM001_MRM_07_SOLO_COORDINADOR';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg3 NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 59196, @msg3, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 59195, 'TEST FAILED CULM001_MRM: quedaron transacciones abiertas.', 1;
PRINT 'TEST_PASS:CULM001_MRM_TRANCOUNT_ZERO';
PRINT 'TEST END: test_mrm_solicitud_sesion';
GO
