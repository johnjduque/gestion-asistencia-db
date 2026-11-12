USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
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
