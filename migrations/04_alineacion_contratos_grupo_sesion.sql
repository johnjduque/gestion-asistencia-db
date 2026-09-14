USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- ============================================================================
-- Migración incremental, aditiva e idempotente para instancias EXISTENTES.
-- deploy_schema.ps1 no ejecuta esta carpeta; debe correrse manualmente una vez
-- por instancia ya desplegada. Para instalaciones nuevas, schema/tables/Grupo.sql
-- y schema/tables/Sesion.sql ya incluyen estas columnas desde el CREATE TABLE.
--
-- Alcance:
--   1. dbo.Grupo.aula                (contrato publico usp_crear_grupo/usp_actualizar_grupo)
--   2. dbo.Sesion.descripcion/aula/tipo (contrato publico usp_crear_sesion/usp_actualizar_sesion)
--   3. Diagnostico y correccion puntual de Grupo.cantidadEstudiantes <= 0
--      generados por el bug historico de usp_crear_grupo (insertaba 0 fijo).
-- No se ejecuta ningun DROP/ALTER destructivo ni TRUNCATE/DELETE masivo.
-- ============================================================================

-- 1. dbo.Grupo.aula
IF COL_LENGTH('dbo.Grupo', 'aula') IS NULL
BEGIN
    ALTER TABLE dbo.Grupo
    ADD aula NVARCHAR(100) NULL;

    PRINT 'Migracion 04: columna dbo.Grupo.aula agregada.';
END
ELSE
BEGIN
    PRINT 'Migracion 04: columna dbo.Grupo.aula ya existia, sin cambios.';
END
GO

-- 2. dbo.Sesion.descripcion / aula / tipo
IF COL_LENGTH('dbo.Sesion', 'descripcion') IS NULL
BEGIN
    ALTER TABLE dbo.Sesion
    ADD descripcion NVARCHAR(MAX) NULL;

    PRINT 'Migracion 04: columna dbo.Sesion.descripcion agregada.';
END
ELSE
BEGIN
    PRINT 'Migracion 04: columna dbo.Sesion.descripcion ya existia, sin cambios.';
END
GO

IF COL_LENGTH('dbo.Sesion', 'aula') IS NULL
BEGIN
    ALTER TABLE dbo.Sesion
    ADD aula NVARCHAR(100) NULL;

    PRINT 'Migracion 04: columna dbo.Sesion.aula agregada.';
END
ELSE
BEGIN
    PRINT 'Migracion 04: columna dbo.Sesion.aula ya existia, sin cambios.';
END
GO

IF COL_LENGTH('dbo.Sesion', 'tipo') IS NULL
BEGIN
    ALTER TABLE dbo.Sesion
    ADD tipo NVARCHAR(50) NULL;

    PRINT 'Migracion 04: columna dbo.Sesion.tipo agregada.';
END
ELSE
BEGIN
    PRINT 'Migracion 04: columna dbo.Sesion.tipo ya existia, sin cambios.';
END
GO

-- 3. Diagnostico de grupos con capacidad <= 0 (secuela del bug historico de usp_crear_grupo)
DECLARE @gruposCapacidadInvalida INT;
SELECT @gruposCapacidadInvalida = COUNT(1) FROM dbo.Grupo WHERE cantidadEstudiantes <= 0;

PRINT CONCAT('Migracion 04: grupos con cantidadEstudiantes <= 0 detectados: ', @gruposCapacidadInvalida);

IF @gruposCapacidadInvalida > 0
BEGIN
    DECLARE @capacidadMaximaDefecto INT = TRY_CAST(dbo.ufn_obtener_parametro('GRUPO', 'CAPACIDAD_MAXIMA_DEFECTO') AS INT);

    IF @capacidadMaximaDefecto IS NOT NULL AND @capacidadMaximaDefecto > 0
    BEGIN
        UPDATE dbo.Grupo
        SET cantidadEstudiantes = @capacidadMaximaDefecto
        WHERE cantidadEstudiantes <= 0;

        PRINT CONCAT('Migracion 04: ', @gruposCapacidadInvalida, ' grupo(s) corregidos a capacidad por defecto (', @capacidadMaximaDefecto, '). Solo se modificaron registros con cantidadEstudiantes <= 0.');
    END
    ELSE
    BEGIN
        PRINT 'Migracion 04: ADVERTENCIA - no fue posible resolver GRUPO/CAPACIDAD_MAXIMA_DEFECTO; los grupos con capacidad <= 0 no fueron corregidos automaticamente.';
    END
END
GO
