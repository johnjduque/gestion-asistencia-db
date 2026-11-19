USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- ATA D6 y D7 (migracion 52): solicitudes de sesion del docente y calendario de sesiones con fechas.
--   ATA_P2_00 objetos, mensaje CAL_001 y permisos del rol runtime
--   ATA_P2_01 solicitudes del docente: sus solicitudes pendientes (una fila por sesion en grupo mixto), orden y totalRegistros
--   ATA_P2_02 soloPendientes = 0 incluye aprobadas y rechazadas; @idGrupo; paginacion
--   ATA_P2_03 aislamiento (otro docente, grupo ajeno) y RBAC (SEC_001 coordinador/estudiante, PAG_001)
--   ATA_P2_04 calendario del docente: rango local, orden, cancelada (festivo y manual), extraordinaria aprobada; sin pendientes ni rechazadas
--   ATA_P2_05 calendario del estudiante: solo grupos con matricula inscrita; borde de fecha local (23:30 local es del mismo dia local)
--   ATA_P2_06 rango invalido: CAL_001 (hasta < desde, mas de 31 dias, nulos) y el maximo de 31 dias es valido; RBAC del calendario
-- Todo dentro de transacciones revertidas; @@TRANCOUNT = 0 al terminar.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_ata_p2_solicitudes_calendario';
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @tz NVARCHAR(128) = CONVERT(NVARCHAR(128), dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER'));

    -- ATA_P2_00: objetos, mensaje y permisos
    IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_sesion_docente_paginado', N'P') IS NULL
       OR OBJECT_ID(N'dbo.usp_consultar_sesiones_calendario_estudiante', N'P') IS NULL
       OR OBJECT_ID(N'dbo.usp_consultar_sesiones_calendario_docente', N'P') IS NULL
       OR OBJECT_ID(N'dbo.usp_validar_rango_calendario_interno', N'P') IS NULL
       OR OBJECT_ID(N'dbo.uv_sesion_calendario', N'V') IS NULL
        THROW 59301, 'TEST FAILED ATA_P2_00: faltan objetos de ATA D6/D7 (migracion 52).', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario WHERE codigo = 'CAL_001') OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico WHERE codigo = 'CAL_001')
        THROW 59302, 'TEST FAILED ATA_P2_00: falta el mensaje CAL_001 (usuario y tecnico).', 1;
    IF (SELECT COUNT(*) FROM sys.database_permissions p
        WHERE p.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') AND p.state = 'G'
          AND ((p.permission_name = 'EXECUTE' AND p.major_id IN (OBJECT_ID(N'dbo.usp_consultar_solicitudes_sesion_docente_paginado'), OBJECT_ID(N'dbo.usp_consultar_sesiones_calendario_estudiante'), OBJECT_ID(N'dbo.usp_consultar_sesiones_calendario_docente')))
            OR (p.permission_name = 'SELECT' AND p.major_id = OBJECT_ID(N'dbo.uv_sesion_calendario')))) <> 4
        THROW 59303, 'TEST FAILED ATA_P2_00: rol_asistencias_runtime debe tener EXECUTE sobre los 3 SP y SELECT sobre uv_sesion_calendario.', 1;
    PRINT 'TEST_PASS:ATA_P2_00_OBJETOS_Y_PERMISOS';

    CREATE TABLE #ata_r (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL);
    CREATE TABLE #ata_apr (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL,
        estadoResultado BIT NOT NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaHoraInicio DATETIME2 NULL, totalEstudiantesActivos INT NULL);
    CREATE TABLE #ata_can (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL,
        estadoResultado BIT NOT NULL, idSesion UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL, fechaCancelacionUtc DATETIME2(0) NULL, totalEstudiantesActivos INT NULL);
    CREATE TABLE #ata_sol (idSesion UNIQUEIDENTIFIER, nombreSesion NVARCHAR(200), codigoSesion NVARCHAR(50), idGrupo UNIQUEIDENTIFIER, nombreGrupo NVARCHAR(200), nombreAsignatura NVARCHAR(200),
        idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(200), idDocente UNIQUEIDENTIFIER, nombreDocente NVARCHAR(400), fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2,
        estadoSolicitud NVARCHAR(30), nombreEstadoSolicitud NVARCHAR(100), fechaSolicitudUtc DATETIME2, fechaResolucionUtc DATETIME2 NULL, observacion NVARCHAR(500) NULL,
        usuarioSolicitante UNIQUEIDENTIFIER, pendienteAprobacion BIT, estaCancelada BIT, totalRegistros INT);
    CREATE TABLE #ata_cal (idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(200), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(50),
        nombreAsignatura NVARCHAR(200), idDocente UNIQUEIDENTIFIER, nombreDocente NVARCHAR(400), fechaHoraInicioUtc DATETIME2, fechaHoraFinUtc DATETIME2, esExtraordinaria BIT,
        estaCancelada BIT, motivoCancelacion NVARCHAR(500) NULL, esCancelacionAutomatica BIT NULL, nombreDiaFestivo NVARCHAR(200) NULL);

    -- Fixtures: el docente crea 3 sesiones manuales (pendientes) a las 05:00 locales de tres dias distintos (DEC-072: franja sin clases)
    DECLARE @base DATE = DATEADD(DAY, 2, CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @tz AS DATE));
    DECLARE @i1 DATETIME2 = CAST(DATEADD(HOUR, 5, CAST(DATEADD(DAY, 2, @base) AS DATETIME2)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2);
    DECLARE @i2 DATETIME2 = DATEADD(DAY, 1, @i1), @i3 DATETIME2 = DATEADD(DAY, 2, @i1);
    DECLARE @e1 DATETIME2 = DATEADD(HOUR, 2, @i1), @e2 DATETIME2 = DATEADD(HOUR, 2, @i2), @e3 DATETIME2 = DATEADD(HOUR, 2, @i3);
    INSERT #ata_r EXEC dbo.usp_crear_sesion_v2 @idGrupo = @grupoG, @nombre = N'ATA aprobada', @fechaHoraInicio = @i1, @fechaHoraFin = @e1, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    INSERT #ata_r EXEC dbo.usp_crear_sesion_v2 @idGrupo = @grupoG, @nombre = N'ATA pendiente', @fechaHoraInicio = @i2, @fechaHoraFin = @e2, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    INSERT #ata_r EXEC dbo.usp_crear_sesion_v2 @idGrupo = @grupoG, @nombre = N'ATA rechazada', @fechaHoraInicio = @i3, @fechaHoraFin = @e3, @idCorrelacion = @c, @idUsuarioEjecutor = @uT;
    IF (SELECT COUNT(*) FROM #ata_r WHERE estadoResultado = 1) <> 3
        THROW 59310, 'TEST FAILED ATA_P2_01: las 3 sesiones manuales de la prueba debieron crearse.', 1;
    DECLARE @sApr UNIQUEIDENTIFIER = (SELECT id FROM dbo.Sesion WHERE grupo = @grupoG AND nombre = N'ATA aprobada');
    DECLARE @sPen UNIQUEIDENTIFIER = (SELECT id FROM dbo.Sesion WHERE grupo = @grupoG AND nombre = N'ATA pendiente');
    DECLARE @sRec UNIQUEIDENTIFIER = (SELECT id FROM dbo.Sesion WHERE grupo = @grupoG AND nombre = N'ATA rechazada');

    -- ATA_P2_01: el docente ve sus 3 pendientes, una fila por sesion aunque el grupo sea mixto (programas A y B), fechaSolicitudUtc DESC
    INSERT #ata_sol EXEC dbo.usp_consultar_solicitudes_sesion_docente_paginado @idUsuario = @uT, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #ata_sol) <> 3 OR EXISTS (SELECT 1 FROM #ata_sol WHERE totalRegistros <> 3 OR pendienteAprobacion <> 1 OR estadoSolicitud <> N'PENDIENTE' OR idGrupo <> @grupoG)
       OR EXISTS (SELECT 1 FROM #ata_sol GROUP BY idSesion HAVING COUNT(*) > 1)
       OR EXISTS (SELECT 1 FROM #ata_sol WHERE nombreAsignatura IS NULL OR nombreDocente IS NULL OR nombrePrograma IS NULL OR nombreGrupo IS NULL)
       OR EXISTS (SELECT 1 FROM #ata_sol WHERE idPrograma NOT IN (@progA, @progB))
        THROW 59311, 'TEST FAILED ATA_P2_01: el docente debe ver sus 3 solicitudes pendientes, una fila por sesion y con un programa del grupo.', 1;
    IF EXISTS (SELECT 1 FROM (SELECT fechaSolicitudUtc, prev = LAG(fechaSolicitudUtc) OVER (ORDER BY (SELECT NULL)) FROM #ata_sol) x WHERE prev < fechaSolicitudUtc)
        THROW 59312, 'TEST FAILED ATA_P2_01: el orden debe ser fechaSolicitudUtc DESC.', 1;
    TRUNCATE TABLE #ata_sol;
    PRINT 'TEST_PASS:ATA_P2_01_DOCENTE_VE_SUS_PENDIENTES';

    -- ATA_P2_02: aprobar (CA) y rechazar (CB); soloPendientes = 0, @idGrupo y paginacion
    INSERT #ata_apr EXEC dbo.usp_aprobar_solicitud_sesion @idSesion = @sApr, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    DECLARE @motivo NVARCHAR(50) = (SELECT TOP 1 codigo FROM dbo.uv_motivo_cancelacion_sesion WHERE estaActivo = 1 ORDER BY orden);
    INSERT #ata_can EXEC dbo.usp_rechazar_solicitud_sesion @idSesion = @sRec, @codigoMotivo = @motivo, @observacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCB;
    IF NOT EXISTS (SELECT 1 FROM #ata_apr WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM #ata_can WHERE estadoResultado = 1)
        THROW 59313, 'TEST FAILED ATA_P2_02: la aprobacion y el rechazo de la prueba debieron ejecutarse.', 1;
    INSERT #ata_sol EXEC dbo.usp_consultar_solicitudes_sesion_docente_paginado @idUsuario = @uT, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #ata_sol) <> 1 OR NOT EXISTS (SELECT 1 FROM #ata_sol WHERE idSesion = @sPen AND totalRegistros = 1)
        THROW 59314, 'TEST FAILED ATA_P2_02: por defecto solo la solicitud pendiente.', 1;
    TRUNCATE TABLE #ata_sol;
    INSERT #ata_sol EXEC dbo.usp_consultar_solicitudes_sesion_docente_paginado @idUsuario = @uT, @soloPendientes = 0, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #ata_sol) <> 3 OR EXISTS (SELECT 1 FROM #ata_sol WHERE totalRegistros <> 3)
       OR NOT EXISTS (SELECT 1 FROM #ata_sol WHERE idSesion = @sApr AND estadoSolicitud = N'APROBADA' AND pendienteAprobacion = 0 AND fechaResolucionUtc IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM #ata_sol WHERE idSesion = @sRec AND estadoSolicitud = N'RECHAZADA' AND estaCancelada = 1 AND pendienteAprobacion = 0)
        THROW 59315, 'TEST FAILED ATA_P2_02: con soloPendientes = 0 el docente ve las 3 (aprobada, pendiente y rechazada).', 1;
    TRUNCATE TABLE #ata_sol;
    INSERT #ata_sol EXEC dbo.usp_consultar_solicitudes_sesion_docente_paginado @idUsuario = @uT, @soloPendientes = 0, @idGrupo = @grupoG, @numeroPagina = 2, @tamanoPagina = 2, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #ata_sol) <> 1 OR EXISTS (SELECT 1 FROM #ata_sol WHERE totalRegistros <> 3)
        THROW 59316, 'TEST FAILED ATA_P2_02: la pagina 2 de tamano 2 trae 1 fila y totalRegistros = 3.', 1;
    TRUNCATE TABLE #ata_sol;
    PRINT 'TEST_PASS:ATA_P2_02_TODAS_FILTRO_Y_PAGINACION';

    -- ATA_P2_03: aislamiento y RBAC
    DECLARE @uOtroDoc UNIQUEIDENTIFIER = (SELECT TOP 1 d.usuario FROM dbo.Docente d INNER JOIN dbo.Usuario u ON u.id = d.usuario AND u.estado = 1 WHERE d.usuario <> @uT ORDER BY d.id);
    DECLARE @errRbac NVARCHAR(4000);
    INSERT #ata_sol EXEC dbo.usp_consultar_solicitudes_sesion_docente_paginado @idUsuario = @uOtroDoc, @soloPendientes = 0, @idCorrelacion = @c;
    IF @uOtroDoc IS NULL OR EXISTS (SELECT 1 FROM #ata_sol WHERE idGrupo = @grupoG)
        THROW 59317, 'TEST FAILED ATA_P2_03: otro docente no debe ver las solicitudes de un grupo ajeno.', 1;
    TRUNCATE TABLE #ata_sol;
    INSERT #ata_sol EXEC dbo.usp_consultar_solicitudes_sesion_docente_paginado @idUsuario = @uOtroDoc, @soloPendientes = 0, @idGrupo = @grupoG, @idCorrelacion = @c;
    IF EXISTS (SELECT 1 FROM #ata_sol)
        THROW 59318, 'TEST FAILED ATA_P2_03: filtrar por un grupo ajeno no debe devolver filas.', 1;
    BEGIN TRY
        INSERT #ata_sol EXEC dbo.usp_consultar_solicitudes_sesion_docente_paginado @idUsuario = @uCA, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @errRbac = ERROR_MESSAGE();
    END CATCH;
    IF @errRbac IS NULL OR @errRbac NOT LIKE N'%DBCODE=SEC[_]001|%'
        THROW 59319, 'TEST FAILED ATA_P2_03: el coordinador no consulta las solicitudes del docente (SEC_001).', 1;
    SET @errRbac = NULL;
    BEGIN TRY
        INSERT #ata_sol EXEC dbo.usp_consultar_solicitudes_sesion_docente_paginado @idUsuario = @uT, @numeroPagina = 0, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @errRbac = ERROR_MESSAGE();
    END CATCH;
    IF @errRbac IS NULL OR @errRbac NOT LIKE N'%DBCODE=PAG[_]001|%'
        THROW 59320, 'TEST FAILED ATA_P2_03: pagina 0 debe responder PAG_001.', 1;
    TRUNCATE TABLE #ata_sol;
    PRINT 'TEST_PASS:ATA_P2_03_AISLAMIENTO_Y_RBAC';

    -- ATA_P2_04: calendario del docente. Dia 0: generada 08:00-10:00 (sA) y 23:30-23:50 (sB); dia 1: cancelada por festivo 08:00 (sF) y por el docente 14:00 (sM);
    -- dia 2 (@base + 2): la extraordinaria aprobada de 05:00; dia 3: pendiente y dia 4: rechazada (excluidas); dia 10: generada fuera del rango.
    DECLARE @sA UNIQUEIDENTIFIER = NEWID(), @sB UNIQUEIDENTIFIER = NEWID(), @sF UNIQUEIDENTIFIER = NEWID(), @sM UNIQUEIDENTIFIER = NEWID(), @sLejos UNIQUEIDENTIFIER = NEWID();
    DECLARE @a0 DATETIME2 = CAST(DATEADD(HOUR, 8, CAST(@base AS DATETIME2)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2);
    DECLARE @b0 DATETIME2 = CAST(DATEADD(MINUTE, 23 * 60 + 30, CAST(@base AS DATETIME2)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2);
    DECLARE @f1 DATETIME2 = CAST(DATEADD(HOUR, 8, CAST(DATEADD(DAY, 1, @base) AS DATETIME2)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2);
    DECLARE @m1 DATETIME2 = CAST(DATEADD(HOUR, 14, CAST(DATEADD(DAY, 1, @base) AS DATETIME2)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2);
    DECLARE @l10 DATETIME2 = CAST(DATEADD(HOUR, 8, CAST(DATEADD(DAY, 10, @base) AS DATETIME2)) AT TIME ZONE @tz AT TIME ZONE 'UTC' AS DATETIME2);
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sA, N'ATA generada A', 911, N'ATA911', 1, @grupoG, @a0, DATEADD(HOUR, 2, @a0), N'UTC_GENERADOR'),
           (@sB, N'ATA generada B', 912, N'ATA912', 1, @grupoG, @b0, DATEADD(MINUTE, 20, @b0), N'UTC_GENERADOR'),
           (@sF, N'ATA festivo', 913, N'ATA913', 1, @grupoG, @f1, DATEADD(HOUR, 2, @f1), N'UTC_GENERADOR'),
           (@sM, N'ATA cancelada docente', 914, N'ATA914', 1, @grupoG, @m1, DATEADD(HOUR, 2, @m1), N'UTC_GENERADOR'),
           (@sLejos, N'ATA lejos', 915, N'ATA915', 1, @grupoG, @l10, DATEADD(HOUR, 2, @l10), N'UTC_GENERADOR');
    DECLARE @idFestivo UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.DiaFestivo (id, fecha, nombre, fuente, estaActivo, fechaCargaUtc, idCorrelacionCarga)
    VALUES (@idFestivo, DATEADD(DAY, 1, @base), N'Festivo ATA', N'PRUEBA', 1, SYSUTCDATETIME(), @c);
    INSERT dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, idCorrelacion)
    SELECT @sF, t.id, N'Dia festivo', @idFestivo, NULL, @c FROM dbo.TipoCancelacionSesion t WHERE t.esAutomatica = 1;
    INSERT dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, idCorrelacion)
    SELECT @sM, t.id, N'Calamidad del docente', NULL, @uT, @c FROM dbo.TipoCancelacionSesion t WHERE t.esAutomatica = 0;

    DECLARE @hasta06 DATE = DATEADD(DAY, 6, @base);
    INSERT #ata_cal EXEC dbo.usp_consultar_sesiones_calendario_docente @idUsuario = @uT, @desde = @base, @hasta = @hasta06, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #ata_cal) <> 5
       OR EXISTS (SELECT 1 FROM #ata_cal WHERE idSesion IN (@sPen, @sRec, @sLejos))
       OR (SELECT COUNT(*) FROM #ata_cal WHERE idSesion IN (@sA, @sB, @sF, @sM, @sApr)) <> 5
        THROW 59330, 'TEST FAILED ATA_P2_04: el calendario del docente trae 5 sesiones (sin pendiente, rechazada ni fuera del rango).', 1;
    IF EXISTS (SELECT 1 FROM (SELECT fechaHoraInicioUtc, prev = LAG(fechaHoraInicioUtc) OVER (ORDER BY (SELECT NULL)) FROM #ata_cal) x WHERE prev > fechaHoraInicioUtc)
        THROW 59331, 'TEST FAILED ATA_P2_04: el orden debe ser por inicio ascendente.', 1;
    IF EXISTS (SELECT 1 FROM #ata_cal WHERE idGrupo <> @grupoG OR idAsignatura <> @asigOPT OR codigoAsignatura <> N'B2NM-OPT' OR nombreAsignatura <> N'B2NM Optativa'
                                           OR nombreGrupo <> N'B2NM-G' OR idDocente <> @docT OR nombreDocente IS NULL OR codigoGrupo IS NULL)
        THROW 59332, 'TEST FAILED ATA_P2_04: grupo, asignatura y docente de cada fila.', 1;
    IF NOT EXISTS (SELECT 1 FROM #ata_cal WHERE idSesion = @sA AND fechaHoraInicioUtc = @a0 AND fechaHoraFinUtc = DATEADD(HOUR, 2, @a0) AND esExtraordinaria = 0 AND estaCancelada = 0
                                               AND motivoCancelacion IS NULL AND nombreDiaFestivo IS NULL)
       OR NOT EXISTS (SELECT 1 FROM #ata_cal WHERE idSesion = @sApr AND esExtraordinaria = 1 AND estaCancelada = 0)
       OR NOT EXISTS (SELECT 1 FROM #ata_cal WHERE idSesion = @sF AND estaCancelada = 1 AND esCancelacionAutomatica = 1 AND nombreDiaFestivo = N'Festivo ATA' AND esExtraordinaria = 0)
       OR NOT EXISTS (SELECT 1 FROM #ata_cal WHERE idSesion = @sM AND estaCancelada = 1 AND esCancelacionAutomatica = 0 AND motivoCancelacion = N'Calamidad del docente' AND nombreDiaFestivo IS NULL)
        THROW 59333, 'TEST FAILED ATA_P2_04: banderas esExtraordinaria, estaCancelada, esCancelacionAutomatica, motivo y festivo.', 1;
    TRUNCATE TABLE #ata_cal;
    INSERT #ata_cal EXEC dbo.usp_consultar_sesiones_calendario_docente @idUsuario = @uOtroDoc, @desde = @base, @hasta = @hasta06, @idCorrelacion = @c;
    IF EXISTS (SELECT 1 FROM #ata_cal WHERE idGrupo = @grupoG)
        THROW 59334, 'TEST FAILED ATA_P2_04: otro docente no ve el calendario de un grupo ajeno.', 1;
    TRUNCATE TABLE #ata_cal;
    PRINT 'TEST_PASS:ATA_P2_04_CALENDARIO_DOCENTE';

    -- ATA_P2_05: calendario del estudiante. Borde local: 23:30 local del dia 0 es del dia 0 aunque en UTC ya sea el dia 1.
    INSERT #ata_cal EXEC dbo.usp_consultar_sesiones_calendario_estudiante @idUsuario = @uEA, @desde = @base, @hasta = @base, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #ata_cal) <> 2 OR NOT EXISTS (SELECT 1 FROM #ata_cal WHERE idSesion = @sA) OR NOT EXISTS (SELECT 1 FROM #ata_cal WHERE idSesion = @sB)
        THROW 59340, 'TEST FAILED ATA_P2_05: el dia local 0 trae las sesiones de 08:00 y de 23:30 locales.', 1;
    TRUNCATE TABLE #ata_cal;
    DECLARE @dia1 DATE = DATEADD(DAY, 1, @base);
    INSERT #ata_cal EXEC dbo.usp_consultar_sesiones_calendario_estudiante @idUsuario = @uEA, @desde = @dia1, @hasta = @dia1, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #ata_cal) <> 2 OR NOT EXISTS (SELECT 1 FROM #ata_cal WHERE idSesion = @sF AND estaCancelada = 1) OR NOT EXISTS (SELECT 1 FROM #ata_cal WHERE idSesion = @sM AND estaCancelada = 1)
        THROW 59341, 'TEST FAILED ATA_P2_05: el dia local 1 trae solo las dos canceladas (la de 23:30 del dia 0 no se corre al dia 1).', 1;
    TRUNCATE TABLE #ata_cal;
    INSERT #ata_cal EXEC dbo.usp_consultar_sesiones_calendario_estudiante @idUsuario = @uEA, @desde = @base, @hasta = @hasta06, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #ata_cal) <> 5 OR EXISTS (SELECT 1 FROM #ata_cal WHERE idSesion IN (@sPen, @sRec, @sLejos))
        THROW 59342, 'TEST FAILED ATA_P2_05: el estudiante inscrito ve las mismas 5 sesiones que el docente.', 1;
    TRUNCATE TABLE #ata_cal;
    -- una matricula que no esta inscrita no cuenta
    UPDATE eg SET estado = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo <> N'A' ORDER BY codigo)
    FROM dbo.EstudianteGrupo eg WHERE eg.estudiante = @eB AND eg.grupo = @grupoG;
    INSERT #ata_cal EXEC dbo.usp_consultar_sesiones_calendario_estudiante @idUsuario = @uEB, @desde = @base, @hasta = @hasta06, @idCorrelacion = @c;
    IF EXISTS (SELECT 1 FROM #ata_cal)
        THROW 59343, 'TEST FAILED ATA_P2_05: una matricula no inscrita no entra al calendario.', 1;
    TRUNCATE TABLE #ata_cal;
    PRINT 'TEST_PASS:ATA_P2_05_CALENDARIO_ESTUDIANTE';

    -- ATA_P2_06: rango invalido y RBAC
    DECLARE @i INT = 0, @err NVARCHAR(4000), @d1 DATE, @d2 DATE, @hasta31 DATE = DATEADD(DAY, 30, @base);
    DECLARE @casos TABLE (n INT, d1 DATE NULL, d2 DATE NULL);
    INSERT @casos VALUES (1, DATEADD(DAY, 1, @base), @base), (2, @base, DATEADD(DAY, 31, @base)), (3, NULL, @base), (4, @base, NULL);
    WHILE @i < 4
    BEGIN
        SET @i += 1; SET @err = NULL;
        SELECT @d1 = d1, @d2 = d2 FROM @casos WHERE n = @i;
        BEGIN TRY
            INSERT #ata_cal EXEC dbo.usp_consultar_sesiones_calendario_estudiante @idUsuario = @uEA, @desde = @d1, @hasta = @d2, @idCorrelacion = @c;
        END TRY
        BEGIN CATCH
            SET @err = ERROR_MESSAGE();
        END CATCH;
        IF @err IS NULL OR @err NOT LIKE N'%DBCODE=CAL[_]001|%'
            THROW 59350, 'TEST FAILED ATA_P2_06: un rango invalido (hasta < desde, mas de 31 dias o fechas nulas) debe responder CAL_001.', 1;
    END
    INSERT #ata_cal EXEC dbo.usp_consultar_sesiones_calendario_docente @idUsuario = @uT, @desde = @base, @hasta = @hasta31, @idCorrelacion = @c;   -- exactamente 31 dias
    IF NOT EXISTS (SELECT 1 FROM #ata_cal WHERE idSesion = @sLejos)
        THROW 59351, 'TEST FAILED ATA_P2_06: 31 dias es un rango valido e incluye la sesion del dia 10.', 1;
    TRUNCATE TABLE #ata_cal;
    SET @err = NULL;
    BEGIN TRY
        INSERT #ata_cal EXEC dbo.usp_consultar_sesiones_calendario_docente @idUsuario = @uEA, @desde = @base, @hasta = @hasta06, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH;
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=SEC[_]001|%'
        THROW 59352, 'TEST FAILED ATA_P2_06: un estudiante no consulta el calendario del docente (SEC_001).', 1;
    SET @err = NULL;
    BEGIN TRY
        INSERT #ata_cal EXEC dbo.usp_consultar_sesiones_calendario_estudiante @idUsuario = @uT, @desde = @base, @hasta = @hasta06, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH;
    IF @err IS NULL OR @err NOT LIKE N'%DBCODE=SEC[_]001|%'
        THROW 59353, 'TEST FAILED ATA_P2_06: un docente no consulta el calendario del estudiante (SEC_001).', 1;
    -- el SESSION_CONTEXT del ejecutor queda como estaba (las validaciones lo fijan y lo restauran)
    DECLARE @centinela UNIQUEIDENTIFIER = NEWID();
    EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @centinela, @read_only = 0;
    INSERT #ata_cal EXEC dbo.usp_consultar_sesiones_calendario_docente @idUsuario = @uT, @desde = @base, @hasta = @hasta06, @idCorrelacion = @c;
    IF CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'idUsuarioEjecutor')) <> @centinela
        THROW 59354, 'TEST FAILED ATA_P2_06: el SESSION_CONTEXT del ejecutor debe quedar como estaba.', 1;
    EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = NULL, @read_only = 0;
    PRINT 'TEST_PASS:ATA_P2_06_RANGO_Y_RBAC';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 59397, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 59398, 'TEST FAILED ATA_P2: quedaron transacciones abiertas.', 1;
PRINT 'TEST_PASS:ATA_P2_TRANCOUNT_ZERO';
PRINT 'TEST END: test_ata_p2_solicitudes_calendario';
GO
