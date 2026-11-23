USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEC-081 (2026-11-21): parametros del receso academico y del tipo de cancelacion por festivo. Patron 34_parametros_sesion_festivos.sql:
-- idempotente y sin pisar el valor administrado (WHEN MATCHED solo actualiza tipoDato y valorDefecto). Migracion 68.
--   RECESO/PREFIJO_MOTIVO_CANCELACION: prefijo del motivo de la cancelacion automatica (motivo final = prefijo + motivo del receso).
--   RECESO/CODIGO_TIPO_CANCELACION y SESION/CODIGO_TIPO_CANCELACION_FESTIVO: codigo de TipoCancelacionSesion con que cada mecanismo
--   automatico cancela sus sesiones (ya no se distingue por esAutomatica = 1, que ahora cubre dos tipos).
--   RECESO/MOTIVO_LONGITUD_MAXIMA: largo maximo del motivo (PeriodoRecesoAcademico.motivo es NVARCHAR(200)).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('RECESO',   'PREFIJO_MOTIVO_CANCELACION', N'Receso académico: ', 'STRING', N'Receso académico: '),
    ('RECESO',   'CODIGO_TIPO_CANCELACION',    N'RECESO',             'STRING', N'RECESO'),
    ('RECESO',   'MOTIVO_LONGITUD_MAXIMA',     N'200',                'INT',    N'200'),
    ('SESION',   'CODIGO_TIPO_CANCELACION_FESTIVO', N'FESTIVO',       'STRING', N'FESTIVO')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
