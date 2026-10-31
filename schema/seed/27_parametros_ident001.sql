USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- IDENT-001: parametros del dominio institucional del estudiante y de la verificacion del correo (idempotente).
-- El dominio incluye el '@' y es la unica fuente de verdad (SP, backend y frontend la leen de aqui).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE', N'@uco.edu.co', 'STRING', N'@uco.edu.co'),
    ('VERIFICACION_CORREO', 'TTL_HORAS', N'24', 'INT', N'24'),
    ('VERIFICACION_CORREO', 'REENVIO_ESPERA_MINUTOS', N'5', 'INT', N'5')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
