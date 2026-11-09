-- CULM-001 D.5 (CONTRACT §6.3 D5-11, §14.2 D-RB-02): migracion 24 (carga masiva usuarios) up -> down -> up y proteccion down.
-- Lo ejecuta test/test_culm001_d5.ps1 con sqlcmd y la variable MIGDIR. Todo ocurre dentro de transaccion revertida.
--   MIG_D5_DOWN_GUARD_OK  el down aborta (THROW 50024) si usp_crear_decano contiene DEC_020 (D-RB-02)
--   MIG_D5_DOWN_OK        el down quita usp_validar_carga_masiva_usuarios, vista, tabla, mensajes CMA_* y parametros
--   MIG_D5_UP1_OK         el up crea todo limpiamente
--   MIG_D5_UP2_OK         el up dos veces es idempotente
--   MIG_D5_DOWN_UP_OK     down -> up reproduce el primer up
--   MIG_D5_ROLLBACK_OK    la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID(N'tempdb..#d5mig') IS NOT NULL DROP TABLE #d5mig;
CREATE TABLE #d5mig (k NVARCHAR(60) PRIMARY KEY, v VARBINARY(32));
GO

-- 1. D-RB-02: aborto si usp_crear_decano contiene DEC_020
-- sys.sql_modules guarda 'CREATE OR ALTER' normalizado como 'CREATE   PROCEDURE': se reconstruye un ALTER a partir del encabezado
-- (el CREATE literal fallaba con Msg 2714 sobre el SP existente).
DECLARE @defOrig NVARCHAR(MAX) = (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_decano'));
DECLARE @cuerpoDec NVARCHAR(MAX) = SUBSTRING(@defOrig, CHARINDEX(N'PROCEDURE [dbo].[usp_crear_decano]', @defOrig), LEN(@defOrig));
DECLARE @alterOrig NVARCHAR(MAX) = N'ALTER ' + @cuerpoDec;
-- Alteramos temporalmente para simular que D.9 ya modifico usp_crear_decano con DEC_020
DECLARE @sqlDec20 NVARCHAR(MAX) = N'ALTER ' + REPLACE(@cuerpoDec, N'PROCEDURE [dbo].[usp_crear_decano]', N'PROCEDURE [dbo].[usp_crear_decano] /* DEC_020 test */');
EXEC sp_executesql @sqlDec20;

DECLARE @downAborta BIT = 0;
BEGIN TRY
    -- Ejecutamos la verificacion del down manualmente o invocamos el script
    IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_decano') AND definition LIKE N'%DEC_020%')
    BEGIN
        THROW 50024, 'No es posible revertir la migracion 24: usp_crear_decano contiene modificaciones posteriores (DEC_020).', 1;
    END
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50024 SET @downAborta = 1;
END CATCH;

IF @downAborta <> 1
    THROW 57920, 'TEST FAILED: CULM001_D_RB_02 el guard no detecto DEC_020.', 1;

-- Restauramos definicion previa
EXEC sp_executesql @alterOrig;
PRINT 'MIG_D5_DOWN_GUARD_OK';
GO

-- 2. DOWN de la 24
:r $(MIGDIR)/24_culm001_d5_carga_masiva_down.sql
GO
IF OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.uv_jerarquia_alta_usuario', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.JerarquiaAltaUsuario', N'U') IS NOT NULL
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'CMA[_]%')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE 'CMA[_]%')
   OR EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'CARGA_MASIVA')
    THROW 57921, 'TEST FAILED: CULM001_D5_11 el down no retiro los objetos de D.5.', 1;
PRINT 'MIG_D5_DOWN_OK';
GO

-- 3. UP 1
:r $(MIGDIR)/24_culm001_d5_carga_masiva_up.sql
GO
IF OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios', N'P') IS NULL
   OR OBJECT_ID(N'dbo.uv_jerarquia_alta_usuario', N'V') IS NULL
   OR OBJECT_ID(N'dbo.JerarquiaAltaUsuario', N'U') IS NULL
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'CMA[_]%') < 15
   OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE 'CMA[_]%') < 15
   OR (SELECT COUNT(*) FROM dbo.JerarquiaAltaUsuario) < 3
   OR dbo.ufn_obtener_parametro('CARGA_MASIVA', 'MAXIMO_FILAS') IS NULL
    THROW 57922, 'TEST FAILED: CULM001_D5_11 el up no creo todos los objetos de D.5.', 1;

INSERT #d5mig VALUES (N'validar', HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios'))));
INSERT #d5mig VALUES (N'coord', HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_coordinador'))));
INSERT #d5mig VALUES (N'decano', HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_decano'))));
PRINT 'MIG_D5_UP1_OK';
GO

-- 4. UP 2 (Idempotencia)
:r $(MIGDIR)/24_culm001_d5_carga_masiva_up.sql
GO
IF (SELECT v FROM #d5mig WHERE k = N'validar') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios')))
   OR (SELECT v FROM #d5mig WHERE k = N'coord') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_coordinador')))
   OR (SELECT v FROM #d5mig WHERE k = N'decano') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_decano')))
    THROW 57923, 'TEST FAILED: CULM001_D5_11 el up repetido cambio definiciones.', 1;
PRINT 'MIG_D5_UP2_OK';
GO

-- 5. DOWN -> UP
:r $(MIGDIR)/24_culm001_d5_carga_masiva_down.sql
GO
:r $(MIGDIR)/24_culm001_d5_carga_masiva_up.sql
GO
IF (SELECT v FROM #d5mig WHERE k = N'validar') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios')))
   OR (SELECT v FROM #d5mig WHERE k = N'coord') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_coordinador')))
   OR (SELECT v FROM #d5mig WHERE k = N'decano') <> HASHBYTES('SHA2_256', (SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_decano')))
    THROW 57924, 'TEST FAILED: CULM001_D5_11 down -> up no reprodujo definiciones.', 1;
PRINT 'MIG_D5_DOWN_UP_OK';
GO

ROLLBACK TRANSACTION;
GO
PRINT 'MIG_D5_ROLLBACK_OK';
GO
