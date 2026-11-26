USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 16 (2026-11-26): correcciones del code review de la rama refactor/skills-bd y de develop
-- (informes/CODE_REVIEW_RAMA_SKILLS-BD_2026-11-26.md).
--   SKL16_S01_VISTAS_INTERNAS_SIN_SELECT  las 32 vistas finas internas tienen DENY SELECT para rol_asistencias_runtime y el resto de
--                                         vistas uv_* conserva su GRANT (el backend sigue leyendo las suyas, excepcion E3)
--   SKL16_S02_VISTAS_INTERNAS_EN_SP       los SP siguen leyendo una vista negada (encadenamiento de propiedad): un SP de lectura que usa
--                                         uv_sesion_cancelacion responde igual
--   SKL16_M01_MENSAJE_CODIGO_NULO         usp_obtener_mensaje_catalogo con codigo NULL devuelve DBCODE=DESCONOCIDO aunque falte
--                                         GENERAL/CADENA_VACIA (transaccion revertida)
--   SKL16_T01_TOKEN_RELANZA_CONDENADA     los 4 SP publicos de token relanzan el error si la transaccion del llamador quedo condenada
--   SKL16_A01_QR_REVIERTE_FALLO           usp_registrar_asistencia_por_token ya no confirma lo escrito cuando el registro falla y vuelve al
--                                         punto de guardado con transaccion del llamador; TOP 1 de la matricula con ORDER BY
--   SKL16_B01_CIERRE_SIN_BLOQUEOS_NUEVOS  usp_marcar_ausentes_toma_interno solo bloquea lo que bloqueaba antes del lote 2 (3 UPDLOCK) y
--                                         usp_cerrar_tomas_vencidas decide la cancelacion por uv_sesion_cancelacion
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote16_correcciones';

DECLARE @internas TABLE (nombre SYSNAME PRIMARY KEY);
INSERT INTO @internas (nombre) VALUES (N'uv_administrador_registro'), (N'uv_archivo_soporte_registro'), (N'uv_asignatura_registro'), (N'uv_asistencia_registro'), (N'uv_aviso_falta_sesion'), (N'uv_aviso_sesion_sin_toma'), (N'uv_decano_rol'), (N'uv_detalle_asistencia_registro'), (N'uv_estado_notificacion'), (N'uv_estudiante_grupo_registro'), (N'uv_estudiante_programa_registro'), (N'uv_estudiante_programa_semestre'), (N'uv_evaluacion_alerta_grupo'), (N'uv_facultad_registro'), (N'uv_grupo_registro'), (N'uv_horario_registro'), (N'uv_notificacion_saliente'), (N'uv_parametro_edicion_registro'), (N'uv_parametro_registro'), (N'uv_periodo_academico_fechas'), (N'uv_programa_registro'), (N'uv_receso_academico_registro'), (N'uv_revision_cancelacion_registro'), (N'uv_sesion_cancelacion'), (N'uv_sesion_procedencia_clasificacion_registro'), (N'uv_sesion_registro'), (N'uv_sincronizacion_parametro_externo_registro'), (N'uv_solicitud_revision_asistencia_registro'), (N'uv_solicitud_sesion_registro'), (N'uv_token_matricula_grupo_registro'), (N'uv_token_verificacion_correo'), (N'uv_toma_asistencia_registro');
IF EXISTS (
    SELECT 1 FROM @internas i
    WHERE NOT EXISTS (SELECT 1 FROM sys.database_permissions dp
                      WHERE dp.major_id = OBJECT_ID(N'dbo.' + i.nombre, N'V') AND dp.permission_name = N'SELECT' AND dp.state = 'D'
                        AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
)
   OR EXISTS (
    SELECT 1 FROM sys.views v
    WHERE v.schema_id = SCHEMA_ID(N'dbo') AND v.name LIKE N'uv[_]%'
      AND NOT EXISTS (SELECT 1 FROM @internas i WHERE i.nombre = v.name)
      AND v.name <> N'uv_periodo_academico_cierre'   -- revocada por SES-GEN-01 (zz_rol_asistencias_runtime_ses_gen_01.sql)
      AND NOT EXISTS (SELECT 1 FROM sys.database_permissions dp
                      WHERE dp.major_id = v.object_id AND dp.permission_name = N'SELECT' AND dp.state IN ('G', 'W')
                        AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
)
    THROW 53060, 'TEST FAILED: SKL16_S01_VISTAS_INTERNAS_SIN_SELECT (una vista interna sin DENY o una vista del backend sin GRANT)', 1;
PRINT 'TEST_PASS:SKL16_S01_VISTAS_INTERNAS_SIN_SELECT';
GO

-- El SP se ejecuta con un usuario sin login del rol runtime: lee uv_sesion_cancelacion (negada) por encadenamiento de propiedad
IF DATABASE_PRINCIPAL_ID(N'skl16_runtime_prueba') IS NOT NULL DROP USER [skl16_runtime_prueba];
CREATE USER [skl16_runtime_prueba] WITHOUT LOGIN;
ALTER ROLE [rol_asistencias_runtime] ADD MEMBER [skl16_runtime_prueba];
GO
DECLARE @okDirecto BIT = 0, @okSp BIT = 0;
EXECUTE AS USER = N'skl16_runtime_prueba';
BEGIN TRY
    DECLARE @n INT = (SELECT COUNT(*) FROM dbo.uv_sesion_cancelacion);
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229 SET @okDirecto = 1;   -- SELECT permission was denied
END CATCH
BEGIN TRY
    DECLARE @r TABLE (idToma UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, totalAusentesMarcados INT);
    BEGIN TRANSACTION;
    INSERT INTO @r EXEC dbo.usp_cerrar_tomas_vencidas @idCorrelacion = '16161616-0000-4000-8000-000000000001';
    ROLLBACK TRANSACTION;
    SET @okSp = 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH
REVERT;
ALTER ROLE [rol_asistencias_runtime] DROP MEMBER [skl16_runtime_prueba];
DROP USER [skl16_runtime_prueba];
IF @okDirecto = 0 OR @okSp = 0
BEGIN
    DECLARE @m NVARCHAR(2048) = CONCAT(N'TEST FAILED: SKL16_S02_VISTAS_INTERNAS_EN_SP (directo negado=', @okDirecto, N', SP=', @okSp, N')');
    THROW 53061, @m, 1;
END
PRINT 'TEST_PASS:SKL16_S02_VISTAS_INTERNAS_EN_SP';
GO

BEGIN TRANSACTION;
UPDATE dbo.CatalogoParametro SET clave = N'CADENA_VACIA_SKL16' WHERE grupo = 'GENERAL' AND clave = 'CADENA_VACIA';
DECLARE @u NVARCHAR(4000), @t NVARCHAR(4000);
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = NULL, @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t OUTPUT;
DECLARE @t2 NVARCHAR(4000);
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = '  GEN_002  ', @p_param1 = N'x', @mensajeUsuarioResultado = @u OUTPUT, @mensajeTecnicoResultado = @t2 OUTPUT;
ROLLBACK TRANSACTION;
IF @t IS NULL OR @t NOT LIKE N'DBCODE=DESCONOCIDO|%' OR @t2 IS NULL OR @t2 NOT LIKE N'DBCODE=GEN[_]002|%'
BEGIN
    DECLARE @m NVARCHAR(2048) = LEFT(CONCAT(N'TEST FAILED: SKL16_M01_MENSAJE_CODIGO_NULO ', @t, N' / ', @t2), 2048);
    THROW 53062, @m, 1;
END
PRINT 'TEST_PASS:SKL16_M01_MENSAJE_CODIGO_NULO';
GO

IF EXISTS (
    SELECT 1 FROM (VALUES (N'usp_matricular_estudiante_por_token'), (N'usp_registrar_estudiante_por_token_publico'),
                          (N'usp_rotar_token_matricula_grupo'), (N'usp_rotar_token_matricula_automatico')) s(nombre)
    WHERE OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + s.nombre, N'P')) NOT LIKE N'%BEGIN CATCH%IF XACT_STATE() = -1 AND @@TRANCOUNT > 0%THROW;%SYS[_]001%'
)
    THROW 53063, 'TEST FAILED: SKL16_T01_TOKEN_RELANZA_CONDENADA (un SP de token no relanza con la transaccion del llamador condenada)', 1;
PRINT 'TEST_PASS:SKL16_T01_TOKEN_RELANZA_CONDENADA';
GO

DECLARE @d NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_registrar_asistencia_por_token', N'P'));
DECLARE @ds NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_sincronizar_asistencia_estudiante_interno', N'P'));
IF @d LIKE N'%AND @detalleCreado = 1%'
   OR @d NOT LIKE N'%ELSE IF @savepointCreado = 1 AND @escrituraIntentada = 1 AND @estadoResultado = 0 AND XACT_STATE() = 1%ROLLBACK TRANSACTION sp_asistencia_por_token;%'
   OR @d NOT LIKE N'%e.codigo = @codigoActiva%ORDER BY eg.id;%'
   OR @ds NOT LIKE N'%eeg.codigo = ''A''%ORDER BY eg.id;%'
    THROW 53064, 'TEST FAILED: SKL16_A01_QR_REVIERTE_FALLO (confirmacion parcial o TOP 1 sin ORDER BY)', 1;
-- Rechazo de negocio con transaccion del llamador: la transaccion sigue abierta y utilizable (se volvio al punto de guardado)
DECLARE @est UNIQUEIDENTIFIER = (SELECT TOP 1 e.usuario FROM dbo.Estudiante e ORDER BY e.id);
IF @est IS NOT NULL
BEGIN
    DECLARE @r TABLE (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT, idToma UNIQUEIDENTIFIER,
                      idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(200), nombreGrupo NVARCHAR(300),
                      numeroSesion INT, numeroToma SMALLINT, yaRegistrado BIT, fechaRegistroUtc DATETIME2(0));
    BEGIN TRANSACTION;
    INSERT INTO @r EXEC dbo.usp_registrar_asistencia_por_token @pin = N'000000', @idCorrelacion = '16161616-0000-4000-8000-000000000002',
        @idUsuarioEjecutor = @est;
    IF @@TRANCOUNT <> 1 OR XACT_STATE() <> 1 OR (SELECT estado FROM @r) <> 0
    BEGIN
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW 53065, 'TEST FAILED: SKL16_A01_QR_REVIERTE_FALLO (el rechazo con transaccion del llamador la dejo inutilizable)', 1;
    END
    ROLLBACK TRANSACTION;
END
PRINT 'TEST_PASS:SKL16_A01_QR_REVIERTE_FALLO';
GO

DECLARE @m NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_marcar_ausentes_toma_interno', N'P'));
DECLARE @c NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_cerrar_tomas_vencidas', N'P'));
IF (LEN(@m) - LEN(REPLACE(@m, N'WITH (UPDLOCK, HOLDLOCK)', N''))) / LEN(N'WITH (UPDLOCK, HOLDLOCK)') <> 3
   OR @c NOT LIKE N'%@cancelada = IIF(EXISTS (SELECT 1 FROM dbo.uv_sesion_cancelacion sc WHERE sc.idSesion = @idSesion), 1, 0)%'
    THROW 53066, 'TEST FAILED: SKL16_B01_CIERRE_SIN_BLOQUEOS_NUEVOS', 1;
PRINT 'TEST_PASS:SKL16_B01_CIERRE_SIN_BLOQUEOS_NUEVOS';
GO
PRINT 'TEST END: test_skills_lote16_correcciones';
GO
