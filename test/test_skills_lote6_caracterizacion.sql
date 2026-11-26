USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 6 (plan por lotes 2026-11-25): asignaturas y planes de estudio.
-- Fija el comportamiento de los internos del lote antes de refactorizarlos (usp_validar_gestion_asignatura_coordinador_interno
-- no tenia prueba directa). Los SP publicos del lote siguen cubiertos por sus pruebas de dominio. Todo lo que escribe corre dentro
-- de una transaccion revertida.
--   SKL6_R01_ASIGNATURA_ACTIVA     usp_validar_asignatura_activa_interno: activa (con y sin bloqueo), ASI_010 (con y sin bloqueo)
--                                  e inexistente (pasa; la existencia la valida el llamador)
--   SKL6_R02_GESTION_VALIDACIONES  usp_validar_gestion_asignatura_coordinador_interno: GEN_002, perfil, VAL_002 y PLA_002
--   SKL6_R03_GESTION_PLAN          con plan: exito, ASI_004 (vinculo inactivo) y SEC_002 (plan de otro programa)
--   SKL6_R04_GESTION_PROGRAMAS     sin plan: exito, SEC_002 (sin vinculo activo coordinado) y ASI_006 (exigir todos los programas)
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote6_caracterizacion';

DECLARE @idAsig UNIQUEIDENTIFIER, @idPlan UNIQUEIDENTIFIER, @idPrograma UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER, @idApe UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = v.idAsignatura, @idPlan = v.idPlanEstudio, @idPrograma = v.idPrograma, @uCoord = c.usuario, @idApe = v.idAsignaturaPlanEstudio
FROM dbo.uv_asignatura_plan_estudio v
INNER JOIN dbo.Programa p ON p.id = v.idPrograma
INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
WHERE v.estaActivoVinculo = 1 AND v.estaActivaAsignatura = 1
  AND EXISTS (SELECT 1 FROM dbo.uv_usuario_perfil up WHERE up.idUsuario = c.usuario AND up.codigoPerfil = 'CD')
ORDER BY v.idAsignatura;
DECLARE @uOtro UNIQUEIDENTIFIER = (SELECT TOP 1 u.id FROM dbo.uv_usuario u
    WHERE u.id <> @uCoord AND NOT EXISTS (SELECT 1 FROM dbo.Coordinador c WHERE c.usuario = u.id) ORDER BY u.id);
IF @idAsig IS NULL OR @uOtro IS NULL
    THROW 55600, 'TEST FAILED: SKL6 faltan fixtures del seed (asignatura con vinculo activo en un plan de un programa coordinado).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @inexistente UNIQUEIDENTIFIER = '5C6A0000-0000-0000-0000-0000000000E1';

    -- ================================================================= R01
    EXEC dbo.usp_validar_asignatura_activa_interno @idAsignatura = @idAsig, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55610, 'TEST FAILED: SKL6_R01_ASIGNATURA_ACTIVA (activa)', 1;
    EXEC dbo.usp_validar_asignatura_activa_interno @idAsignatura = @idAsig, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @bloquearFila = 1;
    IF @ok <> 1 OR @mt <> N'' THROW 55611, 'TEST FAILED: SKL6_R01_ASIGNATURA_ACTIVA (activa con bloqueo)', 1;
    EXEC dbo.usp_validar_asignatura_activa_interno @idAsignatura = @inexistente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55612, 'TEST FAILED: SKL6_R01_ASIGNATURA_ACTIVA (inexistente pasa)', 1;
    UPDATE dbo.Asignatura SET estado = 0 WHERE id = @idAsig;
    EXEC dbo.usp_validar_asignatura_activa_interno @idAsignatura = @idAsig, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=ASI[_]010|%' OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
        THROW 55613, 'TEST FAILED: SKL6_R01_ASIGNATURA_ACTIVA (ASI_010)', 1;
    EXEC dbo.usp_validar_asignatura_activa_interno @idAsignatura = @idAsig, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @bloquearFila = 1;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=ASI[_]010|%' THROW 55614, 'TEST FAILED: SKL6_R01_ASIGNATURA_ACTIVA (ASI_010 con bloqueo)', 1;
    UPDATE dbo.Asignatura SET estado = 1 WHERE id = @idAsig;
    PRINT 'TEST_PASS:SKL6_R01_ASIGNATURA_ACTIVA';

    -- ================================================================= R02
    EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno @idAsignatura = @idAsig, @idUsuarioEjecutor = NULL, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]002|%' OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
        THROW 55620, 'TEST FAILED: SKL6_R02_GESTION_VALIDACIONES (GEN_002)', 1;
    EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno @idAsignatura = @idAsig, @idUsuarioEjecutor = @uOtro, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=SEC[_]%' THROW 55621, 'TEST FAILED: SKL6_R02_GESTION_VALIDACIONES (perfil)', 1;
    EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno @idAsignatura = @inexistente, @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VAL[_]002|%' THROW 55622, 'TEST FAILED: SKL6_R02_GESTION_VALIDACIONES (VAL_002)', 1;
    EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno @idAsignatura = @idAsig, @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @idPlanEstudio = @inexistente;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=PLA[_]002|%' THROW 55623, 'TEST FAILED: SKL6_R02_GESTION_VALIDACIONES (PLA_002)', 1;
    PRINT 'TEST_PASS:SKL6_R02_GESTION_VALIDACIONES';

    -- Programa, plan y vinculo de otro coordinador (para SEC_002 con plan y ASI_006); se revierten al final
    DECLARE @idCoord2 UNIQUEIDENTIFIER = NEWID(), @idProg2 UNIQUEIDENTIFIER = NEWID(), @idPlan2 UNIQUEIDENTIFIER = NEWID(), @idSpe2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Coordinador (id, usuario, estado) VALUES (@idCoord2, @uOtro, 1);
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado, modalidad, jornada)
    SELECT @idProg2, p.facultad, p.tipoDePrograma, N'SKL6 programa de prueba', @idCoord2, 1, p.modalidad, p.jornada FROM dbo.Programa p WHERE p.id = @idPrograma;
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@idPlan2, @idProg2, 960001, 1);
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) SELECT TOP 1 @idSpe2, @idPlan2, s.id FROM dbo.Semestre s ORDER BY s.id;

    -- ================================================================= R03
    EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno @idAsignatura = @idAsig, @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @idPlanEstudio = @idPlan;
    IF @ok <> 1 OR @mt <> N'' THROW 55630, 'TEST FAILED: SKL6_R03_GESTION_PLAN (exito)', 1;
    EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno @idAsignatura = @idAsig, @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @idPlanEstudio = @idPlan2;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=SEC[_]002|%' THROW 55631, 'TEST FAILED: SKL6_R03_GESTION_PLAN (SEC_002 plan ajeno)', 1;
    UPDATE dbo.AsignaturaPlanEstudio SET estaActivo = 0, fechaDesvinculacionUtc = SYSUTCDATETIME() WHERE id = @idApe;
    EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno @idAsignatura = @idAsig, @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @idPlanEstudio = @idPlan;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=ASI[_]004|%' OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
        THROW 55632, 'TEST FAILED: SKL6_R03_GESTION_PLAN (ASI_004)', 1;
    PRINT 'TEST_PASS:SKL6_R03_GESTION_PLAN';

    -- ================================================================= R04 (el vinculo del plan propio sigue inactivo)
    EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno @idAsignatura = @idAsig, @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=SEC[_]002|%' THROW 55640, 'TEST FAILED: SKL6_R04_GESTION_PROGRAMAS (SEC_002 sin vinculo activo)', 1;
    UPDATE dbo.AsignaturaPlanEstudio SET estaActivo = 1, fechaDesvinculacionUtc = NULL WHERE id = @idApe;
    EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno @idAsignatura = @idAsig, @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @exigirTodosLosProgramas = 1;
    IF @ok <> 1 OR @mt <> N'' THROW 55641, 'TEST FAILED: SKL6_R04_GESTION_PROGRAMAS (exito, todos coordinados)', 1;
    INSERT INTO dbo.AsignaturaPlanEstudio (id, asignatura, semestrePlanEstudio, caracter)
    SELECT NEWID(), @idAsig, @idSpe2, ape.caracter FROM dbo.AsignaturaPlanEstudio ape WHERE ape.id = @idApe;
    EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno @idAsignatura = @idAsig, @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55642, 'TEST FAILED: SKL6_R04_GESTION_PROGRAMAS (exito, alguno coordinado)', 1;
    EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno @idAsignatura = @idAsig, @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @exigirTodosLosProgramas = 1;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=ASI[_]006|%' THROW 55643, 'TEST FAILED: SKL6_R04_GESTION_PROGRAMAS (ASI_006)', 1;
    PRINT 'TEST_PASS:SKL6_R04_GESTION_PROGRAMAS';

    IF @@TRANCOUNT <> 1 THROW 55690, 'TEST FAILED: SKL6 la transaccion de la prueba no quedo abierta', 1;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
