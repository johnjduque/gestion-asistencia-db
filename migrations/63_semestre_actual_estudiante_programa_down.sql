-- ============================================================================
-- MIGRACION DOWN 63: retira el semestre actual del estudiante en el programa. El cuerpo anterior de
-- usp_consultar_directorio_estudiantes_paginado se restaura desplegando el esquema de la version previa (deploy_schema.ps1), como en la 56:
-- el down no conserva copias de SP. Desplegar ANTES de este down: los cuerpos nuevos leen la columna que aqui se elimina. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
PRINT 'MIGRACION 63 DOWN: retiro del semestre actual del estudiante en el programa';
GO
DROP PROCEDURE IF EXISTS dbo.usp_actualizar_semestre_estudiante_programa;
GO
IF COL_LENGTH('dbo.EstudiantePrograma', 'semestreActual') IS NOT NULL
    ALTER TABLE dbo.EstudiantePrograma DROP COLUMN semestreActual;
GO
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('EST_007', 'EST_008', 'EST_009');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('EST_007', 'EST_008', 'EST_009');
GO
PRINT 'MIGRACION 63 DOWN OK';
GO
