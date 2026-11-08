USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- CULM-001 C.1 (CONTRACT §2.13.1 C-DB-45, C-DB-61, O-11): audiencias del SSE de grupo por ambito (una sola definicion del ambito)
-- y permisos de los objetos publicos de C. Transaccion revertida.
PRINT 'TEST START: test_culm001_c_realtime_audiencias';
GO
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_c_fixture.sql
    IF OBJECT_ID(N'tempdb..#c1a') IS NOT NULL DROP TABLE #c1a;
    CREATE TABLE #c1a (esDocenteTitular BIT, esEstudianteActivo BIT, esAmbitoLectura BIT);
    DECLARE @uCoordAjeno UNIQUEIDENTIFIER = (SELECT TOP 1 c.usuario FROM dbo.Programa p JOIN dbo.Coordinador c ON c.id = p.coordinador WHERE p.id NOT IN (@progA, @progB) ORDER BY p.id);
    DECLARE @uAdmAjeno UNIQUEIDENTIFIER = (SELECT TOP 1 usuario FROM dbo.Administrador WHERE institucion <> @inst);

    DELETE FROM #c1a; INSERT INTO #c1a EXEC dbo.usp_consultar_audiencias_realtime_grupo @idUsuarioEjecutor = @uT, @idCorrelacion = @c, @idGrupo = @grupoG;
    IF NOT EXISTS (SELECT 1 FROM #c1a WHERE esDocenteTitular = 1 AND esEstudianteActivo = 0) THROW 58400, 'TEST FAILED: C-DB-45 el titular es DOCENTE_TITULAR.', 1;
    DELETE FROM #c1a; INSERT INTO #c1a EXEC dbo.usp_consultar_audiencias_realtime_grupo @idUsuarioEjecutor = @uEA, @idCorrelacion = @c, @idGrupo = @grupoG;
    IF NOT EXISTS (SELECT 1 FROM #c1a WHERE esDocenteTitular = 0 AND esEstudianteActivo = 1 AND esAmbitoLectura = 0) THROW 58401, 'TEST FAILED: C-DB-45 el estudiante activo es ESTUDIANTE_GRUPO.', 1;
    UPDATE dbo.EstudianteGrupo SET estado = @estCI WHERE id = @egEA;
    DELETE FROM #c1a; INSERT INTO #c1a EXEC dbo.usp_consultar_audiencias_realtime_grupo @idUsuarioEjecutor = @uEA, @idCorrelacion = @c, @idGrupo = @grupoG;
    IF NOT EXISTS (SELECT 1 FROM #c1a WHERE esDocenteTitular = 0 AND esEstudianteActivo = 0 AND esAmbitoLectura = 0) THROW 58402, 'TEST FAILED: C-DB-45 tras CI el estudiante ya no tiene audiencia.', 1;
    UPDATE dbo.EstudianteGrupo SET estado = @estA WHERE id = @egEA;
    DELETE FROM #c1a; INSERT INTO #c1a EXEC dbo.usp_consultar_audiencias_realtime_grupo @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @idGrupo = @grupoG;
    IF NOT EXISTS (SELECT 1 FROM #c1a WHERE esAmbitoLectura = 1 AND esDocenteTitular = 0 AND esEstudianteActivo = 0) THROW 58403, 'TEST FAILED: C-DB-45 el coordinador del programa A tiene ambito.', 1;
    IF @uCoordAjeno IS NOT NULL
    BEGIN
        DELETE FROM #c1a; INSERT INTO #c1a EXEC dbo.usp_consultar_audiencias_realtime_grupo @idUsuarioEjecutor = @uCoordAjeno, @idCorrelacion = @c, @idGrupo = @grupoG;
        IF NOT EXISTS (SELECT 1 FROM #c1a WHERE esAmbitoLectura = 0 AND esDocenteTitular = 0 AND esEstudianteActivo = 0) THROW 58404, 'TEST FAILED: C-DB-45 un coordinador de otro programa no tiene ambito.', 1;
    END
    DELETE FROM #c1a; INSERT INTO #c1a EXEC dbo.usp_consultar_audiencias_realtime_grupo @idUsuarioEjecutor = @uDec, @idCorrelacion = @c, @idGrupo = @grupoG;
    IF NOT EXISTS (SELECT 1 FROM #c1a WHERE esAmbitoLectura = 1) THROW 58405, 'TEST FAILED: C-DB-45 el decano de la facultad tiene ambito.', 1;
    DELETE FROM #c1a; INSERT INTO #c1a EXEC dbo.usp_consultar_audiencias_realtime_grupo @idUsuarioEjecutor = @uAdm, @idCorrelacion = @c, @idGrupo = @grupoG;
    IF NOT EXISTS (SELECT 1 FROM #c1a WHERE esAmbitoLectura = 1) THROW 58406, 'TEST FAILED: C-DB-45 el administrador de la institucion tiene ambito.', 1;
    IF @uAdmAjeno IS NOT NULL
    BEGIN
        DELETE FROM #c1a; INSERT INTO #c1a EXEC dbo.usp_consultar_audiencias_realtime_grupo @idUsuarioEjecutor = @uAdmAjeno, @idCorrelacion = @c, @idGrupo = @grupoG;
        IF NOT EXISTS (SELECT 1 FROM #c1a WHERE esAmbitoLectura = 0) THROW 58407, 'TEST FAILED: C-DB-45 el administrador de otra institucion no tiene ambito.', 1;
    END
    DELETE FROM #c1a; INSERT INTO #c1a EXEC dbo.usp_consultar_audiencias_realtime_grupo @idUsuarioEjecutor = @uT, @idCorrelacion = @c, @idGrupo = '00000000-0000-0000-0000-0000000000AC';
    IF NOT EXISTS (SELECT 1 FROM #c1a WHERE esDocenteTitular = 0 AND esEstudianteActivo = 0 AND esAmbitoLectura = 0) THROW 58408, 'TEST FAILED: C-DB-45 grupo inexistente -> tres en 0.', 1;

    -- C-DB-61: los 10 SP de C.1 estan concedidos al rol runtime; las funciones no
    DECLARE @sinGrant NVARCHAR(MAX) = (SELECT STRING_AGG(n.name, N', ') FROM (VALUES (N'usp_evaluar_alertas_inasistencia_grupo'), (N'usp_consultar_grupos_pendientes_evaluacion_alertas'),
        (N'usp_consultar_alertas_estudiante'), (N'usp_decidir_revision_cancelacion'), (N'usp_consultar_revisiones_cancelacion_coordinador_paginado'),
        (N'usp_consultar_revisiones_cancelacion_decano_paginado'), (N'usp_resolver_revision_cancelacion'), (N'usp_consultar_destinatarios_revision_cancelacion'),
        (N'usp_consultar_audiencias_realtime_grupo'), (N'usp_actualizar_resolutores_revisiones_cancelacion')) n(name)
        WHERE OBJECT_ID(N'dbo.' + n.name, N'P') IS NULL
           OR NOT EXISTS (SELECT 1 FROM sys.database_permissions pm WHERE pm.major_id = OBJECT_ID(N'dbo.' + n.name) AND pm.permission_name = N'EXECUTE' AND pm.state IN ('G','W')
                          AND pm.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')));
    IF @sinGrant IS NOT NULL THROW 58410, 'TEST FAILED: C-DB-61 SP de C sin EXECUTE para rol_asistencias_runtime (o inexistentes).', 1;
    IF EXISTS (SELECT 1 FROM sys.database_permissions pm WHERE pm.class = 1 AND pm.major_id IN (OBJECT_ID(N'dbo.ufn_revision_cancelacion_resolutores'), OBJECT_ID(N'dbo.ufn_umbral_alerta_inasistencia'))
               AND pm.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
        THROW 58411, 'TEST FAILED: C-DB-61 las funciones de C no se conceden.', 1;

    PRINT 'TEST_PASS:CULM001_C_AUDIENCIAS_Y_PERMISOS';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 58419, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 58418, 'TEST FAILED: C audiencias dejo una transaccion abierta.', 1;
GO
