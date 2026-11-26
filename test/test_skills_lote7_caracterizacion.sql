USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 7 (plan por lotes 2026-11-25): estudiantes y matricula.
-- Fija el comportamiento de los internos del lote antes de refactorizarlos (varios no tenian prueba directa). Los SP publicos
-- del lote siguen cubiertos por sus pruebas de dominio. Todo lo que escribe corre dentro de una transaccion revertida.
--   SKL7_R01_ESTUDIANTE_EXISTE     usp_validar_estudiante_exista_por_id_interno: exito, EST_001, CORR_001 y USU_002
--   SKL7_R02_PROGRAMA_COMUN        usp_validar_programa_comun_estudiante_grupo_interno: exito, EST_006, EST_010 (con y sin
--                                  programa elegido) y estudiante sin vinculos (no se restringe)
--   SKL7_R03_VALIDAR_REGISTRO      usp_validar_registro_estudiante_en_grupo_interno: ERR_MATRICULA_DUPLICADA, EST_001 y exito
--   SKL7_R04_ESTUDIANTE_EN_PROGRAMA usp_validar_estudiante_en_programa_interno: exito, VAL_001 y GEN_001 (por THROW)
--   SKL7_R05_SINCRONIZAR_ESTUDIANTE usp_sincronizar_estudiante_interno: VAL_006 (ya es estudiante) y GEN_004 (alta)
--   SKL7_R06_REGISTRAR_EN_PROGRAMA usp_registrar_estudiante_en_programa_interno: EST_003 (ya vinculado), GEN_002 (no existe) y
--                                  GEN_004 (vinculo nuevo)
--   SKL7_R07_REACTIVAR_MATRICULA   usp_reactivar_matricula_retirada_interno: sin retirada (no escribe), ERR_CUPO_SUPERADO y
--                                  reactivacion de la misma fila
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote7_caracterizacion';

DECLARE @idEst UNIQUEIDENTIFIER, @uEst UNIQUEIDENTIFIER, @idGrupo UNIQUEIDENTIFIER, @idProg UNIQUEIDENTIFIER, @idEg UNIQUEIDENTIFIER;
SELECT TOP 1 @idEst = eg.estudiante, @uEst = e.usuario, @idGrupo = eg.grupo, @idProg = ep.programa, @idEg = eg.id
FROM dbo.EstudianteGrupo eg
INNER JOIN dbo.Estudiante e ON e.id = eg.estudiante
INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = eg.estudiante
WHERE EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(eg.grupo) pg WHERE pg.idPrograma = ep.programa)
  AND EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = e.usuario AND u.estado = 1)
ORDER BY eg.id;
DECLARE @uNoEst UNIQUEIDENTIFIER = (SELECT TOP 1 u.id FROM dbo.Usuario u
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Estudiante x WHERE x.usuario = u.id) ORDER BY u.id);
DECLARE @idOtroGrupo UNIQUEIDENTIFIER = (SELECT TOP 1 g.id FROM dbo.Grupo g
    WHERE NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo x WHERE x.grupo = g.id AND x.estudiante = @idEst) ORDER BY g.id);
IF @idEst IS NULL OR @uNoEst IS NULL
    THROW 55700, 'TEST FAILED: SKL7 faltan fixtures del seed (estudiante matriculado con vinculo al programa del grupo).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @r BIT, @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @inexistente UNIQUEIDENTIFIER = '5C7A0000-0000-0000-0000-0000000000E1';
    DECLARE @err NVARCHAR(4000);

    -- ================================================================= R01
    EXEC dbo.usp_validar_estudiante_exista_por_id_interno @idEstudiante = @idEst, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55710, 'TEST FAILED: SKL7_R01_ESTUDIANTE_EXISTE (exito)', 1;
    EXEC dbo.usp_validar_estudiante_exista_por_id_interno @idEstudiante = @inexistente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=EST[_]001|%' OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
        THROW 55711, 'TEST FAILED: SKL7_R01_ESTUDIANTE_EXISTE (EST_001)', 1;
    EXEC dbo.usp_validar_estudiante_exista_por_id_interno @idEstudiante = @idEst, @idCorrelacion = NULL,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=CORR[_]001|%' THROW 55712, 'TEST FAILED: SKL7_R01_ESTUDIANTE_EXISTE (CORR_001)', 1;
    UPDATE dbo.Usuario SET estado = 0 WHERE id = @uEst;
    EXEC dbo.usp_validar_estudiante_exista_por_id_interno @idEstudiante = @idEst, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=USU[_]002|%' THROW 55713, 'TEST FAILED: SKL7_R01_ESTUDIANTE_EXISTE (USU_002)', 1;
    UPDATE dbo.Usuario SET estado = 1 WHERE id = @uEst;
    PRINT 'TEST_PASS:SKL7_R01_ESTUDIANTE_EXISTE';

    -- ================================================================= R02
    EXEC dbo.usp_validar_programa_comun_estudiante_grupo_interno @idEstudiante = @idEst, @idGrupo = @idGrupo, @idProgramaElegido = @idProg,
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55720, 'TEST FAILED: SKL7_R02_PROGRAMA_COMUN (exito)', 1;
    EXEC dbo.usp_validar_programa_comun_estudiante_grupo_interno @idEstudiante = @idEst, @idGrupo = @idGrupo, @idProgramaElegido = @inexistente,
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=EST[_]006|%' OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
        THROW 55721, 'TEST FAILED: SKL7_R02_PROGRAMA_COMUN (EST_006)', 1;
    EXEC dbo.usp_validar_programa_comun_estudiante_grupo_interno @idEstudiante = @inexistente, @idGrupo = @idGrupo, @idProgramaElegido = NULL,
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 55722, 'TEST FAILED: SKL7_R02_PROGRAMA_COMUN (sin vinculos no restringe)', 1;
    -- vinculo solo con un programa nuevo ajeno al grupo: EST_010
    DECLARE @idProg2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado, modalidad, jornada)
    SELECT @idProg2, p.facultad, p.tipoDePrograma, N'SKL7 programa de prueba', p.coordinador, 1, p.modalidad, p.jornada FROM dbo.Programa p WHERE p.id = @idProg;
    DELETE FROM dbo.EstudiantePrograma WHERE estudiante = @idEst;
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @idEst, @idProg2);
    EXEC dbo.usp_validar_programa_comun_estudiante_grupo_interno @idEstudiante = @idEst, @idGrupo = @idGrupo, @idProgramaElegido = NULL,
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=EST[_]010|%' THROW 55723, 'TEST FAILED: SKL7_R02_PROGRAMA_COMUN (EST_010)', 1;
    DELETE FROM dbo.EstudiantePrograma WHERE estudiante = @idEst;
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @idEst, @idProg2);
    -- programa del grupo elegido pero el estudiante solo tiene el ajeno => EST_010 primero (regla 2 antes que 3)
    EXEC dbo.usp_validar_programa_comun_estudiante_grupo_interno @idEstudiante = @idEst, @idGrupo = @idGrupo, @idProgramaElegido = @idProg,
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=EST[_]010|%' THROW 55724, 'TEST FAILED: SKL7_R02_PROGRAMA_COMUN (EST_010 con programa elegido)', 1;
    PRINT 'TEST_PASS:SKL7_R02_PROGRAMA_COMUN';
    -- se restablece el vinculo original
    DELETE FROM dbo.EstudiantePrograma WHERE estudiante = @idEst;
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @idEst, @idProg);

    -- ================================================================= R03
    EXEC dbo.usp_validar_registro_estudiante_en_grupo_interno @idGrupo = @idGrupo, @idEstudiante = @idEst, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=ERR[_]MATRICULA[_]DUPLICADA|%' THROW 55730, 'TEST FAILED: SKL7_R03_VALIDAR_REGISTRO (duplicada)', 1;
    EXEC dbo.usp_validar_registro_estudiante_en_grupo_interno @idGrupo = @idGrupo, @idEstudiante = @inexistente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=EST[_]001|%' THROW 55731, 'TEST FAILED: SKL7_R03_VALIDAR_REGISTRO (EST_001)', 1;
    IF @idOtroGrupo IS NOT NULL
    BEGIN
        EXEC dbo.usp_validar_registro_estudiante_en_grupo_interno @idGrupo = @idOtroGrupo, @idEstudiante = @idEst, @idCorrelacion = @corr,
             @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
        IF @ok <> 1 OR @mt <> N'' THROW 55732, 'TEST FAILED: SKL7_R03_VALIDAR_REGISTRO (exito)', 1;
    END
    PRINT 'TEST_PASS:SKL7_R03_VALIDAR_REGISTRO';

    -- ================================================================= R04
    EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = @idEst, @idPrograma = @idProg;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = NULL, @idPrograma = @idProg;
    END TRY
    BEGIN CATCH
        SET @err = CONCAT(ERROR_NUMBER(), N'|', ERROR_MESSAGE());
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'51000|DBCODE=VAL[_]001|%' THROW 55740, 'TEST FAILED: SKL7_R04_ESTUDIANTE_EN_PROGRAMA (VAL_001)', 1;
    SET @err = NULL;
    BEGIN TRY
        EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = @idEst, @idPrograma = @inexistente;
    END TRY
    BEGIN CATCH
        SET @err = CONCAT(ERROR_NUMBER(), N'|', ERROR_MESSAGE());
    END CATCH
    IF @err IS NULL OR @err NOT LIKE N'51000|DBCODE=GEN[_]001|%' THROW 55741, 'TEST FAILED: SKL7_R04_ESTUDIANTE_EN_PROGRAMA (GEN_001)', 1;
    PRINT 'TEST_PASS:SKL7_R04_ESTUDIANTE_EN_PROGRAMA';

    -- ================================================================= R05
    EXEC dbo.usp_sincronizar_estudiante_interno @idUsuario = @uEst, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VAL[_]006|%' THROW 55750, 'TEST FAILED: SKL7_R05_SINCRONIZAR_ESTUDIANTE (VAL_006)', 1;
    EXEC dbo.usp_sincronizar_estudiante_interno @idUsuario = @uNoEst, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]004|%' OR NOT EXISTS (SELECT 1 FROM dbo.Estudiante WHERE usuario = @uNoEst)
        THROW 55751, 'TEST FAILED: SKL7_R05_SINCRONIZAR_ESTUDIANTE (GEN_004)', 1;
    PRINT 'TEST_PASS:SKL7_R05_SINCRONIZAR_ESTUDIANTE';

    -- ================================================================= R06
    EXEC dbo.usp_registrar_estudiante_en_programa_interno @idEstudiante = @idEst, @idPrograma = @idProg, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=EST[_]003|%' THROW 55760, 'TEST FAILED: SKL7_R06_REGISTRAR_EN_PROGRAMA (EST_003)', 1;
    EXEC dbo.usp_registrar_estudiante_en_programa_interno @idEstudiante = @inexistente, @idPrograma = @idProg, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]002|%' THROW 55761, 'TEST FAILED: SKL7_R06_REGISTRAR_EN_PROGRAMA (GEN_002)', 1;
    EXEC dbo.usp_registrar_estudiante_en_programa_interno @idEstudiante = @idEst, @idPrograma = @idProg2, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]004|%'
       OR NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @idEst AND programa = @idProg2)
        THROW 55762, 'TEST FAILED: SKL7_R06_REGISTRAR_EN_PROGRAMA (GEN_004)', 1;
    PRINT 'TEST_PASS:SKL7_R06_REGISTRAR_EN_PROGRAMA';

    -- ================================================================= R07
    EXEC dbo.usp_reactivar_matricula_retirada_interno @idEstudiante = @idEst, @idGrupo = @idGrupo, @idCorrelacion = @corr, @codigoEstadoDestino = N'A',
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @reactivada = @r OUTPUT;
    IF @ok <> 1 OR @r <> 0 OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr) OR @@TRANCOUNT <> 1
        THROW 55770, 'TEST FAILED: SKL7_R07_REACTIVAR_MATRICULA (sin retirada)', 1;
    UPDATE dbo.EstudianteGrupo SET estado = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'I') WHERE id = @idEg;
    DECLARE @cupoOriginal INT = (SELECT cantidadEstudiantes FROM dbo.Grupo WHERE id = @idGrupo);
    UPDATE dbo.Grupo SET cantidadEstudiantes = (SELECT COUNT(*) FROM dbo.EstudianteGrupo x INNER JOIN dbo.EstadoEstudianteGrupo s ON s.id = x.estado
                                                WHERE x.grupo = @idGrupo AND s.codigo = N'A') WHERE id = @idGrupo;
    EXEC dbo.usp_reactivar_matricula_retirada_interno @idEstudiante = @idEst, @idGrupo = @idGrupo, @idCorrelacion = @corr, @codigoEstadoDestino = N'A',
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @reactivada = @r OUTPUT;
    IF @ok <> 0 OR @r <> 0 OR @mt NOT LIKE N'DBCODE=ERR[_]CUPO[_]SUPERADO|%' OR @@TRANCOUNT <> 1
        THROW 55771, 'TEST FAILED: SKL7_R07_REACTIVAR_MATRICULA (ERR_CUPO_SUPERADO)', 1;
    UPDATE dbo.Grupo SET cantidadEstudiantes = @cupoOriginal + 1 WHERE id = @idGrupo;
    EXEC dbo.usp_reactivar_matricula_retirada_interno @idEstudiante = @idEst, @idGrupo = @idGrupo, @idCorrelacion = @corr, @codigoEstadoDestino = N'A',
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @reactivada = @r OUTPUT;
    IF @ok <> 1 OR @r <> 1 OR @@TRANCOUNT <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo x INNER JOIN dbo.EstadoEstudianteGrupo s ON s.id = x.estado WHERE x.id = @idEg AND s.codigo = N'A')
        THROW 55772, 'TEST FAILED: SKL7_R07_REACTIVAR_MATRICULA (reactivada)', 1;
    PRINT 'TEST_PASS:SKL7_R07_REACTIVAR_MATRICULA';

    IF @@TRANCOUNT <> 1 THROW 55790, 'TEST FAILED: SKL7 la transaccion de la prueba no quedo abierta', 1;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
