USE [gestionasistenciadb];
GO
-- CULM-001 B2NM (B2NM-04 parcial, 13, 14, 17): oferta del estudiante (G una vez por programa del estudiante, con caracter), oferta docente
-- (1 fila por asignatura), S2 (catalogo de una asignatura compartida), desvincular/reasociar y consultas del decano. Transaccion revertida.
-- Los rechazos por THROW (PLA_002) van al final: con XACT_ABORT ON invalidan la transaccion compartida.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_culm001_b2nm_oferta_y_decano';
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreProgB NVARCHAR(100) = N'B2NM-Programa B';

    -- B2NM-13: HU008, G aparece una vez en las propias de EA (carácter OPT) y de EB; E0 sin vinculo no la ve como propia
    DECLARE @o TABLE (n INT IDENTITY(1,1), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(50), idAsignatura UNIQUEIDENTIFIER,
        codigoAsignatura NVARCHAR(20), nombreAsignatura NVARCHAR(100), nombreDocente NVARCHAR(400), idPeriodoAcademico UNIQUEIDENTIFIER,
        nombrePeriodoAcademico NVARCHAR(50), fechaInicioPeriodo DATE, fechaFinPeriodo DATE, estadoPeriodo NVARCHAR(10), horario NVARCHAR(400),
        capacidadMaxima INT, estudiantesActivos INT, cuposDisponibles INT, matriculado BIT, codigoComponente NVARCHAR(3),
        codigoCaracter NVARCHAR(3), nombreCaracter NVARCHAR(50), totalRegistros INT);
    INSERT INTO @o (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, codigoAsignatura, nombreAsignatura, nombreDocente, idPeriodoAcademico,
        nombrePeriodoAcademico, fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, horario, capacidadMaxima, estudiantesActivos, cuposDisponibles,
        matriculado, codigoComponente, codigoCaracter, nombreCaracter, totalRegistros)
    EXEC dbo.usp_consultar_oferta_grupos_estudiante @busqueda = N'B2NM', @idCorrelacion = @c, @idUsuarioEjecutor = @uEA;
    IF (SELECT COUNT(*) FROM @o WHERE idGrupo = @grupoG) <> 1 OR NOT EXISTS (SELECT 1 FROM @o WHERE idGrupo = @grupoG AND codigoCaracter = N'OPT')
        THROW 53881, 'TEST FAILED: B2NM-13 G debe aparecer una vez en las propias de EA con caracter OPT.', 1;
    DELETE FROM @o;
    INSERT INTO @o (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, codigoAsignatura, nombreAsignatura, nombreDocente, idPeriodoAcademico,
        nombrePeriodoAcademico, fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, horario, capacidadMaxima, estudiantesActivos, cuposDisponibles,
        matriculado, codigoComponente, codigoCaracter, nombreCaracter, totalRegistros)
    EXEC dbo.usp_consultar_oferta_grupos_estudiante @busqueda = N'B2NM', @idCorrelacion = @c, @idUsuarioEjecutor = @uEB;
    IF (SELECT COUNT(*) FROM @o WHERE idGrupo = @grupoG) <> 1 THROW 53882, 'TEST FAILED: B2NM-13 G debe aparecer una vez en las propias de EB.', 1;
    DELETE FROM @o;
    INSERT INTO @o (idGrupo, codigoGrupo, nombreGrupo, idAsignatura, codigoAsignatura, nombreAsignatura, nombreDocente, idPeriodoAcademico,
        nombrePeriodoAcademico, fechaInicioPeriodo, fechaFinPeriodo, estadoPeriodo, horario, capacidadMaxima, estudiantesActivos, cuposDisponibles,
        matriculado, codigoComponente, codigoCaracter, nombreCaracter, totalRegistros)
    EXEC dbo.usp_consultar_oferta_grupos_estudiante @busqueda = N'B2NM', @idCorrelacion = @c, @idUsuarioEjecutor = @uE0;
    IF EXISTS (SELECT 1 FROM @o WHERE idGrupo = @grupoG) THROW 53883, 'TEST FAILED: B2NM-13 E0 sin vinculo no debe ver G como propia.', 1;

    -- B2NM-13: oferta docente, 1 fila por asignatura con los programas del docente
    DECLARE @od TABLE (idDocente UNIQUEIDENTIFIER, idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(50), nombreAsignatura NVARCHAR(200), programas NVARCHAR(1000));
    INSERT INTO @od EXEC dbo.usp_consultar_oferta_creacion_grupo_docente @idUsuarioEjecutor = @uT, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM @od WHERE idAsignatura = @asigOPT) <> 1 OR NOT EXISTS (SELECT 1 FROM @od WHERE idAsignatura = @asigOPT AND programas LIKE N'%B2NM-Programa B%')
        THROW 53884, 'TEST FAILED: B2NM-13 la oferta docente debe tener 1 fila por asignatura con ambos programas.', 1;

    -- B2NM-14: el decano ve G una vez en usp_consultar_grupos_facultad_paginado, con los programas agregados
    DECLARE @gf TABLE (idGrupo UNIQUEIDENTIFIER, codigo INT, nombre NVARCHAR(50), idPeriodoAcademico UNIQUEIDENTIFIER, idAsignatura UNIQUEIDENTIFIER,
        nombreAsignatura NVARCHAR(100), idDocente UNIQUEIDENTIFIER, capacidadMaximaPermitida INT, estudiantesActivos INT, cuposDisponibles INT,
        grupoEstaHablitado BIT, programas NVARCHAR(1000), totalRegistros INT);
    INSERT INTO @gf EXEC dbo.usp_consultar_grupos_facultad_paginado @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF (SELECT COUNT(*) FROM @gf WHERE idGrupo = @grupoG) <> 1 OR NOT EXISTS (SELECT 1 FROM @gf WHERE idGrupo = @grupoG AND programas LIKE N'%B2NM-Programa B%')
        THROW 53885, 'TEST FAILED: B2NM-14 el decano debe ver G una vez con sus programas.', 1;

    -- B2NM-17 (S2): CA no cambia el catalogo ni el estado global de OPT (compartida con B); si el semestre/caracter de su vinculo
    DECLARE @r TABLE (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT);
    INSERT INTO @r EXEC dbo.usp_actualizar_asignatura @idAsignatura = @asigOPT, @codigo = NULL, @nombre = N'B2NM Cambio', @creditos = NULL, @idPlanEstudio = @planA,
        @semestreNumero = NULL, @nombreArea = NULL, @nombreComponente = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA, @codigoCaracter = NULL;
    IF NOT EXISTS (SELECT 1 FROM @r WHERE estado = 0 AND mt LIKE N'%ASI_006%') THROW 53886, 'TEST FAILED: B2NM-17 CA no debe cambiar el nombre de una asignatura compartida (ASI_006).', 1;
    DELETE FROM @r;
    INSERT INTO @r EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @asigOPT, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM @r WHERE estado = 0 AND mt LIKE N'%ASI_006%') THROW 53887, 'TEST FAILED: B2NM-17 CA no debe cambiar el estado global de una asignatura compartida (ASI_006).', 1;
    DELETE FROM @r;
    INSERT INTO @r EXEC dbo.usp_actualizar_asignatura @idAsignatura = @asigOPT, @codigo = NULL, @nombre = NULL, @creditos = NULL, @idPlanEstudio = @planA,
        @semestreNumero = NULL, @nombreArea = NULL, @nombreComponente = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA, @codigoCaracter = N'OBL';
    IF NOT EXISTS (SELECT 1 FROM @r WHERE estado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio WHERE idAsignatura = @asigOPT AND idPlanEstudio = @planA AND codigoCaracter = N'OBL')
        THROW 53888, 'TEST FAILED: B2NM-17 CA debe poder cambiar el caracter de su vinculo.', 1;

    -- B2NM-04: EA (matricula activa cuyo unico programa comun con G es A) bloquea la baja: ASI_005; sin esa matricula la baja es logica,
    -- G conserva sus 2 programas (S1) y reasociar reactiva la misma fila
    DELETE FROM @r;
    INSERT INTO @r EXEC dbo.usp_desvincular_asignatura_plan @idAsignatura = @asigOPT, @idPlanEstudio = @planA, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM @r WHERE estado = 0 AND mt LIKE N'%ASI_005%') THROW 53893, 'TEST FAILED: B2NM-04 la matricula activa de EA debe dar ASI_005.', 1;
    UPDATE eg SET estado = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'I') FROM dbo.EstudianteGrupo eg WHERE eg.estudiante = @eA AND eg.grupo = @grupoG;
    DELETE FROM @r;
    INSERT INTO @r EXEC dbo.usp_desvincular_asignatura_plan @idAsignatura = @asigOPT, @idPlanEstudio = @planA, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM @r WHERE estado = 1) OR (SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio WHERE asignatura = @asigOPT AND semestrePlanEstudio = @speA AND estaActivo = 0) <> 1
        THROW 53889, 'TEST FAILED: B2NM-04 desvincular OPT de A debe ser una baja logica.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_grupo_programa WHERE idGrupo = @grupoG) <> 2 THROW 53890, 'TEST FAILED: B2NM-04 G conserva sus 2 programas tras desvincular en el periodo vigente (S1).', 1;
    DELETE FROM @r;
    INSERT INTO @r EXEC dbo.usp_asociar_asignatura_plan @idAsignatura = @asigOPT, @idPlanEstudio = @planA, @semestreNumero = 8, @codigoCaracter = N'OPT', @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM @r WHERE estado = 1) OR (SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio WHERE asignatura = @asigOPT AND semestrePlanEstudio = @speA) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio WHERE asignatura = @asigOPT AND semestrePlanEstudio = @speA AND estaActivo = 1)
        THROW 53891, 'TEST FAILED: B2NM-04 reasociar debe reactivar la misma fila.', 1;

    -- B2NM-14: malla de un plan inexistente -> PLA_002 (THROW; ultimo paso)
    DECLARE @pla002 BIT = 0, @planInexistente UNIQUEIDENTIFIER = NEWID();
    BEGIN TRY
        EXEC dbo.usp_consultar_asignaturas_plan_paginado @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @idPlanEstudio = @planInexistente, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE N'%PLA_002%' SET @pla002 = 1;
    END CATCH
    IF @pla002 = 0 THROW 53892, 'TEST FAILED: B2NM-14 un plan inexistente debe dar PLA_002.', 1;

    PRINT 'TEST_PASS:CULM001_B2NM_OFERTA_Y_DECANO';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 53899, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
