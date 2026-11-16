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
