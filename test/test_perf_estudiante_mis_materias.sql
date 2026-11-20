USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- PERF-EST-MM (migracion 59, docs/work-items/PERF-estudiante-mis-materias/PLAN.md): el cambio es solo de rendimiento.
--   PERF_MM_01  ufn_calcular_fecha_limite_justificacion_conjunto da lo mismo que la escalar (fechas normales, borde de
--               medianoche, NULL y fecha maxima) con los parametros de la semilla.
--   PERF_MM_02  ... y con parametros ausentes o invalidos (dias vacio, negativo, no entero; zona vacia o inexistente).
--   PERF_MM_03  uv_sesion_estudiante_reclamo: fechaLimiteJustificacionUtc y plazoJustificacionVigente iguales a la regla escalar.
--   PERF_MM_04  uv_asistencia_toma_estudiante: esReclamable igual a la regla anterior (escalar + ufn_obtener_parametro por fila).
--   PERF_MM_05  usp_consultar_sesiones_materia_estudiante devuelve las mismas filas, orden y total que la consulta anterior
--               (paginas de 2 filas) para los estudiantes con sesiones.
--   PERF_MM_06  existen los cuatro indices.
-- Las variaciones de parametros corren dentro de una transaccion con ROLLBACK: no quedan cambios.
-- ============================================================================
IF OBJECT_ID('tempdb..#perf_mm_expect') IS NOT NULL DROP PROCEDURE #perf_mm_expect;
GO
CREATE PROCEDURE #perf_mm_expect @label NVARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = N'TEST FAILED: PERF_MM_' + @label;
        THROW 52900, @mensaje, 1;
    END
END;
GO

IF OBJECT_ID('tempdb..#perf_mm_fechas') IS NOT NULL DROP TABLE #perf_mm_fechas;
CREATE TABLE #perf_mm_fechas (fecha DATETIME2(7) NULL);
INSERT #perf_mm_fechas (fecha) VALUES
    (NULL), (SYSUTCDATETIME()), ('2026-11-04T13:00:00'), ('2026-11-05T04:30:00'), ('2026-11-05T05:00:00'),
    ('2026-03-08T07:59:59'), ('2026-12-31T23:59:59.9999999'), ('2000-01-01T00:00:00'), ('9999-12-25T00:00:00'),
    ('9999-12-31T23:59:59.9999999');
INSERT #perf_mm_fechas (fecha) SELECT TOP (200) s.fechaHoraFin FROM dbo.Sesion s ORDER BY s.fechaHoraFin DESC;
GO

-- PERF_MM_01: parametros de la semilla.
DECLARE @dif INT = (SELECT COUNT(1) FROM #perf_mm_fechas f
                    CROSS APPLY dbo.ufn_calcular_fecha_limite_justificacion_conjunto(f.fecha) lim
                    WHERE EXISTS (SELECT lim.fechaLimiteUtc EXCEPT SELECT dbo.ufn_calcular_fecha_limite_justificacion(f.fecha)));
IF NOT (@dif = 0) EXEC #perf_mm_expect 'TVF_IGUAL_ESCALAR_SEMILLA', @ok = 0;
IF NOT ((SELECT COUNT(1) FROM dbo.ufn_calcular_fecha_limite_justificacion_conjunto(NULL)) = 1) EXEC #perf_mm_expect 'TVF_UNA_FILA', @ok = 0;
PRINT 'TEST_PASS:PERF_MM_01_TVF_IGUAL_ESCALAR_SEMILLA';
GO

-- PERF_MM_02: parametros ausentes o invalidos (ROLLBACK al final de cada variante).
DECLARE @casos TABLE (orden INT, grupo VARCHAR(100), clave VARCHAR(100), valor NVARCHAR(MAX), quitarValorDefecto BIT);
INSERT @casos VALUES
    (1, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION', N'', 1),
    (2, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION', N'-1', 0),
    (3, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION', N'cinco', 0),
    (4, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION', N' 0 ', 0),
    (5, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION', N'40000', 0),
    (6, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER', N'', 1),
    (7, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER', N'Zona/Inexistente', 0),
    (8, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER', N'  UTC  ', 0),
    (9, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER', NULL, 0);   -- NULL = parametro inactivo (uv_parametro no lo trae)
DECLARE @orden INT = 1, @grupo VARCHAR(100), @clave VARCHAR(100), @valor NVARCHAR(MAX), @quitar BIT, @dif INT, @etiqueta VARCHAR(100);
WHILE @orden <= 9
BEGIN
    SELECT @grupo = grupo, @clave = clave, @valor = valor, @quitar = quitarValorDefecto FROM @casos WHERE orden = @orden;
    BEGIN TRANSACTION;
    UPDATE dbo.CatalogoParametro
       SET valor = ISNULL(@valor, valor), valorDefecto = IIF(@quitar = 1, N'', valorDefecto), estaActivo = IIF(@valor IS NULL, 0, estaActivo)
     WHERE grupo = @grupo AND clave = @clave;
    SET @dif = (SELECT COUNT(1) FROM #perf_mm_fechas f
                CROSS APPLY dbo.ufn_calcular_fecha_limite_justificacion_conjunto(f.fecha) lim
                WHERE EXISTS (SELECT lim.fechaLimiteUtc EXCEPT SELECT dbo.ufn_calcular_fecha_limite_justificacion(f.fecha)));
    ROLLBACK TRANSACTION;
    SET @etiqueta = CONCAT('TVF_IGUAL_ESCALAR_CASO_', @orden);
    IF NOT (@dif = 0) EXEC #perf_mm_expect @etiqueta, @ok = 0;
    SET @orden += 1;
END
PRINT 'TEST_PASS:PERF_MM_02_TVF_IGUAL_ESCALAR_PARAMETROS_INVALIDOS';
GO

-- PERF_MM_03: la vista de sesiones del estudiante con la regla escalar de antes.
DECLARE @dif INT = (SELECT COUNT(1) FROM dbo.uv_sesion_estudiante_reclamo r
                    WHERE EXISTS (SELECT r.fechaLimiteJustificacionUtc, r.plazoJustificacionVigente
                                  EXCEPT
                                  SELECT x.limite, CAST(IIF(r.estaCancelada = 0 AND x.limite IS NOT NULL AND SYSUTCDATETIME() < x.limite, 1, 0) AS BIT)
                                  FROM (SELECT limite = dbo.ufn_calcular_fecha_limite_justificacion(r.fechaHoraFin)) x));
IF NOT (@dif = 0) EXEC #perf_mm_expect 'VISTA_RECLAMO_IGUAL', @ok = 0;
PRINT 'TEST_PASS:PERF_MM_03_VISTA_SESION_ESTUDIANTE_RECLAMO_IGUAL';
GO

-- PERF_MM_04: esReclamable de la vista de tomas con la regla anterior.
DECLARE @retirado NVARCHAR(5) = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_RETIRADO') AS NVARCHAR(5));
DECLARE @dif INT = (
    SELECT COUNT(1)
    FROM dbo.uv_asistencia_toma_estudiante t
    INNER JOIN dbo.uv_toma_punto_control pc ON pc.idToma = t.idToma AND pc.idSesion = t.idSesion
    OUTER APPLY (SELECT TOP 1 idSolicitud = sra.id
                 FROM dbo.SolicitudRevisionAsistencia sra
                 INNER JOIN dbo.Estado e ON e.id = sra.estado
                 WHERE sra.asistencia = t.idAsistencia AND sra.toma = t.idToma AND e.codigo <> @retirado
                 ORDER BY sra.fecha DESC, sra.id DESC) sol
    WHERE ISNULL(t.idSolicitudRevision, '00000000-0000-0000-0000-000000000000') <> ISNULL(sol.idSolicitud, '00000000-0000-0000-0000-000000000000')
       OR t.esReclamable <> CAST(IIF(t.codigoRazonCausa = N'SJC' AND sol.idSolicitud IS NULL AND pc.estaSesionCancelada = 0
                                     AND SYSUTCDATETIME() < dbo.ufn_calcular_fecha_limite_justificacion(pc.fechaHoraFinSesion), 1, 0) AS BIT));
IF NOT (@dif = 0) EXEC #perf_mm_expect 'VISTA_TOMAS_IGUAL', @ok = 0;
PRINT 'TEST_PASS:PERF_MM_04_VISTA_ASISTENCIA_TOMA_ESTUDIANTE_IGUAL';
GO

-- PERF_MM_05: el SP frente a la consulta anterior (vista filtrada + escalar), en paginas de 2 filas.
DECLARE @inscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @pares TABLE (n INT IDENTITY(1, 1), usuario UNIQUEIDENTIFIER, asignatura UNIQUEIDENTIFIER, filas INT);
INSERT @pares (usuario, asignatura, filas)
SELECT TOP (10) e.usuario, r.idAsignatura, COUNT(1)
FROM dbo.uv_sesion_estudiante_reclamo r
INNER JOIN dbo.Estudiante e ON e.id = r.idEstudiante
WHERE r.codigoEstadoEstudiante = @inscrita AND e.usuario IS NOT NULL
GROUP BY e.usuario, r.idAsignatura
ORDER BY COUNT(1) DESC, e.usuario, r.idAsignatura;

IF OBJECT_ID('tempdb..#perf_mm_sp') IS NOT NULL DROP TABLE #perf_mm_sp;
CREATE TABLE #perf_mm_sp (
    id UNIQUEIDENTIFIER, nombre NVARCHAR(400), numero INT, codigo NVARCHAR(100), numeroSemana INT, idGrupo UNIQUEIDENTIFIER,
    codigoGrupo NVARCHAR(100), nombreGrupo NVARCHAR(400), fechaHoraInicio DATETIME2(7), fechaHoraFin DATETIME2(7),
    fechaLimiteJustificacionUtc DATETIME2(7), plazoJustificacionVigente BIT, totalRegistros INT, fila INT IDENTITY(1, 1));
DECLARE @n INT = 1, @max INT = (SELECT COUNT(1) FROM @pares), @usuario UNIQUEIDENTIFIER, @asignatura UNIQUEIDENTIFIER, @filas INT,
        @pagina INT, @dif INT, @comparados INT = 0, @rbacU NVARCHAR(4000), @rbacT NVARCHAR(4000), @rbacE BIT;
WHILE @n <= @max
BEGIN
    SELECT @usuario = usuario, @asignatura = asignatura, @filas = filas FROM @pares WHERE n = @n;
    SELECT @rbacU = N'', @rbacT = N'', @rbacE = 1;
    EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @usuario, @codigoPerfilRequerido = 'ESTUDIANTE', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @rbacU OUTPUT, @mensajeTecnicoResultado = @rbacT OUTPUT, @estadoResultado = @rbacE OUTPUT;
    IF @rbacE = 1
    BEGIN
        SET @pagina = 1;
        WHILE @pagina <= (@filas + 1) / 2 + 1
        BEGIN
            TRUNCATE TABLE #perf_mm_sp;
            INSERT INTO #perf_mm_sp (id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio,
                                     fechaHoraFin, fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros)
            EXEC dbo.usp_consultar_sesiones_materia_estudiante @idUsuarioEjecutor = @usuario, @idCorrelacion = @corr,
                 @idMateria = @asignatura, @numeroPagina = @pagina, @tamanoPagina = 2;
            ;WITH esperado AS (
                SELECT  id = r.idSesion, r.nombre, r.numero, r.codigo, r.numeroSemana, r.idGrupo, r.codigoGrupo, r.nombreGrupo,
                        r.fechaHoraInicio, r.fechaHoraFin, fechaLimiteJustificacionUtc = x.limite,
                        plazoJustificacionVigente = CAST(IIF(r.estaCancelada = 0 AND x.limite IS NOT NULL AND SYSUTCDATETIME() < x.limite, 1, 0) AS BIT),
                        totalRegistros = COUNT(1) OVER(),
                        fila = ROW_NUMBER() OVER (ORDER BY r.fechaHoraInicio ASC, r.numero ASC, r.idSesion ASC)
                FROM dbo.uv_sesion_estudiante_reclamo r
                INNER JOIN dbo.Estudiante e ON e.id = r.idEstudiante
                CROSS APPLY (SELECT limite = dbo.ufn_calcular_fecha_limite_justificacion(r.fechaHoraFin)) x
                WHERE e.usuario = @usuario AND r.idAsignatura = @asignatura AND r.codigoEstadoEstudiante = @inscrita
            ), pagina AS (
                SELECT id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin,
                       fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros, fila = fila - (@pagina - 1) * 2
                FROM esperado WHERE fila > (@pagina - 1) * 2 AND fila <= @pagina * 2
            )
            SELECT @dif = (SELECT COUNT(1) FROM (
                    (SELECT id, numero, idGrupo, fechaHoraInicio, fechaHoraFin, fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros, fila FROM #perf_mm_sp
                     EXCEPT SELECT id, numero, idGrupo, fechaHoraInicio, fechaHoraFin, fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros, fila FROM pagina)
                    UNION ALL
                    (SELECT id, numero, idGrupo, fechaHoraInicio, fechaHoraFin, fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros, fila FROM pagina
                     EXCEPT SELECT id, numero, idGrupo, fechaHoraInicio, fechaHoraFin, fechaLimiteJustificacionUtc, plazoJustificacionVigente, totalRegistros, fila FROM #perf_mm_sp)
                ) d);
            IF NOT (@dif = 0) EXEC #perf_mm_expect 'SP_IGUAL_CONSULTA_ANTERIOR', @ok = 0;
            SET @pagina += 1;
        END
        SET @comparados += 1;
    END
    SET @n += 1;
END
PRINT CONCAT('PERF_MM_05 pares estudiante/materia comparados: ', @comparados);
PRINT 'TEST_PASS:PERF_MM_05_SP_SESIONES_MATERIA_IGUAL';
GO

-- PERF_MM_06: indices.
IF NOT ((SELECT COUNT(1) FROM sys.indexes
    WHERE (object_id = OBJECT_ID('dbo.EstudianteGrupo') AND name IN ('IX_EstudianteGrupo_Estudiante', 'IX_EstudianteGrupo_Grupo'))
       OR (object_id = OBJECT_ID('dbo.Grupo') AND name = 'IX_Grupo_Asignatura')
       OR (object_id = OBJECT_ID('dbo.Asistencia') AND name = 'IX_Asistencia_Sesion')) = 4) EXEC #perf_mm_expect 'INDICES', @ok = 0;
PRINT 'TEST_PASS:PERF_MM_06_INDICES';
GO

IF OBJECT_ID('tempdb..#perf_mm_sp') IS NOT NULL DROP TABLE #perf_mm_sp;
IF OBJECT_ID('tempdb..#perf_mm_fechas') IS NOT NULL DROP TABLE #perf_mm_fechas;
IF OBJECT_ID('tempdb..#perf_mm_expect') IS NOT NULL DROP PROCEDURE #perf_mm_expect;
GO
