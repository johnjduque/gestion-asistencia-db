USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- HU091 (T-MIG-01..03): estructura, seed, backfill (R2) y retiro del SP autonomo (D7).
-- MEJORAS-SERGIO-2026-11-18 (migracion 56): el tipo de vinculacion se retiro (tabla, vista, columna, FK y DOC_004).
PRINT 'TEST START: test_migracion_docente_programa';

IF OBJECT_ID('dbo.TipoVinculacion', 'U') IS NOT NULL OR OBJECT_ID('dbo.uv_tipo_vinculacion', 'V') IS NOT NULL
   OR COL_LENGTH('dbo.DocentePrograma', 'tipoVinculacion') IS NOT NULL
    THROW 52400, 'T-MIG FAILED: el tipo de vinculacion debio retirarse (migracion 56).', 1;
IF OBJECT_ID('dbo.DocentePrograma', 'U') IS NULL THROW 52401, 'T-MIG FAILED: falta la tabla DocentePrograma.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_DocentePrograma_docente_programa')
    THROW 52402, 'T-MIG FAILED: falta UNIQUE (docente, programa).', 1;
IF (SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dbo.DocentePrograma')) < 2
    THROW 52403, 'T-MIG FAILED: DocentePrograma debe tener FK a Docente y Programa.', 1;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_DocentePrograma_TipoVinculacion')
    THROW 52404, 'T-MIG FAILED: FK_DocentePrograma_TipoVinculacion debio retirarse.', 1;
IF OBJECT_ID('dbo.uv_docente_programa', 'V') IS NULL OR OBJECT_ID('dbo.uv_auth_docente_programa', 'V') IS NULL
    THROW 52405, 'T-MIG FAILED: faltan las vistas uv_docente_programa / uv_auth_docente_programa.', 1;
PRINT 'TEST_PASS:T-MIG-01';

-- T-MIG-02 (R2): todo par (docente, programa) que hoy sale de uv_docente tiene un vinculo.
IF EXISTS (
    SELECT 1 FROM (SELECT DISTINCT id AS idDocente, idPrograma FROM dbo.uv_docente) par
    WHERE NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma dp WHERE dp.docente = par.idDocente AND dp.programa = par.idPrograma))
    THROW 52410, 'T-MIG-02 FAILED: hay docentes con grupos sin vinculo (backfill incompleto).', 1;
IF EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE fechaVinculacionUtc IS NULL)
    THROW 52411, 'T-MIG-02 FAILED: vinculos sin fecha.', 1;
PRINT 'TEST_PASS:T-MIG-02';

-- T-MIG-03 (D7): SP autonomo sin RBAC retirado
IF OBJECT_ID('dbo.usp_registrar_docente_en_grupo_autonomo', 'P') IS NOT NULL
    THROW 52420, 'T-MIG-03 FAILED: usp_registrar_docente_en_grupo_autonomo debio retirarse.', 1;
PRINT 'TEST_PASS:T-MIG-03';

-- Catalogo de mensajes DOC_* / IAM_001
IF EXISTS (
    SELECT 1 FROM (VALUES ('DOC_002'),('DOC_003'),('DOC_005'),('DOC_006'),('DOC_007'),('DOC_008'),('DOC_009'),('IAM_001')) x(codigo)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario m WHERE m.codigo = x.codigo)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = x.codigo))
    THROW 52430, 'T-MIG FAILED: faltan mensajes de catalogo DOC_002..DOC_009 / IAM_001 (usuario o tecnico).', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'DOC_004') OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'DOC_004')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ERR_TIPO_VINCULACION_INVALIDO')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'DOCENTE' AND clave = 'TIPO_VINCULACION_DEFECTO')
    THROW 52431, 'T-MIG FAILED: DOC_004, ERR_TIPO_VINCULACION_INVALIDO y DOCENTE/TIPO_VINCULACION_DEFECTO debieron retirarse (migracion 56).', 1;
PRINT 'TEST_PASS:MENSAJES_DOC';
PRINT 'TEST_PASS:TEST_MIGRACION_DOCENTE_PROGRAMA';
GO
