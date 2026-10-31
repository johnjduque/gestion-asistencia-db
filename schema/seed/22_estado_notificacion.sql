USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: EstadoNotificacion (NOTIF-001)
MERGE INTO [dbo].[EstadoNotificacion] AS Target
USING (VALUES
    ('PENDIENTE', 'Pendiente', 0),
    ('RESERVADA', 'Reservada', 0),
    ('FALLIDA_REINTENTABLE', 'Fallida reintentable', 0),
    ('ENTREGADA', 'Entregada', 1),
    ('FALLIDA_DEFINITIVA', 'Fallida definitiva', 1)
) AS Source (codigo, nombre, esTerminal)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.esTerminal = Source.esTerminal
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, esTerminal)
    VALUES (NEWID(), Source.codigo, Source.nombre, Source.esTerminal);
GO
