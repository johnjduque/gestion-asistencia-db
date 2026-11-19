-- ============================================================================
-- MIGRACION DOWN 53: retira ATA D9 (nueva toma cierra la anterior)
--   Restaura el texto de develop (antes de la 53) de usp_abrir_toma_asistencia (TOM_003 con una toma abierta, sin columnas *Anterior) y de
--   usp_cerrar_toma_asistencia (cierre en linea) y elimina usp_internal_cerrar_toma. Los permisos de los SP publicos se conservan. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 53 DOWN: retira ATA D9';
GO
-- ---- schema/stored-procedures/usp_cerrar_toma_asistencia.sql (texto de develop antes de la 53)
-- ============================================================================
-- usp_cerrar_toma_asistencia (CULM-001 B.2, HU175; CONTRACT §2.8.2, DEC-013, [SUPUESTO-B-08])
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idToma, idSesion, idGrupo, fechaCierreUtc,
-- totalAusentesMarcados, totalFaltantes, yaEstabaCerrada (NULL si estadoResultado = 0).
--
-- El docente titular cierra una toma (no exige ventana para cerrar). Ya cerrada: exito idempotente TOM_011
-- (yaEstabaCerrada = 1, sin escrituras). Si no: cierra el token QR activo de la toma; con @marcarAusentes = 1 (NULL =>
-- ModoTomaAsistencia.marcaAusentesAlCerrar: MANUAL 0, QR 1) y la ventana con margen todavia abierta, inserta SJC a las
-- matriculas activas sin detalle en la toma (usp_internal_marcar_ausentes_toma); vencida la ventana se cierra sin marcar.
-- totalFaltantes = filas de uv_faltantes_toma despues del cierre. Bloqueos: Sesion -> TomaAsistencia -> TokenAsistenciaToma.
-- Exito TOM_009.
-- VAL-pendientes-john PRU-15: una toma de una sesion de un periodo cerrado por el cierre masivo no se cierra a mano (PER_008, despues
-- de la titularidad); las tomas que queden abiertas las cierra usp_cerrar_tomas_vencidas, que no aplica esta regla.
-- ============================================================================
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
    DECLARE @marcaPorModo      BIT;
    DECLARE @marcar            BIT;
    DECLARE @ventanaAbierta    BIT;
    DECLARE @idEstadoCerrada   UNIQUEIDENTIFIER;
    DECLARE @fechaCierre       DATETIME2(0);
    DECLARE @totalMarcados     INT = 0;
    DECLARE @totalFaltantes    INT;
    DECLARE @yaEstabaCerrada   BIT = 0;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- Toma existente (TOM_001) y titularidad sobre su sesion
        IF @estadoResultado = 1
        BEGIN
            SELECT @idSesion = t.sesion, @idGrupo = s.grupo
            FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion
            WHERE t.id = @idTomaDefecto;

            IF @idSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_001', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idSesion, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- VAL-pendientes-john PRU-15: la toma de una sesion de un periodo cerrado por el cierre masivo no cambia (PER_008)
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_periodo_abierto_sesion_interno
                @idSesion = @idSesion, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            SELECT @idEstadoCerrada = e.id FROM dbo.EstadoTomaAsistencia e WHERE e.estaAbierta = 0;
            IF @idEstadoCerrada IS NULL
                THROW 52511, 'CULM001_B2_CATALOGO_INCONSISTENTE: falta EstadoTomaAsistencia(estaAbierta = 0).', 1;

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

            -- Bloqueo de la sesion (sin exigir ventana para cerrar) y luego de la toma
            SELECT @idGrupo = s.grupo FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK) WHERE s.id = @idSesion;
            SELECT @fechaCierrePrevia = t.fechaCierreUtc, @marcaPorModo = m.marcaAusentesAlCerrar, @totalMarcados = t.totalAusentesMarcados
            FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.ModoTomaAsistencia m ON m.id = t.modo
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
                SET @fechaCierre = SYSUTCDATETIME();
                SET @marcar = IIF(@marcarAusentes IS NULL, @marcaPorModo, @marcarAusentes);
                SELECT @ventanaAbierta = v.ventanaAbierta FROM dbo.uv_sesion_estado v WHERE v.idSesion = @idSesion;
                SET @totalMarcados = 0;

                UPDATE dbo.TokenAsistenciaToma SET fechaCierreUtc = @fechaCierre
                WHERE toma = @idTomaDefecto AND fechaCierreUtc IS NULL;

                IF @marcar = 1 AND @ventanaAbierta = 1
                    EXEC dbo.usp_internal_marcar_ausentes_toma
                        @idToma = @idTomaDefecto, @idSesion = @idSesion, @idGrupo = @idGrupo,
                        @fechaRegistroUtc = @fechaCierre, @totalMarcados = @totalMarcados OUTPUT;

                UPDATE dbo.TomaAsistencia
                SET estado = @idEstadoCerrada,
                    fechaCierreUtc = IIF(@fechaCierre < fechaAperturaUtc, fechaAperturaUtc, @fechaCierre),
                    totalAusentesMarcados = @totalMarcados,
                    idCorrelacionCierre = @idCorrelacionDefecto
                WHERE id = @idTomaDefecto;

                SET @p1 = CONVERT(NVARCHAR(20), @totalMarcados);
                SET @p2 = CONVERT(NVARCHAR(36), @idTomaDefecto);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_009', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeDescartado OUTPUT;
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_009', @p_param1 = @p2, @p_param2 = @p1,
                    @mensajeUsuarioResultado = @mensajeDescartado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            SELECT @totalFaltantes = COUNT(1) FROM dbo.uv_faltantes_toma f WHERE f.idToma = @idTomaDefecto;
            SELECT @fechaCierre = t.fechaCierreUtc FROM dbo.TomaAsistencia t WHERE t.id = @idTomaDefecto;

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_cerrar_toma;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

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
-- ---- schema/stored-procedures/usp_abrir_toma_asistencia.sql (texto de develop antes de la 53)
-- ============================================================================
-- usp_abrir_toma_asistencia (CULM-001 B.2, HU175; CONTRACT §2.8.2, DEC-013, DEC-014, [SUPUESTO-B-07])
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idToma, numero, codigoModo, usaCodigoQr,
-- fechaAperturaUtc, ventanaCierreUtc, totalTomasSesion, horasToma (NULL si estadoResultado = 0).
--
-- El docente titular abre una toma MANUAL o QR en una sesion dentro de la ventana [inicio - ASISTENCIA/TOLERANCIA_MINUTOS,
-- fin + ASISTENCIA/MARGEN_RETARDO_MINUTOS). Una sola toma abierta por sesion (TOM_003) y como maximo
-- TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION (TOM_004). El modo se resuelve contra ModoTomaAsistencia.codigo (TOM_002); el estado
-- ABIERTA por la bandera estaAbierta = 1. Bloqueos: Sesion (ventana) -> TomaAsistencia. Las ramas de rechazo no escriben y
-- solo confirman la transaccion propia (compatible con INSERT ... EXEC). Exito TOM_008.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_abrir_toma_asistencia]
(
    @idSesion          UNIQUEIDENTIFIER,
    @codigoModo        NVARCHAR(20),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeDescartado       NVARCHAR(4000);
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @toleranciaMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS');
    DECLARE @margenMinutos     INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @maximoTomas       INT = dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'MAXIMO_TOMAS_POR_SESION');
    DECLARE @codigoModoLimpio  NVARCHAR(20) = UPPER(TRIM(@codigoModo));
    DECLARE @idModo            UNIQUEIDENTIFIER;
    DECLARE @codigoModoResuelto NVARCHAR(20);
    DECLARE @usaCodigoQr       BIT;
    DECLARE @idEstadoAbierta   UNIQUEIDENTIFIER;
    DECLARE @idDocente         UNIQUEIDENTIFIER;
    DECLARE @idTomaAbierta     UNIQUEIDENTIFIER;
    DECLARE @totalTomas        INT;
    DECLARE @numero            SMALLINT;
    DECLARE @idToma            UNIQUEIDENTIFIER;
    DECLARE @fechaApertura     DATETIME2(0);
    DECLARE @ventanaCierre     DATETIME2(0);
    DECLARE @horasToma         DECIMAL(12,6);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC (DOCENTE), sesion existente y titularidad
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idSesionDefecto, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 3: modo de la toma (TOM_002) y estado ABIERTA por bandera
        IF @estadoResultado = 1
        BEGIN
            SELECT @idModo = m.id, @codigoModoResuelto = m.codigo, @usaCodigoQr = m.usaCodigoQr
            FROM dbo.ModoTomaAsistencia m
            WHERE m.codigo = @codigoModoLimpio;
            SELECT @idEstadoAbierta = e.id FROM dbo.EstadoTomaAsistencia e WHERE e.estaAbierta = 1;
            SELECT @idDocente = d.id FROM dbo.Docente d WHERE d.usuario = @idUsuarioEjecutorDefecto;

            IF @idModo IS NULL
            BEGIN
                SET @p1 = IIF(@codigoModo IS NULL, N'NULL', @codigoModo);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_002', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @idEstadoAbierta IS NULL OR @maximoTomas IS NULL
                THROW 52510, 'CULM001_B2_CATALOGO_INCONSISTENTE: falta EstadoTomaAsistencia(estaAbierta = 1) o TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION.', 1;
        END

        -- PASO 4: escritura atomica bajo el bloqueo de la sesion
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_abrir_toma;
                SET @savepointCreado = 1;
            END

            -- Ventana con tolerancia y margen (bloquea Sesion; SES_007/008/009/010)
            EXEC dbo.usp_validar_sesion_ventana_registro_interno
                @idSesion = @idSesionDefecto, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @toleranciaMinutos = @toleranciaMinutos, @margenMinutos = @margenMinutos;

            IF @estadoResultado = 1
            BEGIN
                SELECT @totalTomas = COUNT(1), @numero = ISNULL(MAX(t.numero), 0) + 1,
                       @idTomaAbierta = CAST(MAX(IIF(t.fechaCierreUtc IS NULL, CAST(t.id AS NVARCHAR(36)), NULL)) AS UNIQUEIDENTIFIER)
                FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.sesion = @idSesionDefecto;

                IF @idTomaAbierta IS NOT NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_003', @p_param1 = @idSesionDefecto, @p_param2 = @idTomaAbierta,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
                ELSE IF @totalTomas >= @maximoTomas
                BEGIN
                    SET @p1 = CONVERT(NVARCHAR(20), @maximoTomas);
                    SET @p2 = CONVERT(NVARCHAR(36), @idSesionDefecto);
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_004', @p_param1 = @p1,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeDescartado OUTPUT;
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_004', @p_param1 = @p2,
                        @mensajeUsuarioResultado = @mensajeDescartado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
                ELSE
                BEGIN
                    SET @idToma = NEWID();
                    SET @fechaApertura = SYSUTCDATETIME();
                    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc,
                                                    fechaCierreUtc, totalAusentesMarcados, idCorrelacionApertura, idCorrelacionCierre)
                    VALUES (@idToma, @idSesionDefecto, @numero, @idModo, @idEstadoAbierta, 0, @idDocente, @fechaApertura, NULL, 0,
                            @idCorrelacionDefecto, NULL);

                    SELECT @ventanaCierre = CAST(DATEADD(MINUTE, IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos), s.fechaHoraFin) AS DATETIME2(0))
                    FROM dbo.Sesion s WHERE s.id = @idSesionDefecto;
                    SET @totalTomas = @totalTomas + 1;
                    SET @horasToma = dbo.ufn_horas_toma(@idSesionDefecto);

                    SET @p1 = CONVERT(NVARCHAR(20), @numero);
                    SET @p2 = CONVERT(NVARCHAR(36), @idToma);
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_008', @p_param1 = @p1,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeDescartado OUTPUT;
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_008', @p_param1 = @p2, @p_param2 = @codigoModoResuelto,
                        @mensajeUsuarioResultado = @mensajeDescartado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                END
            END

            -- Las ramas de rechazo no escriben: solo se confirma la transaccion propia (libera el bloqueo)
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_abrir_toma;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idToma                  = IIF(@estadoResultado = 1, @idToma, NULL),
        numero                  = IIF(@estadoResultado = 1, @numero, NULL),
        codigoModo              = IIF(@estadoResultado = 1, @codigoModoResuelto, NULL),
        usaCodigoQr             = IIF(@estadoResultado = 1, @usaCodigoQr, NULL),
        fechaAperturaUtc        = IIF(@estadoResultado = 1, @fechaApertura, NULL),
        ventanaCierreUtc        = IIF(@estadoResultado = 1, @ventanaCierre, NULL),
        totalTomasSesion        = IIF(@estadoResultado = 1, @totalTomas, NULL),
        horasToma               = IIF(@estadoResultado = 1, @horasToma, NULL);
END;
GO
IF OBJECT_ID(N'dbo.usp_internal_cerrar_toma', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_internal_cerrar_toma];
GO
PRINT 'MIGRACION 53 DOWN OK';
GO
