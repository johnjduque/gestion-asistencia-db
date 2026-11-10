-- ============================================================================
-- MIGRACION UP 31: CULM-001 / DEC-065 (1) - la cancelacion por inasistencia la decide el coordinador (sin escalar al decano) y el docente
-- consulta sus revisiones
-- Modifica (CREATE OR ALTER) ufn_revision_cancelacion_resolutores (sin la CTE de decanos; esEscalamiento siempre 0), usp_decidir_revision_cancelacion
-- (perfil siempre COORDINADOR; sin coordinador RCN_013 con texto nuevo; sin historial ESCALAR), usp_actualizar_resolutores_revisiones_cancelacion
-- (solo REASIGNAR, nunca DECANO), usp_resolver_revision_cancelacion (el decano recibe RCN_016) y
-- usp_consultar_revisiones_cancelacion_decano_paginado (solo consulta: todas las revisiones de su facultad). Crea
-- usp_consultar_revisiones_cancelacion_docente_paginado y le concede EXECUTE al rol runtime. Actualiza RCN_013 y RCN_015 (en desuso) y siembra RCN_016
-- (MERGE). Las revisiones que estuvieran escaladas al decano se reasignan al coordinador en la siguiente corrida de
-- usp_actualizar_resolutores_revisiones_cancelacion (huella distinta, evento REASIGNAR). Idempotente. Down: 31_..._down.sql.
-- ============================================================================
PRINT 'MIGRACION 31 UP: la cancelacion por inasistencia la decide el coordinador';
GO
-- ---- schema/functions/ufn_revision_cancelacion_resolutores.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.3, O-1, O-2) + DEC-065 (1): usuarios que pueden resolver una revision de cancelacion. La decision final es del
-- coordinador del programa: no hay escalamiento al decano. Programas competentes = EstudiantePrograma del estudiante que ademas son
-- programas vigentes del grupo (regla S1 de B2, replicada de ufn_programas_grupo para no depender del orden de despliegue; la paridad la
-- prueba C-DB-63). Resolutores = coordinadores titulares activos (Programa.coordinador) de esos programas, sin @idUsuarioExcluido (quien
-- propuso). esEscalamiento se conserva por compatibilidad de los consumidores y es siempre 0. Solo tablas base.
CREATE OR ALTER FUNCTION [dbo].[ufn_revision_cancelacion_resolutores] (@idEstudianteGrupo UNIQUEIDENTIFIER, @idUsuarioExcluido UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    WITH vigentes AS (
        SELECT DISTINCT idPrograma = pe.programa, eg.estudiante
        FROM dbo.EstudianteGrupo eg
        INNER JOIN dbo.Grupo g ON g.id = eg.grupo
        INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
        INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = g.asignatura
        INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
        CROSS APPLY (SELECT zona = COALESCE((SELECT TOP 1 valor FROM dbo.CatalogoParametro
                                             WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1),
                                            'SA Pacific Standard Time')) z
        WHERE eg.id = @idEstudianteGrupo
          AND CAST(ape.fechaVinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) <= pa.fechaFin
          AND (ape.fechaDesvinculacionUtc IS NULL
               OR CAST(ape.fechaDesvinculacionUtc AT TIME ZONE 'UTC' AT TIME ZONE z.zona AS DATE) >= pa.fechaInicio)
    ),
    competentes AS (
        SELECT idPrograma = p.id, idFacultad = p.facultad, idCoordinador = p.coordinador
        FROM vigentes v
        INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = v.estudiante AND ep.programa = v.idPrograma
        INNER JOIN dbo.Programa p ON p.id = v.idPrograma AND p.estado = 1
    ),
    coordinadores AS (
        SELECT DISTINCT idUsuario = u.id, codigoPerfil = CAST(N'COORDINADOR' AS NVARCHAR(20)), c.idPrograma, c.idFacultad, esEscalamiento = CAST(0 AS BIT)
        FROM competentes c
        INNER JOIN dbo.Coordinador co ON co.id = c.idCoordinador AND co.estado = 1
        INNER JOIN dbo.Usuario u ON u.id = co.usuario AND u.estado = 1
        WHERE (@idUsuarioExcluido IS NULL OR u.id <> @idUsuarioExcluido)
    )
    SELECT idUsuario, codigoPerfil, idPrograma, idFacultad, esEscalamiento FROM coordinadores
);
GO
GO
-- ---- schema/stored-procedures/usp_decidir_revision_cancelacion.sql
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
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- RCN_002 decision del docente; RCN_003 motivo
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.TransicionRevisionCancelacion t WHERE t.codigoDecision = @decision AND t.esDecisionResolutor = 0)
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
                SAVE TRANSACTION sp_decidir_revision;
                SET @savepointCreado = 1;
            END

            SELECT @idEstadoActual = r.estado, @idEstudianteGrupo = r.estudianteGrupo, @decisionPrevia = r.codigoDecisionDocente,
                   @idGrupo = g.id, @idEstudiante = eg.estudiante, @codigoMatricula = ee.codigo
            FROM dbo.RevisionCancelacion r WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo
            INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
            INNER JOIN dbo.Grupo g ON g.id = eg.grupo
            INNER JOIN dbo.Docente d ON d.id = g.docente
            WHERE r.id = @idRevisionDefecto AND d.usuario = @idUsuarioEjecutorDefecto;

            IF @idEstadoActual IS NULL
                SELECT @err = 'RCN_001', @e1 = CONVERT(NVARCHAR(36), @idRevisionDefecto), @e2 = CONVERT(NVARCHAR(36), @idUsuarioEjecutorDefecto);
            ELSE
            BEGIN
                SELECT @codigoEstadoActual = es.codigo, @nombreEstadoActual = es.nombre FROM dbo.EstadoRevisionCancelacion es WHERE es.id = @idEstadoActual;
                SELECT @porcentaje = rs.porcentajeInasistencia FROM dbo.uv_resumen_asistencia_estudiante_grupo rs WHERE rs.idEstudianteGrupo = @idEstudianteGrupo;
                SELECT TOP 1 @umbral = dbo.ufn_umbral_alerta_inasistencia(t.id) FROM dbo.TipoAlertaInasistencia t WHERE t.creaRevisionCancelacion = 1;
                SET @ahora = CAST(SYSUTCDATETIME() AS DATETIME2(3));

                IF @codigoMatricula <> @codigoInscrita
                    SELECT @err = 'RCN_005', @e1 = CONVERT(NVARCHAR(36), @idEstudianteGrupo), @e2 = @codigoMatricula;

                -- Idempotencia: la misma decision que dejo el estado actual
                IF @err IS NULL AND @decisionPrevia = @decision
                   AND EXISTS (SELECT 1 FROM dbo.TransicionRevisionCancelacion t WHERE t.codigoDecision = @decision AND t.esDecisionResolutor = 0 AND t.estadoDestino = @idEstadoActual)
                BEGIN
                    SET @sinCambios = 1;
                    SELECT @codigoMensajeOk = 'RCN_011', @p1ok = CONVERT(NVARCHAR(36), @idRevisionDefecto), @p2ok = @codigoEstadoActual;
                END
                ELSE IF @err IS NULL
                BEGIN
                    SELECT @idTransicion = t.id, @idEstadoDestino = t.estadoDestino, @exigeUmbral = t.exigeUmbralPerdida, @exigeResolutor = t.exigeResolutorDisponible,
                           @codigoMensajeTransicion = t.codigoMensajeExito, @plantilla = t.tipoPlantillaNotificacion
                    FROM dbo.TransicionRevisionCancelacion t
                    WHERE t.estadoOrigen = @idEstadoActual AND t.codigoDecision = @decision AND t.esDecisionResolutor = 0;
                    IF @idTransicion IS NULL
                        SELECT @err = 'RCN_004', @e1 = @nombreEstadoActual, @e2 = @decision;
                    ELSE IF @exigeUmbral = 1 AND (@porcentaje IS NULL OR @umbral IS NULL OR @porcentaje < @umbral)
                        SELECT @err = 'RCN_006', @e1 = CONVERT(NVARCHAR(20), @porcentaje), @e2 = CONVERT(NVARCHAR(20), @umbral);
                    ELSE
                    BEGIN
                        IF @exigeResolutor = 1
                        BEGIN
                            SELECT f.idUsuario, f.codigoPerfil INTO #culmc_res
                            FROM dbo.ufn_revision_cancelacion_resolutores(@idEstudianteGrupo, @idUsuarioEjecutorDefecto) f;
                            IF NOT EXISTS (SELECT 1 FROM #culmc_res)
                                SELECT @err = 'RCN_013', @e1 = CONVERT(NVARCHAR(36), @idEstudianteGrupo);
                            ELSE
                            BEGIN
                                SET @perfilResolutor = N'COORDINADOR';
                                SELECT @huella = HASHBYTES('SHA2_256', STRING_AGG(CONVERT(VARCHAR(36), x.idUsuario), ',') WITHIN GROUP (ORDER BY CONVERT(VARCHAR(36), x.idUsuario)))
                                FROM (SELECT DISTINCT idUsuario FROM #culmc_res) x;
                            END
                        END

                        IF @err IS NULL
                        BEGIN
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

                            SELECT @codigoEstadoDestino = codigo FROM dbo.EstadoRevisionCancelacion WHERE id = @idEstadoDestino;
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

            IF @err IS NULL
            BEGIN
                SELECT @codigoEstadoAnteriorOut = @codigoEstadoActual,
                       @codigoEstadoNuevoOut = IIF(@sinCambios = 1, @codigoEstadoActual, @codigoEstadoDestino);
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
            ROLLBACK TRANSACTION sp_decidir_revision;

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
        idGrupo                   = IIF(@estadoResultado = 1, @idGrupo, NULL),
        idEstudianteGrupo         = IIF(@estadoResultado = 1, @idEstudianteGrupo, NULL),
        idEstudiante              = IIF(@estadoResultado = 1, @idEstudiante, NULL),
        porcentajeActual          = IIF(@estadoResultado = 1, @porcentaje, NULL),
        tipoPlantillaNotificacion = IIF(@estadoResultado = 1 AND @sinCambios = 0, @plantilla, NULL),
        codigoPerfilResolutor     = IIF(@estadoResultado = 1, @perfilResolutor, NULL),
        esEscalamiento            = IIF(@estadoResultado = 1, CAST(0 AS BIT), NULL);
END;
GO
GO
-- ---- schema/stored-procedures/usp_actualizar_resolutores_revisiones_cancelacion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_actualizar_resolutores_revisiones_cancelacion (CULM-001 C.1; CONTRACT §2.5.11, SUPUESTO-C-09, O-2, DEC-043)
--
-- Comando de SISTEMA (job). Recorre (lote ALERTA_INASISTENCIA/LOTE_EVALUACION_AUTOMATICA) las revisiones que esperan al resolutor
-- con matricula activa y recalcula sus resolutores en vivo; si la huella cambio (coordinador desactivado o reasignado, programa
-- cambiado) actualiza el perfil resolutor (REASIGNAR a otro coordinador; DEC-065: nunca al decano), deja historial + auditoria y devuelve la novedad
-- para el aviso. Sin resolutor posible: perfil NULL, REASIGNAR y REVISION_CANCELACION_SIN_RESOLUTOR una sola vez por cambio de
-- huella. Una transaccion por revision (o la del llamador). Salida: tupla + revisionesReasignadas, revisionesEscaladas (siempre 0),
-- revisionesSinResolutor, novedadesJSON. ALR_007.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_resolutores_revisiones_cancelacion]
(
    @idCorrelacion UNIQUEIDENTIFIER,
    @tamanoLote    INT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @lote INT = ISNULL(@tamanoLote, TRY_CAST(CAST(dbo.ufn_obtener_parametro('ALERTA_INASISTENCIA', 'LOTE_EVALUACION_AUTOMATICA') AS NVARCHAR(20)) AS INT));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @transaccionExterna BIT = IIF(@@TRANCOUNT > 0, 1, 0);
    DECLARE @reasignadas INT = 0, @escaladas INT = 0, @sinResolutor INT = 0;
    DECLARE @novedadesJSON NVARCHAR(MAX) = N'[]';
    DECLARE @i INT = 1, @max INT, @idRevision UNIQUEIDENTIFIER;
    DECLARE @idEg UNIQUEIDENTIFIER, @usuarioProponente UNIQUEIDENTIFIER, @huellaPrev VARBINARY(32), @perfilPrev NVARCHAR(20), @idEstado UNIQUEIDENTIFIER;
    DECLARE @huellaNueva VARBINARY(32), @perfilNuevo NVARCHAR(20), @evento NVARCHAR(20), @porcentaje DECIMAL(5,2), @ahora DATETIME2(3);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500), @p3 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        IF @estadoResultado = 1 AND (@lote IS NULL OR @lote < 1)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = N'1', @p_param2 = N'0',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            CREATE TABLE #culmc_pend (n INT IDENTITY(1,1) PRIMARY KEY, idRevision UNIQUEIDENTIFIER NOT NULL);
            CREATE TABLE #culmc_nov (json NVARCHAR(MAX) NOT NULL);
            INSERT INTO #culmc_pend (idRevision)
            SELECT TOP (@lote) r.id
            FROM dbo.RevisionCancelacion r
            INNER JOIN dbo.EstadoRevisionCancelacion es ON es.id = r.estado AND es.requiereAccionResolutor = 1
            INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo
            INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado AND ee.codigo = @codigoInscrita
            ORDER BY r.fechaDecisionDocenteUtc ASC, r.id ASC;
            SELECT @max = COUNT(1) FROM #culmc_pend;

            WHILE @i <= @max
            BEGIN
                SELECT @idRevision = idRevision FROM #culmc_pend WHERE n = @i;
                SET @i += 1;
                BEGIN TRY
                    IF @transaccionExterna = 0 BEGIN TRANSACTION;
                    SET @idEg = NULL;
                    SELECT @idEg = r.estudianteGrupo, @usuarioProponente = r.usuarioDecisionDocente, @huellaPrev = r.huellaResolutoresActual,
                           @perfilPrev = r.codigoPerfilResolutorActual, @idEstado = r.estado
                    FROM dbo.RevisionCancelacion r WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.EstadoRevisionCancelacion es ON es.id = r.estado AND es.requiereAccionResolutor = 1
                    WHERE r.id = @idRevision;

                    IF @idEg IS NOT NULL
                    BEGIN
                        IF OBJECT_ID(N'tempdb..#culmc_res') IS NOT NULL DROP TABLE #culmc_res;
                        SELECT f.idUsuario, f.codigoPerfil, f.idPrograma, f.esEscalamiento INTO #culmc_res
                        FROM dbo.ufn_revision_cancelacion_resolutores(@idEg, @usuarioProponente) f;
                        SELECT @huellaNueva = NULL, @perfilNuevo = NULL;
                        IF EXISTS (SELECT 1 FROM #culmc_res)
                        BEGIN
                            SET @perfilNuevo = N'COORDINADOR';
                            SELECT @huellaNueva = HASHBYTES('SHA2_256', STRING_AGG(CONVERT(VARCHAR(36), x.idUsuario), ',') WITHIN GROUP (ORDER BY CONVERT(VARCHAR(36), x.idUsuario)))
                            FROM (SELECT DISTINCT idUsuario FROM #culmc_res) x;
                        END

                        IF NOT (ISNULL(CONVERT(VARCHAR(80), @huellaNueva, 2), '') = ISNULL(CONVERT(VARCHAR(80), @huellaPrev, 2), '') AND ISNULL(@perfilNuevo, N'') = ISNULL(@perfilPrev, N''))
                        BEGIN
                            SET @ahora = CAST(SYSUTCDATETIME() AS DATETIME2(3));
                            SELECT @porcentaje = rs.porcentajeInasistencia FROM dbo.uv_resumen_asistencia_estudiante_grupo rs WHERE rs.idEstudianteGrupo = @idEg;
                            SET @porcentaje = ISNULL(@porcentaje, 0);
                            SET @evento = N'REASIGNAR';
                            UPDATE dbo.RevisionCancelacion
                            SET codigoPerfilResolutorActual = @perfilNuevo, huellaResolutoresActual = @huellaNueva,
                                fechaActualizacionUtc = @ahora
                            WHERE id = @idRevision;
                            INSERT INTO dbo.RevisionCancelacionHistorial (id, revision, estadoAnterior, estadoNuevo, codigoEvento, motivo, usuarioActor, codigoPerfilActor,
                                codigoPerfilResolutor, porcentajeInasistencia, fechaUtc, idCorrelacion)
                            VALUES (NEWID(), @idRevision, @idEstado, @idEstado, @evento, NULL, NULL, NULL, @perfilNuevo, @porcentaje, @ahora, @idCorrelacionDefecto);

                            IF @perfilNuevo IS NULL
                                INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId, httpMethod, path, httpStatus, metadata)
                                VALUES (NEWID(), SYSDATETIMEOFFSET(), N'SISTEMA', 'SYSTEM', 'REVISION_CANCELACION_SIN_RESOLUTOR', 'RevisionCancelacion', CONVERT(NVARCHAR(36), @idRevision),
                                        'SUCCESS', @idCorrelacionDefecto, 'JOB', N'/jobs/alertas-inasistencia', 200,
                                        (SELECT perfilAnterior = @perfilPrev, causa = N'SIN_COORDINADOR_ACTIVO' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
                            ELSE
                                INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId, httpMethod, path, httpStatus, metadata)
                                VALUES (NEWID(), SYSDATETIMEOFFSET(), N'SISTEMA', 'SYSTEM', 'REASIGNAR_REVISION_CANCELACION',
                                        'RevisionCancelacion', CONVERT(NVARCHAR(36), @idRevision), 'SUCCESS', @idCorrelacionDefecto, 'JOB', N'/jobs/alertas-inasistencia', 200,
                                        (SELECT perfilAnterior = @perfilPrev, perfilNuevo = @perfilNuevo, causa = N'RESOLUTORES_CAMBIARON' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

                            IF @perfilNuevo IS NULL SET @sinResolutor += 1;
                            ELSE SET @reasignadas += 1;

                            INSERT INTO #culmc_nov (json)
                            SELECT (SELECT idRevision = rv.id, idGrupo = rv.idGrupo, codigoGrupo = rv.codigoGrupo, nombreGrupo = rv.nombreGrupo, nombreAsignatura = rv.nombreAsignatura,
                                           idEstudianteGrupo = rv.idEstudianteGrupo, perfilResolutor = @perfilNuevo, evento = @evento, porcentajeInasistencia = @porcentaje,
                                           umbral = rs.umbralPerdida, motivo = rv.motivoDocente, nombreCompletoEstudiante = rv.nombreCompletoEstudiante,
                                           nombreCompletoDocente = rv.nombreCompletoDocente, idUsuarioDocente = rv.idUsuarioDocenteTitular, idUsuarioEstudiante = rv.idUsuarioEstudiante,
                                           resolutores = JSON_QUERY((SELECT idUsuario = u.id, codigoPerfil = x.codigoPerfil, esEscalamiento = x.esEscalamiento, correo = u.correo,
                                                                            nombreCompleto = CONCAT(LTRIM(RTRIM(CONCAT(u.primerNombre, N' ', u.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(u.primerApellido, N' ', u.segundoApellido))))
                                                                     FROM (SELECT DISTINCT idUsuario, codigoPerfil, esEscalamiento FROM #culmc_res) x
                                                                     INNER JOIN dbo.Usuario u ON u.id = x.idUsuario FOR JSON PATH))
                                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
                            FROM dbo.uv_revision_cancelacion rv
                            LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo rs ON rs.idEstudianteGrupo = rv.idEstudianteGrupo
                            WHERE rv.id = @idRevision;
                        END
                    END
                    IF @transaccionExterna = 0 AND XACT_STATE() = 1 COMMIT TRANSACTION;
                END TRY
                BEGIN CATCH
                    IF @transaccionExterna = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
                    ELSE IF @transaccionExterna = 1 AND XACT_STATE() = -1 THROW;
                END CATCH
            END

            SELECT @novedadesJSON = ISNULL(CONCAT(N'[', (SELECT STRING_AGG(json, N',') FROM #culmc_nov), N']'), N'[]');
            IF @novedadesJSON IS NULL OR @novedadesJSON = N'[]' OR @novedadesJSON = N'[NULL]' SET @novedadesJSON = N'[]';

            SELECT @p1 = CONVERT(NVARCHAR(20), @reasignadas), @p2 = CONVERT(NVARCHAR(20), @escaladas), @p3 = CONVERT(NVARCHAR(20), @sinResolutor);
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ALR_007', @p_param1 = @p1, @p_param2 = @p2, @p_param3 = @p3,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        IF XACT_STATE() = -1 AND @transaccionExterna = 1 THROW;
        IF XACT_STATE() <> 0 AND @transaccionExterna = 0 ROLLBACK TRANSACTION;
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SELECT @reasignadas = 0, @escaladas = 0, @sinResolutor = 0, @novedadesJSON = N'[]';
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        revisionesReasignadas   = @reasignadas,
        revisionesEscaladas     = @escaladas,
        revisionesSinResolutor  = @sinResolutor,
        novedadesJSON           = @novedadesJSON;
END;
GO
GO
-- ---- schema/stored-procedures/usp_resolver_revision_cancelacion.sql
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
                SELECT f.idUsuario, f.codigoPerfil, f.idPrograma INTO #culmc_res
                FROM dbo.ufn_revision_cancelacion_resolutores(@idEstudianteGrupo, @usuarioProponente) f;
                SELECT TOP 1 @perfilEjecutor = x.codigoPerfil FROM #culmc_res x WHERE x.idUsuario = @idUsuarioEjecutorDefecto;
                IF @perfilEjecutor IS NULL AND EXISTS (SELECT 1 FROM dbo.Decano d WHERE d.usuario = @idUsuarioEjecutorDefecto AND d.estado = 1)
                    SELECT @err = 'RCN_016', @e1 = CONVERT(NVARCHAR(36), @idUsuarioEjecutorDefecto), @e2 = CONVERT(NVARCHAR(36), @idRevisionDefecto);
                ELSE IF @perfilEjecutor IS NULL
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
GO
-- ---- schema/stored-procedures/usp_consultar_revisiones_cancelacion_decano_paginado.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_revisiones_cancelacion_decano_paginado (CULM-001 C.1; CONTRACT §2.5.7, SUPUESTO-C-14, DEC-043, DEC-065 (1))
--
-- READ_QUERY_RESULTSET paginado (THROW 51000 si la validacion falla). RBAC DECANO. SOLO CONSULTA Y AUDITORIA: todas las revisiones (cualquier
-- estado) de los grupos que tienen algun programa de la facultad del decano (ufn_programas_ambito_ejecutor); la decision final es del
-- coordinador, por eso esResolutorActual es siempre 0 y accionesPermitidas siempre vacio. @soloPendientes = revisiones que esperan al
-- resolutor (propuestas). @idPrograma fuera de su facultad -> COO_003; @codigoEstado inexistente -> RCN_002. Mismas columnas que la
-- bandeja del coordinador.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_revisiones_cancelacion_decano_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 20,
    @soloPendientes    BIT = 0,
    @codigoEstado      NVARCHAR(20) = NULL,
    @idPrograma        UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
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
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DECANO', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1 AND @codigoEstado IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.EstadoRevisionCancelacion e WHERE e.codigo = UPPER(TRIM(@codigoEstado)))
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCN_002', @p_param1 = @codigoEstado,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1 AND @idPrograma IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_ambito_ejecutor(@idUsuarioDefecto) a WHERE a.idPrograma = @idPrograma AND a.rol = N'DECANO')
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'COO_003',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    SELECT
        rv.*,
        idPrograma = x.idPrograma,
        nombrePrograma = x.nombre,
        porcentajeActual = rs.porcentajeInasistencia,
        horasFaltaActual = rs.horasFalta,
        horasDictadasActual = rs.horasDictadas,
        umbralPerdida = rs.umbralPerdida,
        esResolutorActual = CAST(0 AS BIT),
        accionesPermitidas = CAST(N'' AS NVARCHAR(200)),
        totalRegistros = COUNT(1) OVER()
    FROM dbo.uv_revision_cancelacion rv
    CROSS APPLY (
        SELECT TOP 1 idPrograma = p.id, p.nombre
        FROM dbo.ufn_programas_grupo(rv.idGrupo) pg
        INNER JOIN dbo.ufn_programas_ambito_ejecutor(@idUsuarioDefecto) a ON a.idPrograma = pg.idPrograma AND a.rol = N'DECANO'
        INNER JOIN dbo.Programa p ON p.id = pg.idPrograma
        WHERE (@idPrograma IS NULL OR p.id = @idPrograma)
        ORDER BY p.nombre ASC, p.id ASC
    ) x
    LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo rs ON rs.idEstudianteGrupo = rv.idEstudianteGrupo
    WHERE (@codigoEstado IS NULL OR rv.codigoEstado = UPPER(TRIM(@codigoEstado)))
      AND (@soloPendientes IS NULL OR @soloPendientes = 0 OR rv.requiereAccionResolutor = 1)
    ORDER BY rv.requiereAccionResolutor DESC, rv.fechaActualizacionUtc DESC, rv.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_revisiones_cancelacion_docente_paginado.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_revisiones_cancelacion_docente_paginado (DEC-065 (1), HU026C; CONTRACT §2.5.7)
--
-- READ_QUERY_RESULTSET paginado (THROW 51000 si la validacion falla). RBAC DOCENTE. Revisiones de cancelacion por inasistencia de los
-- grupos donde el ejecutor es docente titular (uv_revision_cancelacion), en cualquier estado: el docente sigue la propuesta y la decision
-- del coordinador sin poder resolver. Mismas columnas que usp_consultar_revisiones_cancelacion_coordinador_paginado: uv_revision_cancelacion
-- + idPrograma, nombrePrograma, porcentajeActual, horasFaltaActual, horasDictadasActual, umbralPerdida, esResolutorActual (siempre 0),
-- accionesPermitidas (siempre vacio) y totalRegistros. @soloPendientes = revisiones que esperan la decision del docente (estado con
-- requiereAccionDocente, PENDIENTE_DOCENTE). Orden: fecha de cruce (creacion) DESC. @idGrupo que no es suyo -> SEC_002;
-- @estado inexistente -> RCN_002.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_revisiones_cancelacion_docente_paginado]
(
    @idUsuario      UNIQUEIDENTIFIER,
    @idCorrelacion  UNIQUEIDENTIFIER,
    @soloPendientes BIT = 1,
    @idGrupo        UNIQUEIDENTIFIER = NULL,
    @estado         NVARCHAR(20) = NULL,
    @numeroPagina   INT = 1,
    @tamanoPagina   INT = 20
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuario, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuario IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuario',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1 AND @estado IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.EstadoRevisionCancelacion e WHERE e.codigo = UPPER(TRIM(@estado)))
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCN_002', @p_param1 = @estado,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1 AND @idGrupo IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente WHERE g.id = @idGrupo AND d.usuario = @idUsuarioDefecto)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SEC_002', @p_param1 = 'Grupo del docente',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    SELECT
        rv.*,
        idPrograma = x.idPrograma,
        nombrePrograma = x.nombre,
        porcentajeActual = rs.porcentajeInasistencia,
        horasFaltaActual = rs.horasFalta,
        horasDictadasActual = rs.horasDictadas,
        umbralPerdida = rs.umbralPerdida,
        esResolutorActual = CAST(0 AS BIT),
        accionesPermitidas = CAST(N'' AS NVARCHAR(200)),
        totalRegistros = COUNT(1) OVER()
    FROM dbo.uv_revision_cancelacion rv
    OUTER APPLY (
        SELECT TOP 1 idPrograma = p.id, p.nombre
        FROM dbo.EstudiantePrograma ep
        INNER JOIN dbo.ufn_programas_grupo(rv.idGrupo) pg ON pg.idPrograma = ep.programa
        INNER JOIN dbo.Programa p ON p.id = pg.idPrograma
        WHERE ep.estudiante = rv.idEstudiante
        ORDER BY p.nombre ASC, p.id ASC
    ) x
    LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo rs ON rs.idEstudianteGrupo = rv.idEstudianteGrupo
    WHERE rv.idUsuarioDocenteTitular = @idUsuarioDefecto
      AND (@estado IS NULL OR rv.codigoEstado = UPPER(TRIM(@estado)))
      AND (@idGrupo IS NULL OR rv.idGrupo = @idGrupo)
      AND (@soloPendientes IS NULL OR @soloPendientes = 0 OR rv.requiereAccionDocente = 1)
    ORDER BY rv.fechaCreacionUtc DESC, rv.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
GO
-- ---- schema/seed/40_culm001_c_mensajes.sql (RCN_013, RCN_015, RCN_016 de DEC-065)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('RCN_013', 'BUSINESS_ERROR',   'MEDIO', N'El programa no tiene coordinador activo para resolver la revisión; solicite su asignación al decano.'),
    ('RCN_015', 'SUCCESS',          'BAJO',  N'Mensaje en desuso (DEC-065): la propuesta ya no se envía a la decanatura; la decisión final es del coordinador.'),
    ('RCN_016', 'BUSINESS_ERROR',   'MEDIO', N'La resolución de la revisión corresponde al coordinador del programa.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('RCN_013', 'BUSINESS_ERROR',   'MEDIO', N'ufn_revision_cancelacion_resolutores vacío para [{}] (sin coordinador activo; DEC-065: no se escala al decano).'),
    ('RCN_015', 'SUCCESS',          'BAJO',  N'En desuso (DEC-065): ya no se escala la revisión [{}] a DECANO.'),
    ('RCN_016', 'BUSINESS_ERROR',   'MEDIO', N'Regla DEC-065: el ejecutor [{}] es decano y no resuelve la revisión [{}]; solo el coordinador del programa; sin escrituras.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- ---- schema/security/rol_asistencias_runtime_culm001_c.sql (bloque DEC-065)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO
IF OBJECT_ID(N'dbo.usp_consultar_revisiones_cancelacion_docente_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_revisiones_cancelacion_docente_paginado] TO [rol_asistencias_runtime];
GO
PRINT 'MIGRACION 31 UP OK';
GO
