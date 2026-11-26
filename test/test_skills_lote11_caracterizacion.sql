USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 11 (plan por lotes 2026-11-25): asistencia y reclamos.
-- Fija el comportamiento de usp_consultar_destinatarios_reclamo_asistencia (no tenia prueba directa) antes de refactorizarlo. Los
-- demas SP del lote siguen cubiertos por sus pruebas de dominio. Lo que escribe corre dentro de una transaccion revertida.
--   SKL11_R01_DESTINATARIOS_RECLAMO  por sesion y estudiante (radicacion) y por solicitud (resolucion): dos filas en orden
--                                    ESTUDIANTE, DOCENTE con usuario, nombre, correo y grupo; ejecutor ajeno sin filas;
--                                    sin parametros VAL_001 (THROW 51000)
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote11_caracterizacion';

DECLARE @s UNIQUEIDENTIFIER, @g UNIQUEIDENTIFIER, @eg UNIQUEIDENTIFIER, @est UNIQUEIDENTIFIER, @uEst UNIQUEIDENTIFIER, @uDoc UNIQUEIDENTIFIER;
SELECT TOP 1 @s = s.id, @g = g.id, @eg = eg.id, @est = e.id, @uEst = e.usuario, @uDoc = d.usuario
FROM dbo.Sesion s INNER JOIN dbo.Grupo g ON g.id = s.grupo INNER JOIN dbo.Docente d ON d.id = g.docente
INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id INNER JOIN dbo.Estudiante e ON e.id = eg.estudiante
ORDER BY s.id, eg.id;
IF @s IS NULL THROW 56100, 'TEST FAILED: SKL11 faltan fixtures del seed (sesion con estudiante matriculado).', 1;
DECLARE @ajeno UNIQUEIDENTIFIER = (SELECT TOP 1 u.id FROM dbo.Usuario u WHERE u.id NOT IN (@uEst, @uDoc) ORDER BY u.id);
DECLARE @nombreGrupoEsperado NVARCHAR(300) = (SELECT CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', a.nombre) AS NVARCHAR(300))
    FROM dbo.Grupo g INNER JOIN dbo.Asignatura a ON a.id = g.asignatura WHERE g.id = @g);
DECLARE @fechaEsperada VARCHAR(10) = (SELECT CONVERT(VARCHAR(10), fechaHoraInicio, 23) FROM dbo.Sesion WHERE id = @s);

CREATE TABLE #skl11 (rolDestinatario VARCHAR(20), idUsuario UNIQUEIDENTIFIER, nombreCompleto NVARCHAR(400), correo NVARCHAR(200),
    idGrupo UNIQUEIDENTIFIER, nombreGrupo NVARCHAR(300), fechaSesion VARCHAR(10), codigoGrupo INT, nombreAsignatura NVARCHAR(200), n INT IDENTITY(1,1));

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @c UNIQUEIDENTIFIER = NEWID(), @err NVARCHAR(4000), @num INT;
    -- ================================================================= R01
    INSERT INTO #skl11 (rolDestinatario, idUsuario, nombreCompleto, correo, idGrupo, nombreGrupo, fechaSesion, codigoGrupo, nombreAsignatura)
    EXEC dbo.usp_consultar_destinatarios_reclamo_asistencia @idSesion = @s, @idEstudiante = @est, @idCorrelacion = @c, @idUsuarioEjecutor = @uEst;
    IF (SELECT COUNT(*) FROM #skl11) <> 2
       OR NOT EXISTS (SELECT 1 FROM #skl11 x INNER JOIN dbo.Usuario u ON u.id = x.idUsuario
                      WHERE x.n = 1 AND x.rolDestinatario = 'ESTUDIANTE' AND x.idUsuario = @uEst AND x.correo = u.correo AND x.idGrupo = @g
                        AND x.nombreGrupo = @nombreGrupoEsperado AND x.fechaSesion = @fechaEsperada
                        AND x.nombreCompleto = CONCAT_WS(N' ', NULLIF(TRIM(u.primerNombre), N''), NULLIF(TRIM(u.segundoNombre), N''),
                                                         NULLIF(TRIM(u.primerApellido), N''), NULLIF(TRIM(u.segundoApellido), N'')))
       OR NOT EXISTS (SELECT 1 FROM #skl11 x WHERE x.n = 2 AND x.rolDestinatario = 'DOCENTE' AND x.idUsuario = @uDoc AND x.idGrupo = @g)
        THROW 56110, 'TEST FAILED: SKL11_R01_DESTINATARIOS_RECLAMO (por sesion y estudiante)', 1;

    TRUNCATE TABLE #skl11;
    INSERT INTO #skl11 (rolDestinatario, idUsuario, nombreCompleto, correo, idGrupo, nombreGrupo, fechaSesion, codigoGrupo, nombreAsignatura)
    EXEC dbo.usp_consultar_destinatarios_reclamo_asistencia @idSesion = @s, @idEstudiante = @est, @idCorrelacion = @c, @idUsuarioEjecutor = @ajeno;
    IF (SELECT COUNT(*) FROM #skl11) <> 0 THROW 56111, 'TEST FAILED: SKL11_R01_DESTINATARIOS_RECLAMO (ejecutor ajeno sin filas)', 1;

    -- por solicitud: reclamo sobre la asistencia del estudiante en la sesion
    DECLARE @a UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Asistencia WHERE estudianteGrupo = @eg AND sesion = @s);
    IF @a IS NULL
    BEGIN
        SET @a = NEWID();
        INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@a, @eg, @s);
    END
    DECLARE @sol UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta)
    VALUES (@sol, N'SKL11', @a, CAST(SYSUTCDATETIME() AS DATE), (SELECT TOP 1 id FROM dbo.Estado ORDER BY id), 'SKL11', '');
    TRUNCATE TABLE #skl11;
    INSERT INTO #skl11 (rolDestinatario, idUsuario, nombreCompleto, correo, idGrupo, nombreGrupo, fechaSesion, codigoGrupo, nombreAsignatura)
    EXEC dbo.usp_consultar_destinatarios_reclamo_asistencia @idSolicitud = @sol, @idCorrelacion = @c, @idUsuarioEjecutor = @uDoc;
    IF (SELECT COUNT(*) FROM #skl11) <> 2
       OR NOT EXISTS (SELECT 1 FROM #skl11 WHERE n = 1 AND rolDestinatario = 'ESTUDIANTE' AND idUsuario = @uEst AND nombreGrupo = @nombreGrupoEsperado)
       OR NOT EXISTS (SELECT 1 FROM #skl11 WHERE n = 2 AND rolDestinatario = 'DOCENTE' AND idUsuario = @uDoc AND fechaSesion = @fechaEsperada)
        THROW 56112, 'TEST FAILED: SKL11_R01_DESTINATARIOS_RECLAMO (por solicitud)', 1;

    SELECT @err = NULL, @num = NULL;
    BEGIN TRY
        EXEC dbo.usp_consultar_destinatarios_reclamo_asistencia @idSesion = @s, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SELECT @err = ERROR_MESSAGE(), @num = ERROR_NUMBER();
    END CATCH
    IF @num IS NULL OR @num <> 51000 OR @err NOT LIKE N'DBCODE=VAL[_]001|%' THROW 56113, 'TEST FAILED: SKL11_R01_DESTINATARIOS_RECLAMO (VAL_001)', 1;
    PRINT 'TEST_PASS:SKL11_R01_DESTINATARIOS_RECLAMO';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
DROP TABLE #skl11;
PRINT 'TEST END: test_skills_lote11_caracterizacion';
GO
