USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.8): parametros de alertas de inasistencia, revision de cancelacion y estados de matricula.
-- Idempotente: si ya existen, no se sobrescribe el valor vigente.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('ALERTA_INASISTENCIA', 'HABILITADA',                    N'true', 'BOOLEAN', N'true'),
    ('ALERTA_INASISTENCIA', 'LOTE_EVALUACION_AUTOMATICA',    N'50',   'INT',     N'50'),
    ('ALERTA_INASISTENCIA', 'SOLAPE_MARCA_SEGUNDOS',         N'120',  'INT',     N'120'),
    ('ALERTA_INASISTENCIA', 'MAXIMO_LECTURA_POR_SOLICITUD',  N'100',  'INT',     N'100'),
    ('REVISION_CANCELACION', 'MOTIVO_LONGITUD_MINIMA',       N'10',   'INT',     N'10'),
    ('REVISION_CANCELACION', 'MOTIVO_LONGITUD_MAXIMA',       N'500',  'INT',     N'500'),
    ('MATRICULA',           'ESTADO_CANCELADA_INASISTENCIA', N'CI',  'STRING',  N'CI'),
    ('MATRICULA',           'ESTADO_FINALIZADA',             N'F',   'STRING',  N'F')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
