USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, HU171): mensajes de carga masiva de usuarios por CSV.
-- Idempotente (MERGE por codigo).
-- ============================================================================
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
