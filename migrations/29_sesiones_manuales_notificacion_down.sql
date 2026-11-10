-- ============================================================================
-- MIGRACION DOWN 29: CULM-001 / DEC-064 - retira las sesiones manuales con aviso y cancelacion por el coordinador
--   1. DROP de usp_cancelar_sesion_coordinador, usp_consultar_motivos_cancelacion_sesion y usp_consultar_destinatarios_sesion_manual.
--   2. Marca FALLIDA_DEFINITIVA las notificaciones pendientes de los dos tipos retirados (nunca DELETE, DEC-010) y borra sus plantillas
--      y marcadores creados por el sistema.
--   3. Borra los mensajes SES_018..SES_021 y el parametro de observacion solo si conserva su valor por defecto.
--   4. DROP de las vistas uv_sesion_manual y uv_motivo_cancelacion_sesion y de la tabla MotivoCancelacionSesion. Idempotente.
-- Las cancelaciones ya registradas en SesionCancelacion se conservan (son filas del tipo manual existente).
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 29 DOWN: retira sesiones manuales (aviso y cancelacion por el coordinador)';
GO
IF OBJECT_ID(N'dbo.usp_cancelar_sesion_coordinador', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_cancelar_sesion_coordinador;
GO
IF OBJECT_ID(N'dbo.usp_consultar_motivos_cancelacion_sesion', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_motivos_cancelacion_sesion;
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_manual', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_destinatarios_sesion_manual;
GO

DECLARE @idFallidaDefinitiva UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_DEFINITIVA');
IF @idFallidaDefinitiva IS NOT NULL
    UPDATE n
    SET n.idEstado = @idFallidaDefinitiva,
        n.codigoError = 'TIPO_NOTIFICACION_RETIRADO',
        n.detalleError = N'CULM-001 DEC-064 revertido (migracion 29 down): plantilla de sesion manual retirada.'
    FROM dbo.NotificacionSaliente n
    INNER JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado
    WHERE n.tipo IN ('SESION_MANUAL_CREADA_ESTUDIANTE', 'SESION_MANUAL_CREADA_COORDINADOR') AND e.esTerminal = 0;

DELETE FROM dbo.PlantillaNotificacion
WHERE tipo IN ('SESION_MANUAL_CREADA_ESTUDIANTE', 'SESION_MANUAL_CREADA_COORDINADOR') AND creadoPor IS NULL;
DELETE FROM dbo.PlantillaNotificacionMarcador
WHERE tipo IN ('SESION_MANUAL_CREADA_ESTUDIANTE', 'SESION_MANUAL_CREADA_COORDINADOR')
  AND NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion p WHERE p.tipo = PlantillaNotificacionMarcador.tipo);

DELETE FROM dbo.CatalogoParametro
WHERE grupo = 'SESION' AND clave = 'OBSERVACION_CANCELACION_COORDINADOR_MAXIMA' AND ISNULL(valor, N'') = ISNULL(valorDefecto, N'');
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('SES_018', 'SES_019', 'SES_020', 'SES_021');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('SES_018', 'SES_019', 'SES_020', 'SES_021');
GO

IF OBJECT_ID(N'dbo.uv_sesion_manual', N'V') IS NOT NULL DROP VIEW dbo.uv_sesion_manual;
GO
IF OBJECT_ID(N'dbo.uv_motivo_cancelacion_sesion', N'V') IS NOT NULL DROP VIEW dbo.uv_motivo_cancelacion_sesion;
GO
IF OBJECT_ID(N'dbo.MotivoCancelacionSesion', N'U') IS NOT NULL DROP TABLE dbo.MotivoCancelacionSesion;
GO
PRINT 'MIGRACION 29 DOWN OK';
GO
