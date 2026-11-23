USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Regresion P3 (2026-11-22): defectos D1 y D2 de la regresion del frontend (fixture de asignatura compartida de B2NM; todo en una transaccion revertida).
--   P3R_D1_01_ADMIN_PROGRAMAS_SOLO_VINCULADOS    usp_buscar_estudiantes_institucion_paginado: programas y facultades salen de EstudiantePrograma, no de todos los
--                                                programas de la asignatura compartida de sus grupos; totalGrupos sigue contando sus grupos
--   P3R_D1_02_ADMIN_SIN_VINCULO_SIN_PROGRAMAS    un estudiante matriculado en un grupo sin ningun EstudiantePrograma sigue en el listado, sin programas ni facultades
--   P3R_D1_03_ADMIN_FILTRO_FACULTAD_VINCULADA    el filtro idFacultad usa la facultad de sus programas vinculados
--   P3R_D1_04_DECANO_SOLO_VINCULADOS             el directorio del decano tampoco muestra programas ajenos (ya exigia el vinculo; la prueba lo fija)
--   P3R_D2_01_MENSAJE_ESTADO_CANCELADA           RPT_ASISTENCIA_ESTADO_CANCELADA existe (usuario y tecnico) con el texto CANCELADA
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_p3_regresion_2026_11_22';
DROP TABLE IF EXISTS #adm; DROP TABLE IF EXISTS #dec;
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @msg NVARCHAR(4000);
    DECLARE @nomA NVARCHAR(200) = (SELECT nombre FROM dbo.Programa WHERE id = @progA);
    DECLARE @nomFac NVARCHAR(200) = (SELECT nombre FROM dbo.Facultad WHERE id = @fac);
    CREATE TABLE #adm (idEstudiante UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, numeroIdentificacion INT, nombreCompleto NVARCHAR(400), correo NVARCHAR(320),
        estaActivoUsuario BIT, facultades NVARCHAR(MAX), programas NVARCHAR(MAX), totalGrupos INT, totalRegistros INT,
        primerNombre NVARCHAR(100), segundoNombre NVARCHAR(100), primerApellido NVARCHAR(100), segundoApellido NVARCHAR(100), tipoIdentificacion NVARCHAR(20));

    -- ------------------------------------------------------------------ P3R_D1_01
    -- eA solo esta vinculado al programa A; su grupo G es de una asignatura compartida por A y B (uv_estudiante lo expande a ambos programas).
    INSERT #adm EXEC dbo.usp_buscar_estudiantes_institucion_paginado @idUsuarioEjecutor = @uAdm, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @busqueda = N'1950000003', @idFacultad = NULL, @estaActivo = NULL;
    IF (SELECT COUNT(*) FROM #adm WHERE idEstudiante = @eA) <> 1
        THROW 55101, 'TEST FAILED: P3R_D1_01 el estudiante A debe aparecer una sola vez en el listado del administrador.', 1;
    IF NOT EXISTS (SELECT 1 FROM #adm WHERE idEstudiante = @eA AND programas = @nomA AND facultades = @nomFac AND totalGrupos = 1)
    BEGIN
        SET @msg = CONCAT(N'TEST FAILED: P3R_D1_01 programas debe ser solo "', @nomA, N'" (vinculado), no todos los de la asignatura compartida; obtenido: "',
                          (SELECT programas FROM #adm WHERE idEstudiante = @eA), N'" / facultades "', (SELECT facultades FROM #adm WHERE idEstudiante = @eA), N'".');
        THROW 55102, @msg, 1;
    END
    -- eB solo esta vinculado al programa B
    TRUNCATE TABLE #adm;
    INSERT #adm EXEC dbo.usp_buscar_estudiantes_institucion_paginado @idUsuarioEjecutor = @uAdm, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @busqueda = N'1950000004', @idFacultad = NULL, @estaActivo = NULL;
    IF NOT EXISTS (SELECT 1 FROM #adm WHERE idEstudiante = @eB AND programas = N'B2NM-Programa B' AND totalGrupos = 1)
        THROW 55103, 'TEST FAILED: P3R_D1_01 el estudiante B debe listar solo el programa B.', 1;
    PRINT 'TEST_PASS:P3R_D1_01_ADMIN_PROGRAMAS_SOLO_VINCULADOS';

    -- ------------------------------------------------------------------ P3R_D1_02
    TRUNCATE TABLE #adm;
    INSERT #adm EXEC dbo.usp_buscar_estudiantes_institucion_paginado @idUsuarioEjecutor = @uAdm, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @busqueda = N'1950000005', @idFacultad = NULL, @estaActivo = NULL;
    IF NOT EXISTS (SELECT 1 FROM #adm WHERE idEstudiante = @e0 AND programas IS NULL AND facultades IS NULL AND totalGrupos = 1)
        THROW 55111, 'TEST FAILED: P3R_D1_02 un estudiante sin EstudiantePrograma debe seguir en el listado, sin programas ni facultades.', 1;
    PRINT 'TEST_PASS:P3R_D1_02_ADMIN_SIN_VINCULO_SIN_PROGRAMAS';

    -- ------------------------------------------------------------------ P3R_D1_03
    TRUNCATE TABLE #adm;
    INSERT #adm EXEC dbo.usp_buscar_estudiantes_institucion_paginado @idUsuarioEjecutor = @uAdm, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @busqueda = N'19500000', @idFacultad = @fac, @estaActivo = NULL;
    IF NOT EXISTS (SELECT 1 FROM #adm WHERE idEstudiante = @eA) OR NOT EXISTS (SELECT 1 FROM #adm WHERE idEstudiante = @eB)
       OR EXISTS (SELECT 1 FROM #adm WHERE idEstudiante = @e0)
        THROW 55121, 'TEST FAILED: P3R_D1_03 con idFacultad solo deben salir los estudiantes vinculados a un programa de esa facultad (A y B; no el sin vinculo).', 1;
    PRINT 'TEST_PASS:P3R_D1_03_ADMIN_FILTRO_FACULTAD_VINCULADA';

    -- ------------------------------------------------------------------ P3R_D1_04
    CREATE TABLE #dec (idEstudiante UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, numeroIdentificacion INT, nombreCompleto NVARCHAR(400), correo NVARCHAR(320),
        estaActivoUsuario BIT, programas NVARCHAR(MAX), totalGrupos INT, totalRegistros INT, codigoTipoIdentificacion NVARCHAR(20));
    INSERT #dec EXEC dbo.usp_consultar_estudiantes_facultad_paginado @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 50,
        @busqueda = N'1950000003', @idPrograma = NULL, @estaActivo = NULL;
    IF NOT EXISTS (SELECT 1 FROM #dec WHERE idEstudiante = @eA AND programas = @nomA)
        THROW 55131, 'TEST FAILED: P3R_D1_04 el decano debe ver al estudiante A solo con el programa A.', 1;
    PRINT 'TEST_PASS:P3R_D1_04_DECANO_SOLO_VINCULADOS';

    -- ------------------------------------------------------------------ P3R_D2_01
    IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA' AND contenido = N'CANCELADA') <> 1
       OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'RPT_ASISTENCIA_ESTADO_CANCELADA') <> 1
        THROW 55141, 'TEST FAILED: P3R_D2_01 falta el mensaje RPT_ASISTENCIA_ESTADO_CANCELADA (usuario y tecnico).', 1;
    PRINT 'TEST_PASS:P3R_D2_01_MENSAJE_ESTADO_CANCELADA';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @fallo NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 55199, @fallo, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
PRINT 'TEST_PASS:P3R_TRANCOUNT_ZERO';
GO
