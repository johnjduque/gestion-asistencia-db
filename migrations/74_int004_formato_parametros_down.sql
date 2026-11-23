-- ============================================================================
-- MIGRACION DOWN 74: retira el formato declarativo de parametros (INT-004). Idempotente.
--   Borra las filas NO editables que solo declaraban el formato, la restriccion CK_CPE_Formato, la columna CatalogoParametroEdicion.formato,
--   las funciones ufn_validar_formato_valor y ufn_es_cidr_valido y el mensaje PRM_017. Los SP usp_validar_valor_parametro_externo_interno y
--   usp_actualizar_parametro quedan referenciando la columna y la funcion retiradas hasta redesplegar schema/ de la version anterior.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
IF COL_LENGTH('dbo.CatalogoParametroEdicion', 'formato') IS NOT NULL
    EXEC sp_executesql N'DELETE FROM [dbo].[CatalogoParametroEdicion] WHERE [formato] IS NOT NULL AND [esEditable] = 0;
                         UPDATE [dbo].[CatalogoParametroEdicion] SET [formato] = NULL WHERE [formato] IS NOT NULL;';
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_CPE_Formato' AND parent_object_id = OBJECT_ID('dbo.CatalogoParametroEdicion'))
    ALTER TABLE [dbo].[CatalogoParametroEdicion] DROP CONSTRAINT [CK_CPE_Formato];
GO
IF COL_LENGTH('dbo.CatalogoParametroEdicion', 'formato') IS NOT NULL
    ALTER TABLE [dbo].[CatalogoParametroEdicion] DROP COLUMN [formato];
GO
IF OBJECT_ID(N'dbo.ufn_validar_formato_valor', N'FN') IS NOT NULL
    DROP FUNCTION [dbo].[ufn_validar_formato_valor];
GO
IF OBJECT_ID(N'dbo.ufn_es_cidr_valido', N'FN') IS NOT NULL
    DROP FUNCTION [dbo].[ufn_es_cidr_valido];
GO
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo = 'PRM_017';
GO
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo = 'PRM_017';
GO
PRINT 'MIGRACION 74 DOWN: completada';
GO
