-- ============================================================================
-- MIGRACION UP 50: MEJORAS-SERGIO-2026-11-18 (items 1 y 12) - retiro del tipo de vinculacion del docente
--   Orden de John (2026-11-18): "hay que ejecutar todas esas mejoras y cambios". El sistema no administra el tipo de vinculacion
--   (planta, medio tiempo, catedra, ocasional) del docente con el programa; se retira de todas las capas.
--   1. FK_DocentePrograma_TipoVinculacion, cualquier DEFAULT de la columna y la columna DocentePrograma.tipoVinculacion.
--   2. La vista uv_tipo_vinculacion y la tabla TipoVinculacion (con sus filas).
--   3. El parametro DOCENTE/TIPO_VINCULACION_DEFECTO (con su historial y su fila de edicion, si las hubiera). Si la fila de
--      edicion de OTRO parametro lo referencia como regla cruzada (parametroDebeSerMenorQue, FK_CatalogoParametroEdicion_MenorQue),
--      esa regla se anula (NULL) y la fila se conserva: el otro parametro sigue siendo editable, solo pierde la comparacion
--      contra un parametro que ya no existe.
--   4. Los mensajes DOC_004 (usuario y tecnico) y ERR_TIPO_VINCULACION_INVALIDO (codigo del backend, usuario y tecnico).
--   Los cuerpos nuevos de vistas y SP (uv_docente_programa, uv_auth_docente_programa, usp_vincular_docente_programa(_interno),
--   usp_actualizar_docente_programa, usp_consultar_docentes_programa, usp_consultar_resumen_docentes_programa,
--   usp_consultar_perfil_usuario y usp_consultar_estudiantes_facultad_paginado, que ademas agrega codigoTipoIdentificacion, item 5)
--   se despliegan con deploy_schema.ps1 (CREATE OR ALTER), como en la 48 y la 49: dependen de vistas que otras ramas cambiaron
--   solo por despliegue. Entre esta migracion y el despliegue, las vistas y SP viejos que leian el tipo quedan invalidos: el
--   despliegue es obligatorio (docs/runbooks/ACTUALIZAR_BD_LOCAL_EXISTENTE.md). Los vinculos docente-programa se conservan.
-- Idempotente. Down: 50_mejoras_sergio_retiro_tipo_vinculacion_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 50 UP: MEJORAS-SERGIO retiro del tipo de vinculacion del docente';
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DocentePrograma_TipoVinculacion')
    ALTER TABLE [dbo].[DocentePrograma] DROP CONSTRAINT [FK_DocentePrograma_TipoVinculacion];
GO
DECLARE @df SYSNAME = (SELECT dc.name FROM sys.default_constraints dc
                       INNER JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
                       WHERE dc.parent_object_id = OBJECT_ID(N'dbo.DocentePrograma') AND c.name = N'tipoVinculacion');
IF @df IS NOT NULL
BEGIN
    DECLARE @sqlDf NVARCHAR(400) = N'ALTER TABLE [dbo].[DocentePrograma] DROP CONSTRAINT ' + QUOTENAME(@df) + N';';
    EXEC sys.sp_executesql @sqlDf;
END
GO
IF COL_LENGTH(N'dbo.DocentePrograma', N'tipoVinculacion') IS NOT NULL
    ALTER TABLE [dbo].[DocentePrograma] DROP COLUMN [tipoVinculacion];
GO
IF OBJECT_ID(N'dbo.uv_tipo_vinculacion', N'V') IS NOT NULL
    DROP VIEW [dbo].[uv_tipo_vinculacion];
GO
IF OBJECT_ID(N'dbo.TipoVinculacion', N'U') IS NOT NULL
    DROP TABLE [dbo].[TipoVinculacion];
GO
DELETE c FROM dbo.CambioParametro c
INNER JOIN dbo.CatalogoParametro p ON p.id = c.parametro
WHERE p.grupo = 'DOCENTE' AND p.clave = 'TIPO_VINCULACION_DEFECTO';
UPDATE e SET e.parametroDebeSerMenorQue = NULL
FROM dbo.CatalogoParametroEdicion e
INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametroDebeSerMenorQue
WHERE p.grupo = 'DOCENTE' AND p.clave = 'TIPO_VINCULACION_DEFECTO';
DELETE e FROM dbo.CatalogoParametroEdicion e
INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
WHERE p.grupo = 'DOCENTE' AND p.clave = 'TIPO_VINCULACION_DEFECTO';
DELETE FROM dbo.CatalogoParametro WHERE grupo = 'DOCENTE' AND clave = 'TIPO_VINCULACION_DEFECTO';
GO
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('DOC_004', 'ERR_TIPO_VINCULACION_INVALIDO');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('DOC_004', 'ERR_TIPO_VINCULACION_INVALIDO');
GO
IF OBJECT_ID(N'dbo.TipoVinculacion', N'U') IS NOT NULL OR OBJECT_ID(N'dbo.uv_tipo_vinculacion', N'V') IS NOT NULL
   OR COL_LENGTH(N'dbo.DocentePrograma', N'tipoVinculacion') IS NOT NULL
   OR EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DocentePrograma_TipoVinculacion')
    THROW 55091, 'MIGRACION 50: quedaron objetos del tipo de vinculacion.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'DOCENTE' AND clave = 'TIPO_VINCULACION_DEFECTO')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('DOC_004', 'ERR_TIPO_VINCULACION_INVALIDO'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('DOC_004', 'ERR_TIPO_VINCULACION_INVALIDO'))
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e
              WHERE NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro p WHERE p.id = e.parametro)
                 OR (e.parametroDebeSerMenorQue IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro p WHERE p.id = e.parametroDebeSerMenorQue)))
    THROW 55092, 'MIGRACION 50: quedaron el parametro o los mensajes del tipo de vinculacion.', 1;
IF OBJECT_ID(N'dbo.DocentePrograma', N'U') IS NULL
    THROW 55093, 'MIGRACION 50: los vinculos docente-programa deben conservarse.', 1;
GO
PRINT 'MIGRACION 50 UP OK (ejecute deploy_schema.ps1 para los cuerpos de vistas y SP)';
GO
