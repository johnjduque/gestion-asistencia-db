USE [gestionasistenciadb];
GO
-- CULM-001 B2NM (B2NM-05, 06 parcial, 18 parcial, 19, 20 parcial): ambito por relacion en un grupo mixto (OPT en los programas A y B).
-- CA ve EA y no EB; CB al reves; el decano ve EA y EB; T (titular) y AD (administrador) ven EA, EB y E0; CA y el decano no ven E0.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_culm001_b2nm_ambito_grupo_mixto';
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();

    -- B2NM-01/03: G tiene 2 programas en uv_grupo_programa y 1 fila en uv_grupo / 3 matriculas en uv_estudiante_grupo
    IF (SELECT COUNT(*) FROM dbo.uv_grupo_programa WHERE idGrupo = @grupoG) <> 2 THROW 53851, 'TEST FAILED: B2NM-01 uv_grupo_programa debe tener 2 filas para G.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_grupo WHERE id = @grupoG) <> 1 THROW 53852, 'TEST FAILED: B2NM-03 uv_grupo debe tener 1 fila para G.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo WHERE idGrupo = @grupoG) <> 3 THROW 53853, 'TEST FAILED: B2NM-03 uv_estudiante_grupo debe tener 3 matriculas en G.', 1;

    -- B2NM-05: ufn_estudiantes_grupo_visibles por ejecutor
    IF (SELECT COUNT(*) FROM dbo.ufn_estudiantes_grupo_visibles(@grupoG, @uCA)) <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.ufn_estudiantes_grupo_visibles(@grupoG, @uCA) WHERE idEstudiante = @eA)
        THROW 53854, 'TEST FAILED: B2NM-05 CA debe ver solo a EA.', 1;
    IF (SELECT COUNT(*) FROM dbo.ufn_estudiantes_grupo_visibles(@grupoG, @uCB)) <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.ufn_estudiantes_grupo_visibles(@grupoG, @uCB) WHERE idEstudiante = @eB)
        THROW 53855, 'TEST FAILED: B2NM-05 CB debe ver solo a EB.', 1;
    IF (SELECT COUNT(*) FROM dbo.ufn_estudiantes_grupo_visibles(@grupoG, @uDec)) <> 2 OR EXISTS (SELECT 1 FROM dbo.ufn_estudiantes_grupo_visibles(@grupoG, @uDec) WHERE idEstudiante = @e0)
        THROW 53856, 'TEST FAILED: B2NM-05 el decano debe ver a EA y EB y no a E0.', 1;
    IF (SELECT COUNT(*) FROM dbo.ufn_estudiantes_grupo_visibles(@grupoG, @uT)) <> 3 OR (SELECT COUNT(*) FROM dbo.ufn_estudiantes_grupo_visibles(@grupoG, @uAdm)) <> 3
        THROW 53857, 'TEST FAILED: B2NM-05/19 el titular y el administrador deben ver a EA, EB y E0.', 1;

    -- B2NM-05: el SP de A.2 de estudiantes del grupo
    DECLARE @r TABLE (id UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, documento NVARCHAR(20), nombreCompleto NVARCHAR(400), correo NVARCHAR(100), codigoEstado NVARCHAR(10), nombreEstado NVARCHAR(100), totalRegistros INT);
    DELETE FROM @r; INSERT INTO @r EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @grupoG, @idUsuarioEjecutor = @uCA, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM @r) <> 1 OR NOT EXISTS (SELECT 1 FROM @r WHERE idEstudiante = @eA) THROW 53858, 'TEST FAILED: B2NM-05 usp_consultar_estudiantes_grupo_ambito_paginado para CA.', 1;
    DELETE FROM @r; INSERT INTO @r EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @grupoG, @idUsuarioEjecutor = @uDec, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM @r) <> 2 THROW 53859, 'TEST FAILED: B2NM-05 usp_consultar_estudiantes_grupo_ambito_paginado para el decano.', 1;
    DELETE FROM @r; INSERT INTO @r EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @grupoG, @idUsuarioEjecutor = @uT, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM @r) <> 3 THROW 53860, 'TEST FAILED: B2NM-19 el titular debe ver a E0 (R10).', 1;

    -- B2NM-20: usp_consultar_programas_grupo para T y CA; un usuario sin ambito -> SEC_002
    DECLARE @p TABLE (idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100), idPlanEstudio UNIQUEIDENTIFIER, inpPlanEstudio INT);
    DELETE FROM @p; INSERT INTO @p EXEC dbo.usp_consultar_programas_grupo @idUsuarioEjecutor = @uT, @idCorrelacion = @c, @idGrupo = @grupoG;
    IF (SELECT COUNT(*) FROM @p) <> 2 THROW 53861, 'TEST FAILED: B2NM-20 usp_consultar_programas_grupo debe devolver 2 programas.', 1;
    DELETE FROM @p; INSERT INTO @p EXEC dbo.usp_consultar_programas_grupo @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @idGrupo = @grupoG;
    IF (SELECT COUNT(*) FROM @p) <> 2 THROW 53862, 'TEST FAILED: B2NM-20 CA debe poder consultar los programas del grupo.', 1;
    DECLARE @sinAmbito BIT = 0;
    BEGIN TRY
        DELETE FROM @p; INSERT INTO @p EXEC dbo.usp_consultar_programas_grupo @idUsuarioEjecutor = @uEA, @idCorrelacion = @c, @idGrupo = @grupoG;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE N'%SEC_002%' SET @sinAmbito = 1;
    END CATCH
    IF @sinAmbito = 0 THROW 53863, 'TEST FAILED: B2NM-20 un usuario sin ambito debe recibir SEC_002.', 1;

    -- B2NM-06: directorio con @idPrograma = B pedido por CA -> COO_003
    DECLARE @coo003 BIT = 0;
    BEGIN TRY
        EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uCA, @idCorrelacion = @c, @idPrograma = @progB;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE N'%COO_003%' SET @coo003 = 1;
    END CATCH
    IF @coo003 = 0 THROW 53864, 'TEST FAILED: B2NM-06 el directorio con un programa ajeno debe dar COO_003.', 1;

    -- B2NM-18 (O-N7): CA no gestiona un grupo compartido con un programa que no coordina; el titular si
    DECLARE @esCoord BIT, @docTitular UNIQUEIDENTIFIER, @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT;
    EXEC dbo.usp_validar_gestion_grupo_coordinador_o_titular_interno @idGrupo = @grupoG, @idUsuarioEjecutor = @uCA, @idCorrelacion = @c,
        @ejecutorEsCoordinador = @esCoord OUTPUT, @idDocenteTitular = @docTitular OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 1 OR @mt NOT LIKE N'%SEC_002%' THROW 53865, 'TEST FAILED: B2NM-18 CA no debe gestionar el grupo compartido (SEC_002).', 1;
    EXEC dbo.usp_validar_gestion_grupo_coordinador_o_titular_interno @idGrupo = @grupoG, @idUsuarioEjecutor = @uT, @idCorrelacion = @c,
        @ejecutorEsCoordinador = @esCoord OUTPUT, @idDocenteTitular = @docTitular OUTPUT, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok = 0 THROW 53866, 'TEST FAILED: B2NM-18 el titular debe poder gestionar el grupo.', 1;

    PRINT 'TEST_PASS:CULM001_B2NM_AMBITO_GRUPO_MIXTO';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 53899, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
