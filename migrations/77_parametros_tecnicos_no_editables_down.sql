-- ============================================================================
-- MIGRACION DOWN 77: los 11 parametros tecnicos vuelven a ser editables (esEditable = 1), como los dejaba la migracion 22 / seed 53
--   antes de la 77. No cambia valores de CatalogoParametro. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 77 DOWN: parametros tecnicos vuelven a ser editables';
GO
UPDATE e
SET    e.esEditable = 1
FROM   dbo.CatalogoParametroEdicion e
INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
INNER JOIN (VALUES
        ('ASISTENCIA_QR', 'LIMITE_ESTUDIANTE_POR_MINUTO'),
        ('ASISTENCIA_QR', 'LIMITE_IP_POR_MINUTO'),
        ('ASISTENCIA_QR', 'LIMITE_FALLIDOS_IP_POR_MINUTO'),
        ('ASISTENCIA_QR', 'LIMITE_TOKEN_POR_MINUTO'),
        ('MATRICULA_QR',  'LIMITE_IP_POR_MINUTO'),
        ('MATRICULA_QR',  'LIMITE_REGISTROS_TOKEN_POR_MINUTO'),
        ('ARCHIVOS',      'LIMITE_SUBIDAS_POR_MINUTO'),
        ('FESTIVOS',      'PROVEEDOR_PRINCIPAL'),
        ('FESTIVOS',      'TIMEOUT_SEGUNDOS'),
        ('FESTIVOS',      'MINIMO_POR_ANIO'),
        ('FESTIVOS',      'MAXIMO_POR_ANIO')
    ) AS v (grupo, clave) ON v.grupo = p.grupo AND v.clave = p.clave
WHERE  e.esEditable = 0;
GO
