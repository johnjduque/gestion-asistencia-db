USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- Migracion 65: administracion (ADMINISTRADOR) de categorias de justificacion y motivos de cancelacion de sesion.
--   C1 crear categoria (activa, visible al estudiante, acepta tildes y la enie); C2 codigo y nombre repetidos (CTG_006);
--   C3 texto invalido (CTG_001 nombre con <, nombre largo, CTG_002 codigo en minuscula, CTG_004 descripcion con >);
--   C4 no administrador (SEC_001) y correlacion nula (CORR_001); C5 actualizar y repetido/inexistente (CTG_006/CTG_005);
--   C6 desactivar conserva la fila y los reclamos y la oculta de la oferta; reactivar; idempotencia; C7 la ultima activa no se
--   desactiva (CTG_003); M1..M5 lo mismo para los motivos de cancelacion (orden automatico incluido).
PRINT 'TEST START: test_admin_catalogos_justificacion_cancelacion';

DECLARE @idAdmin UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoAdministrador = 1 ORDER BY idUsuario);
DECLARE @idNoAdmin UNIQUEIDENTIFIER = (
    SELECT TOP 1 up.idUsuario FROM dbo.uv_usuario_perfil up
    WHERE up.estado = 1 AND up.codigoPerfil <> 'AD'
      AND NOT EXISTS (SELECT 1 FROM dbo.uv_usuario_perfil a WHERE a.idUsuario = up.idUsuario AND a.codigoPerfil = 'AD' AND a.estado = 1)
    ORDER BY up.idUsuario);
IF @idAdmin IS NULL THROW 55101, 'TEST FAILED: falta un administrador activo.', 1;
IF @idNoAdmin IS NULL THROW 55102, 'TEST FAILED: falta un usuario no administrador.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @c UNIQUEIDENTIFIER, @cat1 UNIQUEIDENTIFIER = NEWID(), @cat2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @mot1 UNIQUEIDENTIFIER = NEWID(), @mot2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreTildes NVARCHAR(50) = CONCAT(N'Prueba ', NCHAR(209), N'and', NCHAR(250), N' M', NCHAR(233), N'dica (QA) 1/2');
    DECLARE @conteoCat INT = (SELECT COUNT(*) FROM dbo.CategoriaJustificacion);
    DECLARE @conteoMot INT = (SELECT COUNT(*) FROM dbo.MotivoCancelacionSesion);

    -- C1
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_categoria_justificacion @id = @cat1, @codigo = N'QA1', @nombre = @nombreTildes,
        @descripcion = N'Descripcion de prueba', @requiereSoporte = 1, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_007|%')
        THROW 55103, 'TEST FAILED C1: no creo la categoria.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_categoria_justificacion_admin WHERE id = @cat1 AND codigo = N'QA1' AND nombre = @nombreTildes AND requiereSoporte = 1 AND estaActivo = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_categoria_justificacion WHERE id = @cat1)
        THROW 55104, 'TEST FAILED C1: la categoria debe nacer activa y ofrecerse.', 1;
    DELETE FROM #r;

    -- C2
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_categoria_justificacion @id = @cat2, @codigo = N'QA1', @nombre = N'Nombre distinto', @requiereSoporte = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_006|%')
        THROW 55105, 'TEST FAILED C2: codigo repetido debe dar CTG_006.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_crear_categoria_justificacion @id = @cat2, @codigo = N'QA2', @nombre = @nombreTildes, @requiereSoporte = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_006|%')
        THROW 55106, 'TEST FAILED C2: nombre repetido debe dar CTG_006.', 1;
    DELETE FROM #r;

    -- C3
    INSERT INTO #r EXEC dbo.usp_crear_categoria_justificacion @id = @cat2, @codigo = N'QA2', @nombre = N'Con <etiqueta>', @requiereSoporte = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_001|%') THROW 55107, 'TEST FAILED C3: nombre con < debe dar CTG_001.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_crear_categoria_justificacion @id = @cat2, @codigo = N'QA2', @nombre = N'12345678901234567890123456789012345678901234567890X', @requiereSoporte = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_001|%') THROW 55108, 'TEST FAILED C3: nombre de 51 caracteres debe dar CTG_001.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_crear_categoria_justificacion @id = @cat2, @codigo = N'qa2', @nombre = N'Nombre ok', @requiereSoporte = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_002|%') THROW 55109, 'TEST FAILED C3: codigo en minuscula debe dar CTG_002.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_crear_categoria_justificacion @id = @cat2, @codigo = N'QA2', @nombre = N'Nombre ok', @descripcion = N'a > b', @requiereSoporte = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_004|%') THROW 55110, 'TEST FAILED C3: descripcion con > debe dar CTG_004.', 1;
    DELETE FROM #r;
    IF EXISTS (SELECT 1 FROM dbo.CategoriaJustificacion WHERE codigo IN (N'QA2'))
        THROW 55111, 'TEST FAILED C3: un rechazo dejo una fila.', 1;

    -- C4
    INSERT INTO #r EXEC dbo.usp_crear_categoria_justificacion @id = @cat2, @codigo = N'QA2', @nombre = N'Nombre ok', @requiereSoporte = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idNoAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%') OR EXISTS (SELECT 1 FROM dbo.CategoriaJustificacion WHERE codigo = N'QA2')
        THROW 55112, 'TEST FAILED C4: un no administrador debe recibir SEC_001 sin crear.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_categoria_justificacion @id = @cat1, @estaActiva = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idNoAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%') OR NOT EXISTS (SELECT 1 FROM dbo.CategoriaJustificacion WHERE id = @cat1 AND estaActivo = 1)
        THROW 55113, 'TEST FAILED C4: un no administrador no cambia el estado (SEC_001).', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_crear_categoria_justificacion @id = @cat2, @codigo = N'QA2', @nombre = N'Nombre ok', @requiereSoporte = 0, @idCorrelacion = NULL, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%') THROW 55114, 'TEST FAILED C4: correlacion nula debe dar CORR_001.', 1;
    DELETE FROM #r;

    -- C5
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_categoria_justificacion @id = @cat1, @nombre = N'Prueba renombrada', @descripcion = NULL, @requiereSoporte = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_categoria_justificacion_admin WHERE id = @cat1 AND codigo = N'QA1' AND nombre = N'Prueba renombrada' AND descripcion IS NULL AND requiereSoporte = 0)
        THROW 55115, 'TEST FAILED C5: la actualizacion no se persistio (el codigo no cambia).', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_categoria_justificacion @id = @cat1, @nombre = N'Otro', @requiereSoporte = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_006|%') THROW 55116, 'TEST FAILED C5: renombrar a un nombre existente debe dar CTG_006.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_categoria_justificacion @id = @cat2, @nombre = N'Nuevo', @requiereSoporte = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_005|%') THROW 55117, 'TEST FAILED C5: id inexistente debe dar CTG_005.', 1;
    DELETE FROM #r;

    -- C6: desactivar conserva la fila y el historial
    DECLARE @idMed UNIQUEIDENTIFIER = (SELECT id FROM dbo.CategoriaJustificacion WHERE codigo = N'MED');
    DECLARE @reclamosMed INT = (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia WHERE categoriaJustificacion = @idMed);
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_categoria_justificacion @id = @idMed, @estaActiva = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_008|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.CategoriaJustificacion WHERE id = @idMed AND estaActivo = 0)
       OR EXISTS (SELECT 1 FROM dbo.uv_categoria_justificacion WHERE id = @idMed)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_categoria_justificacion_admin WHERE id = @idMed AND estaActivo = 0)
       OR (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia WHERE categoriaJustificacion = @idMed) <> @reclamosMed
       OR (SELECT COUNT(*) FROM dbo.CategoriaJustificacion) <> @conteoCat + 1
        THROW 55118, 'TEST FAILED C6: desactivar debe conservar la fila y los reclamos y ocultarla de la oferta.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_categoria_justificacion @id = @idMed, @estaActiva = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) THROW 55119, 'TEST FAILED C6: repetir el estado debe ser idempotente.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_categoria_justificacion @id = @idMed, @estaActiva = 1, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_categoria_justificacion WHERE id = @idMed) THROW 55120, 'TEST FAILED C6: reactivar debe ofrecerla de nuevo.', 1;
    DELETE FROM #r;

    -- C7: la ultima categoria activa no se desactiva
    UPDATE dbo.CategoriaJustificacion SET estaActivo = 0 WHERE id <> @cat1;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_categoria_justificacion @id = @cat1, @estaActiva = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_003|%') OR NOT EXISTS (SELECT 1 FROM dbo.CategoriaJustificacion WHERE id = @cat1 AND estaActivo = 1)
        THROW 55121, 'TEST FAILED C7: la ultima categoria activa no puede desactivarse (CTG_003).', 1;
    DELETE FROM #r;
    UPDATE dbo.CategoriaJustificacion SET estaActivo = 1;

    -- M1: crear con orden automatico
    DECLARE @maxOrden INT = (SELECT MAX(orden) FROM dbo.MotivoCancelacionSesion);
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_motivo_cancelacion_sesion @id = @mot1, @codigo = N'QA_MOTIVO_1', @nombre = N'Motivo de prueba', @orden = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_007|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_motivo_cancelacion_sesion WHERE id = @mot1 AND codigo = N'QA_MOTIVO_1' AND orden = @maxOrden + 1 AND estaActivo = 1)
        THROW 55122, 'TEST FAILED M1: el motivo debe nacer activo y al final del orden.', 1;
    DELETE FROM #r;

    -- M2: repetido e invalido
    INSERT INTO #r EXEC dbo.usp_crear_motivo_cancelacion_sesion @id = @mot2, @codigo = N'QA_MOTIVO_1', @nombre = N'Otro motivo QA', @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_006|%') THROW 55123, 'TEST FAILED M2: codigo repetido debe dar CTG_006.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_crear_motivo_cancelacion_sesion @id = @mot2, @codigo = N'QA 2', @nombre = N'Otro motivo QA', @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_002|%') THROW 55124, 'TEST FAILED M2: codigo con espacio debe dar CTG_002.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_crear_motivo_cancelacion_sesion @id = @mot2, @codigo = N'QA_2', @nombre = N'<script>', @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_001|%') THROW 55125, 'TEST FAILED M2: nombre con < debe dar CTG_001.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_crear_motivo_cancelacion_sesion @id = @mot2, @codigo = N'QA_2', @nombre = N'Motivo valido', @idCorrelacion = @c, @idUsuarioEjecutor = @idNoAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%') OR (SELECT COUNT(*) FROM dbo.MotivoCancelacionSesion) <> @conteoMot + 1
        THROW 55126, 'TEST FAILED M2: no administrador debe recibir SEC_001 sin crear.', 1;
    DELETE FROM #r;

    -- M3: actualizar
    INSERT INTO #r EXEC dbo.usp_actualizar_motivo_cancelacion_sesion @id = @mot1, @nombre = N'Motivo renombrado', @orden = 99, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_motivo_cancelacion_sesion WHERE id = @mot1 AND codigo = N'QA_MOTIVO_1' AND nombre = N'Motivo renombrado' AND orden = 99)
        THROW 55127, 'TEST FAILED M3: la actualizacion no se persistio.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_motivo_cancelacion_sesion @id = @mot1, @nombre = N'Otro motivo', @orden = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%') THROW 55128, 'TEST FAILED M3: orden 0 debe dar GEN_002.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_motivo_cancelacion_sesion @id = @mot2, @nombre = N'Nuevo', @orden = 1, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_005|%') THROW 55129, 'TEST FAILED M3: id inexistente debe dar CTG_005.', 1;
    DELETE FROM #r;

    -- M4: desactivar conserva la fila y el historial; el SP de oferta al coordinador filtra por estaActivo
    DECLARE @idOtro UNIQUEIDENTIFIER = (SELECT id FROM dbo.MotivoCancelacionSesion WHERE codigo = N'OTRO');
    DECLARE @usadosOtro INT = (SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.MotivoCancelacionSesion m ON m.nombre = sc.motivo WHERE m.id = @idOtro);
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_motivo_cancelacion_sesion @id = @idOtro, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_008|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.MotivoCancelacionSesion WHERE id = @idOtro AND estaActivo = 0)
       OR (SELECT COUNT(*) FROM dbo.SesionCancelacion sc JOIN dbo.MotivoCancelacionSesion m ON m.nombre = sc.motivo WHERE m.id = @idOtro) <> @usadosOtro
        THROW 55130, 'TEST FAILED M4: desactivar conserva la fila y el historial.', 1;
    DELETE FROM #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_motivo_cancelacion_sesion @id = @idOtro, @estaActivo = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%') THROW 55131, 'TEST FAILED M4: estado nulo debe dar GEN_002.', 1;
    DELETE FROM #r;

    -- M5: el ultimo motivo activo no se desactiva
    UPDATE dbo.MotivoCancelacionSesion SET estaActivo = 0 WHERE id <> @mot1;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_motivo_cancelacion_sesion @id = @mot1, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CTG_003|%') OR NOT EXISTS (SELECT 1 FROM dbo.MotivoCancelacionSesion WHERE id = @mot1 AND estaActivo = 1)
        THROW 55132, 'TEST FAILED M5: el ultimo motivo activo no puede desactivarse (CTG_003).', 1;
    DELETE FROM #r;

    IF @@TRANCOUNT <> 1 THROW 55133, 'TEST FAILED: un SP altero el nivel de transaccion del llamador.', 1;

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    PRINT 'TEST_PASS:ADMIN_CATALOGOS_JUSTIFICACION_CANCELACION';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 55199, 'TEST FAILED: test_admin_catalogos_justificacion_cancelacion dejo transacciones abiertas.', 1;
PRINT 'TEST PASS: test_admin_catalogos_justificacion_cancelacion';
GO
