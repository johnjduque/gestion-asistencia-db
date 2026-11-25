-- Migracion 78 (SKILLS-BD lote 2: retiro de los 16 usp_internal_* renombrados a usp_*_interno) up -> down -> up. Lo ejecuta
-- test/test_skills_lote2_migracion_78.ps1 con sqlcmd y la variable MIGDIR. Parte de una BD ya desplegada desde schema/. Todo ocurre
-- dentro de UNA transaccion que se revierte.
--   SKL2_MIG78_UP1_OK       el up sobre la base desplegada no cambia ninguna definicion y no deja ningun nombre viejo
--   SKL2_MIG78_DOWN_OK      el down crea los 16 nombres viejos (copia de los nuevos) con DENY EXECUTE para el runtime
--   SKL2_MIG78_UP2_OK       estado anterior al despliegue (nombre nuevo ausente, un llamador que usa el nombre viejo): el up crea el
--                           nombre nuevo como copia, recompila el llamador con el nombre nuevo (conserva la mencion "antes ...") y
--                           borra los viejos
--   SKL2_MIG78_UP3_OK       el up repetido no cambia nada
--   SKL2_MIG78_ROLLBACK_OK  la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID('tempdb..#mig78') IS NOT NULL DROP TABLE #mig78;
CREATE TABLE #mig78 (nombre SYSNAME COLLATE DATABASE_DEFAULT PRIMARY KEY);
INSERT INTO #mig78 (nombre) VALUES
    (N'aplicar_festivos_grupo'), (N'aplicar_festivos_grupos'), (N'asegurar_estudiante_programa_grupo'), (N'asociar_asignatura_plan'),
    (N'cancelar_sesiones_receso'), (N'cargar_dias_festivos'), (N'cerrar_toma'), (N'marcar_ausentes_toma'), (N'matricular_por_token'),
    (N'radicar_solicitud_revision'), (N'reactivar_matricula_retirada'), (N'resolver_token_asistencia'), (N'resolver_token_matricula'),
    (N'rotar_token_asistencia'), (N'rotar_token_matricula'), (N'validar_plazo_justificacion');
IF OBJECT_ID('tempdb..#huella78') IS NOT NULL DROP TABLE #huella78;
SELECT sm.object_id, HASHBYTES('SHA2_256', sm.definition) AS huella INTO #huella78 FROM sys.sql_modules sm;
GO
BEGIN TRANSACTION;
GO
IF EXISTS (SELECT 1 FROM #mig78 m WHERE OBJECT_ID(N'dbo.usp_' + m.nombre + N'_interno', N'P') IS NULL
                                     OR OBJECT_ID(N'dbo.usp_internal_' + m.nombre, N'P') IS NOT NULL)
    THROW 59780, 'TEST FAILED: SKL2_MIG78 la base inicial no tiene los 16 nucleos usp_*_interno o conserva nombres viejos (desplegar schema/ de la rama primero).', 1;
GO
:r $(MIGDIR)/78_skills_lote2_renombre_internos_up.sql
GO
IF EXISTS (SELECT 1 FROM #huella78 h LEFT JOIN sys.sql_modules sm ON sm.object_id = h.object_id
           WHERE sm.object_id IS NULL OR HASHBYTES('SHA2_256', sm.definition) <> h.huella)
   OR EXISTS (SELECT 1 FROM sys.procedures p WHERE p.name LIKE N'usp[_]internal[_]%')
    THROW 59781, 'TEST FAILED: SKL2_MIG78 el up sobre la base desplegada cambio definiciones o dejo nombres viejos.', 1;
PRINT 'SKL2_MIG78_UP1_OK';
GO
:r $(MIGDIR)/78_skills_lote2_renombre_internos_down.sql
GO
IF (SELECT COUNT(*) FROM #mig78 m WHERE OBJECT_ID(N'dbo.usp_internal_' + m.nombre, N'P') IS NOT NULL) <> 16
   OR EXISTS (SELECT 1 FROM #mig78 m
              WHERE NOT EXISTS (SELECT 1 FROM sys.database_permissions dp
                                WHERE dp.major_id = OBJECT_ID(N'dbo.usp_internal_' + m.nombre) AND dp.permission_name = N'EXECUTE'
                                  AND dp.state = 'D' AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime')))
   OR EXISTS (SELECT 1 FROM #mig78 m
              WHERE (SELECT COUNT(*) FROM sys.parameters x WHERE x.object_id = OBJECT_ID(N'dbo.usp_internal_' + m.nombre))
                 <> (SELECT COUNT(*) FROM sys.parameters x WHERE x.object_id = OBJECT_ID(N'dbo.usp_' + m.nombre + N'_interno')))
    THROW 59782, 'TEST FAILED: SKL2_MIG78 el down no creo los 16 nombres viejos con su firma y DENY.', 1;
PRINT 'SKL2_MIG78_DOWN_OK';
GO
-- Estado anterior al despliegue del lote 2: el nucleo nuevo de cerrar toma no existe y un modulo llama al nombre viejo
DROP PROCEDURE dbo.usp_cerrar_toma_interno;
GO
CREATE OR ALTER PROCEDURE dbo.usp_zz_skl2_mig78_llamador
AS
BEGIN
    -- antes usp_internal_cerrar_toma (mencion historica: no se toca)
    SET NOCOUNT ON;
    IF 1 = 0
    BEGIN
        EXEC dbo.usp_internal_cerrar_toma @idToma = NULL, @idSesion = NULL, @idGrupo = NULL, @marcarAusentes = 0, @idCorrelacion = NULL,
             @totalAusentesMarcados = NULL, @fechaCierreUtc = NULL;
        EXEC dbo.usp_internal_aplicar_festivos_grupos;
    END
END;
GO
:r $(MIGDIR)/78_skills_lote2_renombre_internos_up.sql
GO
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_zz_skl2_mig78_llamador'));
IF OBJECT_ID(N'dbo.usp_cerrar_toma_interno', N'P') IS NULL
   OR EXISTS (SELECT 1 FROM sys.procedures p WHERE p.name LIKE N'usp[_]internal[_]%')
   OR CHARINDEX(N'EXEC dbo.usp_cerrar_toma_interno @idToma', @def) = 0
   OR CHARINDEX(N'EXEC dbo.usp_aplicar_festivos_grupos_interno;', @def) = 0
   OR CHARINDEX(N'-- antes usp_internal_cerrar_toma (mencion', @def) = 0
   OR NOT EXISTS (SELECT 1 FROM sys.database_permissions dp
                  WHERE dp.major_id = OBJECT_ID(N'dbo.usp_cerrar_toma_interno') AND dp.permission_name = N'EXECUTE'
                    AND dp.state = 'D' AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
    THROW 59783, 'TEST FAILED: SKL2_MIG78 el up desde el estado anterior no creo el nucleo nuevo, no recompilo el llamador o dejo nombres viejos.', 1;
PRINT 'SKL2_MIG78_UP2_OK';
GO
IF OBJECT_ID('tempdb..#huella78b') IS NOT NULL DROP TABLE #huella78b;
SELECT sm.object_id, HASHBYTES('SHA2_256', sm.definition) AS huella INTO #huella78b FROM sys.sql_modules sm;
GO
:r $(MIGDIR)/78_skills_lote2_renombre_internos_up.sql
GO
IF EXISTS (SELECT 1 FROM #huella78b h LEFT JOIN sys.sql_modules sm ON sm.object_id = h.object_id
           WHERE sm.object_id IS NULL OR HASHBYTES('SHA2_256', sm.definition) <> h.huella)
    THROW 59784, 'TEST FAILED: SKL2_MIG78 el up repetido cambio definiciones.', 1;
PRINT 'SKL2_MIG78_UP3_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0
   OR OBJECT_ID(N'dbo.usp_zz_skl2_mig78_llamador', N'P') IS NOT NULL
   OR EXISTS (SELECT 1 FROM #huella78 h LEFT JOIN sys.sql_modules sm ON sm.object_id = h.object_id
              WHERE sm.object_id IS NULL OR HASHBYTES('SHA2_256', sm.definition) <> h.huella)
    THROW 59785, 'TEST FAILED: SKL2_MIG78 transaccion abierta o estado perdido tras el rollback.', 1;
PRINT 'SKL2_MIG78_ROLLBACK_OK';
GO
