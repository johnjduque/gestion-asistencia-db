:ON ERROR EXIT
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 B2NM - Migracion 18 DOWN (CONTRACT §2.3.4): restaura la columna como NULL desde el unico vinculo y recrea la FK.
-- Si la columna ya existe no hace nada. 52902 sin cambios si alguna asignatura tiene 0 o mas de 1 vinculo (activos e inactivos).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
IF COL_LENGTH('dbo.Asignatura', 'semestrePlanEstudio') IS NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.Asignatura a WHERE (SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio x WHERE x.asignatura = a.id) <> 1)
        THROW 52902, 'CULM-001 B2NM: hay asignaturas con 0 o mas de 1 vinculo (activos e inactivos); no se restaura la columna.', 1;
    ALTER TABLE dbo.Asignatura ADD semestrePlanEstudio UNIQUEIDENTIFIER NULL;
END
GO
IF COL_LENGTH('dbo.Asignatura', 'semestrePlanEstudio') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Asignatura_SemestrePlanEstudio')
BEGIN
    EXEC sys.sp_executesql N'UPDATE a SET a.semestrePlanEstudio = x.semestrePlanEstudio FROM dbo.Asignatura a INNER JOIN dbo.AsignaturaPlanEstudio x ON x.asignatura = a.id;';
    EXEC sys.sp_executesql N'ALTER TABLE dbo.Asignatura ADD CONSTRAINT FK_Asignatura_SemestrePlanEstudio FOREIGN KEY (semestrePlanEstudio) REFERENCES dbo.SemestrePlanEstudio (id);';
END
GO
