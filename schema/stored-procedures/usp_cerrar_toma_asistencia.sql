USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cerrar_toma_asistencia (CULM-001 B.2, HU175; CONTRACT §2.8.2, DEC-013, [SUPUESTO-B-08])
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idToma, idSesion, idGrupo, fechaCierreUtc,
-- totalAusentesMarcados, totalFaltantes, yaEstabaCerrada (NULL si estadoResultado = 0).
--
-- El docente titular cierra una toma (no exige ventana para cerrar). Ya cerrada: exito idempotente TOM_011
-- (yaEstabaCerrada = 1, sin escrituras). Si no: el cierre lo hace usp_cerrar_toma_interno (ATA D9, compartido con
-- usp_abrir_toma_asistencia): cierra el token QR activo de la toma; con @marcarAusentes = 1 (NULL =>
-- ModoTomaAsistencia.marcaAusentesAlCerrar: 1 en MANUAL y en QR segun el seed 35) y la ventana con margen todavia abierta, inserta SJC a las
-- matriculas activas sin detalle en la toma (usp_marcar_ausentes_toma_interno); vencida la ventana se cierra sin marcar.
-- totalFaltantes = filas de uv_faltantes_toma despues del cierre. Bloqueos: Sesion -> TomaAsistencia -> TokenAsistenciaToma.
-- Exito TOM_009.
-- VAL-pendientes-john PRU-15: una toma de una sesion de un periodo cerrado por el cierre masivo no se cierra a mano (PER_008, despues
-- de la titularidad); las tomas que queden abiertas las cierra usp_cerrar_tomas_vencidas, que no aplica esta regla.
-- ============================================================================
-- SKILLS-BD lote 12 (2026-11-26): PASO n, IF con BEGIN/END y lecturas sin bloqueo por vistas uv_* (antes, las tablas).
-- Las lecturas con UPDLOCK/HOLDLOCK y las escrituras siguen en las tablas. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_cerrar_toma_asistencia]
(
    @idToma            UNIQUEIDENTIFIER,
    @marcarAusentes    BIT = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTomaDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idToma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeDescartado       NVARCHAR(4000);
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @idSesion          UNIQUEIDENTIFIER;
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @fechaCierrePrevia DATETIME2(0);
    DECLARE @fechaCierre       DATETIME2(0);
    DECLARE @totalMarcados     INT = 0;
    DECLARE @totalFaltantes    INT;
    DECLARE @yaEstabaCerrada   BIT = 0;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
    DECLARE @mensajeUsuarioInterno   NVARCHAR(4000);  -- SKILLS-BD lote 2: triplete de usp_cerrar_toma_interno
    DECLARE @mensajeTecnicoInterno   NVARCHAR(4000);
    DECLARE @estadoInterno           BIT;
    DECLARE @mensajeErrorInterno     NVARCHAR(2048);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validar parametros obligatorios (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar perfil del ejecutor (DOCENTE)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- Toma existente (TOM_001) y titularidad sobre su sesion
        -- PASO 4: Toma existente (TOM_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idSesion = t.idSesion, @idGrupo = s.idGrupo
            FROM dbo.uv_toma_asistencia_registro t INNER JOIN dbo.uv_sesion_registro s ON s.id = t.idSesion
            WHERE t.id = @idTomaDefecto;

            IF @idSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_001', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        -- PASO 5: Titularidad del docente sobre la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idSesion, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 6: Periodo abierto (PER_008)
        -- VAL-pendientes-john PRU-15: la toma de una sesion de un periodo cerrado por el cierre masivo no cambia (PER_008)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_periodo_abierto_sesion_interno
                @idSesion = @idSesion, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 7: Transaccion propia o punto de guardado
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cerrar_toma;
                SET @savepointCreado = 1;
            END

            -- PASO 8: Bloquear sesion y toma; cerrar la toma (TOM_009) o informar que ya estaba cerrada (TOM_011)
            -- Bloqueo de la sesion (sin exigir ventana para cerrar) y luego de la toma
            SELECT @idGrupo = s.grupo FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK) WHERE s.id = @idSesion;
            SELECT @fechaCierrePrevia = t.fechaCierreUtc, @totalMarcados = t.totalAusentesMarcados
            FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
            WHERE t.id = @idTomaDefecto;

            IF @fechaCierrePrevia IS NOT NULL
            BEGIN
                SET @yaEstabaCerrada = 1;
                SET @fechaCierre = @fechaCierrePrevia;
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_011', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                EXEC dbo.usp_cerrar_toma_interno
                    @idToma = @idTomaDefecto, @idSesion = @idSesion, @idGrupo = @idGrupo, @marcarAusentes = @marcarAusentes,
                    @idCorrelacion = @idCorrelacionDefecto, @totalAusentesMarcados = @totalMarcados OUTPUT, @fechaCierreUtc = @fechaCierre OUTPUT,
                    @mensajeUsuarioResultado = @mensajeUsuarioInterno OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoInterno OUTPUT,
                    @estadoResultado = @estadoInterno OUTPUT;
                IF @estadoInterno = 0
                BEGIN
                    SET @mensajeErrorInterno = LEFT(@mensajeTecnicoInterno, 2048);
                    THROW 52522, @mensajeErrorInterno, 1;
                END

                SET @p1 = CONVERT(NVARCHAR(20), @totalMarcados);
                SET @p2 = CONVERT(NVARCHAR(36), @idTomaDefecto);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_009', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeDescartado OUTPUT;
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_009', @p_param1 = @p2, @p_param2 = @p1,
                    @mensajeUsuarioResultado = @mensajeDescartado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- PASO 9: Faltantes de la toma y confirmacion
            SELECT @totalFaltantes = COUNT(1) FROM dbo.uv_faltantes_toma f WHERE f.idToma = @idTomaDefecto;

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
        -- PASO 10: Error: revertir lo propio, relanzar si la transaccion externa quedo condenada; si no, SYS_001
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
            ROLLBACK TRANSACTION sp_cerrar_toma;
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

    -- PASO 11: Resultado
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idToma                  = IIF(@estadoResultado = 1, @idTomaDefecto, NULL),
        idSesion                = IIF(@estadoResultado = 1, @idSesion, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        fechaCierreUtc          = IIF(@estadoResultado = 1, @fechaCierre, NULL),
        totalAusentesMarcados   = IIF(@estadoResultado = 1, @totalMarcados, NULL),
        totalFaltantes          = IIF(@estadoResultado = 1, @totalFaltantes, NULL),
        yaEstabaCerrada         = IIF(@estadoResultado = 1, @yaEstabaCerrada, NULL);
END;
GO
