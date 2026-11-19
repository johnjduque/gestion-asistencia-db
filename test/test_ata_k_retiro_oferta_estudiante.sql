USE [gestionasistenciadb];
GO
-- ATA D11 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS K.1): tras desplegar el esquema ya no existen la oferta de grupos del
-- estudiante (HU008, descartada) ni su parametro, y la oferta del docente para crear grupos sigue disponible.
SET NOCOUNT ON;
PRINT 'TEST START: test_ata_k_retiro_oferta_estudiante';
BEGIN TRY
    IF OBJECT_ID(N'dbo.usp_consultar_oferta_grupos_estudiante', N'P') IS NOT NULL
        THROW 59401, 'TEST FAILED: ATA_K_01 usp_consultar_oferta_grupos_estudiante no debe existir tras el despliegue.', 1;
    IF EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'OFERTA' AND clave = 'INCLUIR_TRANSVERSALES')
        THROW 59402, 'TEST FAILED: ATA_K_02 el parametro OFERTA/INCLUIR_TRANSVERSALES no debe existir tras el despliegue.', 1;
    PRINT 'TEST_PASS:ATA_K_01_OFERTA_ESTUDIANTE_RETIRADA';
    IF OBJECT_ID(N'dbo.usp_consultar_oferta_creacion_grupo_docente', N'P') IS NULL
        THROW 59403, 'TEST FAILED: ATA_K_03 la oferta del docente para crear grupos debe seguir disponible.', 1;
    PRINT 'TEST_PASS:ATA_K_02_OFERTA_DOCENTE_CONSERVADA';
END TRY
BEGIN CATCH
    PRINT 'TEST FAILED: ATA_K ' + ERROR_MESSAGE();
    THROW;
END CATCH;
GO
