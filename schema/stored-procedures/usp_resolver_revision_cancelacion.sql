USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_resolver_revision_cancelacion (CULM-001 C.1, HU026C; CONTRACT §2.5.8, SUPUESTO-C-09, O-2, O-13)
--
-- Resolucion de una propuesta de cancelacion por el coordinador competente del programa del estudiante (ufn_revision_cancelacion_resolutores,
-- que excluye al proponente). DEC-065 (1): el decano no resuelve (RCN_016, sin cambios); solo consulta y audita. APROBAR => la matricula pasa a CI (MATRICULA/
-- ESTADO_CANCELADA_INASISTENCIA) y queda fuera de todo registro; RECHAZAR => sigue activa. Una revision ajena es indistinguible de
-- una inexistente (RCN_001). Nadie resuelve su propia propuesta (RCN_014). Idempotente para quien pida lo mismo (RCN_011).
-- Salida: tupla + idRevision, codigoEstadoAnterior, codigoEstadoNuevo, codigoDecision, sinCambios, cambioMatricula, idGrupo,
-- idEstudianteGrupo, idEstudiante, idPrograma, codigoPerfilResolucion, porcentajeActual, tipoPlantillaNotificacion.
-- Bloqueos: RevisionCancelacion -> EstudianteGrupo.
-- ============================================================================
-- SKILLS-BD lote 11 (2026-11-26): PASO n, IF con BEGIN/END, IIF en lugar de ISNULL y lecturas sin bloqueo por vistas uv_* (antes,
-- las tablas). Las lecturas con UPDLOCK, HOLDLOCK (RevisionCancelacion, EstudianteGrupo) y las escrituras siguen en las tablas.
-- Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_revision_cancelacion]
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
    DECLARE @codigoCancelada          NVARCHAR(10)     = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_CANCELADA_INASISTENCIA') AS NVARCHAR(10));
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

    DECLARE @idEstadoActual UNIQUEIDENTIFIER, @codigoEstadoActual NVARCHAR(20), @nombreEstadoActual NVARCHAR(60), @usuarioProponente UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo UNIQUEIDENTIFIER, @idGrupo UNIQUEIDENTIFIER, @idEstudiante UNIQUEIDENTIFIER, @codigoMatricula NVARCHAR(50);
    DECLARE @perfilEjecutor NVARCHAR(20), @idPrograma UNIQUEIDENTIFIER;
    DECLARE @idTransicion UNIQUEIDENTIFIER, @idEstadoDestino UNIQUEIDENTIFIER, @codigoEstadoDestino NVARCHAR(20), @exigeUmbral BIT, @cancela BIT = 0;
    DECLARE @codigoMensajeTransicion VARCHAR(100), @plantilla VARCHAR(60);
    DECLARE @porcentaje DECIMAL(5,2), @umbral DECIMAL(5,2);
    DECLARE @estadoMatriculaActualId UNIQUEIDENTIFIER, @estadoCanceladaId UNIQUEIDENTIFIER;
    DECLARE @sinCambios BIT = 0, @cambioMatricula BIT = 0;
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

        -- PASO 4: Validar decision (RCN_002) y motivo (RCN_003)
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_transicion_revision_cancelacion t WHERE t.codigoDecision = @decision AND t.esDecisionResolutor = 1)
        BEGIN
            SELECT @err = 'RCN_002', @e1 = @decision;
        END
        IF @estadoResultado = 1 AND @err IS NULL AND (@motivoLimpio IS NULL OR LEN(@motivoLimpio) < @motivoMin OR LEN(@motivoLimpio) > @motivoMax)
        BEGIN
            SELECT @err = 'RCN_003', @e1 = CONVERT(NVARCHAR(20), @motivoMin), @e2 = CONVERT(NVARCHAR(20), @motivoMax);
        END

        IF @estadoResultado = 1 AND @err IS NULL
        BEGIN
            -- PASO 5: Transaccion propia o punto de guardado
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_resolver_revision;
                SET @savepointCreado = 1;
            END

            -- PASO 6: Bloquear la revision (RCN_001; el proponente no resuelve: RCN_014)
            SELECT @idEstadoActual = r.estado, @idEstudianteGrupo = r.estudianteGrupo, @usuarioProponente = r.usuarioDecisionDocente
            FROM dbo.RevisionCancelacion r WITH (UPDLOCK, HOLDLOCK)
            WHERE r.id = @idRevisionDefecto;

            IF @idEstadoActual IS NULL
            BEGIN
                SELECT @err = 'RCN_001', @e1 = CONVERT(NVARCHAR(36), @idRevisionDefecto), @e2 = CONVERT(NVARCHAR(36), @idUsuarioEjecutorDefecto);
            END
            ELSE IF @usuarioProponente IS NOT NULL AND @usuarioProponente = @idUsuarioEjecutorDefecto
            BEGIN
                SELECT @err = 'RCN_014', @e1 = CONVERT(NVARCHAR(36), @idUsuarioEjecutorDefecto), @e2 = CONVERT(NVARCHAR(36), @idRevisionDefecto);
            END
            ELSE
            BEGIN
                -- PASO 7: Resolutor vigente y su perfil (RCN_016 decano, RCN_001 ajeno)
                SELECT f.idUsuario, f.codigoPerfil, f.idPrograma INTO #culmc_res
                FROM dbo.ufn_revision_cancelacion_resolutores(@idEstudianteGrupo, @usuarioProponente) f;
                SELECT TOP 1 @perfilEjecutor = x.codigoPerfil FROM #culmc_res x WHERE x.idUsuario = @idUsuarioEjecutorDefecto;
                IF @perfilEjecutor IS NULL AND EXISTS (SELECT 1 FROM dbo.uv_decano_rol d WHERE d.idUsuario = @idUsuarioEjecutorDefecto AND d.estaActivoRolDecano = 1)
                BEGIN
                    SELECT @err = 'RCN_016', @e1 = CONVERT(NVARCHAR(36), @idUsuarioEjecutorDefecto), @e2 = CONVERT(NVARCHAR(36), @idRevisionDefecto);
                END
                ELSE IF @perfilEjecutor IS NULL
                BEGIN
                    SELECT @err = 'RCN_001', @e1 = CONVERT(NVARCHAR(36), @idRevisionDefecto), @e2 = CONVERT(NVARCHAR(36), @idUsuarioEjecutorDefecto);
                END
                ELSE
                BEGIN
                    EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                        @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = @perfilEjecutor, @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;
                END
            END

            IF @err IS NULL AND @estadoResultado = 1
            BEGIN
                -- PASO 8: Estado, matricula, porcentaje, umbral y programa del resolutor
                SELECT @codigoEstadoActual = es.codigo, @nombreEstadoActual = es.nombre FROM dbo.uv_estado_revision_cancelacion es WHERE es.id = @idEstadoActual;
                SELECT @idGrupo = eg.idGrupo, @idEstudiante = eg.idEstudiante, @codigoMatricula = ee.codigo
                FROM dbo.uv_estudiante_grupo_registro eg INNER JOIN dbo.uv_estado_estudiante_grupo ee ON ee.id = eg.idEstado WHERE eg.id = @idEstudianteGrupo;
                SELECT @porcentaje = rs.porcentajeInasistencia FROM dbo.uv_resumen_asistencia_estudiante_grupo rs WHERE rs.idEstudianteGrupo = @idEstudianteGrupo;
                SELECT TOP 1 @umbral = dbo.ufn_umbral_alerta_inasistencia(t.id) FROM dbo.uv_tipo_alerta_inasistencia t WHERE t.creaRevisionCancelacion = 1;
                SELECT TOP 1 @idPrograma = x.idPrograma FROM #culmc_res x INNER JOIN dbo.uv_programa p ON p.id = x.idPrograma
                WHERE x.idUsuario = @idUsuarioEjecutorDefecto ORDER BY p.nombrePrograma, p.id;
                SET @ahora = CAST(SYSUTCDATETIME() AS DATETIME2(3));

                -- PASO 9: Idempotencia o transicion del catalogo (RCN_004, RCN_005, RCN_006)
                -- Idempotencia: quien pida lo mismo que ya quedo registrado (sea quien sea el que resolvio antes)
                IF EXISTS (SELECT 1 FROM dbo.uv_transicion_revision_cancelacion t WHERE t.codigoDecision = @decision AND t.esDecisionResolutor = 1 AND t.idEstadoDestino = @idEstadoActual)
                BEGIN
                    SET @sinCambios = 1;
                    SELECT @codigoMensajeOk = 'RCN_011', @p1ok = CONVERT(NVARCHAR(36), @idRevisionDefecto), @p2ok = @codigoEstadoActual;
                END
                ELSE
                BEGIN
                    SELECT @idTransicion = t.id, @idEstadoDestino = t.idEstadoDestino, @exigeUmbral = t.exigeUmbralPerdida, @codigoMensajeTransicion = t.codigoMensajeExito,
                           @plantilla = t.tipoPlantillaNotificacion
                    FROM dbo.uv_transicion_revision_cancelacion t
                    WHERE t.idEstadoOrigen = @idEstadoActual AND t.codigoDecision = @decision AND t.esDecisionResolutor = 1;
                    IF @idTransicion IS NULL
                    BEGIN
                        SELECT @err = 'RCN_004', @e1 = @nombreEstadoActual, @e2 = @decision;
                    END
                    ELSE IF @codigoMatricula <> @codigoInscrita
                    BEGIN
                        SELECT @err = 'RCN_005', @e1 = CONVERT(NVARCHAR(36), @idEstudianteGrupo), @e2 = @codigoMatricula;
                    END
                    ELSE IF @exigeUmbral = 1 AND (@porcentaje IS NULL OR @umbral IS NULL OR @porcentaje < @umbral)
                    BEGIN
                        SELECT @err = 'RCN_006', @e1 = CONVERT(NVARCHAR(20), @porcentaje), @e2 = CONVERT(NVARCHAR(20), @umbral);
                    END
                    ELSE
                    BEGIN
                        -- PASO 10: Cancelar la matricula si el estado destino lo exige (bloqueo de EstudianteGrupo)
                        SELECT @cancela = es.cancelaMatricula, @codigoEstadoDestino = es.codigo FROM dbo.uv_estado_revision_cancelacion es WHERE es.id = @idEstadoDestino;
                        IF @cancela = 1
                        BEGIN
                            SELECT @estadoCanceladaId = id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = @codigoCancelada;
                            IF @estadoCanceladaId IS NULL
                            BEGIN
                                THROW 52702, 'CULM001_C_CATALOGO_INCONSISTENTE: falta el estado de matricula cancelada por inasistencia.', 1;
                            END
                            SELECT @estadoMatriculaActualId = eg.estado FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK) WHERE eg.id = @idEstudianteGrupo;
                            IF NOT EXISTS (SELECT 1 FROM dbo.uv_estado_estudiante_grupo WHERE id = @estadoMatriculaActualId AND codigo = @codigoInscrita)
                            BEGIN
                                SELECT @err = 'RCN_005', @e1 = CONVERT(NVARCHAR(36), @idEstudianteGrupo), @e2 = (SELECT codigo FROM dbo.uv_estado_estudiante_grupo WHERE id = @estadoMatriculaActualId);
                            END
                            ELSE
                            BEGIN
                                UPDATE dbo.EstudianteGrupo SET estado = @estadoCanceladaId WHERE id = @idEstudianteGrupo;
                                SET @cambioMatricula = 1;
                            END
                        END
                        -- PASO 11: Aplicar la resolucion: revision, historial y auditoria
                        IF @err IS NULL
                        BEGIN
                            IF @codigoEstadoDestino IS NULL
                            BEGIN
                                SELECT @codigoEstadoDestino = codigo FROM dbo.uv_estado_revision_cancelacion WHERE id = @idEstadoDestino;
                            END
                            UPDATE dbo.RevisionCancelacion
                            SET estado = @idEstadoDestino, codigoDecisionResolucion = @decision, motivoResolucion = @motivoLimpio, usuarioResolucion = @idUsuarioEjecutorDefecto,
                                codigoPerfilResolucion = @perfilEjecutor, programaResolucion = @idPrograma, porcentajeResolucion = @porcentaje, fechaResolucionUtc = @ahora,
                                estadoMatriculaAnterior = IIF(@cambioMatricula = 1, @estadoMatriculaActualId, estadoMatriculaAnterior),
                                fechaActualizacionUtc = @ahora
                            WHERE id = @idRevisionDefecto;

                            INSERT INTO dbo.RevisionCancelacionHistorial (id, revision, estadoAnterior, estadoNuevo, codigoEvento, motivo, usuarioActor, codigoPerfilActor,
                                codigoPerfilResolutor, porcentajeInasistencia, fechaUtc, idCorrelacion)
                            VALUES (NEWID(), @idRevisionDefecto, @idEstadoActual, @idEstadoDestino, @decision, @motivoLimpio, @idUsuarioEjecutorDefecto, @perfilEjecutor,
                                    @perfilEjecutor, @porcentaje, @ahora, @idCorrelacionDefecto);

                            INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId, httpMethod, path, httpStatus, metadata)
                            VALUES (NEWID(), SYSDATETIMEOFFSET(), CAST(@idUsuarioEjecutorDefecto AS NVARCHAR(120)), 'USER', 'RESOLVER_REVISION_CANCELACION', 'RevisionCancelacion',
                                    CONVERT(NVARCHAR(36), @idRevisionDefecto), 'SUCCESS', @idCorrelacionDefecto, 'PATCH',
                                    N'/api/v1/coordinador/revisiones-cancelacion/{revisionId}', 200,
                                    (SELECT estadoAnterior = @codigoEstadoActual, estadoNuevo = @codigoEstadoDestino, decision = @decision, motivo = @motivoLimpio,
                                            porcentajeInasistencia = @porcentaje, perfilResolutor = @perfilEjecutor,
                                            matriculaAnterior = IIF(@cambioMatricula = 1, @codigoInscrita, NULL), matriculaNueva = IIF(@cambioMatricula = 1, @codigoCancelada, NULL)
                                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
                            SELECT @codigoMensajeOk = @codigoMensajeTransicion, @p1ok = CONVERT(NVARCHAR(36), @idRevisionDefecto), @p2ok = CONVERT(NVARCHAR(36), @idEstudianteGrupo);
                        END
                    END
                END
            END

            -- PASO 12: Confirmar o liberar la transaccion
            IF @err IS NULL AND @estadoResultado = 1
            BEGIN
                SELECT @codigoEstadoAnteriorOut = @codigoEstadoActual, @codigoEstadoNuevoOut = IIF(@sinCambios = 1, @codigoEstadoActual, @codigoEstadoDestino);
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

        -- PASO 13: Mensaje de rechazo o de exito
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
        -- PASO 14: Error: revertir lo propio, relanzar si la transaccion externa quedo condenada; si no, SYS_001
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
            ROLLBACK TRANSACTION sp_resolver_revision;
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

    -- PASO 15: Resultado
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
        cambioMatricula           = IIF(@estadoResultado = 1, @cambioMatricula, NULL),
        idGrupo                   = IIF(@estadoResultado = 1, @idGrupo, NULL),
        idEstudianteGrupo         = IIF(@estadoResultado = 1, @idEstudianteGrupo, NULL),
        idEstudiante              = IIF(@estadoResultado = 1, @idEstudiante, NULL),
        idPrograma                = IIF(@estadoResultado = 1, @idPrograma, NULL),
        codigoPerfilResolucion    = IIF(@estadoResultado = 1, @perfilEjecutor, NULL),
        porcentajeActual          = IIF(@estadoResultado = 1, @porcentaje, NULL),
        tipoPlantillaNotificacion = IIF(@estadoResultado = 1 AND @sinCambios = 0, @plantilla, NULL);
END;
GO
