USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_decidir_revision_cancelacion (CULM-001 C.1, HU026C; CONTRACT §2.5.6, SUPUESTO-C-07..C-09)
--
-- Decision del docente TITULAR sobre una revision de cancelacion: MANTENER o PROPONER (con motivo). Comando con tupla canonica +
-- idRevision, codigoEstadoAnterior, codigoEstadoNuevo, codigoDecision, sinCambios, idGrupo, idEstudianteGrupo, idEstudiante,
-- porcentajeActual, tipoPlantillaNotificacion, codigoPerfilResolutor, esEscalamiento. Las transiciones salen de
-- TransicionRevisionCancelacion. PROPONER exige umbral de perdida vigente y un resolutor disponible
-- (ufn_revision_cancelacion_resolutores, que excluye a quien propone). DEC-065 (1): la decision final es del coordinador; no hay
-- escalamiento al decano. Si no hay ningun coordinador disponible responde RCN_013 sin cambios; esEscalamiento se conserva y es siempre 0.
-- Codigos: RCN_001..RCN_008, RCN_011, RCN_013, GEN_002, SYS_001. Bloqueo: RevisionCancelacion (UPDLOCK, HOLDLOCK).
-- ============================================================================
-- SKILLS-BD lote 11 (2026-11-26): PASO n, IF con BEGIN/END, IIF en lugar de ISNULL y lecturas sin bloqueo por vistas uv_* (antes,
-- las tablas). La lectura con UPDLOCK, HOLDLOCK de dbo.RevisionCancelacion y las escrituras siguen en las tablas. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_decidir_revision_cancelacion]
(
    @idRevision        UNIQUEIDENTIFIER,
    @codigoDecision    NVARCHAR(20),
    @motivo            NVARCHAR(MAX),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idRevisionDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idRevision, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @decision                 NVARCHAR(20)     = UPPER(TRIM(@codigoDecision));
    DECLARE @motivoLimpio             NVARCHAR(MAX)    = TRIM(@motivo);
    DECLARE @codigoInscrita           NVARCHAR(10)     = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @motivoMin INT = TRY_CAST(CAST(dbo.ufn_obtener_parametro('REVISION_CANCELACION', 'MOTIVO_LONGITUD_MINIMA') AS NVARCHAR(20)) AS INT);
    DECLARE @motivoMax INT = TRY_CAST(CAST(dbo.ufn_obtener_parametro('REVISION_CANCELACION', 'MOTIVO_LONGITUD_MAXIMA') AS NVARCHAR(20)) AS INT);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @err VARCHAR(20) = NULL, @e1 NVARCHAR(500), @e2 NVARCHAR(500), @e3 NVARCHAR(500);
    DECLARE @codigoMensajeOk VARCHAR(100), @p1ok NVARCHAR(500), @p2ok NVARCHAR(500);

    DECLARE @idEstadoActual UNIQUEIDENTIFIER, @codigoEstadoActual NVARCHAR(20), @nombreEstadoActual NVARCHAR(60), @decisionPrevia NVARCHAR(20);
    DECLARE @idEstudianteGrupo UNIQUEIDENTIFIER, @idGrupo UNIQUEIDENTIFIER, @idEstudiante UNIQUEIDENTIFIER, @codigoMatricula NVARCHAR(50);
    DECLARE @idTransicion UNIQUEIDENTIFIER, @idEstadoDestino UNIQUEIDENTIFIER, @codigoEstadoDestino NVARCHAR(20), @exigeUmbral BIT, @exigeResolutor BIT;
    DECLARE @codigoMensajeTransicion VARCHAR(100), @plantilla VARCHAR(60);
    DECLARE @porcentaje DECIMAL(5,2), @umbral DECIMAL(5,2);
    DECLARE @perfilResolutor NVARCHAR(20) = NULL, @huella VARBINARY(32) = NULL;
    DECLARE @sinCambios BIT = 0;
    DECLARE @ahora DATETIME2(3);
    DECLARE @codigoEstadoAnteriorOut NVARCHAR(20), @codigoEstadoNuevoOut NVARCHAR(20);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    -- PASO 1: Longitudes del motivo: 10 y 500 por defecto, maximo 1000
    SET @motivoMin = IIF(@motivoMin IS NULL, 10, @motivoMin);
    SET @motivoMax = IIF(@motivoMax IS NULL, 500, @motivoMax);
    SET @motivoMax = IIF(@motivoMax > 1000, 1000, @motivoMax);
    BEGIN TRY
        -- PASO 2: Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 3: Validar parametros obligatorios (GEN_002)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idRevision IS NULL)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idRevision',
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

        -- PASO 5: Validar decision y motivo
        -- RCN_002 decision del docente; RCN_003 motivo
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_transicion_revision_cancelacion t WHERE t.codigoDecision = @decision AND t.esDecisionResolutor = 0)
        BEGIN
            SELECT @err = 'RCN_002', @e1 = @decision;
        END
        IF @estadoResultado = 1 AND @err IS NULL AND (@motivoLimpio IS NULL OR LEN(@motivoLimpio) < @motivoMin OR LEN(@motivoLimpio) > @motivoMax)
        BEGIN
            SELECT @err = 'RCN_003', @e1 = CONVERT(NVARCHAR(20), @motivoMin), @e2 = CONVERT(NVARCHAR(20), @motivoMax);
        END

        IF @estadoResultado = 1 AND @err IS NULL
        BEGIN
            -- PASO 6: Transaccion propia o punto de guardado
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_decidir_revision;
                SET @savepointCreado = 1;
            END

            -- PASO 7: Bloquear la revision del docente (RCN_001)
            SELECT @idEstadoActual = r.estado, @idEstudianteGrupo = r.estudianteGrupo, @decisionPrevia = r.codigoDecisionDocente,
                   @idGrupo = g.id, @idEstudiante = eg.idEstudiante, @codigoMatricula = ee.codigo
            FROM dbo.RevisionCancelacion r WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.uv_estudiante_grupo_registro eg ON eg.id = r.estudianteGrupo
            INNER JOIN dbo.uv_estado_estudiante_grupo ee ON ee.id = eg.idEstado
            INNER JOIN dbo.uv_grupo_registro g ON g.id = eg.idGrupo
            INNER JOIN dbo.uv_docente_identidad d ON d.id = g.idDocente
            WHERE r.id = @idRevisionDefecto AND d.idUsuario = @idUsuarioEjecutorDefecto;

            IF @idEstadoActual IS NULL
            BEGIN
                SELECT @err = 'RCN_001', @e1 = CONVERT(NVARCHAR(36), @idRevisionDefecto), @e2 = CONVERT(NVARCHAR(36), @idUsuarioEjecutorDefecto);
            END
            ELSE
            BEGIN
                -- PASO 8: Estado, porcentaje, umbral y matricula (RCN_005)
                SELECT @codigoEstadoActual = es.codigo, @nombreEstadoActual = es.nombre FROM dbo.uv_estado_revision_cancelacion es WHERE es.id = @idEstadoActual;
                SELECT @porcentaje = rs.porcentajeInasistencia FROM dbo.uv_resumen_asistencia_estudiante_grupo rs WHERE rs.idEstudianteGrupo = @idEstudianteGrupo;
                SELECT TOP 1 @umbral = dbo.ufn_umbral_alerta_inasistencia(t.id) FROM dbo.uv_tipo_alerta_inasistencia t WHERE t.creaRevisionCancelacion = 1;
                SET @ahora = CAST(SYSUTCDATETIME() AS DATETIME2(3));

                IF @codigoMatricula <> @codigoInscrita
                BEGIN
                    SELECT @err = 'RCN_005', @e1 = CONVERT(NVARCHAR(36), @idEstudianteGrupo), @e2 = @codigoMatricula;
                END

                -- PASO 9: Idempotencia o transicion del catalogo (RCN_004, RCN_006, RCN_013)
                -- Idempotencia: la misma decision que dejo el estado actual
                IF @err IS NULL AND @decisionPrevia = @decision
                   AND EXISTS (SELECT 1 FROM dbo.uv_transicion_revision_cancelacion t WHERE t.codigoDecision = @decision AND t.esDecisionResolutor = 0 AND t.idEstadoDestino = @idEstadoActual)
                BEGIN
                    SET @sinCambios = 1;
                    SELECT @codigoMensajeOk = 'RCN_011', @p1ok = CONVERT(NVARCHAR(36), @idRevisionDefecto), @p2ok = @codigoEstadoActual;
                END
                ELSE IF @err IS NULL
                BEGIN
                    SELECT @idTransicion = t.id, @idEstadoDestino = t.idEstadoDestino, @exigeUmbral = t.exigeUmbralPerdida, @exigeResolutor = t.exigeResolutorDisponible,
                           @codigoMensajeTransicion = t.codigoMensajeExito, @plantilla = t.tipoPlantillaNotificacion
                    FROM dbo.uv_transicion_revision_cancelacion t
                    WHERE t.idEstadoOrigen = @idEstadoActual AND t.codigoDecision = @decision AND t.esDecisionResolutor = 0;
                    IF @idTransicion IS NULL
                    BEGIN
                        SELECT @err = 'RCN_004', @e1 = @nombreEstadoActual, @e2 = @decision;
                    END
                    ELSE IF @exigeUmbral = 1 AND (@porcentaje IS NULL OR @umbral IS NULL OR @porcentaje < @umbral)
                    BEGIN
                        SELECT @err = 'RCN_006', @e1 = CONVERT(NVARCHAR(20), @porcentaje), @e2 = CONVERT(NVARCHAR(20), @umbral);
                    END
                    ELSE
                    BEGIN
                        IF @exigeResolutor = 1
                        BEGIN
                            SELECT f.idUsuario, f.codigoPerfil INTO #culmc_res
                            FROM dbo.ufn_revision_cancelacion_resolutores(@idEstudianteGrupo, @idUsuarioEjecutorDefecto) f;
                            IF NOT EXISTS (SELECT 1 FROM #culmc_res)
                            BEGIN
                                SELECT @err = 'RCN_013', @e1 = CONVERT(NVARCHAR(36), @idEstudianteGrupo);
                            END
                            ELSE
                            BEGIN
                                SET @perfilResolutor = N'COORDINADOR';
                                SELECT @huella = HASHBYTES('SHA2_256', STRING_AGG(CONVERT(VARCHAR(36), x.idUsuario), ',') WITHIN GROUP (ORDER BY CONVERT(VARCHAR(36), x.idUsuario)))
                                FROM (SELECT DISTINCT idUsuario FROM #culmc_res) x;
                            END
                        END

                        IF @err IS NULL
                        BEGIN
                            -- PASO 10: Aplicar la decision: revision, historial y auditoria
                            UPDATE dbo.RevisionCancelacion
                            SET estado = @idEstadoDestino,
                                codigoDecisionDocente = @decision, motivoDocente = @motivoLimpio, usuarioDecisionDocente = @idUsuarioEjecutorDefecto,
                                porcentajeDecisionDocente = @porcentaje, fechaDecisionDocenteUtc = @ahora,
                                codigoPerfilResolutorActual = @perfilResolutor, huellaResolutoresActual = @huella,
                                fechaEscalamientoUtc = NULL,
                                codigoDecisionResolucion = NULL, motivoResolucion = NULL, usuarioResolucion = NULL, codigoPerfilResolucion = NULL,
                                programaResolucion = NULL, porcentajeResolucion = NULL, fechaResolucionUtc = NULL,
                                fechaActualizacionUtc = @ahora
                            WHERE id = @idRevisionDefecto;

                            INSERT INTO dbo.RevisionCancelacionHistorial (id, revision, estadoAnterior, estadoNuevo, codigoEvento, motivo, usuarioActor, codigoPerfilActor,
                                codigoPerfilResolutor, porcentajeInasistencia, fechaUtc, idCorrelacion)
                            VALUES (NEWID(), @idRevisionDefecto, @idEstadoActual, @idEstadoDestino, @decision, @motivoLimpio, @idUsuarioEjecutorDefecto, N'DOCENTE',
                                    @perfilResolutor, @porcentaje, @ahora, @idCorrelacionDefecto);

                            SELECT @codigoEstadoDestino = codigo FROM dbo.uv_estado_revision_cancelacion WHERE id = @idEstadoDestino;
                            INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId, httpMethod, path, httpStatus, metadata)
                            VALUES (NEWID(), SYSDATETIMEOFFSET(), CAST(@idUsuarioEjecutorDefecto AS NVARCHAR(120)), 'USER', 'DECIDIR_REVISION_CANCELACION', 'RevisionCancelacion',
                                    CONVERT(NVARCHAR(36), @idRevisionDefecto), 'SUCCESS', @idCorrelacionDefecto, 'PATCH', N'/api/v1/docente/revisiones-cancelacion/{revisionId}', 200,
                                    (SELECT estadoAnterior = @codigoEstadoActual, estadoNuevo = @codigoEstadoDestino, decision = @decision, motivo = @motivoLimpio,
                                            porcentajeInasistencia = @porcentaje, perfilActor = N'DOCENTE', perfilResolutor = @perfilResolutor FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

                            SELECT @codigoMensajeOk = @codigoMensajeTransicion, @p1ok = CONVERT(NVARCHAR(36), @idRevisionDefecto), @p2ok = NULL;
                        END
                    END
                END
            END

            -- PASO 11: Confirmar o liberar la transaccion
            IF @err IS NULL
            BEGIN
                SELECT @codigoEstadoAnteriorOut = @codigoEstadoActual,
                       @codigoEstadoNuevoOut = IIF(@sinCambios = 1, @codigoEstadoActual, @codigoEstadoDestino);
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
            ELSE
            BEGIN
                -- Todas las validaciones preceden a las escrituras: aqui no hay nada que revertir. Se libera con COMMIT (y sin ROLLBACK)
                -- para que el SP tambien funcione dentro de INSERT ... EXEC.
                IF @transaccionPropia = 1
                BEGIN
                    IF XACT_STATE() = 1
                    BEGIN
                        COMMIT TRANSACTION;
                    END
                    SET @transaccionPropia = 0;
                END
            END
        END

        -- PASO 12: Mensaje de rechazo o de exito
        IF @err IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @err, @p_param1 = @e1, @p_param2 = @e2, @p_param3 = @e3,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        ELSE IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @codigoMensajeOk, @p_param1 = @p1ok, @p_param2 = @p2ok,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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
            ROLLBACK TRANSACTION sp_decidir_revision;
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
        idCorrelacion             = @idCorrelacionDefecto,
        mensajeUsuarioResultado   = @mensajeUsuarioResultado,
        mensajeTecnicoResultado   = @mensajeTecnicoResultado,
        estadoResultado           = @estadoResultado,
        idRevision                = IIF(@estadoResultado = 1, @idRevisionDefecto, NULL),
        codigoEstadoAnterior      = IIF(@estadoResultado = 1, @codigoEstadoAnteriorOut, NULL),
        codigoEstadoNuevo         = IIF(@estadoResultado = 1, @codigoEstadoNuevoOut, NULL),
        codigoDecision            = IIF(@estadoResultado = 1, @decision, NULL),
        sinCambios                = IIF(@estadoResultado = 1, @sinCambios, NULL),
        idGrupo                   = IIF(@estadoResultado = 1, @idGrupo, NULL),
        idEstudianteGrupo         = IIF(@estadoResultado = 1, @idEstudianteGrupo, NULL),
        idEstudiante              = IIF(@estadoResultado = 1, @idEstudiante, NULL),
        porcentajeActual          = IIF(@estadoResultado = 1, @porcentaje, NULL),
        tipoPlantillaNotificacion = IIF(@estadoResultado = 1 AND @sinCambios = 0, @plantilla, NULL),
        codigoPerfilResolutor     = IIF(@estadoResultado = 1, @perfilResolutor, NULL),
        esEscalamiento            = IIF(@estadoResultado = 1, CAST(0 AS BIT), NULL);
END;
GO
