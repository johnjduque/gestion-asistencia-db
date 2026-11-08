USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_ejecutar_cierre_masivo_periodo (HU174; CULM-001 C.1, CONTRACT §2.6, SUPUESTO-C-10, DEC-041 C-10, DEC-043, N-1, N-4)
--
-- Cierre masivo del periodo. Ya NO escribe CI por conteo de faltas: CI solo nace de una revision de cancelacion aprobada.
--   Motor activo (ALERTA_INASISTENCIA/HABILITADA = true y los dos umbrales validos): el SP NO ejecuta el motor (lo hace antes el
--   caso de uso del backend, N-1) y, dentro de su transaccion y con bloqueos, se bloquea con RCN_012 si hay revisiones que esperan
--   al docente o al resolutor, o perdidas por horas sin revision, de matriculas activas del periodo; sin crear revisiones.
--   Si no (o con el motor apagado / umbrales invalidos, que no bloquean y quedan auditados): matriculas A -> F (parametro
--   MATRICULA/ESTADO_FINALIZADA), contadores de Grupo (cantidadEstudiantesCancelaronAutomaticamente = matriculas en CI al cierre,
--   SUPUESTO-C-20) y AuditoriaEvento CIERRE_MASIVO_PERIODO con motorHabilitado, umbralesValidos, perdidasSinRevision y
--   revisionesPendientes. Devuelve SIEMPRE una sola fila (tupla canonica), tambien con INSERT ... EXEC.
-- Bloqueos (orden de §2.0): RevisionCancelacion -> EstudianteGrupo (UPDLOCK, HOLDLOCK) -> lectura de uv_resumen_* sin pistas ->
-- Grupo. Transaccion propia o savepoint si hay una externa.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_ejecutar_cierre_masivo_periodo]
(
    @codigoPeriodo          NVARCHAR(50),
    @idActor                NVARCHAR(100),
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoPeriodoDefecto     NVARCHAR(50)     = TRIM(@codigoPeriodo);
    DECLARE @idActorDefecto           NVARCHAR(100)    = TRIM(@idActor);

    DECLARE @idPeriodoTarget               UNIQUEIDENTIFIER;
    DECLARE @idEstadoActivo                UNIQUEIDENTIFIER;
    DECLARE @idEstadoFinalizado            UNIQUEIDENTIFIER;
    DECLARE @idEstadoCanceladoInasistencia UNIQUEIDENTIFIER;
    DECLARE @codigoActiva                  NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @codigoFinalizada              NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_FINALIZADA') AS NVARCHAR(10));
    DECLARE @codigoCancelada               NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_CANCELADA_INASISTENCIA') AS NVARCHAR(10));
    DECLARE @motorHabilitado               BIT = IIF(LOWER(TRIM(CAST(dbo.ufn_obtener_parametro('ALERTA_INASISTENCIA', 'HABILITADA') AS NVARCHAR(20)))) = N'true', 1, 0);
    DECLARE @umbralesValidos               BIT = 1;
    DECLARE @umbralPerdida                 DECIMAL(5,2);
    DECLARE @motorActivo                   BIT = 0;
    DECLARE @totalEstudiantes              INT = 0;
    DECLARE @totalFinalizados              INT = 0;
    DECLARE @totalCancelados               INT = 0;
    DECLARE @revisionesPendientes          INT = 0;
    DECLARE @perdidasSinRevision           INT = 0;
    DECLARE @transaccionPropia             BIT = 0;
    DECLARE @savepointCreado               BIT = 0;
    DECLARE @estadoTransaccionCatch        INT;
    DECLARE @bloqueado                     BIT = 0;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500), @p3 NVARCHAR(500);
    DECLARE @mensajeDescartado NVARCHAR(4000);

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    -- REC3 (auditoria BD 2026-10-28): cualquier error o cancelacion del cliente revierte la transaccion completa.
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Buscar período académico objetivo consultando uv_periodo_academico
        IF @estadoResultado = 1
        BEGIN
            IF @codigoPeriodoDefecto IS NOT NULL AND @codigoPeriodoDefecto <> ''
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM [dbo].[uv_periodo_academico]
                WHERE nombre = @codigoPeriodoDefecto
                   OR CAST(codigo AS NVARCHAR(50)) = @codigoPeriodoDefecto
                ORDER BY anio DESC;
            END

            IF @idPeriodoTarget IS NULL
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM [dbo].[uv_periodo_academico]
                ORDER BY anio DESC, codigo DESC;
            END

            IF @idPeriodoTarget IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'PeriodoAcademico',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Ejecución transaccional de Cierre Masivo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoActivo = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = @codigoActiva ORDER BY id ASC;
            SELECT TOP 1 @idEstadoFinalizado = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = @codigoFinalizada ORDER BY id ASC;
            SELECT TOP 1 @idEstadoCanceladoInasistencia = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = @codigoCancelada ORDER BY id ASC;

            -- Umbrales: el motor solo bloquea con los dos validos (O-3)
            IF EXISTS (SELECT 1 FROM dbo.TipoAlertaInasistencia t WHERE dbo.ufn_umbral_alerta_inasistencia(t.id) IS NULL)
                SET @umbralesValidos = 0;
            SELECT TOP 1 @umbralPerdida = dbo.ufn_umbral_alerta_inasistencia(t.id) FROM dbo.TipoAlertaInasistencia t WHERE t.creaRevisionCancelacion = 1;
            SET @motorActivo = IIF(@motorHabilitado = 1 AND @umbralesValidos = 1 AND @umbralPerdida IS NOT NULL, 1, 0);

            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cierre_masivo;
                SET @savepointCreado = 1;
            END

            -- (1) RevisionCancelacion y (2) EstudianteGrupo del periodo, en el orden de bloqueos de §2.0 (N-4)
            SELECT @revisionesPendientes = COUNT(1)
            FROM dbo.RevisionCancelacion r WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.EstudianteGrupo eg ON eg.id = r.estudianteGrupo
            INNER JOIN dbo.Grupo g ON g.id = eg.grupo AND g.periodoAcademico = @idPeriodoTarget
            INNER JOIN dbo.EstadoRevisionCancelacion es ON es.id = r.estado AND (es.requiereAccionDocente = 1 OR es.requiereAccionResolutor = 1)
            WHERE eg.estado = @idEstadoActivo;

            SELECT @totalEstudiantes = COUNT(eg.id)
            FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            WHERE g.periodoAcademico = @idPeriodoTarget;

            -- (3) Perdidas por horas sin revision (lectura sin pistas: bloqueos compartidos que no se retienen)
            IF @umbralPerdida IS NOT NULL
                SELECT @perdidasSinRevision = COUNT(1)
                FROM dbo.uv_resumen_asistencia_estudiante_grupo rs
                WHERE rs.idPeriodoAcademico = @idPeriodoTarget AND rs.codigoEstadoEstudiante = @codigoActiva
                  AND rs.porcentajeInasistencia >= @umbralPerdida
                  AND NOT EXISTS (SELECT 1 FROM dbo.RevisionCancelacion r WHERE r.estudianteGrupo = rs.idEstudianteGrupo);

            IF @motorActivo = 1 AND (@revisionesPendientes + @perdidasSinRevision) > 0
            BEGIN
                SET @bloqueado = 1;
                SELECT @p1 = CONVERT(NVARCHAR(20), @revisionesPendientes + @perdidasSinRevision);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCN_012', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeDescartado OUTPUT;
                SELECT @p1 = CONVERT(NVARCHAR(50), @idPeriodoTarget), @p2 = CONVERT(NVARCHAR(20), @revisionesPendientes), @p3 = CONVERT(NVARCHAR(20), @perdidasSinRevision);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCN_012', @p_param1 = @p1, @p_param2 = @p2, @p_param3 = @p3,
                    @mensajeUsuarioResultado = @mensajeDescartado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
                -- No se escribio nada (solo bloqueos y lecturas): se libera con COMMIT y no con ROLLBACK, porque este SP debe poder
                -- ejecutarse dentro de INSERT ... EXEC (C-DB-47) y SQL Server prohibe ROLLBACK en ese contexto.
                IF @transaccionPropia = 1
                BEGIN
                    IF XACT_STATE() = 1 COMMIT TRANSACTION;
                    SET @transaccionPropia = 0;
                END
            END
            ELSE
            BEGIN
                -- (4) A -> F (incluye MANTENIDA/RECHAZADA y, con el motor apagado, cualquier perdida)
                UPDATE eg
                SET eg.estado = @idEstadoFinalizado
                FROM dbo.EstudianteGrupo eg
                INNER JOIN dbo.Grupo g ON eg.grupo = g.id
                WHERE g.periodoAcademico = @idPeriodoTarget
                  AND eg.estado = @idEstadoActivo;
                SET @totalFinalizados = @@ROWCOUNT;

                -- Contadores de Grupo ("cancelaron automaticamente" = matriculas en CI al cierre, SUPUESTO-C-20)
                UPDATE g
                SET
                    cantidadEstudiantesFinalizaron = (
                        SELECT COUNT(1) FROM dbo.EstudianteGrupo eg
                        WHERE eg.grupo = g.id AND eg.estado = @idEstadoFinalizado
                    ),
                    cantidadEstudiantesCancelaronAutomaticamente = (
                        SELECT COUNT(1) FROM dbo.EstudianteGrupo eg
                        WHERE eg.grupo = g.id AND eg.estado = @idEstadoCanceladoInasistencia
                    )
                FROM dbo.Grupo g
                WHERE g.periodoAcademico = @idPeriodoTarget;

                SELECT @totalCancelados = COUNT(1)
                FROM dbo.EstudianteGrupo eg INNER JOIN dbo.Grupo g ON g.id = eg.grupo
                WHERE g.periodoAcademico = @idPeriodoTarget AND eg.estado = @idEstadoCanceladoInasistencia;

                -- (5) Auditoría de evento
                INSERT INTO dbo.AuditoriaEvento (
                    id, occurredAt, actorId, actorType, action,
                    resourceType, resourceId, result, correlationId,
                    httpMethod, path, httpStatus, metadata
                ) VALUES (
                    NEWID(),
                    SYSDATETIMEOFFSET(),
                    CASE WHEN @idActorDefecto IS NOT NULL AND @idActorDefecto <> '' THEN @idActorDefecto ELSE 'ADMIN_SISTEMA' END,
                    CASE WHEN @idActorDefecto IS NOT NULL AND @idActorDefecto <> '' THEN 'USER' ELSE 'SYSTEM' END,
                    'CIERRE_MASIVO_PERIODO',
                    'PeriodoAcademico',
                    CAST(@idPeriodoTarget AS NVARCHAR(50)),
                    'SUCCESS',
                    @idCorrelacionDefecto,
                    'POST',
                    '/api/v1/admin/cierre-masivo',
                    200,
                    (SELECT procesados = @totalEstudiantes, finalizados = @totalFinalizados, canceladosPorInasistencia = @totalCancelados,
                            motorHabilitado = @motorHabilitado, umbralesValidos = @umbralesValidos,
                            perdidasSinRevision = @perdidasSinRevision, revisionesPendientes = @revisionesPendientes
                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
                );

                IF @transaccionPropia = 1
                BEGIN
                    IF XACT_STATE() = 1 COMMIT TRANSACTION; ELSE IF XACT_STATE() = -1 ROLLBACK TRANSACTION;
                    SET @transaccionPropia = 0;
                END

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'CierreMasivoPeriodo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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
            ROLLBACK TRANSACTION sp_cierre_masivo;

        -- Con una transaccion externa condenada (XACT_STATE = -1) solo el llamador puede revertirla
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados (una sola fila, N-1)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
