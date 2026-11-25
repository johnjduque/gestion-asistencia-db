USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_corregir_identidad_usuario_interno (HU159, decision de John 2026-11-05)
--
-- Nucleo comun de la correccion de identidad (nombres, apellidos y documento) de un usuario cuya jerarquia ya valido
-- la fachada (decano por el administrador, estudiante por el coordinador de su programa):
--   0. valida el documento sin escribir (un rechazo no necesita ROLLBACK);
--   1. instantanea de los valores anteriores (ufn_obtener_identidad_usuario_json);
--   2. nombres y apellidos con usp_actualizar_datos_usuario_interno (el correo se conserva);
--   3. documento con usp_corregir_documento_usuario_interno (aislado; apagable por parametro);
--   4. auditoria con el motivo y los valores anteriores y nuevos (usp_registrar_auditoria_identidad_interno).
-- El motivo lo valida la fachada (obligatorio siempre en este flujo). Sin transaccion propia.
-- SKILLS-BD lote 3 (2026-11-25): PASO n, TRY/CATCH (SYS_001; con transaccion abierta relanza el error para que el duenio la
-- revierta, como antes), lectura del correo desde uv_usuario_autenticacion y correlacion por defecto; mismo comportamiento.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_corregir_identidad_usuario_interno]
(
    @idUsuario               UNIQUEIDENTIFIER,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @motivo                  NVARCHAR(500),
    @accionAuditoria         VARCHAR(120),
    @tipoRecurso             VARCHAR(120),
    @idRecurso               UNIQUEIDENTIFIER,
    @rutaAuditoria           NVARCHAR(240),
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @identidadAnterior       NVARCHAR(MAX) = dbo.ufn_obtener_identidad_usuario_json(@idUsuario);
    DECLARE @correoActual            NVARCHAR(100) = (SELECT u.correo FROM dbo.uv_usuario_autenticacion u WHERE u.idUsuario = @idUsuario);
    DECLARE @documentoCambiado       BIT = 0;
    DECLARE @mensajeUsuarioInterno   NVARCHAR(4000);  -- SKILLS-BD lote 2: triplete del nucleo interno
    DECLARE @mensajeTecnicoInterno   NVARCHAR(4000);
    DECLARE @estadoInterno           BIT;
    DECLARE @mensajeErrorInterno     NVARCHAR(2048);
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: respuesta inicial
    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

    BEGIN TRY
        -- PASO 2: validar el documento sin escribir (un rechazo no necesita ROLLBACK)
        EXEC dbo.usp_corregir_documento_usuario_interno
            @idUsuario = @idUsuario,
            @idTipoIdIdentificacion = @idTipoIdIdentificacion,
            @numeroIdentificacion = @numeroIdentificacion,
            @motivo = @motivo,
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @documentoCambiado = @documentoCambiado OUTPUT,
            @soloValidar = 1;

        -- PASO 3: nombres y apellidos (el correo se conserva)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_actualizar_datos_usuario_interno
                @idUsuario = @idUsuario,
                @primerNombre = @primerNombre,
                @segundoNombre = @segundoNombre,
                @primerApellido = @primerApellido,
                @segundoApellido = @segundoApellido,
                @correo = @correoActual,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: documento
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_corregir_documento_usuario_interno
                @idUsuario = @idUsuario,
                @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                @numeroIdentificacion = @numeroIdentificacion,
                @motivo = @motivo,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @documentoCambiado = @documentoCambiado OUTPUT;
        END

        -- PASO 5: auditoria con el motivo y los valores anteriores y nuevos; su fallo aborta (THROW 52531)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_registrar_auditoria_identidad_interno
                @idUsuario = @idUsuario,
                @identidadAnterior = @identidadAnterior,
                @motivo = @motivo,
                @accion = @accionAuditoria,
                @tipoRecurso = @tipoRecurso,
                @idRecurso = @idRecurso,
                @ruta = @rutaAuditoria,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioInterno OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoInterno OUTPUT,
                @estadoResultado = @estadoInterno OUTPUT;
            IF @estadoInterno = 0
            BEGIN
                SET @mensajeErrorInterno = LEFT(@mensajeTecnicoInterno, 2048);
                THROW 52531, @mensajeErrorInterno, 1;
            END

            -- PASO 6: exito (IDE_002)
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'IDE_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        -- PASO 7: error (SYS_001). Sin transaccion propia: con una transaccion abierta se relanza el error original para que
        -- su duenio la revierta (antes del lote 3 el error salia sin capturar)
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        IF XACT_STATE() <> 0
        BEGIN
            THROW;
        END
    END CATCH
END;
GO
