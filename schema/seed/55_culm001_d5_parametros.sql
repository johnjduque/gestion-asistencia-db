USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, HU171): parametros de carga masiva por CSV y tipo doc defecto.
-- ============================================================================
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('CARGA_MASIVA', 'MAXIMO_FILAS',                  N'100',     'INT',    N'100'),
    ('CARGA_MASIVA', 'TAMANIO_MAXIMO_BYTES',          N'1048576', 'INT',    N'1048576'),
    ('CARGA_MASIVA', 'LIMITE_POR_MINUTO',             N'3',       'INT',    N'3'),
    ('IDENTIDAD',    'TIPO_IDENTIFICACION_DEFECTO',   N'CC',      'STRING', N'CC')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

IF OBJECT_ID('dbo.CatalogoParametroEdicion', 'U') IS NOT NULL
BEGIN
    MERGE INTO [dbo].[CatalogoParametroEdicion] AS Target
    USING (
        SELECT  p.id AS parametro, v.esEditable, v.valorMinimo, v.valorMaximo, v.valoresPermitidos, NULL AS parametroDebeSerMenorQue,
                v.etiqueta, v.descripcion, v.unidad, v.categoriaVisual, v.orden
        FROM (VALUES
            ('CARGA_MASIVA', 'MAXIMO_FILAS',         CONVERT(BIT, 1), CONVERT(DECIMAL(19,4), 1),     CONVERT(DECIMAL(19,4), 500),     NULL, N'Máximo de filas por carga',          N'Filas máximas de un archivo de carga masiva de cuentas.', N'filas',      N'Carga masiva', CONVERT(SMALLINT, 10)),
            ('CARGA_MASIVA', 'LIMITE_POR_MINUTO',    1,               1,                             20,                              NULL, N'Límite de cargas por minuto',         N'Cargas masivas por minuto permitidas a un mismo usuario.', N'por minuto', N'Carga masiva', 20),
            ('CARGA_MASIVA', 'TAMANIO_MAXIMO_BYTES', 1,               10240,                         2097152,                         NULL, N'Tamaño máximo del archivo de carga',  N'Bytes máximos del archivo CSV de una carga masiva.',       N'bytes',      N'Carga masiva', 30)
        ) AS v (grupo, clave, esEditable, valorMinimo, valorMaximo, valoresPermitidos, etiqueta, descripcion, unidad, categoriaVisual, orden)
        INNER JOIN [dbo].[CatalogoParametro] p ON p.grupo = v.grupo AND p.clave = v.clave
    ) AS Source
    ON (Target.parametro = Source.parametro)
    WHEN MATCHED THEN
        UPDATE SET Target.esEditable = Source.esEditable, Target.valorMinimo = Source.valorMinimo, Target.valorMaximo = Source.valorMaximo,
                   Target.valoresPermitidos = Source.valoresPermitidos, Target.etiqueta = Source.etiqueta,
                   Target.descripcion = Source.descripcion, Target.unidad = Source.unidad,
                   Target.categoriaVisual = Source.categoriaVisual, Target.orden = Source.orden
    WHEN NOT MATCHED THEN
        INSERT (parametro, esEditable, valorMinimo, valorMaximo, valoresPermitidos, parametroDebeSerMenorQue, etiqueta, descripcion, unidad, categoriaVisual, orden)
        VALUES (Source.parametro, Source.esEditable, Source.valorMinimo, Source.valorMaximo, Source.valoresPermitidos, Source.parametroDebeSerMenorQue,
                Source.etiqueta, Source.descripcion, Source.unidad, Source.categoriaVisual, Source.orden);
END
GO
