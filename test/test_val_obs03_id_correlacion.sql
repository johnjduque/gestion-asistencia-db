USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;

-- VAL OBS-03 (oleada 3): el ID de correlacion llega a los procedimientos (@idCorrelacion).
-- 17 procedimientos de dbo no declaran @idCorrelacion (verificado contra sys.parameters y contra schema/stored-procedures el
-- 2026-11-13; la lista de chequeo decia 18 porque contaba tambien un fixture de test/). Ninguno lo necesita: o es de solo
-- lectura, o es un nucleo interno sin EXECUTE para la aplicacion que corre dentro de la transaccion de un llamador que ya
-- recibe y registra @idCorrelacion. La justificacion de cada uno esta en docs/work-items/VAL-oleada3-bd-pendientes/PLAN.md.
--
-- Lista blanca (clase):
--   LECTURA           solo lee; no escribe tablas.
--   NUCLEO_MUTANTE    escribe, pero es interno: sin EXECUTE para rol_asistencias_runtime y siempre llamado por un procedimiento
--                     que recibe @idCorrelacion y lo usa en su auditoria o en su resultado.
--   CONTEXTO_SESION   solo fija SESSION_CONTEXT; no escribe tablas.
--
--   VAL_OBS03_01: todo procedimiento de dbo sin @idCorrelacion esta en la lista blanca (un procedimiento nuevo sin el parametro
--                 y sin entrada en la lista hace fallar la compuerta).
--   VAL_OBS03_02: la lista no tiene entradas viejas (cada una existe y sigue sin el parametro: si se le agrega, se saca de aqui).
--   VAL_OBS03_03: las entradas LECTURA y CONTEXTO_SESION no actualizan ninguna tabla (sys.dm_sql_referenced_entities.is_updated).
--   VAL_OBS03_04: ninguna entrada NUCLEO_MUTANTE tiene EXECUTE para rol_asistencias_runtime y cada una tiene un llamador
--                 que si declara @idCorrelacion.
-- Solo lectura del catalogo del motor.
PRINT 'TEST START: test_val_obs03_id_correlacion (VAL OBS-03)';
GO

IF OBJECT_ID('tempdb..#obs03Lista') IS NOT NULL DROP TABLE #obs03Lista;
CREATE TABLE #obs03Lista (nombre SYSNAME COLLATE DATABASE_DEFAULT PRIMARY KEY, clase VARCHAR(20) COLLATE DATABASE_DEFAULT NOT NULL);
INSERT INTO #obs03Lista (nombre, clase) VALUES
    ('usp_actualizar_nombres_usuario_interno',               'NUCLEO_MUTANTE'),
    ('usp_internal_marcar_ausentes_toma',                    'NUCLEO_MUTANTE'),
    ('usp_internal_resolver_token_matricula',                'NUCLEO_MUTANTE'),
    ('usp_establecer_contexto_usuario_ejecutor',             'CONTEXTO_SESION'),
    ('usp_consultar_contacto_notificacion_interno',          'LECTURA'),
    ('usp_consultar_notificaciones_salientes_admin_interno', 'LECTURA'),
    ('usp_consultar_plantilla_notificacion_activa_interno',  'LECTURA'),
    ('usp_consultar_plantillas_notificacion_admin_interno',  'LECTURA'),
    ('usp_consultar_ventanas_matricula_por_rotar',           'LECTURA'),
    ('usp_internal_resolver_token_asistencia',               'LECTURA'),
    ('usp_obtener_mensaje_catalogo',                         'LECTURA'),
    ('usp_resolver_periodo_kpi_facultad_interno',            'LECTURA'),
    ('usp_resolver_periodo_kpi_institucion_interno',         'LECTURA'),
    ('usp_resolver_periodo_kpi_interno',                     'LECTURA'),
    ('usp_validar_estudiante_en_programa_interno',           'LECTURA'),
    ('usp_validar_id_interno',                               'LECTURA'),
    ('usp_validar_programa_en_facultad_interno',             'LECTURA');
GO

-- VAL_OBS03_01
DECLARE @nuevos NVARCHAR(MAX) = (
    SELECT STRING_AGG(CAST(p.name AS NVARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY p.name)
    FROM sys.procedures p
    WHERE p.schema_id = SCHEMA_ID('dbo') AND p.is_ms_shipped = 0
      AND NOT EXISTS (SELECT 1 FROM sys.parameters x WHERE x.object_id = p.object_id AND x.name = '@idCorrelacion')
      AND NOT EXISTS (SELECT 1 FROM #obs03Lista l WHERE l.nombre = p.name));
IF @nuevos IS NOT NULL
BEGIN
    DECLARE @m1 NVARCHAR(2048) = CONCAT(N'TEST FAILED VAL_OBS03_01: procedimientos sin @idCorrelacion y fuera de la lista blanca ',
        N'(agregar el parametro o justificarlos en test_val_obs03_id_correlacion.sql y en el PLAN): ', LEFT(@nuevos, 1500));
    THROW 55401, @m1, 1;
END;
PRINT 'TEST_PASS:VAL_OBS03_01_SIN_CORRELACION_EN_LISTA';
GO

-- VAL_OBS03_02
DECLARE @viejas NVARCHAR(MAX) = (
    SELECT STRING_AGG(CAST(l.nombre AS NVARCHAR(MAX)), ', ')
    FROM #obs03Lista l
    WHERE OBJECT_ID(N'dbo.' + QUOTENAME(l.nombre), N'P') IS NULL
       OR EXISTS (SELECT 1 FROM sys.parameters x WHERE x.object_id = OBJECT_ID(N'dbo.' + QUOTENAME(l.nombre), N'P') AND x.name = '@idCorrelacion'));
IF @viejas IS NOT NULL
BEGIN
    DECLARE @m2 NVARCHAR(2048) = CONCAT(N'TEST FAILED VAL_OBS03_02: entradas de la lista blanca que ya no existen o ya declaran @idCorrelacion: ', @viejas);
    THROW 55402, @m2, 1;
END;
PRINT 'TEST_PASS:VAL_OBS03_02_LISTA_SIN_ENTRADAS_VIEJAS';
GO

-- VAL_OBS03_03
DECLARE @escriben NVARCHAR(MAX) = NULL, @nombre SYSNAME;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT nombre FROM #obs03Lista WHERE clase IN ('LECTURA', 'CONTEXTO_SESION') ORDER BY nombre;
OPEN c;
FETCH NEXT FROM c INTO @nombre;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM sys.dm_sql_referenced_entities(N'dbo.' + QUOTENAME(@nombre), N'OBJECT') r
               WHERE r.is_updated = 1 AND r.referenced_entity_name NOT LIKE '#%')
        SET @escriben = CONCAT(@escriben, IIF(@escriben IS NULL, '', ', '), @nombre);
    FETCH NEXT FROM c INTO @nombre;
END;
CLOSE c;
DEALLOCATE c;
IF @escriben IS NOT NULL
BEGIN
    DECLARE @m3 NVARCHAR(2048) = CONCAT(N'TEST FAILED VAL_OBS03_03: procedimientos clasificados como de solo lectura que escriben tablas: ', @escriben);
    THROW 55403, @m3, 1;
END;
PRINT 'TEST_PASS:VAL_OBS03_03_LECTURA_NO_ESCRIBE';
GO

-- VAL_OBS03_04
DECLARE @expuestos NVARCHAR(MAX) = (
    SELECT STRING_AGG(CAST(l.nombre AS NVARCHAR(MAX)), ', ')
    FROM #obs03Lista l
    INNER JOIN sys.database_permissions dp ON dp.major_id = OBJECT_ID(N'dbo.' + QUOTENAME(l.nombre), N'P')
        AND dp.permission_name = 'EXECUTE' AND dp.state IN ('G', 'W')
    INNER JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id AND pr.name = 'rol_asistencias_runtime'
    WHERE l.clase = 'NUCLEO_MUTANTE');
DECLARE @huerfanos NVARCHAR(MAX) = (
    SELECT STRING_AGG(CAST(l.nombre AS NVARCHAR(MAX)), ', ')
    FROM #obs03Lista l
    WHERE l.clase = 'NUCLEO_MUTANTE'
      AND NOT EXISTS (SELECT 1
                      FROM sys.sql_expression_dependencies d
                      INNER JOIN sys.procedures caller ON caller.object_id = d.referencing_id
                      WHERE d.referenced_entity_name = l.nombre
                        AND EXISTS (SELECT 1 FROM sys.parameters x WHERE x.object_id = caller.object_id AND x.name = '@idCorrelacion')));
IF @expuestos IS NOT NULL OR @huerfanos IS NOT NULL
BEGIN
    DECLARE @m4 NVARCHAR(2048) = CONCAT(N'TEST FAILED VAL_OBS03_04: nucleos mutantes con EXECUTE para la aplicacion [', @expuestos,
        N'] o sin llamador con @idCorrelacion [', @huerfanos, N'].');
    THROW 55404, @m4, 1;
END;
PRINT 'TEST_PASS:VAL_OBS03_04_NUCLEOS_SIN_EXECUTE_Y_CON_LLAMADOR';
GO

IF OBJECT_ID('tempdb..#obs03Lista') IS NOT NULL DROP TABLE #obs03Lista;
IF @@TRANCOUNT <> 0
    THROW 55405, 'TEST FAILED VAL_OBS03_TRANCOUNT: transaccion abierta.', 1;
PRINT 'TEST_PASS:VAL_OBS03_TRANCOUNT_ZERO';
GO
