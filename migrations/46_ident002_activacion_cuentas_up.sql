-- ============================================================================
-- MIGRACION UP 46: IDENT-002 activacion de cuentas registradas por otra persona (sin contrasena en el registro)
--   Plantilla ACTIVACION_CUENTA (marcadores nombre, enlace, rol), mensajes VCE_009, ACT_001, ACT_002 y el SP de
--   elegibilidad del reenvio usp_consultar_reenvio_activacion_cuenta con su permiso. Sin cambios de tablas: el token
--   reutiliza dbo.TokenVerificacionCorreo (IDENT-001). Idempotente. Down: 46_ident002_activacion_cuentas_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- ============================================================================
-- IDENT-002: elegibilidad del reenvio del enlace de activacion de una cuenta registrada por otra persona (decano,
-- coordinador, docente o estudiante). Valida RBAC (ADMINISTRADOR, DECANO o COORDINADOR), que el usuario destino exista,
-- que su correo no este verificado (ACT_002: la cuenta ya esta activa) y la espera minima desde la ultima emision
-- (VCE_003, parametro VERIFICACION_CORREO/REENVIO_ESPERA_MINUTOS). El alcance jerarquico (decano: su facultad;
-- coordinador: su programa) lo resuelve la aplicacion con InstitutionalScopePort.canGestionarCuenta antes de invocarlo,
-- igual que el acceso a cuentas. Devuelve una fila con el usuario destino; el backend registra entonces el aviso.
-- Los rechazos se propagan con THROW 51000 y mensaje "DBCODE=<codigo>|..." (como usp_consultar_reenvio_verificacion_correo).
-- READ_QUERY_RESULTSET: NON_GOLDEN_PATH_EXTENSION (ver test/test_contract_closure.sql).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_reenvio_activacion_cuenta]
(
    @idUsuario         UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @correoConfirmado BIT;
    DECLARE @ultimaEmisionUtc DATETIME2(0);
    DECLARE @esperaMinutos    INT;
    DECLARE @codigoRechazo    VARCHAR(20) = NULL;
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: correlacion y parametros obligatorios
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuario IS NULL)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idUsuario',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 2: RBAC del ejecutor (quien puede registrar cuentas de otras personas)
    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioEjecutor,
            @codigoPerfilRequerido = 'ADMINISTRADOR,DECANO,COORDINADOR',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    -- PASO 3: usuario destino existente y activo (VCE_007)
    IF @estadoResultado = 1
    BEGIN
        SELECT @correoConfirmado = u.correoConfirmado FROM dbo.Usuario u WHERE u.id = @idUsuario AND u.estado = 1;
        IF @correoConfirmado IS NULL
            SET @codigoRechazo = 'VCE_007';
    END

    -- PASO 4: cuenta aun sin activar (ACT_002) y espera minima entre envios (VCE_003)
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
    BEGIN
        IF @correoConfirmado = 1
            SET @codigoRechazo = 'ACT_002';
        ELSE
        BEGIN
            SET @esperaMinutos = dbo.ufn_obtener_parametro_int(NULL, 'VERIFICACION_CORREO', 'REENVIO_ESPERA_MINUTOS');
            SELECT @ultimaEmisionUtc = MAX(t.fechaEmisionUtc) FROM dbo.TokenVerificacionCorreo t WHERE t.usuario = @idUsuario;
            IF @ultimaEmisionUtc IS NOT NULL AND @ultimaEmisionUtc > DATEADD(MINUTE, -@esperaMinutos, SYSUTCDATETIME())
                SET @codigoRechazo = 'VCE_003';
        END
    END

    IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = @codigoRechazo,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT @idUsuario AS idUsuario;
END;
GO

-- IDENT-002: activacion de cuentas registradas por otra persona (sin contrasena en el registro). Plantilla v1 y marcadores
-- del aviso ACTIVACION_CUENTA y mensajes VCE_009, ACT_001 y ACT_002 (usuario y tecnicos). Idempotente.
-- El marcador {enlace} lo resuelve el canal de correo al entregar (token de un solo uso, mismo mecanismo de IDENT-001).
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('ACTIVACION_CUENTA', 'nombre', N'Primer nombre de la persona registrada', N'Juan', 1),
    ('ACTIVACION_CUENTA', 'enlace', N'Enlace de activación de un solo uso (lo genera el sistema al enviar)', N'https://plataforma/activar-cuenta#token=...', 1),
    ('ACTIVACION_CUENTA', 'rol', N'Rol con el que fue registrada la cuenta', N'coordinador(a) de programa', 1)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET Target.descripcion = Source.descripcion, Target.ejemplo = Source.ejemplo, Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO
MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('ACTIVACION_CUENTA', 'es', 1,
     N'Active su cuenta en la plataforma de asistencia',
     N'Hola {nombre}, se registró una cuenta a su nombre como {rol} en la plataforma de asistencia de la Universidad Católica de Oriente. Para activarla y definir su contraseña abra el siguiente enlace: {enlace} . El enlace es de un solo uso y vence pronto; si vence, pida a quien lo registró que se lo envíe de nuevo. Si usted no esperaba este mensaje, ignórelo.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET Target.asunto = Source.asunto, Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('VCE_009', 'BUSINESS_ERROR', 'BAJO',  N'Defina su contraseña para activar su cuenta.'),
    ('ACT_001', 'SUCCESS',        'BAJO',  N'Se envió de nuevo el enlace de activación al correo institucional.'),
    ('ACT_002', 'BUSINESS_ERROR', 'BAJO',  N'La cuenta ya está activa; no es necesario enviar el enlace de activación.')
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
    ('VCE_009', 'BUSINESS_ERROR', 'BAJO',  N'Regla: la cuenta del proveedor de identidad no tiene credencial y la activación no incluyó contraseña; el token no se consumió.'),
    ('ACT_001', 'SUCCESS',        'BAJO',  N'Aviso ACTIVACION_CUENTA registrado en el outbox para el usuario indicado.'),
    ('ACT_002', 'BUSINESS_ERROR', 'BAJO',  N'Estado: Usuario.correoConfirmado ya es 1 (cuenta activada).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO


-- IDENT-002: permiso de ejecucion del reenvio del enlace de activacion. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_reenvio_activacion_cuenta', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_reenvio_activacion_cuenta] TO [rol_asistencias_runtime];
GO
PRINT 'MIGRACION 46 UP OK';
GO
