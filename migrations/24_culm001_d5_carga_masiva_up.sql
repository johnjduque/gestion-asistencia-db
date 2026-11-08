-- ============================================================================
-- MIGRACION UP 24: CULM-001 D.5 - carga masiva CSV de roles no estudiantes, HU171 (CONTRACT D §6)
-- Crea tabla JerarquiaAltaUsuario, vista uv_jerarquia_alta_usuario, SP usp_validar_carga_masiva_usuarios,
-- actualiza firmas de usp_crear_coordinador y usp_crear_decano, siembra mensajes CMA_* y parametros.
-- Idempotente. Down: 24_culm001_d5_carga_masiva_down.sql.
-- ============================================================================
PRINT 'MIGRACION 24 UP: carga masiva de usuarios (D.5)';
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- 1. Tabla JerarquiaAltaUsuario
IF OBJECT_ID('dbo.[JerarquiaAltaUsuario]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.JerarquiaAltaUsuario (
        id             UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_JerarquiaAltaUsuario PRIMARY KEY CLUSTERED,
        perfilEjecutor UNIQUEIDENTIFIER NOT NULL,
        perfilDestino  UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT UQ_JerarquiaAltaUsuario_Pares UNIQUE (perfilEjecutor, perfilDestino)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_JerarquiaAltaUsuario_PerfilEjecutor')
BEGIN
    ALTER TABLE [dbo].[JerarquiaAltaUsuario] ADD CONSTRAINT [FK_JerarquiaAltaUsuario_PerfilEjecutor] FOREIGN KEY ([perfilEjecutor]) REFERENCES [dbo].[Perfil] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_JerarquiaAltaUsuario_PerfilDestino')
BEGIN
    ALTER TABLE [dbo].[JerarquiaAltaUsuario] ADD CONSTRAINT [FK_JerarquiaAltaUsuario_PerfilDestino] FOREIGN KEY ([perfilDestino]) REFERENCES [dbo].[Perfil] ([id]);
END
GO

-- 2. Vista uv_jerarquia_alta_usuario
CREATE OR ALTER VIEW dbo.uv_jerarquia_alta_usuario
AS
SELECT 
    j.id,
    j.perfilEjecutor,
    pe.codigo AS codigoPerfilEjecutor,
    pe.nombre AS nombrePerfilEjecutor,
    j.perfilDestino,
    pd.codigo AS codigoPerfilDestino,
    pd.nombre AS nombrePerfilDestino
FROM dbo.JerarquiaAltaUsuario j
INNER JOIN dbo.Perfil pe ON pe.id = j.perfilEjecutor
INNER JOIN dbo.Perfil pd ON pd.id = j.perfilDestino;
GO

-- 3. Mensajes CMA_001..CMA_015
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('CMA_001', 'VALIDATION_ERROR', 'MEDIO', N'El archivo supera {} filas.'),
    ('CMA_002', 'VALIDATION_ERROR', 'MEDIO', N'El archivo supera el tamaño permitido.'),
    ('CMA_003', 'BUSINESS_ERROR',   'ALTO',  N'El archivo cambió desde la validación. Valídalo de nuevo.'),
    ('CMA_004', 'VALIDATION_ERROR', 'MEDIO', N'La cabecera no coincide con la plantilla: {}.'),
    ('CMA_005', 'VALIDATION_ERROR', 'BAJO',  N'Número de documento inválido.'),
    ('CMA_006', 'VALIDATION_ERROR', 'BAJO',  N'Código de {} desconocido: {}.'),
    ('CMA_007', 'BUSINESS_ERROR',   'MEDIO', N'«{}» no está en tu ámbito.'),
    ('CMA_008', 'BUSINESS_ERROR',   'MEDIO', N'El documento y el correo corresponden a personas distintas.'),
    ('CMA_009', 'BUSINESS_ERROR',   'ALTO',  N'Tu rol no puede cargar este tipo de cuentas.'),
    ('CMA_010', 'VALIDATION_ERROR', 'BAJO',  N'Fila repetida en el archivo (línea {}).'),
    ('CMA_011', 'VALIDATION_ERROR', 'MEDIO', N'Valor no permitido en la columna {}.'),
    ('CMA_012', 'VALIDATION_ERROR', 'BAJO',  N'Falta la clave inicial para una persona nueva.'),
    ('CMA_013', 'VALIDATION_ERROR', 'MEDIO', N'El archivo no es un CSV UTF-8 válido.'),
    ('CMA_014', 'BUSINESS_ERROR',   'MEDIO', N'Has superado el número de cargas por minuto.'),
    ('CMA_015', 'SUCCESS',          'BAJO',  N'Carga procesada: {} creadas, {} ya existentes, {} con error.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('CMA_001', 'VALIDATION_ERROR', 'MEDIO', N'HU171: cantidad de filas {} supera CARGA_MASIVA/MAXIMO_FILAS ({}).'),
    ('CMA_002', 'VALIDATION_ERROR', 'MEDIO', N'HU171: tamano de archivo {} bytes supera CARGA_MASIVA/TAMANIO_MAXIMO_BYTES ({}).'),
    ('CMA_003', 'BUSINESS_ERROR',   'ALTO',  N'HU171: huella SHA-256 no coincide con la validada previamente.'),
    ('CMA_004', 'VALIDATION_ERROR', 'MEDIO', N'HU171: cabecera del CSV no valida o incompleta: {}.'),
    ('CMA_005', 'VALIDATION_ERROR', 'BAJO',  N'HU171: numero de documento no es un entero positivo en rango INT.'),
    ('CMA_006', 'VALIDATION_ERROR', 'BAJO',  N'HU171: codigo de {} ''{}'' no existe en catalogo.'),
    ('CMA_007', 'BUSINESS_ERROR',   'MEDIO', N'HU171: entidad ''{}'' no pertenece al ambito de custodia del ejecutor.'),
    ('CMA_008', 'BUSINESS_ERROR',   'MEDIO', N'HU171: documento y correo corresponden a diferentes personas existentes.'),
    ('CMA_009', 'BUSINESS_ERROR',   'ALTO',  N'HU171: jerarquia no permitida en JerarquiaAltaUsuario para este perfil ejecutor y destino.'),
    ('CMA_010', 'VALIDATION_ERROR', 'BAJO',  N'HU171: documento o correo repetido respecto a la linea {}.'),
    ('CMA_011', 'VALIDATION_ERROR', 'MEDIO', N'HU171: intento de inyeccion de formulas o caracteres no permitidos en columna {}.'),
    ('CMA_012', 'VALIDATION_ERROR', 'BAJO',  N'HU171: persona nueva requiere clave inicial valida segun PasswordRegistroRule.'),
    ('CMA_013', 'VALIDATION_ERROR', 'MEDIO', N'HU171: codificacion del archivo no es UTF-8 valida o archivo malformado.'),
    ('CMA_014', 'BUSINESS_ERROR',   'MEDIO', N'HU171: tasa de peticiones supera CARGA_MASIVA/LIMITE_POR_MINUTO.'),
    ('CMA_015', 'SUCCESS',          'BAJO',  N'HU171: resultado de ejecucion: creadas={}, yaExistentes={}, conError={}.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- 4. Parametros CARGA_MASIVA e IDENTIDAD
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

-- 5. Semilla JerarquiaAltaUsuario
MERGE INTO dbo.JerarquiaAltaUsuario AS Target
USING (
    SELECT 
        NEWID() AS id,
        pe.id AS perfilEjecutor,
        pd.id AS perfilDestino
    FROM (VALUES
        ('CD', 'DO'),
        ('DE', 'CD'),
        ('AD', 'DE')
    ) AS v(codEjecutor, codDestino)
    INNER JOIN dbo.Perfil pe ON (pe.codigo = v.codEjecutor OR UPPER(pe.nombre) = CASE v.codEjecutor WHEN 'CD' THEN 'COORDINADOR' WHEN 'DE' THEN 'DECANO' WHEN 'AD' THEN 'ADMINISTRADOR' END)
    INNER JOIN dbo.Perfil pd ON (pd.codigo = v.codDestino OR UPPER(pd.nombre) = CASE v.codDestino WHEN 'DO' THEN 'DOCENTE' WHEN 'CD' THEN 'COORDINADOR' WHEN 'DE' THEN 'DECANO' END)
) AS Source
ON (Target.perfilEjecutor = Source.perfilEjecutor AND Target.perfilDestino = Source.perfilDestino)
WHEN NOT MATCHED THEN
    INSERT (id, perfilEjecutor, perfilDestino)
    VALUES (Source.id, Source.perfilEjecutor, Source.perfilDestino);
GO

-- 6. Actualizar usp_crear_coordinador
:r $(MIGDIR)/../schema/stored-procedures/usp_crear_coordinador.sql
GO

-- 7. Actualizar usp_crear_decano
:r $(MIGDIR)/../schema/stored-procedures/usp_crear_decano.sql
GO

-- 8. Crear usp_validar_carga_masiva_usuarios
:r $(MIGDIR)/../schema/stored-procedures/usp_validar_carga_masiva_usuarios.sql
GO

-- 9. Permisos
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_validar_carga_masiva_usuarios] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.uv_jerarquia_alta_usuario', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_jerarquia_alta_usuario] TO [rol_asistencias_runtime];
GO
