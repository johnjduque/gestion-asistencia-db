USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 9 (plan por lotes 2026-11-25): periodos, recesos y festivos.
-- Fija el comportamiento de los internos del lote que no tenian prueba directa, antes de refactorizarlos. Los SP publicos del lote
-- siguen cubiertos por sus pruebas de dominio. Todo lo que escribe corre dentro de una transaccion revertida.
--   SKL9_R01_INSTITUCION_GESTOR  usp_resolver_institucion_gestor_periodo_interno: administrador (institucion), no administrador
--                                (SEC_001), ejecutor nulo (rechazo RBAC) e institucion inactiva (PER_005)
--   SKL9_R02_FECHAS_PERIODO      usp_validar_fechas_periodo_academico_interno: exito, grupo inexistente (GEN_001), correlacion
--                                nula (CORR_001) y fechaInicio >= fechaFin (VAL_002)
--   SKL9_R03_PERIODO_ABIERTO     usp_validar_periodo_abierto_sesion_interno: abierto no toca las salidas; cerrado PER_008
--   SKL9_R04_SOLAPE_PERIODO      usp_validar_solape_periodo_academico_interno: solape PER_012 con el nombre, excluido y sin solape
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote9_caracterizacion';

DECLARE @adm UNIQUEIDENTIFIER, @instAdm UNIQUEIDENTIFIER;
SELECT TOP 1 @adm = a.usuario, @instAdm = a.institucion FROM dbo.Administrador a INNER JOIN dbo.Institucion i ON i.id = a.institucion AND i.estado = 1 ORDER BY a.usuario;
DECLARE @doc UNIQUEIDENTIFIER = (SELECT TOP 1 d.usuario FROM dbo.Docente d
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Administrador a WHERE a.usuario = d.usuario) ORDER BY d.usuario);
DECLARE @s UNIQUEIDENTIFIER, @g UNIQUEIDENTIFIER, @pa UNIQUEIDENTIFIER;
SELECT TOP 1 @s = s.id, @g = s.grupo, @pa = g.periodoAcademico
FROM dbo.Sesion s INNER JOIN dbo.Grupo g ON g.id = s.grupo INNER JOIN dbo.PeriodoAcademico p ON p.id = g.periodoAcademico
WHERE p.fechaCierreUtc IS NULL ORDER BY s.id;
IF @adm IS NULL OR @doc IS NULL OR @s IS NULL
    THROW 55900, 'TEST FAILED: SKL9 faltan fixtures del seed (administrador, docente y sesion de un periodo abierto).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @inst UNIQUEIDENTIFIER, @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @inexistente UNIQUEIDENTIFIER = '5C6A0000-0000-0000-0000-0000000000E9';
    DECLARE @i2 UNIQUEIDENTIFIER, @fi DATE, @ff DATE, @nom NVARCHAR(50);

    -- ================================================================= R01
    EXEC dbo.usp_resolver_institucion_gestor_periodo_interno @idUsuario = @adm, @idCorrelacion = @corr, @idInstitucion = @inst OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @inst <> @instAdm OR @mt <> N'' THROW 55910, 'TEST FAILED: SKL9_R01_INSTITUCION_GESTOR (administrador)', 1;
    EXEC dbo.usp_resolver_institucion_gestor_periodo_interno @idUsuario = @doc, @idCorrelacion = @corr, @idInstitucion = @inst OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @inst IS NOT NULL OR @mt NOT LIKE N'DBCODE=SEC[_]001|%' THROW 55911, 'TEST FAILED: SKL9_R01_INSTITUCION_GESTOR (SEC_001)', 1;
    EXEC dbo.usp_resolver_institucion_gestor_periodo_interno @idUsuario = NULL, @idCorrelacion = @corr, @idInstitucion = @inst OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @inst IS NOT NULL OR @mt NOT LIKE N'DBCODE=%' THROW 55912, 'TEST FAILED: SKL9_R01_INSTITUCION_GESTOR (ejecutor nulo)', 1;
    UPDATE dbo.Institucion SET estado = 0 WHERE id = @instAdm;
    EXEC dbo.usp_resolver_institucion_gestor_periodo_interno @idUsuario = @adm, @idCorrelacion = @corr, @idInstitucion = @inst OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @inst IS NOT NULL OR @mt NOT LIKE N'DBCODE=PER[_]005|%' OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
        THROW 55913, 'TEST FAILED: SKL9_R01_INSTITUCION_GESTOR (PER_005)', 1;
    UPDATE dbo.Institucion SET estado = 1 WHERE id = @instAdm;
    PRINT 'TEST_PASS:SKL9_R01_INSTITUCION_GESTOR';

    -- ================================================================= R02
    EXEC dbo.usp_validar_fechas_periodo_academico_interno @idGrupo = @g, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55920, 'TEST FAILED: SKL9_R02_FECHAS_PERIODO (exito)', 1;
    EXEC dbo.usp_validar_fechas_periodo_academico_interno @idGrupo = @inexistente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]001|%' OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
        THROW 55921, 'TEST FAILED: SKL9_R02_FECHAS_PERIODO (GEN_001)', 1;
    EXEC dbo.usp_validar_fechas_periodo_academico_interno @idGrupo = @g, @idCorrelacion = NULL,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=CORR[_]001|%' THROW 55922, 'TEST FAILED: SKL9_R02_FECHAS_PERIODO (CORR_001)', 1;
    UPDATE dbo.PeriodoAcademico SET fechaFin = fechaInicio WHERE id = @pa;
    EXEC dbo.usp_validar_fechas_periodo_academico_interno @idGrupo = @g, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VAL[_]002|%' THROW 55923, 'TEST FAILED: SKL9_R02_FECHAS_PERIODO (VAL_002)', 1;
    PRINT 'TEST_PASS:SKL9_R02_FECHAS_PERIODO';

    -- ================================================================= R03
    SELECT @mu = N'u', @mt = N't', @ok = 1;
    EXEC dbo.usp_validar_periodo_abierto_sesion_interno @idSesion = @s, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mu <> N'u' OR @mt <> N't' THROW 55930, 'TEST FAILED: SKL9_R03_PERIODO_ABIERTO (abierto no toca las salidas)', 1;
    SELECT @mu = N'u', @mt = N't', @ok = 1;
    EXEC dbo.usp_validar_periodo_abierto_sesion_interno @idSesion = @inexistente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mu <> N'u' OR @mt <> N't' THROW 55931, 'TEST FAILED: SKL9_R03_PERIODO_ABIERTO (sesion inexistente pasa)', 1;
    UPDATE dbo.PeriodoAcademico SET fechaCierreUtc = '2026-01-02T03:04:05' WHERE id = @pa;
    EXEC dbo.usp_validar_periodo_abierto_sesion_interno @idSesion = @s, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=PER[_]008|%2026-01-02T03:04:05%'
       OR @mt NOT LIKE N'% Periodo: ' + CONVERT(NVARCHAR(36), @pa) + N' Sesion: ' + CONVERT(NVARCHAR(36), @s) + N' Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
        THROW 55932, 'TEST FAILED: SKL9_R03_PERIODO_ABIERTO (PER_008)', 1;
    PRINT 'TEST_PASS:SKL9_R03_PERIODO_ABIERTO';

    -- ================================================================= R04
    SELECT @i2 = institucion, @fi = fechaInicio, @ff = fechaFin, @nom = nombre FROM dbo.PeriodoAcademico WHERE id = @pa;
    EXEC dbo.usp_validar_solape_periodo_academico_interno @idInstitucion = @i2, @fechaInicio = @fi, @fechaFin = @fi, @idPeriodoExcluir = NULL,
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=PER[_]012|%' OR CHARINDEX(@nom, @mt) = 0 OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
        THROW 55940, 'TEST FAILED: SKL9_R04_SOLAPE_PERIODO (PER_012)', 1;
    EXEC dbo.usp_validar_solape_periodo_academico_interno @idInstitucion = @i2, @fechaInicio = @fi, @fechaFin = @fi, @idPeriodoExcluir = @pa,
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55941, 'TEST FAILED: SKL9_R04_SOLAPE_PERIODO (excluido)', 1;
    EXEC dbo.usp_validar_solape_periodo_academico_interno @idInstitucion = @i2, @fechaInicio = '1990-01-01', @fechaFin = '1990-02-01', @idPeriodoExcluir = NULL,
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55942, 'TEST FAILED: SKL9_R04_SOLAPE_PERIODO (sin solape)', 1;
    PRINT 'TEST_PASS:SKL9_R04_SOLAPE_PERIODO';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
PRINT 'TEST END: test_skills_lote9_caracterizacion';
GO
