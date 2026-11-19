USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ATA D1 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C): parametros del aviso de falta por sesion (grupo AVISO_FALTA_SESION). Sin fila en
-- CatalogoParametroEdicion: no son editables por el administrador. Idempotente y sin pisar el valor administrado (WHEN MATCHED solo
-- actualiza tipoDato y valorDefecto).
--   HABILITADO             apaga el aviso sin desplegar (false => usp_consultar_sesiones_pendientes_aviso_falta devuelve 0 filas).
--   LOTE                   maximo de sesiones por pasada del job.
--   HORAS_MAXIMAS_ATRASO   no se avisan sesiones cuya ventana cerro hace mas de N horas (evita correos masivos al desplegar o recargar datos).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('AVISO_FALTA_SESION', 'HABILITADO',           N'true', 'BOOLEAN', N'true'),
    ('AVISO_FALTA_SESION', 'LOTE',                 N'50',   'INT',     N'50'),
    ('AVISO_FALTA_SESION', 'HORAS_MAXIMAS_ATRASO', N'24',   'INT',     N'24')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
