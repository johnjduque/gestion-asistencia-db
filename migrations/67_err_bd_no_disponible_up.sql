-- ============================================================================
-- MIGRACION UP 67: mensaje ERR_BD_NO_DISPONIBLE
--   El backend responde 503 con este codigo cuando la base de datos no responde (conexion caida o tiempo de espera agotado); antes
--   caia en el 500 generico. Siembra el texto de usuario y el tecnico (los mismos de schema/seed/63_val_mensajes_err_pendientes.sql).
--   Idempotente. Down: 67_err_bd_no_disponible_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 67 UP: ERR_BD_NO_DISPONIBLE';
GO
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('ERR_BD_NO_DISPONIBLE', 'TECHNICAL_ERROR', 'ALTO', N'El servicio no está disponible en este momento. Intenta de nuevo en unos minutos.')
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
    ('ERR_BD_NO_DISPONIBLE', 'TECHNICAL_ERROR', 'ALTO', N'La base de datos no respondió (conexión o tiempo de espera).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
PRINT 'MIGRACION 67 UP: completada';
GO
