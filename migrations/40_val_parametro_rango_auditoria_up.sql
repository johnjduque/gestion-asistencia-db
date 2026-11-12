-- ============================================================================
-- MIGRACION UP 40: VAL PAR-06 y VAL ROL-12 (oleada 2)
--   PAR-06: siembra AUDITORIA/RANGO_MAXIMO_DIAS = 90 (INT, rango 1..366, no editable: el grupo AUDITORIA esta en
--           PARAMETROS/GRUPOS_NO_EDITABLES) para que el backend lo lea del catalogo en vez de tenerlo fijo.
--   ROL-12: asigna ambito a las cuentas semilla de decano (Facultad.decano) y coordinador (Programa.coordinador y
--           Coordinador.facultad) cuando existen y no lo tienen. El texto es el de schema/seed/57_val_*.sql.
-- Idempotente. Down: 40_val_parametro_rango_auditoria_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 40 UP: VAL PAR-06 (AUDITORIA/RANGO_MAXIMO_DIAS) y ROL-12 (ambito de cuentas semilla)';
GO
-- VAL PAR-06: rango maximo de dias de la consulta de auditoria (antes fijo en el codigo del backend).
-- Grupo AUDITORIA: pertenece a PARAMETROS/GRUPOS_NO_EDITABLES, asi que la fila de edicion queda con esEditable = 0; solo documenta el
-- rango valido (1..366) y la presentacion. Idempotente y sin pisar el valor vigente.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('AUDITORIA', 'RANGO_MAXIMO_DIAS', N'90', 'INT', N'90')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

IF OBJECT_ID(N'dbo.CatalogoParametroEdicion', N'U') IS NOT NULL
BEGIN
    MERGE INTO [dbo].[CatalogoParametroEdicion] AS Target
    USING (
        SELECT p.id AS parametro
        FROM [dbo].[CatalogoParametro] p
        WHERE p.grupo = 'AUDITORIA' AND p.clave = 'RANGO_MAXIMO_DIAS'
    ) AS Source
    ON (Target.parametro = Source.parametro)
    WHEN MATCHED THEN
        UPDATE SET Target.esEditable = 0, Target.valorMinimo = 1, Target.valorMaximo = 366, Target.valoresPermitidos = NULL,
                   Target.etiqueta = N'Rango máximo de la consulta de auditoría',
                   Target.descripcion = N'Días máximos entre la fecha inicial y la final de la consulta de auditoría. Parámetro de gobierno: no se edita desde la aplicación.',
                   Target.unidad = N'días', Target.categoriaVisual = N'Auditoría', Target.orden = 10
    WHEN NOT MATCHED THEN
        INSERT (parametro, esEditable, valorMinimo, valorMaximo, valoresPermitidos, parametroDebeSerMenorQue, etiqueta, descripcion, unidad, categoriaVisual, orden)
        VALUES (Source.parametro, 0, 1, 366, NULL, NULL, N'Rango máximo de la consulta de auditoría',
                N'Días máximos entre la fecha inicial y la final de la consulta de auditoría. Parámetro de gobierno: no se edita desde la aplicación.',
                N'días', N'Auditoría', 10);
END
GO
-- VAL ROL-12 (hallazgo H-03): las cuentas semilla de decano (decano.ingenieria@uco.edu.co) y coordinador (coordinador.sistemas@uco.edu.co)
-- deben tener ambito: el decano es titular de la Facultad de Ingenieria (Facultad.decano, lo mismo que deja usp_crear_decano_interno) y el
-- coordinador coordina Ingenieria de Sistemas (Programa.coordinador) y conserva su facultad (Coordinador.facultad, lo mismo que deja
-- usp_crear_coordinador_interno). Idempotente: solo actua si las filas semilla existen y la cuenta aun no tiene ese ambito.
DECLARE @idDecanoSemilla      UNIQUEIDENTIFIER = 'F1A2B3C4-0000-0000-0000-000000000001';
DECLARE @idCoordinadorSemilla UNIQUEIDENTIFIER = 'F1A2B3C4-0000-0000-0000-000000000002';
DECLARE @idFacultadSemilla    UNIQUEIDENTIFIER = 'A2B3C4D5-0000-0000-0000-000000000001';
DECLARE @idProgramaSemilla    UNIQUEIDENTIFIER = 'B2C3D4E5-0000-0000-0000-000000000001';

IF EXISTS (SELECT 1 FROM dbo.Decano WHERE id = @idDecanoSemilla)
   AND EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @idFacultadSemilla)
   AND NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE decano = @idDecanoSemilla)
    UPDATE dbo.Facultad SET decano = @idDecanoSemilla WHERE id = @idFacultadSemilla;

IF EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @idCoordinadorSemilla)
   AND EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @idFacultadSemilla)
    UPDATE dbo.Coordinador SET facultad = @idFacultadSemilla WHERE id = @idCoordinadorSemilla AND facultad IS NULL;

IF EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @idCoordinadorSemilla)
   AND EXISTS (SELECT 1 FROM dbo.Programa WHERE id = @idProgramaSemilla AND facultad = @idFacultadSemilla)
   AND NOT EXISTS (SELECT 1 FROM dbo.Programa WHERE coordinador = @idCoordinadorSemilla)
    UPDATE dbo.Programa SET coordinador = @idCoordinadorSemilla WHERE id = @idProgramaSemilla;
GO
PRINT 'MIGRACION 40 UP OK';
GO
