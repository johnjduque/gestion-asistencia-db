USE [gestionasistenciadb];
GO
-- CULM-001 B2NM (B2NM-01, 02, 04 parcial, 17 parcial): asignatura N:M por plan. Transaccion revertida; no deja datos.
-- Usa la semilla canonica: Programa B2C3D4E5-...01 (coordinador F1A2B3C4-...02), plan C2D3E4F5-...01 y asignatura ARQ-402.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_culm001_b2nm_asignatura_plan';
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @plan UNIQUEIDENTIFIER = 'C2D3E4F5-0000-0000-0000-000000000001', @asig UNIQUEIDENTIFIER = 'E2F3A4B5-0000-0000-0000-000000000001';
    DECLARE @coord UNIQUEIDENTIFIER = (SELECT c.usuario FROM dbo.Coordinador c WHERE c.id = 'F1A2B3C4-0000-0000-0000-000000000002');
    DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @programa UNIQUEIDENTIFIER = 'B2C3D4E5-0000-0000-0000-000000000001';
    IF @coord IS NULL THROW 53820, 'TEST FAILED: B2NM semilla de coordinador ausente.', 1;
    DECLARE @planInexistente UNIQUEIDENTIFIER = NEWID(), @asigNueva UNIQUEIDENTIFIER = NEWID();
    DECLARE @r TABLE (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT);

    -- B2NM-01: la asignatura sembrada tiene exactamente 1 vinculo activo OBL y uv_asignatura 1 fila
    IF (SELECT COUNT(*) FROM dbo.uv_asignatura WHERE id = @asig) <> 1 THROW 53821, 'TEST FAILED: B2NM-01 uv_asignatura debe tener 1 fila.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_asignatura_plan_estudio WHERE idAsignatura = @asig AND estaActivoVinculo = 1 AND codigoCaracter = N'OBL') <> 1
        THROW 53822, 'TEST FAILED: B2NM-01 vinculo OBL activo esperado.', 1;

    -- B2NM-02: doble asociacion al mismo plan -> ASI_003; caracter invalido -> ASI_007 (se valida primero el vinculo existente)
    DELETE FROM @r; INSERT INTO @r EXEC dbo.usp_asociar_asignatura_plan @idAsignatura = @asig, @idPlanEstudio = @plan, @semestreNumero = 8, @codigoCaracter = N'OPT', @idCorrelacion = @corr, @idUsuarioEjecutor = @coord;
    IF NOT EXISTS (SELECT 1 FROM @r WHERE estado = 0 AND mt LIKE N'%ASI_003%') THROW 53823, 'TEST FAILED: B2NM-02 doble asociacion debe dar ASI_003.', 1;
    DELETE FROM @r; INSERT INTO @r EXEC dbo.usp_asociar_asignatura_plan @idAsignatura = @asig, @idPlanEstudio = @planInexistente, @semestreNumero = 8, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord;
    IF NOT EXISTS (SELECT 1 FROM @r WHERE estado = 0 AND mt LIKE N'%PLA_002%') THROW 53824, 'TEST FAILED: B2NM-02 plan inexistente debe dar PLA_002.', 1;

    -- B2NM-02: crear con codigo existente -> ASI_002
    DELETE FROM @r; INSERT INTO @r EXEC dbo.usp_crear_asignatura @idAsignatura = @asigNueva, @codigo = N'ARQ-402', @nombre = N'Duplicada', @creditos = 3, @idPlanEstudio = @plan,
        @semestreNumero = 8, @nombreArea = N'x', @nombreComponente = N'x', @idCorrelacion = @corr, @idUsuarioEjecutor = @coord, @codigoCaracter = N'OBL';
    IF NOT EXISTS (SELECT 1 FROM @r WHERE estado = 0 AND mt LIKE N'%ASI_002%') THROW 53825, 'TEST FAILED: B2NM-02 codigo existente debe dar ASI_002.', 1;

    -- B2NM-04: desvincular sin grupos vigentes -> baja logica; reasociar reactiva la MISMA fila
    DECLARE @idVinculo UNIQUEIDENTIFIER = (SELECT idAsignaturaPlanEstudio FROM dbo.uv_asignatura_plan_estudio WHERE idAsignatura = @asig AND estaActivoVinculo = 1);
    DELETE FROM @r; INSERT INTO @r EXEC dbo.usp_desvincular_asignatura_plan @idAsignatura = @asig, @idPlanEstudio = @plan, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord;
    -- el grupo sembrado de ARQ-402 esta en un periodo vigente y su unico programa es este: debe dar ASI_005 y no cambiar nada
    IF NOT EXISTS (SELECT 1 FROM @r WHERE estado = 0 AND mt LIKE N'%ASI_005%') AND NOT EXISTS (SELECT 1 FROM @r WHERE estado = 1)
        THROW 53826, 'TEST FAILED: B2NM-04 desvincular debe dar ASI_005 o bien baja logica.', 1;
    DECLARE @estaba BIT = (SELECT estaActivo FROM dbo.AsignaturaPlanEstudio WHERE id = @idVinculo);
    IF @estaba = 0
    BEGIN
        DELETE FROM @r; INSERT INTO @r EXEC dbo.usp_asociar_asignatura_plan @idAsignatura = @asig, @idPlanEstudio = @plan, @semestreNumero = 8, @idCorrelacion = @corr, @idUsuarioEjecutor = @coord;
        IF (SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio WHERE asignatura = @asig) <> 1 OR (SELECT estaActivo FROM dbo.AsignaturaPlanEstudio WHERE id = @idVinculo) <> 1
            THROW 53827, 'TEST FAILED: B2NM-04 reasociar debe reactivar la misma fila.', 1;
    END

    -- Cardinalidad (B2NM-03 parcial): sin duplicados en las vistas 1:1
    IF EXISTS (SELECT 1 FROM dbo.uv_grupo GROUP BY id HAVING COUNT(*) > 1) THROW 53828, 'TEST FAILED: B2NM-03 uv_grupo duplica grupos.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo GROUP BY id HAVING COUNT(*) > 1) THROW 53829, 'TEST FAILED: B2NM-03 uv_estudiante_grupo duplica matriculas.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo GROUP BY idEstudianteGrupo HAVING COUNT(*) > 1) THROW 53830, 'TEST FAILED: B2NM-03 resumen duplica matriculas.', 1;

    PRINT 'TEST_PASS:CULM001_B2NM_ASIGNATURA_PLAN';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 53899, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
