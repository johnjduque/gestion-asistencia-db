USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;

-- VAL ROL-05 (decision de John, 2026-11-12; migracion 39): retiro del alta de usuarios sin ambito.
--   POST /api/v1/usuarios se retiro del backend y con el su unico llamador del SP publico dbo.usp_sincronizar_usuario.
--   VAL_ROL05_01: el SP publico ya no existe.
--   VAL_ROL05_02: rol_asistencias_runtime no conserva permisos sobre ese nombre y sigue con DENY EXECUTE sobre el nucleo interno.
--   VAL_ROL05_03: el nucleo dbo.usp_sincronizar_usuario_interno sigue existiendo con su contrato OUTPUT.
--   VAL_ROL05_04: los altas con ambito siguen usando el nucleo y ningun modulo de la BD llama al SP publico retirado.
-- Solo lectura de metadatos: no escribe datos. Cada verificacion va en su propio lote.
PRINT 'TEST START: test_val_retiro_alta_usuarios_sin_ambito (VAL ROL-05)';
GO

IF OBJECT_ID(N'dbo.usp_sincronizar_usuario', N'P') IS NOT NULL
    THROW 53910, 'TEST FAILED VAL_ROL05_01: dbo.usp_sincronizar_usuario sigue existiendo (falta la migracion 39).', 1;
PRINT 'TEST_PASS:VAL_ROL05_01_SP_PUBLICO_RETIRADO';
GO

IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    THROW 53911, 'TEST FAILED VAL_ROL05_02: falta rol_asistencias_runtime.', 1;
IF EXISTS (
    SELECT 1
    FROM sys.database_permissions dp
    WHERE dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
      AND dp.class = 1
      AND OBJECT_NAME(dp.major_id) = N'usp_sincronizar_usuario'
)
    THROW 53912, 'TEST FAILED VAL_ROL05_02: rol_asistencias_runtime conserva permisos sobre usp_sincronizar_usuario.', 1;
IF NOT EXISTS (
    SELECT 1
    FROM sys.database_permissions dp
    WHERE dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')
      AND dp.class = 1
      AND dp.major_id = OBJECT_ID(N'dbo.usp_sincronizar_usuario_interno')
      AND dp.permission_name = N'EXECUTE'
      AND dp.state = 'D'
)
    THROW 53913, 'TEST FAILED VAL_ROL05_02: falta el DENY EXECUTE de rol_asistencias_runtime sobre usp_sincronizar_usuario_interno.', 1;
PRINT 'TEST_PASS:VAL_ROL05_02_SIN_PERMISO_RUNTIME';
GO

IF OBJECT_ID(N'dbo.usp_sincronizar_usuario_interno', N'P') IS NULL
    THROW 53914, 'TEST FAILED VAL_ROL05_03: falta dbo.usp_sincronizar_usuario_interno (no debia tocarse).', 1;
IF (SELECT COUNT(*) FROM sys.parameters
    WHERE object_id = OBJECT_ID(N'dbo.usp_sincronizar_usuario_interno') AND is_output = 1
      AND name IN (N'@mensajeUsuarioResultado', N'@mensajeTecnicoResultado', N'@estadoResultado')) <> 3
    THROW 53915, 'TEST FAILED VAL_ROL05_03: usp_sincronizar_usuario_interno cambio su contrato OUTPUT.', 1;
PRINT 'TEST_PASS:VAL_ROL05_03_NUCLEO_INTERNO_INTACTO';
GO

DECLARE @faltantes NVARCHAR(4000) = (
    SELECT STRING_AGG(f.nombre, N', ')
    FROM (VALUES (N'usp_crear_decano_interno'), (N'usp_crear_coordinador_interno'), (N'usp_vincular_docente_programa'),
                 (N'usp_admitir_estudiante'), (N'usp_registrar_estudiante_en_grupo'), (N'usp_internal_matricular_por_token')) f (nombre)
    WHERE OBJECT_ID(N'dbo.' + f.nombre, N'P') IS NULL
       OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + f.nombre, N'P')) NOT LIKE N'%usp_sincronizar_usuario_interno%'
);
IF @faltantes IS NOT NULL
    THROW 53916, 'TEST FAILED VAL_ROL05_04: un alta con ambito ya no existe o no usa usp_sincronizar_usuario_interno.', 1;
DECLARE @llamadores NVARCHAR(4000) = (
    SELECT STRING_AGG(OBJECT_NAME(m.object_id), N', ')
    FROM sys.sql_modules m
    WHERE OBJECT_SCHEMA_NAME(m.object_id) = N'dbo'
      AND OBJECT_NAME(m.object_id) <> N'usp_sincronizar_usuario'
      AND REPLACE(m.definition, N'usp_sincronizar_usuario_interno', N'') LIKE N'%usp[_]sincronizar[_]usuario%'
);
IF @llamadores IS NOT NULL
BEGIN
    DECLARE @mensaje NVARCHAR(2048) = CONCAT(N'TEST FAILED VAL_ROL05_04: modulos que aun llaman a usp_sincronizar_usuario: ', @llamadores);
    THROW 53917, @mensaje, 1;
END
PRINT 'TEST_PASS:VAL_ROL05_04_ALTAS_CON_AMBITO_USAN_EL_NUCLEO';
GO

IF @@TRANCOUNT <> 0
    THROW 53919, 'TEST FAILED VAL_ROL05: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:VAL_ROL05_TRANCOUNT_ZERO';
GO
