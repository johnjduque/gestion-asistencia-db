USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- ============================================================================
-- DEC-074 (2026-11-13): retiro de la carga masiva de usuarios por CSV (HU171, CULM-001 D.5), migracion 44.
--   DEC074_OBJETOS_RETIRADOS        no quedan el SP, la vista, la tabla, los parametros CARGA_MASIVA/*, su metadato de
--                                   edicion ni los mensajes CMA_*, y el rol runtime no tiene permisos sobre ellos.
--   DEC074_ALTA_INDIVIDUAL_INTACTA  siguen la alta individual (usp_crear_decano, usp_crear_coordinador,
--                                   usp_vincular_docente_programa) y el parametro IDENTIDAD/TIPO_IDENTIFICACION_DEFECTO.
-- Solo lectura.
-- ============================================================================
PRINT 'TEST START: test_dec074_retiro_carga_masiva';

IF OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_jerarquia_alta_usuario', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.JerarquiaAltaUsuario', N'U') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'CARGA_MASIVA')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro WHERE p.grupo = 'CARGA_MASIVA')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'CMA[_]___')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE 'CMA[_]___')
   OR EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name LIKE 'FK[_]JerarquiaAltaUsuario[_]%')
    THROW 54480, 'TEST FAILED: DEC074_OBJETOS_RETIRADOS quedan objetos, parametros o mensajes de la carga masiva.', 1;
PRINT 'TEST_PASS:DEC074_OBJETOS_RETIRADOS';

IF OBJECT_ID(N'dbo.usp_crear_decano', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_crear_coordinador', N'P') IS NULL
   OR OBJECT_ID(N'dbo.usp_vincular_docente_programa', N'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'IDENTIDAD' AND clave = 'TIPO_IDENTIFICACION_DEFECTO' AND estaActivo = 1)
   OR NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_crear_coordinador') AND name = N'@idTipoIdIdentificacion')
   OR NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_crear_decano') AND name = N'@idTipoIdIdentificacion')
    THROW 54481, 'TEST FAILED: DEC074_ALTA_INDIVIDUAL_INTACTA la alta individual debe seguir disponible.', 1;
PRINT 'TEST_PASS:DEC074_ALTA_INDIVIDUAL_INTACTA';

IF @@TRANCOUNT <> 0 THROW 54482, 'TEST FAILED: DEC074_TRANCOUNT_ZERO transaccion abierta.', 1;
PRINT 'TEST_PASS:DEC074_TRANCOUNT_ZERO';
PRINT 'TEST END: test_dec074_retiro_carga_masiva';
GO
