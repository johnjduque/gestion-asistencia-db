-- ============================================================================
-- MIGRACION UP 78: SKILLS-BD lote 2 (decision D3 de John, 2026-11-25): retiro de los 16 nucleos usp_internal_* renombrados a
--   usp_<nombre>_interno (convencion de nombres de las skills de BD). Los nombres nuevos, sus llamadores y los DENY del rol de runtime
--   los despliega deploy_schema.ps1 (schema/stored-procedures y schema/security). Para que la base quede coherente aunque la migracion corra
--   ANTES del despliegue (orden del runbook docs/runbooks/ACTUALIZAR_BD_LOCAL_EXISTENTE.md), el up:
--     1. crea cada nombre nuevo que falte como copia del viejo (misma firma y cuerpo; solo cambian los nombres) con DENY EXECUTE al runtime;
--     2. recompila (CREATE OR ALTER, conserva permisos) todo modulo cuya definicion todavia llame a un nombre viejo, con el nombre nuevo;
--     3. borra los 16 nombres viejos.
--   Sobre una base ya desplegada desde schema/ (los nombres nuevos ya existen y nadie llama a los viejos) solo hace el paso 3.
--   Las menciones historicas "antes usp_internal_..." de los comentarios no se tocan. deploy_schema.ps1 despues deja los cuerpos del lote 2.
--   Mapa: usp_internal_<x> -> usp_<x>_interno para x en aplicar_festivos_grupo, aplicar_festivos_grupos, asegurar_estudiante_programa_grupo,
--   asociar_asignatura_plan, cancelar_sesiones_receso, cargar_dias_festivos, cerrar_toma, marcar_ausentes_toma, matricular_por_token,
--   radicar_solicitud_revision, reactivar_matricula_retirada, resolver_token_asistencia, resolver_token_matricula, rotar_token_asistencia,
--   rotar_token_matricula, validar_plazo_justificacion.
-- Sin cambios de tablas ni de datos. Idempotente. Down: 78_skills_lote2_renombre_internos_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 78 UP: retiro de los nucleos usp_internal_* (renombrados a usp_*_interno)';
GO
DECLARE @mapa TABLE (orden INT NOT NULL PRIMARY KEY, viejo SYSNAME NOT NULL, nuevo SYSNAME NOT NULL);
DECLARE @modulos TABLE (orden INT IDENTITY(1, 1) PRIMARY KEY, idObjeto INT NOT NULL);
DECLARE @orden INT;
DECLARE @ordenNombre INT;
DECLARE @viejo SYSNAME;
DECLARE @nuevo SYSNAME;
DECLARE @definicion NVARCHAR(MAX);
DECLARE @sentencia NVARCHAR(400);
DECLARE @original NVARCHAR(MAX);
DECLARE @posicion INT;
DECLARE @inicio INT;
DECLARE @resto NVARCHAR(4);
DECLARE @mensaje NVARCHAR(2048);

-- Mapa (el mas largo primero: usp_internal_aplicar_festivos_grupos antes que usp_internal_aplicar_festivos_grupo)
INSERT INTO @mapa (orden, viejo, nuevo)
SELECT ROW_NUMBER() OVER (ORDER BY LEN(n.nombre) DESC, n.nombre), CONCAT(N'usp_internal_', n.nombre), CONCAT(N'usp_', n.nombre, N'_interno')
FROM (VALUES
    (N'aplicar_festivos_grupo'), (N'aplicar_festivos_grupos'), (N'asegurar_estudiante_programa_grupo'), (N'asociar_asignatura_plan'),
    (N'cancelar_sesiones_receso'), (N'cargar_dias_festivos'), (N'cerrar_toma'), (N'marcar_ausentes_toma'), (N'matricular_por_token'),
    (N'radicar_solicitud_revision'), (N'reactivar_matricula_retirada'), (N'resolver_token_asistencia'), (N'resolver_token_matricula'),
    (N'rotar_token_asistencia'), (N'rotar_token_matricula'), (N'validar_plazo_justificacion')) n (nombre);

-- PASO 1: nombre nuevo que falte = copia del viejo con los nombres cambiados
SELECT @orden = MIN(orden) FROM @mapa;
WHILE @orden IS NOT NULL
BEGIN
    SELECT @viejo = viejo, @nuevo = nuevo FROM @mapa WHERE orden = @orden;
    SET @definicion = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + QUOTENAME(@viejo), N'P'));
    IF OBJECT_ID(N'dbo.' + QUOTENAME(@nuevo), N'P') IS NULL AND @definicion IS NOT NULL
    BEGIN
        SET @definicion = REPLACE(@definicion, N'antes usp_internal_', N'ZZ78ANTESZZ');
        SELECT @ordenNombre = MIN(orden) FROM @mapa;
        WHILE @ordenNombre IS NOT NULL
        BEGIN
            SELECT @definicion = REPLACE(@definicion, m.viejo, m.nuevo) FROM @mapa m WHERE m.orden = @ordenNombre;
            SELECT @ordenNombre = MIN(orden) FROM @mapa WHERE orden > @ordenNombre;
        END
        SET @definicion = REPLACE(@definicion, N'ZZ78ANTESZZ', N'antes usp_internal_');
        -- El motor guarda CREATE OR ALTER como CREATE seguido de espacios: se ubica el primer CREATE seguido solo de espacios
        -- y de PROC/VIEW/FUNCTION/TRIGGER y se vuelve CREATE OR ALTER (recompila conservando los permisos)
        SET @posicion = 0;
        SET @inicio = CHARINDEX(N'CREATE', @definicion);
        WHILE @posicion = 0 AND @inicio > 0
        BEGIN
            SET @resto = LEFT(TRIM(NCHAR(32) + NCHAR(9) + NCHAR(13) + NCHAR(10) FROM SUBSTRING(@definicion, @inicio + 6, 400)), 4);
            IF SUBSTRING(@definicion, @inicio + 6, 1) IN (NCHAR(32), NCHAR(9), NCHAR(13), NCHAR(10)) AND @resto IN (N'PROC', N'VIEW', N'FUNC', N'TRIG')
            BEGIN
                SET @posicion = @inicio;
            END
            ELSE
            BEGIN
                SET @inicio = CHARINDEX(N'CREATE', @definicion, @inicio + 6);
            END
        END
        IF @posicion = 0
        BEGIN
            SET @mensaje = CONCAT(N'MIGRACION 78: no se encontro el CREATE de ', @viejo);
            THROW 57880, @mensaje, 1;
        END
        SET @definicion = STUFF(@definicion, @posicion, 6, N'CREATE OR ALTER');
        EXEC sys.sp_executesql @definicion;
        IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
        BEGIN
            SET @sentencia = CONCAT(N'DENY EXECUTE ON [dbo].', QUOTENAME(@nuevo), N' TO [rol_asistencias_runtime];');
            EXEC sys.sp_executesql @sentencia;
        END
        PRINT CONCAT(N'MIGRACION 78: creado ', @nuevo, N' como copia de ', @viejo);
    END
    SELECT @orden = MIN(orden) FROM @mapa WHERE orden > @orden;
END

-- PASO 2: modulos que todavia llaman a un nombre viejo (fuera de los viejos, que se borran en el PASO 3)
INSERT INTO @modulos (idObjeto)
SELECT sm.object_id
FROM sys.sql_modules sm
INNER JOIN sys.objects o ON o.object_id = sm.object_id
WHERE o.schema_id = SCHEMA_ID(N'dbo')
  AND REPLACE(sm.definition, N'antes usp_internal_', N'') LIKE N'%usp[_]internal[_]%'
  AND NOT EXISTS (SELECT 1 FROM @mapa m WHERE m.viejo = o.name);
SELECT @orden = MIN(orden) FROM @modulos;
WHILE @orden IS NOT NULL
BEGIN
    SELECT @original = OBJECT_DEFINITION(idObjeto), @viejo = OBJECT_NAME(idObjeto) FROM @modulos WHERE orden = @orden;
    SET @definicion = REPLACE(@original, N'antes usp_internal_', N'ZZ78ANTESZZ');
    SELECT @ordenNombre = MIN(orden) FROM @mapa;
    WHILE @ordenNombre IS NOT NULL
    BEGIN
        SELECT @definicion = REPLACE(@definicion, m.viejo, m.nuevo) FROM @mapa m WHERE m.orden = @ordenNombre;
        SELECT @ordenNombre = MIN(orden) FROM @mapa WHERE orden > @ordenNombre;
    END
    SET @definicion = REPLACE(@definicion, N'ZZ78ANTESZZ', N'antes usp_internal_');
    IF @definicion <> @original
    BEGIN
        -- El motor guarda CREATE OR ALTER como CREATE seguido de espacios: se ubica el primer CREATE seguido solo de espacios
        -- y de PROC/VIEW/FUNCTION/TRIGGER y se vuelve CREATE OR ALTER (recompila conservando los permisos)
        SET @posicion = 0;
        SET @inicio = CHARINDEX(N'CREATE', @definicion);
        WHILE @posicion = 0 AND @inicio > 0
        BEGIN
            SET @resto = LEFT(TRIM(NCHAR(32) + NCHAR(9) + NCHAR(13) + NCHAR(10) FROM SUBSTRING(@definicion, @inicio + 6, 400)), 4);
            IF SUBSTRING(@definicion, @inicio + 6, 1) IN (NCHAR(32), NCHAR(9), NCHAR(13), NCHAR(10)) AND @resto IN (N'PROC', N'VIEW', N'FUNC', N'TRIG')
            BEGIN
                SET @posicion = @inicio;
            END
            ELSE
            BEGIN
                SET @inicio = CHARINDEX(N'CREATE', @definicion, @inicio + 6);
            END
        END
        IF @posicion = 0
        BEGIN
            SET @mensaje = CONCAT(N'MIGRACION 78: no se encontro el CREATE de ', @viejo);
            THROW 57881, @mensaje, 1;
        END
        SET @definicion = STUFF(@definicion, @posicion, 6, N'CREATE OR ALTER');
        EXEC sys.sp_executesql @definicion;
        PRINT CONCAT(N'MIGRACION 78: recompilado ', @viejo, N' con los nombres nuevos');
    END
    SELECT @orden = MIN(orden) FROM @modulos WHERE orden > @orden;
END
GO

-- PASO 3: retiro de los nombres viejos
DROP PROCEDURE IF EXISTS dbo.usp_internal_aplicar_festivos_grupo;
DROP PROCEDURE IF EXISTS dbo.usp_internal_aplicar_festivos_grupos;
DROP PROCEDURE IF EXISTS dbo.usp_internal_asegurar_estudiante_programa_grupo;
DROP PROCEDURE IF EXISTS dbo.usp_internal_asociar_asignatura_plan;
DROP PROCEDURE IF EXISTS dbo.usp_internal_cancelar_sesiones_receso;
DROP PROCEDURE IF EXISTS dbo.usp_internal_cargar_dias_festivos;
DROP PROCEDURE IF EXISTS dbo.usp_internal_cerrar_toma;
DROP PROCEDURE IF EXISTS dbo.usp_internal_marcar_ausentes_toma;
DROP PROCEDURE IF EXISTS dbo.usp_internal_matricular_por_token;
DROP PROCEDURE IF EXISTS dbo.usp_internal_radicar_solicitud_revision;
DROP PROCEDURE IF EXISTS dbo.usp_internal_reactivar_matricula_retirada;
DROP PROCEDURE IF EXISTS dbo.usp_internal_resolver_token_asistencia;
DROP PROCEDURE IF EXISTS dbo.usp_internal_resolver_token_matricula;
DROP PROCEDURE IF EXISTS dbo.usp_internal_rotar_token_asistencia;
DROP PROCEDURE IF EXISTS dbo.usp_internal_rotar_token_matricula;
DROP PROCEDURE IF EXISTS dbo.usp_internal_validar_plazo_justificacion;
GO
PRINT 'MIGRACION 78 UP: OK';
GO
