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
-- SKILLS-BD lote 11 (2026-11-26): PASO n, IF con BEGIN/END, IIF en lugar de ISNULL y lecturas sin bloqueo por vistas uv_* (antes,
-- las tablas). La lectura con UPDLOCK, HOLDLOCK de dbo.RevisionCancelacion y las escrituras siguen en las tablas. Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): job del servidor sin @idUsuarioEjecutor; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_resolutores_revisiones_cancelacion]
(
    @idCorrelacion UNIQUEIDENTIFIER,
    @tamanoLote    INT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @lote INT = IIF(@tamanoLote IS NULL, TRY_CAST(CAST(dbo.ufn_obtener_parametro('ALERTA_INASISTENCIA', 'LOTE_EVALUACION_AUTOMATICA') AS NVARCHAR(20)) AS INT), @tamanoLote);
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
        -- PASO 1: Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        -- PASO 2: Validar tamano del lote (PAG_001)
        IF @estadoResultado = 1 AND (@lote IS NULL OR @lote < 1)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = N'1', @p_param2 = N'0',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            -- PASO 3: Revisiones que esperan al resolutor con matricula inscrita (lote)
            CREATE TABLE #culmc_pend (n INT IDENTITY(1,1) PRIMARY KEY, idRevision UNIQUEIDENTIFIER NOT NULL);
            CREATE TABLE #culmc_nov (json NVARCHAR(MAX) NOT NULL);
            INSERT INTO #culmc_pend (idRevision)
            SELECT TOP (@lote) r.id
            FROM dbo.uv_revision_cancelacion_registro r
            INNER JOIN dbo.uv_estado_revision_cancelacion es ON es.id = r.idEstado AND es.requiereAccionResolutor = 1
            INNER JOIN dbo.uv_estudiante_grupo_registro eg ON eg.id = r.idEstudianteGrupo
            INNER JOIN dbo.uv_estado_estudiante_grupo ee ON ee.id = eg.idEstado AND ee.codigo = @codigoInscrita
            ORDER BY r.fechaDecisionDocenteUtc ASC, r.id ASC;
            SELECT @max = COUNT(1) FROM #culmc_pend;

            WHILE @i <= @max
            BEGIN
                -- PASO 4: Por revision, en su propia transaccion: bloquear la revision
                SELECT @idRevision = idRevision FROM #culmc_pend WHERE n = @i;
                SET @i += 1;
                BEGIN TRY
                    IF @transaccionExterna = 0
                    BEGIN
                        BEGIN TRANSACTION;
                    END
                    SET @idEg = NULL;
                    SELECT @idEg = r.estudianteGrupo, @usuarioProponente = r.usuarioDecisionDocente, @huellaPrev = r.huellaResolutoresActual,
                           @perfilPrev = r.codigoPerfilResolutorActual, @idEstado = r.estado
                    FROM dbo.RevisionCancelacion r WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.uv_estado_revision_cancelacion es ON es.id = r.estado AND es.requiereAccionResolutor = 1
                    WHERE r.id = @idRevision;

                    IF @idEg IS NOT NULL
                    BEGIN
                        IF OBJECT_ID(N'tempdb..#culmc_res') IS NOT NULL
                        BEGIN
                            DROP TABLE #culmc_res;
                        END
                        -- PASO 5: Resolutores vigentes y su huella
                        SELECT f.idUsuario, f.codigoPerfil, f.idPrograma, f.esEscalamiento INTO #culmc_res
                        FROM dbo.ufn_revision_cancelacion_resolutores(@idEg, @usuarioProponente) f;
                        SELECT @huellaNueva = NULL, @perfilNuevo = NULL;
                        IF EXISTS (SELECT 1 FROM #culmc_res)
                        BEGIN
                            SET @perfilNuevo = N'COORDINADOR';
                            SELECT @huellaNueva = HASHBYTES('SHA2_256', STRING_AGG(CONVERT(VARCHAR(36), x.idUsuario), ',') WITHIN GROUP (ORDER BY CONVERT(VARCHAR(36), x.idUsuario)))
                            FROM (SELECT DISTINCT idUsuario FROM #culmc_res) x;
                        END

                        -- PASO 6: Si cambiaron, reasignar: actualizar, historial, auditoria y novedad
                        IF NOT (IIF(@huellaNueva IS NULL, '', CONVERT(VARCHAR(80), @huellaNueva, 2)) = IIF(@huellaPrev IS NULL, '', CONVERT(VARCHAR(80), @huellaPrev, 2))
                                AND IIF(@perfilNuevo IS NULL, N'', @perfilNuevo) = IIF(@perfilPrev IS NULL, N'', @perfilPrev))
                        BEGIN
                            SET @ahora = CAST(SYSUTCDATETIME() AS DATETIME2(3));
                            SELECT @porcentaje = rs.porcentajeInasistencia FROM dbo.uv_resumen_asistencia_estudiante_grupo rs WHERE rs.idEstudianteGrupo = @idEg;
                            SET @porcentaje = IIF(@porcentaje IS NULL, 0, @porcentaje);
                            SET @evento = N'REASIGNAR';
                            UPDATE dbo.RevisionCancelacion
                            SET codigoPerfilResolutorActual = @perfilNuevo, huellaResolutoresActual = @huellaNueva,
                                fechaActualizacionUtc = @ahora
                            WHERE id = @idRevision;
                            INSERT INTO dbo.RevisionCancelacionHistorial (id, revision, estadoAnterior, estadoNuevo, codigoEvento, motivo, usuarioActor, codigoPerfilActor,
                                codigoPerfilResolutor, porcentajeInasistencia, fechaUtc, idCorrelacion)
                            VALUES (NEWID(), @idRevision, @idEstado, @idEstado, @evento, NULL, NULL, NULL, @perfilNuevo, @porcentaje, @ahora, @idCorrelacionDefecto);

                            IF @perfilNuevo IS NULL
                            BEGIN
                                INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId, httpMethod, path, httpStatus, metadata)
                                VALUES (NEWID(), SYSDATETIMEOFFSET(), N'SISTEMA', 'SYSTEM', 'REVISION_CANCELACION_SIN_RESOLUTOR', 'RevisionCancelacion', CONVERT(NVARCHAR(36), @idRevision),
                                        'SUCCESS', @idCorrelacionDefecto, 'JOB', N'/jobs/alertas-inasistencia', 200,
                                        (SELECT perfilAnterior = @perfilPrev, causa = N'SIN_COORDINADOR_ACTIVO' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
                            END
                            ELSE
                            BEGIN
                                INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId, httpMethod, path, httpStatus, metadata)
                                VALUES (NEWID(), SYSDATETIMEOFFSET(), N'SISTEMA', 'SYSTEM', 'REASIGNAR_REVISION_CANCELACION',
                                        'RevisionCancelacion', CONVERT(NVARCHAR(36), @idRevision), 'SUCCESS', @idCorrelacionDefecto, 'JOB', N'/jobs/alertas-inasistencia', 200,
                                        (SELECT perfilAnterior = @perfilPrev, perfilNuevo = @perfilNuevo, causa = N'RESOLUTORES_CAMBIARON' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
                            END

                            IF @perfilNuevo IS NULL
                            BEGIN
                                SET @sinResolutor += 1;
                            END
                            ELSE
                            BEGIN
                                SET @reasignadas += 1;
                            END

                            INSERT INTO #culmc_nov (json)
                            SELECT (SELECT idRevision = rv.id, idGrupo = rv.idGrupo, codigoGrupo = rv.codigoGrupo, nombreGrupo = rv.nombreGrupo, nombreAsignatura = rv.nombreAsignatura,
                                           idEstudianteGrupo = rv.idEstudianteGrupo, perfilResolutor = @perfilNuevo, evento = @evento, porcentajeInasistencia = @porcentaje,
                                           umbral = rs.umbralPerdida, motivo = rv.motivoDocente, nombreCompletoEstudiante = rv.nombreCompletoEstudiante,
                                           nombreCompletoDocente = rv.nombreCompletoDocente, idUsuarioDocente = rv.idUsuarioDocenteTitular, idUsuarioEstudiante = rv.idUsuarioEstudiante,
                                           resolutores = JSON_QUERY((SELECT idUsuario = u.id, codigoPerfil = x.codigoPerfil, esEscalamiento = x.esEscalamiento, correo = u.correo,
                                                                            nombreCompleto = CONCAT(LTRIM(RTRIM(CONCAT(u.primerNombre, N' ', u.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(u.primerApellido, N' ', u.segundoApellido))))
                                                                     FROM (SELECT DISTINCT idUsuario, codigoPerfil, esEscalamiento FROM #culmc_res) x
                                                                     INNER JOIN dbo.uv_usuario u ON u.id = x.idUsuario FOR JSON PATH))
                                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
                            FROM dbo.uv_revision_cancelacion rv
                            LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo rs ON rs.idEstudianteGrupo = rv.idEstudianteGrupo
                            WHERE rv.id = @idRevision;
                        END
                    END
                    IF @transaccionExterna = 0 AND XACT_STATE() = 1
                    BEGIN
                        COMMIT TRANSACTION;
                    END
                END TRY
                BEGIN CATCH
                    IF @transaccionExterna = 0 AND XACT_STATE() <> 0
                    BEGIN
                        ROLLBACK TRANSACTION;
                    END
                    ELSE IF @transaccionExterna = 1 AND XACT_STATE() = -1
                    BEGIN
                        THROW;
                    END
                END CATCH
            END

            -- PASO 7: Novedades y resumen (ALR_007)
            -- CONCAT nunca devuelve NULL (el ISNULL previo no tenia efecto); el caso sin novedades lo cubre el IF siguiente
            SELECT @novedadesJSON = CONCAT(N'[', (SELECT STRING_AGG(json, N',') FROM #culmc_nov), N']');
            IF @novedadesJSON IS NULL OR @novedadesJSON = N'[]' OR @novedadesJSON = N'[NULL]'
            BEGIN
                SET @novedadesJSON = N'[]';
            END

            SELECT @p1 = CONVERT(NVARCHAR(20), @reasignadas), @p2 = CONVERT(NVARCHAR(20), @escaladas), @p3 = CONVERT(NVARCHAR(20), @sinResolutor);
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ALR_007', @p_param1 = @p1, @p_param2 = @p2, @p_param3 = @p3,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        -- PASO 8: Error: relanzar si la transaccion externa quedo condenada; si no, SYS_001
        IF XACT_STATE() = -1 AND @transaccionExterna = 1
        BEGIN
            THROW;
        END
        IF XACT_STATE() <> 0 AND @transaccionExterna = 0
        BEGIN
            ROLLBACK TRANSACTION;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SELECT @reasignadas = 0, @escaladas = 0, @sinResolutor = 0, @novedadesJSON = N'[]';
    END CATCH

    -- PASO 9: Resultado
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
