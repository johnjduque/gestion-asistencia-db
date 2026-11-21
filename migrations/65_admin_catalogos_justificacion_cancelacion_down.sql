-- ============================================================================
-- MIGRACION DOWN 65: retira la administracion de categorias de justificacion y motivos de cancelacion.
-- Retira los SP y la vista de administracion, restaura uv_categoria_justificacion sin el filtro de estado y elimina la columna
-- estaActivo. Desplegar ANTES el esquema de la version previa (deploy_schema.ps1): usp_internal_radicar_solicitud_revision de esta
-- version lee la columna que aqui se elimina; el down no conserva copias de SP. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 65 DOWN: retiro de la administracion de catalogos de justificacion y cancelacion';
GO
DROP PROCEDURE IF EXISTS dbo.usp_crear_categoria_justificacion;
DROP PROCEDURE IF EXISTS dbo.usp_actualizar_categoria_justificacion;
DROP PROCEDURE IF EXISTS dbo.usp_cambiar_estado_categoria_justificacion;
DROP PROCEDURE IF EXISTS dbo.usp_crear_motivo_cancelacion_sesion;
DROP PROCEDURE IF EXISTS dbo.usp_actualizar_motivo_cancelacion_sesion;
DROP PROCEDURE IF EXISTS dbo.usp_cambiar_estado_motivo_cancelacion_sesion;
DROP PROCEDURE IF EXISTS dbo.usp_validar_item_catalogo_interno;
DROP PROCEDURE IF EXISTS dbo.usp_validar_ejecutor_administrador_interno;
DROP VIEW IF EXISTS dbo.uv_categoria_justificacion_admin;
GO
CREATE OR ALTER VIEW [dbo].[uv_categoria_justificacion]
AS
SELECT  id, codigo, nombre, descripcion, requiereSoporte
FROM    dbo.CategoriaJustificacion
GO
IF COL_LENGTH('dbo.CategoriaJustificacion', 'estaActivo') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_CategoriaJustificacion_estaActivo')
        ALTER TABLE dbo.CategoriaJustificacion DROP CONSTRAINT DF_CategoriaJustificacion_estaActivo;
    ALTER TABLE dbo.CategoriaJustificacion DROP COLUMN estaActivo;
END
GO
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('CTG_001','CTG_002','CTG_003','CTG_004','CTG_005','CTG_006','CTG_007','CTG_008');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('CTG_001','CTG_002','CTG_003','CTG_004','CTG_005','CTG_006','CTG_007','CTG_008');
GO
PRINT 'MIGRACION 65 DOWN OK';
GO
