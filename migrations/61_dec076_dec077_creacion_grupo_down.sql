-- ============================================================================
-- MIGRACION DOWN 61: retira DEC-076 (PER_010) y DEC-077 (programa responsable del grupo). Los cuerpos anteriores de usp_crear_grupo,
-- usp_validar_gestion_grupo_coordinador_o_titular_interno, usp_validar_coordinador_sesion_interno,
-- usp_consultar_destinatarios_sesion_manual, usp_consultar_destinatarios_aviso_sin_toma y uv_solicitud_sesion se restauran
-- desplegando el esquema de la version previa (deploy_schema.ps1), como en la 56: el down no conserva copias de SP.
-- Desplegar ANTES de este down: los cuerpos nuevos leen la columna y la funcion que aqui se eliminan. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
PRINT 'MIGRACION 61 DOWN: retiro de PER_010 y del programa responsable del grupo';
GO
DROP FUNCTION IF EXISTS dbo.ufn_programas_grupo_responsable;
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Grupo_ProgramaResponsable')
    ALTER TABLE dbo.Grupo DROP CONSTRAINT FK_Grupo_ProgramaResponsable;
GO
IF COL_LENGTH('dbo.Grupo', 'programaResponsable') IS NOT NULL
    ALTER TABLE dbo.Grupo DROP COLUMN programaResponsable;
GO
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'PER_010';
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'PER_010';
GO
PRINT 'MIGRACION 61 DOWN OK';
GO
