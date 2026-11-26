USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 4 (plan por lotes 2026-11-25): decano, facultad, coordinador y programas.
-- Fija el comportamiento de los SP del lote que no tenian prueba directa (nucleos de facultad y programa, validadores y
-- resolvedores de ambito) antes de refactorizarlos. Los SP publicos del lote siguen cubiertos por sus pruebas de dominio.
-- Todo lo que escribe corre dentro de una transaccion revertida.
--   SKL4_N01_ESTRUCTURA            vista uv_decano_rol (id, idUsuario, estaActivoRolDecano) igual a dbo.Decano
--   SKL4_R01_VALIDAR_COORD_FACULTAD usp_validar_coordinador_de_facultad_interno: exito, nulos y otra facultad (GEN_001)
--   SKL4_R02_VALIDAR_PROGRAMA      usp_validar_programa_academico_interno: GEN_002, PROG_003, PROG_004, PROG_006, PROG_005 y exito
--   SKL4_R03_CREAR_COORDINADOR     usp_crear_coordinador_interno (GEN_004, facultad) y usp_crear_decano_interno (DEC_020)
--   SKL4_R04_PROGRAMA_NUCLEOS      insertar, actualizar y cambiar estado del programa (GEN_004, GEN_005, PROG_008 con facultad inactiva)
--   SKL4_R05_FACULTAD_NUCLEOS      usp_actualizar_facultad_interno (NULL conserva) y usp_cambiar_estado_facultad_interno
--   SKL4_R06_RESOLVER_COORDINADOR  usp_resolver_programa_coordinador_interno: VAL_001, programa unico, COO_003 y KPI_001
--   SKL4_R07_RESOLVER_DECANO_ADMIN usp_resolver_facultad_decano_interno (KPI_003, decano inactivo) y usp_resolver_institucion_administrador_interno (KPI_004)
--   SKL4_R08_PROGRAMA_EN_FACULTAD  usp_validar_programa_en_facultad_interno: exito y THROW GEN_001
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote4_caracterizacion';

-- ===================================================================== N01 (estructura; no escribe)
IF OBJECT_ID(N'dbo.uv_decano_rol', N'V') IS NULL
    THROW 55200, 'TEST FAILED: SKL4_N01_ESTRUCTURA falta la vista uv_decano_rol', 1;
IF EXISTS (SELECT d.id, d.usuario, d.estado FROM dbo.Decano d
           EXCEPT SELECT r.id, r.idUsuario, r.estaActivoRolDecano FROM dbo.uv_decano_rol r)
   OR (SELECT COUNT(*) FROM dbo.uv_decano_rol) <> (SELECT COUNT(*) FROM dbo.Decano)
    THROW 55201, 'TEST FAILED: SKL4_N01_ESTRUCTURA uv_decano_rol no coincide con dbo.Decano', 1;
PRINT 'TEST_PASS:SKL4_N01_ESTRUCTURA';
GO

DECLARE @idPrograma UNIQUEIDENTIFIER, @idFacultad UNIQUEIDENTIFIER, @idCoord UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER, @nombrePrograma NVARCHAR(100);
DECLARE @idTipo UNIQUEIDENTIFIER, @idModalidad UNIQUEIDENTIFIER, @idJornada UNIQUEIDENTIFIER;
SELECT TOP 1 @idPrograma = p.id, @idFacultad = p.idFacultad, @idCoord = p.idCoordinador, @uCoord = ci.idUsuario, @nombrePrograma = p.nombrePrograma,
             @idTipo = p.idTipoPrograma, @idModalidad = p.idModalidad, @idJornada = p.idJornada
FROM dbo.uv_programa p
INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE ci.estaActivoUsuario = 1 AND p.estaActivoPrograma = 1
ORDER BY p.id;
IF @idTipo IS NULL SET @idTipo = (SELECT TOP 1 id FROM dbo.uv_tipo_programa WHERE estaActivoTipoPrograma = 1 ORDER BY id);
DECLARE @uDecano UNIQUEIDENTIFIER, @idDecano UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER, @correoDecano NVARCHAR(100);
SELECT @uDecano = d.idUsuario, @idDecano = d.id, @idInstitucion = f.idInstitucion, @correoDecano = d.correo
FROM dbo.uv_facultad f INNER JOIN dbo.uv_decano_identidad d ON d.id = f.idDecano
WHERE f.id = @idFacultad;
DECLARE @uAdmin UNIQUEIDENTIFIER = (SELECT TOP 1 a.idUsuario FROM dbo.uv_administrador a WHERE a.idInstitucion = @idInstitucion ORDER BY a.id);
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
IF @idPrograma IS NULL OR @uDecano IS NULL OR @uAdmin IS NULL OR @idTipo IS NULL OR @tipoCC IS NULL
    THROW 55202, 'TEST FAILED: SKL4 faltan fixtures del seed (programa con coordinador, decano, administrador y tipo de programa).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER = NEWID(), @msg NVARCHAR(4000);
    DECLARE @trancount INT = @@TRANCOUNT, @err NVARCHAR(4000), @idOut UNIQUEIDENTIFIER;

    -- ================================================================= R01
    EXEC dbo.usp_validar_coordinador_de_facultad_interno @idCoordinador = @idCoord, @idFacultad = @idFacultad, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55210, 'TEST FAILED: SKL4_R01_VALIDAR_COORD_FACULTAD (exito)', 1;
    EXEC dbo.usp_validar_coordinador_de_facultad_interno @idCoordinador = NULL, @idFacultad = @idFacultad, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]001|%' THROW 55211, 'TEST FAILED: SKL4_R01_VALIDAR_COORD_FACULTAD (nulo)', 1;
    EXEC dbo.usp_validar_coordinador_de_facultad_interno @idCoordinador = @idCoord, @idFacultad = '5C4A0000-0000-0000-0000-0000000000D1', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]001|%' THROW 55212, 'TEST FAILED: SKL4_R01_VALIDAR_COORD_FACULTAD (otra facultad)', 1;
    PRINT 'TEST_PASS:SKL4_R01_VALIDAR_COORD_FACULTAD';

    -- ================================================================= R02
    EXEC dbo.usp_validar_programa_academico_interno @idPrograma = @idPrograma, @idFacultad = @idFacultad, @nombre = N'  ', @idTipoPrograma = @idTipo,
         @idCoordinador = @idCoord, @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]002|%' THROW 55220, 'TEST FAILED: SKL4_R02_VALIDAR_PROGRAMA (nombre vacio)', 1;
    EXEC dbo.usp_validar_programa_academico_interno @idPrograma = NULL, @idFacultad = @idFacultad, @nombre = @nombrePrograma, @idTipoPrograma = @idTipo,
         @idCoordinador = @idCoord, @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=PROG[_]003|%' THROW 55221, 'TEST FAILED: SKL4_R02_VALIDAR_PROGRAMA (nombre repetido)', 1;
    EXEC dbo.usp_validar_programa_academico_interno @idPrograma = @idPrograma, @idFacultad = @idFacultad, @nombre = @nombrePrograma,
         @idTipoPrograma = '5C4A0000-0000-0000-0000-0000000000D2', @idCoordinador = @idCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=PROG[_]004|%' THROW 55222, 'TEST FAILED: SKL4_R02_VALIDAR_PROGRAMA (tipo)', 1;
    EXEC dbo.usp_validar_programa_academico_interno @idPrograma = @idPrograma, @idFacultad = @idFacultad, @nombre = @nombrePrograma, @idTipoPrograma = @idTipo,
         @idCoordinador = @idCoord, @idModalidad = '5C4A0000-0000-0000-0000-0000000000D3', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=PROG[_]006|%' THROW 55223, 'TEST FAILED: SKL4_R02_VALIDAR_PROGRAMA (modalidad)', 1;
    EXEC dbo.usp_validar_programa_academico_interno @idPrograma = NULL, @idFacultad = @idFacultad, @nombre = N'Programa SKL4 Nuevo', @idTipoPrograma = @idTipo,
         @idCoordinador = @idCoord, @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=PROG[_]005|%' THROW 55224, 'TEST FAILED: SKL4_R02_VALIDAR_PROGRAMA (coordinador ocupado)', 1;
    EXEC dbo.usp_validar_programa_academico_interno @idPrograma = @idPrograma, @idFacultad = @idFacultad, @nombre = @nombrePrograma, @idTipoPrograma = @idTipo,
         @idCoordinador = @idCoord, @idModalidad = @idModalidad, @idJornada = @idJornada, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @@TRANCOUNT <> @trancount
    BEGIN
        SET @msg = CONCAT(N'TEST FAILED: SKL4_R02_VALIDAR_PROGRAMA (exito) ', @mt);
        THROW 55225, @msg, 1;
    END
    PRINT 'TEST_PASS:SKL4_R02_VALIDAR_PROGRAMA';

    -- ================================================================= R03
    DECLARE @idCoordNuevo UNIQUEIDENTIFIER = NULL;
    EXEC dbo.usp_crear_coordinador_interno @idCoordinador = @idCoordNuevo OUTPUT, @numeroIdentificacion = 955240001, @primerNombre = N'Carla',
         @segundoNombre = NULL, @primerApellido = N'Lote', @segundoApellido = N'Cuatro', @correo = N'skl4.coord@uco.edu.co',
         @password = N'HashBackend_QaSkl41234567890', @idFacultad = @idFacultad, @idTipoIdIdentificacion = NULL, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @idCoordNuevo IS NULL OR @mt NOT LIKE N'DBCODE=GEN[_]004|%'
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador_identidad WHERE id = @idCoordNuevo AND idFacultadCoordinador = @idFacultad AND correo = N'skl4.coord@uco.edu.co')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_usuario u WHERE u.correo = N'skl4.coord@uco.edu.co'
                      AND u.idTipoIdentificacion = (SELECT TOP 1 t.id FROM dbo.uv_tipo_identificacion t
                                                    WHERE t.tipoIdentificacion = dbo.ufn_obtener_parametro_texto(NULL, 'IDENTIDAD', 'TIPO_IDENTIFICACION_DEFECTO') ORDER BY t.id))
    BEGIN
        SET @msg = CONCAT(N'TEST FAILED: SKL4_R03_CREAR_COORDINADOR (coordinador) ', @mt);
        THROW 55230, @msg, 1;
    END
    -- Repetir con el mismo correo reutiliza el usuario y el rol
    SET @idOut = NULL;
    EXEC dbo.usp_crear_coordinador_interno @idCoordinador = @idOut OUTPUT, @numeroIdentificacion = 955240001, @primerNombre = N'Carla',
         @segundoNombre = NULL, @primerApellido = N'Lote', @segundoApellido = N'Cuatro', @correo = N'skl4.coord@uco.edu.co',
         @password = N'HashBackend_QaSkl41234567890', @idFacultad = @idFacultad, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @idOut <> @idCoordNuevo THROW 55231, 'TEST FAILED: SKL4_R03_CREAR_COORDINADOR (reutiliza el rol)', 1;
    SET @idOut = NULL;
    EXEC dbo.usp_crear_decano_interno @idDecano = @idOut OUTPUT, @numeroIdentificacion = 955240002, @primerNombre = N'Otro', @segundoNombre = NULL,
         @primerApellido = N'Decano', @segundoApellido = NULL, @correo = @correoDecano, @password = N'HashBackend_QaSkl41234567890',
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=DEC[_]020|%' THROW 55232, 'TEST FAILED: SKL4_R03_CREAR_COORDINADOR (decano ya activo)', 1;
    SET @idOut = NULL;
    EXEC dbo.usp_crear_decano_interno @idDecano = @idOut OUTPUT, @numeroIdentificacion = 955240003, @primerNombre = N'Dora', @segundoNombre = NULL,
         @primerApellido = N'Lote', @segundoApellido = NULL, @correo = N'skl4.decano@uco.edu.co', @password = N'HashBackend_QaSkl41234567890',
         @idTipoIdIdentificacion = @tipoCC, @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @idOut IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_decano_identidad WHERE id = @idOut AND correo = N'skl4.decano@uco.edu.co')
        THROW 55233, 'TEST FAILED: SKL4_R03_CREAR_COORDINADOR (decano nuevo sin facultad)', 1;
    PRINT 'TEST_PASS:SKL4_R03_CREAR_COORDINADOR';

    -- ================================================================= R04
    DECLARE @idProgNuevo UNIQUEIDENTIFIER = NEWID();
    EXEC dbo.usp_insertar_programa_academico_interno @idPrograma = @idProgNuevo, @idFacultad = @idFacultad, @nombre = N' Programa SKL4 ',
         @idTipoPrograma = @idTipo, @idCoordinador = @idCoordNuevo, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]004|%' OR @@TRANCOUNT <> @trancount
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @idProgNuevo AND nombrePrograma = N'Programa SKL4' AND idCoordinador = @idCoordNuevo AND estaActivoPrograma = 1)
        THROW 55240, 'TEST FAILED: SKL4_R04_PROGRAMA_NUCLEOS (insertar)', 1;
    EXEC dbo.usp_actualizar_programa_academico_interno @idPrograma = @idProgNuevo, @idFacultad = @idFacultad, @nombre = N'Programa SKL4 Editado',
         @idTipoPrograma = @idTipo, @idCoordinador = @idCoordNuevo, @idModalidad = @idModalidad, @idJornada = @idJornada, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]005|%'
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @idProgNuevo AND nombrePrograma = N'Programa SKL4 Editado')
        THROW 55241, 'TEST FAILED: SKL4_R04_PROGRAMA_NUCLEOS (actualizar)', 1;
    EXEC dbo.usp_actualizar_programa_academico_interno @idPrograma = @idProgNuevo, @idFacultad = @idFacultad, @nombre = @nombrePrograma,
         @idTipoPrograma = @idTipo, @idCoordinador = @idCoordNuevo, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=PROG[_]003|%' OR @@TRANCOUNT <> @trancount
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @idProgNuevo AND nombrePrograma = N'Programa SKL4 Editado')
        THROW 55242, 'TEST FAILED: SKL4_R04_PROGRAMA_NUCLEOS (actualizar rechazado)', 1;
    EXEC dbo.usp_cambiar_estado_programa_academico_interno @idPrograma = @idPrograma, @estaActivo = 0, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF (SELECT COUNT(*) FROM dbo.uv_grupo_programa gp WHERE gp.idPrograma = @idPrograma AND gp.grupoEstaHablitado = 1) > 0
       AND (@ok <> 0 OR @mt NOT LIKE N'DBCODE=PROG[_]007|%')
        THROW 55243, 'TEST FAILED: SKL4_R04_PROGRAMA_NUCLEOS (PROG_007 con grupos activos)', 1;
    EXEC dbo.usp_cambiar_estado_programa_academico_interno @idPrograma = @idProgNuevo, @estaActivo = 0, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]005|%' OR NOT EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @idProgNuevo AND estaActivoPrograma = 0)
        THROW 55244, 'TEST FAILED: SKL4_R04_PROGRAMA_NUCLEOS (inactivar)', 1;

    -- ================================================================= R05 (y PROG_008: reactivar un programa de una facultad inactiva)
    EXEC dbo.usp_cambiar_estado_facultad_interno @id = @idFacultad, @estaActiva = 0, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]005|%' OR NOT EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE id = @idFacultad AND estaActivaFacultad = 0)
        THROW 55250, 'TEST FAILED: SKL4_R05_FACULTAD_NUCLEOS (inactivar)', 1;
    EXEC dbo.usp_cambiar_estado_programa_academico_interno @idPrograma = @idProgNuevo, @estaActivo = 1, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=PROG[_]008|%' OR @@TRANCOUNT <> @trancount
        THROW 55245, 'TEST FAILED: SKL4_R04_PROGRAMA_NUCLEOS (PROG_008)', 1;
    PRINT 'TEST_PASS:SKL4_R04_PROGRAMA_NUCLEOS';
    EXEC dbo.usp_cambiar_estado_facultad_interno @id = @idFacultad, @estaActiva = 1, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    DECLARE @nombreFacultad NVARCHAR(150) = (SELECT nombreFacultad FROM dbo.uv_facultad WHERE id = @idFacultad);
    EXEC dbo.usp_actualizar_facultad_interno @id = @idFacultad, @nombre = N'Facultad SKL4', @idDecano = NULL, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]005|%'
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE id = @idFacultad AND nombreFacultad = N'Facultad SKL4' AND idDecano = @idDecano AND estaActivaFacultad = 1)
        THROW 55251, 'TEST FAILED: SKL4_R05_FACULTAD_NUCLEOS (actualizar)', 1;
    EXEC dbo.usp_actualizar_facultad_interno @id = @idFacultad, @nombre = @nombreFacultad, @idDecano = NULL, @idCorrelacion = NULL,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=CORR[_]001|%' OR NOT EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE id = @idFacultad AND nombreFacultad = N'Facultad SKL4')
        THROW 55252, 'TEST FAILED: SKL4_R05_FACULTAD_NUCLEOS (sin correlacion)', 1;
    PRINT 'TEST_PASS:SKL4_R05_FACULTAD_NUCLEOS';

    -- ================================================================= R06
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = NULL, @idCorrelacion = @corr, @validarUmbrales = 0, @idPrograma = @idOut OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'DBCODE=VAL[_]001|%' THROW 55260, 'TEST FAILED: SKL4_R06_RESOLVER_COORDINADOR (ejecutor nulo)', 1;
    SET @idOut = NULL;
    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr, @validarUmbrales = 0, @idPrograma = @idOut OUTPUT;
    IF @idOut IS NULL OR @idOut <> @idPrograma THROW 55261, 'TEST FAILED: SKL4_R06_RESOLVER_COORDINADOR (programa unico)', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr, @validarUmbrales = 0, @idPrograma = @idOut OUTPUT,
             @idProgramaSolicitado = @idProgNuevo;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'DBCODE=COO[_]003|%' THROW 55262, 'TEST FAILED: SKL4_R06_RESOLVER_COORDINADOR (programa ajeno)', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @uDecano, @idCorrelacion = @corr, @validarUmbrales = 0, @idPrograma = @idOut OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'DBCODE=KPI[_]001|%' OR @@TRANCOUNT <> @trancount
        THROW 55263, 'TEST FAILED: SKL4_R06_RESOLVER_COORDINADOR (sin programa)', 1;
    PRINT 'TEST_PASS:SKL4_R06_RESOLVER_COORDINADOR';

    -- ================================================================= R07
    SET @idOut = NULL;
    EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @uDecano, @idCorrelacion = @corr, @validarUmbrales = 0, @idFacultad = @idOut OUTPUT;
    IF @idOut IS NULL OR @idOut <> @idFacultad THROW 55270, 'TEST FAILED: SKL4_R07_RESOLVER_DECANO_ADMIN (decano)', 1;
    SET @idOut = NULL;
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @corr, @validarUmbrales = 0, @idInstitucion = @idOut OUTPUT;
    IF @idOut IS NULL OR @idOut <> @idInstitucion THROW 55271, 'TEST FAILED: SKL4_R07_RESOLVER_DECANO_ADMIN (administrador)', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @uDecano, @idCorrelacion = @corr, @validarUmbrales = 0, @idInstitucion = @idOut OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'DBCODE=KPI[_]004|%' THROW 55272, 'TEST FAILED: SKL4_R07_RESOLVER_DECANO_ADMIN (no administrador)', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = NULL, @idCorrelacion = @corr, @validarUmbrales = 0, @idFacultad = @idOut OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'DBCODE=VAL[_]001|%' THROW 55273, 'TEST FAILED: SKL4_R07_RESOLVER_DECANO_ADMIN (ejecutor nulo)', 1;
    -- Un rol de decano inactivo (Decano.estado = 0) no resuelve facultad aunque el usuario siga activo (KPI_003)
    UPDATE dbo.Decano SET estado = 0 WHERE id = @idDecano;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @uDecano, @idCorrelacion = @corr, @validarUmbrales = 0, @idFacultad = @idOut OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    UPDATE dbo.Decano SET estado = 1 WHERE id = @idDecano;
    IF @err IS NULL OR @err NOT LIKE N'DBCODE=KPI[_]003|%' OR @@TRANCOUNT <> @trancount
        THROW 55274, 'TEST FAILED: SKL4_R07_RESOLVER_DECANO_ADMIN (decano inactivo)', 1;
    PRINT 'TEST_PASS:SKL4_R07_RESOLVER_DECANO_ADMIN';

    -- ================================================================= R08
    EXEC dbo.usp_validar_programa_en_facultad_interno @idFacultad = @idFacultad, @idPrograma = @idPrograma;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_validar_programa_en_facultad_interno @idFacultad = '5C4A0000-0000-0000-0000-0000000000D4', @idPrograma = @idPrograma;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'DBCODE=GEN[_]001|%' THROW 55280, 'TEST FAILED: SKL4_R08_PROGRAMA_EN_FACULTAD', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_validar_programa_en_facultad_interno @idFacultad = @idFacultad, @idPrograma = NULL;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'DBCODE=GEN[_]001|%' OR @@TRANCOUNT <> @trancount
        THROW 55281, 'TEST FAILED: SKL4_R08_PROGRAMA_EN_FACULTAD (programa nulo)', 1;
    PRINT 'TEST_PASS:SKL4_R08_PROGRAMA_EN_FACULTAD';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
