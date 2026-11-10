USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: catalogo de motivos con los que el coordinador cancela una sesion creada manualmente por el docente, y el
-- limite parametrizado de su observacion libre (SES_021). Idempotente: el catalogo se actualiza por id; el parametro no pisa el
-- valor administrado (WHEN MATCHED solo actualiza tipoDato y valorDefecto).
MERGE INTO [dbo].[MotivoCancelacionSesion] AS Target
USING (VALUES
    (CAST('7C1E0B10-5E51-4C0A-9B01-000000000001' AS UNIQUEIDENTIFIER), N'SESION_NO_AUTORIZADA',     N'Sesión no autorizada por la coordinación', 1),
    (CAST('7C1E0B10-5E51-4C0A-9B01-000000000002' AS UNIQUEIDENTIFIER), N'FUERA_DE_CALENDARIO',      N'Sesión fuera del calendario académico', 2),
    (CAST('7C1E0B10-5E51-4C0A-9B01-000000000003' AS UNIQUEIDENTIFIER), N'DUPLICADA',                N'Sesión duplicada', 3),
    (CAST('7C1E0B10-5E51-4C0A-9B01-000000000004' AS UNIQUEIDENTIFIER), N'CONFLICTO_INSTITUCIONAL',  N'Conflicto con una actividad institucional', 4),
    (CAST('7C1E0B10-5E51-4C0A-9B01-000000000005' AS UNIQUEIDENTIFIER), N'OTRO',                     N'Otro motivo', 5)
) AS Source (id, codigo, nombre, orden)
ON (Target.id = Source.id)
WHEN MATCHED THEN
    UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.orden = Source.orden
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, orden, estaActivo)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.orden, 1);
GO

MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('SESION', 'OBSERVACION_CANCELACION_COORDINADOR_MAXIMA', N'250', 'INT', N'250')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- CULM-001 / DEC-065 (2): estados de la solicitud de una sesion extraordinaria (aval previo del coordinador) y el prefijo del motivo con el que
-- se registra la cancelacion al rechazarla. Los SP resuelven los estados por bandera: esFinal = 0 (en espera), esFinal = 1 y esAprobada = 1
-- (aprobada), esFinal = 1 y esAprobada = 0 (rechazada). Idempotente: el catalogo se actualiza por id; el parametro no pisa el valor administrado.
MERGE INTO [dbo].[EstadoSolicitudSesion] AS Target
USING (VALUES
    (CAST('7C1E0B10-5E51-4C0A-9B02-000000000001' AS UNIQUEIDENTIFIER), N'PENDIENTE', N'Pendiente de aprobación', 1, CAST(0 AS BIT), CAST(0 AS BIT)),
    (CAST('7C1E0B10-5E51-4C0A-9B02-000000000002' AS UNIQUEIDENTIFIER), N'APROBADA',  N'Aprobada',               2, CAST(1 AS BIT), CAST(1 AS BIT)),
    (CAST('7C1E0B10-5E51-4C0A-9B02-000000000003' AS UNIQUEIDENTIFIER), N'RECHAZADA', N'Rechazada',              3, CAST(1 AS BIT), CAST(0 AS BIT))
) AS Source (id, codigo, nombre, orden, esFinal, esAprobada)
ON (Target.id = Source.id)
WHEN MATCHED THEN
    UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.orden = Source.orden, Target.esFinal = Source.esFinal, Target.esAprobada = Source.esAprobada
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, orden, esFinal, esAprobada)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.orden, Source.esFinal, Source.esAprobada);
GO

MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('SESION', 'PREFIJO_MOTIVO_SOLICITUD_RECHAZADA', N'Solicitud rechazada', 'STRING', N'Solicitud rechazada')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
