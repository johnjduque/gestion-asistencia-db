USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- ufn_calcular_fecha_limite_justificacion_conjunto (PERF-EST-MM, docs/work-items/PERF-estudiante-mis-materias/PLAN.md)
--
-- Version en linea (funcion de tabla de una sola sentencia) de ufn_calcular_fecha_limite_justificacion: misma regla y mismo
-- resultado (CULM-001 D.1, HU026B; CONTRACT §0 [SUPUESTO-D-01], §2.2). Devuelve una fila con fechaLimiteUtc:
--   limite EXCLUSIVO (UTC) = medianoche local (TIEMPO/ZONA_HORARIA_SQLSERVER) del dia
--   fecha local de fin de la sesion + N + 1,   N = ASISTENCIA/DIAS_LIMITE_JUSTIFICACION.
-- NULL si @fechaHoraFinSesionUtc es NULL, si N falta, es vacio, no es entero o es negativo, si la zona falta, es vacia o no
-- existe en sys.time_zone_info, o si el limite se sale del rango de DATE.
--
-- Por que existe: la funcion escalar tiene varias sentencias, lee dos parametros y sys.time_zone_info en cada llamada y no
-- se puede expandir en linea; usada por fila en vistas (uv_sesion_estudiante_reclamo, uv_asistencia_toma_estudiante)
-- obliga a planes en serie y a una evaluacion fila por fila. Esta version se expande dentro de la consulta: los dos
-- parametros y la zona se leen como un conjunto constante y solo la aritmetica de fechas se hace por fila.
-- Los parametros se leen con la misma semantica de ufn_obtener_parametro (valor, si no valorDefecto, si no '';
-- uv_parametro solo trae los activos) seguida del TRIM de ufn_obtener_parametro_texto.
-- La zona invalida se reemplaza por 'UTC' antes de AT TIME ZONE (que fallaria con un nombre inexistente); el resultado de
-- esa rama se descarta porque zonaValida = 0 devuelve NULL.
-- Sin escrituras. Uso: CROSS APPLY dbo.ufn_calcular_fecha_limite_justificacion_conjunto(s.fechaHoraFin) lim.
-- La funcion escalar se conserva sin cambios para los llamadores de un solo valor; test_perf_estudiante_mis_materias.sql
-- comprueba que las dos den el mismo resultado.
-- ============================================================================

-- Una funcion en linea exige que uv_parametro exista al crearse; las funciones se despliegan antes que las vistas
-- (mismo resguardo que ufn_obtener_parametro). La vista real la reemplaza al desplegar schema/views.
IF OBJECT_ID('dbo.uv_parametro', 'V') IS NULL
BEGIN
    EXEC('CREATE VIEW dbo.uv_parametro AS SELECT CAST(NULL AS UNIQUEIDENTIFIER) AS id, CAST('' '' AS VARCHAR(100)) AS grupo, CAST('' '' AS VARCHAR(100)) AS clave, CAST('' '' AS NVARCHAR(MAX)) AS valor, CAST(''STRING'' AS VARCHAR(20)) AS tipoDato, CAST('' '' AS NVARCHAR(MAX)) AS valorDefecto, CAST(1 AS BIT) AS estaActivo, GETDATE() AS fechaCreacion, GETDATE() AS fechaModificacion');
END
GO

CREATE OR ALTER FUNCTION [dbo].[ufn_calcular_fecha_limite_justificacion_conjunto] (
    @fechaHoraFinSesionUtc DATETIME2(7)
)
RETURNS TABLE
AS
RETURN
SELECT  fechaLimiteUtc = CAST(CASE
                WHEN @fechaHoraFinSesionUtc IS NULL OR cfg.dias IS NULL OR cfg.zonaValida = 0 THEN NULL
                WHEN cfg.dias + 1 > DATEDIFF(DAY, loc.fechaLocalFin, CAST('9999-12-30' AS DATE)) THEN NULL
                ELSE (CAST(DATEADD(DAY, cfg.dias + 1, loc.fechaLocalFin) AS DATETIME2(7)) AT TIME ZONE cfg.zona) AT TIME ZONE 'UTC'
            END AS DATETIME2(7))
FROM (
        SELECT  dias = CASE WHEN txt.textoDias = N'' OR TRY_CAST(txt.textoDias AS INT) < 0 THEN NULL
                            ELSE TRY_CAST(txt.textoDias AS INT) END,
                zonaValida = CAST(IIF(txt.textoZona <> N''
                                      AND EXISTS (SELECT 1 FROM sys.time_zone_info tz WHERE tz.name = txt.textoZona), 1, 0) AS BIT),
                zona = CAST(IIF(txt.textoZona <> N''
                                AND EXISTS (SELECT 1 FROM sys.time_zone_info tz WHERE tz.name = txt.textoZona),
                                txt.textoZona, N'UTC') AS NVARCHAR(128))
        FROM (
                SELECT  textoDias = TRIM(ISNULL((SELECT TOP (1) ISNULL(p.valor, ISNULL(p.valorDefecto, N''))
                                                FROM dbo.uv_parametro p
                                                WHERE p.grupo = 'ASISTENCIA' AND p.clave = 'DIAS_LIMITE_JUSTIFICACION'), N'')),
                        textoZona = TRIM(ISNULL((SELECT TOP (1) ISNULL(p.valor, ISNULL(p.valorDefecto, N''))
                                                FROM dbo.uv_parametro p
                                                WHERE p.grupo = 'TIEMPO' AND p.clave = 'ZONA_HORARIA_SQLSERVER'), N''))
             ) txt
     ) cfg
CROSS APPLY (SELECT fechaLocalFin = CAST((@fechaHoraFinSesionUtc AT TIME ZONE 'UTC') AT TIME ZONE cfg.zona AS DATE)) loc;
GO
