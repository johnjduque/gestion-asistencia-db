-- ============================================================================
-- CULM-001 D.2 - Migracion 21 DOWN (CONTRACT D §3.2, DEC-044 (8), patron A.1/DEC-010): retira los soportes multiples y la categoria.
-- Requiere la variable sqlcmd CONFIRMAR_COLAPSO_SOPORTES (-v CONFIRMAR_COLAPSO_SOPORTES=0|1 o :setvar antes de :r). Sin ella sqlcmd se
-- detiene antes de cambiar nada (:on error exit).
--   1. Si alguna solicitud tiene mas de un soporte ATTACHED y CONFIRMAR_COLAPSO_SOPORTES <> 1: THROW 50021 (sin cambios).
--   2. Copia (id, categoriaJustificacion) de las solicitudes con categoria a zz_archivo_SolicitudRevisionCategoria_culm001_d2
--      (sin FK ni GRANT; MERGE por id).
--   3. Con confirmacion, copia (idArchivo, idSolicitud, fechaAdjuncionUtc, idCorrelacionAdjuncion) de los soportes que se colapsan a
--      zz_archivo_SoporteColapsado_culm001_d2, deja ATTACHED el de menor fechaAdjuncionUtc (desempate por id) y pasa los demas a ORPHAN
--      con solicitud, fechaAdjuncionUtc e idCorrelacionAdjuncion en NULL (CK_ArchivoSoporte_EstadoVinculo).
--   4. Recrea UX_ArchivoSoporte_Solicitud, quita IX_ArchivoSoporte_Solicitud, la FK, el indice y la columna de categoria, y requiereSoporte.
--   5. Restaura el texto anterior (literal, D.1) de v2, R2, detalle, lista del estudiante, descarga autorizada y de las vistas;
--      DROP de v3, del interno, de la configuracion y de uv_soporte_reclamo; borra REV_021..REV_024 y los parametros de D.2 que siguen
--      en su valor por defecto.
-- El up siguiente RESTAURA las categorias y los vinculos colapsados (solo si el archivo sigue ORPHAN) y no borra las tablas zz_archivo_*.
-- Orden de rollback (CONTRACT §14.2): el down de la 20 (D.1) aborta mientras exista el interno de D.2; este down deja v2 en el texto de D.1.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @confirmar NVARCHAR(10) = N'$(CONFIRMAR_COLAPSO_SOPORTES)';
IF @confirmar <> N'1'
   AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE estado = 'ATTACHED' GROUP BY solicitudRevisionAsistencia HAVING COUNT(*) > 1)
    THROW 50021, 'CULM001_D2_DOWN: hay solicitudes con mas de un soporte; ejecute con CONFIRMAR_COLAPSO_SOPORTES = 1 para colapsar a un soporte por solicitud.', 1;
GO

-- ---------------------------------------------------------------------------------------------------------------
-- 2-3. Archivo de categorias y de soportes colapsados (patron DEC-010, sin FKs) y colapso a un soporte por solicitud
-- ---------------------------------------------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'categoriaJustificacion') IS NOT NULL
    EXEC sys.sp_executesql N'
        IF OBJECT_ID(N''dbo.zz_archivo_SolicitudRevisionCategoria_culm001_d2'', N''U'') IS NULL
            CREATE TABLE dbo.zz_archivo_SolicitudRevisionCategoria_culm001_d2 (
                id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY, categoriaJustificacion UNIQUEIDENTIFIER NOT NULL, fechaArchivoUtc DATETIME2(7) NOT NULL);
        MERGE dbo.zz_archivo_SolicitudRevisionCategoria_culm001_d2 AS t
        USING (SELECT id, categoriaJustificacion FROM dbo.SolicitudRevisionAsistencia WHERE categoriaJustificacion IS NOT NULL) AS s
        ON t.id = s.id
        WHEN MATCHED THEN UPDATE SET t.categoriaJustificacion = s.categoriaJustificacion, t.fechaArchivoUtc = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT (id, categoriaJustificacion, fechaArchivoUtc) VALUES (s.id, s.categoriaJustificacion, SYSUTCDATETIME());';
GO
IF OBJECT_ID(N'dbo.zz_archivo_SoporteColapsado_culm001_d2', N'U') IS NULL
    CREATE TABLE dbo.zz_archivo_SoporteColapsado_culm001_d2 (
        idArchivo UNIQUEIDENTIFIER NOT NULL PRIMARY KEY, idSolicitud UNIQUEIDENTIFIER NOT NULL, fechaAdjuncionUtc DATETIME2(7) NOT NULL,
        idCorrelacionAdjuncion UNIQUEIDENTIFIER NOT NULL, fechaArchivoUtc DATETIME2(7) NOT NULL);
GO
-- Soportes que sobran (todos menos el primero por solicitud): se archivan y pasan a ORPHAN. Si CONFIRMAR_COLAPSO_SOPORTES <> 1 no
-- hay ninguno (el THROW de arriba lo garantiza).
;WITH orden AS (
    SELECT a.id, a.solicitudRevisionAsistencia, a.fechaAdjuncionUtc, a.idCorrelacionAdjuncion,
           n = ROW_NUMBER() OVER (PARTITION BY a.solicitudRevisionAsistencia ORDER BY a.fechaAdjuncionUtc, a.id)
    FROM dbo.ArchivoSoporte a WHERE a.estado = 'ATTACHED'
)
MERGE dbo.zz_archivo_SoporteColapsado_culm001_d2 AS t
USING (SELECT id, solicitudRevisionAsistencia, fechaAdjuncionUtc, idCorrelacionAdjuncion FROM orden WHERE n > 1) AS s
ON t.idArchivo = s.id
WHEN MATCHED THEN UPDATE SET t.idSolicitud = s.solicitudRevisionAsistencia, t.fechaAdjuncionUtc = s.fechaAdjuncionUtc,
                             t.idCorrelacionAdjuncion = s.idCorrelacionAdjuncion, t.fechaArchivoUtc = SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT (idArchivo, idSolicitud, fechaAdjuncionUtc, idCorrelacionAdjuncion, fechaArchivoUtc)
                      VALUES (s.id, s.solicitudRevisionAsistencia, s.fechaAdjuncionUtc, s.idCorrelacionAdjuncion, SYSUTCDATETIME());
GO
;WITH orden AS (
    SELECT a.id, n = ROW_NUMBER() OVER (PARTITION BY a.solicitudRevisionAsistencia ORDER BY a.fechaAdjuncionUtc, a.id)
    FROM dbo.ArchivoSoporte a WHERE a.estado = 'ATTACHED'
)
UPDATE a SET a.estado = 'ORPHAN', a.solicitudRevisionAsistencia = NULL, a.fechaAdjuncionUtc = NULL, a.idCorrelacionAdjuncion = NULL,
             a.fechaCambioEstadoUtc = SYSUTCDATETIME()
FROM dbo.ArchivoSoporte a INNER JOIN orden o ON o.id = a.id
WHERE o.n > 1;
GO

-- ---------------------------------------------------------------------------------------------------------------
-- 4. Texto anterior a D.2 (version D.1) de los objetos modificados
-- ---------------------------------------------------------------------------------------------------------------
-- ---- schema/views/uv_solicitud_revision_asistencia.sql (texto anterior a D.2)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_solicitud_revision_asistencia]
AS
SELECT		id = sr.id,
			nombre = sr.nombre,
			idAsistencia = asi.id,
			fecha = sr.fecha,
			idEstado = est.id,
			nombreEstado = est.nombre,
			justificacionSolicitud = sr.justificacionSolicitud,
			justificacionRespuesta = sr.justificacionRespuesta

FROM		SolicitudRevisionAsistencia sr
INNER JOIN	uv_asistencia asi
ON			sr.asistencia = asi.id
INNER JOIN	uv_estado est
ON			sr.estado = est.id
GO
-- ---- schema/views/uv_categoria_justificacion.sql (texto anterior a D.2)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU005/HU016: categorias de justificacion (catalogo de solo consulta). El runtime recibe SELECT con el resto de
-- vistas uv_* (rol_asistencias_runtime.sql).
CREATE OR ALTER VIEW [dbo].[uv_categoria_justificacion]
AS
SELECT  id,
        codigo,
        nombre,
        descripcion
FROM    dbo.CategoriaJustificacion
GO
-- ---- schema/stored-procedures/usp_radicar_solicitud_revision_asistencia_v2.sql (texto anterior a D.2)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_radicar_solicitud_revision_asistencia_v2  (LB-004D, W2)
--
-- Radica la solicitud de revision y, si se indica @idArchivoSoporte, vincula el soporte
-- (DRAFT -> ATTACHED) en la MISMA transaccion. La v1 permanece intacta.
--
--   * Sin @soporteNombre/@soporteUrl: la v2 no confia en datos de soporte del cliente.
--   * Verifica que @idEstudiante pertenezca a @idUsuarioEjecutor (defensa en profundidad, H-01).
--   * El soporte es opcional: sin @idArchivoSoporte el comportamiento es el de la v1.
--   * Soporte inexistente, ajeno, ya vinculado u huerfano => ARC_001 identico, sin escritura.
--   * Reintento con la misma correlacion tras un exito => exito idempotente (sin segunda solicitud).
--   * Carrera por el mismo fileId: el UPDLOCK sobre la fila serializa; la segunda ve ATTACHED => ARC_001.
--   * CULM-001 D.1 (HU026B): el plazo de excusas se valida DESPUES de la reejecucion idempotente por correlacion y antes de
--     cualquier escritura (usp_internal_validar_plazo_justificacion: REV_020 vencido, REV_025 sin parametros). Un reintento
--     legitimo con la misma correlacion tras el vencimiento sigue devolviendo el exito original.
--   * `fecha` es la fecha LOCAL de radicacion (TIEMPO/ZONA_HORARIA_SQLSERVER), no la fecha UTC del servidor.
--
-- Resultset: MUTATION_COMMAND_RESULTSET (4 columnas canonicas).
-- Ownership transaccional: transaccion propia o SAVE TRANSACTION si el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia_v2]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @idArchivoSoporte   UNIQUEIDENTIFIER = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @justificacionDefecto     NVARCHAR(MAX)    = TRIM(@justificacion);

    DECLARE @idAsistencia         UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @nuevaSolicitudId     UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSolicitud      NVARCHAR(50);
    DECLARE @idEstadoPendiente    UNIQUEIDENTIFIER;

    DECLARE @tieneSoporte         BIT = IIF(@idArchivoSoporte IS NULL, 0, 1);
    DECLARE @propietarioSoporte   UNIQUEIDENTIFIER;
    DECLARE @estadoSoporte        VARCHAR(10);
    DECLARE @correlacionAdjuncion UNIQUEIDENTIFIER;
    DECLARE @esReintento          BIT = 0;
    DECLARE @fechaLimiteUtc       DATETIME2(7);
    DECLARE @zonaLocal            NVARCHAR(128);
    DECLARE @fechaLocalRadicacion DATE;
    DECLARE @filasActualizadas    INT;
    DECLARE @escrituraRealizada   BIT = 0;

    DECLARE @conteoTransaccionesInicial INT;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validacion de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (no nulo, no GUID vacio)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioEjecutorDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil RBAC ESTUDIANTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Existencia del estudiante
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno
                @idEstudiante = @idEstudianteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: El estudiante debe corresponder al ejecutor autenticado (H-01)
        IF @estadoResultado = 1
           AND NOT EXISTS (
                SELECT 1 FROM dbo.Estudiante e
                WHERE e.id = @idEstudianteDefecto AND e.usuario = @idUsuarioEjecutorDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARC_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Existencia de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 7: Matricula: el estudiante pertenece al grupo de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                @idEstudiante = @idEstudianteDefecto,
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 8: Transaccion propia (o savepoint si el llamador ya tiene una)
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_lb004d_radicar_v2;
                SET @savepointCreado = 1;
            END
        END

        -- PASO 9: Soporte opcional. UPDLOCK serializa radicaciones concurrentes con el mismo fileId.
        IF @estadoResultado = 1 AND @tieneSoporte = 1
        BEGIN
            SELECT @propietarioSoporte   = a.usuarioPropietario,
                   @estadoSoporte        = a.estado,
                   @correlacionAdjuncion = a.idCorrelacionAdjuncion
            FROM dbo.ArchivoSoporte a WITH (UPDLOCK, ROWLOCK)
            WHERE a.id = @idArchivoSoporte;

            IF @propietarioSoporte IS NULL OR @propietarioSoporte <> @idUsuarioEjecutorDefecto
            BEGIN
                SET @estadoResultado = 0;
            END
            ELSE IF @estadoSoporte = 'ATTACHED' AND @correlacionAdjuncion = @idCorrelacionDefecto
            BEGIN
                SET @esReintento = 1;
            END
            ELSE IF @estadoSoporte <> 'DRAFT'
            BEGIN
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ARC_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
        END

        -- PASO 9.5 (D.1): plazo de excusas. Solo cuando NO es la reejecucion idempotente de una radicacion ya exitosa.
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            EXEC dbo.usp_internal_validar_plazo_justificacion
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @fechaLimiteUtc = @fechaLimiteUtc OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 10: Creacion de la solicitud y vinculo atomico del soporte
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SET @zonaLocal = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
            SET @fechaLocalRadicacion = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @zonaLocal AS DATE);

            SELECT TOP 1 @idEstudianteGrupo = eg.id
            FROM dbo.Sesion s
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
            WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

            SELECT TOP 1 @idAsistencia = id
            FROM dbo.Asistencia
            WHERE estudianteGrupo = @idEstudianteGrupo AND sesion = @idSesionDefecto;

            SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado WHERE codigo IN ('P', 'PEND') ORDER BY id ASC;
            IF @idEstadoPendiente IS NULL
            BEGIN
                SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado ORDER BY id ASC;
            END

            SET @nombreSolicitud = CONCAT('REC-', UPPER(SUBSTRING(CAST(@nuevaSolicitudId AS VARCHAR(36)), 1, 8)));

            SET @escrituraRealizada = 1;
            IF @idAsistencia IS NULL
            BEGIN
                SET @idAsistencia = NEWID();
                INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
                VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
            END

            INSERT INTO dbo.SolicitudRevisionAsistencia (
                id, nombre, asistencia, fecha, estado,
                justificacionSolicitud, justificacionRespuesta
            )
            VALUES (
                @nuevaSolicitudId,
                @nombreSolicitud,
                @idAsistencia,
                @fechaLocalRadicacion,
                @idEstadoPendiente,
                CASE WHEN @justificacionDefecto IS NOT NULL AND @justificacionDefecto <> '' THEN @justificacionDefecto ELSE 'Solicitud de revision de asistencia radicada por estudiante.' END,
                ''
            );

            IF @tieneSoporte = 1
            BEGIN
                UPDATE dbo.ArchivoSoporte
                SET estado = 'ATTACHED',
                    solicitudRevisionAsistencia = @nuevaSolicitudId,
                    fechaAdjuncionUtc = SYSUTCDATETIME(),
                    fechaCambioEstadoUtc = SYSUTCDATETIME(),
                    idCorrelacionAdjuncion = @idCorrelacionDefecto
                WHERE id = @idArchivoSoporte
                  AND estado = 'DRAFT'
                  AND usuarioPropietario = @idUsuarioEjecutorDefecto;
                SET @filasActualizadas = @@ROWCOUNT;

                -- Postcondicion verificada por lectura (no solo @@ROWCOUNT): el soporte quedo vinculado a ESTA solicitud.
                IF @filasActualizadas <> 1
                   OR NOT EXISTS (SELECT 1 FROM dbo.ArchivoSoporte a
                                  WHERE a.id = @idArchivoSoporte AND a.estado = 'ATTACHED'
                                    AND a.solicitudRevisionAsistencia = @nuevaSolicitudId)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ARC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudRevisionAsistencia',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 11: Finalizacion respetando ownership: commit solo si el resultado es exitoso
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            -- Solo se revierte lo escrito (un rechazo previo a las escrituras no deja nada que deshacer).
            IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @escrituraRealizada = 1
                ROLLBACK TRANSACTION sp_lb004d_radicar_v2;
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_lb004d_radicar_v2;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar la excepcion original al propietario
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
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados (4 columnas canonicas)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_solicitudes_revision_docente.sql (texto anterior a D.2)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_revision_docente  (LB-004D, R2)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (filas de datos + totalRegistros), paginado en servidor.
-- Los parametros invalidos se propagan con THROW (como usp_consultar_grupos_paginado).
--
-- Alcance: SOLO solicitudes de grupos cuyo Grupo.docente pertenece a Docente.usuario = ejecutor
-- (titularidad institucional, no solo el rol). Otro docente => 0 filas. Une tablas base; no usa
-- SESSION_CONTEXT ni uv_auth_*.
--
-- Semantica temporal: fechaSolicitud es DATE de calendario (semantica v1, no es un instante).
-- fechaHoraInicioSesion es el DATETIME2(7) de dbo.Sesion TAL CUAL y procedenciaTemporalSesion indica
-- si es UTC verificable (UTC_V2/UTC_GENERADOR/UTC_OWNER) o INDETERMINADA (NULL, historica): el
-- consumidor decide segun esa procedencia (contrato UTC v2); la DB no afirma UTC cuando no lo sabe.
-- fechaRegistroSoporteUtc es un instante UTC DATETIME2(7) generado con SYSUTCDATETIME().
-- Datos personales minimos: nombre del estudiante, sin correo.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_revision_docente]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @codigoEstado       NVARCHAR(5) = NULL,
    @numeroPagina       INT         = 1,
    @tamanoPagina       INT         = 10
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginacion protegida (minimo 1, maximo 100)
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @estadoFiltro NVARCHAR(5) = NULLIF(TRIM(@codigoEstado), '');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idSolicitudRevisionAsistencia = sra.id,
        nombreSolicitud               = sra.nombre,
        fechaSolicitud                = sra.fecha,
        codigoEstado                  = est.codigo,
        nombreEstado                  = est.nombre,
        justificacionSolicitud        = CAST(sra.justificacionSolicitud AS NVARCHAR(MAX)),
        justificacionRespuesta        = CAST(sra.justificacionRespuesta AS NVARCHAR(MAX)),
        idEstudiante                  = estu.id,
        nombreEstudiante              = CAST(CONCAT_WS(N' ',
                                            NULLIF(TRIM(usu.primerNombre), N''),
                                            NULLIF(TRIM(usu.segundoNombre), N''),
                                            NULLIF(TRIM(usu.primerApellido), N''),
                                            NULLIF(TRIM(usu.segundoApellido), N'')) AS NVARCHAR(400)),
        idSesion                      = ses.id,
        numeroSesion                  = ses.numero,
        fechaHoraInicioSesion         = ses.fechaHoraInicio,
        procedenciaTemporalSesion     = ses.procedenciaTemporal,
        idGrupo                       = gru.id,
        codigoGrupo                   = gru.codigo,
        nombreGrupo                   = gru.nombre,
        idAsignatura                  = asg.id,
        codigoAsignatura              = asg.codigo,
        nombreAsignatura              = asg.nombre,
        idArchivoSoporte              = arc.id,
        nombreSoporte                 = arc.nombreOriginal,
        tipoContenidoSoporte          = arc.tipoContenido,
        tamanioSoporteBytes           = arc.tamanioBytes,
        fechaRegistroSoporteUtc       = arc.fechaRegistroUtc,
        totalRegistros                = COUNT(*) OVER()
    FROM dbo.SolicitudRevisionAsistencia sra
    INNER JOIN dbo.Estado est             ON est.id = sra.estado
    INNER JOIN dbo.Asistencia asi         ON asi.id = sra.asistencia
    INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = asi.estudianteGrupo
    INNER JOIN dbo.Estudiante estu        ON estu.id = eg.estudiante
    INNER JOIN dbo.Usuario usu            ON usu.id = estu.usuario
    INNER JOIN dbo.Sesion ses             ON ses.id = asi.sesion
    INNER JOIN dbo.Grupo gru              ON gru.id = ses.grupo
    INNER JOIN dbo.Docente doc            ON doc.id = gru.docente
    INNER JOIN dbo.Asignatura asg         ON asg.id = gru.asignatura
    LEFT  JOIN dbo.ArchivoSoporte arc     ON arc.solicitudRevisionAsistencia = sra.id
                                         AND arc.estado = 'ATTACHED'
    WHERE doc.usuario = @idUsuarioDefecto
      AND (@estadoFiltro IS NULL OR est.codigo = @estadoFiltro)
    ORDER BY sra.fecha DESC, sra.nombre ASC, sra.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_detalle_solicitud_revision_docente.sql (texto anterior a D.2)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_detalle_solicitud_revision_docente  (HU035/HU036)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (0..1 fila con el detalle y la causal de una solicitud de revision).
-- Los parametros invalidos se propagan con THROW (como usp_consultar_solicitudes_revision_docente, R2).
--
-- Alcance: SOLO solicitudes de grupos cuyo Grupo.docente pertenece a Docente.usuario = ejecutor
-- (titularidad institucional, no solo el rol). Solicitud inexistente o ajena => 0 filas (no distingue
-- ambos casos para no revelar existencia). Solo lectura: sin transaccion explicita.
--
-- Causal: DetalleAsistencia y RazonCausa se unen con LEFT JOIN (la solicitud existe aunque falte el detalle).
-- Soporte: ArchivoSoporte se une con LEFT JOIN y solo en el estado definido por el parametro
-- ARCHIVO.ESTADO_ADJUNTO (sin literales quemados).
--
-- Semantica temporal: igual que R2. fechaSolicitud es DATE de calendario; fechaHoraInicioSesion es el
-- DATETIME2(7) de dbo.Sesion TAL CUAL con procedenciaTemporalSesion (NULL = INDETERMINADA, historica);
-- fechaRegistroSoporteUtc es un instante UTC DATETIME2(7). Datos personales minimos: sin correo.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_detalle_solicitud_revision_docente]
(
    @idSolicitud        UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto   UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @estadoAdjunto        VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idSolicitud IS NULL OR @idSolicitudDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'Solicitud',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idSolicitudRevisionAsistencia = sra.id,
        nombreSolicitud               = sra.nombre,
        fechaSolicitud                = sra.fecha,
        codigoEstado                  = est.codigo,
        nombreEstado                  = est.nombre,
        justificacionSolicitud        = CAST(sra.justificacionSolicitud AS NVARCHAR(MAX)),
        justificacionRespuesta        = CAST(sra.justificacionRespuesta AS NVARCHAR(MAX)),
        idEstudiante                  = estu.id,
        nombreEstudiante              = CAST(CONCAT_WS(N' ',
                                            NULLIF(TRIM(usu.primerNombre), N''),
                                            NULLIF(TRIM(usu.segundoNombre), N''),
                                            NULLIF(TRIM(usu.primerApellido), N''),
                                            NULLIF(TRIM(usu.segundoApellido), N'')) AS NVARCHAR(400)),
        idSesion                      = ses.id,
        numeroSesion                  = ses.numero,
        fechaHoraInicioSesion         = ses.fechaHoraInicio,
        procedenciaTemporalSesion     = ses.procedenciaTemporal,
        idGrupo                       = gru.id,
        codigoGrupo                   = gru.codigo,
        nombreGrupo                   = gru.nombre,
        idAsignatura                  = asg.id,
        codigoAsignatura              = asg.codigo,
        nombreAsignatura              = asg.nombre,
        asistio                       = CAST(CASE WHEN det.codigoRazonCausaConsolidado IS NULL THEN NULL WHEN det.codigoRazonCausaConsolidado = N'AN' THEN 1 ELSE 0 END AS BIT),
        codigoRazonCausa              = rzc.codigo,
        nombreRazonCausa              = rzc.nombre,
        idArchivoSoporte              = arc.id,
        nombreSoporte                 = arc.nombreOriginal,
        tipoContenidoSoporte          = arc.tipoContenido,
        tamanioSoporteBytes           = arc.tamanioBytes,
        fechaRegistroSoporteUtc       = arc.fechaRegistroUtc
    FROM dbo.SolicitudRevisionAsistencia sra
    INNER JOIN dbo.Estado est             ON est.id = sra.estado
    INNER JOIN dbo.Asistencia asi         ON asi.id = sra.asistencia
    INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = asi.estudianteGrupo
    INNER JOIN dbo.Estudiante estu        ON estu.id = eg.estudiante
    INNER JOIN dbo.Usuario usu            ON usu.id = estu.usuario
    INNER JOIN dbo.Sesion ses             ON ses.id = asi.sesion
    INNER JOIN dbo.Grupo gru              ON gru.id = ses.grupo
    INNER JOIN dbo.Docente doc            ON doc.id = gru.docente
    INNER JOIN dbo.Asignatura asg         ON asg.id = gru.asignatura
    -- CULM-001 B.2 (CONTRACT §2.9): estado consolidado de la sesion (una fila aunque haya varias tomas)
    OUTER APPLY (SELECT h.codigoRazonCausaConsolidado FROM dbo.uv_asistencia_sesion_horas h WHERE h.idAsistencia = asi.id) det
    LEFT  JOIN dbo.RazonCausa rzc         ON rzc.codigo = det.codigoRazonCausaConsolidado
    LEFT  JOIN dbo.ArchivoSoporte arc     ON arc.solicitudRevisionAsistencia = sra.id
                                         AND arc.estado = @estadoAdjunto
    WHERE sra.id = @idSolicitudDefecto
      AND doc.usuario = @idUsuarioDefecto;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_solicitudes_revision_estudiante.sql (texto anterior a D.2)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_revision_estudiante  (HU010/HU011, consulta)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (filas de datos + totalRegistros), paginado en servidor.
-- Los parametros invalidos se propagan con THROW (como usp_consultar_grupos_paginado).
--
-- Alcance (ownership en persistencia): SOLO solicitudes cuya cadena
-- SolicitudRevisionAsistencia -> Asistencia -> EstudianteGrupo -> Estudiante tiene Estudiante.usuario = ejecutor.
-- Otro estudiante, un docente o un coordinador => 0 filas. Une tablas base; no usa SESSION_CONTEXT ni uv_auth_*.
-- Resultset con las MISMAS columnas y tipos que usp_consultar_solicitudes_revision_docente (R2, LB-004D):
-- idEstudiante/nombreEstudiante son los del propio ejecutor. El soporte vinculado se resuelve con el
-- parametro ARCHIVO.ESTADO_ADJUNTO (sin literales quemados), igual que el detalle HU035/HU036.
--
-- Semantica temporal: fechaSolicitud es DATE de calendario (semantica v1, no es un instante).
-- fechaHoraInicioSesion es el DATETIME2(7) de dbo.Sesion TAL CUAL y procedenciaTemporalSesion indica
-- si es UTC verificable (UTC_V2/UTC_GENERADOR/UTC_OWNER) o INDETERMINADA (NULL, historica): el
-- consumidor decide segun esa procedencia (contrato UTC v2); la DB no afirma UTC cuando no lo sabe.
-- fechaRegistroSoporteUtc es un instante UTC DATETIME2(7) generado con SYSUTCDATETIME().
-- Datos personales minimos: solo el nombre del propio estudiante, sin correo.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_revision_estudiante]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @codigoEstado       NVARCHAR(5) = NULL,
    @numeroPagina       INT         = 1,
    @tamanoPagina       INT         = 10
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginacion protegida (minimo 1, maximo 100)
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @estadoFiltro NVARCHAR(5) = NULLIF(TRIM(@codigoEstado), '');
    DECLARE @estadoAdjunto VARCHAR(10) = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idSolicitudRevisionAsistencia = sra.id,
        nombreSolicitud               = sra.nombre,
        fechaSolicitud                = sra.fecha,
        codigoEstado                  = est.codigo,
        nombreEstado                  = est.nombre,
        justificacionSolicitud        = CAST(sra.justificacionSolicitud AS NVARCHAR(MAX)),
        justificacionRespuesta        = CAST(sra.justificacionRespuesta AS NVARCHAR(MAX)),
        idEstudiante                  = estu.id,
        nombreEstudiante              = CAST(CONCAT_WS(N' ',
                                            NULLIF(TRIM(usu.primerNombre), N''),
                                            NULLIF(TRIM(usu.segundoNombre), N''),
                                            NULLIF(TRIM(usu.primerApellido), N''),
                                            NULLIF(TRIM(usu.segundoApellido), N'')) AS NVARCHAR(400)),
        idSesion                      = ses.id,
        numeroSesion                  = ses.numero,
        fechaHoraInicioSesion         = ses.fechaHoraInicio,
        procedenciaTemporalSesion     = ses.procedenciaTemporal,
        idGrupo                       = gru.id,
        codigoGrupo                   = gru.codigo,
        nombreGrupo                   = gru.nombre,
        idAsignatura                  = asg.id,
        codigoAsignatura              = asg.codigo,
        nombreAsignatura              = asg.nombre,
        idArchivoSoporte              = arc.id,
        nombreSoporte                 = arc.nombreOriginal,
        tipoContenidoSoporte          = arc.tipoContenido,
        tamanioSoporteBytes           = arc.tamanioBytes,
        fechaRegistroSoporteUtc       = arc.fechaRegistroUtc,
        totalRegistros                = COUNT(*) OVER()
    FROM dbo.SolicitudRevisionAsistencia sra
    INNER JOIN dbo.Estado est             ON est.id = sra.estado
    INNER JOIN dbo.Asistencia asi         ON asi.id = sra.asistencia
    INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = asi.estudianteGrupo
    INNER JOIN dbo.Estudiante estu        ON estu.id = eg.estudiante
    INNER JOIN dbo.Usuario usu            ON usu.id = estu.usuario
    INNER JOIN dbo.Sesion ses             ON ses.id = asi.sesion
    INNER JOIN dbo.Grupo gru              ON gru.id = ses.grupo
    INNER JOIN dbo.Asignatura asg         ON asg.id = gru.asignatura
    LEFT  JOIN dbo.ArchivoSoporte arc     ON arc.solicitudRevisionAsistencia = sra.id
                                         AND arc.estado = @estadoAdjunto
    WHERE estu.usuario = @idUsuarioDefecto
      AND (@estadoFiltro IS NULL OR est.codigo = @estadoFiltro)
    ORDER BY sra.fecha DESC, sra.nombre ASC, sra.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_archivo_soporte_autorizado.sql (texto anterior a D.2)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_archivo_soporte_autorizado  (LB-004D, R1)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (0..1 fila de datos). NO es un MUTATION_COMMAND_RESULTSET: el
-- resultset de 4 columnas aplica solo a comandos, por eso este SP queda excluido de esa regla en
-- test/test_contract_closure.sql. Los parametros invalidos se propagan con THROW (como
-- usp_consultar_grupos_paginado).
--
-- Autorizacion (se resuelve aqui, ANTES de que el backend pida bytes al storage):
--   PROPIETARIO     usuarioPropietario = ejecutor y estado IN (DRAFT, ATTACHED)
--   DOCENTE_TITULAR estado = ATTACHED y el ejecutor es Docente.usuario del Grupo.docente de la
--                   sesion de la asistencia de la solicitud
-- Cualquier otro caso (inexistente, otro estudiante incluso del mismo grupo, docente no titular,
-- administrador, decano, coordinador, ORPHAN) => 0 filas, sin senal que distinga los casos.
-- Une tablas base: NO usa SESSION_CONTEXT ni uv_auth_* (que exponen reclamos a companeros/roles
-- administrativos, hallazgo H-03).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_archivo_soporte_autorizado]
(
    @idArchivoSoporte   UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idArchivoDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idArchivoSoporte, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    -- Validacion de correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1 AND (@idArchivoSoporte IS NULL OR @idArchivoDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002',
            @p_param1 = 'idArchivoSoporte',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idArchivoSoporte              = a.id,
        estado                        = a.estado,
        nombreOriginal                = a.nombreOriginal,
        tipoContenido                 = a.tipoContenido,
        tamanioBytes                  = a.tamanioBytes,
        checksumSha256                = a.checksumSha256,
        fechaRegistroUtc              = a.fechaRegistroUtc,
        fechaAdjuncionUtc             = a.fechaAdjuncionUtc,
        idSolicitudRevisionAsistencia = a.solicitudRevisionAsistencia,
        relacionAcceso                = CAST(CASE
                                            WHEN a.usuarioPropietario = @idUsuarioDefecto
                                                 AND a.estado IN ('DRAFT', 'ATTACHED') THEN 'PROPIETARIO'
                                            ELSE 'DOCENTE_TITULAR'
                                        END AS VARCHAR(20))
    FROM dbo.ArchivoSoporte a
    WHERE a.id = @idArchivoDefecto
      AND (
            (a.usuarioPropietario = @idUsuarioDefecto AND a.estado IN ('DRAFT', 'ATTACHED'))
         OR (a.estado = 'ATTACHED'
             AND EXISTS (
                SELECT 1
                FROM dbo.SolicitudRevisionAsistencia sra
                INNER JOIN dbo.Asistencia asi ON asi.id = sra.asistencia
                INNER JOIN dbo.Sesion ses     ON ses.id = asi.sesion
                INNER JOIN dbo.Grupo gru      ON gru.id = ses.grupo
                INNER JOIN dbo.Docente doc    ON doc.id = gru.docente
                WHERE sra.id = a.solicitudRevisionAsistencia
                  AND doc.usuario = @idUsuarioDefecto))
          );
END;
GO

-- ---------------------------------------------------------------------------------------------------------------
-- 5. Retiro de los objetos y del esquema de D.2
-- ---------------------------------------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v3', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia_v3];
GO
IF OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_internal_radicar_solicitud_revision];
GO
IF OBJECT_ID(N'dbo.usp_consultar_configuracion_reclamos', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_configuracion_reclamos];
GO
IF OBJECT_ID(N'dbo.uv_soporte_reclamo', N'V') IS NOT NULL DROP VIEW [dbo].[uv_soporte_reclamo];
GO
-- Indice unico filtrado de vuelta (ya no hay mas de un ATTACHED por solicitud) y retiro de IX/FK/columnas de D.2
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.ArchivoSoporte') AND name = 'IX_ArchivoSoporte_Solicitud')
    DROP INDEX [IX_ArchivoSoporte_Solicitud] ON [dbo].[ArchivoSoporte];
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.ArchivoSoporte') AND name = 'UX_ArchivoSoporte_Solicitud')
    CREATE UNIQUE NONCLUSTERED INDEX [UX_ArchivoSoporte_Solicitud]
    ON [dbo].[ArchivoSoporte] ([solicitudRevisionAsistencia])
    WHERE [solicitudRevisionAsistencia] IS NOT NULL;
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SolicitudRevisionAsistencia_CategoriaJustificacion')
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] DROP CONSTRAINT [FK_SolicitudRevisionAsistencia_CategoriaJustificacion];
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SolicitudRevisionAsistencia') AND name = 'IX_SolicitudRevisionAsistencia_Categoria')
    DROP INDEX [IX_SolicitudRevisionAsistencia_Categoria] ON [dbo].[SolicitudRevisionAsistencia];
GO
IF COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'categoriaJustificacion') IS NOT NULL
    ALTER TABLE [dbo].[SolicitudRevisionAsistencia] DROP COLUMN [categoriaJustificacion];
GO
IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_CategoriaJustificacion_requiereSoporte')
    ALTER TABLE [dbo].[CategoriaJustificacion] DROP CONSTRAINT [DF_CategoriaJustificacion_requiereSoporte];
GO
IF COL_LENGTH('dbo.CategoriaJustificacion', 'requiereSoporte') IS NOT NULL
    ALTER TABLE [dbo].[CategoriaJustificacion] DROP COLUMN [requiereSoporte];
GO
-- Mensajes y parametros de D.2 (los parametros solo si siguen en su valor por defecto, para no perder lo que administro el usuario)
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo IN ('REV_021', 'REV_022', 'REV_023', 'REV_024');
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo IN ('REV_021', 'REV_022', 'REV_023', 'REV_024');
GO
-- D.3 (CatalogoParametroEdicion, CambioParametro) referencia estos parametros: se retiran sus filas antes que los parametros
IF OBJECT_ID(N'dbo.CatalogoParametroEdicion', N'U') IS NOT NULL
    EXEC sys.sp_executesql N'DELETE e FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
        WHERE ((p.grupo = ''ARCHIVOS'' AND p.clave = ''MAXIMO_SOPORTES_POR_RECLAMO'') OR (p.grupo = ''ARCHIVO'' AND p.clave IN (''ESTADO_BORRADOR'', ''TIPOS_PERMITIDOS''))) AND p.valor = p.valorDefecto;';
GO
DELETE FROM [dbo].[CatalogoParametro]
WHERE ((grupo = 'ARCHIVOS' AND clave = 'MAXIMO_SOPORTES_POR_RECLAMO') OR (grupo = 'ARCHIVO' AND clave IN ('ESTADO_BORRADOR', 'TIPOS_PERMITIDOS')))
  AND valor = valorDefecto;
GO
