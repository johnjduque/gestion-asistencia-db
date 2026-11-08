USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_evaluar_alertas_inasistencia_grupo (CULM-001 C.1, HU026C; CONTRACT §2.5.1, DEC-039/041, SUPUESTO-C-03..C-05)
--
-- Motor de alertas de inasistencia. Comando de SISTEMA (sin usuario; lo invocan solo el backend y el job). Clasificacion:
-- NON_GOLDEN_PATH_EXTENSION, tupla canonica + alertasCreadas, alertasSuperadas, alertasReactivadas, revisionesCreadas,
-- novedadesJSON (una novedad por alerta creada; esPrincipal en la de mayor nivel creada para la matricula en esta evaluacion).
-- Lee el porcentaje por horas de uv_resumen_asistencia_estudiante_grupo (EX no cuenta) de las matriculas activas del grupo;
-- crea la alerta del tipo cuyo umbral se alcanza (una por matricula y tipo), marca SUPERADA/reactiva y, al cruzar la alerta
-- que crea revision (perdida), crea una sola revision por matricula. Serializa por grupo con EvaluacionAlertaGrupo (marca de
-- agua capturada al INICIO, O-8). Ningun SP invoca este motor (N-1).
-- Codigos: GEN_002, ALR_001 (deshabilitado, sin escrituras), ALR_002 (umbral invalido), ALR_003 (exito), ALR_006.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_evaluar_alertas_inasistencia_grupo]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idEstudianteGrupo UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita       NVARCHAR(10)     = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @habilitada           NVARCHAR(20)     = LOWER(TRIM(CAST(dbo.ufn_obtener_parametro('ALERTA_INASISTENCIA', 'HABILITADA') AS NVARCHAR(20))));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeDescartado       NVARCHAR(4000);
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @corte                  DATETIME2(3);
    DECLARE @alertasCreadas         INT = 0;
    DECLARE @alertasSuperadas       INT = 0;
    DECLARE @alertasReactivadas     INT = 0;
    DECLARE @revisionesCreadas      INT = 0;
    DECLARE @novedadesJSON          NVARCHAR(MAX) = N'[]';
    DECLARE @idEstadoVigente        UNIQUEIDENTIFIER;
    DECLARE @idEstadoSuperada       UNIQUEIDENTIFIER;
    DECLARE @idEstadoRevisionInicial UNIQUEIDENTIFIER;
    DECLARE @codigoTipoInvalido     NVARCHAR(20);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500), @p3 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idGrupo IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idGrupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- Solo existencia (no usp_validar_grupo_exista_por_id_interno: exige la ventana de matricula y el cierre evalua periodos terminados)
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.Grupo g WHERE g.id = @idGrupoDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VAL_001', @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND @idEstudianteGrupo IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg WHERE eg.id = @idEstudianteGrupo AND eg.grupo = @idGrupoDefecto)
        BEGIN
            SELECT @p1 = CONVERT(NVARCHAR(36), @idEstudianteGrupo), @p2 = CONVERT(NVARCHAR(36), @idGrupoDefecto);
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ALR_006', @p_param1 = @p1, @p_param2 = @p2,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- ALR_001: interruptor apagado -> exito sin escrituras
        IF @estadoResultado = 1 AND ISNULL(@habilitada, N'') <> N'true'
        BEGIN
            SET @p1 = CONVERT(NVARCHAR(36), @idGrupoDefecto);
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ALR_001', @p_param1 = @p1,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 1;
            SELECT idCorrelacion = @idCorrelacionDefecto, mensajeUsuarioResultado = @mensajeUsuarioResultado, mensajeTecnicoResultado = @mensajeTecnicoResultado,
                   estadoResultado = @estadoResultado, alertasCreadas = 0, alertasSuperadas = 0, alertasReactivadas = 0, revisionesCreadas = 0, novedadesJSON = N'[]';
            RETURN;
        END

        -- ALR_002: algun umbral ausente o no numerico
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @codigoTipoInvalido = t.codigo
            FROM dbo.TipoAlertaInasistencia t
            WHERE dbo.ufn_umbral_alerta_inasistencia(t.id) IS NULL
            ORDER BY t.nivel;
            IF @codigoTipoInvalido IS NOT NULL
            BEGIN
                SELECT @p1 = CONCAT(t.grupoParametroUmbral, '/', t.claveParametroUmbral), @p2 = t.codigo FROM dbo.TipoAlertaInasistencia t WHERE t.codigo = @codigoTipoInvalido;
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ALR_002', @p_param1 = @p1, @p_param2 = @p2,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            -- O-8: instante de corte capturado al INICIO de la evaluacion
            SET @corte = CAST(SYSUTCDATETIME() AS DATETIME2(3));
            SELECT @idEstadoVigente = id FROM dbo.EstadoAlertaInasistencia WHERE estaVigente = 1;
            SELECT @idEstadoSuperada = id FROM dbo.EstadoAlertaInasistencia WHERE estaVigente = 0;
            SELECT @idEstadoRevisionInicial = id FROM dbo.EstadoRevisionCancelacion WHERE esInicial = 1;
            IF @idEstadoVigente IS NULL OR @idEstadoSuperada IS NULL OR @idEstadoRevisionInicial IS NULL
                THROW 52701, 'CULM001_C_CATALOGO_INCONSISTENTE: faltan estados de alerta o de revision.', 1;

            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_evaluar_alertas_grupo;
                SET @savepointCreado = 1;
            END

            -- Cerrojo por grupo: serializa las evaluaciones del mismo grupo
            MERGE dbo.EvaluacionAlertaGrupo WITH (UPDLOCK, HOLDLOCK) AS t
            USING (SELECT g = @idGrupoDefecto) s ON t.grupo = s.g
            WHEN NOT MATCHED THEN INSERT (grupo, fechaCorteUtc, idCorrelacionUltima, totalEvaluaciones) VALUES (s.g, @corte, @idCorrelacionDefecto, 0);
            SELECT @corte = @corte FROM dbo.EvaluacionAlertaGrupo WITH (UPDLOCK, HOLDLOCK) WHERE grupo = @idGrupoDefecto;

            CREATE TABLE #culmc_cand (idEstudianteGrupo UNIQUEIDENTIFIER NOT NULL PRIMARY KEY, porcentaje DECIMAL(5,2) NOT NULL, horasFalta DECIMAL(12,6) NOT NULL, horasDictadas DECIMAL(12,6) NOT NULL);
            INSERT INTO #culmc_cand (idEstudianteGrupo, porcentaje, horasFalta, horasDictadas)
            SELECT r.idEstudianteGrupo, r.porcentajeInasistencia, r.horasFalta, r.horasDictadas
            FROM dbo.uv_resumen_asistencia_estudiante_grupo r
            WHERE r.idGrupo = @idGrupoDefecto AND r.codigoEstadoEstudiante = @codigoInscrita
              AND (@idEstudianteGrupo IS NULL OR r.idEstudianteGrupo = @idEstudianteGrupo);

            -- Evaluacion por (matricula, tipo): accion NUEVA | SUPERAR | REACTIVAR | NINGUNA
            CREATE TABLE #culmc_eval (idEstudianteGrupo UNIQUEIDENTIFIER NOT NULL, idTipo UNIQUEIDENTIFIER NOT NULL, nivel TINYINT NOT NULL, creaRevision BIT NOT NULL,
                umbral DECIMAL(5,2) NOT NULL, porcentaje DECIMAL(5,2) NOT NULL, horasFalta DECIMAL(12,6) NOT NULL, horasDictadas DECIMAL(12,6) NOT NULL,
                idAlertaExistente UNIQUEIDENTIFIER NULL, accion VARCHAR(10) NOT NULL, idAlertaNueva UNIQUEIDENTIFIER NULL, PRIMARY KEY (idEstudianteGrupo, idTipo));
            INSERT INTO #culmc_eval (idEstudianteGrupo, idTipo, nivel, creaRevision, umbral, porcentaje, horasFalta, horasDictadas, idAlertaExistente, accion, idAlertaNueva)
            SELECT c.idEstudianteGrupo, t.id, t.nivel, t.creaRevisionCancelacion, u.umbral, c.porcentaje, c.horasFalta, c.horasDictadas, a.id,
                   CASE WHEN a.id IS NULL AND c.porcentaje >= u.umbral THEN 'NUEVA'
                        WHEN a.id IS NOT NULL AND ea.estaVigente = 1 AND c.porcentaje < u.umbral THEN 'SUPERAR'
                        WHEN a.id IS NOT NULL AND ea.estaVigente = 0 AND c.porcentaje >= u.umbral THEN 'REACTIVAR'
                        ELSE 'NINGUNA' END,
                   NULL
            FROM #culmc_cand c
            CROSS JOIN dbo.TipoAlertaInasistencia t
            CROSS APPLY (SELECT umbral = dbo.ufn_umbral_alerta_inasistencia(t.id)) u
            LEFT JOIN dbo.AlertaInasistencia a WITH (UPDLOCK, HOLDLOCK) ON a.estudianteGrupo = c.idEstudianteGrupo AND a.tipo = t.id
            LEFT JOIN dbo.EstadoAlertaInasistencia ea ON ea.id = a.estado;
            UPDATE #culmc_eval SET idAlertaNueva = NEWID() WHERE accion = 'NUEVA';

            INSERT INTO dbo.AlertaInasistencia (id, estudianteGrupo, tipo, estado, porcentajeCruce, umbralCruce, horasFaltaCruce, horasDictadasCruce, fechaCruceUtc,
                idCorrelacionCruce, porcentajeUltimaEvaluacion, fechaUltimaEvaluacionUtc, fechaLecturaUtc)
            SELECT e.idAlertaNueva, e.idEstudianteGrupo, e.idTipo, @idEstadoVigente, e.porcentaje, e.umbral, e.horasFalta, e.horasDictadas, @corte,
                   @idCorrelacionDefecto, e.porcentaje, @corte, NULL
            FROM #culmc_eval e
            WHERE e.accion = 'NUEVA'
              AND NOT EXISTS (SELECT 1 FROM dbo.AlertaInasistencia x WHERE x.estudianteGrupo = e.idEstudianteGrupo AND x.tipo = e.idTipo);
            SET @alertasCreadas = @@ROWCOUNT;

            UPDATE a SET porcentajeUltimaEvaluacion = e.porcentaje, fechaUltimaEvaluacionUtc = @corte,
                         estado = CASE e.accion WHEN 'SUPERAR' THEN @idEstadoSuperada WHEN 'REACTIVAR' THEN @idEstadoVigente ELSE a.estado END
            FROM dbo.AlertaInasistencia a
            INNER JOIN #culmc_eval e ON e.idAlertaExistente = a.id;
            SELECT @alertasSuperadas = COUNT(1) FROM #culmc_eval WHERE accion = 'SUPERAR';
            SELECT @alertasReactivadas = COUNT(1) FROM #culmc_eval WHERE accion = 'REACTIVAR';

            -- Una sola revision por matricula al cruzar la alerta que la crea
            CREATE TABLE #culmc_rev (idRevision UNIQUEIDENTIFIER NOT NULL, idEstudianteGrupo UNIQUEIDENTIFIER NOT NULL, idAlerta UNIQUEIDENTIFIER NOT NULL, porcentaje DECIMAL(5,2) NOT NULL);
            INSERT INTO #culmc_rev (idRevision, idEstudianteGrupo, idAlerta, porcentaje)
            SELECT NEWID(), e.idEstudianteGrupo, e.idAlertaNueva, e.porcentaje
            FROM #culmc_eval e
            WHERE e.accion = 'NUEVA' AND e.creaRevision = 1 AND e.idAlertaNueva IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM dbo.RevisionCancelacion r WITH (UPDLOCK, HOLDLOCK) WHERE r.estudianteGrupo = e.idEstudianteGrupo);
            INSERT INTO dbo.RevisionCancelacion (id, estudianteGrupo, estado, alertaOrigen, porcentajeCreacion, horasFaltaCreacion, horasDictadasCreacion, fechaCreacionUtc,
                idCorrelacionCreacion, fechaActualizacionUtc)
            SELECT v.idRevision, v.idEstudianteGrupo, @idEstadoRevisionInicial, v.idAlerta, v.porcentaje, e.horasFalta, e.horasDictadas, @corte, @idCorrelacionDefecto, @corte
            FROM #culmc_rev v INNER JOIN #culmc_eval e ON e.idEstudianteGrupo = v.idEstudianteGrupo AND e.idAlertaNueva = v.idAlerta;
            SET @revisionesCreadas = @@ROWCOUNT;
            INSERT INTO dbo.RevisionCancelacionHistorial (id, revision, estadoAnterior, estadoNuevo, codigoEvento, motivo, usuarioActor, codigoPerfilActor, codigoPerfilResolutor,
                porcentajeInasistencia, fechaUtc, idCorrelacion)
            SELECT NEWID(), v.idRevision, NULL, @idEstadoRevisionInicial, N'CREAR', NULL, NULL, NULL, NULL, v.porcentaje, @corte, @idCorrelacionDefecto
            FROM #culmc_rev v;

            -- Auditoria (SYSTEM)
            INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId, httpMethod, path, httpStatus, metadata)
            SELECT NEWID(), SYSDATETIMEOFFSET(), N'SISTEMA', 'SYSTEM', 'ALERTA_INASISTENCIA_REGISTRADA', 'AlertaInasistencia', CONVERT(NVARCHAR(36), e.idAlertaNueva), 'SUCCESS',
                   @idCorrelacionDefecto, 'JOB', N'/jobs/alertas-inasistencia', 200,
                   (SELECT idEstudianteGrupo = e.idEstudianteGrupo, tipo = t.codigo, porcentajeInasistencia = e.porcentaje, umbral = e.umbral FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
            FROM #culmc_eval e INNER JOIN dbo.TipoAlertaInasistencia t ON t.id = e.idTipo
            WHERE e.accion = 'NUEVA';
            INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId, httpMethod, path, httpStatus, metadata)
            SELECT NEWID(), SYSDATETIMEOFFSET(), N'SISTEMA', 'SYSTEM', 'ALERTA_INASISTENCIA_ACTUALIZADA', 'AlertaInasistencia', CONVERT(NVARCHAR(36), e.idAlertaExistente), 'SUCCESS',
                   @idCorrelacionDefecto, 'JOB', N'/jobs/alertas-inasistencia', 200,
                   (SELECT idEstudianteGrupo = e.idEstudianteGrupo, tipo = t.codigo, estadoNuevo = IIF(e.accion = 'SUPERAR', N'SUPERADA', N'VIGENTE'), porcentajeInasistencia = e.porcentaje, umbral = e.umbral FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
            FROM #culmc_eval e INNER JOIN dbo.TipoAlertaInasistencia t ON t.id = e.idTipo
            WHERE e.accion IN ('SUPERAR', 'REACTIVAR');
            INSERT INTO dbo.AuditoriaEvento (id, occurredAt, actorId, actorType, action, resourceType, resourceId, result, correlationId, httpMethod, path, httpStatus, metadata)
            SELECT NEWID(), SYSDATETIMEOFFSET(), N'SISTEMA', 'SYSTEM', 'REVISION_CANCELACION_CREADA', 'RevisionCancelacion', CONVERT(NVARCHAR(36), v.idRevision), 'SUCCESS',
                   @idCorrelacionDefecto, 'JOB', N'/jobs/alertas-inasistencia', 200,
                   (SELECT idEstudianteGrupo = v.idEstudianteGrupo, porcentajeInasistencia = v.porcentaje FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
            FROM #culmc_rev v;

            -- Novedades (una por alerta creada); principal = la de mayor nivel creada para la matricula
            SELECT @novedadesJSON = ISNULL((
                SELECT  idAlerta = e.idAlertaNueva, codigoTipo = t.codigo, nivel = t.nivel,
                        esPrincipal = CAST(IIF(e.nivel = MAX(e.nivel) OVER (PARTITION BY e.idEstudianteGrupo), 1, 0) AS BIT),
                        porcentajeInasistencia = e.porcentaje, umbral = e.umbral,
                        umbralPerdida = (SELECT TOP 1 dbo.ufn_umbral_alerta_inasistencia(tp.id) FROM dbo.TipoAlertaInasistencia tp WHERE tp.creaRevisionCancelacion = 1),
                        horasFalta = e.horasFalta, horasDictadas = e.horasDictadas,
                        idEstudianteGrupo = e.idEstudianteGrupo, idGrupo = g.id, codigoGrupo = g.codigo, nombreGrupo = g.nombre, nombreAsignatura = asig.nombre,
                        tipoPlantillaEstudiante = t.tipoPlantillaEstudiante,
                        [estudiante.idEstudiante] = est.id, [estudiante.idUsuario] = ue.id,
                        [estudiante.nombreCompleto] = CONCAT(LTRIM(RTRIM(CONCAT(ue.primerNombre, N' ', ue.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(ue.primerApellido, N' ', ue.segundoApellido)))),
                        [estudiante.correo] = ue.correo,
                        [docente.idDocente] = d.id, [docente.idUsuario] = ud.id,
                        [docente.nombreCompleto] = CONCAT(LTRIM(RTRIM(CONCAT(ud.primerNombre, N' ', ud.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(ud.primerApellido, N' ', ud.segundoApellido)))),
                        [docente.correo] = ud.correo,
                        idRevisionCreada = v.idRevision
                FROM #culmc_eval e
                INNER JOIN dbo.TipoAlertaInasistencia t ON t.id = e.idTipo
                INNER JOIN dbo.EstudianteGrupo eg ON eg.id = e.idEstudianteGrupo
                INNER JOIN dbo.Estudiante est ON est.id = eg.estudiante
                INNER JOIN dbo.Usuario ue ON ue.id = est.usuario
                INNER JOIN dbo.Grupo g ON g.id = eg.grupo
                INNER JOIN dbo.Asignatura asig ON asig.id = g.asignatura
                INNER JOIN dbo.Docente d ON d.id = g.docente
                INNER JOIN dbo.Usuario ud ON ud.id = d.usuario
                LEFT JOIN #culmc_rev v ON v.idEstudianteGrupo = e.idEstudianteGrupo AND v.idAlerta = e.idAlertaNueva
                WHERE e.accion = 'NUEVA'
                ORDER BY e.idEstudianteGrupo, t.nivel
                FOR JSON PATH), N'[]');

            UPDATE dbo.EvaluacionAlertaGrupo
            SET fechaCorteUtc = @corte, idCorrelacionUltima = @idCorrelacionDefecto, totalEvaluaciones = totalEvaluaciones + 1
            WHERE grupo = @idGrupoDefecto;

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END

            SELECT @p1 = CONVERT(NVARCHAR(36), @idGrupoDefecto), @p2 = CONVERT(NVARCHAR(20), @alertasCreadas), @p3 = CONVERT(NVARCHAR(20), @alertasSuperadas + @alertasReactivadas);
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ALR_003', @p_param1 = @p1, @p_param2 = @p2, @p_param3 = @p3,
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
            ROLLBACK TRANSACTION sp_evaluar_alertas_grupo;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SELECT @alertasCreadas = 0, @alertasSuperadas = 0, @alertasReactivadas = 0, @revisionesCreadas = 0, @novedadesJSON = N'[]';
    END CATCH

    -- Si el error ocurre tras escribir, el rollback anterior ya revirtio los contadores
    IF @estadoResultado = 0
        SELECT @alertasCreadas = 0, @alertasSuperadas = 0, @alertasReactivadas = 0, @revisionesCreadas = 0, @novedadesJSON = N'[]';

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        alertasCreadas          = @alertasCreadas,
        alertasSuperadas        = @alertasSuperadas,
        alertasReactivadas      = @alertasReactivadas,
        revisionesCreadas       = @revisionesCreadas,
        novedadesJSON           = @novedadesJSON;
END;
GO
