:ON ERROR EXIT
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 B2NM - Migracion 18 UP: retira Asignatura.semestrePlanEstudio y FK_Asignatura_SemestrePlanEstudio (DEC-025, CONTRACT §2.3.3).
-- BREAKING CHANGE: se elimina la columna Asignatura.semestrePlanEstudio y FK_Asignatura_SemestrePlanEstudio.
-- Solo se ejecuta con db-test de la 17 en verde. Idempotente. Verificacion y DROP en UNA transaccion; si falla, la columna y la FK quedan intactas.
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
IF COL_LENGTH('dbo.Asignatura', 'semestrePlanEstudio') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
        IF EXISTS (SELECT 1 FROM dbo.Asignatura a WHERE NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio x WHERE x.asignatura = a.id))
            THROW 52901, 'CULM-001 B2NM: hay asignaturas sin vinculo en la tabla puente; no se retira la columna.', 1;
        IF EXISTS (
            SELECT 1
            FROM dbo.EstudianteGrupo eg
            INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado AND ee.codigo = N'A'
            WHERE EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(eg.grupo))
              AND NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep INNER JOIN dbo.ufn_programas_grupo(eg.grupo) pg ON pg.idPrograma = ep.programa WHERE ep.estudiante = eg.estudiante)
              AND NOT EXISTS (SELECT 1 FROM dbo.zz_reporte_culm001_b2nm_estudiante_programa r WHERE r.estudiante = eg.estudiante AND r.tipo IN (N'AMBIGUO', N'SIN_INTERSECCION', N'RESUELTO'))
        )
            THROW 52901, 'CULM-001 B2NM: hay matriculas activas que violan R7 sin fila AMBIGUO/SIN_INTERSECCION en el reporte; no se retira la columna.', 1;
        EXEC sys.sp_executesql N'
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = ''FK_Asignatura_SemestrePlanEstudio'') ALTER TABLE dbo.Asignatura DROP CONSTRAINT FK_Asignatura_SemestrePlanEstudio;
            ALTER TABLE dbo.Asignatura DROP COLUMN semestrePlanEstudio;';
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
