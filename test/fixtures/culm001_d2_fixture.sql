-- CULM-001 D.2: fixture de las pruebas de migracion (test_culm001_d2_migraciones.sql, test_culm001_d2_down_sin_confirmacion.sql y
-- test_culm001_d_rollback.sql). Exige la migracion 21 aplicada (usp_radicar_solicitud_revision_asistencia_v3) y una transaccion
-- abierta por el llamador; deja en #d2fx los ids creados:
--   sol1  solicitud MED con DOS soportes ATTACHED (a, b)        sol2  solicitud CAL con UN soporte ATTACHED (c)
--   med / cal  ids de las categorias                             a, b, c  ids de los soportes
-- Todo se revierte con el ROLLBACK del llamador.
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
IF OBJECT_ID(N'tempdb..#d2fx') IS NOT NULL DROP TABLE #d2fx;
CREATE TABLE #d2fx (k NVARCHAR(20) NOT NULL PRIMARY KEY, v UNIQUEIDENTIFIER NOT NULL);
GO
DECLARE @codIns NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
DECLARE @g UNIQUEIDENTIFIER, @e UNIQUEIDENTIFIER, @u UNIQUEIDENTIFIER;
SELECT TOP 1 @g = gr.id, @e = eg.idEstudiante
FROM dbo.Grupo gr INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = gr.id AND eg.codigoEstadoEstudiante = @codIns
ORDER BY gr.id, eg.idEstudiante;
SELECT @u = usuario FROM dbo.Estudiante WHERE id = @e;
IF @g IS NULL OR @u IS NULL THROW 52410, 'TEST FAILED: CULM001_D2_MIG fixture faltante (semilla local).', 1;
DECLARE @fin DATETIME2(7) = DATEADD(DAY, -2, SYSUTCDATETIME());
DECLARE @s1 UNIQUEIDENTIFIER = NEWID(), @s2 UNIQUEIDENTIFIER = NEWID();
DECLARE @num INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @g);
INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin) VALUES
    (@s1, N'QA D2 mig 1', @num,     LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @g, DATEADD(HOUR, -1, @fin), @fin),
    (@s2, N'QA D2 mig 2', @num + 1, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @g, DATEADD(HOUR, -1, @fin), @fin);
DECLARE @a UNIQUEIDENTIFIER = NEWID(), @b UNIQUEIDENTIFIER = NEWID(), @c UNIQUEIDENTIFIER = NEWID();
INSERT dbo.ArchivoSoporte (id, usuarioPropietario, nombreOriginal, tipoContenido, tamanioBytes, checksumSha256, estado, fechaRegistroUtc, fechaCambioEstadoUtc, idCorrelacionRegistro)
SELECT x.id, @u, N'mig.pdf', 'application/pdf', 10, LOWER(CONVERT(CHAR(64), HASHBYTES('SHA2_256', CONVERT(VARCHAR(36), x.id)), 2)), 'DRAFT', SYSUTCDATETIME(), SYSUTCDATETIME(), NEWID()
FROM (VALUES (@a), (@b), (@c)) x (id);
CREATE TABLE #d2w (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX), mensajeTecnicoResultado NVARCHAR(MAX),
    estadoResultado INT NOT NULL, idSolicitudRevision UNIQUEIDENTIFIER NULL, totalSoportes INT NULL);
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @j NVARCHAR(MAX) = CONCAT('["', CAST(@a AS CHAR(36)), '","', CAST(@b AS CHAR(36)), '"]');
INSERT INTO #d2w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @e, @idSesion = @s1, @categoria = N'MED',
    @justificacion = N'QA D2 mig 1', @idsArchivoSoporte = @j, @idCorrelacion = @corr, @idUsuarioEjecutor = @u;
INSERT #d2fx SELECT 'sol1', idSolicitudRevision FROM #d2w WHERE idCorrelacion = @corr AND estadoResultado = 1 AND totalSoportes = 2;
TRUNCATE TABLE #d2w;
SET @corr = NEWID(); SET @j = CONCAT('["', CAST(@c AS CHAR(36)), '"]');
INSERT INTO #d2w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @e, @idSesion = @s2, @categoria = N'CAL',
    @justificacion = N'QA D2 mig 2', @idsArchivoSoporte = @j, @idCorrelacion = @corr, @idUsuarioEjecutor = @u;
INSERT #d2fx SELECT 'sol2', idSolicitudRevision FROM #d2w WHERE idCorrelacion = @corr AND estadoResultado = 1 AND totalSoportes = 1;
DROP TABLE #d2w;
INSERT #d2fx SELECT 'med', id FROM dbo.CategoriaJustificacion WHERE codigo = N'MED';
INSERT #d2fx SELECT 'cal', id FROM dbo.CategoriaJustificacion WHERE codigo = N'CAL';
INSERT #d2fx VALUES ('a', @a), ('b', @b), ('c', @c);
IF (SELECT COUNT(*) FROM #d2fx) <> 7 THROW 52411, 'TEST FAILED: CULM001_D2_MIG el fixture no radico las dos solicitudes.', 1;
GO
