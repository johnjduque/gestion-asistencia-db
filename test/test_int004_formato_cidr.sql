USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- INT-004 (migracion 74): formato declarativo CIDR_LIST de CatalogoParametroEdicion.formato. Un valor mal formado de RED/CIDRS_CAMPUS o
-- RED/PROXIES_CONFIABLES que llega del Catalogo de Parametros externo se rechaza (PRM_017) y la BD conserva el valor anterior.
--   INT004F_01: ufn_validar_formato_valor / ufn_es_cidr_valido aceptan listas IPv4/IPv6 validas y rechazan las mal formadas.
--   INT004F_02: la semilla declara formato CIDR_LIST (no editable) en RED/CIDRS_CAMPUS y RED/PROXIES_CONFIABLES, y existe PRM_017.
--   INT004F_03: la sincronizacion rechaza una lista CIDR invalida (RECHAZADO, estado 0, PRM_017) y conserva el valor; acepta una valida.
--   INT004F_04: un parametro sin formato no se ve afectado (acepta cualquier texto).
--   INT004F_05: la edicion local (usp_actualizar_parametro) aplica la misma regla.
PRINT 'TEST START: test_int004_formato_cidr (INT-004)';
GO

-- INT004F_01: la funcion de formato (sin tocar datos)
DECLARE @malos TABLE (valor NVARCHAR(4000));
INSERT INTO @malos VALUES (N'no-es-un-cidr'), (N'10.0.0.0'), (N'10.0.0.0/33'), (N'300.1.1.1/8'), (N'10.0.0/8'), (N'10.0.0.0/8,'), (N'10.0.0.0/8,basura'),
    (N',10.0.0.0/8'), (N'10.0.0.0//8'), (N'10.0.0.0/-1'), (N'10.0.0.0/x'), (N'::1/129'), (N'g::1/64'), (N'1:2:3:4:5:6:7:8:9/64'), (N':::/0'),
    (N'1::2::3/64'), (N'12345::1/64'), (N':1::2/64'), (N'1:2:3:4:5:6:7/64'), (N'1.2.3.4.5/8'), (N'a.b.c.d/8'), (N'   '), (N'/8'), (N'10.0.0.0/');
IF EXISTS (SELECT 1 FROM @malos m WHERE dbo.ufn_validar_formato_valor('CIDR_LIST', m.valor) IS NULL)
    THROW 56500, 'TEST FAILED INT004F_01: una lista CIDR mal formada se acepto.', 1;
IF EXISTS (SELECT 1 FROM @malos m WHERE dbo.ufn_validar_formato_valor('CIDR_LIST', m.valor) <> 'PRM_017')
    THROW 56501, 'TEST FAILED INT004F_01: el rechazo debe ser PRM_017.', 1;
IF dbo.ufn_validar_formato_valor('CIDR_LIST', NULL) <> 'PRM_017'
    THROW 56502, 'TEST FAILED INT004F_01: un valor NULL no es una lista CIDR.', 1;

DECLARE @buenos TABLE (valor NVARCHAR(4000));
INSERT INTO @buenos VALUES (N'127.0.0.1/32,::1/128'), (N'10.0.0.0/8'), (N' 10.0.0.0/8 , 192.168.0.0/16 '), (N'0.0.0.0/0'), (N'255.255.255.255/32'),
    (N'::/0'), (N'2001:db8::/32'), (N'2001:0db8:0000:0000:0000:0000:0000:0001/128'), (N'fe80::1/10'), (N'1:2:3:4:5:6:7:8/128'), (N'::1/128'),
    (N'1::/16'), (N'FE80::ABCD/64'), (N'172.16.0.0/12,fd00::/8,10.1.2.0/24');
IF EXISTS (SELECT 1 FROM @buenos b WHERE dbo.ufn_validar_formato_valor('CIDR_LIST', b.valor) IS NOT NULL)
    THROW 56503, 'TEST FAILED INT004F_01: una lista CIDR valida se rechazo.', 1;
IF dbo.ufn_validar_formato_valor(NULL, N'cualquier cosa') IS NOT NULL
    THROW 56504, 'TEST FAILED INT004F_01: sin formato declarado no se valida.', 1;
PRINT 'TEST_PASS:INT004F_01_FORMATO_CIDR_LIST';
GO

-- INT004F_02: semilla
IF OBJECT_ID('dbo.ufn_es_cidr_valido', 'FN') IS NULL OR COL_LENGTH('dbo.CatalogoParametroEdicion', 'formato') IS NULL
    THROW 56505, 'TEST FAILED INT004F_02: faltan ufn_es_cidr_valido o CatalogoParametroEdicion.formato.', 1;
IF (SELECT COUNT(1) FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
    WHERE p.grupo = 'RED' AND p.clave IN ('CIDRS_CAMPUS', 'PROXIES_CONFIABLES') AND e.formato = 'CIDR_LIST' AND e.esEditable = 0) <> 2
    THROW 56506, 'TEST FAILED INT004F_02: RED/CIDRS_CAMPUS y RED/PROXIES_CONFIABLES deben declarar formato CIDR_LIST y no ser editables.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario WHERE codigo = 'PRM_017') OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico WHERE codigo = 'PRM_017')
    THROW 56507, 'TEST FAILED INT004F_02: falta el mensaje PRM_017.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
           WHERE e.formato = 'CIDR_LIST' AND dbo.ufn_validar_formato_valor(e.formato, p.valor) IS NOT NULL AND LEN(p.valor) > 0)
    THROW 56508, 'TEST FAILED INT004F_02: el valor sembrado de un parametro CIDR_LIST no cumple su propio formato.', 1;
PRINT 'TEST_PASS:INT004F_02_SEMILLA_FORMATO';
GO

IF OBJECT_ID('tempdb..#int004fResultado') IS NOT NULL DROP TABLE #int004fResultado;
CREATE TABLE #int004fResultado (
    idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT, resultado VARCHAR(20), grupo VARCHAR(100), clave VARCHAR(100), huboCambio BIT, fechaModificacion DATETIME);
GO

DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @t0 DATETIME2(7) = SYSUTCDATETIME();
DECLARE @idCidr UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'RED' AND clave = 'CIDRS_CAMPUS');
DECLARE @idProx UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'RED' AND clave = 'PROXIES_CONFIABLES');
DECLARE @idLibre UNIQUEIDENTIFIER = NEWID();
DECLARE @valorOriginal NVARCHAR(4000) = (SELECT valor FROM dbo.CatalogoParametro WHERE id = @idCidr);

BEGIN TRANSACTION;

INSERT INTO dbo.CatalogoParametro (id, grupo, clave, valor, tipoDato, valorDefecto, estaActivo)
VALUES (@idLibre, 'INT004F', 'LIBRE', N'a', 'STRING', N'a', 1);

-- INT004F_03: el caso del defecto: RED/CIDRS_CAMPUS = "no-es-un-cidr" llegaba como APLICADO
INSERT INTO #int004fResultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'RED', @clave = 'CIDRS_CAMPUS', @valor = N'no-es-un-cidr',
    @operacion = 'UPSERT', @idEvento = 'evtf-1', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004fResultado WHERE estadoResultado = 0 AND resultado = 'RECHAZADO' AND huboCambio = 0)
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idCidr AND valor = @valorOriginal)
   OR NOT EXISTS (SELECT 1 FROM dbo.SincronizacionParametroExterno WHERE idEvento = 'evtf-1' AND resultado = 'RECHAZADO' AND valorNuevo IS NULL)
   OR NOT EXISTS (SELECT 1 FROM #int004fResultado WHERE mensajeUsuarioResultado = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PRM_017'))
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56510, 'TEST FAILED INT004F_03: una lista CIDR invalida debe rechazarse con PRM_017 y conservar el valor.', 1;
END
DELETE FROM #int004fResultado;

INSERT INTO #int004fResultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'RED', @clave = 'CIDRS_CAMPUS', @valor = N'10.0.0.0/8,300.1.1.1/8',
    @operacion = 'UPSERT', @idEvento = 'evtf-2', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
INSERT INTO #int004fResultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'RED', @clave = 'PROXIES_CONFIABLES', @valor = N'10.0.0.1',
    @operacion = 'UPSERT', @idEvento = 'evtf-3', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF (SELECT COUNT(1) FROM #int004fResultado WHERE estadoResultado = 0 AND resultado = 'RECHAZADO') <> 2
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idCidr AND valor = @valorOriginal)
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idProx AND valor = N'10.0.0.1')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56511, 'TEST FAILED INT004F_03: un elemento invalido dentro de la lista o un proxy sin prefijo deben rechazarse.', 1;
END
DELETE FROM #int004fResultado;

INSERT INTO #int004fResultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'RED', @clave = 'CIDRS_CAMPUS', @valor = N' 10.20.0.0/16 , 2001:db8::/32 ',
    @operacion = 'UPSERT', @idEvento = 'evtf-4', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004fResultado WHERE estadoResultado = 1 AND resultado = 'APLICADO' AND huboCambio = 1)
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idCidr AND valor = N'10.20.0.0/16 , 2001:db8::/32')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56512, 'TEST FAILED INT004F_03: una lista CIDR valida debe aplicarse.', 1;
END
PRINT 'TEST_PASS:INT004F_03_SINCRONIZACION_RECHAZA_CIDR_INVALIDO';
DELETE FROM #int004fResultado;

-- INT004F_04: un parametro sin formato acepta cualquier texto
INSERT INTO #int004fResultado EXEC dbo.usp_sincronizar_parametro_catalogo_externo @grupo = 'INT004F', @clave = 'LIBRE', @valor = N'no-es-un-cidr',
    @operacion = 'UPSERT', @idEvento = 'evtf-5', @ocurridoEnUtc = @t0, @idCorrelacion = @corr;
IF NOT EXISTS (SELECT 1 FROM #int004fResultado WHERE estadoResultado = 1 AND resultado = 'APLICADO')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idLibre AND valor = N'no-es-un-cidr')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56513, 'TEST FAILED INT004F_04: un parametro sin formato no debe validarse como CIDR.', 1;
END
PRINT 'TEST_PASS:INT004F_04_SIN_FORMATO_NO_AFECTA';
DELETE FROM #int004fResultado;

-- INT004F_05: la edicion local aplica la misma regla (parametro temporal en un grupo editable, con formato)
DECLARE @admin UNIQUEIDENTIFIER = (SELECT TOP 1 a.usuario FROM dbo.Administrador a JOIN dbo.uv_usuario u ON u.id = a.usuario WHERE u.estaActivoUsuario = 1 ORDER BY a.id);
DECLARE @idEdit UNIQUEIDENTIFIER = NEWID();
IF @admin IS NULL
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56514, 'TEST FAILED INT004F_05: no hay administrador activo para la edicion local.', 1;
END
INSERT INTO dbo.CatalogoParametro (id, grupo, clave, valor, tipoDato, valorDefecto, estaActivo)
VALUES (@idEdit, 'INT004F', 'EDITABLE_CIDR', N'10.0.0.0/8', 'STRING', N'10.0.0.0/8', 1);
INSERT INTO dbo.CatalogoParametroEdicion (parametro, esEditable, etiqueta, descripcion, categoriaVisual, orden, formato)
VALUES (@idEdit, 1, N'Prueba INT004F', N'Prueba INT004F', N'Prueba', 0, 'CIDR_LIST');
DECLARE @f DATETIME = (SELECT fechaModificacion FROM dbo.CatalogoParametro WHERE id = @idEdit);
CREATE TABLE #int004fEdicion (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
    estadoResultado BIT, idParametro UNIQUEIDENTIFIER, grupo VARCHAR(100), clave VARCHAR(100), valorAnterior NVARCHAR(4000), valorNuevo NVARCHAR(4000), fechaModificacion DATETIME);
INSERT INTO #int004fEdicion EXEC dbo.usp_actualizar_parametro @idParametro = @idEdit, @valor = N'no-es-un-cidr', @fechaModificacionEsperada = @f,
    @motivo = N'Prueba INT004F local invalido', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
IF NOT EXISTS (SELECT 1 FROM #int004fEdicion WHERE estadoResultado = 0 AND mensajeUsuarioResultado = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'PRM_017'))
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idEdit AND valor = N'10.0.0.0/8')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56515, 'TEST FAILED INT004F_05: la edicion local debe rechazar una lista CIDR invalida con PRM_017.', 1;
END
DELETE FROM #int004fEdicion;
INSERT INTO #int004fEdicion EXEC dbo.usp_actualizar_parametro @idParametro = @idEdit, @valor = N'192.168.0.0/16,::1/128', @fechaModificacionEsperada = @f,
    @motivo = N'Prueba INT004F local valido', @idCorrelacion = @corr, @idUsuarioEjecutor = @admin;
IF NOT EXISTS (SELECT 1 FROM #int004fEdicion WHERE estadoResultado = 1)
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE id = @idEdit AND valor = N'192.168.0.0/16,::1/128')
BEGIN
    ROLLBACK TRANSACTION;
    THROW 56516, 'TEST FAILED INT004F_05: la edicion local debe aceptar una lista CIDR valida.', 1;
END
PRINT 'TEST_PASS:INT004F_05_EDICION_LOCAL_MISMA_REGLA';
DROP TABLE #int004fEdicion;

ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0
    THROW 56517, 'TEST FAILED INT004F_TRANCOUNT_ZERO: transaccion abierta.', 1;
PRINT 'TEST_PASS:INT004F_TRANCOUNT_ZERO';
GO

IF OBJECT_ID('tempdb..#int004fResultado') IS NOT NULL DROP TABLE #int004fResultado;
GO
