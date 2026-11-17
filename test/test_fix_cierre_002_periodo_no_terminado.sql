USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- FIX-CIERRE-002 (decision de producto 2026-11-17): el cierre masivo solo se ejecuta sobre un periodo que ya termino
-- (uv_periodo_academico.estado = CERRADO: fecha local institucional estrictamente posterior a fechaFin).
--   FIX002_CIE_01  periodo vigente (ACTIVO)  -> PER_007, sin cambiar matriculas, grupos ni AuditoriaEvento
--   FIX002_CIE_02  periodo en planeacion     -> PER_007, sin cambios
--   FIX002_CIE_03  el dia exacto de fechaFin cuenta como NO terminado (frontera) -> PER_007, sin cambios
--   FIX002_CIE_04  fechaFin ayer (terminado) -> sigue cerrando ese periodo (A -> F, contador, auditoria) y solo ese
--   FIX002_CIE_05  el rechazo no deja transaccion abierta
-- Todo corre en UNA transaccion con ROLLBACK final.
-- ============================================================================
PRINT 'TEST START: test_fix_cierre_002_periodo_no_terminado';
GO

DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_docente);
DECLARE @adminUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1);
DECLARE @active UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10)));
DECLARE @finished UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_FINALIZADA') AS NVARCHAR(10)));
IF @institution IS NULL OR @assignment IS NULL OR @teacher IS NULL OR @adminUser IS NULL OR @active IS NULL OR @finished IS NULL
    THROW 55001, 'TEST FAILED FIX002: faltan datos sembrados.', 1;

-- Misma fecha local institucional que usa uv_periodo_academico para su estado
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100)) AS DATE);

IF OBJECT_ID(N'tempdb..#fix2') IS NOT NULL DROP TABLE #fix2;
CREATE TABLE #fix2 (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);

DECLARE @periodos TABLE (orden INT, idPeriodo UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, idMatricula UNIQUEIDENTIFIER, codigo INT, fechaInicio DATE, fechaFin DATE, estadoEsperado VARCHAR(20));
INSERT @periodos VALUES
    (1, NEWID(), NEWID(), NEWID(), 600001, DATEADD(DAY, -30, @hoy), DATEADD(DAY, 30, @hoy), 'ACTIVO'),
    (2, NEWID(), NEWID(), NEWID(), 600002, DATEADD(DAY, 10, @hoy),  DATEADD(DAY, 90, @hoy), 'PLANEACION'),
    (3, NEWID(), NEWID(), NEWID(), 600003, DATEADD(DAY, -60, @hoy), @hoy,                    'ACTIVO'),
    (4, NEWID(), NEWID(), NEWID(), 600004, DATEADD(DAY, -60, @hoy), DATEADD(DAY, -1, @hoy), 'CERRADO');

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    SELECT idPeriodo, @institution, CONCAT(N'QA-FIX002-', orden), codigo, fechaInicio, fechaFin, YEAR(fechaInicio) FROM @periodos;
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT idGrupo, @assignment, idPeriodo, 610000 + orden, CONCAT(N'Grupo QA FIX002 ', orden), 30, 0, 0, 0, @teacher FROM @periodos;
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    SELECT p.idMatricula, @active, (SELECT TOP 1 id FROM dbo.Estudiante ORDER BY id), p.idGrupo FROM @periodos p;

    -- Precondicion: el estado de la vista coincide con el esperado (el SP reutiliza esa misma columna)
    IF EXISTS (SELECT 1 FROM @periodos p INNER JOIN dbo.uv_periodo_academico v ON v.id = p.idPeriodo WHERE v.estado <> p.estadoEsperado)
       OR (SELECT COUNT(*) FROM @periodos p INNER JOIN dbo.uv_periodo_academico v ON v.id = p.idPeriodo) <> 4
        THROW 55002, 'TEST FAILED FIX002: el estado de uv_periodo_academico no es el esperado para los periodos de prueba.', 1;

    DECLARE @orden INT = 1, @corr UNIQUEIDENTIFIER, @nombre NVARCHAR(50), @idP UNIQUEIDENTIFIER, @idG UNIQUEIDENTIFIER, @idM UNIQUEIDENTIFIER, @fin DATE;
    DECLARE @audAntes INT, @activasAntes INT, @ok BIT;

    -- FIX002_CIE_01..03: periodos no terminados (vigente, planeacion, dia exacto de fechaFin) -> PER_007 sin cambios
    WHILE @orden <= 3
    BEGIN
        SELECT @nombre = CONCAT(N'QA-FIX002-', orden), @idP = idPeriodo, @idG = idGrupo, @idM = idMatricula, @fin = fechaFin FROM @periodos WHERE orden = @orden;
        SELECT @audAntes = COUNT(*) FROM dbo.AuditoriaEvento WHERE action = N'CIERRE_MASIVO_PERIODO';
        SELECT @activasAntes = COUNT(*) FROM dbo.EstudianteGrupo WHERE estado = @active;
        SET @corr = NEWID();
        DELETE FROM #fix2;
        INSERT #fix2 EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @nombre, @idActor = N'QA_FIX002', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
        SET @ok = IIF((SELECT COUNT(*) FROM #fix2) = 1
                      AND EXISTS (SELECT 1 FROM #fix2 WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=PER_007|%'
                                  AND mensajeUsuarioResultado LIKE N'%' + CONVERT(NVARCHAR(10), @fin, 103) + N'%')
                      AND EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @idM AND estado = @active)
                      AND EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @idG AND cantidadEstudiantesFinalizaron = 0)
                      AND (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE estado = @active) = @activasAntes
                      AND (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE action = N'CIERRE_MASIVO_PERIODO') = @audAntes
                      AND @@TRANCOUNT = 1, 1, 0);
        IF @ok <> 1
            THROW 55011, 'TEST FAILED FIX002_CIE_01-03: un periodo que aun no termino (vigente, en planeacion o el dia de fechaFin) debe responder PER_007 con su fecha de fin, sin cerrar ni auditar nada.', 1;
        PRINT CONCAT('TEST_PASS:FIX002_CIE_0', @orden, CASE @orden WHEN 1 THEN '_VIGENTE' WHEN 2 THEN '_PLANEACION' ELSE '_DIA_FECHA_FIN' END);
        SET @orden += 1;
    END

    -- FIX002_CIE_04: periodo terminado (fechaFin = ayer) -> cierra ese periodo y solo ese
    SELECT @nombre = N'QA-FIX002-4', @idP = idPeriodo, @idG = idGrupo, @idM = idMatricula FROM @periodos WHERE orden = 4;
    SELECT @audAntes = COUNT(*) FROM dbo.AuditoriaEvento WHERE action = N'CIERRE_MASIVO_PERIODO';
    SET @corr = NEWID();
    DELETE FROM #fix2;
    INSERT #fix2 EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @nombre, @idActor = N'QA_FIX002', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #fix2 WHERE estadoResultado = 1)
                  AND EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE id = @idM AND estado = @finished)
                  AND EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @idG AND cantidadEstudiantesFinalizaron = 1)
                  AND (SELECT COUNT(*) FROM dbo.EstudianteGrupo e INNER JOIN @periodos p ON p.idMatricula = e.id WHERE p.orden < 4 AND e.estado = @active) = 3
                  AND (SELECT COUNT(*) FROM dbo.AuditoriaEvento WHERE action = N'CIERRE_MASIVO_PERIODO') = @audAntes + 1
                  AND EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corr AND action = N'CIERRE_MASIVO_PERIODO' AND resourceId = CONVERT(NVARCHAR(50), @idP)), 1, 0);
    IF @ok <> 1 THROW 55014, 'TEST FAILED FIX002_CIE_04: un periodo cuya fechaFin ya paso debe cerrarse (A -> F, contador y auditoria) sin tocar los demas periodos.', 1;
    PRINT 'TEST_PASS:FIX002_CIE_04_PERIODO_TERMINADO';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @fallo NVARCHAR(4000) = ERROR_MESSAGE();
    THROW 55099, @fallo, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

IF @@TRANCOUNT <> 0
    THROW 55090, 'TEST FAILED FIX002_TRANCOUNT: transaccion abierta.', 1;
PRINT 'TEST_PASS:FIX002_CIE_05_TRANCOUNT_ZERO';
GO
