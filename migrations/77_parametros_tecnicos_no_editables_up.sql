-- ============================================================================
-- MIGRACION UP 77: 11 parametros tecnicos dejan de ser editables por el administrador (esEditable = 0 en CatalogoParametroEdicion).
--   Clasificacion negocio vs tecnico del 2026-11-24 (decision de John): limites de tasa del QR de asistencia y de matricula, limite de
--   subidas de archivos y la configuracion de la integracion de festivos (proveedor, tiempo de espera y rango de cordura anual).
--   La fila se conserva (rango, regla cruzada MINIMO < MAXIMO y presentacion siguen sirviendo para validar la sincronizacion externa
--   y para mostrar el parametro en solo lectura). No cambia ningun valor de CatalogoParametro. Mismo resultado que
--   schema/seed/53_culm001_d3_parametro_edicion.sql. Idempotente. Down: 77_parametros_tecnicos_no_editables_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 77 UP: parametros tecnicos no editables';
GO
UPDATE e
SET    e.esEditable = 0
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
WHERE  e.esEditable = 1;
GO
