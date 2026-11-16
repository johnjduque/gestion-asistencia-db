-- ============================================================================
-- MIGRACION UP 47: REA-02 (VAL-oleada9), mensaje ERR_ALMACENAMIENTO_NO_DISPONIBLE
--   El backend responde 503 con este codigo cuando MinIO no responde (o su circuit breaker esta abierto) al subir o descargar
--   un soporte; antes caia en el 500 generico. Siembra el texto de usuario y el tecnico (los mismos de
--   schema/seed/63_val_mensajes_err_pendientes.sql). Idempotente. Down: 47_val_mensaje_almacenamiento_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 47 UP: REA-02 (ERR_ALMACENAMIENTO_NO_DISPONIBLE)';
GO
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('ERR_ALMACENAMIENTO_NO_DISPONIBLE', 'TECHNICAL_ERROR', 'ALTO', N'El almacenamiento de soportes no está disponible en este momento. Intente de nuevo en unos minutos.')
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
    ('ERR_ALMACENAMIENTO_NO_DISPONIBLE', 'TECHNICAL_ERROR', 'ALTO', N'Backend (SERVICE_UNAVAILABLE, ArchivoErrorCode): MinIO no respondio o el circuit breaker fileStorage esta abierto al subir o descargar un soporte; 503 sin registrar metadata (REA-02).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
PRINT 'MIGRACION 47 UP: completada';
GO
