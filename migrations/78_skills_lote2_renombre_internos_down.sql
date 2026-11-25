-- ============================================================================
-- MIGRACION DOWN 78: vuelve a crear los 16 nombres usp_internal_* como copia del nucleo renombrado (misma definicion; solo cambia el
--   nombre del CREATE) cuando el nombre viejo no existe y el nuevo si. No borra los usp_*_interno ni toca los llamadores: para volver al
--   codigo anterior al lote 2 se despliega schema/ del commit anterior con deploy_schema.ps1 (que tambien recompila los nombres viejos con
--   su cuerpo y firma originales). Los nombres viejos quedan con DENY EXECUTE para rol_asistencias_runtime, como los nucleos.
-- Sin cambios de tablas ni de datos. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 78 DOWN: nombres usp_internal_* como copia de los nucleos usp_*_interno';
GO
DECLARE @mapa TABLE (orden INT IDENTITY(1, 1) PRIMARY KEY, nombre SYSNAME NOT NULL);
DECLARE @orden INT;
DECLARE @nombre SYSNAME;
DECLARE @viejo SYSNAME;
DECLARE @nuevo SYSNAME;
DECLARE @definicion NVARCHAR(MAX);
DECLARE @sentencia NVARCHAR(400);
INSERT INTO @mapa (nombre) VALUES
    (N'aplicar_festivos_grupo'), (N'aplicar_festivos_grupos'), (N'asegurar_estudiante_programa_grupo'), (N'asociar_asignatura_plan'),
    (N'cancelar_sesiones_receso'), (N'cargar_dias_festivos'), (N'cerrar_toma'), (N'marcar_ausentes_toma'), (N'matricular_por_token'),
    (N'radicar_solicitud_revision'), (N'reactivar_matricula_retirada'), (N'resolver_token_asistencia'), (N'resolver_token_matricula'),
    (N'rotar_token_asistencia'), (N'rotar_token_matricula'), (N'validar_plazo_justificacion');
SELECT @orden = MIN(orden) FROM @mapa;
WHILE @orden IS NOT NULL
BEGIN
    SELECT @nombre = nombre FROM @mapa WHERE orden = @orden;
    SET @viejo = CONCAT(N'usp_internal_', @nombre);
    SET @nuevo = CONCAT(N'usp_', @nombre, N'_interno');
    SET @definicion = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + QUOTENAME(@nuevo), N'P'));
    IF OBJECT_ID(N'dbo.' + QUOTENAME(@viejo), N'P') IS NULL AND @definicion IS NOT NULL
    BEGIN
        SET @definicion = REPLACE(@definicion, CONCAT(N'[dbo].[', @nuevo, N']'), CONCAT(N'[dbo].[', @viejo, N']'));
        EXEC sys.sp_executesql @definicion;
        IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
        BEGIN
            SET @sentencia = CONCAT(N'DENY EXECUTE ON [dbo].', QUOTENAME(@viejo), N' TO [rol_asistencias_runtime];');
            EXEC sys.sp_executesql @sentencia;
        END
    END
    SELECT @orden = MIN(orden) FROM @mapa WHERE orden > @orden;
END
GO
PRINT 'MIGRACION 78 DOWN: OK';
GO
