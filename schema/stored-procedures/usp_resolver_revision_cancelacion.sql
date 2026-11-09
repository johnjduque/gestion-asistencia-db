USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_resolver_revision_cancelacion (CULM-001 C.1, HU026C; CONTRACT §2.5.8, SUPUESTO-C-09, O-2, O-13)
--
-- Resolucion de una propuesta de cancelacion por el coordinador competente del programa del estudiante o, por escalamiento, el
-- decano (ufn_revision_cancelacion_resolutores, que excluye al proponente). APROBAR => la matricula pasa a CI (MATRICULA/
-- ESTADO_CANCELADA_INASISTENCIA) y queda fuera de todo registro; RECHAZAR => sigue activa. Una revision ajena es indistinguible de
-- una inexistente (RCN_001). Nadie resuelve su propia propuesta (RCN_014). Idempotente para quien pida lo mismo (RCN_011).
-- Salida: tupla + idRevision, codigoEstadoAnterior, codigoEstadoNuevo, codigoDecision, sinCambios, cambioMatricula, idGrupo,
-- idEstudianteGrupo, idEstudiante, idPrograma, codigoPerfilResolucion, porcentajeActual, tipoPlantillaNotificacion.
-- Bloqueos: RevisionCancelacion -> EstudianteGrupo.
-- ============================================================================
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
    DECLARE @motivoMin INT = ISNULL(TRY_CAST(CAST(dbo.ufn_obtener_parametro('REVISION_CANCELACION', 'MOTIVO_LONGITUD_MINIMA') AS NVARCHAR(20)) AS INT), 10);
    DECLARE @motivoMax INT = IIF(ISNULL(TRY_CAST(CAST(dbo.ufn_obtener_parametro('REVISION_CANCELACION', 'MOTIVO_LONGITUD_MAXIMA') AS NVARCHAR(20)) AS INT), 500) > 1000, 1000,
                                 ISNULL(TRY_CAST(CAST(dbo.ufn_obtener_parametro('REVISION_CANCELACION', 'MOTIVO_LONGITUD_MAXIMA') AS NVARCHAR(20)) AS INT), 500));

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
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idRevision IS NULL)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idRevision',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.TransicionRevisionCancelacion t WHERE t.codigoDecision = @decision AND t.esDecisionResolutor = 1)
            SELECT @err = 'RCN_002', @e1 = @decision;
        IF @estadoResultado = 1 AND @err IS NULL AND (@motivoLimpio IS NULL OR LEN(@motivoLimpio) < @motivoMin OR LEN(@motivoLimpio) > @motivoMax)
            SELECT @err = 'RCN_003', @e1 = CONVERT(NVARCHAR(20), @motivoMin), @e2 = CONVERT(NVARCHAR(20), @motivoMax);

        IF @estadoResultado = 1 AND @err IS NULL
        BEGIN
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

            SELECT @idEstadoActual = r.estado, @idEstudianteGrupo = r.estudianteGrupo, @usuarioProponente = r.usuarioDecisionDocente
            FROM dbo.RevisionCancelacion r WITH (UPDLOCK, HOLDLOCK)
            WHERE r.id = @idRevisionDefecto;

            IF @idEstadoActual IS NULL
                SELECT @err = 'RCN_001', @e1 = CONVERT(NVARCHAR(36), @idRevisionDefecto), @e2 = CONVERT(NVARCHAR(36), @idUsuarioEjecutorDefecto);
            ELSE IF @usuarioProponente IS NOT NULL AND @usuarioProponente = @idUsuarioEjecutorDefecto
                SELECT @err = 'RCN_014', @e1 = CONVERT(NVARCHAR(36), @idUsuarioEjecutorDefecto), @e2 = CONVERT(NVARCHAR(36), @idRevisionDefecto);
            ELSE
            BEGIN
                SELECT f.idUsuario, f.codigoPerfil, f.idPrograma, f.esEscalamiento INTO #culmc_res
                FROM dbo.ufn_revision_cancelacion_resolutores(@idEstudianteGrupo, @usuarioProponente) f;
                SELECT TOP 1 @perfilEjecutor = x.codigoPerfil FROM #culmc_res x WHERE x.idUsuario = @idUsuarioEjecutorDefecto;
                IF @perfilEjecutor IS NULL
                    SELECT @err = 'RCN_001', @e1 = CONVERT(NVARCHAR(36), @idRevisionDefecto), @e2 = CONVERT(NVARCHAR(36), @idUsuarioEjecutorDefecto);
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
                SELECT @codigoEstadoActual = es.codigo, @nombreEstadoActual = es.nombre FROM dbo.EstadoRevisionCancelacion es WHERE es.id = @idEstadoActual;
                SELECT @idGrupo = eg.grupo, @idEstudiante = eg.estudiante, @codigoMatricula = ee.codigo
                FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado WHERE eg.id = @idEstudianteGrupo;
                SELECT @porcentaje = rs.porcentajeInasistencia FROM dbo.uv_resumen_asistencia_estudiante_grupo rs WHERE rs.idEstudianteGrupo = @idEstudianteGrupo;
                SELECT TOP 1 @umbral = dbo.ufn_umbral_alerta_inasistencia(t.id) FROM dbo.TipoAlertaInasistencia t WHERE t.creaRevisionCancelacion = 1;
                SELECT TOP 1 @idPrograma = x.idPrograma FROM #culmc_res x INNER JOIN dbo.Programa p ON p.id = x.idPrograma
                WHERE x.idUsuario = @idUsuarioEjecutorDefecto ORDER BY p.nombre, p.id;
                SET @ahora = CAST(SYSUTCDATETIME() AS DATETIME2(3));

                -- Idempotencia: quien pida lo mismo que ya quedo registrado (sea quien sea el que resolvio antes)
                IF EXISTS (SELECT 1 FROM dbo.TransicionRevisionCancelacion t WHERE t.codigoDecision = @decision AND t.esDecisionResolutor = 1 AND t.estadoDestino = @idEstadoActual)
                BEGIN
                    SET @sinCambios = 1;
                    SELECT @codigoMensajeOk = 'RCN_011', @p1ok = CONVERT(NVARCHAR(36), @idRevisionDefecto), @p2ok = @codigoEstadoActual;
                END
                ELSE
                BEGIN
                    SELECT @idTransicion = t.id, @idEstadoDestino = t.estadoDestino, @exigeUmbral = t.exigeUmbralPerdida, @codigoMensajeTransicion = t.codigoMensajeExito,
                           @plantilla = t.tipoPlantillaNotificacion
                    FROM dbo.TransicionRevisionCancelacion t
                    WHERE t.estadoOrigen = @idEstadoActual AND t.codigoDecision = @decision AND t.esDecisionResolutor = 1;
                    IF @idTransicion IS NULL
                        SELECT @err = 'RCN_004', @e1 = @nombreEstadoActual, @e2 = @decision;
                    ELSE IF @codigoMatricula <> @codigoInscrita
                        SELECT @err = 'RCN_005', @e1 = CONVERT(NVARCHAR(36), @idEstudianteGrupo), @e2 = @codigoMatricula;
                    ELSE IF @exigeUmbral = 1 AND (@porcentaje IS NULL OR @umbral IS NULL OR @porcentaje < @umbral)
                        SELECT @err = 'RCN_006', @e1 = CONVERT(NVARCHAR(20), @porcentaje), @e2 = CONVERT(NVARCHAR(20), @umbral);
                    ELSE
                    BEGIN
                        SELECT @cancela = es.cancelaMatricula, @codigoEstadoDestino = es.codigo FROM dbo.EstadoRevisionCancelacion es WHERE es.id = @idEstadoDestino;
                        IF @cancela = 1
                        BEGIN
                            SELECT @estadoCanceladaId = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = @codigoCancelada;
                            IF @estadoCanceladaId IS NULL
                                THROW 52702, 'CULM001_C_CATALOGO_INCONSISTENTE: falta el estado de matricula cancelada por inasistencia.', 1;
                            SELECT @estadoMatriculaActualId = eg.estado FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK) WHERE eg.id = @idEstudianteGrupo;
                            IF NOT EXISTS (SELECT 1 FROM dbo.EstadoEstudianteGrupo WHERE id = @estadoMatriculaActualId AND codigo = @codigoInscrita)
                                SELECT @err = 'RCN_005', @e1 = CONVERT(NVARCHAR(36), @idEstudianteGrupo), @e2 = (SELECT codigo FROM dbo.EstadoEstudianteGrupo WHERE id = @estadoMatriculaActualId);
                            ELSE
                            BEGIN
                                UPDATE dbo.EstudianteGrupo SET estado = @estadoCanceladaId WHERE id = @idEstudianteGrupo;
                                SET @cambioMatricula = 1;
                            END
                        END
                        IF @err IS NULL
                        BEGIN
                            IF @codigoEstadoDestino IS NULL SELECT @codigoEstadoDestino = codigo FROM dbo.EstadoRevisionCancelacion WHERE id = @idEstadoDestino;
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
                                    IIF(@perfilEjecutor = N'DECANO', N'/api/v1/decano/revisiones-cancelacion/{revisionId}', N'/api/v1/coordinador/revisiones-cancelacion/{revisionId}'), 200,
                                    (SELECT estadoAnterior = @codigoEstadoActual, estadoNuevo = @codigoEstadoDestino, decision = @decision, motivo = @motivoLimpio,
                                            porcentajeInasistencia = @porcentaje, perfilResolutor = @perfilEjecutor,
                                            escalada = CAST(IIF(EXISTS (SELECT 1 FROM #culmc_res WHERE esEscalamiento = 1), 1, 0) AS BIT),
                                            matriculaAnterior = IIF(@cambioMatricula = 1, @codigoInscrita, NULL), matriculaNueva = IIF(@cambioMatricula = 1, @codigoCancelada, NULL)
                                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
                            SELECT @codigoMensajeOk = @codigoMensajeTransicion, @p1ok = CONVERT(NVARCHAR(36), @idRevisionDefecto), @p2ok = CONVERT(NVARCHAR(36), @idEstudianteGrupo);
                        END
                    END
                END
            END

            IF @err IS NULL AND @estadoResultado = 1
            BEGIN
                SELECT @codigoEstadoAnteriorOut = @codigoEstadoActual, @codigoEstadoNuevoOut = IIF(@sinCambios = 1, @codigoEstadoActual, @codigoEstadoDestino);
                IF @transaccionPropia = 1
                BEGIN
                    IF XACT_STATE() = 1 COMMIT TRANSACTION; ELSE IF XACT_STATE() = -1 ROLLBACK TRANSACTION;
                    SET @transaccionPropia = 0;
                END
            END
            ELSE
            BEGIN
                -- Todas las validaciones preceden a las escrituras: aqui no hay nada que revertir. Se libera con COMMIT (y sin ROLLBACK)
                -- para que el SP tambien funcione dentro de INSERT ... EXEC.
                IF @transaccionPropia = 1
                BEGIN
                    IF XACT_STATE() = 1 COMMIT TRANSACTION;
                    SET @transaccionPropia = 0;
                END
            END
        END

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
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_resolver_revision;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

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
