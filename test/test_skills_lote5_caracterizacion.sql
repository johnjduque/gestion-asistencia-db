USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 5 (plan por lotes 2026-11-25): docentes y grupos.
-- Fija el comportamiento de los internos del lote sin prueba directa antes de refactorizarlos. Los SP publicos del lote
-- siguen cubiertos por sus pruebas de dominio. Todo lo que escribe corre dentro de una transaccion revertida.
--   SKL5_R01_DOCENTE_EXISTE        usp_validar_docente_exista_por_id_interno: exito, DOC_001, CORR_001 y USU_002 (usuario inactivo)
--   SKL5_R02_VINCULO_ACTIVO        usp_validar_docente_vinculo_activo_programa_interno: exito y DOC_009 (solo vinculos inactivos)
--   SKL5_R03_VINCULAR_NUCLEO       usp_vincular_docente_programa_interno: DOC_006 (duplicado) y GEN_004 (vinculo nuevo activo)
--   SKL5_R04_SINCRONIZAR_DOCENTE   usp_sincronizar_docente_interno: DOC_002 (ya es docente), USU (no existe) y GEN_004 (alta)
--   SKL5_R05_CUPO_GRUPO            usp_validar_cupo_disponible_grupo_interno: exito y ERR_CUPO_SUPERADO
--   SKL5_R06_CONSULTA_TITULAR      usp_validar_consulta_grupo_docente_titular_interno: exito, GEN_002, SEC (perfil), PAG_001,
--                                  grupo inexistente y docente no titular
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote5_caracterizacion';

DECLARE @idGrupo UNIQUEIDENTIFIER, @idDocente UNIQUEIDENTIFIER, @uDocente UNIQUEIDENTIFIER, @idAsig UNIQUEIDENTIFIER;
SELECT TOP 1 @idGrupo = g.id, @idDocente = g.idDocente, @uDocente = di.idUsuario, @idAsig = g.idAsignatura
FROM dbo.uv_grupo g
INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
WHERE di.estaActivoUsuario = 1 AND g.cuposDisponibles > 0
  AND EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
              INNER JOIN dbo.uv_docente_programa dp ON dp.idPrograma = v.idPrograma AND dp.idDocente = g.idDocente AND dp.estaActivoVinculacion = 1
              WHERE v.idAsignatura = g.idAsignatura AND v.estaActivoVinculo = 1)
ORDER BY g.id;
DECLARE @idOtroDocente UNIQUEIDENTIFIER, @uOtroDocente UNIQUEIDENTIFIER;
SELECT TOP 1 @idOtroDocente = di.id, @uOtroDocente = di.idUsuario
FROM dbo.uv_docente_identidad di
WHERE di.id <> @idDocente AND di.estaActivoUsuario = 1
  AND EXISTS (SELECT 1 FROM dbo.uv_usuario_perfil up WHERE up.idUsuario = di.idUsuario AND up.codigoPerfil = 'DO')
ORDER BY di.id;
DECLARE @idProgramaVinculado UNIQUEIDENTIFIER = (SELECT TOP 1 dp.idPrograma FROM dbo.uv_docente_programa dp WHERE dp.idDocente = @idDocente ORDER BY dp.idPrograma);
DECLARE @uNoDocente UNIQUEIDENTIFIER = (SELECT TOP 1 u.id FROM dbo.uv_usuario u
    WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_docente_identidad d WHERE d.idUsuario = u.id) ORDER BY u.id);
IF @idGrupo IS NULL OR @idOtroDocente IS NULL OR @idProgramaVinculado IS NULL OR @uNoDocente IS NULL
    THROW 55300, 'TEST FAILED: SKL5 faltan fixtures del seed (grupo con docente vinculado, otro docente y usuario sin rol docente).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @trancount INT = @@TRANCOUNT;

    -- ================================================================= R01
    EXEC dbo.usp_validar_docente_exista_por_id_interno @idDocente = @idDocente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55310, 'TEST FAILED: SKL5_R01_DOCENTE_EXISTE (exito)', 1;
    EXEC dbo.usp_validar_docente_exista_por_id_interno @idDocente = '5C5A0000-0000-0000-0000-0000000000E1', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=DOC[_]001|%' THROW 55311, 'TEST FAILED: SKL5_R01_DOCENTE_EXISTE (DOC_001)', 1;
    EXEC dbo.usp_validar_docente_exista_por_id_interno @idDocente = @idDocente, @idCorrelacion = NULL,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=CORR[_]001|%' THROW 55312, 'TEST FAILED: SKL5_R01_DOCENTE_EXISTE (CORR_001)', 1;
    UPDATE dbo.Usuario SET estado = 0 WHERE id = @uOtroDocente;
    EXEC dbo.usp_validar_docente_exista_por_id_interno @idDocente = @idOtroDocente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=USU[_]002|%' THROW 55313, 'TEST FAILED: SKL5_R01_DOCENTE_EXISTE (USU_002)', 1;
    UPDATE dbo.Usuario SET estado = 1 WHERE id = @uOtroDocente;
    PRINT 'TEST_PASS:SKL5_R01_DOCENTE_EXISTE';

    -- ================================================================= R02
    EXEC dbo.usp_validar_docente_vinculo_activo_programa_interno @idDocente = @idDocente, @idAsignatura = @idAsig, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55320, 'TEST FAILED: SKL5_R02_VINCULO_ACTIVO (exito)', 1;
    UPDATE dbo.DocentePrograma SET estado = 0 WHERE docente = @idDocente;
    EXEC dbo.usp_validar_docente_vinculo_activo_programa_interno @idDocente = @idDocente, @idAsignatura = @idAsig, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=DOC[_]009|%' OR @mt NOT LIKE N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr)
        THROW 55321, 'TEST FAILED: SKL5_R02_VINCULO_ACTIVO (DOC_009)', 1;
    UPDATE dbo.DocentePrograma SET estado = 1 WHERE docente = @idDocente;
    PRINT 'TEST_PASS:SKL5_R02_VINCULO_ACTIVO';

    -- ================================================================= R03
    EXEC dbo.usp_vincular_docente_programa_interno @idDocente = @idDocente, @idPrograma = @idProgramaVinculado, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=DOC[_]006|%' THROW 55330, 'TEST FAILED: SKL5_R03_VINCULAR_NUCLEO (DOC_006)', 1;
    DELETE FROM dbo.DocentePrograma WHERE docente = @idDocente AND programa = @idProgramaVinculado;   -- se revierte al final
    EXEC dbo.usp_vincular_docente_programa_interno @idDocente = @idDocente, @idPrograma = @idProgramaVinculado, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]004|%' OR @@TRANCOUNT <> @trancount
       OR NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @idDocente AND programa = @idProgramaVinculado AND estado = 1)
        THROW 55331, 'TEST FAILED: SKL5_R03_VINCULAR_NUCLEO (GEN_004)', 1;
    PRINT 'TEST_PASS:SKL5_R03_VINCULAR_NUCLEO';

    -- ================================================================= R04
    EXEC dbo.usp_sincronizar_docente_interno @idUsuario = @uDocente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=DOC[_]002|%' THROW 55340, 'TEST FAILED: SKL5_R04_SINCRONIZAR_DOCENTE (DOC_002)', 1;
    EXEC dbo.usp_sincronizar_docente_interno @idUsuario = '5C5A0000-0000-0000-0000-0000000000E2', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=%' THROW 55341, 'TEST FAILED: SKL5_R04_SINCRONIZAR_DOCENTE (usuario inexistente)', 1;
    EXEC dbo.usp_sincronizar_docente_interno @idUsuario = @uNoDocente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=GEN[_]004|%' OR NOT EXISTS (SELECT 1 FROM dbo.Docente WHERE usuario = @uNoDocente)
        THROW 55342, 'TEST FAILED: SKL5_R04_SINCRONIZAR_DOCENTE (GEN_004)', 1;
    PRINT 'TEST_PASS:SKL5_R04_SINCRONIZAR_DOCENTE';

    -- ================================================================= R05
    EXEC dbo.usp_validar_cupo_disponible_grupo_interno @idGrupo = @idGrupo, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 55350, 'TEST FAILED: SKL5_R05_CUPO_GRUPO (exito)', 1;
    UPDATE dbo.Grupo SET cantidadEstudiantes = (SELECT estudiantesActivos FROM dbo.uv_grupo WHERE id = @idGrupo) WHERE id = @idGrupo;
    EXEC dbo.usp_validar_cupo_disponible_grupo_interno @idGrupo = @idGrupo, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=ERR[_]CUPO[_]SUPERADO|%' THROW 55351, 'TEST FAILED: SKL5_R05_CUPO_GRUPO (cupo superado)', 1;
    PRINT 'TEST_PASS:SKL5_R05_CUPO_GRUPO';

    -- ================================================================= R06
    EXEC dbo.usp_validar_consulta_grupo_docente_titular_interno @idUsuarioEjecutor = @uDocente, @idCorrelacion = @corr, @idGrupo = @idGrupo,
         @validarPaginacion = 1, @numeroPagina = 1, @tamanoPagina = 10,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 55360, 'TEST FAILED: SKL5_R06_CONSULTA_TITULAR (exito)', 1;
    EXEC dbo.usp_validar_consulta_grupo_docente_titular_interno @idUsuarioEjecutor = NULL, @idCorrelacion = @corr, @idGrupo = @idGrupo,
         @validarPaginacion = 0, @numeroPagina = NULL, @tamanoPagina = NULL,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]002|%' THROW 55361, 'TEST FAILED: SKL5_R06_CONSULTA_TITULAR (GEN_002)', 1;
    EXEC dbo.usp_validar_consulta_grupo_docente_titular_interno @idUsuarioEjecutor = @uNoDocente, @idCorrelacion = @corr, @idGrupo = @idGrupo,
         @validarPaginacion = 0, @numeroPagina = NULL, @tamanoPagina = NULL,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=SEC%' THROW 55362, 'TEST FAILED: SKL5_R06_CONSULTA_TITULAR (perfil)', 1;
    EXEC dbo.usp_validar_consulta_grupo_docente_titular_interno @idUsuarioEjecutor = @uDocente, @idCorrelacion = @corr, @idGrupo = @idGrupo,
         @validarPaginacion = 1, @numeroPagina = 0, @tamanoPagina = 10,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=PAG[_]001|%' THROW 55363, 'TEST FAILED: SKL5_R06_CONSULTA_TITULAR (PAG_001)', 1;
    EXEC dbo.usp_validar_consulta_grupo_docente_titular_interno @idUsuarioEjecutor = @uDocente, @idCorrelacion = @corr,
         @idGrupo = '5C5A0000-0000-0000-0000-0000000000E3', @validarPaginacion = 0, @numeroPagina = NULL, @tamanoPagina = NULL,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=%' THROW 55364, 'TEST FAILED: SKL5_R06_CONSULTA_TITULAR (grupo inexistente)', 1;
    EXEC dbo.usp_validar_consulta_grupo_docente_titular_interno @idUsuarioEjecutor = @uOtroDocente, @idCorrelacion = @corr, @idGrupo = @idGrupo,
         @validarPaginacion = 0, @numeroPagina = NULL, @tamanoPagina = NULL,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=%' OR @@TRANCOUNT <> @trancount THROW 55365, 'TEST FAILED: SKL5_R06_CONSULTA_TITULAR (no titular)', 1;
    PRINT 'TEST_PASS:SKL5_R06_CONSULTA_TITULAR';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
