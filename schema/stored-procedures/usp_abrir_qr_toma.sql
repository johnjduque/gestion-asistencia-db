USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_abrir_qr_toma (CULM-001 B.2, HU175; CONTRACT §2.8.3, DEC-015)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idTokenAsistencia, idToma, idSesion, idGrupo,
-- fechaRotacionUtc, fechaExpiracionUtc, rotacionSegundos (NULL si estadoResultado = 0).
--
-- El docente titular emite el token/PIN de una toma QR ABIERTA dentro de la ventana con tolerancia. El backend genera el
-- token (32 bytes) y el PIN (6 digitos) y envia solo el SHA-256 del token. Modo no QR: AQR_003; toma cerrada: AQR_005;
-- PIN igual a un PIN activo o a un PIN anterior vigente (o hash repetido): AQR_006 sin escritura (el backend reintenta).
-- Cierra el token activo previo de la toma (re-proyeccion) e inserta el nuevo: emision = rotacion = ahora, expiracion =
-- fin de la sesion + ASISTENCIA/MARGEN_RETARDO_MINUTOS. Bloqueos: Sesion -> TomaAsistencia -> TokenAsistenciaToma.
-- Exito AQR_012.
-- ============================================================================
-- SKILLS-BD lote 12 (2026-11-26): PASO n, IF con BEGIN/END y lecturas sin bloqueo por vistas uv_* (antes, las tablas).
-- Las lecturas con UPDLOCK/HOLDLOCK y las escrituras siguen en las tablas. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_abrir_qr_toma]
(
    @idToma            UNIQUEIDENTIFIER,
    @tokenHash         VARBINARY(32),
    @pin               NCHAR(6),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTomaDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idToma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @toleranciaMinutos  INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS');
    DECLARE @margenMinutos      INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @rotacionSegundos   INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'ROTACION_SEGUNDOS');
    DECLARE @toleranciaSegundos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'TOLERANCIA_SEGUNDOS');
    DECLARE @idSesion           UNIQUEIDENTIFIER;
    DECLARE @idGrupo            UNIQUEIDENTIFIER;
    DECLARE @usaCodigoQr        BIT;
    DECLARE @tomaAbierta        BIT;
    DECLARE @idDocente          UNIQUEIDENTIFIER;
    DECLARE @idToken            UNIQUEIDENTIFIER;
    DECLARE @ahora              DATETIME2(0);
    DECLARE @expiracion         DATETIME2(0);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    -- PASO 1: Rotacion (60 s por defecto) y tolerancia del token anterior
    SET @rotacionSegundos = IIF(@rotacionSegundos IS NULL OR @rotacionSegundos < 1, 60, @rotacionSegundos);
    SET @toleranciaSegundos = IIF(@toleranciaSegundos IS NULL OR @toleranciaSegundos < 0, 0, @toleranciaSegundos);
    BEGIN TRY
        -- PASO 2: Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 3: Validar parametros obligatorios (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Validar perfil del ejecutor (DOCENTE)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Toma existente (TOM_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idSesion = t.idSesion, @idGrupo = s.idGrupo, @usaCodigoQr = m.usaCodigoQr
            FROM dbo.uv_toma_asistencia_registro t
            INNER JOIN dbo.uv_sesion_registro s ON s.id = t.idSesion
            INNER JOIN dbo.uv_modo_toma_asistencia m ON m.id = t.idModo
            WHERE t.id = @idTomaDefecto;

            IF @idSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_001', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        -- PASO 6: Titularidad del docente sobre la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idSesion, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 7: Token y PIN validos (GEN_002) y toma con QR (AQR_003)
        -- Hash SHA-256 de 32 bytes y PIN de 6 digitos (los genera el backend)
        IF @estadoResultado = 1
           AND (@tokenHash IS NULL OR DATALENGTH(@tokenHash) <> 32 OR @pin IS NULL OR LEN(@pin) <> 6 OR @pin LIKE N'%[^0-9]%')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'tokenHash/pin',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND @usaCodigoQr = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_003', @p_param1 = @idTomaDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 8: Transaccion propia o punto de guardado y ventana de registro
        IF @estadoResultado = 1
        BEGIN
            SELECT @idDocente = d.id FROM dbo.uv_docente_identidad d WHERE d.idUsuario = @idUsuarioEjecutorDefecto;

            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_abrir_qr_toma;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_validar_sesion_ventana_registro_interno
                @idSesion = @idSesion, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @toleranciaMinutos = @toleranciaMinutos, @margenMinutos = @margenMinutos;

            -- PASO 9: Bloquear la toma: debe seguir abierta (AQR_005)
            IF @estadoResultado = 1
            BEGIN
                SELECT @tomaAbierta = IIF(t.fechaCierreUtc IS NULL, 1, 0)
                FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.id = @idTomaDefecto;

                IF @tomaAbierta = 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_005', @p_param1 = @idTomaDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            -- PASO 10: PIN y hash unicos entre los tokens activos (AQR_006)
            IF @estadoResultado = 1
            BEGIN
                SET @ahora = SYSUTCDATETIME();
                IF EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma tk WITH (UPDLOCK, HOLDLOCK)
                           WHERE tk.fechaCierreUtc IS NULL
                             AND (tk.pin = @pin
                                  OR (tk.pinAnterior = @pin AND @ahora < tk.fechaExpiracionUtc
                                      AND @ahora < DATEADD(SECOND, @toleranciaSegundos, tk.fechaRotacionUtc))))
                   OR EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma tk WITH (UPDLOCK, HOLDLOCK)
                              WHERE tk.tokenHash = @tokenHash OR tk.tokenHashAnterior = @tokenHash)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_006', @p_param1 = @pin,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            -- PASO 11: Cerrar el token previo y emitir el nuevo (AQR_012)
            IF @estadoResultado = 1
            BEGIN
                SELECT @expiracion = CAST(DATEADD(MINUTE, IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos), s.fechaHoraFin) AS DATETIME2(0))
                FROM dbo.uv_sesion_registro s WHERE s.id = @idSesion;
                IF @expiracion <= @ahora
                BEGIN
                    SET @expiracion = DATEADD(SECOND, 1, @ahora);
                END

                UPDATE dbo.TokenAsistenciaToma SET fechaCierreUtc = @ahora WHERE toma = @idTomaDefecto AND fechaCierreUtc IS NULL;

                SET @idToken = NEWID();
                INSERT INTO dbo.TokenAsistenciaToma (id, toma, docenteEmisor, tokenHash, pin, tokenHashAnterior, pinAnterior,
                                                     fechaEmisionUtc, fechaRotacionUtc, fechaExpiracionUtc, fechaCierreUtc, idCorrelacionEmision)
                VALUES (@idToken, @idTomaDefecto, @idDocente, @tokenHash, @pin, NULL, NULL, @ahora, @ahora, @expiracion, NULL, @idCorrelacionDefecto);

                SET @p1 = CONVERT(NVARCHAR(36), @idToken);
                SET @p2 = CONVERT(NVARCHAR(36), @idTomaDefecto);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_012', @p_param1 = @p1, @p_param2 = @p2,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- PASO 12: Confirmar la transaccion propia
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    COMMIT TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                BEGIN
                    ROLLBACK TRANSACTION;
                END
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        -- PASO 13: Error: revertir lo propio, relanzar si la transaccion externa quedo condenada; si no, SYS_001
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_abrir_qr_toma;
        END

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- PASO 14: Resultado
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idTokenAsistencia       = IIF(@estadoResultado = 1, @idToken, NULL),
        idToma                  = IIF(@estadoResultado = 1, @idTomaDefecto, NULL),
        idSesion                = IIF(@estadoResultado = 1, @idSesion, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        fechaRotacionUtc        = IIF(@estadoResultado = 1, @ahora, NULL),
        fechaExpiracionUtc      = IIF(@estadoResultado = 1, @expiracion, NULL),
        rotacionSegundos        = IIF(@estadoResultado = 1, @rotacionSegundos, NULL);
END;
GO
