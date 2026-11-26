-- 02_sesiones.sql  (GENERADO)
USE [gestionasistenciadb];
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;

DECLARE @p20262 UNIQUEIDENTIFIER = 'F2A3B4C5-0000-0000-0000-000000000001', @p20261 UNIQUEIDENTIFIER = '9932D7D4-BB8B-59F9-BBDD-5D1925F56272';
DECLARE @g UNIQUEIDENTIFIER, @u UNIQUEIDENTIFIER, @c UNIQUEIDENTIFIER;
DECLARE @canc INT, @conAs INT, @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT;

-- 2026-2: generador real (horario -> sesiones, festivos nacen cancelados), ejecutado como el docente titular
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
  SELECT g.id, d.usuario FROM dbo.Grupo g JOIN dbo.Docente d ON d.id = g.docente
  WHERE g.periodoAcademico = @p20262 AND NOT EXISTS (SELECT 1 FROM dbo.Sesion s WHERE s.grupo = g.id);
OPEN cur; FETCH NEXT FROM cur INTO @g, @u;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @c = NEWID();
    EXEC dbo.usp_generar_sesiones_grupo_v2 @idGrupo = @g, @idCorrelacion = @c, @idUsuarioEjecutor = @u;
    FETCH NEXT FROM cur INTO @g, @u;
END
CLOSE cur; DEALLOCATE cur;

-- 2026-1 (periodo ya terminado: el generador lo rechaza): mismas reglas que el generador, luego festivos
IF NOT EXISTS (SELECT 1 FROM dbo.Sesion s JOIN dbo.Grupo g ON g.id = s.grupo WHERE g.periodoAcademico = @p20261)
BEGIN
    ;WITH f AS (SELECT CAST('2026-02-02' AS DATE) AS d UNION ALL SELECT DATEADD(DAY, 1, d) FROM f WHERE d < '2026-06-12')
    SELECT g.id AS grupo, f.d, h.horaInicio, h.horaFin,
           ini = DATEADD(HOUR, 5, DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), h.horaInicio), CAST(f.d AS DATETIME2(7)))),
           fin = DATEADD(HOUR, 5, DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), h.horaFin), CAST(f.d AS DATETIME2(7))))
    INTO #s1
    FROM f JOIN dbo.Horario h ON 1 = 1 JOIN dbo.Grupo g ON g.id = h.grupo AND g.periodoAcademico = @p20261
    JOIN dbo.Dia di ON di.id = h.dia
    WHERE di.codigo = CHOOSE(DATEDIFF(DAY, '19000101', f.d) % 7 + 1, 'LU', 'MA', 'MI', 'JU', 'VI', 'SA', 'DO')
    OPTION (MAXRECURSION 400);
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT NEWID(), CONCAT(N'Sesión ', x.n), x.n, UPPER(LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(50)), '-', ''), 6)),
           DATEDIFF(WEEK, '2026-02-02', x.d) + 1, x.grupo, x.ini, x.fin, N'UTC_GENERADOR'
    FROM (SELECT *, n = ROW_NUMBER() OVER (PARTITION BY grupo ORDER BY ini) FROM #s1) x;
    DROP TABLE #s1;
END

DECLARE cur2 CURSOR LOCAL FAST_FORWARD FOR
  SELECT g.id, d.usuario FROM dbo.Grupo g JOIN dbo.Docente d ON d.id = g.docente WHERE g.periodoAcademico = @p20261;
OPEN cur2; FETCH NEXT FROM cur2 INTO @g, @u;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @c = NEWID();
    BEGIN TRANSACTION;
    EXEC dbo.usp_internal_aplicar_festivos_grupo @idGrupo = @g, @soloFuturas = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @u,
         @sesionesCanceladas = @canc OUTPUT, @sesionesConAsistencia = @conAs OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 1 COMMIT TRANSACTION; ELSE BEGIN ROLLBACK TRANSACTION; PRINT CONCAT(N'festivos 2026-1 fallo: ', @mt); END
    FETCH NEXT FROM cur2 INTO @g, @u;
END
CLOSE cur2; DEALLOCATE cur2;

SELECT periodo = pa.nombre, grupos = COUNT(DISTINCT g.id), sesiones = COUNT(s.id),
       canceladasFestivo = SUM(IIF(sc.sesion IS NULL, 0, 1))
FROM dbo.Grupo g JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
LEFT JOIN dbo.Sesion s ON s.grupo = g.id LEFT JOIN dbo.SesionCancelacion sc ON sc.sesion = s.id GROUP BY pa.nombre;
