USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEC-073 (revision exhaustiva de formularios, 2026-11-13): parametros y mensajes de las reglas nuevas.
--   RECLAMO/RESPUESTA_*: al rechazar un reclamo la respuesta es obligatoria (10 a 500); al aprobar es opcional (hasta 500).
--   ASIGNATURA/CREDITOS_MAXIMO: los creditos van de 1 a 10 (el minimo sigue siendo ASI_001: mayores que cero).
--   VCE_008: correo institucional de decanos, coordinadores y docentes ({} = REGISTRO/DOMINIO_CORREO_ESTUDIANTE).
--   SES_028: la sesion empieza y termina el mismo dia en TIEMPO/ZONA_HORARIA_SQLSERVER (DEC-072).
--   ERR_CODIGO_GRUPO_INVALIDO: el codigo del grupo es un entero mayor que cero.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('RECLAMO',    'RESPUESTA_RECHAZO_LONGITUD_MINIMA', N'10',  'INT', N'10'),
    ('RECLAMO',    'RESPUESTA_LONGITUD_MAXIMA',         N'500', 'INT', N'500'),
    ('ASIGNATURA', 'CREDITOS_MAXIMO',                   N'10',  'INT', N'10')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('VCE_008', 'BUSINESS_ERROR', 'MEDIO', N'El correo debe ser institucional y terminar en {}.'),
    ('SES_028', 'BUSINESS_ERROR', 'MEDIO', N'La sesión debe terminar el mismo día en que empieza; no puede pasar de la medianoche.'),
    ('ASI_008', 'BUSINESS_ERROR', 'MEDIO', N'Los créditos de la asignatura no pueden superar {}.'),
    ('ERR_CODIGO_GRUPO_INVALIDO', 'BUSINESS_ERROR', 'MEDIO', N'El código del grupo debe ser un número entero mayor que cero.'),
    ('ERR_RESPUESTA_RECLAMO_LONGITUD_INVALIDA', 'BUSINESS_ERROR', 'MEDIO', N'Al rechazar, la respuesta es obligatoria ({} a {} caracteres); al aprobar es opcional (máx. {}).')
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
    ('VCE_008', 'BUSINESS_ERROR', 'MEDIO', N'Regla DEC-073: el correo de personal nuevo no cumple REGISTRO/DOMINIO_CORREO_ESTUDIANTE ({}).'),
    ('SES_028', 'BUSINESS_ERROR', 'MEDIO', N'Regla DEC-072: fechaHoraInicio y fechaHoraFin caen en dias distintos en la zona {}.'),
    ('ASI_008', 'BUSINESS_ERROR', 'MEDIO', N'Regla DEC-073: @creditos supera ASIGNATURA/CREDITOS_MAXIMO ({}) o el parametro no existe.'),
    ('ERR_CODIGO_GRUPO_INVALIDO', 'BUSINESS_ERROR', 'MEDIO', N'Regla DEC-073: @codigo nulo, cero o negativo ({}).'),
    ('ERR_RESPUESTA_RECLAMO_LONGITUD_INVALIDA', 'BUSINESS_ERROR', 'MEDIO', N'Regla DEC-073: respuestaDocente fuera de RECLAMO/RESPUESTA_RECHAZO_LONGITUD_MINIMA ({}) .. RESPUESTA_LONGITUD_MAXIMA ({}).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
