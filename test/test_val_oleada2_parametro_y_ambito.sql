USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;

-- VAL PAR-06 y ROL-12 (oleada 2; migracion 40 y semillas 57_val_*):
--   VAL_PAR06_01: existe AUDITORIA/RANGO_MAXIMO_DIAS = 90, tipo INT, valor por defecto 90, activo.
--   VAL_PAR06_02: rango 1..366 en CatalogoParametroEdicion, no editable (tambien en uv_parametro_edicion), y ufn_validar_valor_parametro
--                 acepta 90, 1 y 366 y rechaza 0 y 367 con PRM_005.
--   VAL_ROL12_01: la cuenta semilla de decano (decano.ingenieria@uco.edu.co) es titular de una facultad.
--   VAL_ROL12_02: la cuenta semilla de coordinador (coordinador.sistemas@uco.edu.co) tiene programa y facultad.
-- Solo lectura. Cada verificacion va en su propio lote.
PRINT 'TEST START: test_val_oleada2_parametro_y_ambito (VAL PAR-06, ROL-12)';
GO

IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'AUDITORIA' AND clave = 'RANGO_MAXIMO_DIAS'
               AND valor = N'90' AND valorDefecto = N'90' AND tipoDato = 'INT' AND estaActivo = 1)
    THROW 53920, 'TEST FAILED VAL_PAR06_01: falta AUDITORIA/RANGO_MAXIMO_DIAS = 90 INT (migracion 40).', 1;
PRINT 'TEST_PASS:VAL_PAR06_01_PARAMETRO_SEMBRADO';
GO

DECLARE @id UNIQUEIDENTIFIER = (SELECT id FROM dbo.CatalogoParametro WHERE grupo = 'AUDITORIA' AND clave = 'RANGO_MAXIMO_DIAS');
IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion WHERE parametro = @id AND esEditable = 0 AND valorMinimo = 1 AND valorMaximo = 366)
    THROW 53921, 'TEST FAILED VAL_PAR06_02: falta la fila de edicion no editable con rango 1..366.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_parametro_edicion WHERE id = @id AND esEditable = 1)
    THROW 53922, 'TEST FAILED VAL_PAR06_02: el parametro de auditoria no debe ser editable.', 1;
IF dbo.ufn_validar_valor_parametro('INT', N'90', 1, 366, NULL) IS NOT NULL
   OR dbo.ufn_validar_valor_parametro('INT', N'1', 1, 366, NULL) IS NOT NULL
   OR dbo.ufn_validar_valor_parametro('INT', N'366', 1, 366, NULL) IS NOT NULL
    THROW 53923, 'TEST FAILED VAL_PAR06_02: 90, 1 y 366 deben ser validos.', 1;
IF ISNULL(dbo.ufn_validar_valor_parametro('INT', N'0', 1, 366, NULL), '') <> 'PRM_005'
   OR ISNULL(dbo.ufn_validar_valor_parametro('INT', N'367', 1, 366, NULL), '') <> 'PRM_005'
    THROW 53924, 'TEST FAILED VAL_PAR06_02: 0 y 367 deben dar PRM_005.', 1;
PRINT 'TEST_PASS:VAL_PAR06_02_RANGO_Y_NO_EDITABLE';
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Usuario u
               INNER JOIN dbo.Decano d ON d.usuario = u.id
               INNER JOIN dbo.Facultad f ON f.decano = d.id AND f.estado = 1
               WHERE u.correo = 'decano.ingenieria@uco.edu.co')
    THROW 53925, 'TEST FAILED VAL_ROL12_01: la cuenta semilla de decano no es titular de ninguna facultad.', 1;
PRINT 'TEST_PASS:VAL_ROL12_01_DECANO_CON_FACULTAD';
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Usuario u
               INNER JOIN dbo.Coordinador c ON c.usuario = u.id AND c.facultad IS NOT NULL
               INNER JOIN dbo.Programa p ON p.coordinador = c.id AND p.estado = 1 AND p.facultad = c.facultad
               WHERE u.correo = 'coordinador.sistemas@uco.edu.co')
    THROW 53926, 'TEST FAILED VAL_ROL12_02: la cuenta semilla de coordinador no tiene programa y facultad coherentes.', 1;
PRINT 'TEST_PASS:VAL_ROL12_02_COORDINADOR_CON_PROGRAMA';
GO

IF @@TRANCOUNT <> 0
    THROW 53927, 'TEST FAILED VAL_OLEADA2_TRANCOUNT: transaccion abierta.', 1;
PRINT 'TEST_PASS:VAL_OLEADA2_TRANCOUNT_ZERO';
GO
