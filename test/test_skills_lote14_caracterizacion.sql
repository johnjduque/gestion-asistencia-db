USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 14 (plan por lotes 2026-11-25): objetos congelados (decision D5).
-- Fija el comportamiento de los dos SP del lote que no tenian prueba directa, antes de refactorizarlos. Los demas siguen cubiertos
-- por sus pruebas de dominio. Todo lo que escribe corre dentro de una transaccion revertida.
--   SKL14_R01_VALOR_PARAMETRO_EXTERNO  usp_validar_valor_parametro_externo_interno: valor valido (sin rechazo), tipo invalido (PRM_004
--                                      con el tipo), fuera de rango (PRM_005 con minimo y maximo), no permitido (PRM_006 con la
--                                      lista) y parametro inexistente (sin rechazo)
--   SKL14_R02_ACTUALIZAR_SESION        usp_actualizar_sesion_interno: renombrar con el mismo horario (GEN_004, nombre recortado,
--                                      correlacion devuelta), sesion inexistente (SES_001), otro docente (SEC_002) y correlacion nula
--                                      (CORR_001)
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote14_caracterizacion';

DECLARE @idDias UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'ASISTENCIA' AND clave = 'DIAS_LIMITE_JUSTIFICACION');
DECLARE @idProveedor UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'FESTIVOS' AND clave = 'PROVEEDOR_PRINCIPAL');
DECLARE @minDias DECIMAL(19,4), @maxDias DECIMAL(19,4), @permitidos NVARCHAR(500);
SELECT @minDias = valorMinimo, @maxDias = valorMaximo FROM dbo.CatalogoParametroEdicion WHERE parametro = @idDias;
SELECT @permitidos = valoresPermitidos FROM dbo.CatalogoParametroEdicion WHERE parametro = @idProveedor;
DECLARE @s UNIQUEIDENTIFIER, @docU UNIQUEIDENTIFIER, @ini DATETIME2, @fin DATETIME2, @otroDoc UNIQUEIDENTIFIER;
SELECT TOP 1 @s = s.id, @docU = d.usuario, @ini = s.fechaHoraInicio, @fin = s.fechaHoraFin
FROM dbo.Sesion s INNER JOIN dbo.Grupo g ON g.id = s.grupo INNER JOIN dbo.Docente d ON d.id = g.docente
WHERE NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion c WHERE c.sesion = s.id)
ORDER BY s.id;
SELECT TOP 1 @otroDoc = d.usuario FROM dbo.Docente d
WHERE d.usuario <> @docU
  AND NOT EXISTS (SELECT 1 FROM dbo.Administrador a WHERE a.usuario = d.usuario)
  AND NOT EXISTS (SELECT 1 FROM dbo.Grupo g2 INNER JOIN dbo.Sesion s2 ON s2.grupo = g2.id WHERE s2.id = @s AND g2.docente = d.id)
ORDER BY d.usuario;
IF @idDias IS NULL OR @minDias IS NULL OR @maxDias IS NULL OR @idProveedor IS NULL OR @permitidos IS NULL OR @s IS NULL OR @otroDoc IS NULL
    THROW 56400, 'TEST FAILED: SKL14 faltan fixtures del seed (parametros editables, sesion no cancelada y otro docente).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @inexistente UNIQUEIDENTIFIER = '5C6A0000-0000-0000-0000-0000000000E9';
    DECLARE @r VARCHAR(20), @p1 NVARCHAR(500), @p2 NVARCHAR(500);
    DECLARE @cr UNIQUEIDENTIFIER, @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT;
    DECLARE @sufijo NVARCHAR(60) = N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr);
    DECLARE @minTexto NVARCHAR(40) = CONVERT(NVARCHAR(40), CONVERT(BIGINT, @minDias));
    DECLARE @maxTexto NVARCHAR(40) = CONVERT(NVARCHAR(40), CONVERT(BIGINT, @maxDias));
    DECLARE @fuera NVARCHAR(40) = CONVERT(NVARCHAR(40), CONVERT(BIGINT, @maxDias) + 1);

    -- ================================================================= R01
    SELECT @r = 'X', @p1 = N'X', @p2 = N'X';
    EXEC dbo.usp_validar_valor_parametro_externo_interno @idParametro = @idDias, @valor = @minTexto, @idCorrelacion = @corr,
         @codigoRechazo = @r OUTPUT, @param1 = @p1 OUTPUT, @param2 = @p2 OUTPUT;
    IF @r IS NOT NULL OR @p1 IS NOT NULL OR @p2 IS NOT NULL THROW 56410, 'TEST FAILED: SKL14_R01_VALOR_PARAMETRO_EXTERNO (valido)', 1;
    EXEC dbo.usp_validar_valor_parametro_externo_interno @idParametro = @idDias, @valor = N'abc', @idCorrelacion = @corr,
         @codigoRechazo = @r OUTPUT, @param1 = @p1 OUTPUT, @param2 = @p2 OUTPUT;
    IF @r <> 'PRM_004' OR @p1 <> N'INT' OR @p2 IS NOT NULL THROW 56411, 'TEST FAILED: SKL14_R01_VALOR_PARAMETRO_EXTERNO (PRM_004)', 1;
    EXEC dbo.usp_validar_valor_parametro_externo_interno @idParametro = @idDias, @valor = @fuera, @idCorrelacion = @corr,
         @codigoRechazo = @r OUTPUT, @param1 = @p1 OUTPUT, @param2 = @p2 OUTPUT;
    IF @r <> 'PRM_005' OR @p1 <> @minTexto OR @p2 <> @maxTexto THROW 56412, 'TEST FAILED: SKL14_R01_VALOR_PARAMETRO_EXTERNO (PRM_005)', 1;
    EXEC dbo.usp_validar_valor_parametro_externo_interno @idParametro = @idProveedor, @valor = N'NO_EXISTE_SKL14', @idCorrelacion = @corr,
         @codigoRechazo = @r OUTPUT, @param1 = @p1 OUTPUT, @param2 = @p2 OUTPUT;
    IF @r <> 'PRM_006' OR @p1 <> @permitidos OR @p2 IS NOT NULL THROW 56413, 'TEST FAILED: SKL14_R01_VALOR_PARAMETRO_EXTERNO (PRM_006)', 1;
    SELECT @r = 'X', @p1 = N'X', @p2 = N'X';
    EXEC dbo.usp_validar_valor_parametro_externo_interno @idParametro = @inexistente, @valor = N'1', @idCorrelacion = @corr,
         @codigoRechazo = @r OUTPUT, @param1 = @p1 OUTPUT, @param2 = @p2 OUTPUT;
    IF @r IS NOT NULL OR @p1 IS NOT NULL OR @p2 IS NOT NULL THROW 56414, 'TEST FAILED: SKL14_R01_VALOR_PARAMETRO_EXTERNO (inexistente)', 1;
    PRINT 'TEST_PASS:SKL14_R01_VALOR_PARAMETRO_EXTERNO';

    -- ================================================================= R02
    EXEC dbo.usp_actualizar_sesion_interno @idSesion = @s, @nombre = N'  Sesion SKL14  ', @fechaHoraInicio = @ini, @fechaHoraFin = @fin,
         @idCorrelacion = @corr, @idUsuarioEjecutor = @docU, @procedenciaTemporal = N'UTC_V2', @idCorrelacionResultado = @cr OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @cr <> @corr OR @mt NOT LIKE N'DBCODE=GEN[_]004|%' OR @mt NOT LIKE @sufijo OR @@TRANCOUNT <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @s AND nombre = N'Sesion SKL14' AND procedenciaTemporal = N'UTC_V2'
                      AND fechaHoraInicio = @ini AND fechaHoraFin = @fin)
        THROW 56420, 'TEST FAILED: SKL14_R02_ACTUALIZAR_SESION (renombrar)', 1;
    EXEC dbo.usp_actualizar_sesion_interno @idSesion = @inexistente, @nombre = N'x', @fechaHoraInicio = @ini, @fechaHoraFin = @fin,
         @idCorrelacion = @corr, @idUsuarioEjecutor = @docU, @procedenciaTemporal = N'UTC_V2', @idCorrelacionResultado = @cr OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=SES[_]001|%' OR @mt NOT LIKE @sufijo THROW 56421, 'TEST FAILED: SKL14_R02_ACTUALIZAR_SESION (SES_001)', 1;
    EXEC dbo.usp_actualizar_sesion_interno @idSesion = @s, @nombre = N'x', @fechaHoraInicio = @ini, @fechaHoraFin = @fin,
         @idCorrelacion = @corr, @idUsuarioEjecutor = @otroDoc, @procedenciaTemporal = N'UTC_V2', @idCorrelacionResultado = @cr OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=SEC[_]002|%' OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @s AND nombre = N'x')
        THROW 56422, 'TEST FAILED: SKL14_R02_ACTUALIZAR_SESION (SEC_002)', 1;
    EXEC dbo.usp_actualizar_sesion_interno @idSesion = @s, @nombre = N'x', @fechaHoraInicio = @ini, @fechaHoraFin = @fin,
         @idCorrelacion = NULL, @idUsuarioEjecutor = @docU, @procedenciaTemporal = N'UTC_V2', @idCorrelacionResultado = @cr OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=CORR[_]001|%' THROW 56423, 'TEST FAILED: SKL14_R02_ACTUALIZAR_SESION (CORR_001)', 1;
    PRINT 'TEST_PASS:SKL14_R02_ACTUALIZAR_SESION';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
PRINT 'TEST END: test_skills_lote14_caracterizacion';
GO
