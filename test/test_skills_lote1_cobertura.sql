USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 1 (plan por lotes 2026-11-25): pruebas de caracterizacion de objetos que no tenian prueba directa
-- (cobertura-pruebas-objetos-bd). Fijan el comportamiento ACTUAL, para que los lotes de refactor posteriores demuestren que no lo cambian.
-- Todo corre dentro de una transaccion revertida, sobre la fixture de asignatura compartida de B2NM.
--   SKL1_F01_VALIDAR_CORREO              ufn_validar_correo: validos, NULL, vacio, sin arroba, doble arroba, puntos seguidos, espacios
--   SKL1_F02_VALIDAR_NUMERO              ufn_validar_numero: 6 y 10 digitos validos; NULL, 0, negativo, 5 y 11 digitos invalidos
--   SKL1_F03_VALIDAR_TEXTO               ufn_validar_texto: alfanumerico con espacios valido; NULL, vacio, solo espacios y simbolos invalidos
--   SKL1_F04_IDENTIDAD_USUARIO_JSON      ufn_obtener_identidad_usuario_json: JSON del usuario; usuario inexistente o NULL => NULL
--   SKL1_F05_PROGRAMAS_AMBITO_EJECUTOR   ufn_programas_ambito_ejecutor: coordinador => su programa; decano => programas de su facultad;
--                                        docente, inexistente o NULL => 0 filas
--   SKL1_V01_CATALOGOS_REFLEJAN_TABLA    uv_perfil, uv_caracter_asignatura_plan, uv_estado_alerta_inasistencia, uv_tipo_alerta_inasistencia,
--                                        uv_estado_revision_cancelacion y uv_transicion_revision_cancelacion devuelven una fila por fila de su tabla
--   SKL1_V02_FORMA_VISTAS                columnas (nombre y orden) de las 10 vistas sin prueba previa
--   SKL1_V03_AUDITORIA_EVENTO            uv_auditoria_evento: nombre del actor y esAccionAsistencia (accion de asistencia = 1; otra = 0)
--   SKL1_V04_ESTADISTICA_GRUPO           uv_estadistica_grupo: totales del grupo de la fixture (3 matriculas activas) y de un grupo sin matriculas (0)
--   SKL1_V05_ESTUDIANTE_GRUPO_PROGRAMA   uv_estudiante_grupo_programa: solo las matriculas cuyo estudiante esta vinculado al programa del grupo
--   SKL1_V06_FACULTAD_RESUMEN            uv_facultad_resumen: totalProgramas = programas de la facultad en uv_programa; vistas base sin filtro de sesion
--   SKL1_S01_ASOCIAR_RECHAZOS            usp_internal_asociar_asignatura_plan: PLA_004 (semestre fuera del plan), ASI_007 (caracter inexistente),
--                                        ASI_003 (vinculo activo ya existente); ningun rechazo escribe
--   SKL1_S02_ASOCIAR_INSERTA_Y_REACTIVA  usp_internal_asociar_asignatura_plan: inserta un vinculo nuevo con el caracter por defecto y reactiva
--                                        (misma fila) un vinculo inactivo del mismo semestre
--   SKL1_S03_CERRAR_TOMA                 usp_internal_cerrar_toma: cierra la toma abierta, su token y marca ausentes (3) cuando se pide
--   SKL1_TRANCOUNT_ZERO                  al terminar no queda transaccion abierta
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote1_cobertura';
DROP TABLE IF EXISTS #skl1Toma;
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @msg NVARCHAR(4000);

    -- ===================================================================== F01
    IF dbo.ufn_validar_correo(N'ana.perez@uco.edu.co') <> 1 OR dbo.ufn_validar_correo(N'a@b.co') <> 1
       OR dbo.ufn_validar_correo(NULL) <> 0 OR dbo.ufn_validar_correo(N'') <> 0 OR dbo.ufn_validar_correo(N'   ') <> 0
       OR dbo.ufn_validar_correo(N'ana.uco.edu.co') <> 0 OR dbo.ufn_validar_correo(N'ana@@uco.edu.co') <> 0
       OR dbo.ufn_validar_correo(N'ana@uco..co') <> 0 OR dbo.ufn_validar_correo(N'ana perez@uco.co') <> 0
       OR dbo.ufn_validar_correo(N'@uco.co') <> 0
        THROW 54101, 'TEST FAILED: SKL1_F01_VALIDAR_CORREO', 1;
    PRINT 'TEST_PASS:SKL1_F01_VALIDAR_CORREO';

    -- ===================================================================== F02
    IF dbo.ufn_validar_numero(123456) <> 1 OR dbo.ufn_validar_numero(1234567890) <> 1
       OR dbo.ufn_validar_numero(NULL) <> 0 OR dbo.ufn_validar_numero(0) <> 0 OR dbo.ufn_validar_numero(-123456) <> 0
       OR dbo.ufn_validar_numero(12345) <> 0 OR dbo.ufn_validar_numero(12345678901) <> 0
        THROW 54102, 'TEST FAILED: SKL1_F02_VALIDAR_NUMERO', 1;
    PRINT 'TEST_PASS:SKL1_F02_VALIDAR_NUMERO';

    -- ===================================================================== F03
    IF dbo.ufn_validar_texto(N'Ingenieria de Sistemas 2') <> 1
       OR dbo.ufn_validar_texto(NULL) <> 0 OR dbo.ufn_validar_texto(N'') <> 0 OR dbo.ufn_validar_texto(N'   ') <> 0
       OR dbo.ufn_validar_texto(N'Sistemas#1') <> 0 OR dbo.ufn_validar_texto(N'a-b') <> 0
        THROW 54103, 'TEST FAILED: SKL1_F03_VALIDAR_TEXTO', 1;
    PRINT 'TEST_PASS:SKL1_F03_VALIDAR_TEXTO';

    -- ===================================================================== F04
    DECLARE @json NVARCHAR(MAX) = dbo.ufn_obtener_identidad_usuario_json(@uT);
    IF @json IS NULL OR ISJSON(@json) <> 1
       OR JSON_VALUE(@json, '$.numeroIdentificacion') <> N'1950000002'
       OR JSON_VALUE(@json, '$.primerNombre') <> N'DocT' OR JSON_VALUE(@json, '$.primerApellido') <> N'B2NM'
       OR TRY_CAST(JSON_VALUE(@json, '$.idTipoIdentificacion') AS UNIQUEIDENTIFIER) <> @tipoCC
       OR dbo.ufn_obtener_identidad_usuario_json(NEWID()) IS NOT NULL
       OR dbo.ufn_obtener_identidad_usuario_json(NULL) IS NOT NULL
        THROW 54104, 'TEST FAILED: SKL1_F04_IDENTIDAD_USUARIO_JSON', 1;
    PRINT 'TEST_PASS:SKL1_F04_IDENTIDAD_USUARIO_JSON';

    -- ===================================================================== F05
    IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_ambito_ejecutor(@uCA) WHERE idPrograma = @progA AND rol = N'COORDINADOR')
       OR EXISTS (SELECT 1 FROM dbo.ufn_programas_ambito_ejecutor(@uCA) WHERE idPrograma = @progB)
       OR NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_ambito_ejecutor(@uCB) WHERE idPrograma = @progB AND rol = N'COORDINADOR')
       OR NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_ambito_ejecutor(@uDec) WHERE idPrograma = @progA AND rol = N'DECANO')
       OR NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_ambito_ejecutor(@uDec) WHERE idPrograma = @progB AND rol = N'DECANO')
       OR (SELECT COUNT(*) FROM dbo.ufn_programas_ambito_ejecutor(@uDec) WHERE rol = N'DECANO')
          <> (SELECT COUNT(*) FROM dbo.Programa WHERE facultad = @fac)
       OR EXISTS (SELECT 1 FROM dbo.ufn_programas_ambito_ejecutor(@uT))
       OR EXISTS (SELECT 1 FROM dbo.ufn_programas_ambito_ejecutor(NEWID()))
       OR EXISTS (SELECT 1 FROM dbo.ufn_programas_ambito_ejecutor(NULL))
        THROW 54105, 'TEST FAILED: SKL1_F05_PROGRAMAS_AMBITO_EJECUTOR', 1;
    PRINT 'TEST_PASS:SKL1_F05_PROGRAMAS_AMBITO_EJECUTOR';

    -- ===================================================================== V01
    IF (SELECT COUNT(*) FROM dbo.uv_perfil) <> (SELECT COUNT(*) FROM dbo.Perfil)
       OR EXISTS (SELECT id, codigo FROM dbo.Perfil EXCEPT SELECT id, codigo FROM dbo.uv_perfil)
       OR (SELECT COUNT(*) FROM dbo.uv_caracter_asignatura_plan) <> (SELECT COUNT(*) FROM dbo.CaracterAsignaturaPlan)
       OR EXISTS (SELECT id, codigo, estado FROM dbo.CaracterAsignaturaPlan EXCEPT SELECT id, codigo, estaActivo FROM dbo.uv_caracter_asignatura_plan)
       OR (SELECT COUNT(*) FROM dbo.uv_estado_alerta_inasistencia) <> (SELECT COUNT(*) FROM dbo.EstadoAlertaInasistencia)
       OR (SELECT COUNT(*) FROM dbo.uv_tipo_alerta_inasistencia) <> (SELECT COUNT(*) FROM dbo.TipoAlertaInasistencia)
       OR (SELECT COUNT(*) FROM dbo.uv_estado_revision_cancelacion) <> (SELECT COUNT(*) FROM dbo.EstadoRevisionCancelacion)
       OR (SELECT COUNT(*) FROM dbo.uv_transicion_revision_cancelacion) <> (SELECT COUNT(*) FROM dbo.TransicionRevisionCancelacion)
       OR EXISTS (SELECT 1 FROM dbo.uv_transicion_revision_cancelacion t
                  INNER JOIN dbo.EstadoRevisionCancelacion o ON o.id = t.idEstadoOrigen
                  WHERE o.codigo <> t.codigoEstadoOrigen)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_perfil WHERE codigo = N'DE')
        THROW 54111, 'TEST FAILED: SKL1_V01_CATALOGOS_REFLEJAN_TABLA', 1;
    PRINT 'TEST_PASS:SKL1_V01_CATALOGOS_REFLEJAN_TABLA';

    -- ===================================================================== V02
    DECLARE @formas TABLE (vista SYSNAME NOT NULL, columnas NVARCHAR(MAX) NOT NULL);
    INSERT @formas (vista, columnas) VALUES
(N'uv_auditoria_evento', N'id,occurredAt,actorId,actorType,nombreActor,action,resourceType,resourceId,result,correlationId,httpMethod,path,httpStatus,clientIp,errorCode,metadata,esAccionAsistencia'),
        (N'uv_caracter_asignatura_plan', N'id,codigo,nombre,orden,estaActivo'),
        (N'uv_estadistica_grupo', N'id,cupoMaximoConfigurado,totalMatriculadosGrupo,cantidadCanceladoPorVoluntadPropia,cantidadActivos,cantidadCanceladoPorInasistencia,cantidadFinalizados'),
        (N'uv_estado_alerta_inasistencia', N'id,codigo,nombre,estaVigente'),
        (N'uv_estado_revision_cancelacion', N'id,codigo,nombre,orden,esInicial,requiereAccionDocente,requiereAccionResolutor,conservaMatricula,cancelaMatricula,esFinal'),
        (N'uv_estudiante_grupo_programa', N'id,idEstudiante,idGrupo,codigoEstadoEstudiante,idPrograma'),
        (N'uv_facultad_resumen', N'id,nombreFacultad,idInstitucion,nombreInstitucion,idDecano,nombreCompletoDecano,estaActivaFacultad,estaActivaTextoFacultad,totalProgramas,totalEstudiantes'),
        (N'uv_perfil', N'id,codigo,nombre,nivel_acceso'),
        (N'uv_tipo_alerta_inasistencia', N'id,codigo,nombre,nivel,grupoParametroUmbral,claveParametroUmbral,tipoPlantillaEstudiante,codigoMensajeUsuario,creaRevisionCancelacion'),
        (N'uv_transicion_revision_cancelacion', N'id,idEstadoOrigen,codigoEstadoOrigen,codigoDecision,esDecisionResolutor,idEstadoDestino,codigoEstadoDestino,exigeUmbralPerdida,exigeResolutorDisponible,codigoMensajeExito,tipoPlantillaNotificacion');
    DECLARE @drift NVARCHAR(MAX) = (
        SELECT STRING_AGG(f.vista, ',')
        FROM @formas f
        OUTER APPLY (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), c.name), ',') WITHIN GROUP (ORDER BY c.column_id) AS columnas
                     FROM sys.columns c WHERE c.object_id = OBJECT_ID(CONCAT(N'dbo.', f.vista))) a
        WHERE a.columnas IS NULL OR a.columnas <> f.columnas);
    IF @drift IS NOT NULL OR (SELECT COUNT(*) FROM @formas) <> 10
    BEGIN
        SET @msg = CONCAT('TEST FAILED: SKL1_V02_FORMA_VISTAS ', @drift);
        THROW 54112, @msg, 1;
    END
    PRINT 'TEST_PASS:SKL1_V02_FORMA_VISTAS';

    -- ===================================================================== V03
    DECLARE @ae1 UNIQUEIDENTIFIER = NEWID(), @ae2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId,
                                     httpMethod, path, httpStatus)
    VALUES (@ae1, SYSDATETIMEOFFSET(), CAST(@uT AS NVARCHAR(120)), 'USER', 'CERRAR_SESION', 'SESION', NULL, 'SUCCESS', NEWID(), 'POST', N'/skl1', 200),
           (@ae2, SYSDATETIMEOFFSET(), N'no-es-un-guid', 'SYSTEM', 'CREAR_FACULTAD', 'FACULTAD', NULL, 'FAILURE', NULL, 'POST', N'/skl1', 400);
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_auditoria_evento WHERE id = @ae1 AND esAccionAsistencia = 1 AND nombreActor IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_auditoria_evento WHERE id = @ae2 AND esAccionAsistencia = 0 AND nombreActor IS NULL)
        THROW 54113, 'TEST FAILED: SKL1_V03_AUDITORIA_EVENTO', 1;
    PRINT 'TEST_PASS:SKL1_V03_AUDITORIA_EVENTO';

    -- ===================================================================== V04
    DECLARE @grupoVacio UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@grupoVacio, @asigOPT, @periodo, @codGrupo + 1, N'SKL1-Vacio', 25, 0, 0, 0, @docT);
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_estadistica_grupo WHERE id = @grupoG AND cupoMaximoConfigurado = 30 AND totalMatriculadosGrupo = 3
                   AND cantidadActivos = 3 AND cantidadCanceladoPorVoluntadPropia = 0 AND cantidadCanceladoPorInasistencia = 0 AND cantidadFinalizados = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estadistica_grupo WHERE id = @grupoVacio AND cupoMaximoConfigurado = 25 AND totalMatriculadosGrupo = 0
                   AND cantidadActivos = 0 AND cantidadCanceladoPorVoluntadPropia = 0 AND cantidadCanceladoPorInasistencia = 0 AND cantidadFinalizados = 0)
        THROW 54114, 'TEST FAILED: SKL1_V04_ESTADISTICA_GRUPO', 1;
    PRINT 'TEST_PASS:SKL1_V04_ESTADISTICA_GRUPO';

    -- ===================================================================== V05
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa WHERE idGrupo = @grupoG AND idEstudiante = @eA AND idPrograma = @progA AND codigoEstadoEstudiante = N'A')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa WHERE idGrupo = @grupoG AND idEstudiante = @eB AND idPrograma = @progB)
       OR EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa WHERE idGrupo = @grupoG AND idEstudiante = @e0)
       OR EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa WHERE idGrupo = @grupoG AND idEstudiante = @eA AND idPrograma = @progB)
        THROW 54115, 'TEST FAILED: SKL1_V05_ESTUDIANTE_GRUPO_PROGRAMA', 1;
    PRINT 'TEST_PASS:SKL1_V05_ESTUDIANTE_GRUPO_PROGRAMA';

    -- ===================================================================== V06
    EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = NULL;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_facultad_resumen r WHERE r.id = @fac
                   AND r.totalProgramas = (SELECT COUNT(*) FROM dbo.uv_programa p WHERE p.idFacultad = @fac) AND r.totalProgramas >= 2
                   AND r.totalEstudiantes >= 0)
       OR (SELECT COUNT(*) FROM dbo.uv_facultad_resumen) <> (SELECT COUNT(*) FROM dbo.uv_facultad)
        THROW 54116, 'TEST FAILED: SKL1_V06_FACULTAD_RESUMEN', 1;
    PRINT 'TEST_PASS:SKL1_V06_FACULTAD_RESUMEN';

    -- ===================================================================== S01
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @vinculos INT = (SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio WHERE asignatura = @asigOPT);
    EXEC dbo.usp_internal_asociar_asignatura_plan @idAsignatura = @asigOPT, @idPlanEstudio = @planB, @semestreNumero = 99,
         @codigoCaracter = NULL, @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=PLA[_]004|%' OR @mt NOT LIKE CONCAT(N'%Correlacion: ', @corr)
        THROW 54121, 'TEST FAILED: SKL1_S01_ASOCIAR_RECHAZOS (PLA_004)', 1;
    EXEC dbo.usp_internal_asociar_asignatura_plan @idAsignatura = @asigOPT, @idPlanEstudio = @planB, @semestreNumero = 7,
         @codigoCaracter = N'ZZZ', @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=ASI[_]007|%'
        THROW 54122, 'TEST FAILED: SKL1_S01_ASOCIAR_RECHAZOS (ASI_007)', 1;
    EXEC dbo.usp_internal_asociar_asignatura_plan @idAsignatura = @asigOPT, @idPlanEstudio = @planB, @semestreNumero = 7,
         @codigoCaracter = N'OPT', @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=ASI[_]003|%'
       OR (SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio WHERE asignatura = @asigOPT) <> @vinculos
        THROW 54123, 'TEST FAILED: SKL1_S01_ASOCIAR_RECHAZOS (ASI_003 o escritura en un rechazo)', 1;
    PRINT 'TEST_PASS:SKL1_S01_ASOCIAR_RECHAZOS';

    -- ===================================================================== S02
    DECLARE @asigNueva UNIQUEIDENTIFIER = NEWID();
    DECLARE @caracterDefecto NVARCHAR(3) = CAST(dbo.ufn_obtener_parametro('ASIGNATURA_PLAN', 'CARACTER_DEFECTO') AS NVARCHAR(3));
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, estado) VALUES (@asigNueva, N'SKL1-NUEVA', N'SKL1 Nueva', 2, @area, @comp, 1);
    EXEC dbo.usp_internal_asociar_asignatura_plan @idAsignatura = @asigNueva, @idPlanEstudio = @planB, @semestreNumero = 7,
         @codigoCaracter = NULL, @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape INNER JOIN dbo.CaracterAsignaturaPlan c ON c.id = ape.caracter
                               WHERE ape.asignatura = @asigNueva AND ape.semestrePlanEstudio = @speB AND ape.estaActivo = 1 AND c.codigo = @caracterDefecto)
        THROW 54124, 'TEST FAILED: SKL1_S02_ASOCIAR_INSERTA_Y_REACTIVA (insercion)', 1;
    DECLARE @idVinculoB UNIQUEIDENTIFIER = (SELECT id FROM dbo.AsignaturaPlanEstudio WHERE asignatura = @asigOPT AND semestrePlanEstudio = @speB);
    UPDATE dbo.AsignaturaPlanEstudio SET estaActivo = 0, fechaDesvinculacionUtc = SYSUTCDATETIME() WHERE id = @idVinculoB;
    EXEC dbo.usp_internal_asociar_asignatura_plan @idAsignatura = @asigOPT, @idPlanEstudio = @planB, @semestreNumero = 7,
         @codigoCaracter = N'OPT', @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio WHERE id = @idVinculoB AND estaActivo = 1 AND fechaDesvinculacionUtc IS NULL)
       OR (SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio WHERE asignatura = @asigOPT) <> @vinculos
        THROW 54125, 'TEST FAILED: SKL1_S02_ASOCIAR_INSERTA_Y_REACTIVA (reactivacion)', 1;
    PRINT 'TEST_PASS:SKL1_S02_ASOCIAR_INSERTA_Y_REACTIVA';

    -- ===================================================================== S03
    DECLARE @sesion UNIQUEIDENTIFIER = NEWID(), @idToma UNIQUEIDENTIFIER, @total INT, @fechaCierre DATETIME2(0);
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    VALUES (@sesion, N'SKL1 en curso', 1, N'SKL1S1', 1, @grupoG, DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, 90, SYSUTCDATETIME()), N'UTC_V2');
    CREATE TABLE #skl1Toma (idCorrelacion UNIQUEIDENTIFIER NULL, mu NVARCHAR(4000) NULL, mt NVARCHAR(4000) NULL, estado BIT NOT NULL,
        idToma UNIQUEIDENTIFIER NULL, numero SMALLINT NULL, codigoModo NVARCHAR(20) NULL, usaCodigoQr BIT NULL, fechaAperturaUtc DATETIME2(0) NULL,
        ventanaCierreUtc DATETIME2(0) NULL, totalTomasSesion INT NULL, horasToma DECIMAL(12,6) NULL,
        idTomaCerradaAnterior UNIQUEIDENTIFIER NULL, numeroTomaCerradaAnterior SMALLINT NULL, totalAusentesMarcadosAnterior INT NULL);
    INSERT INTO #skl1Toma EXEC dbo.usp_abrir_toma_asistencia @idSesion = @sesion, @codigoModo = N'MANUAL', @idCorrelacion = @corr, @idUsuarioEjecutor = @uT;
    SET @idToma = (SELECT idToma FROM #skl1Toma WHERE estado = 1);
    IF @idToma IS NULL
    BEGIN
        SET @msg = CONCAT('TEST FAILED: SKL1_S03_CERRAR_TOMA (no se pudo abrir la toma) ', (SELECT TOP 1 mt FROM #skl1Toma));
        THROW 54131, @msg, 1;
    END
    EXEC dbo.usp_internal_cerrar_toma @idToma = @idToma, @idSesion = @sesion, @idGrupo = @grupoG, @marcarAusentes = 1, @idCorrelacion = @corr,
         @totalAusentesMarcados = @total OUTPUT, @fechaCierreUtc = @fechaCierre OUTPUT;
    IF @total <> 3 OR @fechaCierre IS NULL
       OR NOT EXISTS (SELECT 1 FROM dbo.TomaAsistencia t INNER JOIN dbo.EstadoTomaAsistencia e ON e.id = t.estado
                      WHERE t.id = @idToma AND e.estaAbierta = 0 AND t.fechaCierreUtc = @fechaCierre AND t.fechaCierreUtc >= t.fechaAperturaUtc
                        AND t.totalAusentesMarcados = 3 AND t.idCorrelacionCierre = @corr)
       OR EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma WHERE toma = @idToma AND fechaCierreUtc IS NULL)
       OR (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE toma = @idToma) <> 3
        THROW 54132, 'TEST FAILED: SKL1_S03_CERRAR_TOMA', 1;
    PRINT 'TEST_PASS:SKL1_S03_CERRAR_TOMA';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
DROP TABLE IF EXISTS #skl1Toma;
IF @@TRANCOUNT <> 0
    THROW 54199, 'TEST FAILED: SKL1_TRANCOUNT_ZERO', 1;
PRINT 'TEST_PASS:SKL1_TRANCOUNT_ZERO';
PRINT 'TEST END: test_skills_lote1_cobertura';
GO
