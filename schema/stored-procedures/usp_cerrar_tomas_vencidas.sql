USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cerrar_tomas_vencidas (CULM-001 B.2; CONTRACT §2.8.2, §3.5, [SUPUESTO-B-09])
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION. Job del servidor (sin usuario, como usp_rotar_token_matricula_automatico).
-- Resultset: una fila por toma cerrada en esta pasada: idToma, idSesion, idGrupo, totalAusentesMarcados.
--
-- Cierra las tomas ABIERTAS cuya sesion ya cumplio SYSUTCDATETIME() >= fin + ASISTENCIA/MARGEN_RETARDO_MINUTOS o esta
-- cancelada (maximo TOMA_ASISTENCIA/LOTE_CIERRE_AUTOMATICO por pasada). Una transaccion por toma con el orden de bloqueos
-- Sesion -> TomaAsistencia; la toma se vuelve a leer bloqueada y, si otra instancia (o el docente) ya la cerro, se omite:
-- dos pasadas concurrentes nunca cierran la misma toma dos veces. Si el modo marca ausentes (y la sesion no esta cancelada)
-- inserta SJC a los activos sin registro ANTES de cerrar (permitido aunque la ventana vencio: es el cierre automatico).
-- Un error en una toma no deshace las anteriores: se revierte esa toma, su detalle queda en @mensajeTecnicoResultado (SYS_001 con
-- ufn_obtener_detalle_error) y la pasada sigue con la siguiente.
-- SKILLS-BD lote 2 (2026-11-25): DECLARE en la cabecera, PASO n, SYS_001 en el CATCH y usp_marcar_ausentes_toma_interno (triplete).
-- Lecturas a la tabla con bloqueo (excepcion de lecturas con bloqueo): la seleccion de candidatas (PASO 2) conserva su consulta con
-- READPAST sobre TomaAsistencia para no esperar tomas que otra instancia o el docente tiene bloqueadas (una vista no admite la
-- pista sobre la fila fisica), y la toma y la sesion se releen con UPDLOCK/HOLDLOCK antes de cerrar.
-- ============================================================================
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): job del servidor sin @idUsuarioEjecutor; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_cerrar_tomas_vencidas]
(
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @margenMinutos   INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @lote            INT = dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'LOTE_CIERRE_AUTOMATICO');
    DECLARE @idEstadoCerrada UNIQUEIDENTIFIER;
    DECLARE @ahora           DATETIME2 = SYSUTCDATETIME();

    DECLARE @candidatas TABLE (n INT IDENTITY(1,1) PRIMARY KEY, idToma UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER);
    DECLARE @cerradas TABLE (idToma UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, totalAusentesMarcados INT);
    DECLARE @i INT = 1;
    DECLARE @total INT;
    DECLARE @idToma UNIQUEIDENTIFIER;
    DECLARE @idSesion UNIQUEIDENTIFIER;
    DECLARE @idGrupo UNIQUEIDENTIFIER;
    DECLARE @abierta BIT;
    DECLARE @marcaPorModo BIT;
    DECLARE @cancelada BIT;
    DECLARE @marcados INT;
    DECLARE @fechaCierre DATETIME2(0);
    DECLARE @transaccionPropia BIT;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @mensajeErrorInterno     NVARCHAR(2048);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: parametros del job y estado CERRADA
    SET @margenMinutos = IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos);
    SET @lote = IIF(@lote IS NULL OR @lote < 1, 200, @lote);
    SELECT @idEstadoCerrada = e.id FROM dbo.uv_estado_toma_asistencia e WHERE e.estaAbierta = 0;
    IF @idEstadoCerrada IS NULL
    BEGIN
        THROW 52512, 'CULM001_B2_CATALOGO_INCONSISTENTE: falta EstadoTomaAsistencia(estaAbierta = 0).', 1;
    END

    -- PASO 2: candidatas (abiertas con la ventana vencida o la sesion cancelada), sin esperar filas bloqueadas
    INSERT INTO @candidatas (idToma, idSesion, idGrupo)
    SELECT TOP (@lote) t.id, t.sesion, s.grupo
    FROM dbo.TomaAsistencia t WITH (READPAST)
    INNER JOIN dbo.Sesion s ON s.id = t.sesion
    WHERE t.fechaCierreUtc IS NULL
      AND (@ahora >= DATEADD(MINUTE, @margenMinutos, s.fechaHoraFin)
           OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = t.sesion))
    ORDER BY t.fechaAperturaUtc ASC, t.id ASC;
    SET @total = @@ROWCOUNT;

    -- PASO 3: una transaccion (o savepoint) por toma
    WHILE @i <= @total
    BEGIN
        SELECT @idToma = idToma, @idSesion = idSesion, @idGrupo = idGrupo FROM @candidatas WHERE n = @i;
        SET @transaccionPropia = 0;
        BEGIN TRY
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cerrar_tomas_vencidas;
            END

            -- PASO 3.1: bloqueos Sesion -> TomaAsistencia y relectura de la toma
            SELECT @idGrupo = s.grupo FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK) WHERE s.id = @idSesion;
            SET @abierta = 0;
            SELECT @abierta = IIF(t.fechaCierreUtc IS NULL, 1, 0), @marcaPorModo = m.marcaAusentesAlCerrar
            FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.uv_modo_toma_asistencia m ON m.id = t.modo
            WHERE t.id = @idToma;

            -- PASO 3.2: cierre (otra instancia o el docente pudo cerrarla ya: se omite)
            IF @abierta = 1
            BEGIN
                SET @cancelada = 0;
                SELECT @cancelada = se.estaCancelada FROM dbo.uv_sesion_estado se WHERE se.idSesion = @idSesion;
                SET @fechaCierre = SYSUTCDATETIME();
                SET @marcados = 0;

                UPDATE dbo.TokenAsistenciaToma SET fechaCierreUtc = @fechaCierre WHERE toma = @idToma AND fechaCierreUtc IS NULL;

                IF @marcaPorModo = 1 AND @cancelada = 0
                BEGIN
                    EXEC dbo.usp_marcar_ausentes_toma_interno
                        @idToma = @idToma, @idSesion = @idSesion, @idGrupo = @idGrupo,
                        @fechaRegistroUtc = @fechaCierre, @idCorrelacion = @idCorrelacionDefecto,
                        @totalMarcados = @marcados OUTPUT,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;

                    IF @estadoResultado = 0
                    BEGIN
                        SET @mensajeErrorInterno = LEFT(@mensajeTecnicoResultado, 2048);
                        THROW 52523, @mensajeErrorInterno, 1;
                    END
                END

                UPDATE dbo.TomaAsistencia
                SET estado = @idEstadoCerrada,
                    fechaCierreUtc = IIF(@fechaCierre < fechaAperturaUtc, fechaAperturaUtc, @fechaCierre),
                    totalAusentesMarcados = @marcados,
                    idCorrelacionCierre = @idCorrelacionDefecto
                WHERE id = @idToma;

                INSERT INTO @cerradas (idToma, idSesion, idGrupo, totalAusentesMarcados) VALUES (@idToma, @idSesion, @idGrupo, @marcados);
            END

            IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
            END
        END TRY
        BEGIN CATCH
            -- PASO 3.3: error en esta toma: se revierte solo ella y se registra el detalle (SYS_001)
            SET @estadoTransaccionCatch = XACT_STATE();
            IF @transaccionPropia = 1 AND @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
            ELSE IF @transaccionPropia = 0 AND @estadoTransaccionCatch = 1
            BEGIN
                ROLLBACK TRANSACTION sp_cerrar_tomas_vencidas;
            END
            ELSE IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            BEGIN
                THROW;
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SYS_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END CATCH;
        SET @i += 1;
    END

    -- PASO 4: resultset del job (una fila por toma cerrada en esta pasada)
    SELECT idToma, idSesion, idGrupo, totalAusentesMarcados FROM @cerradas;
END;
GO
