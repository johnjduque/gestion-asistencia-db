USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- ============================================================================
-- DEC-081: receso academico del periodo (migracion 68). Un dia completo sin clase para toda la institucion del periodo.
--   REC_01  objetos, tipo RECESO, parametros, y mensajes sembrados
--   REC_02  el ADMINISTRADOR crea un dia: cancela las sesiones de ese dia en los grupos existentes (tipo RECESO, motivo, enlace) y la tupla
--           trae idReceso y conteos; DECANO, COORDINADOR y DOCENTE se rechazan (SEC_001); otra institucion => PER_001
--   REC_03  rechazos: fuera del periodo, hoy y pasado, festivo, repetido, periodo cerrado, motivo vacio o largo, fecha nula
--   REC_04  una sesion con asistencia no se toca y se informa en sesionesConAsistencia
--   REC_05  un grupo creado despues (precarga) y uno generado con usp_generar_sesiones_grupo_v2 nacen con la sesion del dia cancelada
--   REC_06  retirar: sin sesiones canceladas funciona (y el dia se puede volver a registrar); con sesiones se rechaza (REC_010); inexistente (REC_009)
--   REC_07  la previsualizacion cuenta las sesiones en receso (CANCELADA_POR_RECESO, sesionesEnReceso, minutosPerdidosReceso, fila RECESO)
--   REC_08  el cumplimiento y el denominador de asistencia no cuentan las sesiones canceladas por receso
--   REC_09  lectura por perfil (consultar recesos) y destinatarios (un estudiante y el docente por sesion cancelada)
--   REC_10  los festivos siguen funcionando con el tipo resuelto por codigo
--   REC_TRANCOUNT  @@TRANCOUNT = 0
-- Todo corre en UNA transaccion con ROLLBACK final. El resultset 2 de usp_crear_receso_academico no se captura aqui (INSERT ... EXEC no admite dos
-- resultsets distintos): las pruebas pasan @incluirDetalle = 0 y verifican las mismas filas en SesionCancelacion.
-- ============================================================================
PRINT 'TEST START: test_receso_academico (DEC-081)';
GO

IF OBJECT_ID('tempdb..#rec_expect') IS NOT NULL DROP PROCEDURE #rec_expect;
GO
CREATE PROCEDURE #rec_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: REC_', @label);
        THROW 59700, @mensaje, 1;
    END
END;
GO

-- REC_01: objetos y semillas
IF OBJECT_ID(N'dbo.PeriodoRecesoAcademico', N'U') IS NULL OR OBJECT_ID(N'dbo.uv_periodo_receso_academico', N'V') IS NULL
   OR OBJECT_ID(N'dbo.usp_crear_receso_academico', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_retirar_receso_academico', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_consultar_recesos_periodo', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_consultar_destinatarios_receso_academico', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_validar_receso_academico_interno', N'P') IS NULL OR OBJECT_ID(N'dbo.usp_cancelar_sesiones_receso_interno', N'P') IS NULL
   OR COL_LENGTH('dbo.SesionCancelacion', 'recesoAcademico') IS NULL
    THROW 59701, 'TEST FAILED REC_01: faltan objetos del receso academico (tabla, vista, columna o SP).', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.TipoCancelacionSesion WHERE id = '7C1E0B10-5E51-4C0A-9A01-000000000003' AND codigo = N'RECESO' AND esAutomatica = 1)
   OR EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_TipoCancelacionSesion_esAutomatica')
   OR dbo.ufn_obtener_parametro('RECESO', 'PREFIJO_MOTIVO_CANCELACION') <> N'Receso académico: '
   OR dbo.ufn_obtener_parametro('RECESO', 'CODIGO_TIPO_CANCELACION') <> N'RECESO'
   OR dbo.ufn_obtener_parametro('SESION', 'CODIGO_TIPO_CANCELACION_FESTIVO') <> N'FESTIVO'
   OR dbo.ufn_obtener_parametro_int(NULL, 'RECESO', 'MOTIVO_LONGITUD_MAXIMA') <> 200
    THROW 59702, 'TEST FAILED REC_01: tipo RECESO o parametros RECESO/* y SESION/CODIGO_TIPO_CANCELACION_FESTIVO no sembrados como en la migracion 68.', 1;
IF EXISTS (SELECT 1 FROM (VALUES ('REC_001'), ('REC_002'), ('REC_003'), ('REC_004'), ('REC_005'), ('REC_006'), ('REC_007'), ('REC_008'), ('REC_009'), ('REC_010'), ('REC_011')) c(codigo)
           WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario u WHERE u.codigo = c.codigo)
              OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = c.codigo))
    THROW 59703, 'TEST FAILED REC_01: mensajes REC_001..REC_011 ausentes.', 1;
PRINT 'TEST_PASS:REC_01_OBJETOS_Y_SEMILLAS';
GO

DECLARE @uAdmin UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER, @asignatura UNIQUEIDENTIFIER, @docente UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER;
SELECT TOP 1 @uCoord = c.usuario, @asignatura = g.idAsignatura, @docente = g.idDocente
FROM dbo.Coordinador c
INNER JOIN dbo.Programa p ON p.coordinador = c.id
INNER JOIN dbo.uv_asignatura_plan_estudio v ON v.idPrograma = p.id AND v.estaActivoVinculo = 1 AND v.estaActivoPlan = 1 AND v.estaActivaAsignatura = 1
INNER JOIN dbo.uv_grupo g ON g.idAsignatura = v.idAsignatura
WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v2
                  WHERE v2.idAsignatura = v.idAsignatura AND v2.estaActivoVinculo = 1 AND v2.estaActivoPlan = 1
                    AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(c.usuario) cp WHERE cp.idPrograma = v2.idPrograma))
ORDER BY c.id;
SELECT TOP 1 @uAdmin = a.usuario, @idInstitucion = a.institucion
FROM dbo.Administrador a
INNER JOIN dbo.uv_programa p ON p.idInstitucion = a.institucion
INNER JOIN dbo.Coordinador c ON c.usuario = @uCoord
WHERE p.idCoordinador = c.id
ORDER BY a.id;
DECLARE @uDocente UNIQUEIDENTIFIER = (SELECT usuario FROM dbo.Docente WHERE id = @docente);
DECLARE @uDecano UNIQUEIDENTIFIER = (SELECT TOP 1 d.usuario FROM dbo.Decano d INNER JOIN dbo.Facultad f ON f.decano = d.id WHERE f.institucion = @idInstitucion ORDER BY d.id);
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
IF @uAdmin IS NULL OR @uCoord IS NULL OR @asignatura IS NULL OR @docente IS NULL OR @uDocente IS NULL OR @uDecano IS NULL OR @tipoCC IS NULL OR @estadoA IS NULL
    THROW 59705, 'TEST FAILED: REC faltan fixtures del seed (administrador, coordinador, decano, asignatura, docente).', 1;

DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @ok BIT, @n INT, @msg NVARCHAR(4000), @esperado NVARCHAR(4000), @tecnico NVARCHAR(4000);
DECLARE @zona SYSNAME = dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER');
DECLARE @hoy DATE = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE);
DECLARE @prefijo NVARCHAR(200) = dbo.ufn_obtener_parametro('RECESO', 'PREFIJO_MOTIVO_CANCELACION');
-- Periodo futuro de 112 dias que empieza un miercoles; el lunes de la tercera semana es el dia de receso de las pruebas
DECLARE @inicio DATE = DATEADD(DAY, 60, @hoy);
WHILE DATEDIFF(DAY, '19000101', @inicio) % 7 <> 2 SET @inicio = DATEADD(DAY, 1, @inicio);
DECLARE @fin DATE = DATEADD(DAY, 111, @inicio);
DECLARE @lunes DATE = DATEADD(DAY, 12, @inicio);
DECLARE @miercoles DATE = DATEADD(DAY, 14, @inicio);
DECLARE @lunes2 DATE = DATEADD(DAY, 19, @inicio);
DECLARE @lunes3 DATE = DATEADD(DAY, 26, @inicio);
DECLARE @h2 NVARCHAR(MAX) = N'[{"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"},{"codigoDia":"MI","horaInicio":"08:00","horaFin":"10:00"}]';
DECLARE @per UNIQUEIDENTIFIER = NEWID(), @perHoy UNIQUEIDENTIFIER = NEWID(), @perCerrado UNIQUEIDENTIFIER = NEWID(), @perVacio UNIQUEIDENTIFIER = NEWID(), @perLimpio UNIQUEIDENTIFIER = NEWID();
DECLARE @g1 UNIQUEIDENTIFIER = NEWID(), @g2 UNIQUEIDENTIFIER = NEWID(), @g3 UNIQUEIDENTIFIER = NEWID();
DECLARE @idReceso UNIQUEIDENTIFIER = NEWID(), @idReceso2 UNIQUEIDENTIFIER = NEWID(), @idRecesoHoy UNIQUEIDENTIFIER = NEWID(), @idRecesoCerrado UNIQUEIDENTIFIER = NEWID();
DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
DECLARE @uEst UNIQUEIDENTIFIER = NEWID(), @est UNIQUEIDENTIFIER = NEWID(), @eg UNIQUEIDENTIFIER = NEWID();
DECLARE @uAdminOtro UNIQUEIDENTIFIER = NEWID(), @instOtra UNIQUEIDENTIFIER = NEWID(), @idAjeno UNIQUEIDENTIFIER = NEWID();

IF OBJECT_ID('tempdb..#rc') IS NOT NULL DROP TABLE #rc;
IF OBJECT_ID('tempdb..#r4') IS NOT NULL DROP TABLE #r4;
IF OBJECT_ID('tempdb..#rp') IS NOT NULL DROP TABLE #rp;
IF OBJECT_ID('tempdb..#pv') IS NOT NULL DROP TABLE #pv;
IF OBJECT_ID('tempdb..#lista') IS NOT NULL DROP TABLE #lista;
IF OBJECT_ID('tempdb..#dest') IS NOT NULL DROP TABLE #dest;
CREATE TABLE #rc (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
    idReceso UNIQUEIDENTIFIER NULL, sesionesCanceladas INT NULL, sesionesConAsistencia INT NULL);
CREATE TABLE #r4 (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
CREATE TABLE #rp (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT, idPeriodo UNIQUEIDENTIFIER NULL);
CREATE TABLE #pv (tipoFila VARCHAR(12), orden INT, id1 UNIQUEIDENTIFIER, id2 UNIQUEIDENTIFIER, id3 UNIQUEIDENTIFIER,
    texto1 NVARCHAR(200), texto2 NVARCHAR(200), texto3 NVARCHAR(4000), texto4 NVARCHAR(200), texto5 NVARCHAR(200),
    fecha1 DATE, fecha2 DATE, instante1 DATETIME2, instante2 DATETIME2,
    e1 INT, e2 INT, e3 INT, e4 INT, e5 INT, e6 INT, e7 INT, e8 INT, e9 INT, e10 INT, e11 INT, e12 INT, e13 INT, e14 INT, e15 INT, e16 INT, e17 INT, e18 INT,
    b1 BIT, b2 BIT, e19 INT, e20 INT);
CREATE TABLE #lista (id UNIQUEIDENTIFIER, idPeriodoAcademico UNIQUEIDENTIFIER, fecha DATE, motivo NVARCHAR(200), sesionesCanceladas INT, estaAplicado BIT,
    puedeRetirarse BIT, fechaCreacionUtc DATETIME2, totalRegistros INT);
CREATE TABLE #dest (rolDestinatario VARCHAR(12), idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(200), idSesion UNIQUEIDENTIFIER,
    idGrupo UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(200), nombreGrupo NVARCHAR(300), fecha DATE, fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2, motivoCancelacion NVARCHAR(500));
DECLARE @cre INT, @eli INT, @mu NVARCHAR(4000), @mt NVARCHAR(4000), @okPre BIT;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ---------------------------------------------------------------- Fixture: periodos, grupo con 2 franjas semanales y un estudiante
    UPDATE dbo.Asignatura SET horasSemanales = 4 WHERE id = @asignatura;
    INSERT #rp EXEC dbo.usp_crear_periodo_academico @idPeriodo = @per, @nombre = N'REC receso A', @fechaInicio = @inicio, @fechaFin = @fin,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rp WHERE estadoResultado = 1), 1, 0);
    EXEC #rec_expect 'FIXTURE_PERIODO', @ok;
    -- Periodo que contiene a hoy (para fechas pasadas y de hoy) y periodo cerrado (insercion directa)
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@perHoy, @idInstitucion, N'REC receso hoy', 3300000 + ABS(CHECKSUM(NEWID()) % 600000), DATEADD(DAY, -10, @hoy), DATEADD(DAY, 101, @hoy), YEAR(@hoy));
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@perVacio, @idInstitucion, N'REC receso sin grupos', 3300000 + ABS(CHECKSUM(NEWID()) % 600000), DATEADD(DAY, 200, @hoy), DATEADD(DAY, 311, @hoy), YEAR(DATEADD(DAY, 200, @hoy)));
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@perLimpio, @idInstitucion, N'REC receso limpio', 3300000 + ABS(CHECKSUM(NEWID()) % 600000), DATEADD(DAY, 400, @hoy), DATEADD(DAY, 511, @hoy), YEAR(DATEADD(DAY, 400, @hoy)));
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio, fechaCierreUtc)
    VALUES (@perCerrado, @idInstitucion, N'REC receso cerrado', 3300000 + ABS(CHECKSUM(NEWID()) % 600000), @inicio, @fin, YEAR(@inicio), SYSUTCDATETIME());

    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_crear_grupo @idGrupo = @g1, @idAsignatura = @asignatura, @idPeriodoAcademico = @per, @codigo = 981, @nombre = N'REC g1',
        @idDocente = @docente, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 1), 1, 0);
    EXEC #rec_expect 'FIXTURE_GRUPO', @ok;
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @g1, @horariosJSON = @h2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 1), 1, 0);
    EXEC #rec_expect 'FIXTURE_HORARIO', @ok;
    EXEC dbo.usp_precargar_sesiones_grupo_interno @idGrupo = @g1, @idCorrelacion = @corr, @sesionesCreadas = @cre OUTPUT, @sesionesEliminadas = @eli OUTPUT,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @okPre OUTPUT;
    SET @ok = IIF(@okPre = 1 AND @cre = 32 AND (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @g1) = 32, 1, 0);
    EXEC #rec_expect 'FIXTURE_SESIONES', @ok;

    INSERT dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado)
    VALUES (@uEst, @tipoCC, 986100000 + ABS(CHECKSUM(NEWID()) % 899999), N'Receso', N'Qa', N'Estela', N'Rec', CONCAT(N'rec.est.', @tag, N'@test.local'), 1, 1),
           (@uAdminOtro, @tipoCC, 987100000 + ABS(CHECKSUM(NEWID()) % 899999), N'Admin', N'Otra', N'Olga', N'Rec', CONCAT(N'rec.adm.', @tag, N'@test.local'), 1, 1);
    INSERT dbo.Estudiante (id, usuario) VALUES (@est, @uEst);
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@eg, @estadoA, @est, @g1);
    INSERT dbo.Institucion (id, nombre, estado) VALUES (@instOtra, CONCAT(N'REC Institucion ', @tag), 1);
    INSERT dbo.Administrador (id, usuario, institucion) VALUES (NEWID(), @uAdminOtro, @instOtra);

    DECLARE @cumplAntes INT = (SELECT COUNT(*) FROM dbo.uv_cumplimiento_sesion_grupo WHERE idGrupo = @g1);
    DECLARE @sesionesPeriodoAntes INT = (SELECT sesionesPeriodo FROM dbo.uv_resumen_asistencia_estudiante_grupo WHERE idEstudianteGrupo = @eg);
    DECLARE @sesionLunes UNIQUEIDENTIFIER = (SELECT id FROM dbo.Sesion WHERE grupo = @g1 AND CAST((fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE) = @lunes);
    DECLARE @sesionLunes2 UNIQUEIDENTIFIER = (SELECT id FROM dbo.Sesion WHERE grupo = @g1 AND CAST((fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE) = @lunes2);
    SET @ok = IIF(@sesionLunes IS NOT NULL AND @sesionLunes2 IS NOT NULL, 1, 0);
    EXEC #rec_expect 'FIXTURE_SESION_LUNES', @ok;

    -- ---------------------------------------------------------------- REC_02 creacion por el administrador
    -- La sesion del segundo lunes ya tiene asistencia: debe quedar sin tocar (REC_04)
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (NEWID(), @eg, @sesionLunes2);

    INSERT #rc EXEC dbo.usp_crear_receso_academico @idPeriodo = @per, @fecha = @lunes, @motivo = N'  Jornada institucional  ', @idCorrelacion = @corr,
        @idUsuarioEjecutor = @uAdmin, @idReceso = @idReceso, @incluirDetalle = 0;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'REC_001', @p_param1 = N'', @p_param2 = N'1',
        @mensajeUsuarioResultado = @msg OUTPUT, @mensajeTecnicoResultado = @tecnico OUTPUT;
    SET @esperado = CONCAT(N'Se registró el receso académico del ', CONVERT(NVARCHAR(10), @lunes, 103), N'; se cancelaron 1 clases.');
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rc WHERE estadoResultado = 1 AND idReceso = @idReceso AND sesionesCanceladas = 1
                                                AND sesionesConAsistencia = 0 AND idCorrelacion = @corr AND mensajeUsuarioResultado = @esperado
                                                AND mensajeTecnicoResultado LIKE N'DBCODE=REC[_]001|%'), 1, 0);
    EXEC #rec_expect 'REC_02_CREA', @ok;
    SET @ok = IIF(EXISTS (SELECT 1 FROM dbo.PeriodoRecesoAcademico WHERE id = @idReceso AND periodoAcademico = @per AND fecha = @lunes
                                                AND motivo = N'Jornada institucional' AND estaActivo = 1 AND usuarioCreador = @uAdmin AND idCorrelacion = @corr), 1, 0);
    EXEC #rec_expect 'REC_02_FILA', @ok;
    SET @ok = IIF(EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.TipoCancelacionSesion t ON t.id = sc.tipoCancelacion
                                                WHERE sc.sesion = @sesionLunes AND t.codigo = N'RECESO' AND t.esAutomatica = 1 AND sc.recesoAcademico = @idReceso
                                                AND sc.diaFestivo IS NULL AND sc.usuarioEjecutor = @uAdmin AND sc.idCorrelacion = @corr
                                                AND sc.motivo = CONCAT(@prefijo, N'Jornada institucional')) AND (SELECT COUNT(*) FROM dbo.SesionCancelacion WHERE recesoAcademico = @idReceso) = 1, 1, 0);
    EXEC #rec_expect 'REC_02_CANCELACION', @ok;
    SET @ok = IIF(EXISTS (SELECT 1 FROM dbo.uv_sesion_estado WHERE idSesion = @sesionLunes AND estaCancelada = 1
                                                AND codigoTipoCancelacion = N'RECESO' AND esCancelacionAutomatica = 1 AND motivoCancelacion = CONCAT(@prefijo, N'Jornada institucional'))
                                              AND EXISTS (SELECT 1 FROM dbo.uv_periodo_receso_academico WHERE id = @idReceso AND sesionesCanceladas = 1 AND estaAplicado = 1
                                                AND idInstitucion = @idInstitucion), 1, 0);
    EXEC #rec_expect 'REC_02_VISTA', @ok;
    SET @ok = IIF((SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @g1) = 1, 1, 0);
    EXEC #rec_expect 'REC_02_OTRAS_NO_TOCADAS', @ok;
    PRINT 'TEST_PASS:REC_02_ADMIN_CREA_Y_CANCELA';

    -- Rechazo por perfil: decano, coordinador y docente (SEC_001); administrador de otra institucion (PER_001)
    DECLARE @quien TABLE (rol VARCHAR(20), usuario UNIQUEIDENTIFIER, codigo VARCHAR(10));
    INSERT @quien VALUES ('DECANO', @uDecano, 'SEC_001'), ('COORDINADOR', @uCoord, 'SEC_001'), ('DOCENTE', @uDocente, 'SEC_001'), ('OTRA_INSTITUCION', @uAdminOtro, 'PER_001');
    DECLARE @rol VARCHAR(20), @usr UNIQUEIDENTIFIER, @cod VARCHAR(10);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT rol, usuario, codigo FROM @quien;
    OPEN c; FETCH NEXT FROM c INTO @rol, @usr, @cod;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE #rc;
        INSERT #rc EXEC dbo.usp_crear_receso_academico @idPeriodo = @per, @fecha = @lunes3, @motivo = N'No debe crearse', @idCorrelacion = @corr, @idUsuarioEjecutor = @usr, @incluirDetalle = 0;
        SET @ok = IIF(EXISTS (SELECT 1 FROM #rc WHERE estadoResultado = 0 AND idReceso IS NULL AND sesionesCanceladas IS NULL AND mensajeTecnicoResultado LIKE CONCAT(N'DBCODE=', @cod, N'|%'))
                      AND NOT EXISTS (SELECT 1 FROM dbo.PeriodoRecesoAcademico WHERE periodoAcademico = @per AND fecha = @lunes3), 1, 0);
        IF @ok <> 1 BEGIN SET @msg = CONCAT(N'TEST FAILED: REC_02_RECHAZO_', @rol); THROW 59710, @msg, 1; END
        FETCH NEXT FROM c INTO @rol, @usr, @cod;
    END
    CLOSE c; DEALLOCATE c;
    -- Sin ejecutor
    DELETE #rc;
    INSERT #rc EXEC dbo.usp_crear_receso_academico @idPeriodo = @per, @fecha = @lunes3, @motivo = N'x', @idCorrelacion = @corr, @idUsuarioEjecutor = NULL, @incluirDetalle = 0;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rc WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN[_]002|%'), 1, 0);
    EXEC #rec_expect 'REC_02_SIN_EJECUTOR', @ok;
    PRINT 'TEST_PASS:REC_02_RECHAZO_POR_PERFIL';

    -- ---------------------------------------------------------------- REC_03 rechazos de validacion
    DECLARE @val TABLE (etiqueta VARCHAR(30), idPer UNIQUEIDENTIFIER, fecha DATE, motivo NVARCHAR(4000), codigo VARCHAR(10));
    INSERT @val VALUES
        ('FUERA_ANTES',   @per,       DATEADD(DAY, -1, @inicio), N'm', 'REC_003'),
        ('FUERA_DESPUES', @per,       DATEADD(DAY, 1, @fin),     N'm', 'REC_003'),
        ('HOY',           @perHoy,    @hoy,                      N'm', 'REC_004'),
        ('PASADO',        @perHoy,    DATEADD(DAY, -1, @hoy),    N'm', 'REC_004'),
        ('REPETIDO',      @per,       @lunes,                    N'otro motivo', 'REC_006'),
        ('CERRADO',       @perCerrado, @lunes,                   N'm', 'REC_007'),
        ('MOTIVO_VACIO',  @per,       @lunes3,                   N'   ', 'REC_008'),
        ('MOTIVO_NULO',   @per,       @lunes3,                   NULL, 'REC_008'),
        ('MOTIVO_LARGO',  @per,       @lunes3,                   REPLICATE(N'x', 201), 'REC_008'),
        ('FECHA_NULA',    @per,       NULL,                      N'm', 'GEN_002'),
        ('PERIODO_INEXISTENTE', NEWID(), @lunes3,                N'm', 'PER_001');
    DECLARE @et VARCHAR(30), @vp UNIQUEIDENTIFIER, @vf DATE, @vm NVARCHAR(4000), @vc VARCHAR(10);
    DECLARE c2 CURSOR LOCAL FAST_FORWARD FOR SELECT etiqueta, idPer, fecha, motivo, codigo FROM @val;
    OPEN c2; FETCH NEXT FROM c2 INTO @et, @vp, @vf, @vm, @vc;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE #rc;
        INSERT #rc EXEC dbo.usp_crear_receso_academico @idPeriodo = @vp, @fecha = @vf, @motivo = @vm, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin, @incluirDetalle = 0;
        SET @ok = IIF(EXISTS (SELECT 1 FROM #rc WHERE estadoResultado = 0 AND idReceso IS NULL AND mensajeTecnicoResultado LIKE CONCAT(N'DBCODE=', @vc, N'|%')
                              AND LEN(mensajeUsuarioResultado) > 0), 1, 0);
        IF @ok <> 1 BEGIN SET @msg = CONCAT(N'TEST FAILED: REC_03_RECHAZO_', @et); THROW 59711, @msg, 1; END
        FETCH NEXT FROM c2 INTO @et, @vp, @vf, @vm, @vc;
    END
    CLOSE c2; DEALLOCATE c2;
    -- Festivo: el responsable pide que no se pueda registrar un receso en un festivo
    IF EXISTS (SELECT 1 FROM dbo.DiaFestivo WHERE fecha = @lunes3)
        DELETE sc FROM dbo.SesionCancelacion sc JOIN dbo.DiaFestivo df ON df.id = sc.diaFestivo WHERE df.fecha = @lunes3;
    DELETE FROM dbo.DiaFestivo WHERE fecha = @lunes3;
    INSERT dbo.DiaFestivo (id, fecha, nombre, fuente, estaActivo, fechaCargaUtc, idCorrelacionCarga)
    VALUES (NEWID(), @lunes3, N'Festivo QA receso', N'CALCULO_LOCAL', 1, SYSUTCDATETIME(), @corr);
    DELETE #rc;
    INSERT #rc EXEC dbo.usp_crear_receso_academico @idPeriodo = @per, @fecha = @lunes3, @motivo = N'En festivo', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin, @incluirDetalle = 0;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rc WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=REC[_]005|%'
                                                         AND mensajeUsuarioResultado LIKE N'%Festivo QA receso%'), 1, 0);
    EXEC #rec_expect 'REC_03_FESTIVO', @ok;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM dbo.PeriodoRecesoAcademico WHERE periodoAcademico IN (@per, @perHoy, @perCerrado) AND id <> @idReceso)
                                                      AND (SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @g1) = 1, 1, 0);
    EXEC #rec_expect 'REC_03_NADA_ESCRITO', @ok;
    PRINT 'TEST_PASS:REC_03_RECHAZOS_DE_VALIDACION';

    -- ---------------------------------------------------------------- REC_04 una sesion con asistencia no se toca
    DELETE #rc;
    INSERT #rc EXEC dbo.usp_crear_receso_academico @idPeriodo = @per, @fecha = @lunes2, @motivo = N'Dia con asistencia', @idCorrelacion = @corr,
        @idUsuarioEjecutor = @uAdmin, @idReceso = @idReceso2, @incluirDetalle = 0;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rc WHERE estadoResultado = 1 AND idReceso = @idReceso2 AND sesionesCanceladas = 0 AND sesionesConAsistencia = 1), 1, 0);
    EXEC #rec_expect 'REC_04_CONTEO', @ok;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sesionLunes2)
                                                   AND EXISTS (SELECT 1 FROM dbo.uv_periodo_receso_academico WHERE id = @idReceso2 AND sesionesCanceladas = 0 AND estaAplicado = 0), 1, 0);
    EXEC #rec_expect 'REC_04_SIN_TOCAR', @ok;
    PRINT 'TEST_PASS:REC_04_SESION_CON_ASISTENCIA_NO_SE_TOCA';

    -- ---------------------------------------------------------------- REC_05 grupos nuevos: precarga y generacion v2
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_crear_grupo @idGrupo = @g2, @idAsignatura = @asignatura, @idPeriodoAcademico = @per, @codigo = 982, @nombre = N'REC g2',
        @idDocente = @docente, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_guardar_horarios_grupo @idGrupo = @g2, @horariosJSON = N'[{"codigoDia":"LU","horaInicio":"14:00","horaFin":"16:00"},{"codigoDia":"MI","horaInicio":"14:00","horaFin":"16:00"}]',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    EXEC dbo.usp_precargar_sesiones_grupo_interno @idGrupo = @g2, @idCorrelacion = @corr, @sesionesCreadas = @cre OUTPUT, @sesionesEliminadas = @eli OUTPUT,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @okPre OUTPUT;
    SET @ok = IIF(@okPre = 1 AND @cre = 32, 1, 0);
    EXEC #rec_expect 'REC_05_PRECARGA_OK', @ok;
    -- Nacen canceladas las dos sesiones de los lunes con receso (@lunes y @lunes2), ambas con usuarioEjecutor NULL
    SET @ok = IIF((SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion
                                                              WHERE s.grupo = @g2 AND sc.recesoAcademico IN (@idReceso, @idReceso2) AND sc.usuarioEjecutor IS NULL
                                                                AND sc.tipoCancelacion = (SELECT id FROM dbo.TipoCancelacionSesion WHERE codigo = N'RECESO')
                                                                AND sc.motivo IN (CONCAT(@prefijo, N'Jornada institucional'), CONCAT(@prefijo, N'Dia con asistencia'))) = 2
                                                            AND (SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @g2 AND sc.recesoAcademico IS NOT NULL) = 2, 1, 0);
    EXEC #rec_expect 'REC_05_PRECARGA_CANCELADAS', @ok;
    -- Generacion v2: el generador congelado exige que el grupo este habilitado (periodo vigente), asi que se usa el periodo que contiene a hoy
    DECLARE @diaV2 DATE = DATEADD(DAY, 2, @hoy), @idRecesoV2 UNIQUEIDENTIFIER = NEWID();
    DELETE #rc;
    INSERT #rc EXEC dbo.usp_crear_receso_academico @idPeriodo = @perHoy, @fecha = @diaV2, @motivo = N'Receso v2', @idCorrelacion = @corr,
        @idUsuarioEjecutor = @uAdmin, @idReceso = @idRecesoV2, @incluirDetalle = 0;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rc WHERE estadoResultado = 1 AND sesionesCanceladas = 0), 1, 0);
    EXEC #rec_expect 'REC_05_V2_RECESO_SIN_GRUPOS', @ok;
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_crear_grupo @idGrupo = @g3, @idAsignatura = @asignatura, @idPeriodoAcademico = @perHoy, @codigo = 983, @nombre = N'REC g3',
        @idDocente = @docente, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 1), 1, 0);
    EXEC #rec_expect 'REC_05_V2_GRUPO', @ok;
    INSERT dbo.Horario (id, grupo, dia, horaInicio, horaFin) SELECT NEWID(), @g3, id, '18:00', '19:00' FROM dbo.uv_dia;
    EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = @g3, @idCorrelacion = @corr, @idUsuarioEjecutor = @uDocente;
    SET @ok = IIF(@@TRANCOUNT = 1 AND EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @g3)
        AND (SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @g3 AND sc.recesoAcademico = @idRecesoV2
             AND sc.usuarioEjecutor IS NULL AND sc.motivo = CONCAT(@prefijo, N'Receso v2')
             AND CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE) = @diaV2) = 1
        AND (SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @g3 AND sc.recesoAcademico IS NOT NULL) = 1, 1, 0);
    EXEC #rec_expect 'REC_05_V2_CANCELADAS', @ok;
    -- Idempotencia: repetir la generacion no cancela nada nuevo ni duplica
    EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = @g3, @idCorrelacion = @corr, @idUsuarioEjecutor = @uDocente;
    SET @ok = IIF((SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion WHERE s.grupo = @g3 AND sc.recesoAcademico IS NOT NULL) = 1, 1, 0);
    EXEC #rec_expect 'REC_05_V2_IDEMPOTENTE', @ok;
    -- Los recesos de otro periodo no aplican: toda cancelacion por receso corresponde al periodo del grupo
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion JOIN dbo.Grupo g ON g.id = s.grupo
                              JOIN dbo.PeriodoRecesoAcademico r ON r.id = sc.recesoAcademico WHERE r.periodoAcademico <> g.periodoAcademico), 1, 0);
    EXEC #rec_expect 'REC_05_SOLO_SU_PERIODO', @ok;
PRINT 'TEST_PASS:REC_05_GRUPOS_NUEVOS_NACEN_CANCELADOS';

    -- ---------------------------------------------------------------- REC_06 retirar
    -- Con sesiones canceladas: REC_010 y el dia sigue activo
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_retirar_receso_academico @idReceso = @idReceso, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=REC[_]010|%'
                                                                     AND mensajeUsuarioResultado LIKE N'%ya canceló 2 clases%')
                                                              AND EXISTS (SELECT 1 FROM dbo.PeriodoRecesoAcademico WHERE id = @idReceso AND estaActivo = 1), 1, 0);
    EXEC #rec_expect 'REC_06_APLICADO_NO_SE_RETIRA', @ok;
    -- Sin sesiones canceladas (el dia con asistencia aun no cancelo nada en g1 pero si en g2/g3 al nacer): se crea uno en un periodo sin grupos (@perVacio)
    DECLARE @manana DATE = DATEADD(DAY, 205, @hoy);
    DELETE #rc;
    INSERT #rc EXEC dbo.usp_crear_receso_academico @idPeriodo = @perVacio, @fecha = @manana, @motivo = N'Receso sin grupos', @idCorrelacion = @corr,
        @idUsuarioEjecutor = @uAdmin, @idReceso = @idRecesoHoy, @incluirDetalle = 0;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rc WHERE estadoResultado = 1 AND idReceso = @idRecesoHoy AND sesionesCanceladas = 0 AND sesionesConAsistencia = 0) AND EXISTS (SELECT 1 FROM dbo.uv_periodo_receso_academico WHERE id = @idRecesoHoy AND estaAplicado = 0), 1, 0);
    EXEC #rec_expect 'REC_06_CREA_SIN_GRUPOS', @ok;
    -- Otra institucion y no administrador no pueden retirarlo
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_retirar_receso_academico @idReceso = @idRecesoHoy, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdminOtro;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=REC[_]009|%'), 1, 0);
    EXEC #rec_expect 'REC_06_OTRA_INSTITUCION', @ok;
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_retirar_receso_academico @idReceso = @idRecesoHoy, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%') AND EXISTS (SELECT 1 FROM dbo.PeriodoRecesoAcademico WHERE id = @idRecesoHoy AND estaActivo = 1), 1, 0);
    EXEC #rec_expect 'REC_06_NO_ADMIN', @ok;
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_retirar_receso_academico @idReceso = @idRecesoHoy, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=REC[_]002|%')
                                                AND EXISTS (SELECT 1 FROM dbo.PeriodoRecesoAcademico WHERE id = @idRecesoHoy AND estaActivo = 0)
                                                AND NOT EXISTS (SELECT 1 FROM dbo.uv_periodo_receso_academico WHERE id = @idRecesoHoy), 1, 0);
    EXEC #rec_expect 'REC_06_RETIRA', @ok;
    -- Ya retirado: inexistente (REC_009); y la fecha puede registrarse otra vez
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_retirar_receso_academico @idReceso = @idRecesoHoy, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=REC[_]009|%'), 1, 0);
    EXEC #rec_expect 'REC_06_YA_RETIRADO', @ok;
    DELETE #rc;
    INSERT #rc EXEC dbo.usp_crear_receso_academico @idPeriodo = @perVacio, @fecha = @manana, @motivo = N'Receso corregido', @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin, @incluirDetalle = 0;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rc WHERE estadoResultado = 1)
                                                            AND (SELECT COUNT(*) FROM dbo.PeriodoRecesoAcademico WHERE periodoAcademico = @perVacio AND fecha = @manana) = 2
                                                            AND (SELECT COUNT(*) FROM dbo.PeriodoRecesoAcademico WHERE periodoAcademico = @perVacio AND fecha = @manana AND estaActivo = 1) = 1, 1, 0);
    EXEC #rec_expect 'REC_06_VUELVE_A_REGISTRAR', @ok;
    -- Inexistente
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_retirar_receso_academico @idReceso = @idAjeno, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=REC[_]009|%'), 1, 0);
    EXEC #rec_expect 'REC_06_INEXISTENTE', @ok;
    -- Periodo cerrado: el dia (insertado directo) no se retira (REC_007)
    INSERT dbo.PeriodoRecesoAcademico (id, periodoAcademico, fecha, motivo, estaActivo, usuarioCreador, idCorrelacion)
    VALUES (@idRecesoCerrado, @perCerrado, @lunes3, N'Receso de periodo cerrado', 1, @uAdmin, @corr);
    DELETE #r4;
    INSERT #r4 EXEC dbo.usp_retirar_receso_academico @idReceso = @idRecesoCerrado, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r4 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=REC[_]007|%')
                                                         AND EXISTS (SELECT 1 FROM dbo.PeriodoRecesoAcademico WHERE id = @idRecesoCerrado AND estaActivo = 1), 1, 0);
    EXEC #rec_expect 'REC_06_PERIODO_CERRADO', @ok;
    PRINT 'TEST_PASS:REC_06_RETIRAR';

    -- ---------------------------------------------------------------- REC_07 previsualizacion
    -- Grupo nuevo en el periodo (franjas LU y MI 08:00-10:00): los 3 recesos activos de @per... solo @lunes y @lunes2 caen en lunes
    INSERT #pv EXEC dbo.usp_previsualizar_horario_grupo @idGrupo = NULL, @idAsignatura = @asignatura, @idPeriodoAcademico = @per, @idDocente = @docente,
        @horariosJSON = @h2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #pv WHERE tipoFila = 'RESUMEN' AND e7 = 1 AND e19 = 2 AND e20 = 240 AND e5 = 32 AND e6 = 29)
                                                 AND (SELECT COUNT(*) FROM #pv) > 0, 1, 0);
    EXEC #rec_expect 'REC_07_RESUMEN', @ok;
    SET @ok = IIF((SELECT COUNT(*) FROM #pv WHERE tipoFila = 'SESION' AND texto1 = 'CANCELADA_POR_RECESO') = 2
                                                  AND EXISTS (SELECT 1 FROM #pv WHERE tipoFila = 'SESION' AND texto1 = 'CANCELADA_POR_RECESO' AND fecha1 = @lunes
                                                              AND texto2 = CONCAT(@prefijo, N'Jornada institucional'))
                                                  AND (SELECT COUNT(*) FROM #pv WHERE tipoFila = 'SESION' AND texto1 = 'PROGRAMADA') = 29, 1, 0);
    EXEC #rec_expect 'REC_07_SESIONES', @ok;
    SET @ok = IIF((SELECT COUNT(*) FROM #pv WHERE tipoFila = 'RECESO') = 2
                                                                 AND EXISTS (SELECT 1 FROM #pv WHERE tipoFila = 'RECESO' AND fecha1 = @lunes AND e1 = 1)
                                                                 AND EXISTS (SELECT 1 FROM #pv WHERE tipoFila = 'CONFLICTO' AND texto1 = 'REC_011' AND texto2 = 'INFORMATIVO' AND LEN(texto3) > 0), 1, 0);
    EXEC #rec_expect 'REC_07_FILA_RECESO_Y_CONFLICTO', @ok;
    -- Un periodo sin recesos no los cuenta
    DELETE #pv;
    INSERT #pv EXEC dbo.usp_previsualizar_horario_grupo @idGrupo = NULL, @idAsignatura = @asignatura, @idPeriodoAcademico = @perLimpio, @idDocente = @docente,
        @horariosJSON = @h2, @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #pv WHERE tipoFila = 'RESUMEN' AND e19 = 0 AND e20 = 0)
                                                     AND NOT EXISTS (SELECT 1 FROM #pv WHERE tipoFila IN ('RECESO') OR texto1 = 'REC_011'), 1, 0);
    EXEC #rec_expect 'REC_07_SIN_RECESOS', @ok;
    PRINT 'TEST_PASS:REC_07_PREVISUALIZACION';

    -- ---------------------------------------------------------------- REC_08 asistencia: las canceladas por receso salen del cumplimiento y del denominador
    SET @ok = IIF((SELECT COUNT(*) FROM dbo.uv_cumplimiento_sesion_grupo WHERE idGrupo = @g1) = @cumplAntes - 1
                                                      AND NOT EXISTS (SELECT 1 FROM dbo.uv_cumplimiento_sesion_grupo WHERE idSesion = @sesionLunes), 1, 0);
    EXEC #rec_expect 'REC_08_CUMPLIMIENTO', @ok;
    SET @ok = IIF((SELECT sesionesPeriodo FROM dbo.uv_resumen_asistencia_estudiante_grupo WHERE idEstudianteGrupo = @eg) = @sesionesPeriodoAntes - 1, 1, 0);
    EXEC #rec_expect 'REC_08_DENOMINADOR', @ok;
    PRINT 'TEST_PASS:REC_08_NO_CUENTA_EN_ASISTENCIA';

    -- ---------------------------------------------------------------- REC_09 lectura por perfil y destinatarios
    SET @n = 0;
    DECLARE @lectores TABLE (rol VARCHAR(20), usuario UNIQUEIDENTIFIER, esperaFilas BIT);
    INSERT @lectores VALUES ('ADMINISTRADOR', @uAdmin, 1), ('COORDINADOR', @uCoord, 1), ('DECANO', @uDecano, 1), ('DOCENTE', @uDocente, 1);
    DECLARE c3 CURSOR LOCAL FAST_FORWARD FOR SELECT rol, usuario FROM @lectores;
    OPEN c3; FETCH NEXT FROM c3 INTO @rol, @usr;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE #lista;
        BEGIN TRY
            INSERT #lista EXEC dbo.usp_consultar_recesos_periodo @idPeriodo = @per, @idCorrelacion = @corr, @idUsuarioEjecutor = @usr;
        END TRY
        BEGIN CATCH
            -- Un decano de otra facultad de la misma institucion tambien pertenece a la institucion; solo se rechaza fuera de ella
            SET @msg = CONCAT(N'TEST FAILED: REC_09_LECTURA_', @rol, N' ', ERROR_MESSAGE()); THROW 59712, @msg, 1;
        END CATCH
        IF (SELECT COUNT(*) FROM #lista) <> 2 OR NOT EXISTS (SELECT 1 FROM #lista WHERE id = @idReceso AND fecha = @lunes AND motivo = N'Jornada institucional'
                AND sesionesCanceladas = 2 AND estaAplicado = 1 AND puedeRetirarse = 0 AND totalRegistros = 2)
           OR NOT EXISTS (SELECT 1 FROM #lista WHERE id = @idReceso2 AND estaAplicado = 1)
        BEGIN SET @msg = CONCAT(N'TEST FAILED: REC_09_LECTURA_DATOS_', @rol); THROW 59713, @msg, 1; END
        FETCH NEXT FROM c3 INTO @rol, @usr;
    END
    CLOSE c3; DEALLOCATE c3;
    -- Fuera del ambito (administrador de otra institucion) y estudiante (sin perfil de lectura): THROW
    DECLARE @fallo INT = 0;
    BEGIN TRY INSERT #lista EXEC dbo.usp_consultar_recesos_periodo @idPeriodo = @per, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdminOtro; END TRY
    BEGIN CATCH IF ERROR_MESSAGE() LIKE N'DBCODE=PER[_]001|%' SET @fallo += 1; END CATCH
    BEGIN TRY INSERT #lista EXEC dbo.usp_consultar_recesos_periodo @idPeriodo = @per, @idCorrelacion = @corr, @idUsuarioEjecutor = @uEst; END TRY
    BEGIN CATCH IF ERROR_MESSAGE() LIKE N'DBCODE=SEC[_]001|%' SET @fallo += 1; END CATCH
    BEGIN TRY INSERT #lista EXEC dbo.usp_consultar_recesos_periodo @idPeriodo = @idAjeno, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin; END TRY
    BEGIN CATCH IF ERROR_MESSAGE() LIKE N'DBCODE=PER[_]001|%' SET @fallo += 1; END CATCH
    SET @ok = IIF(@fallo = 3, 1, 0);
    EXEC #rec_expect 'REC_09_LECTURA_RECHAZOS', @ok;

    -- Destinatarios: el estudiante y el docente de g1 (una sesion cancelada del @lunes) y el del docente en g2 (sin matriculas)
    INSERT #dest EXEC dbo.usp_consultar_destinatarios_receso_academico @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr, @idReceso = @idReceso;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #dest WHERE rolDestinatario = 'ESTUDIANTE' AND idUsuario = @uEst AND idGrupo = @g1 AND idSesion = @sesionLunes
                                                                AND correo = CONCAT(N'rec.est.', @tag, N'@test.local') AND fecha = @lunes
                                                                AND motivoCancelacion = CONCAT(@prefijo, N'Jornada institucional') AND nombreGrupo LIKE N'G%de %')
                                                      AND (SELECT COUNT(*) FROM #dest WHERE rolDestinatario = 'ESTUDIANTE') = 1
                                                      AND (SELECT COUNT(*) FROM #dest WHERE rolDestinatario = 'DOCENTE' AND idUsuario = @uDocente) = 2
                                                      AND (SELECT COUNT(DISTINCT idSesion) FROM #dest) = 2, 1, 0);
    EXEC #rec_expect 'REC_09_DESTINATARIOS', @ok;
    DELETE #dest;
    SET @fallo = 0;
    BEGIN TRY INSERT #dest EXEC dbo.usp_consultar_destinatarios_receso_academico @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr, @idReceso = @idReceso; END TRY
    BEGIN CATCH IF ERROR_MESSAGE() LIKE N'DBCODE=SEC[_]001|%' SET @fallo += 1; END CATCH
    BEGIN TRY INSERT #dest EXEC dbo.usp_consultar_destinatarios_receso_academico @idUsuarioEjecutor = @uAdminOtro, @idCorrelacion = @corr, @idReceso = @idReceso; END TRY
    BEGIN CATCH IF ERROR_MESSAGE() LIKE N'DBCODE=REC[_]009|%' SET @fallo += 1; END CATCH
    SET @ok = IIF(@fallo = 2 AND NOT EXISTS (SELECT 1 FROM #dest), 1, 0);
    EXEC #rec_expect 'REC_09_DESTINATARIOS_AMBITO', @ok;
    PRINT 'TEST_PASS:REC_09_LECTURA_Y_DESTINATARIOS';

    -- ---------------------------------------------------------------- REC_10 festivos con el tipo por codigo
    -- Un festivo en el miercoles del segundo bloque: usp_aplicar_festivos_grupo cancela con el tipo FESTIVO y no toca los de receso
    DELETE FROM dbo.DiaFestivo WHERE fecha = @miercoles;
    INSERT dbo.DiaFestivo (id, fecha, nombre, fuente, estaActivo, fechaCargaUtc, idCorrelacionCarga)
    VALUES (NEWID(), @miercoles, N'Festivo QA miercoles', N'CALCULO_LOCAL', 1, SYSUTCDATETIME(), @corr);
    DELETE #r4;
    DECLARE @tAplG TABLE (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
        sesionesCanceladas INT, sesionesConAsistencia INT);
    INSERT @tAplG EXEC dbo.usp_aplicar_festivos_grupo @idGrupo = @g1, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM @tAplG WHERE estadoResultado = 1 AND sesionesCanceladas = 2)
        AND EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc JOIN dbo.Sesion s ON s.id = sc.sesion JOIN dbo.TipoCancelacionSesion t ON t.id = sc.tipoCancelacion
                    JOIN dbo.DiaFestivo df ON df.id = sc.diaFestivo
                    WHERE s.grupo = @g1 AND df.fecha = @miercoles AND t.codigo = N'FESTIVO' AND sc.recesoAcademico IS NULL
                      AND sc.motivo = CONCAT(dbo.ufn_obtener_parametro('FESTIVOS', 'PREFIJO_MOTIVO_CANCELACION'), N'Festivo QA miercoles')), 1, 0);
    EXEC #rec_expect 'REC_10_FESTIVO_POR_CODIGO', @ok;
    -- El receso de un dia que despues se declara festivo no se pisa: la sesion conserva su cancelacion por receso
    SET @ok = IIF(EXISTS (SELECT 1 FROM dbo.SesionCancelacion WHERE sesion = @sesionLunes AND recesoAcademico = @idReceso), 1, 0);
    EXEC #rec_expect 'REC_10_RECESO_INTACTO', @ok;
    PRINT 'TEST_PASS:REC_10_FESTIVOS_POR_CODIGO';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @errTexto NVARCHAR(4000) = CONCAT(ERROR_MESSAGE(), N' (linea ', ERROR_LINE(), N')');
    THROW 59799, @errTexto, 1;
END CATCH
GO

IF @@TRANCOUNT <> 0
    THROW 59798, 'TEST FAILED REC_TRANCOUNT: transaccion abierta.', 1;
PRINT 'TEST_PASS:REC_TRANCOUNT_ZERO';
IF OBJECT_ID('tempdb..#rc') IS NOT NULL DROP TABLE #rc;
IF OBJECT_ID('tempdb..#r4') IS NOT NULL DROP TABLE #r4;
IF OBJECT_ID('tempdb..#rp') IS NOT NULL DROP TABLE #rp;
IF OBJECT_ID('tempdb..#pv') IS NOT NULL DROP TABLE #pv;
IF OBJECT_ID('tempdb..#lista') IS NOT NULL DROP TABLE #lista;
IF OBJECT_ID('tempdb..#dest') IS NOT NULL DROP TABLE #dest;
GO
