USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_sincronizar_parametro_catalogo_externo (INT-004, migracion 73)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema con tupla canonica + resultado, grupo, clave, huboCambio y
-- fechaModificacion. Unico camino de escritura de valores que vienen del Catalogo de Parametros externo (M2M + eventos Pulsar):
-- copia en dbo.CatalogoParametro el valor vigente de un parametro que YA existe en la BD. Lo invoca el backend al recibir un evento
-- Parameter* (despues de reconfirmar el valor por M2M) y en la reconciliacion de arranque. No hay usuario ejecutor (proceso del
-- sistema), por eso no valida RBAC; la edicion humana sigue en usp_actualizar_parametro (bloqueada por el backend con PRM_010 cuando el
-- catalogo activo no es sqlserver).
--
-- Entradas: @grupo y @clave (el backend parte el nombre GRUPO.CLAVE del catalogo externo con el separador configurado), @valor,
-- @operacion (UPSERT | DELETE), @idEvento (eventId del evento; NULL en la reconciliacion), @ocurridoEnUtc (occurredAt del evento, o el
-- instante de la lectura M2M en la reconciliacion) y @idCorrelacion.
--
-- Pasos: correlacion -> grupo, clave, operacion, ocurridoEnUtc y (UPSERT) valor obligatorios (GEN_002) -> transaccion y fila del
-- parametro bloqueada (UPDLOCK, HOLDLOCK) -> evento ya procesado: DUPLICADO (PRM_014, sin escritura) -> clave inexistente o inactiva:
-- DESCONOCIDO (PRM_016: no se crean filas) -> evento mas antiguo que el ultimo aplicado: OBSOLETO (PRM_015, "el ultimo evento gana"; el
-- empate lo gana el que llega despues) -> UPSERT valida tipo/rango/lista (usp_validar_valor_parametro_externo_interno; PRM_004/005/006:
-- RECHAZADO, estadoResultado = 0, no escribe el valor) -> valor igual en comparacion binaria: SIN_CAMBIOS (PRM_011) -> UPDATE
-- valor y fechaModificacion: APLICADO (PRM_013).
-- DELETE (el parametro se borro en el catalogo externo): la fila NUNCA se borra porque los SP la leen; el valor vuelve a
-- valorDefecto de la propia fila (APLICADO si era distinto, SIN_CAMBIOS si ya lo era). Es el estado "sin valor externo".
-- Auditoria e idempotencia: con @idEvento, cada resultado queda en dbo.SincronizacionParametroExterno; sin @idEvento (reconciliacion)
-- solo se registran los APLICADO. Transaccion propia o SAVE TRANSACTION. Las ramas sin escritura solo confirman la transaccion propia.
-- ============================================================================
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): proceso del sistema sin @idUsuarioEjecutor; exige @idCorrelacion.
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): PASO n, IF con BEGIN/END y lecturas sin bloqueo del ultimo evento aplicado y de la fecha nueva por vistas
-- uv_* (antes, las tablas); los UPDLOCK, el UPDATE y el INSERT siguen en las tablas.
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_sincronizar_parametro_catalogo_externo]
(
    @grupo          VARCHAR(100),
    @clave          VARCHAR(100),
    @valor          NVARCHAR(4000),
    @operacion      VARCHAR(10),
    @idEvento       VARCHAR(100),
    @ocurridoEnUtc  DATETIME2(7),
    @idCorrelacion  UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @grupoLimpio     VARCHAR(100)   = TRIM(@grupo);
    DECLARE @claveLimpia     VARCHAR(100)   = TRIM(@clave);
    DECLARE @valorLimpio     NVARCHAR(4000) = TRIM(@valor);
    DECLARE @operacionLimpia VARCHAR(10)    = UPPER(TRIM(@operacion));
    DECLARE @idEventoLimpio  VARCHAR(100)   = NULLIF(TRIM(@idEvento), '');
    DECLARE @idParametro     UNIQUEIDENTIFIER = NULL;
    DECLARE @valorActual     NVARCHAR(MAX);
    DECLARE @valorDefecto    NVARCHAR(MAX);
    DECLARE @valorObjetivo   NVARCHAR(MAX);
    DECLARE @fechaActual     DATETIME = NULL;
    DECLARE @fechaNueva      DATETIME = NULL;
    DECLARE @ultimoAplicado  DATETIME2(7);
    DECLARE @codigoRechazo   VARCHAR(20) = NULL;
    DECLARE @codigoMensaje   VARCHAR(20) = NULL;
    DECLARE @param1          NVARCHAR(500) = NULL;
    DECLARE @param2          NVARCHAR(500) = NULL;
    DECLARE @resultado       VARCHAR(20) = NULL;
    DECLARE @huboCambio      BIT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: campos obligatorios (GEN_002)
        IF @estadoResultado = 1 AND (@grupoLimpio IS NULL OR @grupoLimpio = '')
        BEGIN
            SET @param1 = N'grupo';
            SET @codigoRechazo = 'GEN_002';
        END
        IF @codigoRechazo IS NULL AND @estadoResultado = 1 AND (@claveLimpia IS NULL OR @claveLimpia = '')
        BEGIN
            SET @param1 = N'clave';
            SET @codigoRechazo = 'GEN_002';
        END
        IF @codigoRechazo IS NULL AND @estadoResultado = 1 AND (@operacionLimpia IS NULL OR @operacionLimpia NOT IN ('UPSERT', 'DELETE'))
        BEGIN
            SET @param1 = N'operacion';
            SET @codigoRechazo = 'GEN_002';
        END
        IF @codigoRechazo IS NULL AND @estadoResultado = 1 AND @ocurridoEnUtc IS NULL
        BEGIN
            SET @param1 = N'ocurridoEnUtc';
            SET @codigoRechazo = 'GEN_002';
        END
        IF @codigoRechazo IS NULL AND @estadoResultado = 1 AND @operacionLimpia = 'UPSERT' AND (@valorLimpio IS NULL OR @valorLimpio = N'')
        BEGIN
            SET @param1 = N'valor';
            SET @codigoRechazo = 'GEN_002';
        END
        IF @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @param1,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            SET @codigoRechazo = NULL;
            SET @param1 = NULL;
        END

        -- PASO 3: transaccion y evaluacion bajo el bloqueo de la fila del parametro
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_sincronizar_parametro_externo;
                SET @savepointCreado = 1;
            END

            SELECT @idParametro = p.id, @valorActual = p.valor, @valorDefecto = p.valorDefecto, @fechaActual = p.fechaModificacion
            FROM dbo.CatalogoParametro p WITH (UPDLOCK, HOLDLOCK)
            WHERE p.grupo = @grupoLimpio AND p.clave = @claveLimpia AND p.estaActivo = 1;

            IF @idEventoLimpio IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.SincronizacionParametroExterno s WITH (UPDLOCK, HOLDLOCK) WHERE s.idEvento = @idEventoLimpio)
            BEGIN
                SET @resultado = 'DUPLICADO';
                SET @codigoMensaje = 'PRM_014';
                SET @fechaNueva = @fechaActual;
            END
            ELSE IF @idParametro IS NULL
            BEGIN
                SET @resultado = 'DESCONOCIDO';
                SET @codigoMensaje = 'PRM_016';
            END
            ELSE
            BEGIN
                SELECT @ultimoAplicado = MAX(s.ocurridoEnUtc)
                FROM dbo.uv_sincronizacion_parametro_externo_registro s
                WHERE s.idParametro = @idParametro AND s.resultado IN ('APLICADO', 'SIN_CAMBIOS');

                IF @ultimoAplicado IS NOT NULL AND @ocurridoEnUtc < @ultimoAplicado
                BEGIN
                    SET @resultado = 'OBSOLETO';
                    SET @codigoMensaje = 'PRM_015';
                    SET @fechaNueva = @fechaActual;
                END
                ELSE
                BEGIN
                    SET @valorObjetivo = IIF(@operacionLimpia = 'DELETE', @valorDefecto, @valorLimpio);

                    IF @operacionLimpia = 'UPSERT'
                    BEGIN
                        EXEC dbo.usp_validar_valor_parametro_externo_interno
                            @idParametro = @idParametro, @valor = @valorLimpio, @idCorrelacion = @idCorrelacionDefecto,
                            @codigoRechazo = @codigoRechazo OUTPUT, @param1 = @param1 OUTPUT, @param2 = @param2 OUTPUT;
                    END

                    IF @codigoRechazo IS NOT NULL
                    BEGIN
                        SET @resultado = 'RECHAZADO';
                        SET @codigoMensaje = @codigoRechazo;
                        SET @fechaNueva = @fechaActual;
                        SET @estadoResultado = 0;
                    END
                    ELSE IF @valorObjetivo COLLATE Latin1_General_BIN2 = @valorActual COLLATE Latin1_General_BIN2
                    BEGIN
                        SET @resultado = 'SIN_CAMBIOS';
                        SET @codigoMensaje = 'PRM_011';
                        SET @fechaNueva = @fechaActual;
                    END
                    ELSE
                    BEGIN
                        UPDATE dbo.CatalogoParametro
                        SET valor = @valorObjetivo, fechaModificacion = SYSUTCDATETIME()
                        WHERE id = @idParametro;

                        SELECT @fechaNueva = r.fechaModificacion FROM dbo.uv_parametro_registro r WHERE r.id = @idParametro;
                        SET @resultado = 'APLICADO';
                        SET @codigoMensaje = 'PRM_013';
                        SET @huboCambio = 1;
                    END
                END
            END

            -- PASO 4: bitacora; con idEvento se registra todo resultado (idempotencia y auditoria); sin idEvento solo los valores aplicados
            IF @resultado <> 'DUPLICADO' AND (@idEventoLimpio IS NOT NULL OR @resultado = 'APLICADO')
            BEGIN
                INSERT INTO dbo.SincronizacionParametroExterno
                    (id, idEvento, parametro, grupo, clave, operacion, resultado, valorAnterior, valorNuevo, ocurridoEnUtc, idCorrelacion, fechaRegistroUtc)
                VALUES
                    (NEWID(), @idEventoLimpio, @idParametro, @grupoLimpio, @claveLimpia, @operacionLimpia, @resultado,
                     LEFT(CONVERT(NVARCHAR(MAX), @valorActual), 4000),
                     IIF(@resultado IN ('APLICADO', 'SIN_CAMBIOS'), LEFT(CONVERT(NVARCHAR(MAX), @valorObjetivo), 4000), NULL),
                     @ocurridoEnUtc, @idCorrelacionDefecto, SYSUTCDATETIME());
            END

            -- PASO 5: mensaje del resultado
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoMensaje, @p_param1 = @param1, @p_param2 = @param2,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Parametro: ', @grupoLimpio, '.', @claveLimpia,
                                                  ' Correlacion: ', @idCorrelacionDefecto);

            -- PASO 6: las ramas sin escritura solo confirman la transaccion propia (libera los bloqueos).
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
        -- PASO 7: reversion respetando ownership; transaccion externa condenada se propaga al propietario; si no, SYS_001
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
            ROLLBACK TRANSACTION sp_sincronizar_parametro_externo;
        END

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SET @resultado = NULL;
        SET @huboCambio = 0;
        SET @fechaNueva = NULL;
    END CATCH

    -- PASO 8: retorno unificado de resultados
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        resultado               = @resultado,
        grupo                   = IIF(@resultado IS NOT NULL, @grupoLimpio, NULL),
        clave                   = IIF(@resultado IS NOT NULL, @claveLimpia, NULL),
        huboCambio              = IIF(@resultado IS NOT NULL, @huboCambio, NULL),
        fechaModificacion       = IIF(@resultado IS NOT NULL, @fechaNueva, NULL);
END;
GO
