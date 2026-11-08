USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- CULM-001 D.9-a (CONTRACT D §11): hallazgos medios y bajos de BD.
--   D9-DEC-01  usp_crear_decano: persona que ya es decano activo -> DEC_020 sin escrituras (F-ADM-024)
--   D9-DEC-05  usp_crear_decano: @idTipoIdIdentificacion se guarda en el Usuario nuevo (F-ADM-011)
--   D9-DEC-02  usp_consultar_grupo_facultad_detalle: grupo de la facultad del decano -> 1 fila (F-DEC-003)
--   D9-DEC-03  usp_consultar_grupo_facultad_detalle: grupo inexistente o ajeno -> THROW SEC_002 (403) (F-DEC-003)
--   D9-DEC-04  usp_consultar_sesiones_facultad_paginado: @idGrupo filtra en el SP; grupo ajeno -> SEC_002 (F-DEC-014)
--   D9-NTF-01  usp_reintentar_notificacion_saliente: id inexistente -> NTF_020 (F-ADM-027)
--   D9-NTF-02  usp_consultar_plantilla_notificacion_activa con @validarExistencia = 1: tipo inexistente -> NTF_021 (F-ADM-027)
--   D9-MSG-01  mensajes DEC_020, NTF_020 y NTF_021 sembrados (usuario y tecnico)
--   D9-PER-01  usp_crear_periodo_academico devuelve idPeriodo (F-ADM-030)
--   D9-PER-02  usp_consultar_periodos_academicos_paginado: ADMINISTRADOR, esVigente, SEC_001 y PAG_001 (F-ADM-030)
--   D9-HOR-01  el grupo sembrado tiene franjas (Horario) coherentes con el dia de sus sesiones (F-EST-S06, F-DOC-021)
--   D9-TRX-01  usp_validar_acceso_reporte_grupo: grupo inexistente o fuera de ambito -> SEC_002 (F-TRX-021, excel)
--   D9-CRU-01  usp_validar_cruce_horario_estudiante_interno: solo cuentan matriculas MATRICULA/ESTADO_INSCRITA (R-8 de A)
--   D9-TRX-02/03  regresion: plan inexistente -> PLA_002 para coordinador y decano (B2NM)
-- Todo corre en UNA transaccion con ROLLBACK final; los casos que lanzan con XACT_ABORT ON van al final.
-- ============================================================================
IF OBJECT_ID('tempdb..#d9_expect') IS NOT NULL DROP PROCEDURE #d9_expect;
GO
CREATE PROCEDURE #d9_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: CULM001_D9_', @label);
        THROW 52900, @mensaje, 1;
    END
END;
GO

DECLARE @uAdmin UNIQUEIDENTIFIER, @inst UNIQUEIDENTIFIER, @uDecano UNIQUEIDENTIFIER, @facultad UNIQUEIDENTIFIER;
DECLARE @docDecano INT, @correoDecano NVARCHAR(255), @uDocente UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER;
SELECT TOP 1 @uAdmin = a.usuario, @inst = a.institucion FROM dbo.Administrador a ORDER BY a.id;
SELECT TOP 1 @uDecano = d.usuario, @facultad = f.id, @docDecano = u.numeroIdentificacion, @correoDecano = u.correo
FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano INNER JOIN dbo.Usuario u ON u.id = d.usuario
WHERE f.institucion = @inst AND d.estado = 1 ORDER BY f.id;
DECLARE @grupo UNIQUEIDENTIFIER = CAST('A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D' AS UNIQUEIDENTIFIER);
DECLARE @grupo2 UNIQUEIDENTIFIER = CAST('A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C23' AS UNIQUEIDENTIFIER);
SELECT TOP 1 @uDocente = dc.usuario FROM dbo.Grupo g INNER JOIN dbo.Docente dc ON dc.id = g.docente WHERE g.id = @grupo;
SELECT TOP 1 @uCoord = c.usuario FROM dbo.Programa p INNER JOIN dbo.Coordinador c ON c.id = p.coordinador ORDER BY p.id;
IF @uAdmin IS NULL OR @uDecano IS NULL OR @uDocente IS NULL OR @uCoord IS NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupo) OR NOT EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @grupo2)
    THROW 52901, 'TEST FAILED: CULM001_D9 faltan fixtures del seed (administrador, decano, docente, coordinador o grupos).', 1;

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @tipoCE UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CE');
DECLARE @hash NVARCHAR(500) = N'HashBackend_QaD9Hallazgos1234567890';
DECLARE @corr UNIQUEIDENTIFIER, @n INT, @ok BIT, @err NVARCHAR(4000), @idAjeno UNIQUEIDENTIFIER = NEWID();
DECLARE @uAjeno UNIQUEIDENTIFIER = NEWID(), @decAjeno UNIQUEIDENTIFIER = NEWID(), @facAjena UNIQUEIDENTIFIER = NEWID();

CREATE TABLE #c (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
CREATE TABLE #p (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT, idPeriodo UNIQUEIDENTIFIER);
CREATE TABLE #gd (idGrupo UNIQUEIDENTIFIER, codigo INT, nombre NVARCHAR(300), idPeriodoAcademico UNIQUEIDENTIFIER, idAsignatura UNIQUEIDENTIFIER,
                  nombreAsignatura NVARCHAR(300), idDocente UNIQUEIDENTIFIER, capacidadMaximaPermitida INT, estudiantesActivos INT,
                  cuposDisponibles INT, grupoEstaHablitado BIT, programas NVARCHAR(1000));
CREATE TABLE #sf (id UNIQUEIDENTIFIER, nombre NVARCHAR(300), codigo NVARCHAR(50), numeroSemana INT, fechaHoraInicio DATETIME2, fechaHoraFin DATETIME2,
                  idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(300), idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(300),
                  totalRegistros INT, estaCancelada BIT, codigoTipoCancelacion NVARCHAR(50), motivoCancelacion NVARCHAR(500),
                  nombreDiaFestivo NVARCHAR(200), fechaCancelacionUtc DATETIME2);
CREATE TABLE #pl (id UNIQUEIDENTIFIER, idInstitucion UNIQUEIDENTIFIER, nombreInstitucion NVARCHAR(300), nombre NVARCHAR(100), codigo INT,
                  fechaInicio DATE, fechaFin DATE, anio INT, esVigente BIT, totalRegistros INT);

BEGIN TRANSACTION;
BEGIN TRY
    -- Facultad ajena: decano nuevo de una facultad sin grupos (para los casos fuera de ambito)
    INSERT dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uAjeno, @tipoCC, 916900001, N'Ajeno', N'Qa', N'Decano', N'D9', N'decano.ajeno.qa.d9@test.local', 1, 1, @hash);
    INSERT dbo.Decano (id, usuario) VALUES (@decAjeno, @uAjeno);
    INSERT dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@facAjena, N'QA D9 Facultad ajena', @inst, @decAjeno, 1);

    -- ---------------------------------------------------------------- D9-MSG-01 mensajes sembrados
    SET @ok = IIF((SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('DEC_020', 'NTF_020', 'NTF_021')) = 3
              AND (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('DEC_020', 'NTF_020', 'NTF_021')) = 3, 1, 0);
    EXEC #d9_expect 'D9_MSG_01_MENSAJES', @ok;
    PRINT 'TEST_PASS:CULM001_D9_MSG_01';

    -- ---------------------------------------------------------------- D9-DEC-01 decano activo repetido -> DEC_020
    SELECT @n = COUNT(*) FROM dbo.Decano;
    SET @corr = NEWID();
    DELETE FROM #c;
    BEGIN TRY
        INSERT #c EXEC dbo.usp_crear_decano @idDecano = NULL, @numeroIdentificacion = @docDecano, @primerNombre = N'Repetido', @segundoNombre = N'',
            @primerApellido = N'Decano', @segundoApellido = N'', @correo = @correoDecano, @idFacultad = NULL, @nombreFacultad = NULL,
            @password = @hash, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=DEC_020|%')
                  AND (SELECT COUNT(*) FROM dbo.Decano) = @n, 1, 0);
    EXEC #d9_expect 'D9_DEC_01_DECANO_ACTIVO_REPETIDO', @ok;
    PRINT 'TEST_PASS:CULM001_D9_DEC_01';

    -- ---------------------------------------------------------------- D9-DEC-05 el tipo de documento se guarda
    SET @corr = NEWID();
    DELETE FROM #c;
    INSERT #c EXEC dbo.usp_crear_decano @idDecano = NULL, @numeroIdentificacion = 916900077, @primerNombre = N'Nuevo', @segundoNombre = N'',
        @primerApellido = N'Decano', @segundoApellido = N'D9', @correo = N'decano.nuevo.qa.d9@test.local', @idFacultad = NULL, @nombreFacultad = NULL,
        @password = @hash, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin, @idTipoIdIdentificacion = @tipoCE;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 1)
                  AND EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = N'decano.nuevo.qa.d9@test.local' AND tipoIdIdentificacion = @tipoCE), 1, 0);
    EXEC #d9_expect 'D9_DEC_05_TIPO_DOCUMENTO', @ok;
    PRINT 'TEST_PASS:CULM001_D9_DEC_05';

    -- ---------------------------------------------------------------- D9-DEC-02 detalle del grupo de la facultad
    SET @corr = NEWID();
    DELETE FROM #gd;
    INSERT #gd EXEC dbo.usp_consultar_grupo_facultad_detalle @idUsuarioEjecutor = @uDecano, @idCorrelacion = @corr, @idGrupo = @grupo;
    SET @ok = IIF((SELECT COUNT(*) FROM #gd) = 1 AND EXISTS (SELECT 1 FROM #gd WHERE idGrupo = @grupo AND programas IS NOT NULL AND nombreAsignatura IS NOT NULL), 1, 0);
    EXEC #d9_expect 'D9_DEC_02_DETALLE_GRUPO', @ok;
    PRINT 'TEST_PASS:CULM001_D9_DEC_02';

    -- ---------------------------------------------------------------- D9-DEC-03 inexistente o ajeno -> SEC_002
    SET @err = NULL;
    BEGIN TRY
        INSERT #gd EXEC dbo.usp_consultar_grupo_facultad_detalle @idUsuarioEjecutor = @uDecano, @idCorrelacion = @corr, @idGrupo = @idAjeno;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    SET @ok = IIF(@err LIKE N'DBCODE=SEC_002|%', 1, 0);
    EXEC #d9_expect 'D9_DEC_03_INEXISTENTE', @ok;
    SET @err = NULL;
    BEGIN TRY
        INSERT #gd EXEC dbo.usp_consultar_grupo_facultad_detalle @idUsuarioEjecutor = @uAjeno, @idCorrelacion = @corr, @idGrupo = @grupo;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    SET @ok = IIF(@err LIKE N'DBCODE=SEC_002|%', 1, 0);
    EXEC #d9_expect 'D9_DEC_03_AJENO', @ok;
    PRINT 'TEST_PASS:CULM001_D9_DEC_03';

    -- ---------------------------------------------------------------- D9-DEC-04 sesiones por grupo en el SP
    SET @corr = NEWID();
    DELETE FROM #sf;
    INSERT #sf EXEC dbo.usp_consultar_sesiones_facultad_paginado @idUsuarioEjecutor = @uDecano, @idCorrelacion = @corr,
        @numeroPagina = 1, @tamanoPagina = 50, @idGrupo = @grupo;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #sf) AND NOT EXISTS (SELECT 1 FROM #sf WHERE idGrupo <> @grupo), 1, 0);
    EXEC #d9_expect 'D9_DEC_04_FILTRA_GRUPO', @ok;
    SET @err = NULL;
    BEGIN TRY
        INSERT #sf EXEC dbo.usp_consultar_sesiones_facultad_paginado @idUsuarioEjecutor = @uDecano, @idCorrelacion = @corr,
            @numeroPagina = 1, @tamanoPagina = 50, @idGrupo = @idAjeno;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    SET @ok = IIF(@err LIKE N'DBCODE=SEC_002|%', 1, 0);
    EXEC #d9_expect 'D9_DEC_04_GRUPO_AJENO', @ok;
    PRINT 'TEST_PASS:CULM001_D9_DEC_04';

    -- ---------------------------------------------------------------- D9-NTF-01 reintento de una notificacion inexistente
    SET @corr = NEWID();
    DELETE FROM #c;
    INSERT #c EXEC dbo.usp_reintentar_notificacion_saliente @id = @idAjeno, @idNotificacion = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_020|%'), 1, 0);
    EXEC #d9_expect 'D9_NTF_01_REINTENTO_INEXISTENTE', @ok;
    PRINT 'TEST_PASS:CULM001_D9_NTF_01';

    -- ---------------------------------------------------------------- D9-NTF-02 tipo de plantilla inexistente
    SET @corr = NEWID();
    DELETE FROM #c;
    INSERT #c EXEC dbo.usp_consultar_plantilla_notificacion_activa @tipo = N'XX', @idioma = 'es', @idCorrelacion = @corr, @validarExistencia = 1;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=NTF_021|%'), 1, 0);
    EXEC #d9_expect 'D9_NTF_02_TIPO_INEXISTENTE', @ok;
    -- (con un tipo existente el SP devuelve ademas los resultsets de plantilla y marcadores: no cabe en INSERT ... EXEC de 4 columnas;
    -- ese camino lo cubre IT/AdministracionNotificacionJpaAdapter y la comprobacion manual del reporte.)
    PRINT 'TEST_PASS:CULM001_D9_NTF_02';

    -- ---------------------------------------------------------------- D9-PER-01 crear periodo devuelve el id
    DECLARE @idPeriodo UNIQUEIDENTIFIER = NEWID();
    SET @corr = NEWID();
    DELETE FROM #p;
    INSERT #p EXEC dbo.usp_crear_periodo_academico @idPeriodo = @idPeriodo, @nombre = N'QA-D9-2099-1', @fechaInicio = '2099-01-10', @fechaFin = '2099-06-10',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #p WHERE estadoResultado = 1 AND idPeriodo = @idPeriodo)
                  AND EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @idPeriodo), 1, 0);
    EXEC #d9_expect 'D9_PER_01_CREAR_DEVUELVE_ID', @ok;
    PRINT 'TEST_PASS:CULM001_D9_PER_01';

    -- ---------------------------------------------------------------- D9-PER-02 consulta del administrador con esVigente
    SET @corr = NEWID();
    DELETE FROM #pl;
    INSERT #pl EXEC dbo.usp_consultar_periodos_academicos_paginado @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50;
    DECLARE @hoy DATE = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100)) AS DATE);
    SET @ok = IIF(EXISTS (SELECT 1 FROM #pl WHERE id = @idPeriodo AND esVigente = 0)
                  AND NOT EXISTS (SELECT 1 FROM #pl p WHERE p.esVigente <> IIF(p.fechaInicio <= @hoy AND p.fechaFin >= @hoy, 1, 0))
                  AND NOT EXISTS (SELECT 1 FROM #pl WHERE totalRegistros < 2), 1, 0);
    EXEC #d9_expect 'D9_PER_02_ADMIN_ESVIGENTE', @ok;
    SET @err = NULL;
    BEGIN TRY
        INSERT #pl EXEC dbo.usp_consultar_periodos_academicos_paginado @idUsuarioEjecutor = @uDocente, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 50;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    SET @ok = IIF(@err LIKE N'DBCODE=SEC_001|%', 1, 0);
    EXEC #d9_expect 'D9_PER_02_DOCENTE_SEC_001', @ok;
    SET @err = NULL;
    BEGIN TRY
        INSERT #pl EXEC dbo.usp_consultar_periodos_academicos_paginado @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 100000;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    SET @ok = IIF(@err LIKE N'DBCODE=PAG_001|%', 1, 0);
    EXEC #d9_expect 'D9_PER_02_PAG_001', @ok;
    PRINT 'TEST_PASS:CULM001_D9_PER_02';

    -- ---------------------------------------------------------------- D9-HOR-01 franjas coherentes con las sesiones del grupo sembrado
    -- Dia de la semana local de cada sesion (1900-01-01 es lunes: 0 = LU .. 6 = DO) y su franja local.
    DECLARE @zona NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100));
    SET @ok = IIF(EXISTS (SELECT 1 FROM dbo.Horario h WHERE h.grupo = @grupo)
                  AND NOT EXISTS (
                      SELECT 1 FROM dbo.Sesion s
                      WHERE s.grupo = @grupo
                        AND NOT EXISTS (
                            SELECT 1 FROM dbo.Horario h INNER JOIN dbo.Dia d ON d.id = h.dia
                            WHERE h.grupo = s.grupo
                              AND d.codigo = CHOOSE(DATEDIFF(DAY, '1900-01-01', CAST(CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATETIME2) AS DATE)) % 7 + 1,
                                                    'LU', 'MA', 'MI', 'JU', 'VI', 'SA', 'DO')
                              AND h.horaInicio = CAST(CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATETIME2) AS TIME(0))
                              AND h.horaFin = CAST(CAST((s.fechaHoraFin AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATETIME2) AS TIME(0)))), 1, 0);
    EXEC #d9_expect 'D9_HOR_01_FRANJAS_COHERENTES', @ok;
    PRINT 'TEST_PASS:CULM001_D9_HOR_01';

    -- ---------------------------------------------------------------- D9-TRX-01 acceso al reporte del grupo
    SET @corr = NEWID();
    DELETE FROM #c;
    INSERT #c EXEC dbo.usp_validar_acceso_reporte_grupo @idUsuarioEjecutor = @uDocente, @idCorrelacion = @corr, @idGrupo = @grupo;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 1), 1, 0);
    EXEC #d9_expect 'D9_TRX_01_DOCENTE_TITULAR', @ok;
    DELETE FROM #c;
    INSERT #c EXEC dbo.usp_validar_acceso_reporte_grupo @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr, @idGrupo = @grupo;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 1), 1, 0);
    EXEC #d9_expect 'D9_TRX_01_ADMINISTRADOR', @ok;
    DELETE FROM #c;
    INSERT #c EXEC dbo.usp_validar_acceso_reporte_grupo @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr, @idGrupo = @idAjeno;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_002|%'), 1, 0);
    EXEC #d9_expect 'D9_TRX_01_INEXISTENTE_403', @ok;
    DELETE FROM #c;
    INSERT #c EXEC dbo.usp_validar_acceso_reporte_grupo @idUsuarioEjecutor = @uAjeno, @idCorrelacion = @corr, @idGrupo = @grupo;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #c WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_002|%'), 1, 0);
    EXEC #d9_expect 'D9_TRX_01_FUERA_DE_AMBITO_403', @ok;
    PRINT 'TEST_PASS:CULM001_D9_TRX_01';

    -- ---------------------------------------------------------------- D9-CRU-01 el cruce solo cuenta matriculas inscritas
    -- Estudiante con matricula A en el grupo 1 e I (inactiva) en el grupo 2; ambos grupos con la misma franja de domingo.
    DECLARE @dia UNIQUEIDENTIFIER = (SELECT id FROM dbo.Dia WHERE codigo = 'DO');
    DECLARE @est UNIQUEIDENTIFIER = (SELECT eg1.estudiante FROM dbo.EstudianteGrupo eg1
                                     INNER JOIN dbo.EstadoEstudianteGrupo e1 ON e1.id = eg1.estado AND e1.codigo = 'A'
                                     INNER JOIN dbo.EstudianteGrupo eg2 ON eg2.estudiante = eg1.estudiante AND eg2.grupo = @grupo2
                                     INNER JOIN dbo.EstadoEstudianteGrupo e2 ON e2.id = eg2.estado AND e2.codigo = 'I'
                                     WHERE eg1.grupo = @grupo);
    IF @est IS NULL OR @dia IS NULL THROW 52902, 'TEST FAILED: CULM001_D9_CRU_01 falta el estudiante con matricula A e I o el dia DO.', 1;
    INSERT dbo.Horario (id, grupo, dia, horaInicio, horaFin) VALUES (NEWID(), @grupo, @dia, '08:00', '10:00'), (NEWID(), @grupo2, @dia, '08:00', '10:00');
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @est1 BIT;
    SET @corr = NEWID();
    EXEC dbo.usp_validar_cruce_horario_estudiante_interno @idEstudiante = @est, @idGrupo = @grupo, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @est1 OUTPUT;
    SET @ok = IIF(@est1 = 1, 1, 0);   -- la matricula inactiva del grupo 2 no cuenta
    EXEC #d9_expect 'D9_CRU_01_INACTIVA_NO_CUENTA', @ok;
    EXEC dbo.usp_validar_cruce_horario_estudiante_interno @idEstudiante = @est, @idGrupo = @grupo2, @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @est1 OUTPUT;
    SET @ok = IIF(@est1 = 0 AND @mt LIKE N'DBCODE=HOR_001|%', 1, 0);   -- la matricula activa del grupo 1 si cruza
    EXEC #d9_expect 'D9_CRU_01_ACTIVA_CUENTA', @ok;
    PRINT 'TEST_PASS:CULM001_D9_CRU_01';

    -- ---------------------------------------------------------------- D9-TRX-02/03 regresion: plan inexistente -> PLA_002
    -- (estos SP usan XACT_ABORT ON: van al final porque la transaccion queda no confirmable)
    SET @err = NULL;
    BEGIN TRY
        INSERT #c EXEC dbo.usp_consultar_asignaturas_plan_paginado @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr, @idPlanEstudio = @idAjeno, @numeroPagina = 1, @tamanoPagina = 20;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    SET @ok = IIF(@err LIKE N'DBCODE=PLA_002|%', 1, 0);
    EXEC #d9_expect 'D9_TRX_02_COORDINADOR_PLA_002', @ok;
    PRINT 'TEST_PASS:CULM001_D9_TRX_02';
    SET @err = NULL;
    BEGIN TRY
        INSERT #c EXEC dbo.usp_consultar_asignaturas_plan_paginado @idUsuarioEjecutor = @uDecano, @idCorrelacion = @corr, @idPlanEstudio = @idAjeno, @numeroPagina = 1, @tamanoPagina = 20;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    SET @ok = IIF(@err LIKE N'DBCODE=PLA_002|%', 1, 0);
    EXEC #d9_expect 'D9_TRX_03_DECANO_PLA_002', @ok;
    PRINT 'TEST_PASS:CULM001_D9_TRX_03';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @fallo NVARCHAR(4000) = ERROR_MESSAGE();
    THROW 52999, @fallo, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
