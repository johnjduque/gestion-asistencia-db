:ON ERROR EXIT
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 B2NM - Migracion 17 UP: asignaturas N:M por plan (DEC-019, DEC-020, DEC-025). CONTRACT §2.3.1.
-- Crea la tabla puente AsignaturaPlanEstudio y el catalogo CaracterAsignaturaPlan, hace backfill 1:1 de vinculos, deja
-- Asignatura.semestrePlanEstudio como NULL CONSERVANDO su FK (la migracion 18 la elimina), agrega los indices unicos, el programa por
-- defecto del token de matricula, el backfill de EstudiantePrograma con su reporte, y despliega funciones, vistas y SP del paquete.
-- Idempotente: un segundo UP no cambia nada. Toda sentencia que nombra la columna va en SQL dinamico con COL_LENGTH (compila con o sin ella).
-- BREAKING CHANGE (resultset): cambian columnas de uv_asignatura, uv_estudiante, uv_resumen_asistencia_estudiante_grupo y
-- uv_cumplimiento_sesion_grupo (sin idPrograma).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- 1. Precheck: codigos duplicados (UPPER(TRIM)) o asignaturas cuyo semestre no existe -> THROW 52900
IF COL_LENGTH('dbo.Asignatura', 'semestrePlanEstudio') IS NOT NULL
    EXEC sys.sp_executesql N'
    IF EXISTS (SELECT 1 FROM dbo.Asignatura GROUP BY UPPER(TRIM(codigo)) HAVING COUNT(*) > 1)
        THROW 52900, ''CULM-001 B2NM: hay codigos de asignatura duplicados; resuelvalos antes de la migracion 17.'', 1;
    IF EXISTS (SELECT 1 FROM dbo.Asignatura a WHERE a.semestrePlanEstudio IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.SemestrePlanEstudio s WHERE s.id = a.semestrePlanEstudio))
        THROW 52900, ''CULM-001 B2NM: hay asignaturas con un semestre de plan inexistente.'', 1;';
GO

-- 2. Catalogo, puente y reporte
USE [gestionasistenciadb];
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
-- CULM-001 B2NM (DEC-019): catalogo del caracter de una asignatura dentro de un plan (OBL, OPT). Solo consulta.
IF OBJECT_ID('dbo.CaracterAsignaturaPlan', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CaracterAsignaturaPlan (
        id      UNIQUEIDENTIFIER NOT NULL,
        codigo  NVARCHAR(3)      NOT NULL,
        nombre  NVARCHAR(50)     NOT NULL,
        orden   INT              NOT NULL,
        estado  BIT              NOT NULL CONSTRAINT DF_CaracterAsignaturaPlan_estado DEFAULT (1),
        CONSTRAINT PK_CaracterAsignaturaPlan PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_CaracterAsignaturaPlan_codigo UNIQUE (codigo),
        CONSTRAINT UQ_CaracterAsignaturaPlan_nombre UNIQUE (nombre),
        CONSTRAINT UQ_CaracterAsignaturaPlan_orden UNIQUE (orden)
    );
END
GO
USE [gestionasistenciadb];
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
-- CULM-001 B2NM (DEC-019): tabla puente N:M entre Asignatura y SemestrePlanEstudio, con caracter y vigencia (S1).
IF OBJECT_ID('dbo.AsignaturaPlanEstudio', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AsignaturaPlanEstudio (
        id                      UNIQUEIDENTIFIER NOT NULL,
        asignatura              UNIQUEIDENTIFIER NOT NULL,
        semestrePlanEstudio     UNIQUEIDENTIFIER NOT NULL,
        caracter                UNIQUEIDENTIFIER NOT NULL,
        estaActivo              BIT              NOT NULL CONSTRAINT DF_AsignaturaPlanEstudio_estaActivo DEFAULT (1),
        fechaVinculacionUtc     DATETIME2(3)     NOT NULL CONSTRAINT DF_AsignaturaPlanEstudio_fechaVinculacionUtc DEFAULT (SYSUTCDATETIME()),
        fechaDesvinculacionUtc  DATETIME2(3)     NULL,
        CONSTRAINT PK_AsignaturaPlanEstudio PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_AsignaturaPlanEstudio_asignatura_semestre UNIQUE (asignatura, semestrePlanEstudio),
        CONSTRAINT CK_AsignaturaPlanEstudio_vigencia CHECK (
               (estaActivo = 1 AND fechaDesvinculacionUtc IS NULL)
            OR (estaActivo = 0 AND fechaDesvinculacionUtc IS NOT NULL AND fechaDesvinculacionUtc >= fechaVinculacionUtc))
    );
    CREATE INDEX IX_AsignaturaPlanEstudio_semestre
        ON dbo.AsignaturaPlanEstudio (semestrePlanEstudio) INCLUDE (asignatura, caracter, estaActivo);
END
GO
IF OBJECT_ID('dbo.zz_reporte_culm001_b2nm_estudiante_programa', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.zz_reporte_culm001_b2nm_estudiante_programa (
        id          UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_zz_reporte_culm001_b2nm PRIMARY KEY,
        estudiante  UNIQUEIDENTIFIER NOT NULL,
        grupo       UNIQUEIDENTIFIER NULL,
        programa    UNIQUEIDENTIFIER NULL,
        tipo        NVARCHAR(20)     NOT NULL,   -- CREADO | AMBIGUO | SIN_INTERSECCION | DEDUPLICADO | RESUELTO
        detalle     NVARCHAR(400)    NULL,
        fechaUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_zz_reporte_culm001_b2nm_fecha DEFAULT (SYSUTCDATETIME())
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_AsignaturaPlanEstudio_Asignatura')
    ALTER TABLE dbo.AsignaturaPlanEstudio ADD CONSTRAINT FK_AsignaturaPlanEstudio_Asignatura FOREIGN KEY (asignatura) REFERENCES dbo.Asignatura (id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_AsignaturaPlanEstudio_SemestrePlanEstudio')
    ALTER TABLE dbo.AsignaturaPlanEstudio ADD CONSTRAINT FK_AsignaturaPlanEstudio_SemestrePlanEstudio FOREIGN KEY (semestrePlanEstudio) REFERENCES dbo.SemestrePlanEstudio (id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_AsignaturaPlanEstudio_CaracterAsignaturaPlan')
    ALTER TABLE dbo.AsignaturaPlanEstudio ADD CONSTRAINT FK_AsignaturaPlanEstudio_CaracterAsignaturaPlan FOREIGN KEY (caracter) REFERENCES dbo.CaracterAsignaturaPlan (id);
GO
-- CULM-001 B2NM (DEC-019, CONTRACT §2.1): catalogo del caracter de la asignatura en el plan. Ids fijos, resueltos por codigo.
MERGE INTO [dbo].[CaracterAsignaturaPlan] AS Target
USING (VALUES
    ('E1B2C3D4-0001-4B2A-9A00-000000000001', N'OBL', N'Obligatoria', 1, 1),
    ('E1B2C3D4-0001-4B2A-9A00-000000000002', N'OPT', N'Optativa', 2, 1)
) AS Source (id, codigo, nombre, orden, estado)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.orden = Source.orden, Target.estado = Source.estado
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, orden, estado)
    VALUES (CAST(Source.id AS UNIQUEIDENTIFIER), Source.codigo, Source.nombre, Source.orden, Source.estado);
GO

-- CULM-001 B2NM (R1): caracter por defecto cuando el SP recibe @codigoCaracter NULL. Sin pisar el valor administrado.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('ASIGNATURA_PLAN', 'CARACTER_DEFECTO', N'OBL', 'STRING', N'OBL')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO


-- 3. Backfill 1:1 de la puente (SQL dinamico, WHERE NOT EXISTS): caracter por defecto, fecha = MIN(inicio de periodos de sus grupos)
IF COL_LENGTH('dbo.Asignatura', 'semestrePlanEstudio') IS NOT NULL
    EXEC sys.sp_executesql N'
    INSERT INTO dbo.AsignaturaPlanEstudio (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc, fechaDesvinculacionUtc)
    SELECT NEWID(), a.id, a.semestrePlanEstudio,
           (SELECT c.id FROM dbo.CaracterAsignaturaPlan c WHERE c.codigo = CAST(dbo.ufn_obtener_parametro(''ASIGNATURA_PLAN'', ''CARACTER_DEFECTO'') AS NVARCHAR(3))),
           1,
           COALESCE((SELECT CAST(MIN(pa.fechaInicio) AS DATETIME2(3)) FROM dbo.Grupo g INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico WHERE g.asignatura = a.id),
                    SYSUTCDATETIME()),
           NULL
    FROM dbo.Asignatura a
    WHERE a.semestrePlanEstudio IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio x WHERE x.asignatura = a.id);';
GO

-- 4. Indices y columnas nuevas
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Asignatura_codigo' AND object_id = OBJECT_ID('dbo.Asignatura'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_Asignatura_codigo ON dbo.Asignatura (codigo);
GO
-- deduplicacion de EstudiantePrograma (conserva el menor id; lo borrado va al reporte como DEDUPLICADO)
BEGIN TRY
    BEGIN TRANSACTION;
    ;WITH d AS (SELECT id, estudiante, programa, rn = ROW_NUMBER() OVER (PARTITION BY estudiante, programa ORDER BY id) FROM dbo.EstudiantePrograma)
    INSERT INTO dbo.zz_reporte_culm001_b2nm_estudiante_programa (id, estudiante, grupo, programa, tipo, detalle)
    SELECT NEWID(), estudiante, NULL, programa, N'DEDUPLICADO', CONCAT(N'EstudiantePrograma duplicado eliminado: ', CAST(id AS NVARCHAR(40))) FROM d WHERE rn > 1;
    ;WITH d AS (SELECT id, rn = ROW_NUMBER() OVER (PARTITION BY estudiante, programa ORDER BY id) FROM dbo.EstudiantePrograma)
    DELETE FROM dbo.EstudiantePrograma WHERE id IN (SELECT id FROM d WHERE rn > 1);
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_EstudiantePrograma_estudiante_programa' AND object_id = OBJECT_ID('dbo.EstudiantePrograma'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_EstudiantePrograma_estudiante_programa ON dbo.EstudiantePrograma (estudiante, programa);
GO
IF COL_LENGTH('dbo.TokenMatriculaGrupo', 'programaPorDefecto') IS NULL
    ALTER TABLE dbo.TokenMatriculaGrupo ADD programaPorDefecto UNIQUEIDENTIFIER NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TokenMatriculaGrupo_Programa')
    ALTER TABLE dbo.TokenMatriculaGrupo ADD CONSTRAINT FK_TokenMatriculaGrupo_Programa FOREIGN KEY (programaPorDefecto) REFERENCES dbo.Programa (id);
GO

-- 5. Asignatura.semestrePlanEstudio pasa a NULL (conserva FK_Asignatura_SemestrePlanEstudio; los SP nuevos insertan sin ella)
IF COL_LENGTH('dbo.Asignatura', 'semestrePlanEstudio') IS NOT NULL
    EXEC sys.sp_executesql N'ALTER TABLE dbo.Asignatura ALTER COLUMN semestrePlanEstudio UNIQUEIDENTIFIER NULL;';
GO

-- 6. Objetos programables (mismo texto que schema/): funciones, vistas y procedimientos
-- >>> functions/ufn_programas_grupo
-- CULM-001 B2NM (CONTRACT §2.6): programas vigentes de un grupo segun la tabla puente (regla S1 de vigencia del vinculo).
-- Solo lee tablas base (las funciones se despliegan antes que las vistas). Por programa elige un unico plan:
-- activo primero, mayor inp, menor id.
CREATE OR ALTER FUNCTION [dbo].[ufn_programas_grupo] (@idGrupo UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT  x.idPrograma, x.idPlanEstudio, x.inpPlanEstudio
    FROM (
        SELECT  idPrograma = pe.programa,
                idPlanEstudio = pe.id,
                inpPlanEstudio = pe.inp,
                rn = ROW_NUMBER() OVER (PARTITION BY pe.programa ORDER BY pe.estado DESC, pe.inp DESC, pe.id ASC)
        FROM    dbo.Grupo g
        INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
        INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = g.asignatura
        INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
        CROSS APPLY (SELECT zona = COALESCE((SELECT TOP 1 valor FROM dbo.CatalogoParametro
                                             WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1),
                                            'SA Pacific Standard Time')) z
        WHERE   g.id = @idGrupo
          AND   CAST(ape.fechaVinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) <= pa.fechaFin
          AND   (ape.fechaDesvinculacionUtc IS NULL
                 OR CAST(ape.fechaDesvinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) >= pa.fechaInicio)
    ) x
    WHERE x.rn = 1
);
GO

-- >>> functions/ufn_programas_coordinador
-- CULM-001 B2NM (CONTRACT §2.6, R8): programas que coordina un usuario (reemplaza los TOP 1 de programa).
CREATE OR ALTER FUNCTION [dbo].[ufn_programas_coordinador] (@idUsuario UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT  idPrograma = p.id
    FROM    dbo.Programa p
    INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
    WHERE   c.usuario = @idUsuario
);
GO

-- >>> functions/ufn_programas_ambito_ejecutor
-- CULM-001 B2NM (CONTRACT §2.6): programas del ambito de un ejecutor. Coordinador -> sus programas; decano -> programas de su facultad.
CREATE OR ALTER FUNCTION [dbo].[ufn_programas_ambito_ejecutor] (@idUsuario UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT  idPrograma = p.id, rol = CAST(N'COORDINADOR' AS NVARCHAR(20))
    FROM    dbo.Programa p
    INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
    WHERE   c.usuario = @idUsuario
    UNION
    SELECT  idPrograma = p.id, rol = CAST(N'DECANO' AS NVARCHAR(20))
    FROM    dbo.Programa p
    INNER JOIN dbo.Facultad f ON f.id = p.facultad
    INNER JOIN dbo.Decano d ON d.id = f.decano
    WHERE   d.usuario = @idUsuario
);
GO

-- >>> functions/ufn_estudiantes_grupo_visibles
-- CULM-001 B2NM (CONTRACT §2.6, R6/R10): matriculas de un grupo visibles para un ejecutor.
--   * Docente titular del grupo y administrador de la institucion del grupo: todas las matriculas (R10).
--   * Coordinador y decano: matriculas cuyo estudiante tiene EstudiantePrograma en (programas del grupo ∩ ambito del ejecutor) (R6).
-- Lee solo tablas base y no llama a otras ufn_* (el orden de despliegue es alfabetico).
CREATE OR ALTER FUNCTION [dbo].[ufn_estudiantes_grupo_visibles] (@idGrupo UNIQUEIDENTIFIER, @idUsuarioEjecutor UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT  idEstudianteGrupo = eg.id, idEstudiante = eg.estudiante
    FROM    dbo.EstudianteGrupo eg
    WHERE   eg.grupo = @idGrupo
      AND (
            EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente doc ON doc.id = g.docente
                    WHERE g.id = @idGrupo AND doc.usuario = @idUsuarioEjecutor)
         OR EXISTS (SELECT 1
                    FROM dbo.Grupo g
                    INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
                    INNER JOIN dbo.Administrador adm ON adm.institucion = pa.institucion
                    WHERE g.id = @idGrupo AND adm.usuario = @idUsuarioEjecutor)
         OR EXISTS (SELECT 1
                    FROM dbo.EstudiantePrograma ep
                    INNER JOIN dbo.Grupo g ON g.id = @idGrupo
                    INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
                    INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = g.asignatura
                    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                    INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio AND pe.programa = ep.programa
                    CROSS APPLY (SELECT zona = COALESCE((SELECT TOP 1 valor FROM dbo.CatalogoParametro
                                                         WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1),
                                                        'SA Pacific Standard Time')) z
                    WHERE ep.estudiante = eg.estudiante
                      AND CAST(ape.fechaVinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) <= pa.fechaFin
                      AND (ape.fechaDesvinculacionUtc IS NULL
                           OR CAST(ape.fechaDesvinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) >= pa.fechaInicio)
                      AND (EXISTS (SELECT 1 FROM dbo.Programa p INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
                                   WHERE p.id = ep.programa AND c.usuario = @idUsuarioEjecutor)
                           OR EXISTS (SELECT 1 FROM dbo.Programa p INNER JOIN dbo.Facultad f ON f.id = p.facultad
                                      INNER JOIN dbo.Decano d ON d.id = f.decano
                                      WHERE p.id = ep.programa AND d.usuario = @idUsuarioEjecutor)))
      )
);
GO

-- >>> views/uv_caracter_asignatura_plan
-- CULM-001 B2NM: catalogo de solo consulta del caracter de una asignatura en un plan.
CREATE OR ALTER VIEW [dbo].[uv_caracter_asignatura_plan]
AS
SELECT  id = c.id,
        codigo = c.codigo,
        nombre = c.nombre,
        orden = c.orden,
        estaActivo = c.estado
FROM    CaracterAsignaturaPlan c
GO

-- >>> views/uv_asignatura
-- CULM-001 B2NM (DEC-019): catalogo de asignaturas, 1 fila por asignatura. La pertenencia a planes vive en
-- uv_asignatura_plan_estudio (tabla puente AsignaturaPlanEstudio).
CREATE OR ALTER  VIEW [dbo].[uv_asignatura]
AS
SELECT		id = a.id,
			codigo = a.codigo,
			nombre = a.nombre,
			credito = a.credito,
			idArea = ar.id,
			nombreArea = ar.nombre,
			idComponente = co.id,
			nombreComponente = co.nombre,
			estaActivaAsignatura = a.estado,
			estaActivaTextoAsignatura = IIF(a.estado = 1, 'SI', 'NO'),
			totalPlanesActivos = (SELECT COUNT(*) FROM AsignaturaPlanEstudio x WHERE x.asignatura = a.id AND x.estaActivo = 1)

FROM		Asignatura a
INNER JOIN	uv_area ar
ON			a.area = ar.id
INNER JOIN	uv_componente co
ON			a.componente = co.id
GO

-- >>> views/uv_asignatura_plan_estudio
-- CULM-001 B2NM (CONTRACT 2.5): 1 fila por vinculo (asignatura, semestre de un plan), con caracter y programa.
CREATE OR ALTER VIEW [dbo].[uv_asignatura_plan_estudio]
AS
SELECT  idAsignaturaPlanEstudio = ape.id,
        idAsignatura = a.id,
        codigoAsignatura = a.codigo,
        nombreAsignatura = a.nombre,
        credito = a.credito,
        idArea = a.idArea,
        nombreArea = a.nombreArea,
        idComponente = a.idComponente,
        codigoComponente = co.codigo,
        nombreComponente = a.nombreComponente,
        estaActivaAsignatura = a.estaActivaAsignatura,
        idSemestrePlanEstudio = sp.id,
        idSemestre = sp.idSemestre,
        numeroSemestre = sp.numeroSemestre,
        codigoSemestre = s.codigo,
        idPlanEstudio = pe.id,
        inpPlanEstudio = pe.inp,
        estaActivoPlan = pe.estaActivoPlanEstudio,
        idPrograma = pr.id,
        nombrePrograma = pr.nombrePrograma,
        idFacultad = pr.idFacultad,
        idInstitucion = pr.idInstitucion,
        idCaracter = ca.id,
        codigoCaracter = ca.codigo,
        nombreCaracter = ca.nombre,
        ordenCaracter = ca.orden,
        estaActivoVinculo = ape.estaActivo,
        fechaVinculacionUtc = ape.fechaVinculacionUtc,
        fechaDesvinculacionUtc = ape.fechaDesvinculacionUtc,
        totalProgramasActivos = (SELECT COUNT(DISTINCT p2.programa)
                                 FROM AsignaturaPlanEstudio x
                                 INNER JOIN SemestrePlanEstudio sx ON sx.id = x.semestrePlanEstudio
                                 INNER JOIN PlanEstudio p2 ON p2.id = sx.planEstudio
                                 WHERE x.asignatura = a.id AND x.estaActivo = 1)
FROM    AsignaturaPlanEstudio ape
INNER JOIN uv_asignatura a ON a.id = ape.asignatura
INNER JOIN Componente co ON co.id = a.idComponente
INNER JOIN uv_semestre_plan_estudio sp ON sp.id = ape.semestrePlanEstudio
INNER JOIN uv_semestre s ON s.id = sp.idSemestre
INNER JOIN uv_plan_estudio pe ON pe.id = sp.idPlanEstudio
INNER JOIN uv_programa pr ON pr.id = pe.idPrograma
INNER JOIN CaracterAsignaturaPlan ca ON ca.id = ape.caracter
GO

-- >>> views/uv_grupo_programa
-- HU078 / CULM-001 B2NM (DEC-019, R5): relacion grupo -> programas por la tabla puente (ufn_programas_grupo, regla S1).
-- GRANO 1:N por (grupo, programa): todo consumidor que cuente o pagine grupos, sesiones o estudiantes debe usar EXISTS o
-- DISTINCT sobre la clave de negocio. El plan es el del programa con vinculo vigente; si hay varios: activo primero,
-- mayor inp, menor id. PlanEstudio.estado = 0 NO saca un grupo de la vista (conserva la historia, O-N10).
CREATE OR ALTER VIEW [dbo].[uv_grupo_programa]
AS
SELECT  idGrupo = g.id,
        idPrograma = pg.idPrograma,
        idPeriodoAcademico = g.idPeriodoAcademico,
        grupoEstaHablitado = g.grupoEstaHablitado,
        idPlanEstudio = pg.idPlanEstudio,
        inpPlanEstudio = pg.inpPlanEstudio
FROM    uv_grupo g
CROSS APPLY dbo.ufn_programas_grupo(g.id) pg
GO

-- >>> views/uv_docente
-- CULM-001 B2NM: programa y plan desde uv_grupo_programa. Grano 1 por (docente, grupo, programa del grupo).
CREATE OR ALTER    VIEW	[dbo].[uv_docente]
AS
SELECT		di.id,
			di.idUsuario,
			di.numeroIdentificacion,
			di.nombreCompleto,
			di.estaActivoUsuario,

			idInstitucion = pr.idInstitucion,
			nombreInstitucion = pr.nombreInstitucion,

			idFacultad = pr.idFacultad,
			nombreFacultad = pr.nombreFacultad,
			idPrograma = pr.id,
			nombrePrograma = pr.nombrePrograma,

			idPlanEstudio = gp.idPlanEstudio,
			inpPlanEstudio = gp.inpPlanEstudio,
			idAsignatura = a.id,
			nombreAsignatura = a.nombre,
			idGrupo = g.id,
			nombreGrupo = g.nombre,

			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,

			estaActivoDocente = IIF(di.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 1, 0),
			estaActivoTextoDocente = IIF(di.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 'SI', 'NO')

FROM		uv_docente_identidad di
INNER JOIN	uv_grupo g
ON			di.id = g.idDocente
INNER JOIN	uv_asignatura a
ON			g.idAsignatura = a.id
INNER JOIN	uv_grupo_programa gp
ON			gp.idGrupo = g.id
INNER JOIN	uv_programa pr
ON			gp.idPrograma = pr.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'DO') p
GO

-- >>> views/uv_estudiante
-- CULM-001 B2NM (DEC-020, R6): 1 fila por (estudiante, grupo, programa del grupo); ya no exige EstudiantePrograma.
-- tieneVinculoPrograma = 1 cuando el estudiante tiene EstudiantePrograma en ese programa.
CREATE OR ALTER     VIEW	[dbo].[uv_estudiante]
AS
SELECT		ei.id,
			ei.idUsuario,
			ei.numeroIdentificacion,
			ei.nombreCompleto,
			ei.estaActivoUsuario,

			idInstitucion = pr.idInstitucion,
			nombreInstitucion = pr.nombreInstitucion,

			idFacultad = pr.idFacultad,
			nombreFacultad = pr.nombreFacultad,
			idPrograma = pr.id,
			nombrePrograma = pr.nombrePrograma,

			idPlanEstudio = gp.idPlanEstudio,
			inpPlanEstudio = gp.inpPlanEstudio,
			idAsignatura = a.id,
			nombreAsignatura = a.nombre,
			idGrupo = g.id,
			nombreGrupo = g.nombre,

			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,

			estaActivoEstudiante = IIF(ei.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 1, 0),
			estaActivoTextoEstudiante = IIF(ei.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 'SI', 'NO'),
			tieneVinculoPrograma = CAST(IIF(EXISTS (SELECT 1 FROM EstudiantePrograma ep WHERE ep.estudiante = ei.id AND ep.programa = pr.id), 1, 0) AS BIT)

FROM		uv_estudiante_identidad ei
INNER JOIN	uv_estudiante_grupo eg
ON			ei.id = eg.idEstudiante
INNER JOIN	uv_grupo g
ON			eg.idGrupo = g.id
INNER JOIN	uv_asignatura a
ON			g.idAsignatura = a.id
INNER JOIN	uv_grupo_programa gp
ON			gp.idGrupo = g.id
INNER JOIN	uv_programa pr
ON			gp.idPrograma = pr.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'ES') p
GO

-- >>> views/uv_estudiante_grupo_programa
-- CULM-001 B2NM (R6): 1 fila por (matricula, programa del grupo en el que el estudiante tiene EstudiantePrograma).
CREATE OR ALTER VIEW [dbo].[uv_estudiante_grupo_programa]
AS
SELECT  id = eg.id,
        idEstudiante = eg.idEstudiante,
        idGrupo = eg.idGrupo,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        idPrograma = gp.idPrograma
FROM    uv_estudiante_grupo eg
INNER JOIN uv_grupo_programa gp ON gp.idGrupo = eg.idGrupo
INNER JOIN EstudiantePrograma ep ON ep.estudiante = eg.idEstudiante AND ep.programa = gp.idPrograma
GO

-- >>> views/uv_estudiante_programa
-- CULM-001 B2NM: 1 fila por EstudiantePrograma, construida desde el vinculo y la identidad (ya no desde uv_estudiante).
CREATE OR ALTER  VIEW [dbo].[uv_estudiante_programa]
AS
SELECT  id = ep.id,

        idEstudiante = e.id,
        nombreEstudiante = e.nombreCompleto,
        idPrograma = p.id,
        nombrePrograma = p.nombrePrograma,
        estaActivoUsuario = e.estaActivoUsuario

FROM		EstudiantePrograma ep
INNER JOIN	uv_estudiante_identidad e
ON          ep.estudiante = e.id
INNER JOIN	uv_programa p
ON          ep.programa = p.id
GO

-- >>> views/uv_auth_grupo
CREATE OR ALTER VIEW [dbo].[uv_auth_grupo]
AS
SELECT  g.id,
        g.idPeriodoAcademico,
        g.fechaInicioPeriodoAcademico,
        g.fechaFinPeriodoAcademico,
        g.idAsignatura,
        g.nombreAsignatura,
        g.idDocente,
        g.codigo,
        g.nombre,
        g.capacidadMaximaPermitida,
        g.estudiantesActivos,
        g.estudiantesFinalizados,
        g.estudiantesCanceladosVoluntad,
        g.estudiantesCanceladosInasistencia,
        g.cuposDisponibles,
        g.grupoEstaHablitado,
        g.grupoEstaHablitadoTexto
FROM    dbo.uv_grupo g
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            -- CULM-001 B2NM: ambito por EXISTS sobre los programas del grupo (uv_grupo_programa 1:N); sigue siendo 1 fila por grupo.
            EXISTS (
            SELECT 1 FROM dbo.uv_grupo_programa gp
            INNER JOIN dbo.Programa pr ON pr.id = gp.idPrograma
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            INNER JOIN dbo.Administrador adm ON adm.institucion = f.institucion
            WHERE gp.idGrupo = g.id AND adm.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.uv_grupo_programa gp
            INNER JOIN dbo.Programa pr ON pr.id = gp.idPrograma
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            INNER JOIN dbo.Decano d ON f.decano = d.id
            WHERE gp.idGrupo = g.id AND d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.uv_grupo_programa gp
            INNER JOIN dbo.Programa pr ON pr.id = gp.idPrograma
            INNER JOIN dbo.Coordinador c ON pr.coordinador = c.id
            WHERE gp.idGrupo = g.id AND c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND g.idDocente = doc.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Estudiante e INNER JOIN dbo.EstudianteGrupo eg ON e.id = eg.estudiante WHERE e.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND eg.grupo = g.id
        )
        );
GO

-- >>> views/uv_auth_programa
-- CULM-001 B2NM: programa del grupo por uv_grupo_programa (tabla puente, S1) en lugar de Asignatura.semestrePlanEstudio.
CREATE OR ALTER VIEW [dbo].[uv_auth_programa]
AS
SELECT  p.id,
        p.nombrePrograma,
        p.estado,
        p.idFacultad,
        p.nombreFacultad,
        p.idInstitucion,
        p.nombreInstitucion,
        p.idCoordinador,
        p.nombreCoordinador,
        p.estaActivoPrograma,
        p.estaActivoTextoPrograma,
        p.idTipoPrograma,
        p.nombreTipoPrograma,
        p.idModalidad,
        p.nombreModalidad,
        p.idJornada,
        p.nombreJornada
FROM    dbo.uv_programa p
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = p.idInstitucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d INNER JOIN dbo.Facultad f ON d.id = f.decano WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.id = p.idFacultad
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND p.idCoordinador = c.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc
            INNER JOIN dbo.Grupo g ON doc.id = g.docente
            INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
            WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND gp.idPrograma = p.id
        )
        );
GO

-- >>> views/uv_auth_facultad
-- CULM-001 B2NM: programa del grupo por uv_grupo_programa (tabla puente, S1) en lugar de Asignatura.semestrePlanEstudio.
CREATE OR ALTER VIEW [dbo].[uv_auth_facultad]
AS
SELECT  f.id,
        f.nombreFacultad,
        f.idInstitucion,
        f.nombreInstitucion,
        f.idDecano,
        f.nombreCompletoDecano,
        f.estaActivaFacultad,
        f.estaActivaTextoFacultad
FROM    dbo.uv_facultad f
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = f.idInstitucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.idDecano = d.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c 
            INNER JOIN dbo.Programa pr ON c.id = pr.coordinador 
            WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.facultad = f.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc
            INNER JOIN dbo.Grupo g ON doc.id = g.docente
            INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
            INNER JOIN dbo.Programa pr ON gp.idPrograma = pr.id
            WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.facultad = f.id
        )
        );
GO

-- >>> views/uv_auth_institucion
-- CULM-001 B2NM: programa del grupo por uv_grupo_programa (tabla puente, S1) en lugar de Asignatura.semestrePlanEstudio.
CREATE OR ALTER VIEW [dbo].[uv_auth_institucion]
AS
SELECT  i.id,
        i.nombre,
        i.estaActivaInstitucion,
        i.estaActivaTextoInstitucion
FROM    dbo.uv_institucion i
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d 
            INNER JOIN dbo.Facultad f ON d.id = f.decano 
            WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c 
            INNER JOIN dbo.Programa pr ON c.id = pr.coordinador 
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc
            INNER JOIN dbo.Grupo g ON doc.id = g.docente
            INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
            INNER JOIN dbo.Programa pr ON gp.idPrograma = pr.id
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Estudiante e
            INNER JOIN dbo.EstudianteGrupo eg ON e.id = eg.estudiante
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
            INNER JOIN dbo.Programa pr ON gp.idPrograma = pr.id
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            WHERE e.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        )
        );
GO

-- >>> views/uv_auth_estudiante
-- CULM-001 B2NM (R6/R10): coordinador y decano exigen tieneVinculoPrograma = 1; administrador, docente titular y el propio estudiante no.
CREATE OR ALTER VIEW [dbo].[uv_auth_estudiante]
AS
SELECT  e.id,
        e.idUsuario,
        e.numeroIdentificacion,
        e.nombreCompleto,
        e.estaActivoUsuario,
        e.idInstitucion,
        e.nombreInstitucion,
        e.idFacultad,
        e.nombreFacultad,
        e.idPrograma,
        e.nombrePrograma,
        e.idPlanEstudio,
        e.inpPlanEstudio,
        e.idAsignatura,
        e.nombreAsignatura,
        e.idGrupo,
        e.nombreGrupo,
        e.idPerfil,
        e.codigoPerfil,
        e.nombrePerfil,
        e.estaActivoEstudiante,
        e.estaActivoTextoEstudiante,
        e.tieneVinculoPrograma
FROM    dbo.uv_estudiante e
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = e.idInstitucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano dec INNER JOIN dbo.Facultad f ON dec.id = f.decano WHERE e.tieneVinculoPrograma = 1 AND dec.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.id = e.idFacultad
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c INNER JOIN dbo.Programa pr ON c.id = pr.coordinador WHERE e.tieneVinculoPrograma = 1 AND c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.id = e.idPrograma
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc INNER JOIN dbo.Grupo g ON doc.id = g.docente WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND g.id = e.idGrupo
        )
   OR   e.idUsuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        );
GO

-- >>> views/uv_cumplimiento_sesion_grupo
-- HU065: una fila por sesion con su estado de cumplimiento (D4, D7). Consume uv_sesion_v2 (procedencia temporal) y
-- uv_grupo_programa; no altera las vistas congeladas.
-- CULM-001 B.1 (CONTRACT §2.6): una sesion cancelada (dbo.SesionCancelacion, por el docente o por festivo) sale de la
-- vista y con ello de sesionesProgramadas, vencidas, ejecutadas, cumplimiento, progreso de calendario y tendencia.
-- Columnas sin cambio.
-- CULM-001 B.2 (CONTRACT §2.6, [SUPUESTO-B-06]): tieneRegistroAsistencia = existe Asistencia O existe TomaAsistencia (una toma
-- QR abierta y cerrada sin lecturas cuenta como sesion ejecutada); columnas nuevas totalTomas y horasSesion.
-- CULM-001 B2NM: sin idPrograma (1 fila por sesion); el programa se resuelve con EXISTS uv_grupo_programa.
CREATE OR ALTER VIEW [dbo].[uv_cumplimiento_sesion_grupo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idPeriodoAcademico = g.idPeriodoAcademico,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaVencida = CAST(IIF(s.procedenciaTemporal IS NOT NULL AND s.fechaHoraFin <= SYSUTCDATETIME(), 1, 0) AS BIT),
        procedenciaIndeterminada = CAST(IIF(s.procedenciaTemporal IS NULL, 1, 0) AS BIT),
        tieneRegistroAsistencia = CAST(IIF(EXISTS (SELECT 1 FROM dbo.uv_asistencia a WHERE a.idSesion = s.id)
                                           OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id), 1, 0) AS BIT),
        totalTomas = (SELECT COUNT(1) FROM dbo.TomaAsistencia t WHERE t.sesion = s.id),
        horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_grupo g
ON      g.id = s.idGrupo
WHERE   NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id)
GO

-- >>> views/uv_resumen_asistencia_estudiante_grupo
-- HU066/HU067/HU069/HU070: una fila por matricula (EstudianteGrupo) con sus cifras de asistencia.
-- Denominador (D1): sesiones vencidas CON registro del grupo. Falta (D2): asistio = 0 con razon SJC; la excusa (EX) no cuenta.
-- CULM-001 B.2 (CONTRACT §2.6, §2.9, DEC-012, DEC-024, NB-2): inasistencia por HORAS conservando los nombres.
--   sesionesEjecutadas: sesiones vencidas, con registro (Asistencia o TomaAsistencia) y no canceladas (sin cambio de nombre).
--   asistencias / faltasSinJustaCausa / excusas: pasan a contar TOMAS (con una toma por sesion = sesiones, igual que antes).
--   tomasDictadas / horasDictadas: tomas y horas (ufn_horas_sesion) de esas mismas sesiones, sin mirar el estado de la toma.
--   horasAsistidas / horasFalta / horasExcusa: suma de uv_asistencia_sesion_horas en esas sesiones; horasSinRegistro =
--   horasDictadas - las tres (nunca negativo).
--   porcentajeInasistencia = ufn_calcular_porcentaje_inasistencia_horas(horasFalta, horasDictadas); codigoPermanencia sobre ese
--   porcentaje (ufn_clasificar_permanencia sin cambio). porcentajeInasistenciaSesiones = formula anterior por sesiones
--   (sesionesConFaltaSinJustaCausa / sesionesEjecutadas), solo trazabilidad. umbralAdvertencia / umbralPerdida: parametros.
--   sesionesAsistidas / sesionesConFaltaSinJustaCausa / sesionesConExcusa: sesiones por estado consolidado (consumidores
--   diferidos a D).
-- CULM-001 B2NM: sin idPrograma (1 fila por matricula); el resumen por programa es uv_resumen_asistencia_estudiante_programa_grupo.
CREATE OR ALTER VIEW [dbo].[uv_resumen_asistencia_estudiante_grupo]
AS
SELECT  idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        idGrupo = eg.idGrupo,
        idAsignatura = g.idAsignatura,
        idPeriodoAcademico = g.idPeriodoAcademico,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        sesionesEjecutadas = ISNULL(se.sesionesEjecutadas, 0),
        asistencias = ISNULL(de.asistencias, 0),
        faltasSinJustaCausa = ISNULL(de.faltas, 0),
        excusas = ISNULL(de.excusas, 0),
        porcentajeInasistencia = p.porcentaje,
        codigoPermanencia = dbo.ufn_clasificar_permanencia(p.porcentaje, eg.codigoEstadoEstudiante),
        tomasDictadas = ISNULL(se.tomasDictadas, 0),
        horasDictadas = hd.horasDictadas,
        horasAsistidas = hd.horasAsistidas,
        horasFalta = hd.horasFalta,
        horasExcusa = hd.horasExcusa,
        horasSinRegistro = hd.horasSinRegistro,
        porcentajeAsistenciaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasAsistidas, hd.horasDictadas),
        porcentajeExcusaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasExcusa, hd.horasDictadas),
        porcentajeSinRegistroHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasSinRegistro, hd.horasDictadas),
        porcentajeInasistenciaSesiones = CAST(IIF(ISNULL(se.sesionesEjecutadas, 0) = 0, 0,
                                                  100.0 * ISNULL(hs.sesionesConFalta, 0) / se.sesionesEjecutadas) AS DECIMAL(5,2)),
        umbralAdvertencia = u.umbralAdvertencia,
        umbralPerdida = u.umbralPerdida,
        sesionesAsistidas = ISNULL(hs.sesionesAsistidas, 0),
        sesionesConFaltaSinJustaCausa = ISNULL(hs.sesionesConFalta, 0),
        sesionesConExcusa = ISNULL(hs.sesionesConExcusa, 0)
FROM    dbo.uv_estudiante_grupo eg
INNER JOIN dbo.uv_grupo g
ON      g.id = eg.idGrupo
LEFT JOIN (
            SELECT  c.idGrupo,
                    sesionesEjecutadas = COUNT(*),
                    tomasDictadas = SUM(c.totalTomas),
                    horasDictadas = SUM(c.horasSesion)
            FROM    dbo.uv_cumplimiento_sesion_grupo c
            WHERE   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY c.idGrupo
          ) se
ON      se.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  v.idEstudianteGrupo,
                    asistencias = SUM(IIF(v.asistio = 1, 1, 0)),
                    faltas = SUM(IIF(v.asistio = 0 AND v.codigoRazonCausa = N'SJC', 1, 0)),
                    excusas = SUM(IIF(v.codigoRazonCausa = N'EX', 1, 0))
            FROM    dbo.uv_detalle_asistencia_v2 v
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = v.idSesion AND c.estaVencida = 1
            GROUP BY v.idEstudianteGrupo
          ) de
ON      de.idEstudianteGrupo = eg.id
LEFT JOIN (
            SELECT  h.idEstudianteGrupo,
                    horasAsistidas = SUM(h.horasAsistidas),
                    horasFalta = SUM(h.horasFalta),
                    horasExcusa = SUM(h.horasExcusa),
                    sesionesAsistidas = SUM(IIF(h.codigoRazonCausaConsolidado = N'AN', 1, 0)),
                    sesionesConFalta = SUM(IIF(h.tieneFaltaSinJustaCausa = 1, 1, 0)),
                    sesionesConExcusa = SUM(IIF(h.codigoRazonCausaConsolidado = N'EX', 1, 0))
            FROM    dbo.uv_asistencia_sesion_horas h
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = h.idSesion AND c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY h.idEstudianteGrupo
          ) hs
ON      hs.idEstudianteGrupo = eg.id
CROSS APPLY (
            SELECT  horasDictadas = CAST(ISNULL(se.horasDictadas, 0) AS DECIMAL(12,6)),
                    horasAsistidas = CAST(ISNULL(hs.horasAsistidas, 0) AS DECIMAL(12,6)),
                    horasFalta = CAST(ISNULL(hs.horasFalta, 0) AS DECIMAL(12,6)),
                    horasExcusa = CAST(ISNULL(hs.horasExcusa, 0) AS DECIMAL(12,6)),
                    horasSinRegistro = CAST(IIF(ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0) < 0, 0,
                                                ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0)) AS DECIMAL(12,6))
          ) hd
CROSS APPLY (SELECT porcentaje = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasFalta, hd.horasDictadas)) p
CROSS APPLY (
            SELECT  umbralAdvertencia = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA') AS NVARCHAR(20))), '') AS DECIMAL(5,2)),
                    umbralPerdida = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA') AS NVARCHAR(20))), '') AS DECIMAL(5,2))
          ) u;
GO

-- >>> views/uv_resumen_asistencia_estudiante_programa_grupo
-- CULM-001 B2NM (R9): resumen por (matricula, programa) para los KPI por programa; las columnas son las de
-- uv_resumen_asistencia_estudiante_grupo (B.2) mas idPrograma, solo para estudiantes con vinculo en ese programa.
CREATE OR ALTER VIEW [dbo].[uv_resumen_asistencia_estudiante_programa_grupo]
AS
SELECT  r.idEstudianteGrupo,
        r.idEstudiante,
        r.idGrupo,
        r.idAsignatura,
        idPrograma = egp.idPrograma,
        r.idPeriodoAcademico,
        r.codigoEstadoEstudiante,
        r.sesionesEjecutadas,
        r.asistencias,
        r.faltasSinJustaCausa,
        r.excusas,
        r.porcentajeInasistencia,
        r.codigoPermanencia,
        r.tomasDictadas,
        r.horasDictadas,
        r.horasAsistidas,
        r.horasFalta,
        r.horasExcusa,
        r.horasSinRegistro,
        r.porcentajeAsistenciaHoras,
        r.porcentajeExcusaHoras,
        r.porcentajeSinRegistroHoras,
        r.porcentajeInasistenciaSesiones,
        r.umbralAdvertencia,
        r.umbralPerdida,
        r.sesionesAsistidas,
        r.sesionesConFaltaSinJustaCausa,
        r.sesionesConExcusa
FROM    uv_resumen_asistencia_estudiante_grupo r
INNER JOIN uv_estudiante_grupo_programa egp ON egp.id = r.idEstudianteGrupo
GO

-- >>> stored-procedures/usp_internal_asegurar_estudiante_programa_grupo
-- =============================================================================
-- Procedimiento: [dbo].[usp_internal_asegurar_estudiante_programa_grupo]   (INTERNO: DENY EXECUTE al runtime)
-- CULM-001 B2NM (DEC-020, R7, S3): garantiza que la matricula de un estudiante en un grupo tenga al menos un
-- EstudiantePrograma en un programa del grupo (ufn_programas_grupo). Reglas, en este orden:
--   (1) si ya tiene vinculo con algun programa del grupo, lo devuelve y no crea nada;
--   (2) si no y el grupo tiene un unico programa, crea el vinculo con ese programa;
--   (3) si no y el grupo tiene varios, exige @idProgramaElegido entre los programas del grupo: EST_005 si falta,
--       EST_006 si es ajeno; y crea el vinculo.
-- Un grupo sin programa vigente (limitacion O-N10) no crea vinculo y devuelve @idProgramaResultado NULL.
-- Sin ROLLBACK propio: corre dentro de la transaccion del llamador. La unicidad se protege con UPDLOCK/HOLDLOCK sobre
-- EstudiantePrograma (y el indice unico UX_EstudiantePrograma_estudiante_programa como ultima defensa).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_asegurar_estudiante_programa_grupo]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idProgramaElegido       UNIQUEIDENTIFIER = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idProgramaResultado     UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @totalProgramas INT;

    SELECT
        @idProgramaResultado = NULL,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

    SELECT @totalProgramas = COUNT(*) FROM dbo.ufn_programas_grupo(@idGrupo);

    -- (1) vinculo previo con un programa del grupo
    SELECT TOP 1 @idProgramaResultado = ep.programa
    FROM dbo.EstudiantePrograma ep WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.ufn_programas_grupo(@idGrupo) pg ON pg.idPrograma = ep.programa
    WHERE ep.estudiante = @idEstudiante
    ORDER BY ep.programa;

    IF @idProgramaResultado IS NOT NULL OR @totalProgramas = 0
        RETURN;

    -- (2) un unico programa en el grupo
    IF @totalProgramas = 1
        SELECT @idProgramaResultado = pg.idPrograma FROM dbo.ufn_programas_grupo(@idGrupo) pg;
    ELSE
    BEGIN
        -- (3) varios programas: el programa elegido es obligatorio y debe ser del grupo
        IF @idProgramaElegido IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'EST_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) pg WHERE pg.idPrograma = @idProgramaElegido)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'EST_006',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            RETURN;
        END

        SET @idProgramaResultado = @idProgramaElegido;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WITH (UPDLOCK, HOLDLOCK)
                   WHERE estudiante = @idEstudiante AND programa = @idProgramaResultado)
        INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
        VALUES (NEWID(), @idEstudiante, @idProgramaResultado);
END;
GO

-- >>> stored-procedures/usp_internal_asociar_asignatura_plan
-- =============================================================================
-- Procedimiento: [dbo].[usp_internal_asociar_asignatura_plan]   (INTERNO: DENY EXECUTE al runtime)
-- CULM-001 B2NM (DEC-019, R1, R3): crea o reactiva el vinculo (asignatura, semestre de un plan) con su caracter.
--   * Resuelve el SemestrePlanEstudio por plan + numero de semestre (PLA_004 si no existe).
--   * Resuelve el caracter activo por codigo; con @codigoCaracter NULL lee ASIGNATURA_PLAN/CARACTER_DEFECTO (sin literales).
--     Un caracter inexistente o inactivo es ASI_007.
--   * Con UPDLOCK/HOLDLOCK: un vinculo activo en el mismo u otro semestre del plan es ASI_003; un vinculo inactivo en el mismo
--     semestre se reactiva (misma fila, conserva fechaVinculacionUtc, TD aceptada); si no, se inserta.
-- Sin transaccion propia: corre dentro de la del llamador (usp_crear_asignatura, usp_asociar_asignatura_plan).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_asociar_asignatura_plan]
(
    @idAsignatura            UNIQUEIDENTIFIER,
    @idPlanEstudio           UNIQUEIDENTIFIER,
    @semestreNumero          INT,
    @codigoCaracter          NVARCHAR(3),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSpe UNIQUEIDENTIFIER, @idCaracter UNIQUEIDENTIFIER, @idVinculoInactivo UNIQUEIDENTIFIER;
    DECLARE @codigoEfectivo NVARCHAR(3) = COALESCE(NULLIF(TRIM(@codigoCaracter), N''),
                                                   CAST(dbo.ufn_obtener_parametro('ASIGNATURA_PLAN', 'CARACTER_DEFECTO') AS NVARCHAR(3)));
    DECLARE @codigoRechazo NVARCHAR(10);

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

    SELECT @idSpe = spe.id
    FROM dbo.SemestrePlanEstudio spe
    INNER JOIN dbo.Semestre s ON s.id = spe.semestre
    WHERE spe.planEstudio = @idPlanEstudio AND s.numero = @semestreNumero;

    SELECT @idCaracter = c.id FROM dbo.CaracterAsignaturaPlan c WHERE c.codigo = @codigoEfectivo AND c.estado = 1;

    IF @idSpe IS NULL
        SET @codigoRechazo = 'PLA_004';
    ELSE IF @idCaracter IS NULL
        SET @codigoRechazo = 'ASI_007';
    ELSE IF EXISTS (SELECT 1
                    FROM dbo.AsignaturaPlanEstudio ape WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                    WHERE ape.asignatura = @idAsignatura AND spe.planEstudio = @idPlanEstudio AND ape.estaActivo = 1)
        SET @codigoRechazo = 'ASI_003';

    IF @codigoRechazo IS NOT NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = @codigoRechazo,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
        RETURN;
    END

    SELECT @idVinculoInactivo = ape.id
    FROM dbo.AsignaturaPlanEstudio ape WITH (UPDLOCK, HOLDLOCK)
    WHERE ape.asignatura = @idAsignatura AND ape.semestrePlanEstudio = @idSpe AND ape.estaActivo = 0;

    IF @idVinculoInactivo IS NOT NULL
        UPDATE dbo.AsignaturaPlanEstudio
        SET estaActivo = 1, fechaDesvinculacionUtc = NULL, caracter = @idCaracter
        WHERE id = @idVinculoInactivo;
    ELSE
        INSERT INTO dbo.AsignaturaPlanEstudio (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc, fechaDesvinculacionUtc)
        VALUES (NEWID(), @idAsignatura, @idSpe, @idCaracter, 1, SYSUTCDATETIME(), NULL);
END;
GO

-- >>> stored-procedures/usp_internal_matricular_por_token
-- HU176B: nucleo interno de la matricula atomica por token o PIN de una ventana ACTIVA. Lo invocan las fachadas
-- usp_matricular_estudiante_por_token (autenticado) y usp_registrar_estudiante_por_token_publico (publico). NO se concede
-- EXECUTE al rol de runtime. CONTRACT A2.
--   * @idUsuarioAutenticado NO NULL: modo autenticado: RBAC ESTUDIANTE; el estudiante es el de ese usuario.
--   * @idUsuarioAutenticado NULL: modo publico: crea Usuario (ACTIVO, correoConfirmado = 0) y Estudiante; el correo debe ser
--     institucional (IDENT-001: VCE_001). Documento o correo ya existentes: MQR_005 sin cambios.
--   * Reglas de HU050 via usp_registrar_estudiante_en_grupo_interno (cupo, cruce, duplicado, programa). El estado de la
--     matricula es el parametro MATRICULA_QR/ESTADO_MATRICULA (sin literal quemado), validado ANTES de escribir.
--   * Atomico: la expiracion perezosa de la ventana persiste; el trabajo de negocio se revierte hasta su savepoint ante
--     cualquier falla posterior a la escritura.
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_matricular_por_token]
(
    @idCorrelacion            UNIQUEIDENTIFIER,
    @tokenHash                VARBINARY(32),
    @pin                      NCHAR(6),
    @idUsuarioAutenticado     UNIQUEIDENTIFIER,
    @idTipoIdentificacion     UNIQUEIDENTIFIER,
    @numeroIdentificacion     INT,
    @primerNombre             NVARCHAR(50),
    @segundoNombre            NVARCHAR(50),
    @primerApellido           NVARCHAR(50),
    @segundoApellido          NVARCHAR(50),
    @correo                   NVARCHAR(100),
    @password                 NVARCHAR(500),
    @mensajeUsuarioResultado  NVARCHAR(4000)   OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000)   OUTPUT,
    @estadoResultado          BIT              OUTPUT,
    @idEstudianteResultado    UNIQUEIDENTIFIER OUTPUT,
    @idUsuarioResultado       UNIQUEIDENTIFIER OUTPUT,
    @idGrupoResultado         UNIQUEIDENTIFIER OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    DECLARE @idVentana        UNIQUEIDENTIFIER;
    DECLARE @idGrupo          UNIQUEIDENTIFIER;
    DECLARE @idDocenteEmisor  UNIQUEIDENTIFIER;
    DECLARE @codigoRechazo    VARCHAR(20) = NULL;
    DECLARE @parametroRechazo NVARCHAR(255) = NULL;

    DECLARE @idUsuarioTarget    UNIQUEIDENTIFIER = NULL;
    DECLARE @idEstudianteTarget UNIQUEIDENTIFIER = NULL;
    DECLARE @correoNormalizado  NVARCHAR(100)    = LOWER(TRIM(@correo));
BEGIN
    SET NOCOUNT ON;

    SELECT @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @estadoResultado = 1,
           @idEstudianteResultado = NULL, @idUsuarioResultado = NULL, @idGrupoResultado = NULL;

    BEGIN TRY
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_hu176b_matricular;
            SET @savepointCreado = 1;
        END

        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: resolver la ventana (UPDLOCK). Puede escribir solo la expiracion perezosa.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_internal_resolver_token_matricula
                @tokenHash = @tokenHash, @pin = @pin,
                @idVentana = @idVentana OUTPUT, @idGrupo = @idGrupo OUTPUT,
                @idDocenteEmisor = @idDocenteEmisor OUTPUT, @codigoRechazo = @codigoRechazo OUTPUT;
        END

        -- PASO 3: validaciones sin escritura
        DECLARE @codigoMatricula NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_MATRICULA') AS NVARCHAR(10));

        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idUsuarioAutenticado IS NOT NULL
        BEGIN
            -- Modo autenticado: el usuario debe ser un ESTUDIANTE
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioAutenticado,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                SET @idUsuarioTarget = @idUsuarioAutenticado;
                SELECT TOP 1 @idEstudianteTarget = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioAutenticado;

                IF @idEstudianteTarget IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'GEN_001', @p_param1 = 'Estudiante',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END
        ELSE IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            -- Modo publico: datos obligatorios
            IF @idTipoIdentificacion IS NULL OR @numeroIdentificacion IS NULL OR @primerNombre IS NULL
               OR @primerApellido IS NULL OR @correoNormalizado IS NULL OR @correoNormalizado = N'' OR @password IS NULL
            BEGIN
                SET @codigoRechazo = 'GEN_002';
                SET @parametroRechazo = N'datos de registro';
            END
            -- Persona ya registrada (documento o correo): debe iniciar sesion
            ELSE IF EXISTS (
                SELECT 1 FROM dbo.Usuario u
                WHERE u.correo = @correoNormalizado
                   OR (u.tipoIdIdentificacion = @idTipoIdentificacion AND u.numeroIdentificacion = @numeroIdentificacion)
            )
                SET @codigoRechazo = 'MQR_005';
            -- IDENT-001: el correo de un alta nueva debe ser institucional
            ELSE IF dbo.ufn_correo_cumple_dominio_institucional(@correo, dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE')) = 0
            BEGIN
                SET @codigoRechazo = 'VCE_001';
                SET @parametroRechazo = CAST(dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE') AS NVARCHAR(255));
            END
        END

        -- Ya matriculado (solo se puede evaluar con estudiante conocido: modo autenticado)
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idEstudianteTarget IS NOT NULL
           AND EXISTS (
                SELECT 1
                FROM dbo.EstudianteGrupo eg
                INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.estado
                WHERE eg.estudiante = @idEstudianteTarget AND eg.grupo = @idGrupo AND es.codigo = @codigoMatricula
           )
            SET @codigoRechazo = 'MQR_004';

        DECLARE @programaVentana UNIQUEIDENTIFIER = (SELECT t.programaPorDefecto FROM dbo.TokenMatriculaGrupo t WHERE t.id = @idVentana);
        -- CULM-001 B2NM (S3 minimo): grupo multiprograma sin programaPorDefecto en la ventana y sin vinculo previo -> MQR_008,
        -- antes de crear usuario o matricula.
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
           AND (SELECT COUNT(*) FROM dbo.ufn_programas_grupo(@idGrupo)) > 1
           AND (SELECT t.programaPorDefecto FROM dbo.TokenMatriculaGrupo t WHERE t.id = @idVentana) IS NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                           INNER JOIN dbo.ufn_programas_grupo(@idGrupo) pg ON pg.idPrograma = ep.programa
                           WHERE ep.estudiante = @idEstudianteTarget)
            SET @codigoRechazo = 'MQR_008';

        -- Cupo, antes de crear nada
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno
                @idGrupo = @idGrupo,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- Estado de matricula configurado y existente, ANTES de escribir (falla rapida: un parametro mal
        -- configurado no debe dejar usuarios a medias; ademas ROLLBACK no es valido bajo INSERT ... EXEC).
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_estado_estudiante_grupo es WHERE es.codigo = UPPER(TRIM(@codigoMatricula)))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001', @p_param1 = 'Estado de matricula por QR',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- Mensaje del rechazo por catalogo
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @parametroRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: escrituras de negocio bajo un savepoint propio (la expiracion perezosa del paso 2 no se revierte)
        IF @estadoResultado = 1
        BEGIN
            SAVE TRANSACTION sp_hu176b_negocio;

            IF @idEstudianteTarget IS NULL
            BEGIN
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correo,
                    @password = @password,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @estaActivo = 1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                    SELECT TOP 1 @idUsuarioTarget = u.id FROM dbo.Usuario u WHERE u.correo = @correoNormalizado;

                IF @estadoResultado = 1
                BEGIN
                    EXEC dbo.usp_sincronizar_estudiante_interno
                        @idUsuario = @idUsuarioTarget,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;

                    IF @estadoResultado = 1
                        SELECT TOP 1 @idEstudianteTarget = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioTarget;
                END
            END

            IF @estadoResultado = 1 AND @idEstudianteTarget IS NOT NULL
            BEGIN
                EXEC dbo.usp_registrar_estudiante_en_grupo_interno
                    @idEstudiante = @idEstudianteTarget,
                    @idGrupo = @idGrupo,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @codigoEstado = @codigoMatricula,
                    @idProgramaElegido = @programaVentana,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                UPDATE dbo.TokenMatriculaGrupo SET totalMatriculas = totalMatriculas + 1 WHERE id = @idVentana;
            END
            ELSE IF XACT_STATE() = 1
            BEGIN
                -- Falla despues de escribir: se revierte solo el trabajo de negocio
                ROLLBACK TRANSACTION sp_hu176b_negocio;
                SELECT @idUsuarioTarget = NULL, @idEstudianteTarget = NULL;
            END
        END

        -- PASO 5: cierre de la transaccion propia (confirma tambien la expiracion perezosa)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() = -1
                ROLLBACK TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_hu176b_matricular;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SELECT @idUsuarioTarget = NULL, @idEstudianteTarget = NULL;
    END CATCH

    IF @estadoResultado = 1
        SELECT @idEstudianteResultado = @idEstudianteTarget, @idUsuarioResultado = @idUsuarioTarget, @idGrupoResultado = @idGrupo;
END;
GO

-- >>> stored-procedures/usp_resolver_programa_coordinador_interno
-- =============================================================================
-- Procedimiento: [dbo].[usp_resolver_programa_coordinador_interno]
-- HU065-HU070: valida correlacion y ejecutor y resuelve el programa que coordina el usuario (ambito).
-- Falla con THROW (DBCODE=...): VAL_001 (ejecutor nulo), KPI_001 (no es coordinador de un programa), KPI_002 (umbral ausente).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_programa_coordinador_interno]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @validarUmbrales   BIT = 1,
    @idPrograma        UNIQUEIDENTIFIER OUTPUT,
    @idProgramaSolicitado UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @msgP1 NVARCHAR(500);

    SET @idPrograma = NULL;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0 THROW 51000, @mensajeTecnicoResultado, 1;

    IF @idUsuarioEjecutor IS NULL OR @idUsuarioEjecutor = @guidVacio
    BEGIN
        SET @msgP1 = CAST(N'UsuarioEjecutor' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- CULM-001 B2NM (R8, S4): sin TOP 1. Con @idProgramaSolicitado se valida que sea de su coordinacion (COO_003); sin el:
    -- un programa -> ese; varios -> COO_002; ninguno -> KPI_001.
    DECLARE @totalProgramasCoordinador INT = (SELECT COUNT(*) FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor));
    IF @idProgramaSolicitado IS NOT NULL
    BEGIN
        SELECT @idPrograma = x.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) x WHERE x.idPrograma = @idProgramaSolicitado;
        IF @idPrograma IS NULL AND @totalProgramasCoordinador > 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'COO_003',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            THROW 51000, @mensajeTecnicoResultado, 1;
        END
    END
    ELSE IF @totalProgramasCoordinador = 1
        SELECT @idPrograma = x.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) x;
    ELSE IF @totalProgramasCoordinador > 1
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'COO_002',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    IF @idPrograma IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'KPI_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    IF @validarUmbrales = 1 AND dbo.ufn_clasificar_permanencia(0, N'A') IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'KPI_002',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

END;
GO

-- >>> stored-procedures/usp_validar_docente_vinculo_activo_programa_interno
-- HU093 (D12): un docente cuyo vinculo con el programa de la asignatura fue INACTIVADO no puede ser titular de grupos
-- nuevos ni asignarse a un grupo existente (DOC_009). Un docente sin ningun vinculo no se bloquea, para no romper
-- flujos de asignacion previos a la adscripcion; los grupos ya asignados se conservan (esta regla solo se aplica
-- cuando se designa un titular).
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_docente_vinculo_activo_programa_interno]
(
    @idDocente               UNIQUEIDENTIFIER,
    @idAsignatura            UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPrograma UNIQUEIDENTIFIER;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;

    -- CULM-001 B2NM (R8): sin TOP 1. DOC_009 si el docente solo tiene vinculos inactivos con los programas de la asignatura
    -- (vinculos activos de la asignatura en planes) y ninguno activo.
    SELECT TOP 1 @idPrograma = v.idPrograma
    FROM dbo.uv_asignatura_plan_estudio v
    INNER JOIN dbo.DocentePrograma dpi ON dpi.programa = v.idPrograma AND dpi.docente = @idDocente AND dpi.estado = 0
    WHERE v.idAsignatura = @idAsignatura AND v.estaActivoVinculo = 1
      AND NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio w
                      INNER JOIN dbo.DocentePrograma dpa ON dpa.programa = w.idPrograma AND dpa.docente = @idDocente AND dpa.estado = 1
                      WHERE w.idAsignatura = @idAsignatura AND w.estaActivoVinculo = 1)
    ORDER BY v.idPrograma;

    IF @idPrograma IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @idDocente AND programa = @idPrograma AND estado = 0)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'DOC_009',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
END;
GO

-- >>> stored-procedures/usp_validar_gestion_asignatura_coordinador_interno
-- =============================================================================
-- Procedimiento: [dbo].[usp_validar_gestion_asignatura_coordinador_interno]   (INTERNO)
-- REC2 + CULM-001 B2NM (DEC-019, S2, R8): valida que el ejecutor sea COORDINADOR activo y que pueda gestionar la asignatura.
--   * Sin @idPlanEstudio: basta coordinar ALGUN programa con vinculo activo de la asignatura (sin TOP 1). Con
--     @exigirTodosLosProgramas = 1 debe coordinar TODOS (datos de catalogo / estado global): si coordina solo algunos -> ASI_006.
--   * Con @idPlanEstudio: el plan debe ser de un programa que coordina (SEC_002) y la asignatura debe tener un vinculo
--     activo en ese plan (ASI_004).
-- Asignatura inexistente: VAL_002. Sin ningun programa coordinado con vinculo activo: SEC_002.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_gestion_asignatura_coordinador_interno]
(
    @idAsignatura            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @idPlanEstudio           UNIQUEIDENTIFIER = NULL,
    @exigirTodosLosProgramas BIT = 0
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaPlan           UNIQUEIDENTIFIER;
    DECLARE @totalProgramas           INT;
    DECLARE @totalCoordinados         INT;
    DECLARE @codigoRechazo            NVARCHAR(10);

BEGIN
    SET NOCOUNT ON;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;
    BEGIN TRY
        -- PASO 1: Ejecutor obligatorio
        IF @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: Perfil COORDINADOR activo
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Existencia de la asignatura
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @idAsignaturaDefecto)
            SET @codigoRechazo = 'VAL_002';

        -- PASO 4: Ambito
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            IF @idPlanEstudio IS NOT NULL
            BEGIN
                SELECT @idProgramaPlan = pe.programa FROM dbo.PlanEstudio pe WHERE pe.id = @idPlanEstudio;
                IF @idProgramaPlan IS NULL
                    SET @codigoRechazo = 'PLA_002';
                ELSE IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto) cp WHERE cp.idPrograma = @idProgramaPlan)
                    SET @codigoRechazo = 'SEC_002';
                ELSE IF NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape
                                    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                                    WHERE ape.asignatura = @idAsignaturaDefecto AND spe.planEstudio = @idPlanEstudio AND ape.estaActivo = 1)
                    SET @codigoRechazo = 'ASI_004';
            END
            ELSE
            BEGIN
                SELECT @totalProgramas = COUNT(DISTINCT v.idPrograma),
                       @totalCoordinados = COUNT(DISTINCT CASE WHEN cp.idPrograma IS NOT NULL THEN v.idPrograma END)
                FROM dbo.uv_asignatura_plan_estudio v
                LEFT JOIN dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto) cp ON cp.idPrograma = v.idPrograma
                WHERE v.idAsignatura = @idAsignaturaDefecto AND v.estaActivoVinculo = 1;

                IF @totalCoordinados = 0
                    SET @codigoRechazo = 'SEC_002';
                ELSE IF @exigirTodosLosProgramas = 1 AND @totalCoordinados < @totalProgramas
                    SET @codigoRechazo = 'ASI_006';
            END
        END

        IF @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @p_param1 = 'Asignatura',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

-- >>> stored-procedures/usp_validar_gestion_grupo_coordinador_o_titular_interno
-- F1/F2/F3 (2026-11-02): validacion compartida de "quien puede gestionar el horario y las sesiones de un grupo"
-- (skill procedimientos-externos-condiciones, REC4 #5: la validacion repetida entre SP se extrae a un usp_validar_*_interno).
-- La usan usp_guardar_horarios_grupo y usp_precargar_sesiones_grupo.
--   * ejecutor obligatorio (GEN_002) con perfil COORDINADOR o DOCENTE (SEC_001);
--   * el grupo existe (VAL_002);
--   * COORDINADOR: debe coordinar el programa de la asignatura del grupo (SEC_002);
--   * DOCENTE: debe ser el titular del grupo (SEC_002).
-- Devuelve si el ejecutor actua como coordinador y el docente titular del grupo, para las reglas propias del caller.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_gestion_grupo_coordinador_o_titular_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @ejecutorEsCoordinador   BIT OUTPUT,
    @idDocenteTitular        UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignatura             UNIQUEIDENTIFIER;
    DECLARE @idPrograma               UNIQUEIDENTIFIER;
    DECLARE @idDocenteEjecutor        UNIQUEIDENTIFIER;

    SELECT
        @ejecutorEsCoordinador = 0,
        @idDocenteTitular = NULL,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Ejecutor obligatorio (GEN_002) y perfil COORDINADOR o DOCENTE (SEC_001)
        IF @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR,DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: El grupo existe (VAL_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idAsignatura = g.idAsignatura, @idDocenteTitular = g.idDocente
            FROM dbo.uv_grupo g
            WHERE g.id = @idGrupoDefecto;

            IF @idAsignatura IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002', @p_param1 = 'Grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Ambito del ejecutor
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.uv_coordinador_identidad ci WHERE ci.idUsuario = @idUsuarioEjecutorDefecto)
            BEGIN
                SET @ejecutorEsCoordinador = 1;
            END

            SELECT @idDocenteEjecutor = di.id
            FROM dbo.uv_docente_identidad di
            WHERE di.idUsuario = @idUsuarioEjecutorDefecto;
        END

        -- COORDINADOR: titular del programa de la asignatura del grupo
        IF @estadoResultado = 1 AND @ejecutorEsCoordinador = 1
        BEGIN
            -- CULM-001 B2NM (R8, O-N7): sin TOP 1. En un grupo compartido, un coordinador gestiona solo si coordina TODOS los
            -- programas vigentes del grupo (minimo privilegio, coherente con S2); si no, SEC_002.
            IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo))
               OR EXISTS (SELECT idPrograma FROM dbo.ufn_programas_grupo(@idGrupo)
                          EXCEPT
                          SELECT idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto))
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- DOCENTE: solo el titular del grupo
        IF @estadoResultado = 1 AND @ejecutorEsCoordinador = 0
           AND (@idDocenteEjecutor IS NULL OR @idDocenteEjecutor <> @idDocenteTitular)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

-- >>> stored-procedures/usp_abrir_ventana_matricula_grupo
-- HU176B: el docente titular abre la ventana de matricula por QR/PIN de su grupo.
-- El token y el PIN los genera el backend (SecureRandom); la DB solo recibe el SHA-256 del token y el PIN.
--   * RBAC DOCENTE + titularidad del grupo (SEC_002) + grupo existente + cupo disponible.
--   * Cierra cualquier ventana ACTIVA del grupo e inserta la nueva (una ventana activa por grupo).
--   * Fin de la ventana = ahora + MATRICULA_QR/DURACION_MAXIMA_MINUTOS (parametro administrable, CONTRACT A1).
--   * PIN repetido en el PIN vigente o anterior de otra ventana activa -> MQR_006 sin escrituras (el backend reintenta).
-- Resultset: tupla canonica + idVentana + fechaExpiracionUtc (extension documentada, CONTRACT §2.3).
CREATE OR ALTER PROCEDURE [dbo].[usp_abrir_ventana_matricula_grupo]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @tokenHash         VARBINARY(32),
    @pin               NCHAR(6),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL,
    @idPrograma        UNIQUEIDENTIFIER = NULL   -- CULM-001 B2NM (S3 minimo): obligatorio si el grupo tiene varios programas
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    DECLARE @idDocenteTitular   UNIQUEIDENTIFIER;
    DECLARE @idVentana          UNIQUEIDENTIFIER = NULL;
    DECLARE @fechaExpiracionUtc DATETIME2(0)     = NULL;
    DECLARE @codigoRechazo      VARCHAR(20)      = NULL;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: correlacion, ejecutor y datos del token
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@idGrupo IS NULL OR @tokenHash IS NULL OR @pin IS NULL OR @pin LIKE N'%[^0-9]%' OR LEN(@pin) <> 6)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idGrupo/tokenHash/pin',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC (DOCENTE)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutor,
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: grupo existente y titularidad
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @idDocenteTitular = d.id
            FROM dbo.Grupo g
            INNER JOIN dbo.Docente d ON d.id = g.docente
            WHERE g.id = @idGrupoDefecto AND d.usuario = @idUsuarioEjecutor;

            IF @idDocenteTitular IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: cupo disponible
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4.1 (CULM-001 B2NM, S3): programa de la ventana en grupos multiprograma (EST_005 si falta, EST_006 si es ajeno)
        IF @estadoResultado = 1 AND (SELECT COUNT(*) FROM dbo.ufn_programas_grupo(@idGrupoDefecto)) > 1
        BEGIN
            DECLARE @codigoPrograma NVARCHAR(10) = CASE
                WHEN @idPrograma IS NULL THEN 'EST_005'
                WHEN NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupoDefecto) pg WHERE pg.idPrograma = @idPrograma) THEN 'EST_006' END;
            IF @codigoPrograma IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoPrograma,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        ELSE IF @estadoResultado = 1 AND @idPrograma IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupoDefecto) pg WHERE pg.idPrograma = @idPrograma)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'EST_006',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: escritura atomica
        IF @estadoResultado = 1
        BEGIN
            DECLARE @estadoActiva  NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA') AS NVARCHAR(10));
            DECLARE @estadoCerrada NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_CERRADA') AS NVARCHAR(10));
            DECLARE @duracionMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'DURACION_MAXIMA_MINUTOS');
            DECLARE @ahora DATETIME2(0) = SYSUTCDATETIME();

            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_hu176b_abrir;
                SET @savepointCreado = 1;
            END

            -- PIN unico frente al vigente y al anterior de las ventanas activas de OTROS grupos
            IF EXISTS (
                SELECT 1 FROM dbo.TokenMatriculaGrupo t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.estado = @estadoActiva AND t.grupo <> @idGrupoDefecto AND (t.pin = @pin OR t.pinAnterior = @pin)
            )
                SET @codigoRechazo = 'MQR_006';

            IF @codigoRechazo IS NULL
            BEGIN
                UPDATE dbo.TokenMatriculaGrupo
                SET estado = @estadoCerrada, fechaCierreUtc = @ahora
                WHERE grupo = @idGrupoDefecto AND estado = @estadoActiva;

                SET @idVentana = NEWID();
                SET @fechaExpiracionUtc = DATEADD(MINUTE, @duracionMinutos, @ahora);

                INSERT INTO dbo.TokenMatriculaGrupo
                    (id, grupo, docenteEmisor, tokenHash, pin, tokenHashAnterior, pinAnterior, fechaRotacionUtc,
                     estado, fechaEmisionUtc, fechaExpiracionUtc, fechaCierreUtc, totalMatriculas, programaPorDefecto)
                VALUES
                    (@idVentana, @idGrupoDefecto, @idDocenteTitular, @tokenHash, @pin, NULL, NULL, @ahora,
                     @estadoActiva, @ahora, @fechaExpiracionUtc, NULL, 0, @idPrograma);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004', @p_param1 = 'Ventana de matricula',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- La rama de rechazo no escribe nada: solo se confirma la transaccion propia.
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_hu176b_abrir;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SET @idVentana = NULL;
        SET @fechaExpiracionUtc = NULL;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idVentana               = IIF(@estadoResultado = 1, @idVentana, NULL),
        fechaExpiracionUtc      = IIF(@estadoResultado = 1, @fechaExpiracionUtc, NULL);
END;
GO

-- >>> stored-procedures/usp_actualizar_asignatura
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_asignatura]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @codigo             NVARCHAR(50),
    @nombre             NVARCHAR(50),
    @creditos           INT,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @semestreNumero     INT,
    @nombreArea         NVARCHAR(100),
    @nombreComponente   NVARCHAR(100),
    @idCorrelacion      UNIQUEIDENTIFIER,
    -- REC2 (auditoria BD 2026-10-28): ejecutor obligatorio (GEN_002 si llega NULL). El DEFAULT solo conserva la
    -- compatibilidad de firma; RBAC COORDINADOR + titularidad del PROGRAMA se validan en usp_validar_gestion_asignatura_coordinador_interno.
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL,
    @codigoCaracter     NVARCHAR(3) = NULL   -- CULM-001 B2NM: NULL conserva el caracter actual del vinculo
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDefecto        NVARCHAR(50)     = UPPER(TRIM(@codigo));
    DECLARE @nombreDefecto        NVARCHAR(50)     = TRIM(@nombre);
    DECLARE @idAreaResolved       UNIQUEIDENTIFIER;
    DECLARE @idComponenteResolved UNIQUEIDENTIFIER;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @idSpeNuevo           UNIQUEIDENTIFIER;
    DECLARE @idCaracterNuevo      UNIQUEIDENTIFIER;
    DECLARE @cambiaCatalogo       BIT = 0;
    DECLARE @codigoRechazo        NVARCHAR(10);

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio, perfil COORDINADOR, existencia de la asignatura y titularidad del
        --         programa (REC2: logica comun en usp_validar_gestion_asignatura_coordinador_interno)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno
                @idAsignatura = @idAsignaturaDefecto,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @idCorrelacion = @idCorrelacionDefecto,
                @idPlanEstudio = @idPlanEstudio,   -- CULM-001 B2NM: ambito por el plan indicado (SEC_002 / ASI_004)
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.1: Creditos (decision de John 2026-11-04): si llegan deben ser mayores que cero (ASI_001); nulos
        --           conservan los actuales (actualizacion parcial, como el resto de campos)
        IF @estadoResultado = 1 AND @creditos IS NOT NULL AND @creditos <= 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ASI_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar unicidad del código si cambia
        IF @estadoResultado = 1 AND @codigoDefecto IS NOT NULL AND @codigoDefecto <> ''
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[Asignatura] WHERE UPPER(TRIM(codigo)) = @codigoDefecto AND id <> @idAsignaturaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ASI_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Actualización de la Asignatura
        -- P5 (2026-11-04): el área y el componente, si llegan, deben existir en sus tablas (GEN_001); vacíos conservan el actual.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_resolver_area_componente_asignatura_interno
                @area = @nombreArea,
                @componente = @nombreComponente,
                @obligatorios = 0,
                @idCorrelacion = @idCorrelacionDefecto,
                @idArea = @idAreaResolved OUTPUT,
                @idComponente = @idComponenteResolved OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4.1 (CULM-001 B2NM, S2): semestre y caracter del vinculo en el plan indicado. NULL conserva el actual.
        IF @estadoResultado = 1 AND @semestreNumero IS NOT NULL
        BEGIN
            SELECT @idSpeNuevo = spe.id
            FROM dbo.SemestrePlanEstudio spe
            INNER JOIN dbo.Semestre sm ON sm.id = spe.semestre
            WHERE spe.planEstudio = @idPlanEstudio AND sm.numero = @semestreNumero;
            IF @idSpeNuevo IS NULL
                SET @codigoRechazo = 'PLA_004';
        END
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND NULLIF(TRIM(@codigoCaracter), N'') IS NOT NULL
        BEGIN
            SELECT @idCaracterNuevo = c.id FROM dbo.CaracterAsignaturaPlan c WHERE c.codigo = TRIM(@codigoCaracter) AND c.estado = 1;
            IF @idCaracterNuevo IS NULL
                SET @codigoRechazo = 'ASI_007';
        END

        -- PASO 4.2: los datos de catalogo de una asignatura compartida solo los cambia quien coordina todos sus programas (ASI_006)
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            SELECT @cambiaCatalogo = IIF(
                   (@codigoDefecto IS NOT NULL AND @codigoDefecto <> '' AND a.codigo <> @codigoDefecto)
                OR (@nombreDefecto IS NOT NULL AND @nombreDefecto <> '' AND a.nombre <> @nombreDefecto)
                OR (@creditos IS NOT NULL AND a.credito <> @creditos)
                OR (@idAreaResolved IS NOT NULL AND a.area <> @idAreaResolved)
                OR (@idComponenteResolved IS NOT NULL AND a.componente <> @idComponenteResolved), 1, 0)
            FROM dbo.Asignatura a WHERE a.id = @idAsignaturaDefecto;

            IF @cambiaCatalogo = 1
               AND EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
                           WHERE v.idAsignatura = @idAsignaturaDefecto AND v.estaActivoVinculo = 1
                             AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE cp.idPrograma = v.idPrograma))
                SET @codigoRechazo = 'ASI_006';
        END

        -- PASO 4.3: un vinculo (inactivo) ya ocupa el semestre destino -> ASI_003
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idSpeNuevo IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape
                       WHERE ape.asignatura = @idAsignaturaDefecto AND ape.semestrePlanEstudio = @idSpeNuevo)
           AND NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape2
                           WHERE ape2.asignatura = @idAsignaturaDefecto AND ape2.semestrePlanEstudio = @idSpeNuevo AND ape2.estaActivo = 1)
            SET @codigoRechazo = 'ASI_003';

        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            IF @cambiaCatalogo = 1
                UPDATE dbo.Asignatura
                SET codigo = CASE WHEN @codigoDefecto IS NOT NULL AND @codigoDefecto <> '' THEN @codigoDefecto ELSE codigo END,
                    nombre = CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE nombre END,
                    credito = CASE WHEN @creditos IS NOT NULL THEN @creditos ELSE credito END,
                    area = CASE WHEN @idAreaResolved IS NOT NULL THEN @idAreaResolved ELSE area END,
                    componente = CASE WHEN @idComponenteResolved IS NOT NULL THEN @idComponenteResolved ELSE componente END
                WHERE id = @idAsignaturaDefecto;

            -- La MISMA fila de la tabla puente cambia de semestre / caracter (no se crea otra: la asignatura de un solo plan sigue 1:1)
            UPDATE ape
            SET ape.semestrePlanEstudio = COALESCE(@idSpeNuevo, ape.semestrePlanEstudio),
                ape.caracter = COALESCE(@idCaracterNuevo, ape.caracter)
            FROM dbo.AsignaturaPlanEstudio ape
            INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
            WHERE ape.asignatura = @idAsignaturaDefecto AND spe.planEstudio = @idPlanEstudio AND ape.estaActivo = 1;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Asignatura',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            IF @transaccionPropia = 1 COMMIT TRANSACTION;
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

-- >>> stored-procedures/usp_asociar_asignatura_plan
-- =============================================================================
-- Procedimiento: [dbo].[usp_asociar_asignatura_plan]
-- CULM-001 B2NM (DEC-019, R3): asocia una asignatura existente (catalogo) a un plan de estudios, con semestre y caracter.
-- RBAC COORDINADOR; el plan existe (PLA_002) y es de un programa suyo (SEC_002); la asignatura existe y esta activa, y tiene
-- algun vinculo en un programa de la misma institucion (si no, GEN_001). Reglas de vinculo en usp_internal_asociar_asignatura_plan
-- (PLA_004, ASI_003, ASI_007). Salida canonica (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_asociar_asignatura_plan]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @semestreNumero     INT,
    @codigoCaracter     NVARCHAR(3) = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaPlan UNIQUEIDENTIFIER, @idInstitucionPlan UNIQUEIDENTIFIER;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @transaccionPropia BIT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'COORDINADOR', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- Plan existente (PLA_002) y titularidad del programa del plan (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idProgramaPlan = pe.programa, @idInstitucionPlan = f.institucion
            FROM dbo.PlanEstudio pe
            INNER JOIN dbo.Programa p ON p.id = pe.programa
            INNER JOIN dbo.Facultad f ON f.id = p.facultad
            WHERE pe.id = @idPlanEstudio;

            IF @idProgramaPlan IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PLA_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
                EXEC dbo.usp_validar_titularidad_jerarquica_interno
                    @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idProgramaPlan, @tipoEntidadPadre = 'PROGRAMA',
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
        END

        -- La asignatura existe, esta activa y pertenece a la institucion del plan (tiene algun vinculo en ella)
        IF @estadoResultado = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
                           WHERE v.idAsignatura = @idAsignatura AND v.estaActivaAsignatura = 1 AND v.idInstitucion = @idInstitucionPlan)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_001', @p_param1 = 'Asignatura',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            EXEC dbo.usp_internal_asociar_asignatura_plan
                @idAsignatura = @idAsignatura, @idPlanEstudio = @idPlanEstudio, @semestreNumero = @semestreNumero,
                @codigoCaracter = @codigoCaracter, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Vinculo de asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                IF @transaccionPropia = 1 COMMIT TRANSACTION;
            END
            ELSE IF @transaccionPropia = 1
                ROLLBACK TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT idCorrelacion = @idCorrelacionDefecto, mensajeUsuarioResultado = @mensajeUsuarioResultado,
           mensajeTecnicoResultado = @mensajeTecnicoResultado, estadoResultado = @estadoResultado;
END;
GO

-- >>> stored-procedures/usp_buscar_asignaturas_paginado
-- ============================================================================
-- usp_buscar_asignaturas_paginado (HU143 busqueda transversal de asignaturas)
--
-- Catalogo de asignaturas con su programa, facultad, plan, semestre, area, componente y creditos. Es transversal a
-- los programas y planes del ambito del ejecutor: el ADMINISTRADOR busca en todas las facultades de su institucion y
-- el DECANO solo en su facultad (decision del dueno del producto, 2026-11-02). @busqueda compara contra el codigo y el
-- nombre de la asignatura; @idFacultad y @estaActiva acotan el resultado.
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001).
-- Ambito: perfiles ADMINISTRADOR o DECANO; programas de uv_auth_programa (fail-closed) restringidos a la institucion
-- que administra el ejecutor (uv_administrador) o a la facultad a su cargo (uv_decano).
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_buscar_asignaturas_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @busqueda           NVARCHAR(100)    = NULL,
    @idFacultad         UNIQUEIDENTIFIER = NULL,
    @estaActiva         BIT              = NULL
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @busquedaFiltro          NVARCHAR(100) = NULLIF(TRIM(@busqueda), '');
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: Correlacion, ejecutor, perfil y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'ADMINISTRADOR,DECANO',
            @numeroPagina = @numeroPagina,
            @tamanoPagina = @tamanoPagina,
            @idUsuarioValidado = @idUsuario OUTPUT,
            @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 2: Consulta y retorno de resultados
        WITH programasAmbito AS (
            SELECT  p.id, p.nombrePrograma, p.idFacultad, p.nombreFacultad
            FROM    dbo.uv_auth_programa p
            WHERE   p.idInstitucion IN (SELECT a.idInstitucion FROM dbo.uv_administrador a WHERE a.idUsuario = @idUsuario)
               OR   p.idFacultad IN (SELECT d.idFacultad FROM dbo.uv_decano d WHERE d.idUsuario = @idUsuario)
        )
        -- CULM-001 B2NM (DEC-019): 1 fila por asignatura (catalogo); planes = vinculos activos en el ambito, totalPlanes = su conteo.
        SELECT
            idAsignatura          = a.id,
            codigo                = a.codigo,
            nombre                = a.nombre,
            credito               = a.credito,
            nombreArea            = a.nombreArea,
            nombreComponente      = a.nombreComponente,
            planes                = CAST((SELECT STRING_AGG(CONCAT(v.nombrePrograma, N' · Plan ', v.inpPlanEstudio, N' · S', v.numeroSemestre), N'; ')
                                          WITHIN GROUP (ORDER BY v.nombrePrograma, v.inpPlanEstudio)
                                          FROM dbo.uv_asignatura_plan_estudio v
                                          INNER JOIN programasAmbito pa ON pa.id = v.idPrograma
                                          WHERE v.idAsignatura = a.id AND v.estaActivoVinculo = 1
                                            AND (@idFacultad IS NULL OR pa.idFacultad = @idFacultad)) AS NVARCHAR(1000)),
            totalPlanes           = (SELECT COUNT(*)
                                     FROM dbo.uv_asignatura_plan_estudio v
                                     INNER JOIN programasAmbito pa ON pa.id = v.idPrograma
                                     WHERE v.idAsignatura = a.id AND v.estaActivoVinculo = 1
                                       AND (@idFacultad IS NULL OR pa.idFacultad = @idFacultad)),
            estaActivaAsignatura  = a.estaActivaAsignatura,
            totalRegistros        = COUNT(*) OVER()
        FROM dbo.uv_asignatura a
        WHERE
            EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
                    INNER JOIN programasAmbito pa ON pa.id = v.idPrograma
                    WHERE v.idAsignatura = a.id AND v.estaActivoVinculo = 1 AND (@idFacultad IS NULL OR pa.idFacultad = @idFacultad))
            AND (@estaActiva IS NULL OR a.estaActivaAsignatura = @estaActiva)
            AND (
                @busquedaFiltro IS NULL
                OR CHARINDEX(@busquedaFiltro, a.codigo) > 0
                OR CHARINDEX(@busquedaFiltro, a.nombre) > 0
            )
        ORDER BY a.nombre ASC, a.codigo ASC, a.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO

-- >>> stored-procedures/usp_buscar_estudiante_por_documento_grupo
-- ============================================================================
-- usp_buscar_estudiante_por_documento_grupo (CULM-001 A.2-15; DEC-027; F-DOC-013; CONTRACT §8.2.3 A2-DB-9)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo, fuera de ambito o documento
-- invalido). Busqueda del estudiante a matricular a mano (GET /api/v1/grupos/{grupoId}/estudiantes/busqueda) y unica via
-- para resolver el estudiante de una matricula manual sin correo:
--   * Titularidad dentro del SP: el ejecutor debe ser el DOCENTE titular del grupo (Grupo.docente -> Docente.usuario);
--     si no, o el grupo no existe: THROW 51000 con DBCODE=SEC_002 (403).
--   * Documento nulo o @numeroIdentificacion <= 0: THROW 51000 con DBCODE=VAL_001 (400).
--   * Busqueda EXACTA por (Usuario.tipoIdIdentificacion, Usuario.numeroIdentificacion) de un usuario CON fila Estudiante
--     (un usuario que solo es docente, coordinador, decano o administrador da 0 filas). Sin LIKE y sin listar: 0 o 1 fila.
--   * Alcance institucional: solo devuelve al estudiante si no tiene vinculos (alta pendiente de matricula; excepcion
--     deliberada al fail-closed de DEC-031 §3, A2-C1) o si alguno de sus vinculos (EstudiantePrograma o EstudianteGrupo)
--     es de la institucion del grupo. Uno de otra institucion da 0 filas, igual que uno inexistente.
--   * Datos minimos: nombres, nombreCompleto, numeroIdentificacion, correoEnmascarado (primer caracter + '***' +
--     '@dominio'; el correo real nunca sale) y codigoEstadoMatriculaGrupo (su matricula en ESE grupo o NULL).
-- Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_buscar_estudiante_por_documento_grupo]
(
    @idGrupo              UNIQUEIDENTIFIER,
    @idTipoIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion INT,
    @idCorrelacion        UNIQUEIDENTIFIER,
    @idUsuarioEjecutor    UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucionGrupo   UNIQUEIDENTIFIER;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 3: titularidad del docente ejecutor sobre el grupo (SEC_002)
    IF @estadoResultado = 1
       AND NOT EXISTS (SELECT 1 FROM dbo.Grupo g
                       INNER JOIN dbo.Docente d ON d.id = g.docente
                       INNER JOIN dbo.Usuario u ON u.id = d.usuario
                       WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor AND u.estado = 1)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SEC_002',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 4: documento obligatorio y positivo (VAL_001)
    IF @estadoResultado = 1 AND (@idTipoIdentificacion IS NULL OR @numeroIdentificacion IS NULL OR @numeroIdentificacion <= 0)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'numeroIdentificacion',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 5: institucion del grupo
    SELECT @idInstitucionGrupo = f.institucion
    FROM dbo.Grupo g
    INNER JOIN dbo.uv_grupo_programa gpx ON gpx.idGrupo = g.id   -- CULM-001 B2NM: vigencia S1
    INNER JOIN dbo.Programa p ON p.id = gpx.idPrograma
    INNER JOIN dbo.Facultad f ON f.id = p.facultad
    WHERE g.id = @idGrupo;

    -- PASO 6: busqueda exacta de un estudiante, con alcance institucional y datos minimos
    SELECT TOP 1
        idEstudiante               = e.id,
        primerNombre               = u.primerNombre,
        segundoNombre              = u.segundoNombre,
        primerApellido             = u.primerApellido,
        segundoApellido            = u.segundoApellido,
        nombreCompleto             = CAST(CONCAT(LTRIM(RTRIM(CONCAT(u.primerNombre, N' ', u.segundoNombre))), N' ',
                                         LTRIM(RTRIM(CONCAT(u.primerApellido, N' ', u.segundoApellido)))) AS NVARCHAR(400)),
        numeroIdentificacion       = u.numeroIdentificacion,
        correoEnmascarado          = CAST(IIF(CHARINDEX(N'@', u.correo) > 1,
                                         CONCAT(LEFT(u.correo, 1), N'***', SUBSTRING(u.correo, CHARINDEX(N'@', u.correo), LEN(u.correo))),
                                         CONCAT(LEFT(u.correo, 1), N'***')) AS NVARCHAR(120)),
        codigoEstadoMatriculaGrupo = (SELECT TOP 1 es.codigo FROM dbo.EstudianteGrupo eg
                                      INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.estado
                                      WHERE eg.estudiante = e.id AND eg.grupo = @idGrupo
                                      ORDER BY eg.id)
    FROM dbo.Usuario u
    INNER JOIN dbo.Estudiante e ON e.usuario = u.id
    WHERE u.tipoIdIdentificacion = @idTipoIdentificacion
      AND u.numeroIdentificacion = @numeroIdentificacion
      AND (
            -- sin vinculos: alta pendiente de matricula (A2-C1)
            (NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = e.id)
             AND NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg WHERE eg.estudiante = e.id))
            -- algun vinculo en la institucion del grupo
            OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                       INNER JOIN dbo.Programa p ON p.id = ep.programa
                       INNER JOIN dbo.Facultad f ON f.id = p.facultad
                       WHERE ep.estudiante = e.id AND f.institucion = @idInstitucionGrupo)
            OR EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg
                       INNER JOIN dbo.Grupo g ON g.id = eg.grupo
                       INNER JOIN dbo.uv_grupo_programa gpx ON gpx.idGrupo = g.id   -- CULM-001 B2NM: vigencia S1
                       INNER JOIN dbo.Programa p ON p.id = gpx.idPrograma
                       INNER JOIN dbo.Facultad f ON f.id = p.facultad
                       WHERE eg.estudiante = e.id AND f.institucion = @idInstitucionGrupo)
          )
    ORDER BY e.id;
END;
GO

-- >>> stored-procedures/usp_consultar_aforo_grupos_facultad
-- ============================================================================
-- usp_consultar_aforo_grupos_facultad (HU144). READ_QUERY_RESULTSET paginado. Solo lectura.
-- Aforo = matriculados activos / cupo maximo (D4); NULL si el cupo es 0. No se recorta por encima de 100 %.
-- @soloHabilitados = 1 (defecto) lista solo grupos habilitados en su periodo. Orden: aforo descendente (NULL al final).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_aforo_grupos_facultad]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @idPrograma         UNIQUEIDENTIFIER = NULL,
    @soloHabilitados    BIT              = 1
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idFacultad UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_facultad_decano_interno)
    EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idFacultad = @idFacultad OUTPUT;
    DECLARE @tamanoMaximo INT = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO')), '') AS INT);
    -- PASO 2: Validacion de negocio (PAG_001)
    IF @numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo
    BEGIN
        SET @msgP1 = CAST(@numeroPagina AS NVARCHAR(500));
        DECLARE @msgP2 NVARCHAR(500) = CAST(@tamanoPagina AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PAG_001',
            @p_param1 = @msgP1,
            @p_param2 = @msgP2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
    DECLARE @offset INT = (@numeroPagina - 1) * @tamanoPagina;

    -- PASO 3: Validacion de negocio (usp_validar_programa_en_facultad_interno)
    IF @idPrograma IS NOT NULL
        EXEC dbo.usp_validar_programa_en_facultad_interno @idFacultad = @idFacultad, @idPrograma = @idPrograma;
    -- PASO 4: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_facultad_interno)
    EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @idFacultad, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 5: Consulta y retorno de resultados
    SELECT
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        idAsignatura = g.idAsignatura,
        nombreAsignatura = g.nombreAsignatura,
        programas = p.nombrePrograma,
        cupoMaximo = g.capacidadMaximaPermitida,
        matriculadosActivos = g.estudiantesActivos,
        cuposDisponibles = g.cuposDisponibles,
        tasaAforo = CAST(IIF(ISNULL(g.capacidadMaximaPermitida, 0) = 0, NULL, 100.0 * g.estudiantesActivos / g.capacidadMaximaPermitida) AS DECIMAL(7,2)),
        grupoEstaHabilitado = CAST(g.grupoEstaHablitado AS BIT),
        totalRegistros = COUNT(*) OVER()
    -- CULM-001 B2NM (R5): 1 fila por grupo; idPrograma/nombrePrograma = primer programa del ambito, nombrePrograma lista todos.
    FROM dbo.uv_grupo g
    CROSS APPLY (SELECT TOP 1 id = x.id,
                              nombrePrograma = (SELECT STRING_AGG(y.nombrePrograma, N', ') WITHIN GROUP (ORDER BY y.nombrePrograma)
                                                FROM dbo.uv_grupo_programa gy
                                                INNER JOIN dbo.uv_programa y ON y.id = gy.idPrograma
                                                WHERE gy.idGrupo = g.id AND y.idFacultad = @idFacultad)
                 FROM dbo.uv_grupo_programa gp
                 INNER JOIN dbo.uv_programa x ON x.id = gp.idPrograma
                 WHERE gp.idGrupo = g.id AND x.idFacultad = @idFacultad AND (@idPrograma IS NULL OR x.id = @idPrograma)
                 ORDER BY x.nombrePrograma, x.id) p
    WHERE g.idPeriodoAcademico = @idPeriodo
      AND (ISNULL(@soloHabilitados, 1) = 0 OR g.grupoEstaHablitado = 1)
    ORDER BY IIF(ISNULL(g.capacidadMaximaPermitida, 0) = 0, 1, 0) ASC,
             100.0 * g.estudiantesActivos / NULLIF(g.capacidadMaximaPermitida, 0) DESC,
             g.codigo ASC, g.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_alerta_temprana_programa
-- ============================================================================
-- usp_consultar_alerta_temprana_programa (HU066, HU070). READ_QUERY_RESULTSET paginado. Solo lectura.
-- Una fila por persona: % = el mayor de sus matriculas activas, faltas = suma, clasificacion = la peor (D6).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_alerta_temprana_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @semaforo           NVARCHAR(5)      = NULL,
    @filtroTexto        NVARCHAR(100)    = NULL
,
    @idPrograma UNIQUEIDENTIFIER = NULL)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idPeriodo UNIQUEIDENTIFIER;
    DECLARE @filtro NVARCHAR(100) = NULLIF(TRIM(@filtroTexto), '');

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idPrograma = @idPrograma OUTPUT, @idProgramaSolicitado = @idPrograma;
    DECLARE @tamanoMaximo INT = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO')), '') AS INT);
    -- PASO 2: Validacion de negocio (PAG_001)
    IF @numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo
    BEGIN
        SET @msgP1 = CAST(@numeroPagina AS NVARCHAR(500));
        DECLARE @msgP2 NVARCHAR(500) = CAST(@tamanoPagina AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PAG_001',
            @p_param1 = @msgP1,
            @p_param2 = @msgP2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
    DECLARE @offset INT = (@numeroPagina - 1) * @tamanoPagina;
    -- PASO 3: Validacion de negocio (GEN_002)
    IF @semaforo IS NOT NULL AND @semaforo NOT IN (N'VERDE', N'AMBAR', N'ROJO')
    BEGIN
        SET @msgP1 = CAST(N'semaforo' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_interno)
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 5: Consulta y retorno de resultados
    WITH persona AS (
        SELECT  r.idEstudiante,
                totalMatriculasActivas = COUNT(*),
                porcentajeInasistencia = MAX(r.porcentajeInasistencia),
                faltasSinJustaCausa = SUM(r.faltasSinJustaCausa),
                tomasDictadas = SUM(r.tomasDictadas),
                horasDictadas = SUM(r.horasDictadas),
                horasFalta = SUM(r.horasFalta),
                peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
        FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
        WHERE   r.idPrograma = @idPrograma AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY r.idEstudiante
    )
    -- PASO 6: Consulta y retorno de resultados
    SELECT
        idEstudiante = pe.idEstudiante,
        nombreCompleto = u.nombreCompleto,
        numeroIdentificacion = u.numeroIdentificacion,
        correo = u.correo,
        totalMatriculasActivas = pe.totalMatriculasActivas,
        porcentajeInasistencia = pe.porcentajeInasistencia,
        faltasSinJustaCausa = pe.faltasSinJustaCausa,
        codigoPermanencia = CASE pe.peor WHEN 3 THEN N'PERDIDA' WHEN 2 THEN N'RIESGO' ELSE N'REGULAR' END,
        semaforo = CASE pe.peor WHEN 3 THEN N'ROJO' WHEN 2 THEN N'AMBAR' ELSE N'VERDE' END,
        totalRegistros = COUNT(*) OVER(),
        -- CULM-001 B.2 (NB-2): unidades de la inasistencia por horas
        tomasDictadas = pe.tomasDictadas,
        horasDictadas = pe.horasDictadas,
        horasFalta = pe.horasFalta
    FROM persona pe
    INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = pe.idEstudiante
    INNER JOIN dbo.uv_usuario u ON u.id = ei.idUsuario
    WHERE (@semaforo IS NULL OR (CASE pe.peor WHEN 3 THEN N'ROJO' WHEN 2 THEN N'AMBAR' ELSE N'VERDE' END) = @semaforo)
      AND (@filtro IS NULL
           OR CHARINDEX(@filtro, u.nombreCompleto) > 0
           OR CHARINDEX(@filtro, CONVERT(NVARCHAR(20), u.numeroIdentificacion)) > 0
           OR CHARINDEX(@filtro, u.correo) > 0)
    ORDER BY pe.porcentajeInasistencia DESC, u.nombreCompleto ASC, pe.idEstudiante ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_asignaturas_asociables_paginado
-- =============================================================================
-- CULM-001 B2NM (DEC-019, R3): asignaturas activas de la institucion del plan sin vinculo activo en el. 1 fila por asignatura,
-- con planes = "Programa · Plan inp · S n" de sus vinculos activos. Plan inexistente -> PLA_002; plan ajeno -> SEC_002.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asignaturas_asociables_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idPlanEstudio     UNIQUEIDENTIFIER,
    @numeroPagina      INT,
    @tamanoPagina      INT,
    @busqueda          NVARCHAR(100) = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoRechazo NVARCHAR(10);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        SET @codigoRechazo = 'VAL_001';

    DECLARE @idPrograma UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER;
    IF @codigoRechazo IS NULL AND @estadoResultado = 1
    BEGIN
        SELECT @idPrograma = pe.programa, @idInstitucion = f.institucion
        FROM dbo.PlanEstudio pe
        INNER JOIN dbo.Programa p ON p.id = pe.programa
        INNER JOIN dbo.Facultad f ON f.id = p.facultad
        WHERE pe.id = @idPlanEstudio;
        IF @idPrograma IS NULL
            SET @codigoRechazo = 'PLA_002';
        ELSE IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE cp.idPrograma = @idPrograma)
            SET @codigoRechazo = 'SEC_002';
    END

    IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
    BEGIN
        IF @codigoRechazo IS NOT NULL
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = N'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    DECLARE @patron NVARCHAR(220) = IIF(NULLIF(TRIM(@busqueda), N'') IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(UPPER(TRIM(@busqueda)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));

    SELECT
        idAsignatura     = a.id,
        codigo           = a.codigo,
        nombre           = a.nombre,
        credito          = a.credito,
        nombreArea       = a.nombreArea,
        nombreComponente = a.nombreComponente,
        planes           = CAST((SELECT STRING_AGG(CONCAT(v.nombrePrograma, N' · Plan ', v.inpPlanEstudio, N' · S', v.numeroSemestre), N'; ')
                                 WITHIN GROUP (ORDER BY v.nombrePrograma, v.inpPlanEstudio)
                                 FROM dbo.uv_asignatura_plan_estudio v
                                 WHERE v.idAsignatura = a.id AND v.estaActivoVinculo = 1) AS NVARCHAR(1000)),
        totalRegistros   = COUNT(*) OVER()
    FROM dbo.uv_asignatura a
    WHERE a.estaActivaAsignatura = 1
      AND EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v WHERE v.idAsignatura = a.id AND v.estaActivoVinculo = 1 AND v.idInstitucion = @idInstitucion)
      AND NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v WHERE v.idAsignatura = a.id AND v.estaActivoVinculo = 1 AND v.idPlanEstudio = @idPlanEstudio)
      AND (@patron IS NULL OR UPPER(a.nombre) LIKE @patron ESCAPE N'\' OR UPPER(a.codigo) LIKE @patron ESCAPE N'\')
    ORDER BY a.nombre ASC, a.codigo ASC, a.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_asignaturas_coordinador_paginado
-- =============================================================================
-- CULM-001 B2NM (DEC-019): asignaturas de los programas del coordinador (reemplaza AsignaturaJpaRepository.HQL_POR_PROGRAMA).
-- 1 fila por (asignatura, plan de sus programas). @idPrograma ajeno -> COO_003 (403); sin @idPrograma incluye todos sus programas (S4).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asignaturas_coordinador_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT,
    @tamanoPagina      INT,
    @idPrograma        UNIQUEIDENTIFIER = NULL,
    @busqueda          NVARCHAR(100) = NULL,
    @estaActiva        BIT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoRechazo NVARCHAR(10);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        SET @codigoRechazo = 'VAL_001';

    IF @codigoRechazo IS NULL AND @estadoResultado = 1 AND @idPrograma IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE cp.idPrograma = @idPrograma)
        SET @codigoRechazo = 'COO_003';

    IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
    BEGIN
        IF @codigoRechazo IS NOT NULL
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = N'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    DECLARE @patron NVARCHAR(220) = IIF(NULLIF(TRIM(@busqueda), N'') IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(UPPER(TRIM(@busqueda)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));

    SELECT
        idAsignatura          = v.idAsignatura,
        codigo                = v.codigoAsignatura,
        nombre                = v.nombreAsignatura,
        credito               = v.credito,
        idArea                = v.idArea,
        nombreArea            = v.nombreArea,
        idComponente          = v.idComponente,
        nombreComponente      = v.nombreComponente,
        idPlanEstudio         = v.idPlanEstudio,
        inpPlanEstudio        = v.inpPlanEstudio,
        idPrograma            = v.idPrograma,
        nombrePrograma        = v.nombrePrograma,
        idSemestrePlanEstudio = v.idSemestrePlanEstudio,
        numeroSemestre        = v.numeroSemestre,
        codigoSemestre        = v.codigoSemestre,
        codigoCaracter        = v.codigoCaracter,
        nombreCaracter        = v.nombreCaracter,
        estaActivoVinculo     = v.estaActivoVinculo,
        estaActivaAsignatura  = v.estaActivaAsignatura,
        compartida            = CAST(IIF(v.totalProgramasActivos > 1, 1, 0) AS BIT),
        totalRegistros        = COUNT(*) OVER()
    FROM dbo.uv_asignatura_plan_estudio v
    WHERE v.estaActivoVinculo = 1
      AND v.idPrograma IN (SELECT cp.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE @idPrograma IS NULL OR cp.idPrograma = @idPrograma)
      AND (@estaActiva IS NULL OR v.estaActivaAsignatura = @estaActiva)
      AND (@patron IS NULL OR UPPER(v.nombreAsignatura) LIKE @patron ESCAPE N'\' OR UPPER(v.codigoAsignatura) LIKE @patron ESCAPE N'\')
    ORDER BY v.nombrePrograma ASC, v.numeroSemestre ASC, v.nombreAsignatura ASC, v.idAsignatura ASC, v.idPlanEstudio ASC
    OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_asignaturas_plan_paginado
-- =============================================================================
-- CULM-001 B2NM (DEC-019): malla de un plan (coordinador y decano). 1 fila por vinculo activo de la tabla puente.
-- Plan inexistente o fuera del ambito (coordinador: sus programas; decano: su facultad) -> PLA_002 (404).
-- compartida = 1 si la asignatura tiene vinculos activos en mas de un programa. Paginado con COUNT(*) OVER().
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asignaturas_plan_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idPlanEstudio     UNIQUEIDENTIFIER,
    @numeroPagina      INT,
    @tamanoPagina      INT,
    @numeroSemestre    INT = NULL,
    @codigoCaracter    NVARCHAR(3) = NULL,
    @busqueda          NVARCHAR(100) = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoRechazo NVARCHAR(10);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        SET @codigoRechazo = 'VAL_001';

    IF @codigoRechazo IS NULL AND @estadoResultado = 1
       AND NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio pe
                       WHERE pe.id = @idPlanEstudio
                         AND (pe.programa IN (SELECT idPrograma FROM dbo.ufn_programas_ambito_ejecutor(@idUsuarioEjecutor))))
        SET @codigoRechazo = 'PLA_002';

    IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
    BEGIN
        IF @codigoRechazo IS NOT NULL
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = N'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    DECLARE @patron NVARCHAR(220) = IIF(NULLIF(TRIM(@busqueda), N'') IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(UPPER(TRIM(@busqueda)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));

    SELECT
        idAsignatura          = v.idAsignatura,
        codigo                = v.codigoAsignatura,
        nombre                = v.nombreAsignatura,
        credito               = v.credito,
        idArea                = v.idArea,
        nombreArea            = v.nombreArea,
        idComponente          = v.idComponente,
        nombreComponente      = v.nombreComponente,
        idPlanEstudio         = v.idPlanEstudio,
        inpPlanEstudio        = v.inpPlanEstudio,
        idPrograma            = v.idPrograma,
        nombrePrograma        = v.nombrePrograma,
        idSemestrePlanEstudio = v.idSemestrePlanEstudio,
        numeroSemestre        = v.numeroSemestre,
        codigoSemestre        = v.codigoSemestre,
        codigoCaracter        = v.codigoCaracter,
        nombreCaracter        = v.nombreCaracter,
        estaActivoVinculo     = v.estaActivoVinculo,
        estaActivaAsignatura  = v.estaActivaAsignatura,
        compartida            = CAST(IIF(v.totalProgramasActivos > 1, 1, 0) AS BIT),
        totalRegistros        = COUNT(*) OVER()
    FROM dbo.uv_asignatura_plan_estudio v
    WHERE v.idPlanEstudio = @idPlanEstudio
      AND v.estaActivoVinculo = 1
      AND (@numeroSemestre IS NULL OR v.numeroSemestre = @numeroSemestre)
      AND (NULLIF(TRIM(@codigoCaracter), N'') IS NULL OR v.codigoCaracter = TRIM(@codigoCaracter))
      AND (@patron IS NULL OR UPPER(v.nombreAsignatura) LIKE @patron ESCAPE N'\' OR UPPER(v.codigoAsignatura) LIKE @patron ESCAPE N'\')
    ORDER BY v.numeroSemestre ASC, v.nombreAsignatura ASC, v.codigoAsignatura ASC, v.idAsignatura ASC
    OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_asistencias_grupo_ambito_paginado
-- ============================================================================
-- usp_consultar_asistencias_grupo_ambito_paginado (CULM-001 A.2-2; F-COO-003; CONTRACT §8.2.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo o fuera de
-- ambito). Asistencias del grupo de GET /api/v1/grupos/{grupoId}/asistencias (WORM #4: columnas de
-- AsistenciaConsultadaDTO). INNER JOIN desde uv_detalle_asistencia / uv_asistencia (vistas congeladas, solo lectura):
-- "ausencia = sin fila" (§E). Filtro opcional por sesion.
-- Ambito validado ANTES de leer filas (ejecutor activo): DOCENTE titular y ADMINISTRADOR de la institucion del grupo ven
-- todas; COORDINADOR activo del programa del grupo solo las de los estudiantes con EstudiantePrograma en sus programas
-- (DEC-031 §4). Grupo inexistente o fuera de ambito: THROW 51000 con DBCODE=SEC_002 (403).
-- @tamanoPagina NULL = todas las filas (A2-C3); con valor, 1..100. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asistencias_grupo_ambito_paginado]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL, 2147483647, IIF(@tamanoPagina < 1, 1, IIF(@tamanoPagina > 100, 100, @tamanoPagina)));
    DECLARE @offset INT = IIF(@tamanoPagina IS NULL, 0, (@pagina - 1) * @tamano);
    DECLARE @ejecutorActivo BIT = 0;
    DECLARE @verTodos BIT = 0;
    DECLARE @esCoordinador BIT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 3: ambito del grupo, antes de leer filas
    IF @estadoResultado = 1
    BEGIN
        SET @ejecutorActivo = IIF(EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuarioEjecutor AND u.estado = 1), 1, 0);

        SET @verTodos = IIF(@ejecutorActivo = 1 AND (
                EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente
                        WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor)
             OR EXISTS (SELECT 1 FROM dbo.Grupo g
                        INNER JOIN dbo.uv_grupo_programa gpx ON gpx.idGrupo = g.id   -- CULM-001 B2NM: vigencia S1
                        INNER JOIN dbo.Programa p ON p.id = gpx.idPrograma
                        INNER JOIN dbo.Facultad f ON f.id = p.facultad
                        INNER JOIN dbo.Administrador ad ON ad.institucion = f.institucion
                        WHERE g.id = @idGrupo AND ad.usuario = @idUsuarioEjecutor)), 1, 0);

        SET @esCoordinador = IIF(@ejecutorActivo = 1 AND EXISTS (
                -- CULM-001 B2NM (DEC-020): coordinador de algun programa del grupo, o decano de su facultad.
                SELECT 1 FROM dbo.Grupo g
                INNER JOIN dbo.uv_grupo_programa gpa ON gpa.idGrupo = g.id
                INNER JOIN dbo.Programa p ON p.id = gpa.idPrograma
                LEFT JOIN dbo.Coordinador c ON c.id = p.coordinador AND c.usuario = @idUsuarioEjecutor AND c.estado = 1
                LEFT JOIN dbo.Facultad fa ON fa.id = p.facultad
                LEFT JOIN dbo.Decano dc ON dc.id = fa.decano AND dc.usuario = @idUsuarioEjecutor
                WHERE g.id = @idGrupo AND (c.id IS NOT NULL OR dc.id IS NOT NULL)), 1, 0);

        IF @verTodos = 0 AND @esCoordinador = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: asistencias registradas del grupo (el coordinador, solo las de los estudiantes de sus programas)
    SELECT
        asistencia     = da.id,
        estudiante     = eg.idEstudiante,
        grupo          = eg.idGrupo,
        sesion         = a.idSesion,
        presente       = da.asistio,
        estado         = da.codigoRazonCausa,
        observacion    = CAST(N'' AS NVARCHAR(500)),
        totalRegistros = COUNT(*) OVER()
    FROM dbo.uv_detalle_asistencia da
    INNER JOIN dbo.uv_asistencia a ON a.id = da.idAsistencia
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = a.idEstudianteGrupo
    WHERE eg.idGrupo = @idGrupo
      AND (@idSesion IS NULL OR a.idSesion = @idSesion)
      AND (@verTodos = 1
           OR eg.id IN (SELECT v.idEstudianteGrupo FROM dbo.ufn_estudiantes_grupo_visibles(@idGrupo, @idUsuarioEjecutor) v))   -- CULM-001 B2NM R6
    ORDER BY a.idSesion ASC, eg.idEstudiante ASC, da.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_bitacora_estudiante_programa
-- ============================================================================
-- usp_consultar_bitacora_estudiante_programa (HU067). READ_QUERY_RESULTSET paginado. Solo lectura.
-- Sesiones vencidas de los grupos del programa en los que el estudiante esta (o estuvo) matriculado, la mas reciente primero.
-- asistio = NULL cuando la sesion vencida no tiene registro de ese estudiante.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_bitacora_estudiante_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idEstudiante       UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
,
    @idPrograma UNIQUEIDENTIFIER = NULL)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idPrograma = @idPrograma OUTPUT, @idProgramaSolicitado = @idPrograma;
    -- PASO 2: Validacion de negocio (usp_validar_estudiante_en_programa_interno)
    EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = @idEstudiante, @idPrograma = @idPrograma;
    DECLARE @tamanoMaximo INT = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO')), '') AS INT);
    -- PASO 3: Validacion de negocio (PAG_001)
    IF @numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo
    BEGIN
        SET @msgP1 = CAST(@numeroPagina AS NVARCHAR(500));
        DECLARE @msgP2 NVARCHAR(500) = CAST(@tamanoPagina AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PAG_001',
            @p_param1 = @msgP1,
            @p_param2 = @msgP2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
    DECLARE @offset INT = (@numeroPagina - 1) * @tamanoPagina;
    -- PASO 4: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_interno)
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 5: Consulta y retorno de resultados
    SELECT
        idSesion = s.id,
        numeroSesion = s.numero,
        nombreSesion = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        idAsignatura = g.idAsignatura,
        nombreAsignatura = g.nombreAsignatura,
        asistio = d.asistio,
        codigoRazonCausa = d.codigoRazonCausa,
        nombreRazonCausa = d.nombreRazonCausa,
        totalRegistros = COUNT(*) OVER()
    FROM dbo.uv_estudiante_grupo eg
    INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idGrupo = eg.idGrupo AND c.estaVencida = 1
    INNER JOIN dbo.uv_sesion_v2 s ON s.id = c.idSesion
    INNER JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
    -- CULM-001 B.2 (CONTRACT §2.9): estado consolidado de la sesion (uv_asistencia_sesion_horas): una fila aunque haya varias tomas
    OUTER APPLY (
        SELECT TOP 1 asistio = CAST(IIF(h.codigoRazonCausaConsolidado = N'AN', 1, 0) AS BIT),
               codigoRazonCausa = rc.codigo, nombreRazonCausa = rc.nombre, h.horasFalta
        FROM dbo.uv_asistencia_sesion_horas h
        LEFT JOIN dbo.uv_razon_causa rc ON rc.codigo = h.codigoRazonCausaConsolidado
        WHERE h.idEstudianteGrupo = eg.id AND h.idSesion = s.id AND h.codigoRazonCausaConsolidado IS NOT NULL
    ) d
    WHERE eg.idEstudiante = @idEstudiante
      AND EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp WHERE gp.idGrupo = c.idGrupo AND gp.idPrograma = @idPrograma)
      AND c.idPeriodoAcademico = @idPeriodo
    ORDER BY s.fechaHoraInicio DESC, s.id DESC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_comparativa_facultades
-- ============================================================================
-- usp_consultar_comparativa_facultades (HU139). READ_QUERY_RESULTSET sin paginar. Solo lectura.
-- Una fila por facultad de la institucion (activas e inactivas, D4). Mismas definiciones que usp_consultar_kpis_institucion.
-- Orden: ausentismo descendente (NULL al final), luego nombre.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_comparativa_facultades]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_institucion_administrador_interno)
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idInstitucion = @idInstitucion OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_institucion_interno)
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 3: Consulta y retorno de resultados
    WITH persona AS (
        SELECT  p.idFacultad, r.idEstudiante,
                peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
        FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idInstitucion = @idInstitucion AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY p.idFacultad, r.idEstudiante
    ),
    conteo AS (
        SELECT  idFacultad,
                total = COUNT(*),
                regulares = SUM(IIF(peor = 1, 1, 0)),
                riesgo = SUM(IIF(peor = 2, 1, 0)),
                perdida = SUM(IIF(peor = 3, 1, 0))
        FROM    persona
        GROUP BY idFacultad
    ),
    asistencia AS (
        SELECT  p.idFacultad,
                sesiones = SUM(r.sesionesEjecutadas),
                -- CULM-001 B.2 (diferido a D: debe pasar a horas): faltas en unidades de sesion para no mezclar unidades
                faltas = SUM(r.sesionesConFaltaSinJustaCausa)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN (SELECT DISTINCT p.idFacultad, idEstudianteGrupo = egp.id
                    FROM dbo.uv_estudiante_grupo_programa egp
                    INNER JOIN dbo.uv_programa p ON p.id = egp.idPrograma
                    WHERE p.idInstitucion = @idInstitucion) p ON p.idEstudianteGrupo = r.idEstudianteGrupo
        WHERE   r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY p.idFacultad
    ),
    programas AS (
        SELECT idFacultad, total = COUNT(*) FROM dbo.uv_programa WHERE idInstitucion = @idInstitucion GROUP BY idFacultad
    ),
    resultado AS (
        SELECT
            idFacultad = f.id,
            nombreFacultad = f.nombreFacultad,
            estaActivaFacultad = CAST(f.estaActivaFacultad AS BIT),
            totalProgramas = ISNULL(pr.total, 0),
            totalEstudiantes = ISNULL(c.total, 0),
            estudiantesRiesgo = ISNULL(c.riesgo, 0),
            estudiantesPerdida = ISNULL(c.perdida, 0),
            tasaRetencion = CAST(IIF(ISNULL(c.total, 0) = 0, NULL, 100.0 * (c.regulares + c.riesgo) / c.total) AS DECIMAL(5,2)),
            sesionesEjecutadas = ISNULL(a.sesiones, 0),
            faltasSinJustaCausa = ISNULL(a.faltas, 0),
            porcentajeAusentismo = CAST(IIF(ISNULL(a.sesiones, 0) = 0, NULL, 100.0 * a.faltas / a.sesiones) AS DECIMAL(5,2))
        FROM dbo.uv_facultad f
        LEFT JOIN programas pr ON pr.idFacultad = f.id
        LEFT JOIN conteo c ON c.idFacultad = f.id
        LEFT JOIN asistencia a ON a.idFacultad = f.id
        WHERE f.idInstitucion = @idInstitucion
    )
    -- PASO 4: Consulta y retorno de resultados
    SELECT idFacultad, nombreFacultad, estaActivaFacultad, totalProgramas, totalEstudiantes, estudiantesRiesgo, estudiantesPerdida,
           tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo
    FROM resultado
    ORDER BY IIF(porcentajeAusentismo IS NULL, 1, 0) ASC, porcentajeAusentismo DESC, nombreFacultad ASC, idFacultad ASC;
END;
GO

-- >>> stored-procedures/usp_consultar_comparativa_programas_facultad
-- ============================================================================
-- usp_consultar_comparativa_programas_facultad (HU103). READ_QUERY_RESULTSET sin paginar (D6). Solo lectura.
-- Una fila por programa de la facultad (activos e inactivos, D5). Mismas definiciones que usp_consultar_kpis_decano.
-- Orden: ausentismo descendente (NULL al final), luego nombre.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_comparativa_programas_facultad]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idFacultad UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_facultad_decano_interno)
    EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idFacultad = @idFacultad OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_facultad_interno)
    EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @idFacultad, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 3: Consulta y retorno de resultados
    WITH persona AS (
        SELECT  r.idPrograma, r.idEstudiante,
                peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
        FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY r.idPrograma, r.idEstudiante
    ),
    conteo AS (
        SELECT  idPrograma,
                total = COUNT(*),
                regulares = SUM(IIF(peor = 1, 1, 0)),
                riesgo = SUM(IIF(peor = 2, 1, 0)),
                perdida = SUM(IIF(peor = 3, 1, 0))
        FROM    persona
        GROUP BY idPrograma
    ),
    asistencia AS (
        SELECT  r.idPrograma,
                sesiones = SUM(r.sesionesEjecutadas),
                -- CULM-001 B.2 (diferido a D: debe pasar a horas): faltas en unidades de sesion para no mezclar unidades
                faltas = SUM(r.sesionesConFaltaSinJustaCausa)
        FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY r.idPrograma
    ),
    resultado AS (
        SELECT
            idPrograma = p.id,
            nombrePrograma = p.nombrePrograma,
            estaActivoPrograma = CAST(p.estaActivoPrograma AS BIT),
            totalEstudiantes = ISNULL(c.total, 0),
            estudiantesRiesgo = ISNULL(c.riesgo, 0),
            estudiantesPerdida = ISNULL(c.perdida, 0),
            tasaRetencion = CAST(IIF(ISNULL(c.total, 0) = 0, NULL, 100.0 * (c.regulares + c.riesgo) / c.total) AS DECIMAL(5,2)),
            sesionesEjecutadas = ISNULL(a.sesiones, 0),
            faltasSinJustaCausa = ISNULL(a.faltas, 0),
            porcentajeAusentismo = CAST(IIF(ISNULL(a.sesiones, 0) = 0, NULL, 100.0 * a.faltas / a.sesiones) AS DECIMAL(5,2))
        FROM dbo.uv_programa p
        LEFT JOIN conteo c ON c.idPrograma = p.id
        LEFT JOIN asistencia a ON a.idPrograma = p.id
        WHERE p.idFacultad = @idFacultad
    )
    -- PASO 4: Consulta y retorno de resultados
    SELECT idPrograma, nombrePrograma, estaActivoPrograma, totalEstudiantes, estudiantesRiesgo, estudiantesPerdida,
           tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo
    FROM resultado
    ORDER BY IIF(porcentajeAusentismo IS NULL, 1, 0) ASC, porcentajeAusentismo DESC, nombrePrograma ASC, idPrograma ASC;
END;
GO

-- >>> stored-procedures/usp_consultar_consolidado_asistencia_grupos_paginado
-- ============================================================================
-- usp_consultar_consolidado_asistencia_grupos_paginado (HU061 consolidado por cohorte, materia y docente)
--
-- Una fila por grupo con el consolidado de asistencia de sus estudiantes. Decision de John (2026-11-04): la cohorte es
-- el PERIODO ACADEMICO del grupo (el modelo no tiene cohorte de ingreso). Filtros opcionales: periodo, programa,
-- asignatura y docente.
-- Metricas: estudiantes activos (A), sesiones ejecutadas (vencidas con registro de asistencia), asistencias, faltas sin
-- justa causa y excusas de los estudiantes activos; % de asistencia y de inasistencia sobre (sesiones x activos);
-- estudiantes activos en RIESGO y estudiantes en PERDIDA (incluye cancelados por inasistencia).
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001).
-- Ambito: perfiles COORDINADOR, DECANO o ADMINISTRADOR; los grupos salen de uv_auth_grupo (fail-closed): el
-- coordinador ve su programa, el decano su facultad y el administrador su institucion.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_consolidado_asistencia_grupos_paginado]
(
    @idUsuarioEjecutor   UNIQUEIDENTIFIER,
    @idCorrelacion       UNIQUEIDENTIFIER,
    @numeroPagina        INT,
    @tamanoPagina        INT,
    @idPeriodoAcademico  UNIQUEIDENTIFIER = NULL,
    @idPrograma          UNIQUEIDENTIFIER = NULL,
    @idAsignatura        UNIQUEIDENTIFIER = NULL,
    @idDocente           UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    -- Grupos del ambito materializados una vez: evita que el optimizador combine uv_auth_grupo con el resumen de
    -- asistencia en un solo plan con una reserva de memoria desproporcionada (Msg 701 en instancias pequenas).
    DECLARE @grupos TABLE (
        id UNIQUEIDENTIFIER PRIMARY KEY, codigo INT, nombre NVARCHAR(100), idPeriodoAcademico UNIQUEIDENTIFIER,
        idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idDocente UNIQUEIDENTIFIER, idPrograma UNIQUEIDENTIFIER);
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: Correlacion, ejecutor, perfil y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'COORDINADOR,DECANO,ADMINISTRADOR',
            @numeroPagina = @numeroPagina,
            @tamanoPagina = @tamanoPagina,
            @idUsuarioValidado = @idUsuario OUTPUT,
            @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 2: Grupos del ambito del ejecutor con los filtros
        INSERT INTO @grupos (id, codigo, nombre, idPeriodoAcademico, idAsignatura, nombreAsignatura, idDocente, idPrograma)
            SELECT  g.id, g.codigo, g.nombre, g.idPeriodoAcademico, g.idAsignatura, g.nombreAsignatura, g.idDocente,
                    gp.idPrograma
            FROM    dbo.uv_auth_grupo g
            INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
            WHERE   (@idPeriodoAcademico IS NULL OR g.idPeriodoAcademico = @idPeriodoAcademico)
               AND  (@idPrograma IS NULL OR gp.idPrograma = @idPrograma)
               AND  (@idAsignatura IS NULL OR g.idAsignatura = @idAsignatura)
               AND  (@idDocente IS NULL OR g.idDocente = @idDocente);

        -- PASO 3: Consolidado de asistencia y retorno de resultados
        WITH consolidado AS (
            -- ISNULL/COALESCE permitidos solo sobre agregaciones (REC4 #3): un grupo sin estudiantes suma 0.
            SELECT  r.idGrupo, r.idPrograma,
                    activos = SUM(IIF(r.codigoEstadoEstudiante = N'A', 1, 0)),
                    sesionesEjecutadas = MAX(r.sesionesEjecutadas),
                    -- CULM-001 B.2 (diferido a D: debe pasar a horas): conteos en unidades de sesion (estado consolidado)
                    asistencias = SUM(IIF(r.codigoEstadoEstudiante = N'A', r.sesionesAsistidas, 0)),
                    faltas = SUM(IIF(r.codigoEstadoEstudiante = N'A', r.sesionesConFaltaSinJustaCausa, 0)),
                    excusas = SUM(IIF(r.codigoEstadoEstudiante = N'A', r.sesionesConExcusa, 0)),
                    riesgo = SUM(IIF(r.codigoEstadoEstudiante = N'A' AND r.codigoPermanencia = N'RIESGO', 1, 0)),
                    perdida = SUM(IIF(r.codigoPermanencia = N'PERDIDA', 1, 0))
            -- CULM-001 B2NM (R9): grano (grupo, programa del ambito); cuenta solo a los estudiantes con vinculo en ese programa.
            FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
            INNER JOIN @grupos gg ON gg.id = r.idGrupo AND gg.idPrograma = r.idPrograma
            GROUP BY r.idGrupo, r.idPrograma
        )
        SELECT
            idGrupo                 = g.id,
            codigoGrupo             = g.codigo,
            nombreGrupo             = g.nombre,
            idPeriodoAcademico      = g.idPeriodoAcademico,
            nombrePeriodoAcademico  = pa.nombre,
            idPrograma              = g.idPrograma,
            nombrePrograma          = p.nombrePrograma,
            idAsignatura            = g.idAsignatura,
            nombreAsignatura        = g.nombreAsignatura,
            idDocente               = g.idDocente,
            nombreDocente           = d.nombreCompleto,
            estudiantesActivos      = ISNULL(c.activos, 0),
            sesionesEjecutadas      = ISNULL(c.sesionesEjecutadas, 0),
            asistencias             = ISNULL(c.asistencias, 0),
            faltasSinJustaCausa     = ISNULL(c.faltas, 0),
            excusas                 = ISNULL(c.excusas, 0),
            porcentajeAsistencia    = CAST(IIF(ISNULL(c.sesionesEjecutadas, 0) * ISNULL(c.activos, 0) = 0, 0,
                                          100.0 * c.asistencias / (c.sesionesEjecutadas * c.activos)) AS DECIMAL(5,2)),
            porcentajeInasistencia  = CAST(IIF(ISNULL(c.sesionesEjecutadas, 0) * ISNULL(c.activos, 0) = 0, 0,
                                          100.0 * c.faltas / (c.sesionesEjecutadas * c.activos)) AS DECIMAL(5,2)),
            estudiantesRiesgo       = ISNULL(c.riesgo, 0),
            estudiantesPerdida      = ISNULL(c.perdida, 0),
            totalRegistros          = COUNT(*) OVER()
        FROM @grupos g
        LEFT JOIN consolidado c ON c.idGrupo = g.id AND c.idPrograma = g.idPrograma
        LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = g.idPeriodoAcademico
        LEFT JOIN dbo.uv_programa p ON p.id = g.idPrograma
        LEFT JOIN dbo.uv_docente_identidad d ON d.id = g.idDocente
        ORDER BY pa.fechaInicio DESC, g.nombreAsignatura ASC, g.codigo ASC, g.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO

-- >>> stored-procedures/usp_consultar_destinatarios_retiro_estudiante_grupo
-- ============================================================================
-- usp_consultar_destinatarios_retiro_estudiante_grupo  (HU051)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (los parametros invalidos se propagan con THROW).
-- Destinatarios del aviso de retiro: el ESTUDIANTE retirado, el DOCENTE titular del grupo y el COORDINADOR del
-- programa (Grupo -> Asignatura -> SemestrePlanEstudio -> PlanEstudio -> Programa.coordinador). Solo el docente
-- titular obtiene filas (otro ejecutor => 0 filas). No exige matricula activa: se consulta despues del retiro.
-- El correo es dato de uso interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_retiro_estudiante_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idEstudiante            UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    ;WITH contexto AS (
        SELECT g.id AS idGrupo, g.codigo AS codigoGrupo, g.nombre AS nombreGrupo, asg.nombre AS nombreAsignatura,
               d.usuario AS usuarioDocente, c.usuario AS usuarioCoordinador, e.usuario AS usuarioEstudiante
        FROM dbo.Grupo g
        INNER JOIN dbo.Docente d               ON d.id = g.docente
        INNER JOIN dbo.Asignatura asg          ON asg.id = g.asignatura
        INNER JOIN dbo.uv_grupo_programa gpx ON gpx.idGrupo = g.id   -- CULM-001 B2NM: vigencia S1
        INNER JOIN dbo.Programa pr             ON pr.id = gpx.idPrograma
        INNER JOIN dbo.Coordinador c           ON c.id = pr.coordinador
        INNER JOIN dbo.EstudianteGrupo eg      ON eg.grupo = g.id AND eg.estudiante = @idEstudiante
        INNER JOIN dbo.Estudiante e            ON e.id = eg.estudiante
        WHERE g.id = @idGrupo AND d.usuario = @idUsuarioDefecto
          -- CULM-001 B2NM: coordinadores de los programas del estudiante que comparten el grupo
          AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma epx WHERE epx.estudiante = eg.estudiante AND epx.programa = pr.id)
    ),
    destinatarios AS (
        SELECT DISTINCT orden = 1, rolDestinatario = 'ESTUDIANTE', idUsuario = usuarioEstudiante, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
        UNION ALL
        SELECT DISTINCT 2, 'DOCENTE', usuarioDocente, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
        UNION ALL
        SELECT DISTINCT 3, 'COORDINADOR', usuarioCoordinador, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
    )
    SELECT
        rolDestinatario  = CAST(dst.rolDestinatario AS VARCHAR(20)),
        idUsuario        = dst.idUsuario,
        nombreCompleto   = CAST(CONCAT_WS(N' ',
                               NULLIF(TRIM(u.primerNombre), N''),
                               NULLIF(TRIM(u.segundoNombre), N''),
                               NULLIF(TRIM(u.primerApellido), N''),
                               NULLIF(TRIM(u.segundoApellido), N'')) AS NVARCHAR(400)),
        correo           = u.correo,
        idGrupo          = dst.idGrupo,
        codigoGrupo      = dst.codigoGrupo,
        nombreGrupo      = dst.nombreGrupo,
        nombreAsignatura = dst.nombreAsignatura
    FROM destinatarios dst
    INNER JOIN dbo.Usuario u ON u.id = dst.idUsuario
    ORDER BY dst.orden;
END;
GO

-- >>> stored-procedures/usp_consultar_directorio_estudiantes_paginado
-- ============================================================================
-- usp_consultar_directorio_estudiantes_paginado (CULM-001 A.2-1; F-COO-001, F-COO-002, F-DOC-013; CONTRACT §8.2.1)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo).
-- Directorio de estudiantes de GET /api/v1/estudiantes y /{id} con el AMBITO DENTRO DEL SP (union si el ejecutor
-- tiene varios roles; el ejecutor debe ser un usuario activo):
--   * ADMINISTRADOR: solo su institucion (DEC-031 §3): estudiantes con EstudiantePrograma en un programa de su
--     institucion o con EstudianteGrupo en un grupo de su institucion. Un estudiante sin ningun vinculo no tiene
--     institucion resoluble y no aparece (fail-closed).
--   * COORDINADOR activo: estudiantes con EstudiantePrograma en sus programas.
--   * DOCENTE: estudiantes con alguna matricula (en cualquier estado: padron historico) en sus grupos.
--   * Cualquier otro rol: ambito vacio.
-- Modo listado (@idEstudiante NULL): 12 columnas, orden primerApellido, primerNombre, numeroIdentificacion, id;
-- paginacion protegida (pagina >= 1, tamano 1..100). Los filtros solo restringen dentro del ambito: igualdad para tipo
-- y numero de documento, LIKE con escape de %, _ y \ sobre UPPER(nombreCompleto) y LOWER(correo), y EXISTS sobre
-- uv_estudiante para los academicos.
-- Modo detalle (@idEstudiante no nulo): las 11 columnas del estudiante mas 12 de contexto academico (institucion,
-- facultad, programa, plan, asignatura y grupo, con id y nombre) LIMITADAS AL AMBITO del ejecutor: una fila por
-- contexto visible o una sola con contexto NULL. Fuera de ambito: 0 filas (el backend responde 404). Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_directorio_estudiantes_paginado]
(
    @idUsuarioEjecutor    UNIQUEIDENTIFIER,
    @idCorrelacion        UNIQUEIDENTIFIER,
    @idEstudiante         UNIQUEIDENTIFIER = NULL,
    @idTipoIdentificacion UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion INT              = NULL,
    @nombre               NVARCHAR(100)    = NULL,
    @correo               NVARCHAR(100)    = NULL,
    @idInstitucion        UNIQUEIDENTIFIER = NULL,
    @idFacultad           UNIQUEIDENTIFIER = NULL,
    @idPrograma           UNIQUEIDENTIFIER = NULL,
    @idGrupo              UNIQUEIDENTIFIER = NULL,
    @activo               BIT              = NULL,
    @numeroPagina         INT              = 1,
    @tamanoPagina         INT              = 20
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @textoNombre NVARCHAR(100) = NULLIF(TRIM(@nombre), N'');
    DECLARE @textoCorreo NVARCHAR(100) = NULLIF(TRIM(@correo), N'');
    DECLARE @patronNombre NVARCHAR(320) = IIF(@textoNombre IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(UPPER(@textoNombre), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));
    DECLARE @patronCorreo NVARCHAR(320) = IIF(@textoCorreo IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(LOWER(@textoCorreo), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));
    DECLARE @filtroAcademico BIT = IIF(@idInstitucion IS NULL AND @idFacultad IS NULL AND @idPrograma IS NULL AND @idGrupo IS NULL, 0, 1);
    DECLARE @ejecutorActivo BIT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 2.1 (CULM-001 B2NM, S4/A.2): un programa fuera de la coordinacion del ejecutor -> COO_003 (403); no aplica a administrador ni docente.
    IF @estadoResultado = 1 AND @idPrograma IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor))
       AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE cp.idPrograma = @idPrograma)
       AND NOT EXISTS (SELECT 1 FROM dbo.Administrador ad WHERE ad.usuario = @idUsuarioEjecutor)
       AND NOT EXISTS (SELECT 1 FROM dbo.Docente dd WHERE dd.usuario = @idUsuarioEjecutor)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'COO_003',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SET @ejecutorActivo = IIF(EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuarioEjecutor AND u.estado = 1), 1, 0);

    -- PASO 3: modo listado
    IF @idEstudiante IS NULL
    BEGIN
        ;WITH ambito AS (
            -- ADMINISTRADOR: matriculas en grupos de su institucion
            SELECT eg.estudiante AS idEstudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.PlanEstudio pe ON pe.programa = p.id
            INNER JOIN dbo.SemestrePlanEstudio spe ON spe.planEstudio = pe.id
            INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.semestrePlanEstudio = spe.id AND ape.estaActivo = 1 INNER JOIN dbo.Asignatura a ON a.id = ape.asignatura
            INNER JOIN dbo.Grupo g ON g.asignatura = a.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1
            UNION
            -- ADMINISTRADOR: inscripciones en programas de su institucion
            SELECT ep.estudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1
            UNION
            -- COORDINADOR activo: inscripciones en sus programas
            SELECT ep.estudiante
            FROM dbo.Coordinador c
            INNER JOIN dbo.Programa p ON p.coordinador = c.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE c.usuario = @idUsuarioEjecutor AND c.estado = 1 AND @ejecutorActivo = 1
            UNION
            -- DOCENTE: matriculas (cualquier estado) en sus grupos
            SELECT eg.estudiante
            FROM dbo.Docente d
            INNER JOIN dbo.Grupo g ON g.docente = d.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE d.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1
        )
        SELECT
            id                   = e.id,
            idUsuario            = u.id,
            tipoIdentificacionId = u.idTipoIdentificacion,
            numeroIdentificacion = u.numeroIdentificacion,
            primerApellido       = u.primerApellido,
            segundoApellido      = u.segundoApellido,
            primerNombre         = u.primerNombre,
            segundoNombre        = u.segundoNombre,
            nombreCompleto       = CAST(u.nombreCompleto AS NVARCHAR(400)),
            correo               = u.correo,
            estaActivoUsuario    = u.estaActivoUsuario,
            totalRegistros       = COUNT(*) OVER()
        FROM dbo.uv_estudiante_identidad e
        INNER JOIN dbo.uv_usuario u ON u.id = e.idUsuario
        WHERE e.id IN (SELECT amb.idEstudiante FROM ambito amb)
          AND (@idTipoIdentificacion IS NULL OR u.idTipoIdentificacion = @idTipoIdentificacion)
          AND (@numeroIdentificacion IS NULL OR u.numeroIdentificacion = @numeroIdentificacion)
          AND (@patronNombre IS NULL OR UPPER(u.nombreCompleto) LIKE @patronNombre ESCAPE N'\')
          AND (@patronCorreo IS NULL OR LOWER(u.correo) LIKE @patronCorreo ESCAPE N'\')
          AND (@activo IS NULL OR u.estaActivoUsuario = @activo)
          AND (@filtroAcademico = 0 OR EXISTS (
                SELECT 1 FROM dbo.uv_estudiante x
                WHERE x.id = e.id
                  AND (@idInstitucion IS NULL OR x.idInstitucion = @idInstitucion)
                  AND (@idFacultad IS NULL OR x.idFacultad = @idFacultad)
                  AND (@idPrograma IS NULL OR (x.idPrograma = @idPrograma AND x.tieneVinculoPrograma = 1))
                  AND (@idGrupo IS NULL OR x.idGrupo = @idGrupo)))
        ORDER BY u.primerApellido ASC, u.primerNombre ASC, u.numeroIdentificacion ASC, e.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;
    END
    ELSE
    -- PASO 4: modo detalle (contextos limitados al ambito del ejecutor)
    BEGIN
        ;WITH ambito AS (
            SELECT eg.estudiante AS idEstudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.PlanEstudio pe ON pe.programa = p.id
            INNER JOIN dbo.SemestrePlanEstudio spe ON spe.planEstudio = pe.id
            INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.semestrePlanEstudio = spe.id AND ape.estaActivo = 1 INNER JOIN dbo.Asignatura a ON a.id = ape.asignatura
            INNER JOIN dbo.Grupo g ON g.asignatura = a.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1 AND eg.estudiante = @idEstudiante
            UNION
            SELECT ep.estudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1 AND ep.estudiante = @idEstudiante
            UNION
            SELECT ep.estudiante
            FROM dbo.Coordinador c
            INNER JOIN dbo.Programa p ON p.coordinador = c.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE c.usuario = @idUsuarioEjecutor AND c.estado = 1 AND @ejecutorActivo = 1 AND ep.estudiante = @idEstudiante
            UNION
            SELECT eg.estudiante
            FROM dbo.Docente d
            INNER JOIN dbo.Grupo g ON g.docente = d.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE d.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1 AND eg.estudiante = @idEstudiante
        ),
        contexto AS (
            SELECT DISTINCT
                x.idInstitucion, x.nombreInstitucion, x.idFacultad, x.nombreFacultad, x.idPrograma, x.nombrePrograma,
                x.idPlanEstudio, inpPlanEstudio = CAST(x.inpPlanEstudio AS NVARCHAR(20)), x.idAsignatura, x.nombreAsignatura,
                x.idGrupo, x.nombreGrupo
            FROM dbo.uv_estudiante x
            WHERE x.id = @idEstudiante
              AND @ejecutorActivo = 1
              AND (EXISTS (SELECT 1 FROM dbo.Administrador ad WHERE ad.usuario = @idUsuarioEjecutor AND ad.institucion = x.idInstitucion)
                   OR EXISTS (SELECT 1 FROM dbo.Coordinador c INNER JOIN dbo.Programa p ON p.coordinador = c.id
                              WHERE c.usuario = @idUsuarioEjecutor AND c.estado = 1 AND p.id = x.idPrograma AND x.tieneVinculoPrograma = 1)
                   OR EXISTS (SELECT 1 FROM dbo.Docente d INNER JOIN dbo.Grupo g ON g.docente = d.id
                              WHERE d.usuario = @idUsuarioEjecutor AND g.id = x.idGrupo))
        )
        SELECT
            id                   = e.id,
            idUsuario            = u.id,
            tipoIdentificacionId = u.idTipoIdentificacion,
            numeroIdentificacion = u.numeroIdentificacion,
            primerApellido       = u.primerApellido,
            segundoApellido      = u.segundoApellido,
            primerNombre         = u.primerNombre,
            segundoNombre        = u.segundoNombre,
            nombreCompleto       = CAST(u.nombreCompleto AS NVARCHAR(400)),
            correo               = u.correo,
            estaActivoUsuario    = u.estaActivoUsuario,
            idInstitucion        = c.idInstitucion,
            nombreInstitucion    = c.nombreInstitucion,
            idFacultad           = c.idFacultad,
            nombreFacultad       = c.nombreFacultad,
            idPrograma           = c.idPrograma,
            nombrePrograma       = c.nombrePrograma,
            idPlanEstudio        = c.idPlanEstudio,
            inpPlanEstudio       = c.inpPlanEstudio,
            idAsignatura         = c.idAsignatura,
            nombreAsignatura     = c.nombreAsignatura,
            idGrupo              = c.idGrupo,
            nombreGrupo          = c.nombreGrupo
        FROM dbo.uv_estudiante_identidad e
        INNER JOIN dbo.uv_usuario u ON u.id = e.idUsuario
        LEFT JOIN contexto c ON 1 = 1
        WHERE e.id = @idEstudiante
          AND e.id IN (SELECT amb.idEstudiante FROM ambito amb)
        ORDER BY c.nombreInstitucion, c.nombreFacultad, c.nombrePrograma, c.nombreAsignatura, c.nombreGrupo, c.idGrupo;
    END
END;
GO

-- >>> stored-procedures/usp_consultar_estudiantes_grupo_ambito_paginado
-- ============================================================================
-- usp_consultar_estudiantes_grupo_ambito_paginado (CULM-001 A.2-2; F-COO-003; CONTRACT §8.2.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo o fuera de
-- ambito). Estudiantes del grupo de GET /api/v1/grupos/{grupoId}/estudiantes (WORM #3: columnas de EstudianteGrupoDTO),
-- en TODOS los estados (DR-007), orden nombreCompleto, id.
-- Ambito validado ANTES de leer filas (ejecutor activo):
--   * DOCENTE titular del grupo (Grupo.docente) y ADMINISTRADOR de la institucion del grupo: todos los estudiantes.
--   * COORDINADOR activo del programa del grupo (asignatura -> semestre -> plan -> programa): solo los estudiantes con
--     EstudiantePrograma en alguno de sus programas (DEC-031 §4; B2 completa la relacion N:M).
--   * Grupo inexistente o fuera de ambito: THROW 51000 con el mensaje tecnico de SEC_002 (DBCODE=SEC_002 -> 403).
-- @tamanoPagina NULL = todas las filas (A2-C3: el contrato WORM fija listas completas); con valor, 1..100. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_estudiantes_grupo_ambito_paginado]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL, 2147483647, IIF(@tamanoPagina < 1, 1, IIF(@tamanoPagina > 100, 100, @tamanoPagina)));
    DECLARE @offset INT = IIF(@tamanoPagina IS NULL, 0, (@pagina - 1) * @tamano);
    DECLARE @ejecutorActivo BIT = 0;
    DECLARE @verTodos BIT = 0;
    DECLARE @esCoordinador BIT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 3: ambito del grupo, antes de leer filas
    IF @estadoResultado = 1
    BEGIN
        SET @ejecutorActivo = IIF(EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuarioEjecutor AND u.estado = 1), 1, 0);

        SET @verTodos = IIF(@ejecutorActivo = 1 AND (
                EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente
                        WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor)
             OR EXISTS (SELECT 1 FROM dbo.Grupo g
                        INNER JOIN dbo.uv_grupo_programa gpx ON gpx.idGrupo = g.id   -- CULM-001 B2NM: vigencia S1
                        INNER JOIN dbo.Programa p ON p.id = gpx.idPrograma
                        INNER JOIN dbo.Facultad f ON f.id = p.facultad
                        INNER JOIN dbo.Administrador ad ON ad.institucion = f.institucion
                        WHERE g.id = @idGrupo AND ad.usuario = @idUsuarioEjecutor)), 1, 0);

        SET @esCoordinador = IIF(@ejecutorActivo = 1 AND EXISTS (
                -- CULM-001 B2NM (DEC-020): coordinador de algun programa del grupo, o decano de su facultad.
                SELECT 1 FROM dbo.Grupo g
                INNER JOIN dbo.uv_grupo_programa gpa ON gpa.idGrupo = g.id
                INNER JOIN dbo.Programa p ON p.id = gpa.idPrograma
                LEFT JOIN dbo.Coordinador c ON c.id = p.coordinador AND c.usuario = @idUsuarioEjecutor AND c.estado = 1
                LEFT JOIN dbo.Facultad fa ON fa.id = p.facultad
                LEFT JOIN dbo.Decano dc ON dc.id = fa.decano AND dc.usuario = @idUsuarioEjecutor
                WHERE g.id = @idGrupo AND (c.id IS NOT NULL OR dc.id IS NOT NULL)), 1, 0);

        IF @verTodos = 0 AND @esCoordinador = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: estudiantes del grupo en todos los estados (el coordinador, solo los de sus programas)
    SELECT
        id             = eg.id,
        idEstudiante   = eg.idEstudiante,
        documento      = CAST(ei.numeroIdentificacion AS NVARCHAR(20)),
        nombreCompleto = CAST(ei.nombreCompleto AS NVARCHAR(400)),
        correo         = u.correo,
        codigoEstado   = eg.codigoEstadoEstudiante,
        nombreEstado   = eg.nombreEstadoEstudiante,
        totalRegistros = COUNT(*) OVER()
    FROM dbo.uv_estudiante_grupo eg
    INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante
    INNER JOIN dbo.uv_usuario u ON u.id = ei.idUsuario
    WHERE eg.idGrupo = @idGrupo
      AND (@verTodos = 1
           OR eg.id IN (SELECT v.idEstudianteGrupo FROM dbo.ufn_estudiantes_grupo_visibles(@idGrupo, @idUsuarioEjecutor) v))   -- CULM-001 B2NM R6
    ORDER BY ei.nombreCompleto ASC, eg.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_ficha_estudiante_programa
-- ============================================================================
-- usp_consultar_ficha_estudiante_programa (HU069). READ_QUERY_RESULTSET (1 fila). Solo campos que existen en la DB (sin telefono, D5).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_ficha_estudiante_programa]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idEstudiante      UNIQUEIDENTIFIER
,
    @idPrograma UNIQUEIDENTIFIER = NULL)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idPrograma = @idPrograma OUTPUT, @idProgramaSolicitado = @idPrograma;
    -- PASO 2: Validacion de negocio (usp_validar_estudiante_en_programa_interno)
    EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = @idEstudiante, @idPrograma = @idPrograma;

    -- PASO 3: Consulta y retorno de resultados
    SELECT
        idEstudiante = ei.id,
        tipoIdentificacion = u.TipoIdentificacion,
        numeroIdentificacion = u.numeroIdentificacion,
        primerNombre = u.primerNombre,
        segundoNombre = u.segundoNombre,
        primerApellido = u.primerApellido,
        segundoApellido = u.segundoApellido,
        nombreCompleto = u.nombreCompleto,
        correo = u.correo,
        estaActivoUsuario = u.estaActivoUsuario,
        idPrograma = p.id,
        nombrePrograma = p.nombrePrograma
    FROM dbo.uv_estudiante_identidad ei
    INNER JOIN dbo.uv_usuario u ON u.id = ei.idUsuario
    INNER JOIN dbo.uv_programa p ON p.id = @idPrograma
    WHERE ei.id = @idEstudiante;
END;
GO

-- >>> stored-procedures/usp_consultar_grupos_facultad_paginado
-- =============================================================================
-- CULM-001 B2NM (DEC-019, F-DEC-002): grupos de la facultad del decano (reemplaza GrupoJpaRepository.HQL_GRUPOS_POR_FACULTAD).
-- Ambito por EXISTS sobre uv_grupo_programa: 1 fila por grupo con programas = nombres de los programas del grupo en su facultad.
-- @idPrograma fuera de su facultad -> KPI_003 (403). Solo DECANO con facultad; si no, KPI_003.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_grupos_facultad_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @idPrograma         UNIQUEIDENTIFIER = NULL,
    @busqueda           NVARCHAR(100) = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoRechazo NVARCHAR(10);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        SET @codigoRechazo = 'VAL_001';

    DECLARE @idFacultad UNIQUEIDENTIFIER;
    IF @codigoRechazo IS NULL AND @estadoResultado = 1
    BEGIN
        SELECT TOP 1 @idFacultad = f.id FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano WHERE d.usuario = @idUsuarioEjecutor ORDER BY f.id;
        IF @idFacultad IS NULL
            SET @codigoRechazo = 'KPI_003';
        ELSE IF @idPrograma IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Programa p WHERE p.id = @idPrograma AND p.facultad = @idFacultad)
            SET @codigoRechazo = 'KPI_003';
    END

    IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
    BEGIN
        IF @codigoRechazo IS NOT NULL
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = N'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    DECLARE @patron NVARCHAR(220) = IIF(NULLIF(TRIM(@busqueda), N'') IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(UPPER(TRIM(@busqueda)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));

    SELECT
        idGrupo                  = g.id,
        codigo                   = g.codigo,
        nombre                   = g.nombre,
        idPeriodoAcademico       = g.idPeriodoAcademico,
        idAsignatura             = g.idAsignatura,
        nombreAsignatura         = g.nombreAsignatura,
        idDocente                = g.idDocente,
        capacidadMaximaPermitida = g.capacidadMaximaPermitida,
        estudiantesActivos       = g.estudiantesActivos,
        cuposDisponibles         = g.cuposDisponibles,
        grupoEstaHablitado       = g.grupoEstaHablitado,
        programas                = CAST((SELECT STRING_AGG(p.nombrePrograma, N', ') WITHIN GROUP (ORDER BY p.nombrePrograma)
                                         FROM dbo.uv_grupo_programa gp
                                         INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
                                         WHERE gp.idGrupo = g.id AND p.idFacultad = @idFacultad) AS NVARCHAR(1000)),
        totalRegistros           = COUNT(*) OVER()
    FROM dbo.uv_grupo g
    WHERE EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
                  WHERE gp.idGrupo = g.id AND p.idFacultad = @idFacultad AND (@idPrograma IS NULL OR p.id = @idPrograma))
      AND (@idPeriodoAcademico IS NULL OR g.idPeriodoAcademico = @idPeriodoAcademico)
      AND (@patron IS NULL OR UPPER(g.nombre) LIKE @patron ESCAPE N'\' OR UPPER(g.nombreAsignatura) LIKE @patron ESCAPE N'\' OR UPPER(CAST(g.codigo AS NVARCHAR(20))) LIKE @patron ESCAPE N'\')
    ORDER BY g.nombreAsignatura ASC, g.codigo ASC, g.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_historial_estudiante
-- ============================================================================
-- usp_consultar_historial_estudiante (HU157 ficha unificada del estudiante con historial completo)
--
-- Una fila por matricula (programa, periodo, grupo) del estudiante con sus datos personales repetidos en cada fila
-- y el resumen de asistencia del grupo (las mismas vistas que la ficha y el resumen de HU069:
-- uv_usuario y uv_resumen_asistencia_estudiante_grupo). Un estudiante sin grupos devuelve una fila con los datos
-- del programa y las columnas del grupo en NULL. 0 filas si el estudiante no esta en el ambito del ejecutor.
--
-- Resultset: READ_QUERY_RESULTSET (filas de detalle), NO el resultset canonico de 4 columnas de los comandos.
-- Las fallas se propagan con THROW (VAL_001 / SEC_001).
-- Ambito: solo perfiles ADMINISTRADOR o DECANO (SEC_001); las filas salen de uv_auth_estudiante (fail-closed):
-- el administrador ve las matriculas de su institucion y el decano solo las de su facultad.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_historial_estudiante]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idEstudiante       UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGuidVacio             UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: idCorrelacion presente
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor y estudiante obligatorios (VAL_001)
        IF @estadoResultado = 1
           AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @idGuidVacio OR @idEstudianteDefecto IS NULL OR @idEstudianteDefecto = @idGuidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor/Estudiante',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil ADMINISTRADOR o DECANO (SEC_001)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR,DECANO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 4: Fijar el contexto del ejecutor para las vistas uv_auth_*
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor
            @p_idUsuario = @idUsuarioDefecto;

        -- PASO 5: Consulta y retorno de resultados
        SELECT
            idEstudiante              = e.id,
            idUsuario                 = e.idUsuario,
            tipoIdentificacion        = u.TipoIdentificacion,
            numeroIdentificacion      = e.numeroIdentificacion,
            nombreCompleto            = e.nombreCompleto,
            correo                    = u.correo,
            estaActivoUsuario         = e.estaActivoUsuario,
            idFacultad                = e.idFacultad,
            nombreFacultad            = e.nombreFacultad,
            idPrograma                = e.idPrograma,
            nombrePrograma            = e.nombrePrograma,
            inpPlanEstudio            = e.inpPlanEstudio,
            idPeriodoAcademico        = pa.id,
            codigoPeriodoAcademico    = pa.codigo,
            nombrePeriodoAcademico    = pa.nombre,
            idGrupo                   = e.idGrupo,
            codigoGrupo               = eg.codigoGrupo,
            idAsignatura              = e.idAsignatura,
            nombreAsignatura          = e.nombreAsignatura,
            codigoEstadoEstudiante    = eg.codigoEstadoEstudiante,
            nombreEstadoEstudiante    = eg.nombreEstadoEstudiante,
            sesionesEjecutadas        = r.sesionesEjecutadas,
            asistencias               = r.asistencias,
            faltasSinJustaCausa       = r.faltasSinJustaCausa,
            excusas                   = r.excusas,
            porcentajeInasistencia    = r.porcentajeInasistencia,
            codigoPermanencia         = r.codigoPermanencia,
            -- CULM-001 B.2 (NB-2): asistencias/faltas/excusas cuentan tomas; sesionesEjecutadas cuenta sesiones
            tomasDictadas             = r.tomasDictadas,
            horasDictadas             = r.horasDictadas,
            horasFalta                = r.horasFalta
        FROM dbo.uv_auth_estudiante e
        LEFT JOIN dbo.uv_usuario u ON u.id = e.idUsuario
        LEFT JOIN dbo.uv_estudiante_grupo eg ON eg.idEstudiante = e.id AND eg.idGrupo = e.idGrupo
        LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo r ON r.idEstudianteGrupo = eg.id
        LEFT JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = e.idGrupo AND gp.idPrograma = e.idPrograma
        LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = gp.idPeriodoAcademico
        WHERE e.id = @idEstudiante
        ORDER BY pa.fechaInicio DESC, e.nombrePrograma ASC, e.nombreAsignatura ASC, e.idGrupo ASC;

        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
        THROW;
    END CATCH;
END;
GO

-- >>> stored-procedures/usp_consultar_historial_grupos_docente_programa
-- ============================================================================
-- usp_consultar_historial_grupos_docente_programa (HU094)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo).
-- Ficha del docente para el COORDINADOR: historial de los grupos que el docente dicto o dicta en el programa del
-- coordinador, en todos los periodos (filtro opcional por periodo), del mas reciente al mas antiguo.
--   - el programa se resuelve del ejecutor (usp_resolver_programa_coordinador_interno; KPI_001 si no coordina);
--   - el docente debe tener una vinculacion (activa o inactiva) con ese programa; si no, GEN_001 (indistinguible de
--     un docente inexistente, para no revelar docentes de otros programas);
--   - estadoPeriodo: VIGENTE / FINALIZADO / PROXIMO segun la fecha local (TIEMPO.ZONA_HORARIA_SQLSERVER);
--   - las columnas resumen* agregan TODO el historial del docente en el programa (no dependen del filtro de periodo
--     ni de la pagina) y se repiten en cada fila.
-- Paginacion acotada como R2 (pagina >= 1, tamano 1..100). Solo lectura: sin XACT_ABORT.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_historial_grupos_docente_programa]
(
    @idUsuarioEjecutor   UNIQUEIDENTIFIER,
    @idCorrelacion       UNIQUEIDENTIFIER,
    @idDocente           UNIQUEIDENTIFIER,
    @idPeriodoAcademico  UNIQUEIDENTIFIER = NULL,
    @numeroPagina        INT              = 1,
    @tamanoPagina        INT              = 10
,
    @idPrograma UNIQUEIDENTIFIER = NULL)
AS

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @zonaHoraria NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100));
    DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zonaHoraria AS DATE);

BEGIN
    SET NOCOUNT ON;

-- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @validarUmbrales = 0,
        @idPrograma = @idPrograma OUTPUT, @idProgramaSolicitado = @idPrograma;

    -- PASO 2: Validacion de negocio (VAL_001)
    IF @idDocente IS NULL
    BEGIN
        SET @msgP1 = CAST(N'Docente' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 3: Validacion de negocio (GEN_001)
    IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma dp WHERE dp.docente = @idDocente AND dp.programa = @idPrograma)
    BEGIN
        SET @msgP1 = CAST(N'Docente' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: Consulta y retorno de resultados
    ;WITH historial AS (
        SELECT
            g.id, g.codigo, g.nombre, g.idAsignatura, g.nombreAsignatura,
            g.idPeriodoAcademico, pa.codigo AS codigoPeriodo, pa.nombre AS nombrePeriodo,
            pa.fechaInicio, pa.fechaFin,
            estadoPeriodo = CASE
                                WHEN @hoyLocal < pa.fechaInicio THEN 'PROXIMO'
                                WHEN @hoyLocal > pa.fechaFin THEN 'FINALIZADO'
                                ELSE 'VIGENTE'
                            END,
            g.capacidadMaximaPermitida, g.estudiantesActivos, g.estudiantesFinalizados,
            g.estudiantesCanceladosVoluntad, g.estudiantesCanceladosInasistencia
        FROM dbo.uv_grupo g
        INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.idPeriodoAcademico
        WHERE g.idDocente = @idDocente
          AND EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gpx WHERE gpx.idGrupo = g.id AND gpx.idPrograma = @idPrograma)
    ),
    resumen AS (
        SELECT
            totalGrupos      = COUNT(*),
            totalPeriodos    = COUNT(DISTINCT h.idPeriodoAcademico),
            gruposVigentes   = SUM(IIF(h.estadoPeriodo = 'VIGENTE', 1, 0)),
            activosVigentes  = SUM(IIF(h.estadoPeriodo = 'VIGENTE', h.estudiantesActivos, 0))
        FROM historial h
    )
    -- PASO 5: Consulta y retorno de resultados
    SELECT
        idGrupo                           = h.id,
        codigoGrupo                       = h.codigo,
        nombreGrupo                       = h.nombre,
        idAsignatura                      = h.idAsignatura,
        nombreAsignatura                  = h.nombreAsignatura,
        idPeriodoAcademico                = h.idPeriodoAcademico,
        codigoPeriodoAcademico            = h.codigoPeriodo,
        nombrePeriodoAcademico            = h.nombrePeriodo,
        fechaInicioPeriodo                = h.fechaInicio,
        fechaFinPeriodo                   = h.fechaFin,
        estadoPeriodo                     = CAST(h.estadoPeriodo AS NVARCHAR(10)),
        capacidadMaxima                   = h.capacidadMaximaPermitida,
        estudiantesActivos                = h.estudiantesActivos,
        estudiantesFinalizados            = h.estudiantesFinalizados,
        estudiantesCanceladosVoluntad     = h.estudiantesCanceladosVoluntad,
        estudiantesCanceladosInasistencia = h.estudiantesCanceladosInasistencia,
        resumenTotalGrupos                = r.totalGrupos,
        resumenTotalPeriodos              = r.totalPeriodos,
        resumenGruposVigentes             = ISNULL(r.gruposVigentes, 0),
        resumenEstudiantesActivosVigentes = ISNULL(r.activosVigentes, 0),
        totalRegistros                    = COUNT(*) OVER()
    FROM historial h
    CROSS JOIN resumen r
    WHERE (@idPeriodoAcademico IS NULL OR h.idPeriodoAcademico = @idPeriodoAcademico)
    ORDER BY h.fechaInicio DESC, h.nombreAsignatura ASC, h.codigo ASC, h.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_kpis_coordinador
-- ============================================================================
-- usp_consultar_kpis_coordinador (HU065, HU070). READ_QUERY_RESULTSET (1 fila). Solo lectura: sin XACT_ABORT.
-- Ambito: el programa que coordina el ejecutor. Todas las cifras salen de las vistas de resumen (ver CONTRACT §1).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_kpis_coordinador]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
,
    @idPrograma UNIQUEIDENTIFIER = NULL)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idPeriodo UNIQUEIDENTIFIER;
    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idPrograma = @idPrograma OUTPUT, @idProgramaSolicitado = @idPrograma;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_interno)
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @total INT = 0, @regulares INT = 0, @riesgo INT = 0, @perdida INT = 0;
    DECLARE @programadas INT = 0, @vencidas INT = 0, @ejecutadas INT = 0, @sinRegistro INT = 0, @sinProcedencia INT = 0;

    -- PASO 3: Calcular los indicadores del periodo
    IF @idPeriodo IS NOT NULL
    BEGIN
        SELECT  @total = COUNT(*),
                @regulares = ISNULL(SUM(IIF(x.peor = 1, 1, 0)), 0),
                @riesgo = ISNULL(SUM(IIF(x.peor = 2, 1, 0)), 0),
                @perdida = ISNULL(SUM(IIF(x.peor = 3, 1, 0)), 0)
        FROM (
                SELECT  r.idEstudiante,
                        peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
                FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
                WHERE   r.idPrograma = @idPrograma AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
                GROUP BY r.idEstudiante
             ) x;

        SELECT  @programadas = COUNT(*),
                @vencidas = ISNULL(SUM(IIF(c.estaVencida = 1, 1, 0)), 0),
                @ejecutadas = ISNULL(SUM(IIF(c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1, 1, 0)), 0),
                @sinRegistro = ISNULL(SUM(IIF(c.estaVencida = 1 AND c.tieneRegistroAsistencia = 0, 1, 0)), 0),
                @sinProcedencia = ISNULL(SUM(IIF(c.procedenciaIndeterminada = 1, 1, 0)), 0)
        FROM    dbo.uv_cumplimiento_sesion_grupo c
        WHERE   EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp WHERE gp.idGrupo = c.idGrupo AND gp.idPrograma = @idPrograma) AND c.idPeriodoAcademico = @idPeriodo;
    END

    -- PASO 4: Consulta y retorno de resultados
    SELECT
        idPrograma = p.id,
        nombrePrograma = p.nombrePrograma,
        idPeriodoAcademico = pa.id,
        nombrePeriodoAcademico = pa.nombre,
        totalEstudiantes = @total,
        estudiantesRegulares = @regulares,
        estudiantesRiesgo = @riesgo,
        estudiantesPerdida = @perdida,
        tasaPermanencia = CAST(IIF(@total = 0, NULL, 100.0 * (@regulares + @riesgo) / @total) AS DECIMAL(5,2)),
        sesionesProgramadas = @programadas,
        sesionesVencidas = @vencidas,
        sesionesEjecutadas = @ejecutadas,
        sesionesVencidasSinRegistro = @sinRegistro,
        sesionesSinProcedenciaTemporal = @sinProcedencia,
        porcentajeCumplimiento = CAST(IIF(@vencidas = 0, NULL, 100.0 * @ejecutadas / @vencidas) AS DECIMAL(5,2)),
        porcentajeProgresoCalendario = CAST(IIF(@programadas = 0, NULL, 100.0 * @vencidas / @programadas) AS DECIMAL(5,2)),
        umbralAdvertencia = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA')), '') AS DECIMAL(5,2)),
        umbralPerdida = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA')), '') AS DECIMAL(5,2))
    FROM dbo.uv_programa p
    LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = @idPeriodo
    WHERE p.id = @idPrograma;
END;
GO

-- >>> stored-procedures/usp_consultar_kpis_decano
-- ============================================================================
-- usp_consultar_kpis_decano (HU102, HU106, HU144). READ_QUERY_RESULTSET de una fila. Solo lectura.
-- Estudiante = persona con la peor clasificacion de sus matriculas activas de la facultad (D3).
-- Retencion = (regular + riesgo) / total (D2). Ausentismo = faltas / sesiones ejecutadas, ponderado por matricula activa (D1).
-- sesionesEjecutadas = suma por matricula activa (denominador del ausentismo). Aforo = matriculados activos / cupo de los grupos habilitados (D4).
-- Lo que no puede calcularse es NULL; nunca un valor por defecto.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_kpis_decano]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idFacultad UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_facultad_decano_interno)
    EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idFacultad = @idFacultad OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_facultad_interno)
    EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @idFacultad, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @programas INT = (SELECT COUNT(*) FROM dbo.uv_programa p WHERE p.idFacultad = @idFacultad);
    DECLARE @total INT = 0, @regulares INT = 0, @riesgo INT = 0, @perdida INT = 0;
    DECLARE @sesiones INT = 0, @faltas INT = 0;
    DECLARE @tomasDictadas INT = 0, @horasDictadas DECIMAL(12,6) = 0, @horasFalta DECIMAL(12,6) = 0;
    DECLARE @grupos INT = 0, @cupo INT = 0, @matriculados INT = 0;

    -- PASO 3: Calcular los indicadores del periodo
    IF @idPeriodo IS NOT NULL
    BEGIN
        SELECT  @total = COUNT(*),
                @regulares = ISNULL(SUM(IIF(x.peor = 1, 1, 0)), 0),
                @riesgo = ISNULL(SUM(IIF(x.peor = 2, 1, 0)), 0),
                @perdida = ISNULL(SUM(IIF(x.peor = 3, 1, 0)), 0)
        FROM (
                SELECT  r.idEstudiante,
                        peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
                FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
                WHERE   EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa egp INNER JOIN dbo.uv_programa p ON p.id = egp.idPrograma WHERE egp.id = r.idEstudianteGrupo AND p.idFacultad = @idFacultad) AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
                GROUP BY r.idEstudiante
             ) x;

        SELECT  @sesiones = ISNULL(SUM(r.sesionesEjecutadas), 0),
                @faltas = ISNULL(SUM(r.faltasSinJustaCausa), 0),
                @tomasDictadas = ISNULL(SUM(r.tomasDictadas), 0),
                @horasDictadas = ISNULL(SUM(r.horasDictadas), 0),
                @horasFalta = ISNULL(SUM(r.horasFalta), 0)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        WHERE   EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa egp INNER JOIN dbo.uv_programa p ON p.id = egp.idPrograma WHERE egp.id = r.idEstudianteGrupo AND p.idFacultad = @idFacultad) AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A';

        SELECT  @grupos = COUNT(*),
                @cupo = ISNULL(SUM(g.capacidadMaximaPermitida), 0),
                @matriculados = ISNULL(SUM(g.estudiantesActivos), 0)
        FROM    dbo.uv_grupo g
        WHERE   EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
                        WHERE gp.idGrupo = g.id AND p.idFacultad = @idFacultad) AND g.idPeriodoAcademico = @idPeriodo AND g.grupoEstaHablitado = 1;
    END

    -- CULM-001 B.2 (CONTRACT §2.9, DEC-012/DEC-024): ausentismo por horas = 100 * Sigma horasFalta / Sigma horasDictadas de las
    -- matriculas A (antes faltas / sesiones); con sesiones de igual duracion y una toma, identico.
    DECLARE @ausentismo DECIMAL(5,2) = CAST(IIF(@horasDictadas = 0, NULL, 100.0 * @horasFalta / @horasDictadas) AS DECIMAL(5,2));

    -- PASO 4: Consulta y retorno de resultados
    SELECT
        idFacultad = f.id,
        nombreFacultad = f.nombreFacultad,
        idPeriodoAcademico = pa.id,
        nombrePeriodoAcademico = pa.nombre,
        totalProgramas = @programas,
        totalEstudiantes = @total,
        estudiantesRegulares = @regulares,
        estudiantesRiesgo = @riesgo,
        estudiantesPerdida = @perdida,
        tasaRetencion = CAST(IIF(@total = 0, NULL, 100.0 * (@regulares + @riesgo) / @total) AS DECIMAL(5,2)),
        sesionesEjecutadas = @sesiones,
        faltasSinJustaCausa = @faltas,
        porcentajeAusentismo = @ausentismo,
        porcentajeAsistencia = CAST(IIF(@ausentismo IS NULL, NULL, 100.0 - @ausentismo) AS DECIMAL(5,2)),
        gruposActivos = @grupos,
        cupoTotal = @cupo,
        matriculadosActivos = @matriculados,
        tasaAforo = CAST(IIF(@cupo = 0, NULL, 100.0 * @matriculados / @cupo) AS DECIMAL(7,2)),
        umbralAdvertencia = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA')), '') AS DECIMAL(5,2)),
        umbralPerdida = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA')), '') AS DECIMAL(5,2)),
        tomasDictadas = @tomasDictadas,
        horasDictadas = @horasDictadas,
        horasFalta = @horasFalta
    FROM dbo.uv_facultad f
    LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = @idPeriodo
    WHERE f.id = @idFacultad;
END;
GO

-- >>> stored-procedures/usp_consultar_kpis_institucion
-- ============================================================================
-- usp_consultar_kpis_institucion (HU133, HU135, HU136, HU138). READ_QUERY_RESULTSET de una fila. Solo lectura.
-- Mismas definiciones que las olas 1 y 2: persona = peor clasificacion de sus matriculas activas; ausentismo ponderado por
-- matricula activa (sesionesEjecutadas = suma por matricula); retencion = (regular + riesgo) / total.
-- Cumplimiento (HU138) = sesiones vencidas con registro / sesiones vencidas. Censo (HU135/HU136): con matricula o grupo activo
-- en el periodo y registrados (usuario activo; docentes = titulares de al menos un grupo de la institucion, sin depender del periodo).
-- Lo que no puede calcularse es NULL; nunca un valor por defecto.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_kpis_institucion]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_institucion_administrador_interno)
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idInstitucion = @idInstitucion OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_institucion_interno)
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @facultades INT = (SELECT COUNT(*) FROM dbo.uv_facultad f WHERE f.idInstitucion = @idInstitucion);
    DECLARE @programas INT = (SELECT COUNT(*) FROM dbo.uv_programa p WHERE p.idInstitucion = @idInstitucion);
    DECLARE @estudiantesRegistrados INT = (
        SELECT COUNT(DISTINCT ep.idEstudiante)
        FROM dbo.uv_estudiante_programa ep
        INNER JOIN dbo.uv_programa p ON p.id = ep.idPrograma
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = ep.idEstudiante
        WHERE p.idInstitucion = @idInstitucion AND ei.estaActivoUsuario = 1);
    DECLARE @docentesRegistrados INT = (
        SELECT COUNT(DISTINCT g.idDocente)
        FROM dbo.uv_grupo g
        INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
        INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        WHERE p.idInstitucion = @idInstitucion AND di.estaActivoUsuario = 1);

    DECLARE @total INT = 0, @regulares INT = 0, @riesgo INT = 0, @perdida INT = 0;
    DECLARE @sesiones INT = 0, @faltas INT = 0;
    DECLARE @tomasDictadas INT = 0, @horasDictadas DECIMAL(12,6) = 0, @horasFalta DECIMAL(12,6) = 0;
    DECLARE @vencidas INT = 0, @conRegistro INT = 0;
    DECLARE @docentesActivos INT = 0;

    -- PASO 3: Calcular los indicadores del periodo
    IF @idPeriodo IS NOT NULL
    BEGIN
        SELECT  @total = COUNT(*),
                @regulares = ISNULL(SUM(IIF(x.peor = 1, 1, 0)), 0),
                @riesgo = ISNULL(SUM(IIF(x.peor = 2, 1, 0)), 0),
                @perdida = ISNULL(SUM(IIF(x.peor = 3, 1, 0)), 0)
        FROM (
                SELECT  r.idEstudiante,
                        peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
                FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
                WHERE   EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa egp INNER JOIN dbo.uv_programa p ON p.id = egp.idPrograma WHERE egp.id = r.idEstudianteGrupo AND p.idInstitucion = @idInstitucion) AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
                GROUP BY r.idEstudiante
             ) x;

        SELECT  @sesiones = ISNULL(SUM(r.sesionesEjecutadas), 0),
                @faltas = ISNULL(SUM(r.faltasSinJustaCausa), 0),
                @tomasDictadas = ISNULL(SUM(r.tomasDictadas), 0),
                @horasDictadas = ISNULL(SUM(r.horasDictadas), 0),
                @horasFalta = ISNULL(SUM(r.horasFalta), 0)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        WHERE   EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa egp INNER JOIN dbo.uv_programa p ON p.id = egp.idPrograma WHERE egp.id = r.idEstudianteGrupo AND p.idInstitucion = @idInstitucion) AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A';

        SELECT  @vencidas = ISNULL(SUM(IIF(c.estaVencida = 1, 1, 0)), 0),
                @conRegistro = ISNULL(SUM(IIF(c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1, 1, 0)), 0)
        FROM    dbo.uv_cumplimiento_sesion_grupo c
        WHERE   EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma WHERE gp.idGrupo = c.idGrupo AND p.idInstitucion = @idInstitucion) AND c.idPeriodoAcademico = @idPeriodo;

        SELECT  @docentesActivos = COUNT(DISTINCT g.idDocente)
        FROM    dbo.uv_grupo g
        INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
        INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        WHERE   p.idInstitucion = @idInstitucion AND gp.idPeriodoAcademico = @idPeriodo AND gp.grupoEstaHablitado = 1 AND di.estaActivoUsuario = 1;
    END

    -- CULM-001 B.2 (CONTRACT §2.9, DEC-012/DEC-024): ausentismo por horas = 100 * Sigma horasFalta / Sigma horasDictadas de las
    -- matriculas A (antes faltas / sesiones); con sesiones de igual duracion y una toma, identico.
    DECLARE @ausentismo DECIMAL(5,2) = CAST(IIF(@horasDictadas = 0, NULL, 100.0 * @horasFalta / @horasDictadas) AS DECIMAL(5,2));

    -- PASO 4: Consulta y retorno de resultados
    SELECT
        idInstitucion = i.id,
        nombreInstitucion = i.nombre,
        idPeriodoAcademico = pa.id,
        nombrePeriodoAcademico = pa.nombre,
        totalFacultades = @facultades,
        totalProgramas = @programas,
        totalEstudiantes = @total,
        estudiantesRegulares = @regulares,
        estudiantesRiesgo = @riesgo,
        estudiantesPerdida = @perdida,
        tasaRetencion = CAST(IIF(@total = 0, NULL, 100.0 * (@regulares + @riesgo) / @total) AS DECIMAL(5,2)),
        sesionesEjecutadas = @sesiones,
        faltasSinJustaCausa = @faltas,
        porcentajeAusentismo = @ausentismo,
        porcentajeAsistencia = CAST(IIF(@ausentismo IS NULL, NULL, 100.0 - @ausentismo) AS DECIMAL(5,2)),
        sesionesVencidas = @vencidas,
        sesionesConRegistro = @conRegistro,
        porcentajeCumplimiento = CAST(IIF(@vencidas = 0, NULL, 100.0 * @conRegistro / @vencidas) AS DECIMAL(5,2)),
        estudiantesConMatriculaActiva = @total,
        estudiantesRegistrados = @estudiantesRegistrados,
        docentesConGrupoActivo = @docentesActivos,
        docentesRegistrados = @docentesRegistrados,
        umbralAdvertencia = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA')), '') AS DECIMAL(5,2)),
        umbralPerdida = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA')), '') AS DECIMAL(5,2)),
        tomasDictadas = @tomasDictadas,
        horasDictadas = @horasDictadas,
        horasFalta = @horasFalta
    FROM dbo.uv_institucion i
    LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = @idPeriodo
    WHERE i.id = @idInstitucion;
END;
GO

-- >>> stored-procedures/usp_consultar_oferta_creacion_grupo_docente
-- ============================================================================
-- usp_consultar_oferta_creacion_grupo_docente (F3, 2026-11-02)
--
-- Resultset: READ_QUERY_RESULTSET (una fila por asignatura que el docente puede abrir como grupo). NO es un
-- MUTATION_COMMAND_RESULTSET. Las fallas de RBAC se propagan con THROW (mensaje tecnico de catalogo, que lleva el
-- codigo para el clasificador del backend). Solo lectura: sin XACT_ABORT.
-- Que devuelve: el idDocente del ejecutor y las asignaturas activas de los planes activos de los programas con los
-- que el docente tiene vinculo activo. No expone nada fuera de esos programas. El periodo no se elige:
-- usp_crear_grupo toma el mas reciente cuando no se envia.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_oferta_creacion_grupo_docente]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    -- PASO 1: Validar el identificador de correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: Ejecutor obligatorio (GEN_002) y perfil DOCENTE (SEC_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto,
            @codigoPerfilRequerido = 'DOCENTE',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 3: Asignaturas activas con vinculo activo en un programa donde el docente tiene vinculo activo (CULM-001 B2NM:
    -- 1 fila por asignatura; programas = nombres de los programas del docente que la incluyen).
    SELECT
        idDocente          = x.idDocente,
        idAsignatura       = x.idAsignatura,
        codigoAsignatura   = x.codigo,
        nombreAsignatura   = x.nombre,
        programas          = CAST(STRING_AGG(x.nombrePrograma, N', ') WITHIN GROUP (ORDER BY x.nombrePrograma) AS NVARCHAR(1000))
    FROM (
        SELECT DISTINCT dp.idDocente, idAsignatura = a.id, a.codigo, a.nombre, dp.nombrePrograma
        FROM dbo.uv_docente_programa dp
        INNER JOIN dbo.uv_asignatura_plan_estudio v ON v.idPrograma = dp.idPrograma AND v.estaActivoVinculo = 1 AND v.estaActivoPlan = 1
        INNER JOIN dbo.uv_asignatura a ON a.id = v.idAsignatura AND a.estaActivaAsignatura = 1
        WHERE dp.idUsuario = @idUsuarioDefecto
          AND dp.estaActivoDocentePrograma = 1
    ) x
    GROUP BY x.idDocente, x.idAsignatura, x.codigo, x.nombre
    ORDER BY x.nombre, x.codigo;
END;
GO

-- >>> stored-procedures/usp_consultar_oferta_grupos_estudiante
-- ============================================================================
-- usp_consultar_oferta_grupos_estudiante (HU008)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo).
-- Oferta de grupos para el ESTUDIANTE ejecutor en periodos VIGENTES o PROXIMOS (fecha local TIEMPO.ZONA_HORARIA_SQLSERVER).
-- Regla de John (2026-10-27): las asignaturas propias del programa son las del componente ESP (especificas); BAS
-- (basicas) e INS (institucionales) son TRANSVERSALES. La oferta incluye:
--   - los grupos de asignaturas ESP de los programas en que esta inscrito (EstudiantePrograma);
--   - si OFERTA.INCLUIR_TRANSVERSALES = 1 (por defecto), los grupos de asignaturas BAS/INS de cualquier programa de
--     la(s) institucion(es) de sus programas. Con 0 no se muestran transversales (solo se ingresa con el QR/PIN del
--     docente, HU176B, o por matricula manual del docente, HU050).
-- Cada fila trae docente, horario, capacidad y cupos (capacidad - matriculas inscritas, minimo 0), el componente de la
-- asignatura y si el estudiante esta matriculado. Solo la matricula con el codigo del parametro MATRICULA/ESTADO_INSCRITA
-- cuenta como inscrita (CULM-001 A, N10). CULM-001 A.1: sin columnas de solicitud de ingreso (19 columnas).
-- Un ejecutor que no es estudiante obtiene 0 filas. Busqueda por asignatura (nombre o codigo) o nombre del grupo.
-- Paginacion acotada como R2 (pagina >= 1, tamano 1..100). Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_oferta_grupos_estudiante]
(
    @busqueda           NVARCHAR(50) = NULL,
    @numeroPagina       INT          = 1,
    @tamanoPagina       INT          = 10,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @texto NVARCHAR(50) = NULLIF(TRIM(@busqueda), '');
    DECLARE @patron NVARCHAR(120) = IIF(@texto IS NULL, NULL,
        CONCAT('%', REPLACE(REPLACE(REPLACE(@texto, '\', '\\'), '%', '\%'), '_', '\_'), '%'));
    DECLARE @zonaHoraria NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100));
    DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zonaHoraria AS DATE);
    DECLARE @incluirTransversales BIT = IIF(TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('OFERTA', 'INCLUIR_TRANSVERSALES')), '') AS INT) = 0, 0, 1);
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @idEstudiante UNIQUEIDENTIFIER;
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

BEGIN
    SET NOCOUNT ON;

-- PASO 1: Validar el identificador de correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: Ejecutor obligatorio (GEN_002)
    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    -- PASO 3: Validacion de entrada
    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SET @idEstudiante = (SELECT TOP 1 e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioDefecto);

    -- PASO 4: Consulta y retorno de resultados
    ;WITH oferta AS (
        SELECT
            g.id, g.codigo, g.nombre, g.cantidadEstudiantes AS capacidad,
            asg.id AS idAsignatura, asg.codigo AS codigoAsignatura, asg.nombre AS nombreAsignatura,
            g.docente, pa.id AS idPeriodo, pa.nombre AS nombrePeriodo, pa.fechaInicio, pa.fechaFin, comp.codigo AS codigoComponente,
            car.codigoCaracter, car.nombreCaracter,
            activos = (SELECT COUNT(*) FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
                       WHERE eg.grupo = g.id AND ee.codigo = @codigoInscrita)
        FROM dbo.Grupo g
        INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
        INNER JOIN dbo.Asignatura asg ON asg.id = g.asignatura
        INNER JOIN dbo.Componente comp ON comp.id = asg.componente
        -- CULM-001 B2NM (DEC-019/R5): 1 fila por grupo. Caracter = el del vinculo activo de la asignatura en un programa del
        -- estudiante (si hay varios, el de menor orden). Propias: ESP con vinculo en un programa del estudiante.
        OUTER APPLY (SELECT TOP 1 ca.codigo AS codigoCaracter, ca.nombre AS nombreCaracter
                     FROM dbo.AsignaturaPlanEstudio ape
                     INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                     INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                     INNER JOIN dbo.CaracterAsignaturaPlan ca ON ca.id = ape.caracter
                     WHERE ape.asignatura = asg.id AND ape.estaActivo = 1
                       AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = @idEstudiante AND ep.programa = pe.programa)
                     ORDER BY ca.orden, ca.id) car
        WHERE @idEstudiante IS NOT NULL
          AND pa.fechaFin >= @hoyLocal
          AND (
                -- Propias: especificas con vinculo activo en un programa del estudiante.
                (comp.codigo = 'ESP' AND car.codigoCaracter IS NOT NULL)
                -- Transversales: basicas e institucionales de cualquier programa de su institucion (configurable).
                OR (@incluirTransversales = 1 AND comp.codigo IN ('BAS', 'INS')
                    AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                                INNER JOIN dbo.Programa pp ON pp.id = ep.programa
                                INNER JOIN dbo.Facultad fp ON fp.id = pp.facultad
                                WHERE ep.estudiante = @idEstudiante AND fp.institucion = pa.institucion))
              )
          AND (
                @patron IS NULL
                OR asg.nombre LIKE @patron ESCAPE '\'
                OR asg.codigo LIKE @patron ESCAPE '\'
                OR g.nombre LIKE @patron ESCAPE '\'
              )
    )
    -- PASO 5: Consulta y retorno de resultados
    SELECT
        idGrupo                = o.id,
        codigoGrupo            = o.codigo,
        nombreGrupo            = o.nombre,
        idAsignatura           = o.idAsignatura,
        codigoAsignatura       = o.codigoAsignatura,
        nombreAsignatura       = o.nombreAsignatura,
        nombreDocente          = CAST(CONCAT_WS(N' ',
                                     NULLIF(TRIM(ud.primerNombre), N''),
                                     NULLIF(TRIM(ud.primerApellido), N''),
                                     NULLIF(TRIM(ud.segundoApellido), N'')) AS NVARCHAR(400)),
        idPeriodoAcademico     = o.idPeriodo,
        nombrePeriodoAcademico = o.nombrePeriodo,
        fechaInicioPeriodo     = o.fechaInicio,
        fechaFinPeriodo        = o.fechaFin,
        estadoPeriodo          = CAST(IIF(@hoyLocal < o.fechaInicio, 'PROXIMO', 'VIGENTE') AS NVARCHAR(10)),
        horario                = CAST((
                                     SELECT STRING_AGG(CONCAT(d.nombre, N' ', CONVERT(CHAR(5), h.horaInicio, 108), N'-', CONVERT(CHAR(5), h.horaFin, 108)), N'; ')
                                            WITHIN GROUP (ORDER BY CHARINDEX(d.codigo, N'LUMAMIJUVISADO'), h.horaInicio)
                                     FROM dbo.Horario h INNER JOIN dbo.Dia d ON d.id = h.dia
                                     WHERE h.grupo = o.id) AS NVARCHAR(400)),
        capacidadMaxima        = o.capacidad,
        estudiantesActivos     = o.activos,
        cuposDisponibles       = IIF(o.capacidad - o.activos < 0, 0, o.capacidad - o.activos),
        matriculado            = CAST(IIF(EXISTS (
                                     SELECT 1 FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
                                     WHERE eg.grupo = o.id AND eg.estudiante = @idEstudiante AND ee.codigo = @codigoInscrita), 1, 0) AS BIT),
        codigoComponente       = CAST(o.codigoComponente AS NVARCHAR(3)),
        codigoCaracter         = CAST(o.codigoCaracter AS NVARCHAR(3)),
        nombreCaracter         = CAST(o.nombreCaracter AS NVARCHAR(50)),
        totalRegistros         = COUNT(*) OVER()
    FROM oferta o
    INNER JOIN dbo.Docente doc ON doc.id = o.docente
    INNER JOIN dbo.Usuario ud  ON ud.id = doc.usuario
    ORDER BY o.nombreAsignatura ASC, o.fechaInicio ASC, o.codigo ASC, o.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_planes_estudio_programa_paginado
-- =============================================================================
-- CULM-001 B2NM (DEC-019): planes de estudio de los programas del coordinador, con totales por la tabla puente (vinculos activos).
-- Reemplaza PlanEstudioJpaRepository.HQL_POR_PROGRAMA / HQL_TOTAL_SEMESTRES / totales de malla. @idPrograma ajeno -> COO_003.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_planes_estudio_programa_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT,
    @tamanoPagina      INT,
    @idPrograma        UNIQUEIDENTIFIER = NULL,
    @estaActivo        BIT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoRechazo NVARCHAR(10);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        SET @codigoRechazo = 'VAL_001';

    IF @codigoRechazo IS NULL AND @estadoResultado = 1 AND @idPrograma IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE cp.idPrograma = @idPrograma)
        SET @codigoRechazo = 'COO_003';

    IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
    BEGIN
        IF @codigoRechazo IS NOT NULL
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = N'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idPlanEstudio         = pe.id,
        idPrograma            = pe.idPrograma,
        nombrePrograma        = pe.nombrePrograma,
        inp                   = pe.inp,
        estaActivoPlanEstudio = pe.estaActivoPlanEstudio,
        totalSemestres        = ISNULL((SELECT MAX(sp.numeroSemestre) FROM dbo.uv_semestre_plan_estudio sp WHERE sp.idPlanEstudio = pe.id), 0),
        totalAsignaturas      = (SELECT COUNT(*) FROM dbo.uv_asignatura_plan_estudio v WHERE v.idPlanEstudio = pe.id AND v.estaActivoVinculo = 1),
        totalCreditos         = ISNULL((SELECT SUM(v.credito) FROM dbo.uv_asignatura_plan_estudio v WHERE v.idPlanEstudio = pe.id AND v.estaActivoVinculo = 1), 0),
        totalRegistros        = COUNT(*) OVER()
    FROM dbo.uv_plan_estudio pe
    WHERE pe.idPrograma IN (SELECT cp.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE @idPrograma IS NULL OR cp.idPrograma = @idPrograma)
      AND (@estaActivo IS NULL OR pe.estaActivoPlanEstudio = @estaActivo)
    ORDER BY pe.nombrePrograma ASC, pe.inp ASC, pe.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_programas_creditos_facultad_paginado
-- ============================================================================
-- usp_consultar_programas_creditos_facultad_paginado (HU112 tabla unificada de programas y creditos)
--
-- Una fila por programa y plan de estudio de la facultad del decano ejecutor, con el numero de semestres,
-- asignaturas y la suma de creditos (Asignatura.credito) del plan. Los programas sin plan salen con una fila
-- de plan vacio (totales en 0). @busqueda compara contra el nombre del programa y el INP del plan.
-- Los totales cuentan todas las asignaturas del plan (activas o no), igual que la malla de /decano/planes-estudio.
-- totalSemestres: mayor numero de semestre del plan (regla HU082/HU083 del coordinador); antes contaba los semestres
-- creados (certificacion F3, 2026-11-06, decision de John).
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001).
-- Ambito: perfil DECANO; filas de uv_auth_programa (fail-closed) restringidas a la facultad a su cargo (uv_decano).
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_programas_creditos_facultad_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @busqueda           NVARCHAR(100)    = NULL,
    @estaActivo         BIT              = NULL
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @busquedaFiltro          NVARCHAR(100) = NULLIF(TRIM(@busqueda), '');
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: Correlacion, ejecutor, perfil DECANO y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'DECANO',
            @numeroPagina = @numeroPagina,
            @tamanoPagina = @tamanoPagina,
            @idUsuarioValidado = @idUsuario OUTPUT,
            @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 2: Consulta y retorno de resultados
        WITH totalesPlan AS (
            SELECT  sp.idPlanEstudio,
                    totalSemestres = ISNULL(MAX(sp.numeroSemestre), 0),
                    totalAsignaturas = COUNT(a.id),
                    totalCreditos = SUM(a.credito)
            FROM    dbo.uv_semestre_plan_estudio sp
            LEFT JOIN dbo.AsignaturaPlanEstudio ape ON ape.semestrePlanEstudio = sp.id AND ape.estaActivo = 1   -- CULM-001 B2NM: vinculos activos de la tabla puente
            LEFT JOIN dbo.uv_asignatura a ON a.id = ape.asignatura
            GROUP BY sp.idPlanEstudio
        )
        SELECT
            idPrograma            = p.id,
            nombrePrograma        = p.nombrePrograma,
            nombreTipoPrograma    = p.nombreTipoPrograma,
            nombreModalidad       = p.nombreModalidad,
            nombreJornada         = p.nombreJornada,
            estaActivoPrograma    = p.estaActivoPrograma,
            idPlanEstudio         = pe.id,
            inpPlanEstudio        = pe.inp,
            estaActivoPlanEstudio = pe.estaActivoPlanEstudio,
            -- ISNULL permitido solo sobre agregaciones (REC4 #3): un plan o programa sin filas suma 0.
            totalSemestres        = ISNULL(tp.totalSemestres, 0),
            totalAsignaturas      = ISNULL(tp.totalAsignaturas, 0),
            totalCreditos         = ISNULL(tp.totalCreditos, 0),
            totalRegistros        = COUNT(*) OVER()
        FROM dbo.uv_auth_programa p
        LEFT JOIN dbo.uv_plan_estudio pe ON pe.idPrograma = p.id
        LEFT JOIN totalesPlan tp ON tp.idPlanEstudio = pe.id
        WHERE
            p.idFacultad IN (SELECT d.idFacultad FROM dbo.uv_decano d WHERE d.idUsuario = @idUsuario)
            AND (@estaActivo IS NULL OR p.estaActivoPrograma = @estaActivo)
            AND (
                @busquedaFiltro IS NULL
                OR CHARINDEX(@busquedaFiltro, p.nombrePrograma) > 0
                OR CHARINDEX(@busquedaFiltro, CONVERT(NVARCHAR(20), pe.inp)) > 0
            )
        ORDER BY p.nombrePrograma ASC, p.id ASC, pe.inp DESC, pe.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO

-- >>> stored-procedures/usp_consultar_programas_grupo
-- =============================================================================
-- CULM-001 B2NM (S3 minimo): programas vigentes de un grupo, para el selector de la matricula manual y de la ventana QR.
-- Lo pueden usar el titular del grupo y el coordinador o decano con ambito sobre algun programa del grupo; si no, SEC_002 (403).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_programas_grupo]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idGrupo           UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoRechazo NVARCHAR(10);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        SET @codigoRechazo = 'VAL_001';
    IF @codigoRechazo IS NULL AND @estadoResultado = 1
       AND NOT (EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor)
                OR EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) pg
                           INNER JOIN dbo.ufn_programas_ambito_ejecutor(@idUsuarioEjecutor) amb ON amb.idPrograma = pg.idPrograma))
        SET @codigoRechazo = 'SEC_002';

    IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
    BEGIN
        IF @codigoRechazo IS NOT NULL
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = N'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idPrograma     = p.id,
        nombrePrograma = p.nombrePrograma,
        idPlanEstudio  = pg.idPlanEstudio,
        inpPlanEstudio = pg.inpPlanEstudio
    FROM dbo.ufn_programas_grupo(@idGrupo) pg
    INNER JOIN dbo.uv_programa p ON p.id = pg.idPrograma
    ORDER BY p.nombrePrograma ASC, p.id ASC;
END;
GO

-- >>> stored-procedures/usp_consultar_reenvio_verificacion_correo
-- IDENT-001: elegibilidad del reenvio del enlace de verificacion. Valida RBAC (DOCENTE o COORDINADOR), ambito
-- (docente titular del grupo o coordinador del programa del grupo), que el estudiante pertenezca al grupo, que su correo
-- no este verificado (VCE_005) y la espera minima desde la ultima emision (VCE_003, parametro REENVIO_ESPERA_MINUTOS).
-- Devuelve una fila con el usuario del estudiante; el backend registra entonces el aviso. Los rechazos se propagan con
-- THROW 51000 y mensaje "DBCODE=<codigo>|..." (como usp_consultar_detalle_solicitud_revision_docente).
-- READ_QUERY_RESULTSET: NON_GOLDEN_PATH_EXTENSION (ver test/test_contract_closure.sql).
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_reenvio_verificacion_correo]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idEstudiante      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @enAmbito           BIT = 0;
    DECLARE @idUsuarioEstudiante UNIQUEIDENTIFIER;
    DECLARE @correoConfirmado    BIT;
    DECLARE @ultimaEmisionUtc    DATETIME2(0);
    DECLARE @esperaMinutos       INT;
    DECLARE @codigoRechazo       VARCHAR(20) = NULL;
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: correlacion y ejecutor obligatorios
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idGrupo IS NULL OR @idEstudiante IS NULL)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idGrupo/idEstudiante',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 2: RBAC del ejecutor
    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioEjecutor,
            @codigoPerfilRequerido = 'DOCENTE,COORDINADOR',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    -- PASO 3: ambito jerarquico (titular del grupo o coordinador del programa del grupo) y pertenencia del estudiante
    IF @estadoResultado = 1
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM dbo.Grupo g
            INNER JOIN dbo.Docente d ON d.id = g.docente
            WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor
        )
        OR EXISTS (
            SELECT 1
            FROM dbo.Grupo g
            INNER JOIN dbo.uv_grupo_programa gpx ON gpx.idGrupo = g.id   -- CULM-001 B2NM: vigencia S1
            INNER JOIN dbo.Programa pr ON pr.id = gpx.idPrograma
            INNER JOIN dbo.Coordinador c ON c.id = pr.coordinador
            WHERE g.id = @idGrupo AND c.usuario = @idUsuarioEjecutor
              AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma epx WHERE epx.estudiante = @idEstudiante AND epx.programa = pr.id)
        )
            SET @enAmbito = 1;

        SELECT @idUsuarioEstudiante = e.usuario
        FROM dbo.Estudiante e
        INNER JOIN dbo.EstudianteGrupo eg ON eg.estudiante = e.id AND eg.grupo = @idGrupo
        WHERE e.id = @idEstudiante;

        IF @enAmbito = 0 OR @idUsuarioEstudiante IS NULL
            SET @codigoRechazo = 'VCE_004';
    END

    -- PASO 4: correo aun sin verificar y espera minima
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
    BEGIN
        SELECT @correoConfirmado = u.correoConfirmado FROM dbo.Usuario u WHERE u.id = @idUsuarioEstudiante;

        IF @correoConfirmado = 1
            SET @codigoRechazo = 'VCE_005';
        ELSE
        BEGIN
            SET @esperaMinutos = dbo.ufn_obtener_parametro_int(NULL, 'VERIFICACION_CORREO', 'REENVIO_ESPERA_MINUTOS');
            SELECT @ultimaEmisionUtc = MAX(t.fechaEmisionUtc) FROM dbo.TokenVerificacionCorreo t WHERE t.usuario = @idUsuarioEstudiante;
            IF @ultimaEmisionUtc IS NOT NULL AND @ultimaEmisionUtc > DATEADD(MINUTE, -@esperaMinutos, SYSUTCDATETIME())
                SET @codigoRechazo = 'VCE_003';
        END
    END

    IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = @codigoRechazo,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT @idUsuarioEstudiante AS idUsuario;
END;
GO

-- >>> stored-procedures/usp_consultar_resumen_asistencia_estudiante
-- ============================================================================
-- usp_consultar_resumen_asistencia_estudiante (CULM-001 B.2, HU004/HU009/HU013; CONTRACT §2.8.4, §3.2.8, F-EST-002)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001).
-- RBAC ESTUDIANTE; solo las matriculas del propio estudiante (Estudiante.usuario = @idUsuarioEjecutor). Filas: columnas de
-- uv_resumen_asistencia_estudiante_grupo (indicadores por horas). Sin paginacion (a lo sumo las materias del estudiante).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_asistencia_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ESTUDIANTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT
        idEstudianteGrupo              = r.idEstudianteGrupo,
        idEstudiante                   = r.idEstudiante,
        idGrupo                        = r.idGrupo,
        idAsignatura                   = r.idAsignatura,
        idPeriodoAcademico             = r.idPeriodoAcademico,
        codigoEstadoEstudiante         = r.codigoEstadoEstudiante,
        sesionesEjecutadas             = r.sesionesEjecutadas,
        asistencias                    = r.asistencias,
        faltasSinJustaCausa            = r.faltasSinJustaCausa,
        excusas                        = r.excusas,
        porcentajeInasistencia         = r.porcentajeInasistencia,
        codigoPermanencia              = r.codigoPermanencia,
        tomasDictadas                  = r.tomasDictadas,
        horasDictadas                  = r.horasDictadas,
        horasAsistidas                 = r.horasAsistidas,
        horasFalta                     = r.horasFalta,
        horasExcusa                    = r.horasExcusa,
        horasSinRegistro               = r.horasSinRegistro,
        porcentajeAsistenciaHoras      = r.porcentajeAsistenciaHoras,
        porcentajeExcusaHoras          = r.porcentajeExcusaHoras,
        porcentajeSinRegistroHoras     = r.porcentajeSinRegistroHoras,
        porcentajeInasistenciaSesiones = r.porcentajeInasistenciaSesiones,
        umbralAdvertencia              = r.umbralAdvertencia,
        umbralPerdida                  = r.umbralPerdida,
        sesionesAsistidas              = r.sesionesAsistidas,
        sesionesConFaltaSinJustaCausa  = r.sesionesConFaltaSinJustaCausa,
        sesionesConExcusa              = r.sesionesConExcusa
    FROM dbo.uv_resumen_asistencia_estudiante_grupo r
    INNER JOIN dbo.Estudiante e ON e.id = r.idEstudiante
    WHERE e.usuario = @idUsuarioDefecto
    ORDER BY r.idPeriodoAcademico ASC, r.idGrupo ASC;
END;
GO

-- >>> stored-procedures/usp_consultar_resumen_asistencia_estudiante_programa
-- ============================================================================
-- usp_consultar_resumen_asistencia_estudiante_programa (HU069). READ_QUERY_RESULTSET (una fila por matricula). Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_asistencia_estudiante_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idEstudiante       UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
,
    @idPrograma UNIQUEIDENTIFIER = NULL)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idPrograma = @idPrograma OUTPUT, @idProgramaSolicitado = @idPrograma;
    -- PASO 2: Validacion de negocio (usp_validar_estudiante_en_programa_interno)
    EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = @idEstudiante, @idPrograma = @idPrograma;
    -- PASO 3: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_interno)
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 4: Consulta y retorno de resultados
    SELECT
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        idAsignatura = g.idAsignatura,
        nombreAsignatura = g.nombreAsignatura,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        nombreEstadoEstudiante = eg.nombreEstadoEstudiante,
        sesionesEjecutadas = r.sesionesEjecutadas,
        asistencias = r.asistencias,
        faltasSinJustaCausa = r.faltasSinJustaCausa,
        excusas = r.excusas,
        porcentajeInasistencia = r.porcentajeInasistencia,
        codigoPermanencia = r.codigoPermanencia,
        -- CULM-001 B.2 (NB-2): asistencias/faltas/excusas cuentan tomas; sesionesEjecutadas cuenta sesiones
        tomasDictadas = r.tomasDictadas,
        horasDictadas = r.horasDictadas,
        horasFalta = r.horasFalta
    FROM dbo.uv_resumen_asistencia_estudiante_programa_grupo r
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = r.idEstudianteGrupo
    INNER JOIN dbo.uv_grupo g ON g.id = r.idGrupo
    WHERE r.idEstudiante = @idEstudiante AND r.idPrograma = @idPrograma AND r.idPeriodoAcademico = @idPeriodo
    ORDER BY g.nombreAsignatura ASC, g.codigo ASC, g.id ASC;
END;
GO

-- >>> stored-procedures/usp_consultar_resumen_asistencia_grupo_docente_paginado
-- ============================================================================
-- usp_consultar_resumen_asistencia_grupo_docente_paginado (CULM-001 B.2, HU040/HU041; CONTRACT §2.8.4, §3.2.8, F-DOC-004)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001,
-- PAG_001, GRU_*, SEC_002). RBAC DOCENTE titular del grupo. Filas: columnas de uv_resumen_asistencia_estudiante_grupo
-- (indicadores por horas) + nombreCompletoEstudiante + totalRegistros, orden nombreCompletoEstudiante (sabana del docente:
-- el cliente no calcula porcentajes).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_asistencia_grupo_docente_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idGrupo           UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 50
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
            OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_grupo_exista_por_id_interno
            @idGrupo = @idGrupoDefecto, @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @idUsuarioDefecto, @idEntidadPadre = @idGrupoDefecto, @tipoEntidadPadre = 'GRUPO',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    SELECT
        idEstudianteGrupo              = r.idEstudianteGrupo,
        idEstudiante                   = r.idEstudiante,
        idGrupo                        = r.idGrupo,
        idAsignatura                   = r.idAsignatura,
        idPeriodoAcademico             = r.idPeriodoAcademico,
        codigoEstadoEstudiante         = r.codigoEstadoEstudiante,
        sesionesEjecutadas             = r.sesionesEjecutadas,
        asistencias                    = r.asistencias,
        faltasSinJustaCausa            = r.faltasSinJustaCausa,
        excusas                        = r.excusas,
        porcentajeInasistencia         = r.porcentajeInasistencia,
        codigoPermanencia              = r.codigoPermanencia,
        tomasDictadas                  = r.tomasDictadas,
        horasDictadas                  = r.horasDictadas,
        horasAsistidas                 = r.horasAsistidas,
        horasFalta                     = r.horasFalta,
        horasExcusa                    = r.horasExcusa,
        horasSinRegistro               = r.horasSinRegistro,
        porcentajeAsistenciaHoras      = r.porcentajeAsistenciaHoras,
        porcentajeExcusaHoras          = r.porcentajeExcusaHoras,
        porcentajeSinRegistroHoras     = r.porcentajeSinRegistroHoras,
        porcentajeInasistenciaSesiones = r.porcentajeInasistenciaSesiones,
        umbralAdvertencia              = r.umbralAdvertencia,
        umbralPerdida                  = r.umbralPerdida,
        sesionesAsistidas              = r.sesionesAsistidas,
        sesionesConFaltaSinJustaCausa  = r.sesionesConFaltaSinJustaCausa,
        sesionesConExcusa              = r.sesionesConExcusa,
        nombreCompletoEstudiante       = eg.nombreCompletoEstudiante,
        totalRegistros                 = COUNT(1) OVER()
    FROM dbo.uv_resumen_asistencia_estudiante_grupo r
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = r.idEstudianteGrupo
    WHERE r.idGrupo = @idGrupoDefecto
    ORDER BY eg.nombreCompletoEstudiante ASC, r.idEstudiante ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_resumen_docentes_programa
-- ============================================================================
-- usp_consultar_resumen_docentes_programa (HU095)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Consolidado del directorio docente del programa del COORDINADOR: una fila por tipo de vinculacion con los
-- vinculos activos e inactivos (mismo criterio estaActivoDocentePrograma del directorio HU062/HU089).
--   - el programa se resuelve del ejecutor (usp_resolver_programa_coordinador_interno; KPI_001 si no coordina);
--   - incluye los tipos de vinculacion activos aunque no tengan docentes (contadores en cero) y los inactivos
--     que aun tengan vinculos en el programa.
-- Solo lectura: sin XACT_ABORT.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_docentes_programa]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
,
    @idPrograma UNIQUEIDENTIFIER = NULL)
AS

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.

BEGIN
    SET NOCOUNT ON;

-- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @validarUmbrales = 0,
        @idPrograma = @idPrograma OUTPUT, @idProgramaSolicitado = @idPrograma;

    -- PASO 2: Consulta y retorno de resultados
    SELECT
        idTipoVinculacion     = tv.id,
        codigoTipoVinculacion = tv.codigo,
        nombreTipoVinculacion = tv.nombre,
        totalActivos          = SUM(CASE WHEN d.idDocentePrograma IS NOT NULL AND d.estaActivoDocentePrograma = 1 THEN 1 ELSE 0 END),
        totalInactivos        = SUM(CASE WHEN d.idDocentePrograma IS NOT NULL AND d.estaActivoDocentePrograma = 0 THEN 1 ELSE 0 END)
    FROM dbo.TipoVinculacion tv
    LEFT JOIN dbo.uv_docente_programa d
           ON d.idTipoVinculacion = tv.id
          AND d.idPrograma = @idPrograma
    GROUP BY tv.id, tv.codigo, tv.nombre, tv.estado
    HAVING tv.estado = 1 OR COUNT(d.idDocentePrograma) > 0
    ORDER BY tv.nombre ASC, tv.id ASC;
END;
GO

-- >>> stored-procedures/usp_consultar_sesiones_facultad_paginado
-- ============================================================================
-- usp_consultar_sesiones_facultad_paginado (HU145 cronograma de sesiones de la facultad)
--
-- Sesiones programadas en los grupos de la facultad del decano ejecutor, ordenadas por fecha, con filtro
-- opcional por rango de fechas (dias completos, ambos inclusive) y programa.
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de paginacion se propagan con THROW (DBCODE=PAG_001).
-- Ambito: uv_auth_sesion / uv_auth_grupo (fail-closed) restringidas a los programas de las facultades cuyo
-- decano es el ejecutor.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_facultad_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @fechaDesde         DATE             = NULL,
    @fechaHasta         DATE             = NULL,
    @idPrograma         UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = TRY_CAST(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO') AS INT);
    DECLARE @inicio               DATETIME2 = CAST(@fechaDesde AS DATETIME2);
    DECLARE @finExclusivo         DATETIME2 = DATEADD(DAY, 1, CAST(@fechaHasta AS DATETIME2));
    DECLARE @offset               INT;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
           AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
                OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PAG_001',
                @p_param1 = @numeroPagina,
                @p_param2 = @tamanoPagina,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        SET @offset = (@numeroPagina - 1) * @tamanoPagina;

        EXEC dbo.usp_establecer_contexto_usuario_ejecutor
            @p_idUsuario = @idUsuarioDefecto;

        SELECT
            s.id,
            s.nombre,
            s.codigo,
            s.numeroSemana,
            s.fechaHoraInicio,
            s.fechaHoraFin,
            s.idGrupo,
            s.codigoGrupo,
            s.nombreGrupo,
            g.idAsignatura,
            g.nombreAsignatura,
            COUNT(*) OVER()         AS totalRegistros,
            -- CULM-001 B.1 (CONTRACT §2.7.7): estado de la sesion desde uv_sesion_estado
            se.estaCancelada,
            se.codigoTipoCancelacion,
            se.motivoCancelacion,
            se.nombreDiaFestivo,
            se.fechaCancelacionUtc
        FROM dbo.uv_auth_sesion s
        INNER JOIN dbo.uv_sesion_estado se ON se.idSesion = s.id
        INNER JOIN dbo.uv_auth_grupo g ON g.id = s.idGrupo
        -- CULM-001 B2NM (R5): 1 fila por sesion; el ambito es un EXISTS sobre los programas del grupo en la facultad del decano.
        WHERE EXISTS (SELECT 1
                      FROM dbo.uv_grupo_programa gp
                      INNER JOIN dbo.uv_programa x ON x.id = gp.idPrograma
                      WHERE gp.idGrupo = s.idGrupo
                        AND x.idFacultad IN (SELECT f.id FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano WHERE d.usuario = @idUsuarioDefecto)
                        AND (@idPrograma IS NULL OR x.id = @idPrograma))
          AND (@inicio IS NULL OR s.fechaHoraInicio >= @inicio)
          AND (@finExclusivo IS NULL OR s.fechaHoraInicio < @finExclusivo)
        ORDER BY s.fechaHoraInicio ASC, s.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
        THROW;
    END CATCH;
END;
GO

-- >>> stored-procedures/usp_consultar_tendencia_ausentismo
-- ============================================================================
-- usp_consultar_tendencia_ausentismo (HU134). READ_QUERY_RESULTSET sin paginar. Solo lectura.
-- Serie temporal del ausentismo del periodo por SEMANA (calendario, inicia el lunes) o MES, segun la hora local institucional
-- (parametro TIEMPO/ZONA_HORARIA_SQLSERVER) del inicio de la sesion. Solo sesiones vencidas con registro; solo intervalos con datos.
-- Ausentismo del intervalo = faltas SJC / sesiones-estudiante (matriculas activas de cada sesion ejecutada), igual que los KPIs.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_tendencia_ausentismo]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @granularidad       NVARCHAR(6)      = N'SEMANA'
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_institucion_administrador_interno)
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idInstitucion = @idInstitucion OUTPUT;

    DECLARE @g NVARCHAR(6) = UPPER(TRIM(ISNULL(@granularidad, N'SEMANA')));
    -- PASO 2: Validacion de negocio (GEN_002)
    IF @g NOT IN (N'SEMANA', N'MES')
    BEGIN
        SET @msgP1 = CAST(N'granularidad' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 3: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_institucion_interno)
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @zona NVARCHAR(100) = COALESCE(
        (SELECT TOP 1 valor FROM dbo.CatalogoParametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1),
        'SA Pacific Standard Time');

    -- PASO 4: Consulta y retorno de resultados
    WITH ejecutadas AS (
        SELECT  c.idSesion, c.idGrupo,
                fechaLocal = CAST(c.fechaHoraInicio AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE)
        FROM    dbo.uv_cumplimiento_sesion_grupo c
        WHERE   EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
                        WHERE gp.idGrupo = c.idGrupo AND p.idInstitucion = @idInstitucion) AND c.idPeriodoAcademico = @idPeriodo
          AND   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
    ),
    activos AS (
        SELECT idGrupo, n = COUNT(*) FROM dbo.uv_estudiante_grupo WHERE codigoEstadoEstudiante = N'A' GROUP BY idGrupo
    ),
    faltas AS (
        -- CULM-001 B.2 (CONTRACT §2.9; diferido a D: debe pasar a horas): una falta por estudiante y sesion segun el estado
        -- consolidado (uv_asistencia_sesion_horas); con una toma por sesion, identico al conteo anterior.
        SELECT  h.idSesion, f = SUM(IIF(h.tieneFaltaSinJustaCausa = 1, 1, 0))
        FROM    dbo.uv_asistencia_sesion_horas h
        INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = h.idEstudianteGrupo AND eg.codigoEstadoEstudiante = N'A'
        GROUP BY h.idSesion
    ),
    intervalo AS (
        SELECT  e.idSesion,
                inicio = CASE @g WHEN N'MES' THEN DATEFROMPARTS(YEAR(e.fechaLocal), MONTH(e.fechaLocal), 1)
                                 ELSE DATEADD(DAY, -(DATEDIFF(DAY, '19000101', e.fechaLocal) % 7), e.fechaLocal) END,
                fin = CASE @g WHEN N'MES' THEN EOMONTH(e.fechaLocal)
                              ELSE DATEADD(DAY, 6, DATEADD(DAY, -(DATEDIFF(DAY, '19000101', e.fechaLocal) % 7), e.fechaLocal)) END,
                sesionesEstudiante = ISNULL(ac.n, 0),
                faltas = ISNULL(fa.f, 0)
        FROM    ejecutadas e
        LEFT JOIN activos ac ON ac.idGrupo = e.idGrupo
        LEFT JOIN faltas fa ON fa.idSesion = e.idSesion
    )
    -- PASO 5: Consulta y retorno de resultados
    SELECT
        inicioIntervalo = inicio,
        finIntervalo = fin,
        sesionesEjecutadas = SUM(sesionesEstudiante),
        faltasSinJustaCausa = SUM(faltas),
        porcentajeAusentismo = CAST(IIF(SUM(sesionesEstudiante) = 0, NULL, 100.0 * SUM(faltas) / SUM(sesionesEstudiante)) AS DECIMAL(5,2))
    FROM intervalo
    GROUP BY inicio, fin
    ORDER BY inicio ASC;
END;
GO

-- >>> stored-procedures/usp_crear_asignatura
-- ============================================================================
-- usp_crear_asignatura
-- Reglas de negocio (decisiones de John, 2026-11-04):
--   * P5: el area y el componente deben existir en sus tablas (GEN_001); nunca se asigna uno "cualquiera".
--   * Creditos obligatorios y mayores que cero (ASI_001); no hay valor por defecto.
--   * El semestre debe existir en el plan de estudios (PLA_004); la malla del plan no se amplia desde aqui.
--   * El coordinador solo crea asignaturas en planes de su propio programa (PLA_002 si el plan no existe,
--     SEC_002 por usp_validar_titularidad_jerarquica_interno si el programa no es suyo).
-- Salida canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_asignatura]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @codigo             NVARCHAR(50),
    @nombre             NVARCHAR(50),
    @creditos           INT,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @semestreNumero     INT,
    @nombreArea         NVARCHAR(100),
    @nombreComponente   NVARCHAR(100),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL,
    @codigoCaracter     NVARCHAR(3) = NULL   -- CULM-001 B2NM (R1): NULL -> ASIGNATURA_PLAN/CARACTER_DEFECTO
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPlanEstudioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPlanEstudio, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDefecto            NVARCHAR(50)     = UPPER(TRIM(@codigo));
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);
    DECLARE @nombreAreaDefecto        NVARCHAR(100)    = TRIM(@nombreArea);
    DECLARE @nombreCompDefecto        NVARCHAR(100)    = TRIM(@nombreComponente);

    DECLARE @idAreaResolved       UNIQUEIDENTIFIER;
    DECLARE @idComponenteResolved UNIQUEIDENTIFIER;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @idProgramaPlan       UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validación de parámetros obligatorios
        IF @estadoResultado = 1 AND (@codigoDefecto IS NULL OR @codigoDefecto = '' OR @nombreDefecto IS NULL OR @nombreDefecto = '')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Codigo y Nombre son obligatorios. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2.1: Creditos obligatorios y mayores que cero (ASI_001), sin valor por defecto
        IF @estadoResultado = 1 AND (@creditos IS NULL OR @creditos <= 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ASI_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2.2: El plan existe (PLA_002) y pertenece al programa del coordinador (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idProgramaPlan = idPrograma FROM [dbo].[uv_plan_estudio] WHERE id = @idPlanEstudioDefecto;

            IF @idProgramaPlan IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PLA_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idProgramaPlan,
                @tipoEntidadPadre = 'PROGRAMA',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3 (CULM-001 B2NM, R2): unicidad del codigo contra la tabla (UX_Asignatura_codigo); existente -> ASI_002.
        --         La proteccion de concurrencia (UPDLOCK, HOLDLOCK) se toma dentro de la transaccion del PASO 5.
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[Asignatura] WHERE UPPER(TRIM(codigo)) = @codigoDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ASI_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Resolución de Área y Componente desde las tablas (P5, 2026-11-04): coincidencia exacta con su código
        -- o nombre; si no existen se rechaza con GEN_001. Nunca se asigna uno "cualquiera".
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_resolver_area_componente_asignatura_interno
                @area = @nombreAreaDefecto,
                @componente = @nombreCompDefecto,
                @obligatorios = 1,
                @idCorrelacion = @idCorrelacionDefecto,
                @idArea = @idAreaResolved OUTPUT,
                @idComponente = @idComponenteResolved OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4.9 (CULM-001 B2NM): el semestre del plan (PLA_004) y el caracter (ASI_007) se validan ANTES de escribir; asi un rechazo
        --          no necesita ROLLBACK (prohibido bajo INSERT ... EXEC) ni deja el catalogo a medias dentro de una transaccion ajena.
        IF @estadoResultado = 1
        BEGIN
            DECLARE @codigoRechazoPlan NVARCHAR(10);
            IF NOT EXISTS (SELECT 1 FROM dbo.SemestrePlanEstudio spe INNER JOIN dbo.Semestre sm ON sm.id = spe.semestre
                           WHERE spe.planEstudio = @idPlanEstudioDefecto AND sm.numero = @semestreNumero)
                SET @codigoRechazoPlan = 'PLA_004';
            ELSE IF NOT EXISTS (SELECT 1 FROM dbo.CaracterAsignaturaPlan c
                                WHERE c.estado = 1 AND c.codigo = COALESCE(NULLIF(TRIM(@codigoCaracter), N''),
                                      CAST(dbo.ufn_obtener_parametro('ASIGNATURA_PLAN', 'CARACTER_DEFECTO') AS NVARCHAR(3))))
                SET @codigoRechazoPlan = 'ASI_007';
            IF @codigoRechazoPlan IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @codigoRechazoPlan,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5 (CULM-001 B2NM, R3): catalogo + primer vinculo en una sola transaccion.
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            IF EXISTS (SELECT 1 FROM [dbo].[Asignatura] WITH (UPDLOCK, HOLDLOCK) WHERE UPPER(TRIM(codigo)) = @codigoDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ASI_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1
            BEGIN
                INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, estado)
                VALUES (@idAsignaturaDefecto, @codigoDefecto, @nombreDefecto, @creditos, @idAreaResolved, @idComponenteResolved, 1);

                EXEC dbo.usp_internal_asociar_asignatura_plan
                    @idAsignatura = @idAsignaturaDefecto,
                    @idPlanEstudio = @idPlanEstudioDefecto,
                    @semestreNumero = @semestreNumero,
                    @codigoCaracter = @codigoCaracter,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'Asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                IF @transaccionPropia = 1 COMMIT TRANSACTION;
            END
            ELSE IF @transaccionPropia = 1
                ROLLBACK TRANSACTION;

        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

-- >>> stored-procedures/usp_crear_grupo
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idAsignatura            UNIQUEIDENTIFIER,
    @idPeriodoAcademico      UNIQUEIDENTIFIER,
    @codigo                  INT,
    @nombre                  NVARCHAR(50),
    @idDocente               UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPeriodoAcademicoDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPeriodoAcademico, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto             NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idPeriodoResolved         UNIQUEIDENTIFIER = @idPeriodoAcademicoDefecto;
    DECLARE @capacidadMaximaDefecto    INT;
    DECLARE @idDocenteEjecutor         UNIQUEIDENTIFIER;
    DECLARE @ejecutorEsCoordinador     BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR,DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.6 (F3): el COORDINADOR crea y asigna cualquier docente; el DOCENTE solo crea grupos a su propio nombre
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.uv_coordinador_identidad ci WHERE ci.idUsuario = @idUsuarioEjecutorDefecto)
            BEGIN
                SET @ejecutorEsCoordinador = 1;
            END

            SELECT @idDocenteEjecutor = di.id
            FROM dbo.uv_docente_identidad di
            WHERE di.idUsuario = @idUsuarioEjecutorDefecto;

            IF @ejecutorEsCoordinador = 0 AND (@idDocenteEjecutor IS NULL OR @idDocenteEjecutor <> @idDocenteDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2: Validar asignatura en uv_asignatura
        IF @estadoResultado = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[uv_asignatura] WHERE id = @idAsignaturaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'Asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2B (F3): el DOCENTE solo abre grupos de asignaturas de programas con los que tiene vinculo activo
        IF @estadoResultado = 1 AND @ejecutorEsCoordinador = 0
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.uv_asignatura_plan_estudio v
                INNER JOIN dbo.uv_docente_programa dp ON dp.idPrograma = v.idPrograma
                WHERE v.idAsignatura = @idAsignaturaDefecto
                  AND v.estaActivoVinculo = 1   -- CULM-001 B2NM: algun programa de la asignatura (tabla puente)
                  AND dp.idDocente = @idDocenteEjecutor
                  AND dp.estaActivoDocentePrograma = 1
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Resolver período académico si viene nulo/guid defecto
        IF @estadoResultado = 1
        BEGIN
            IF @idPeriodoResolved IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_periodo_academico] WHERE id = @idPeriodoResolved)
            BEGIN
                SELECT TOP 1 @idPeriodoResolved = id 
                FROM [dbo].[uv_periodo_academico] 
                ORDER BY anio DESC;
            END

            IF @idPeriodoResolved IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_periodo_academico] WHERE id = @idPeriodoResolved)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'PeriodoAcademico',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Validar docente mediante procedimiento interno estandarizado
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_docente_exista_por_id_interno
                @idDocente = @idDocenteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4B (HU093/D12): el titular no puede tener su vinculo con el programa inactivado
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_docente_vinculo_activo_programa_interno
                @idDocente = @idDocenteDefecto,
                @idAsignatura = @idAsignaturaDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Validar unicidad de código de grupo en el período consultando uv_grupo
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (
                SELECT 1 FROM [dbo].[uv_grupo]
                WHERE idAsignatura = @idAsignaturaDefecto AND idPeriodoAcademico = @idPeriodoResolved AND codigo = @codigo
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_006',
                    @p_param1 = 'Grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 6: Resolver capacidad máxima por defecto desde el catálogo de parámetros (GRUPO/CAPACIDAD_MAXIMA_DEFECTO)
        IF @estadoResultado = 1
        BEGIN
            SET @capacidadMaximaDefecto = dbo.ufn_obtener_parametro_int(NULL, 'GRUPO', 'CAPACIDAD_MAXIMA_DEFECTO');

            IF @capacidadMaximaDefecto IS NULL OR @capacidadMaximaDefecto <= 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ERR_CAPACIDAD_GRUPO_INVALIDA',
                    @p_param1 = @capacidadMaximaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: Inserción directa de Grupo con capacidad máxima proveniente del catálogo
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.Grupo (
                id, asignatura, periodoAcademico, codigo, nombre,
                cantidadEstudiantes, cantidadEstudiantesFinalizaron,
                cantidadEstudiantesCancelaronVoluntadPropia,
                cantidadEstudiantesCancelaronAutomaticamente,
                docente
            )
            VALUES (
                @idGrupoDefecto,
                @idAsignaturaDefecto,
                @idPeriodoResolved,
                @codigo,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Grupo ', @codigo) END,
                @capacidadMaximaDefecto, 0, 0, 0,
                @idDocenteDefecto
            );

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

-- >>> stored-procedures/usp_desvincular_asignatura_plan
-- =============================================================================
-- Procedimiento: [dbo].[usp_desvincular_asignatura_plan]
-- CULM-001 B2NM (DEC-019, F-COO-005): baja logica del vinculo asignatura-plan (reemplaza el 501 del DELETE).
-- RBAC COORDINADOR; plan existente (PLA_002) y de un programa suyo (SEC_002). Sin vinculo activo en el plan: ASI_004.
-- ASI_005 si hay grupos de la asignatura en un periodo vigente o futuro cuyo UNICO programa vigente es el de este plan,
-- o matriculas activas de esos grupos cuyo unico programa comun con el grupo es este. Si pasa: estaActivo = 0 y
-- fechaDesvinculacionUtc = ahora (los grupos pasados conservan el programa por la regla S1).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_desvincular_asignatura_plan]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaPlan UNIQUEIDENTIFIER, @codigoRechazo NVARCHAR(10);
    DECLARE @zona NVARCHAR(100) = COALESCE((SELECT TOP 1 valor FROM dbo.CatalogoParametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1), 'SA Pacific Standard Time');
    DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @transaccionPropia BIT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'COORDINADOR', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            SELECT @idProgramaPlan = pe.programa FROM dbo.PlanEstudio pe WHERE pe.id = @idPlanEstudio;
            IF @idProgramaPlan IS NULL
                SET @codigoRechazo = 'PLA_002';
            ELSE
            BEGIN
                EXEC dbo.usp_validar_titularidad_jerarquica_interno
                    @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idProgramaPlan, @tipoEntidadPadre = 'PROGRAMA',
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
        END

        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            IF NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape WITH (UPDLOCK, HOLDLOCK)
                           INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                           WHERE ape.asignatura = @idAsignatura AND spe.planEstudio = @idPlanEstudio AND ape.estaActivo = 1)
                SET @codigoRechazo = 'ASI_004';
            -- ASI_005: grupos vigentes o futuros cuyo unico programa vigente es el del plan, o matriculas activas cuyo unico
            -- programa comun con el grupo es el del plan.
            ELSE IF EXISTS (
                SELECT 1
                FROM dbo.Grupo g
                INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico AND pa.fechaFin >= @hoyLocal
                WHERE g.asignatura = @idAsignatura
                  AND EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(g.id) pg WHERE pg.idPrograma = @idProgramaPlan)
                  AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(g.id) pg WHERE pg.idPrograma <> @idProgramaPlan)
            )
                SET @codigoRechazo = 'ASI_005';
            ELSE IF EXISTS (
                SELECT 1
                FROM dbo.Grupo g
                INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico AND pa.fechaFin >= @hoyLocal
                INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
                INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado AND ee.codigo = N'A'
                WHERE g.asignatura = @idAsignatura
                  AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = eg.estudiante AND ep.programa = @idProgramaPlan)
                  AND NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                                  INNER JOIN dbo.ufn_programas_grupo(g.id) pg ON pg.idPrograma = ep.programa
                                  WHERE ep.estudiante = eg.estudiante AND ep.programa <> @idProgramaPlan)
            )
                SET @codigoRechazo = 'ASI_005';
            ELSE
            BEGIN
                UPDATE ape
                SET ape.estaActivo = 0, ape.fechaDesvinculacionUtc = SYSUTCDATETIME()
                FROM dbo.AsignaturaPlanEstudio ape
                INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                WHERE ape.asignatura = @idAsignatura AND spe.planEstudio = @idPlanEstudio AND ape.estaActivo = 1;

                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_005', @p_param1 = 'Vinculo de asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @codigoRechazo IS NULL AND @transaccionPropia = 1
                COMMIT TRANSACTION;
            ELSE IF @codigoRechazo IS NOT NULL AND @transaccionPropia = 1
                ROLLBACK TRANSACTION;
        END

        IF @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT idCorrelacion = @idCorrelacionDefecto, mensajeUsuarioResultado = @mensajeUsuarioResultado,
           mensajeTecnicoResultado = @mensajeTecnicoResultado, estadoResultado = @estadoResultado;
END;
GO

-- >>> stored-procedures/usp_quitar_semestre_plan_estudio
-- HU083: quita un semestre del plan de estudios. Reglas:
--   * El semestre (@numeroSemestre) debe pertenecer al plan (PLA_004).
--   * Solo se quita el ultimo semestre, para que la malla siga siendo consecutiva (PLA_005).
--   * El semestre no puede tener asignaturas asociadas, activas o inactivas (PLA_006).
-- RBAC COORDINADOR + existencia del plan + titularidad PROGRAMA del plan se validan DENTRO del SP.
-- Concurrencia: la fila del plan se bloquea (UPDLOCK, HOLDLOCK) mientras se evaluan las reglas.
CREATE OR ALTER PROCEDURE [dbo].[usp_quitar_semestre_plan_estudio]
(
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @numeroSemestre     INT,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPlanEstudioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPlanEstudio, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaPlan           UNIQUEIDENTIFIER;
    DECLARE @planBloqueado            UNIQUEIDENTIFIER;
    DECLARE @idSemestrePlan           UNIQUEIDENTIFIER;
    DECLARE @numeroUltimo             INT;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @codigoRechazo           VARCHAR(100);

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.
    DECLARE @estadoTransaccionCatch INT;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar perfil del ejecutor (RBAC COORDINADOR)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validacion de negocio (GEN_002)
        IF @estadoResultado = 1 AND (@numeroSemestre IS NULL OR @numeroSemestre <= 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'numeroSemestre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Validacion de negocio (PLA_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idProgramaPlan = pe.programa FROM dbo.PlanEstudio pe WHERE pe.id = @idPlanEstudioDefecto;
            IF @idProgramaPlan IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PLA_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 6: Validar titularidad del ejecutor sobre PROGRAMA
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idProgramaPlan,
                @tipoEntidadPadre = 'PROGRAMA', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 7: Validar la accion y el motivo (codigo de rechazo)
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_quitar_semestre_plan;
                SET @savepointCreado = 1;
            END

            SELECT @planBloqueado = pe.id
            FROM dbo.PlanEstudio pe WITH (UPDLOCK, HOLDLOCK)
            WHERE pe.id = @idPlanEstudioDefecto;

            SELECT @idSemestrePlan = sp.id
            FROM dbo.SemestrePlanEstudio sp
            INNER JOIN dbo.Semestre s ON s.id = sp.semestre
            WHERE sp.planEstudio = @idPlanEstudioDefecto AND s.numero = @numeroSemestre;

            SELECT @numeroUltimo = MAX(s.numero)
            FROM dbo.SemestrePlanEstudio sp
            INNER JOIN dbo.Semestre s ON s.id = sp.semestre
            WHERE sp.planEstudio = @idPlanEstudioDefecto;

            SET @codigoRechazo =
                CASE
                    WHEN @idSemestrePlan IS NULL THEN 'PLA_004'
                    WHEN @numeroSemestre <> @numeroUltimo THEN 'PLA_005'
                    WHEN EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape WHERE ape.semestrePlanEstudio = @idSemestrePlan) THEN 'PLA_006'   -- CULM-001 B2NM: vinculos de la tabla puente (los inactivos tambien bloquean por la FK)
                END;

            IF @codigoRechazo IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                DELETE FROM dbo.SemestrePlanEstudio WHERE id = @idSemestrePlan;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_005', @p_param1 = 'Plan de estudio',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Semestre quitado: ', @numeroSemestre, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    COMMIT TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                BEGIN
                    ROLLBACK TRANSACTION;
                END
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_quitar_semestre_plan;
        END
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

-- >>> stored-procedures/usp_registrar_estudiante_en_grupo
-- ============================================================================
-- usp_registrar_estudiante_en_grupo (HU050, STUDENT-GROUP CANONICAL COMMAND, NON-GOLDEN)
--
-- Matricula manual de un estudiante en un grupo. CULM-001 A.1:
--   * F-COO-004: solo el DOCENTE TITULAR del grupo matricula (perfil DOCENTE y titularidad GRUPO, SEC_001/SEC_002).
--   * DEC-009: una matricula retirada del estudiante en el grupo se reactiva (la misma fila) en el interno.
--   * Atomico (bloqueante 1): SET XACT_ABORT ON; transaccion propia si @@TRANCOUNT = 0, si no savepoint
--     sp_registrar_estudiante_grupo. Las validaciones sin escritura van antes del savepoint de negocio
--     sp_registrar_estudiante_negocio; un rechazo posterior a crear Usuario/Estudiante revierte ese savepoint (sin filas
--     parciales). El resultset canonico va fuera de la transaccion. Firma y resultset sin cambio.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER = NULL,
    @idPrograma              UNIQUEIDENTIFIER = NULL   -- CULM-001 B2NM: obligatorio solo si el grupo tiene varios programas (EST_005/EST_006)
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteResultado    UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @identidadEscrita           BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_registrar_estudiante_grupo;
            SET @savepointCreado = 1;
        END

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor (obligatorio)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.8: Validar existencia del grupo antes de sincronizar identidad
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.85 (CULM-001 A.1, F-COO-004): el ejecutor debe ser el docente titular del grupo (SEC_002).
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idGrupoDefecto,
                @tipoEntidadPadre = 'GRUPO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.9: Validar cupo disponible antes de sincronizar identidad.
        -- usp_validar_grupo_exista_por_id_interno ya no valida cupo (sesiones se pueden programar en grupos llenos);
        -- la matrícula debe rechazarse aquí para no dejar Usuario/Estudiante parciales.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Sincronización de identidad (Usuario y Estudiante) e inscripción en grupo, bajo el savepoint de negocio
        IF @estadoResultado = 1
        BEGIN
            SAVE TRANSACTION sp_registrar_estudiante_negocio;

            DECLARE @idTipoIdTarget UNIQUEIDENTIFIER = @idTipoIdIdentificacion;
            IF @idTipoIdTarget IS NULL
            BEGIN
                SELECT TOP 1 @idTipoIdTarget = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC';
                IF @idTipoIdTarget IS NULL SELECT TOP 1 @idTipoIdTarget = id FROM dbo.TipoIdentificacion;
            END

            DECLARE @idUsuarioTarget UNIQUEIDENTIFIER;
            SELECT TOP 1 @idUsuarioTarget = id FROM dbo.Usuario WHERE correo = LOWER(TRIM(@correo));

            -- IDENT-001: en un alta nueva (sin usuario con ese correo) el correo debe ser institucional. El dominio es el
            -- parametro REGISTRO/DOMINIO_CORREO_ESTUDIANTE; un usuario existente no se revalida (D5).
            IF @estadoResultado = 1 AND @idUsuarioTarget IS NULL
            BEGIN
                DECLARE @dominioInstitucional NVARCHAR(255) = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
                IF dbo.ufn_correo_cumple_dominio_institucional(@correo, @dominioInstitucional) = 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'VCE_001',
                        @p_param1 = @dominioInstitucional,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            IF @estadoResultado = 1 AND @idUsuarioTarget IS NULL
            BEGIN
                SET @identidadEscrita = 1;
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdTarget,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correo,
                    @password = @password,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                    SELECT TOP 1 @idUsuarioTarget = id FROM dbo.Usuario WHERE correo = LOWER(TRIM(@correo));
            END

            IF @estadoResultado = 1 AND @idUsuarioTarget IS NOT NULL
            BEGIN
                SELECT TOP 1 @idEstudianteResultado = id FROM dbo.Estudiante WHERE usuario = @idUsuarioTarget;

                IF @idEstudianteResultado IS NULL
                BEGIN
                    SET @identidadEscrita = 1;
                    EXEC dbo.usp_sincronizar_estudiante_interno
                        @idUsuario = @idUsuarioTarget,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;

                    IF @estadoResultado = 1
                        SELECT TOP 1 @idEstudianteResultado = id FROM dbo.Estudiante WHERE usuario = @idUsuarioTarget;
                END
            END

            IF @estadoResultado = 1 AND @idEstudianteResultado IS NOT NULL
            BEGIN
                EXEC dbo.usp_registrar_estudiante_en_grupo_interno
                    @idEstudiante = @idEstudianteResultado,
                    @idGrupo = @idGrupoDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @idProgramaElegido = @idPrograma,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            -- Rechazo despues de crear Usuario/Estudiante: se revierte solo el trabajo de negocio. Sin identidad escrita
            -- no hay nada que revertir (el interno no deja escrituras en sus rechazos de negocio), y se evita un
            -- ROLLBACK innecesario, que SQL Server prohibe bajo INSERT ... EXEC.
            IF @estadoResultado = 0 AND @identidadEscrita = 1 AND XACT_STATE() = 1
                ROLLBACK TRANSACTION sp_registrar_estudiante_negocio;
        END

        -- Cierre de la transaccion propia
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() = -1
                ROLLBACK TRANSACTION;
        END

    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_registrar_estudiante_grupo;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

-- >>> stored-procedures/usp_registrar_estudiante_en_grupo_interno
-- ============================================================================
-- usp_registrar_estudiante_en_grupo_interno (HU050 manual y HU176B QR/PIN)
--
-- Requiere transaccion del llamador; no la abre ni la confirma. Sus dos llamadores publicos la abren
-- (usp_registrar_estudiante_en_grupo y usp_internal_matricular_por_token) y revierten su savepoint de negocio ante un
-- rechazo posterior a la escritura (docs/arquitectura/transaccion-procedimiento.md, internos compuestos).
-- CULM-001 A.1 (DEC-009): PASO 3.8 reactiva la matricula RETIRADA del estudiante en el grupo (misma fila, I -> estado
-- destino) mediante usp_internal_reactivar_matricula_retirada; sin matricula retirada sigue el alta normal. La regla de
-- inscripcion en el programa (componente ESP) es comun a los dos caminos y vive solo aqui.
-- El estado por defecto ('' o el parametro) se resuelve con MATRICULA/ESTADO_INSCRITA (sin literal quemado).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo_interno]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @codigoEstado            NVARCHAR(10) = 'A',
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @idProgramaElegido       UNIQUEIDENTIFIER = NULL   -- CULM-001 B2NM: programa para grupos con varios programas
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstadoActivo       UNIQUEIDENTIFIER;
    DECLARE @reactivada           BIT = 0;

    -- Inicialización de respuesta desde parámetros del catálogo
    SELECT 
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Obtener identificador del Estado para EstudianteGrupo
        IF @estadoResultado = 1
        BEGIN
            DECLARE @codigoEstadoDefecto NVARCHAR(10) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@codigoEstado, 'GENERAL', 'CADENA_VACIA')));
            IF @codigoEstadoDefecto = '' SET @codigoEstadoDefecto = UPPER(TRIM(CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10))));

            SELECT @idEstadoActivo = id 
            FROM dbo.uv_estado_estudiante_grupo 
            WHERE codigo = @codigoEstadoDefecto;

            IF @idEstadoActivo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001',
                    @p_param1 = 'Estado Estudiante Grupo (A)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Validaciones de reglas de negocio en sub-procedimientos
        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno 
                @idEstudiante = @idEstudianteDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_cruce_horario_estudiante_interno 
                @idEstudiante = @idEstudianteDefecto, 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3.7 (CULM-001 B2NM, DEC-020/R7): toda matricula (alta o reactivacion) tiene EstudiantePrograma en un programa del grupo.
        IF @estadoResultado = 1
        BEGIN
            DECLARE @idProgramaAsegurado UNIQUEIDENTIFIER;
            EXEC dbo.usp_internal_asegurar_estudiante_programa_grupo
                @idEstudiante = @idEstudianteDefecto,
                @idGrupo = @idGrupoDefecto,
                @idProgramaElegido = @idProgramaElegido,
                @idCorrelacion = @idCorrelacionDefecto,
                @idProgramaResultado = @idProgramaAsegurado OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3.8 (CULM-001 A.1, DEC-009): reactivar la matricula retirada (misma fila) si existe.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_internal_reactivar_matricula_retirada
                @idEstudiante = @idEstudianteDefecto,
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @codigoEstadoDestino = @codigoEstadoDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @reactivada = @reactivada OUTPUT;
        END

        IF @estadoResultado = 1 AND @reactivada = 0
        BEGIN
            EXEC dbo.usp_validar_registro_estudiante_en_grupo_interno 
                @idEstudiante = @idEstudianteDefecto, 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Inscripcion en el programa (comun al alta y a la reactivacion) e insercion del alta en dbo.EstudianteGrupo
        IF @estadoResultado = 1 
        BEGIN
            -- (La regla ESP de HU008 fue reemplazada por R7: el vinculo se garantiza en el PASO 3.7.)

            IF @reactivada = 0
            BEGIN
                INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
                VALUES (NEWID(), @idEstadoActivo, @idEstudianteDefecto, @idGrupoDefecto);
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Estudiante en Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

-- >>> stored-procedures/usp_registrar_estudiante_en_programa_interno
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_estudiante_en_programa_interno]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idPrograma              UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @idInstitucionEstudiante UNIQUEIDENTIFIER;
    DECLARE @idInstitucionPrograma   UNIQUEIDENTIFIER;
    DECLARE @idInstitucionFacultad   UNIQUEIDENTIFIER;

    -- Inicialización de respuesta desde parámetros del catálogo
    SELECT 
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Obtención y comprobación de la consistencia institucional cruzada
        IF @estadoResultado = 1
        BEGIN
            -- CULM-001 B2NM (O-B3): la institucion del estudiante sale de cualquiera de sus matriculas (programas del grupo);
            -- sin matriculas se omite la comparacion y se valida solo el programa.
            SELECT TOP 1 @idInstitucionEstudiante = pr0.idInstitucion
            FROM dbo.EstudianteGrupo eg0
            CROSS APPLY dbo.ufn_programas_grupo(eg0.grupo) pg0
            INNER JOIN dbo.uv_programa pr0 ON pr0.id = pg0.idPrograma
            WHERE eg0.estudiante = @idEstudianteDefecto
            ORDER BY pr0.idInstitucion;

            SELECT TOP 1 
                @idInstitucionPrograma = idInstitucion,
                @idInstitucionFacultad = idInstitucion
            FROM dbo.uv_programa 
            WHERE id = @idProgramaDefecto;

            IF @idInstitucionPrograma IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Estudiante WHERE id = @idEstudianteDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_002',
                    @p_param1 = 'Datos institucionales de Estudiante/Programa',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1 AND ((@idInstitucionEstudiante IS NOT NULL AND @idInstitucionEstudiante <> @idInstitucionPrograma) OR @idInstitucionPrograma <> @idInstitucionFacultad)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'INST_001',
                @p_param1 = @idEstudianteDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validación de vinculación previa e inserción en dbo.EstudiantePrograma
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @idEstudianteDefecto AND programa = @idProgramaDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'EST_003',
                @p_param1 = @idEstudianteDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 1;
        END
        ELSE IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
            VALUES (NEWID(), @idEstudianteDefecto, @idProgramaDefecto);

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Estudiante en Programa',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO

-- >>> stored-procedures/usp_toggle_estado_asignatura
CREATE OR ALTER PROCEDURE [dbo].[usp_toggle_estado_asignatura]
(
    @idAsignatura   UNIQUEIDENTIFIER,
    @idCorrelacion  UNIQUEIDENTIFIER,
    -- REC2 (auditoria BD 2026-10-28): ejecutor obligatorio (GEN_002 si llega NULL). El DEFAULT solo conserva la
    -- compatibilidad de firma; RBAC COORDINADOR + titularidad del PROGRAMA se validan en usp_validar_gestion_asignatura_coordinador_interno.
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio, perfil COORDINADOR, existencia de la asignatura y titularidad del
        --         programa (REC2: logica comun en usp_validar_gestion_asignatura_coordinador_interno)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno
                @idAsignatura = @idAsignaturaDefecto,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @exigirTodosLosProgramas = 1,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Alternar estado atómicamente
        IF @estadoResultado = 1
        BEGIN
            UPDATE dbo.Asignatura
            SET estado = CASE WHEN estado = 1 THEN 0 ELSE 1 END
            WHERE id = @idAsignaturaDefecto;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'EstadoAsignatura',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO


-- 7. Backfill de EstudiantePrograma (DEC-020) y reporte
DECLARE @codigoActiva NVARCHAR(10) = N'A';
BEGIN TRY
    BEGIN TRANSACTION;
    -- estudiantes activos (matricula activa) sin ningun EstudiantePrograma
    SELECT eg.estudiante, eg.grupo, pg.idPrograma
    INTO #act
    FROM dbo.EstudianteGrupo eg
    INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado AND ee.codigo = @codigoActiva
    CROSS APPLY dbo.ufn_programas_grupo(eg.grupo) pg;

    SELECT estudiante, programas = COUNT(DISTINCT idPrograma), idPrograma = (SELECT TOP 1 x.idPrograma FROM #act x WHERE x.estudiante = a.estudiante ORDER BY x.idPrograma),
           grupo = (SELECT TOP 1 x.grupo FROM #act x WHERE x.estudiante = a.estudiante ORDER BY x.grupo),
           lista = STRING_AGG(CAST(idPrograma AS NVARCHAR(40)), N',')
    INTO #sinEP
    FROM (SELECT DISTINCT estudiante, idPrograma FROM #act) a
    WHERE NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = a.estudiante)
    GROUP BY estudiante;

    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
    SELECT NEWID(), s.estudiante, s.idPrograma FROM #sinEP s WHERE s.programas = 1;
    INSERT INTO dbo.zz_reporte_culm001_b2nm_estudiante_programa (id, estudiante, grupo, programa, tipo, detalle)
    SELECT NEWID(), s.estudiante, s.grupo, s.idPrograma, N'CREADO', N'Vinculo creado desde el programa unico de sus matriculas activas.'
    FROM #sinEP s WHERE s.programas = 1;
    INSERT INTO dbo.zz_reporte_culm001_b2nm_estudiante_programa (id, estudiante, grupo, programa, tipo, detalle)
    SELECT NEWID(), s.estudiante, s.grupo, NULL, N'AMBIGUO', LEFT(CONCAT(N'Programas: ', s.lista), 400)
    FROM #sinEP s WHERE s.programas > 1
      AND NOT EXISTS (SELECT 1 FROM dbo.zz_reporte_culm001_b2nm_estudiante_programa r WHERE r.estudiante = s.estudiante AND r.tipo = N'AMBIGUO');

    -- matriculas activas sin interseccion con algun vinculo existente: solo se reportan
    INSERT INTO dbo.zz_reporte_culm001_b2nm_estudiante_programa (id, estudiante, grupo, programa, tipo, detalle)
    SELECT NEWID(), a.estudiante, a.grupo, NULL, N'SIN_INTERSECCION', N'Matricula activa sin EstudiantePrograma en ningun programa del grupo.'
    FROM (SELECT DISTINCT estudiante, grupo FROM #act) a
    WHERE EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = a.estudiante)
      AND NOT EXISTS (SELECT 1 FROM #act x INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = x.estudiante AND ep.programa = x.idPrograma
                      WHERE x.estudiante = a.estudiante AND x.grupo = a.grupo)
      AND NOT EXISTS (SELECT 1 FROM dbo.zz_reporte_culm001_b2nm_estudiante_programa r WHERE r.estudiante = a.estudiante AND r.grupo = a.grupo AND r.tipo = N'SIN_INTERSECCION');
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
DROP TABLE IF EXISTS #act;
DROP TABLE IF EXISTS #sinEP;
GO
SELECT tipo, total = COUNT(*) FROM dbo.zz_reporte_culm001_b2nm_estudiante_programa GROUP BY tipo;
GO

-- 8. Mensajes (semilla 38) y permisos (rol_asistencias_runtime_culm001_b2nm.sql)
-- CULM-001 B2NM (CONTRACT §2.8.1): mensajes de asignaturas por plan, matricula con programa y ambito de coordinacion.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('ASI_002', 'BUSINESS_ERROR', 'MEDIO', N'Ya existe una asignatura con ese código. Usa "Asociar asignatura existente" para agregarla a este plan.'),
    ('ASI_003', 'BUSINESS_ERROR', 'MEDIO', N'La asignatura ya está asociada a este plan de estudios.'),
    ('ASI_004', 'BUSINESS_ERROR', 'MEDIO', N'La asignatura no está asociada a este plan de estudios.'),
    ('ASI_005', 'BUSINESS_ERROR', 'ALTO',  N'No puedes quitar la asignatura de este plan: tiene grupos o estudiantes del programa en el periodo vigente o en periodos futuros.'),
    ('ASI_006', 'BUSINESS_ERROR', 'MEDIO', N'La asignatura es compartida con programas que no coordinas; solo puedes cambiar su semestre y su carácter en tu plan.'),
    ('ASI_007', 'BUSINESS_ERROR', 'MEDIO', N'El carácter de la asignatura no es válido.'),
    ('EST_005', 'BUSINESS_ERROR', 'MEDIO', N'El grupo pertenece a varios programas: indica el programa.'),
    ('EST_006', 'BUSINESS_ERROR', 'MEDIO', N'El programa indicado no corresponde a los programas del grupo.'),
    ('MQR_008', 'BUSINESS_ERROR', 'MEDIO', N'No se pudo determinar tu programa en este grupo. Pide a tu docente que te matricule.'),
    ('COO_002', 'BUSINESS_ERROR', 'MEDIO', N'Coordinas varios programas: selecciona el programa que quieres consultar.'),
    ('COO_003', 'BUSINESS_ERROR', 'ALTO',  N'El programa indicado no pertenece a tu coordinación.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('ASI_002', 'BUSINESS_ERROR', 'MEDIO', N'Regla: Asignatura.codigo es unico global (UX_Asignatura_codigo); use usp_asociar_asignatura_plan para vincular una existente.'),
    ('ASI_003', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la asignatura ya tiene un vinculo activo en el plan (mismo u otro semestre).'),
    ('ASI_004', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la asignatura no tiene vinculo activo con el plan indicado.'),
    ('ASI_005', 'BUSINESS_ERROR', 'ALTO',  N'Regla: hay grupos vigentes o futuros, o matriculas activas, cuyo unico programa comun es el del plan.'),
    ('ASI_006', 'BUSINESS_ERROR', 'MEDIO', N'Regla S2: el catalogo de una asignatura compartida solo lo cambia quien coordina todos sus programas con vinculo activo.'),
    ('ASI_007', 'BUSINESS_ERROR', 'MEDIO', N'Validacion: codigoCaracter no existe en CaracterAsignaturaPlan o esta inactivo.'),
    ('EST_005', 'BUSINESS_ERROR', 'MEDIO', N'Regla R7/S3: el grupo tiene varios programas y no se envio idPrograma.'),
    ('EST_006', 'BUSINESS_ERROR', 'MEDIO', N'Regla R7/S3: idPrograma no esta entre los programas del grupo.'),
    ('MQR_008', 'BUSINESS_ERROR', 'MEDIO', N'Regla S3: el token no tiene programaPorDefecto y el grupo tiene varios programas.'),
    ('COO_002', 'BUSINESS_ERROR', 'MEDIO', N'Regla S4: el coordinador tiene varios programas y no envio idPrograma.'),
    ('COO_003', 'BUSINESS_ERROR', 'ALTO',  N'Regla de ambito: idPrograma no esta entre los programas del coordinador.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- CULM-001 B2NM (CONTRACT §2.8.2): permisos de minimo privilegio de las asignaturas por plan y del ambito por relacion.
-- Aditivo e idempotente (patron rol_asistencias_runtime_hu081_hu083.sql); no edita rol_asistencias_runtime.sql.
--   * GRANT EXECUTE a los SP publicos nuevos; DENY EXECUTE a los internos.
--   * DENY INSERT/UPDATE/DELETE en las tablas nuevas y en EstudiantePrograma (se escriben solo por SP, encadenamiento dbo -> dbo).
--   * GRANT SELECT a las TVF nuevas.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

DECLARE @requeridos TABLE (nombre SYSNAME);
INSERT INTO @requeridos VALUES
    (N'usp_asociar_asignatura_plan'), (N'usp_desvincular_asignatura_plan'), (N'usp_consultar_asignaturas_plan_paginado'),
    (N'usp_consultar_asignaturas_asociables_paginado'), (N'usp_consultar_asignaturas_coordinador_paginado'),
    (N'usp_consultar_planes_estudio_programa_paginado'), (N'usp_consultar_grupos_facultad_paginado'), (N'usp_consultar_programas_grupo'),
    (N'usp_internal_asociar_asignatura_plan'), (N'usp_internal_asegurar_estudiante_programa_grupo');
DECLARE @faltante SYSNAME = (SELECT TOP 1 nombre FROM @requeridos WHERE OBJECT_ID(CONCAT(N'dbo.', nombre), N'P') IS NULL);
IF @faltante IS NOT NULL
BEGIN
    DECLARE @msg NVARCHAR(400) = CONCAT(N'CULM001_B2NM_RUNTIME_GRANT: procedimiento requerido ausente: ', @faltante);
    THROW 52930, @msg, 1;
END
GO

GRANT EXECUTE ON [dbo].[usp_asociar_asignatura_plan] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_desvincular_asignatura_plan] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_asignaturas_plan_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_asignaturas_asociables_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_asignaturas_coordinador_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_planes_estudio_programa_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_grupos_facultad_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_programas_grupo] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_internal_asociar_asignatura_plan] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_internal_asegurar_estudiante_programa_grupo] TO [rol_asistencias_runtime];
GO

DENY INSERT, UPDATE, DELETE ON [dbo].[AsignaturaPlanEstudio] TO [rol_asistencias_runtime];
DENY INSERT, UPDATE, DELETE ON [dbo].[CaracterAsignaturaPlan] TO [rol_asistencias_runtime];
DENY INSERT, UPDATE, DELETE ON [dbo].[EstudiantePrograma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.zz_reporte_culm001_b2nm_estudiante_programa', N'U') IS NOT NULL
    DENY INSERT, UPDATE, DELETE ON [dbo].[zz_reporte_culm001_b2nm_estudiante_programa] TO [rol_asistencias_runtime];
GO

GRANT SELECT ON [dbo].[ufn_programas_grupo] TO [rol_asistencias_runtime];
GRANT SELECT ON [dbo].[ufn_programas_coordinador] TO [rol_asistencias_runtime];
GRANT SELECT ON [dbo].[ufn_programas_ambito_ejecutor] TO [rol_asistencias_runtime];
GRANT SELECT ON [dbo].[ufn_estudiantes_grupo_visibles] TO [rol_asistencias_runtime];
GO

DECLARE @v SYSNAME, @sql NVARCHAR(400);
DECLARE vistas CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.views WHERE schema_id = SCHEMA_ID(N'dbo') AND name IN
        (N'uv_caracter_asignatura_plan', N'uv_asignatura_plan_estudio', N'uv_estudiante_grupo_programa', N'uv_resumen_asistencia_estudiante_programa_grupo');
OPEN vistas; FETCH NEXT FROM vistas INTO @v;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = CONCAT(N'GRANT SELECT ON [dbo].', QUOTENAME(@v), N' TO [rol_asistencias_runtime];');
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM vistas INTO @v;
END
CLOSE vistas; DEALLOCATE vistas;
GO

