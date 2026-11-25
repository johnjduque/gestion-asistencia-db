-- Migracion 77 up -> down -> up (11 parametros tecnicos con esEditable = 0). Lo ejecuta test/test_param_migracion_77.ps1 con sqlcmd y la
-- variable MIGDIR. Parte de una BD ya desplegada desde schema/ (seed 53 con la 77). Todo ocurre dentro de UNA transaccion que se revierte.
--   PARAM_MIG77_UP1_OK       el up sobre una BD ya desplegada no cambia nada (idempotente)
--   PARAM_MIG77_DOWN_OK      el down vuelve a dejar editables los 11 y no toca otras filas ni valores
--   PARAM_MIG77_UP2_OK       el up (dos veces) deja los 11 con esEditable = 0 y no toca otras filas ni valores
--   PARAM_MIG77_ROLLBACK_OK  la transaccion se revirtio
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID('tempdb..#mig77') IS NOT NULL DROP TABLE #mig77;
CREATE TABLE #mig77 (grupo VARCHAR(100) NOT NULL, clave VARCHAR(100) NOT NULL);
INSERT INTO #mig77 (grupo, clave) VALUES
    ('ASISTENCIA_QR', 'LIMITE_ESTUDIANTE_POR_MINUTO'), ('ASISTENCIA_QR', 'LIMITE_IP_POR_MINUTO'), ('ASISTENCIA_QR', 'LIMITE_FALLIDOS_IP_POR_MINUTO'),
    ('ASISTENCIA_QR', 'LIMITE_TOKEN_POR_MINUTO'), ('MATRICULA_QR', 'LIMITE_IP_POR_MINUTO'), ('MATRICULA_QR', 'LIMITE_REGISTROS_TOKEN_POR_MINUTO'),
    ('ARCHIVOS', 'LIMITE_SUBIDAS_POR_MINUTO'), ('FESTIVOS', 'PROVEEDOR_PRINCIPAL'), ('FESTIVOS', 'TIMEOUT_SEGUNDOS'),
    ('FESTIVOS', 'MINIMO_POR_ANIO'), ('FESTIVOS', 'MAXIMO_POR_ANIO');
-- Huella de lo que la 77 no debe tocar: filas de edicion fuera de las 11 y todos los valores de CatalogoParametro
IF OBJECT_ID('tempdb..#otros77') IS NOT NULL DROP TABLE #otros77;
SELECT e.parametro, e.esEditable INTO #otros77 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
WHERE NOT EXISTS (SELECT 1 FROM #mig77 m WHERE m.grupo = p.grupo AND m.clave = p.clave);
IF OBJECT_ID('tempdb..#valores77') IS NOT NULL DROP TABLE #valores77;
SELECT id, CONVERT(NVARCHAR(4000), valor) AS valor INTO #valores77 FROM dbo.CatalogoParametro;
GO
BEGIN TRANSACTION;
GO
IF (SELECT COUNT(*) FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
    INNER JOIN #mig77 m ON m.grupo = p.grupo AND m.clave = p.clave WHERE e.esEditable = 0) <> 11
    THROW 59770, 'TEST FAILED: PARAM_MIG77 la base inicial no tiene los 11 parametros tecnicos con esEditable = 0 (desplegar schema/ de la rama primero).', 1;
GO
:r $(MIGDIR)/77_parametros_tecnicos_no_editables_up.sql
GO
IF (SELECT COUNT(*) FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
    INNER JOIN #mig77 m ON m.grupo = p.grupo AND m.clave = p.clave WHERE e.esEditable = 0) <> 11
    THROW 59771, 'TEST FAILED: PARAM_MIG77 el up no es idempotente sobre la base desplegada.', 1;
PRINT 'PARAM_MIG77_UP1_OK';
GO
:r $(MIGDIR)/77_parametros_tecnicos_no_editables_down.sql
GO
IF (SELECT COUNT(*) FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
    INNER JOIN #mig77 m ON m.grupo = p.grupo AND m.clave = p.clave WHERE e.esEditable = 1) <> 11
   OR EXISTS (SELECT 1 FROM #otros77 o INNER JOIN dbo.CatalogoParametroEdicion e ON e.parametro = o.parametro WHERE e.esEditable <> o.esEditable)
   OR EXISTS (SELECT 1 FROM #valores77 v INNER JOIN dbo.CatalogoParametro p ON p.id = v.id WHERE ISNULL(CONVERT(NVARCHAR(4000), p.valor), N'') <> ISNULL(v.valor, N''))
    THROW 59772, 'TEST FAILED: PARAM_MIG77 el down no dejo editables los 11 o toco otras filas o valores.', 1;
PRINT 'PARAM_MIG77_DOWN_OK';
GO
:r $(MIGDIR)/77_parametros_tecnicos_no_editables_up.sql
GO
:r $(MIGDIR)/77_parametros_tecnicos_no_editables_up.sql
GO
IF (SELECT COUNT(*) FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
    INNER JOIN #mig77 m ON m.grupo = p.grupo AND m.clave = p.clave WHERE e.esEditable = 0) <> 11
   OR EXISTS (SELECT 1 FROM #otros77 o INNER JOIN dbo.CatalogoParametroEdicion e ON e.parametro = o.parametro WHERE e.esEditable <> o.esEditable)
   OR EXISTS (SELECT 1 FROM #valores77 v INNER JOIN dbo.CatalogoParametro p ON p.id = v.id WHERE ISNULL(CONVERT(NVARCHAR(4000), p.valor), N'') <> ISNULL(v.valor, N''))
    THROW 59773, 'TEST FAILED: PARAM_MIG77 el up no dejo los 11 no editables o toco otras filas o valores.', 1;
PRINT 'PARAM_MIG77_UP2_OK';
GO
ROLLBACK TRANSACTION;
GO
IF @@TRANCOUNT <> 0
   OR (SELECT COUNT(*) FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
       INNER JOIN #mig77 m ON m.grupo = p.grupo AND m.clave = p.clave WHERE e.esEditable = 0) <> 11
    THROW 59774, 'TEST FAILED: PARAM_MIG77 transaccion abierta o estado perdido tras el rollback.', 1;
PRINT 'PARAM_MIG77_ROLLBACK_OK';
GO
