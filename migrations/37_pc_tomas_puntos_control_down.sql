-- ============================================================================
-- MIGRACION DOWN 37: retira PC - tomas de asistencia como puntos de control
-- Requiere la variable sqlcmd CONFIRMAR_RETIRO_RECLAMO_TOMA (-v CONFIRMAR_RETIRO_RECLAMO_TOMA=0|1 o :setvar antes de :r). Sin ella sqlcmd se
-- detiene antes de cambiar nada (:on error exit).
--   1. Si hay solicitudes de revision con toma y CONFIRMAR_RETIRO_RECLAMO_TOMA <> 1: THROW 50037 sin cambios. Con confirmacion esas
--      solicitudes quedan como reclamos de la sesion (se pierde la toma y el resultado de la aprobacion); los detalles AN que dejo una
--      aprobacion "si estuvo presente" se conservan (no se revierten datos de negocio).
--   2. DROP de usp_consultar_resumen_tomas_sesion y usp_radicar_solicitud_revision_asistencia_v4; restaura el texto de develop de los SP y
--      vistas modificados; DROP de uv_asistencia_toma_estudiante, uv_asistencia_tramo y uv_toma_punto_control.
--   3. Borra los mensajes TOM_012 y REV_026..REV_029; el tope vuelve a 4 solo si sigue en 20; el modo MANUAL deja de marcar ausentes.
--   4. DROP del indice, las FK y las columnas toma y razonCausaResolucion.
-- Las tomas por encima de 4 ya creadas permanecen. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 37 DOWN: retira PC tomas de asistencia como puntos de control';
GO
SET NOCOUNT ON;
IF COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'toma') IS NOT NULL
BEGIN
    DECLARE @confirmar NVARCHAR(10) = N'$(CONFIRMAR_RETIRO_RECLAMO_TOMA)';
    DECLARE @hayReclamosToma BIT = 0;
    EXEC sys.sp_executesql N'SELECT @r = IIF(EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE toma IS NOT NULL), 1, 0);',
        N'@r BIT OUTPUT', @r = @hayReclamosToma OUTPUT;
    IF @hayReclamosToma = 1 AND @confirmar <> N'1'
        THROW 50037, 'PC_DOWN: hay reclamos por toma; ejecute con CONFIRMAR_RETIRO_RECLAMO_TOMA = 1 para dejarlos como reclamos de la sesion.', 1;
END
GO
IF OBJECT_ID(N'dbo.usp_consultar_resumen_tomas_sesion', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_resumen_tomas_sesion;
GO
IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v4', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_radicar_solicitud_revision_asistencia_v4;
GO
-- ---- texto previo (develop) de schema/stored-procedures/usp_registrar_asistencias_toma.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_asistencias_toma (CULM-001 B.2, HU175; CONTRACT §2.8.2, DEC-013, [SUPUESTO-B-08])
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idToma, idSesion, idGrupo, totalRegistros
-- (NULL si estadoResultado = 0).
--
-- Lote del docente titular sobre UNA toma (abierta o cerrada: una cerrada admite correccion mientras dure la ventana
-- [inicio - TOLERANCIA, fin + MARGEN)). @asistenciaJSON = [{"idEstudiante":"uuid","estado":"AN|SJC|EX"}] con las mismas
-- reglas del lote congelado: ATT_001 (no es arreglo o claves distintas de idEstudiante/estado), ATT_002 (vacio), GEN_002
-- (idEstudiante nulo o invalido), RC_001 (estado fuera de AN/SJC/EX), ATT_003 (duplicado), EST_004 (sin matricula A).
-- Todo se valida antes de escribir; el lote es atomico; la ventana se revalida al confirmar. Exito TOM_010.
-- Bloqueos: Sesion (ventana) -> TomaAsistencia -> EstudianteGrupo -> Asistencia -> DetalleAsistencia.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_asistencias_toma]
(
    @idToma            UNIQUEIDENTIFIER,
    @asistenciaJSON    NVARCHAR(MAX),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTomaDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idToma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeDescartado       NVARCHAR(4000);
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @huboEscritura          BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @toleranciaMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS');
    DECLARE @margenMinutos     INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @codigoActiva      NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idSesion          UNIQUEIDENTIFIER;
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @totalEstudiantes  INT = 0;
    DECLARE @iterador          INT = 1;
    DECLARE @idEstudianteActual UNIQUEIDENTIFIER;
    DECLARE @estadoActual      NVARCHAR(200);
    DECLARE @idEstudianteInvalido UNIQUEIDENTIFIER;
    DECLARE @secuenciaInvalida INT;
    DECLARE @estadoInvalido    NVARCHAR(200);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    DECLARE @EstudiantesATrabajar TABLE (secuencia INT IDENTITY(1,1), idEstudiante UNIQUEIDENTIFIER NULL, estado NVARCHAR(200) NULL);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
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
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            SELECT @idSesion = t.sesion, @idGrupo = s.grupo
            FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion
            WHERE t.id = @idTomaDefecto;

            IF @idSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_001', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idSesion, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- Validacion completa del JSON antes de cualquier escritura (mismas reglas del lote congelado)
        IF @estadoResultado = 1
           AND (@asistenciaJSON IS NULL OR ISJSON(@asistenciaJSON, ARRAY) <> 1
                OR EXISTS (SELECT 1 FROM OPENJSON(@asistenciaJSON) item
                           WHERE item.[type] <> 5
                              OR (SELECT COUNT(1) FROM OPENJSON(item.value)) <> 2
                              OR NOT EXISTS (SELECT 1 FROM OPENJSON(item.value) f WHERE f.[key] = 'idEstudiante')
                              OR NOT EXISTS (SELECT 1 FROM OPENJSON(item.value) f WHERE f.[key] = 'estado')))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ATT_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            INSERT INTO @EstudiantesATrabajar (idEstudiante, estado)
            SELECT TRY_CAST(idEstudiante AS UNIQUEIDENTIFIER), UPPER(TRIM(estado))
            FROM OPENJSON(@asistenciaJSON) WITH (idEstudiante NVARCHAR(100) '$.idEstudiante', estado NVARCHAR(200) '$.estado');
            SELECT @totalEstudiantes = COUNT(1) FROM @EstudiantesATrabajar;

            IF @totalEstudiantes = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ATT_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @secuenciaInvalida = secuencia FROM @EstudiantesATrabajar WHERE idEstudiante IS NULL ORDER BY secuencia;
            IF @secuenciaInvalida IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idEstudiante',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @secuenciaInvalida = secuencia,
                   @estadoInvalido = CASE WHEN estado IS NULL OR estado = '' THEN N'(vacio)' ELSE estado END
            FROM @EstudiantesATrabajar
            WHERE estado IS NULL OR estado = '' OR estado NOT IN ('AN', 'SJC', 'EX')
            ORDER BY secuencia;
            IF @secuenciaInvalida IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RC_001', @p_param1 = @estadoInvalido,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstudianteInvalido = idEstudiante FROM @EstudiantesATrabajar GROUP BY idEstudiante HAVING COUNT(1) > 1 ORDER BY idEstudiante;
            IF @idEstudianteInvalido IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ATT_003', @p_param1 = @idEstudianteInvalido,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstudianteInvalido = et.idEstudiante
            FROM @EstudiantesATrabajar et
            WHERE NOT EXISTS (
                SELECT 1 FROM dbo.EstudianteGrupo eg
                INNER JOIN dbo.EstadoEstudianteGrupo eeg ON eeg.id = eg.estado
                WHERE eg.estudiante = et.idEstudiante AND eg.grupo = @idGrupo AND eeg.codigo = @codigoActiva)
            ORDER BY et.secuencia;
            IF @idEstudianteInvalido IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'EST_004', @p_param1 = @idEstudianteInvalido, @p_param2 = @idSesion,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- Escritura atomica: ventana con tolerancia (bloquea Sesion) -> toma -> sincronizacion por estudiante
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_asistencias_toma;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_validar_sesion_ventana_registro_interno
                @idSesion = @idSesion, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @toleranciaMinutos = @toleranciaMinutos, @margenMinutos = @margenMinutos;

            IF @estadoResultado = 1
                SELECT @idSesion = t.sesion FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK) WHERE t.id = @idTomaDefecto;

            WHILE @iterador <= @totalEstudiantes AND @estadoResultado = 1
            BEGIN
                SELECT @idEstudianteActual = idEstudiante, @estadoActual = estado FROM @EstudiantesATrabajar WHERE secuencia = @iterador;
                SET @huboEscritura = 1;
                EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
                    @idEstudiante = @idEstudianteActual, @idSesion = @idSesion, @codigoEstado = @estadoActual,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT,
                    @idToma = @idTomaDefecto, @registradoPorEstudiante = 0, @soloSiNoExiste = 0, @idUsuarioEjecutor = @idUsuarioEjecutorDefecto;
                SET @iterador += 1;
            END

            -- La ventana debe seguir abierta en el punto de confirmacion
            IF @estadoResultado = 1
                EXEC dbo.usp_validar_sesion_ventana_registro_interno
                    @idSesion = @idSesion, @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT,
                    @toleranciaMinutos = @toleranciaMinutos, @margenMinutos = @margenMinutos;

            IF @estadoResultado = 1
            BEGIN
                SET @p1 = CONVERT(NVARCHAR(36), @idTomaDefecto);
                SET @p2 = CONVERT(NVARCHAR(20), @totalEstudiantes);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_010', @p_param1 = @p1, @p_param2 = @p2,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1 AND (@estadoResultado = 1 OR @huboEscritura = 0)
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() <> 0
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
            ELSE IF @savepointCreado = 1 AND XACT_STATE() = 1 AND @estadoResultado = 0 AND @huboEscritura = 1
                ROLLBACK TRANSACTION sp_asistencias_toma;
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
            ROLLBACK TRANSACTION sp_asistencias_toma;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idToma                  = IIF(@estadoResultado = 1, @idTomaDefecto, NULL),
        idSesion                = IIF(@estadoResultado = 1, @idSesion, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        totalRegistros          = IIF(@estadoResultado = 1, @totalEstudiantes, NULL);
END;
GO
GO
-- ---- texto previo (develop) de schema/stored-procedures/usp_consultar_tomas_sesion.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_tomas_sesion (CULM-001 B.2, HU175; CONTRACT §2.8.4, §3.2.5 GET /sesiones/{id}/tomas)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 con el mensaje tecnico si la validacion
-- falla). RBAC DOCENTE + titularidad sobre la sesion (SES_001 / SEC_001 / SEC_002 / GEN_002).
-- Filas: una por toma de la sesion (uv_toma_asistencia, orden numero) con los datos de la sesion y su ventana
-- (uv_sesion_estado: ventanaAperturaUtc, ventanaCierreUtc, ventanaAbierta, estaSesionCancelada, motivoCancelacion) y
-- maximoTomas (TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION). Una sesion SIN tomas devuelve una fila con los datos de la sesion
-- y las columnas de la toma en NULL (el docente ve la ventana antes de abrir la primera toma).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_tomas_sesion]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @maximoTomas          INT = dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'MAXIMO_TOMAS_POR_SESION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
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
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_sesion_exista_por_id_interno
            @idSesion = @idSesionDefecto, @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @idUsuarioDefecto, @idEntidadPadre = @idSesionDefecto, @tipoEntidadPadre = 'SESION',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT
        idSesion              = se.idSesion,
        idGrupo               = se.idGrupo,
        numeroSesion          = se.numero,
        horasSesion           = se.horasSesion,
        estaSesionCancelada   = se.estaCancelada,
        motivoCancelacion     = se.motivoCancelacion,
        ventanaAperturaUtc    = se.ventanaAperturaUtc,
        ventanaCierreUtc      = se.ventanaCierreUtc,
        ventanaAbierta        = se.ventanaAbierta,
        maximoTomas           = @maximoTomas,
        totalTomasSesion      = se.totalTomas,
        idToma                = t.idToma,
        numero                = t.numero,
        idModo                = t.idModo,
        codigoModo            = t.codigoModo,
        nombreModo            = t.nombreModo,
        usaCodigoQr           = t.usaCodigoQr,
        marcaAusentesAlCerrar = t.marcaAusentesAlCerrar,
        idEstado              = t.idEstado,
        codigoEstado          = t.codigoEstado,
        nombreEstado          = t.nombreEstado,
        estaAbierta           = t.estaAbierta,
        esImplicita           = t.esImplicita,
        idDocenteApertura     = t.idDocenteApertura,
        fechaAperturaUtc      = t.fechaAperturaUtc,
        fechaCierreUtc        = t.fechaCierreUtc,
        totalAusentesMarcados = t.totalAusentesMarcados,
        horasToma             = t.horasToma,
        totalRegistros        = t.totalRegistros,
        totalPresentes        = t.totalPresentes,
        totalAusentes         = t.totalAusentes,
        totalExcusas          = t.totalExcusas,
        tieneQrActivo         = t.tieneQrActivo
    FROM dbo.uv_sesion_estado se
    LEFT JOIN dbo.uv_toma_asistencia t ON t.idSesion = se.idSesion
    WHERE se.idSesion = @idSesionDefecto
    ORDER BY t.numero ASC;
END;
GO
GO
-- ---- texto previo (develop) de schema/stored-procedures/usp_internal_radicar_solicitud_revision.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_radicar_solicitud_revision  (CULM-001 D.2, HU014/HU015; CONTRACT §3.2, DEC-044 (3))
--
-- Nucleo interno COMUN de la radicacion de un reclamo: NO se concede a ningun rol. Lo invocan
-- usp_radicar_solicitud_revision_asistencia_v2 (un solo soporte) y _v3 (de 0 a ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO) con
-- parametros OUTPUT, sin INSERT-EXEC (Msg 3915, DEC-036): no emite resultset; el llamador emite el suyo.
--
-- Orden (cada paso solo se evalua si los anteriores pasaron; un rechazo no escribe nada):
--   correlacion -> ejecutor -> RBAC ESTUDIANTE -> estudiante -> propiedad (H-01) -> sesion -> matricula
--   -> reejecucion idempotente por correlacion (algun soporte ya ATTACHED con la MISMA correlacion y del mismo dueno:
--      devuelve la solicitud y el total originales sin escribir)
--   -> plazo de excusas (usp_internal_validar_plazo_justificacion, D.1: REV_020 / REV_025)
--   -> categoria por codigo o por nombre (REV_021)
--   -> JSON valido (arreglo de GUID) y GUID distintos (GEN_002 / REV_024)
--   -> cantidad <= ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO (REV_023)
--   -> categoria con requiereSoporte y 0 soportes (REV_022)
--   -> cada soporte WITH (UPDLOCK, HOLDLOCK) en orden de id: dueno = ejecutor y estado ARCHIVO/ESTADO_BORRADOR
--      (inexistente, ajeno, ya vinculado u huerfano => ARC_001 identico, sin revelar el motivo)
--   -> INSERT de la solicitud (categoria y fecha LOCAL de radicacion) -> UPDATE de todos los soportes a ARCHIVO/ESTADO_ADJUNTO
--   -> verificacion por lectura de las N filas.
-- Los estados de soporte y de reclamo salen de parametros (TD-061), no de literales.
-- Ownership transaccional: transaccion propia si @@TRANCOUNT = 0, si no SAVE TRANSACTION (solo se revierte lo escrito).
-- En @estadoResultado = 1 con reejecucion idempotente no se escribe nada.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_radicar_solicitud_revision]
(
    @idEstudiante             UNIQUEIDENTIFIER,
    @idSesion                 UNIQUEIDENTIFIER,
    @categoria                NVARCHAR(50),
    @justificacion            NVARCHAR(MAX),
    @idsArchivoSoporte        NVARCHAR(MAX),
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER,
    @idSolicitudRevision      UNIQUEIDENTIFIER OUTPUT,
    @totalSoportes            INT              OUTPUT,
    @mensajeUsuarioResultado  NVARCHAR(4000)   OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000)   OUTPUT,
    @estadoResultado          BIT              OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @justificacionDefecto     NVARCHAR(MAX)    = TRIM(@justificacion);
    DECLARE @categoriaDefecto         NVARCHAR(50)     = TRIM(@categoria);
    DECLARE @estadoAdjunto            VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));
    DECLARE @estadoBorrador           VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_BORRADOR') AS VARCHAR(10));
    DECLARE @codigoPendiente          NVARCHAR(5)      = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_PENDIENTE') AS NVARCHAR(5));

    DECLARE @idAsistencia         UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @nuevaSolicitudId     UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSolicitud      NVARCHAR(50);
    DECLARE @idEstadoPendiente    UNIQUEIDENTIFIER;
    DECLARE @idCategoria          UNIQUEIDENTIFIER;
    DECLARE @nombreCategoria      NVARCHAR(50);
    DECLARE @requiereSoporte      BIT = 0;

    -- Lista de soportes: @ids en el orden recibido; @ordenados sin repetidos y por id (orden fijo de bloqueo)
    DECLARE @ids TABLE (orden INT IDENTITY(1, 1) NOT NULL, id UNIQUEIDENTIFIER NULL);
    DECLARE @ordenados TABLE (pos INT IDENTITY(1, 1) NOT NULL, id UNIQUEIDENTIFIER NOT NULL);
    DECLARE @jsonValido           BIT = 1;
    DECLARE @cantidad             INT = 0;
    DECLARE @distintos            INT = 0;
    DECLARE @maximo               INT;
    DECLARE @pos                  INT = 1;
    DECLARE @idArchivo            UNIQUEIDENTIFIER;
    DECLARE @propietarioSoporte   UNIQUEIDENTIFIER;
    DECLARE @estadoSoporte        VARCHAR(10);
    DECLARE @correlacionAdjuncion UNIQUEIDENTIFIER;
    DECLARE @solicitudSoporte     UNIQUEIDENTIFIER;
    DECLARE @esReintento          BIT = 0;
    DECLARE @fechaLimiteUtc       DATETIME2(7);
    DECLARE @zonaLocal            NVARCHAR(128);
    DECLARE @fechaLocalRadicacion DATE;
    DECLARE @filasActualizadas    INT;
    DECLARE @escrituraRealizada   BIT = 0;
    DECLARE @textoCantidad        NVARCHAR(20);
    DECLARE @textoMaximo          NVARCHAR(20);
    DECLARE @descartado           NVARCHAR(4000);

    DECLARE @conteoTransaccionesInicial INT;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    SET @idSolicitudRevision     = NULL;
    SET @totalSoportes           = 0;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado         = 1;

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

        -- PASO 8: Lista de soportes (arreglo JSON de GUID). Solo se lee aqui; los errores se informan en su turno.
        IF @idsArchivoSoporte IS NOT NULL AND LEN(TRIM(@idsArchivoSoporte)) > 0
        BEGIN
            IF ISJSON(@idsArchivoSoporte) = 1 AND LEFT(LTRIM(@idsArchivoSoporte), 1) = N'['
            BEGIN
                INSERT @ids (id)
                SELECT TRY_CAST(j.[value] AS UNIQUEIDENTIFIER)
                FROM OPENJSON(@idsArchivoSoporte) j
                ORDER BY CAST(j.[key] AS INT);
                IF EXISTS (SELECT 1 FROM OPENJSON(@idsArchivoSoporte) j WHERE j.[type] <> 1)
                   OR EXISTS (SELECT 1 FROM @ids WHERE id IS NULL)
                    SET @jsonValido = 0;
            END
            ELSE
                SET @jsonValido = 0;
        END
        SELECT @cantidad = COUNT(*), @distintos = COUNT(DISTINCT id) FROM @ids;

        -- PASO 9: Transaccion propia (o savepoint si el llamador ya tiene una)
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
                SAVE TRANSACTION sp_culm001_d2_radicar;
                SET @savepointCreado = 1;
            END
        END

        -- PASO 10: Reejecucion idempotente por correlacion (antes del plazo: un reintento legitimo tras el vencimiento
        -- devuelve el exito original). Es un soporte ya vinculado con ESTA correlacion y del mismo dueno.
        IF @estadoResultado = 1 AND @jsonValido = 1 AND @cantidad > 0
        BEGIN
            SELECT TOP 1 @solicitudSoporte = a.solicitudRevisionAsistencia
            FROM dbo.ArchivoSoporte a
            INNER JOIN @ids i ON i.id = a.id
            WHERE a.estado = @estadoAdjunto
              AND a.idCorrelacionAdjuncion = @idCorrelacionDefecto
              AND a.usuarioPropietario = @idUsuarioEjecutorDefecto
            ORDER BY a.id;
            IF @solicitudSoporte IS NOT NULL
            BEGIN
                SET @esReintento = 1;
                SET @idSolicitudRevision = @solicitudSoporte;
            END
        END

        -- PASO 11: Plazo de excusas (D.1). Solo cuando NO es la reejecucion idempotente de una radicacion ya exitosa.
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

        -- PASO 12: Categoria por codigo o por nombre (el codigo gana si ambos coinciden con filas distintas)
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SELECT TOP 1 @idCategoria = c.id, @nombreCategoria = c.nombre, @requiereSoporte = c.requiereSoporte
            FROM dbo.CategoriaJustificacion c
            WHERE c.codigo = @categoriaDefecto OR c.nombre = @categoriaDefecto
            ORDER BY IIF(c.codigo = @categoriaDefecto, 0, 1), c.id;
            IF @idCategoria IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_021', @p_param1 = @categoriaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 13: JSON valido y soportes distintos
        IF @estadoResultado = 1 AND @esReintento = 0 AND @jsonValido = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idsArchivoSoporte',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        IF @estadoResultado = 1 AND @esReintento = 0 AND @cantidad <> @distintos
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_024',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 14: Cantidad maxima de soportes (ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO)
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SET @maximo = dbo.ufn_obtener_parametro_int(NULL, 'ARCHIVOS', 'MAXIMO_SOPORTES_POR_RECLAMO');
            IF @maximo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_002', @p_param1 = 'ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @cantidad > @maximo
            BEGIN
                SET @textoCantidad = CONVERT(NVARCHAR(20), @cantidad);
                SET @textoMaximo = CONVERT(NVARCHAR(20), @maximo);
                -- El mensaje de usuario usa solo {1} (maximo); el tecnico usa {1}=cantidad, {2}=maximo.
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_023', @p_param1 = @textoMaximo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @descartado OUTPUT;
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_023', @p_param1 = @textoCantidad, @p_param2 = @textoMaximo,
                    @mensajeUsuarioResultado = @descartado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 15: Soporte obligatorio segun la categoria (HU014)
        IF @estadoResultado = 1 AND @esReintento = 0 AND @requiereSoporte = 1 AND @cantidad = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_022', @p_param1 = @nombreCategoria,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 16: Bloqueo de cada soporte en orden de id (UPDLOCK, HOLDLOCK serializa radicaciones concurrentes con el mismo fileId)
        IF @estadoResultado = 1 AND @esReintento = 0 AND @cantidad > 0
        BEGIN
            INSERT @ordenados (id) SELECT DISTINCT id FROM @ids ORDER BY id;
            WHILE @pos <= (SELECT COUNT(*) FROM @ordenados) AND @estadoResultado = 1 AND @esReintento = 0
            BEGIN
                SELECT @idArchivo = o.id FROM @ordenados o WHERE o.pos = @pos;
                SET @propietarioSoporte = NULL; SET @estadoSoporte = NULL; SET @correlacionAdjuncion = NULL; SET @solicitudSoporte = NULL;
                SELECT @propietarioSoporte   = a.usuarioPropietario,
                       @estadoSoporte        = a.estado,
                       @correlacionAdjuncion = a.idCorrelacionAdjuncion,
                       @solicitudSoporte     = a.solicitudRevisionAsistencia
                FROM dbo.ArchivoSoporte a WITH (UPDLOCK, HOLDLOCK)
                WHERE a.id = @idArchivo;

                IF @propietarioSoporte IS NULL OR @propietarioSoporte <> @idUsuarioEjecutorDefecto
                BEGIN
                    SET @estadoResultado = 0;
                END
                ELSE IF @estadoSoporte = @estadoAdjunto AND @correlacionAdjuncion = @idCorrelacionDefecto
                BEGIN
                    -- Carrera con la misma solicitud (doble envio): la otra sesion ya confirmo; es una reejecucion
                    SET @esReintento = 1;
                    SET @idSolicitudRevision = @solicitudSoporte;
                END
                ELSE IF @estadoSoporte <> @estadoBorrador
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
                SET @pos += 1;
            END
        END

        -- PASO 17: Creacion de la solicitud y vinculo atomico de los N soportes
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

            SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado WHERE codigo = @codigoPendiente ORDER BY id ASC;
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
                justificacionSolicitud, justificacionRespuesta, categoriaJustificacion
            )
            VALUES (
                @nuevaSolicitudId,
                @nombreSolicitud,
                @idAsistencia,
                @fechaLocalRadicacion,
                @idEstadoPendiente,
                CASE WHEN @justificacionDefecto IS NOT NULL AND @justificacionDefecto <> '' THEN @justificacionDefecto ELSE 'Solicitud de revision de asistencia radicada por estudiante.' END,
                '',
                @idCategoria
            );

            IF @cantidad > 0
            BEGIN
                UPDATE a
                SET estado = @estadoAdjunto,
                    solicitudRevisionAsistencia = @nuevaSolicitudId,
                    fechaAdjuncionUtc = SYSUTCDATETIME(),
                    fechaCambioEstadoUtc = SYSUTCDATETIME(),
                    idCorrelacionAdjuncion = @idCorrelacionDefecto
                FROM dbo.ArchivoSoporte a
                INNER JOIN @ordenados o ON o.id = a.id
                WHERE a.estado = @estadoBorrador
                  AND a.usuarioPropietario = @idUsuarioEjecutorDefecto;
                SET @filasActualizadas = @@ROWCOUNT;

                -- Postcondicion verificada por lectura (no solo @@ROWCOUNT): los N soportes quedaron vinculados a ESTA solicitud.
                IF @filasActualizadas <> @cantidad
                   OR (SELECT COUNT(*) FROM dbo.ArchivoSoporte a INNER JOIN @ordenados o ON o.id = a.id
                       WHERE a.estado = @estadoAdjunto AND a.solicitudRevisionAsistencia = @nuevaSolicitudId) <> @cantidad
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ARC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
            IF @estadoResultado = 1
                SET @idSolicitudRevision = @nuevaSolicitudId;
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @totalSoportes = COUNT(*) FROM dbo.uv_soporte_reclamo WHERE idSolicitud = @idSolicitudRevision;
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudRevisionAsistencia',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
        ELSE
        BEGIN
            SET @idSolicitudRevision = NULL;
            SET @totalSoportes = 0;
        END

        -- PASO 18: Finalizacion respetando ownership: commit solo si el resultado es exitoso
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
                ROLLBACK TRANSACTION sp_culm001_d2_radicar;
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
            ROLLBACK TRANSACTION sp_culm001_d2_radicar;
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
        SET @idSolicitudRevision = NULL;
        SET @totalSoportes = 0;
        SET @estadoResultado = 0;
    END CATCH
END;
GO
GO
-- ---- texto previo (develop) de schema/stored-procedures/usp_resolver_solicitud_revision_asistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SES-04: resolucion del reclamo de inasistencia por el docente titular (flujo formal posterior al cierre).
--   * @accion: exactamente APROBADA o RECHAZADA (TRIM + UPPER). Cualquier otro valor => REV_001, sin escrituras.
--   * APROBADA: la asistencia queda JUSTIFICADA = RazonCausa EX con asistio = 0 (no es presencia AN). La solicitud pasa
--     a A. Si la asistencia ya era EX solo se resuelve la solicitud. Una asistencia AN no es justificable => REV_003.
--   * RECHAZADA: la solicitud pasa a R y DetalleAsistencia NO se modifica.
--   * Concurrencia: la solicitud se lee con UPDLOCK/HOLDLOCK dentro de la transaccion; dos resoluciones simultaneas se
--     serializan. Reintento con la misma decision ya aplicada => exito idempotente sin nuevas escrituras ni auditoria;
--     decision contradictoria sobre una solicitud ya resuelta => REV_002.
--   * Solicitud inexistente => REV_005; docente no titular => VAL_007 (contrato previo); sin detalle de asistencia
--     => REV_004 (no se simula una justificacion ni se crean filas).
--   * Auditoria oficial (dbo.AuditoriaEvento) en la MISMA transaccion: actor, accion, estado previo y nuevo de la
--     solicitud y del detalle, respuesta y correlacion.
--   * No usa la ventana de registro ordinario (SES-01): la rectificacion por reclamo es valida despues del cierre.
--   * Firma y resultset canonico de 4 columnas sin cambio.
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_solicitud_revision_asistencia]
(
    @idSolicitud        UNIQUEIDENTIFIER,
    @idDocente          UNIQUEIDENTIFIER,
    @accion             NVARCHAR(20),
    @respuestaDocente   NVARCHAR(MAX),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto         UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @accionDefecto            NVARCHAR(20)     = UPPER(TRIM(@accion));
    DECLARE @respuestaDefecto         NVARCHAR(MAX)    = TRIM(@respuestaDocente);

    DECLARE @docenteTitularGrupo   UNIQUEIDENTIFIER;
    DECLARE @idAsistencia          UNIQUEIDENTIFIER;
    DECLARE @idDetalle             UNIQUEIDENTIFIER;
    DECLARE @asistioAnterior       BIT;
    DECLARE @codigoCausaAnterior   NVARCHAR(5);
    DECLARE @codigoEstadoActual    CHAR(1);
    DECLARE @codigoEstadoNuevo     CHAR(1);
    DECLARE @idEstadoNuevo         UNIQUEIDENTIFIER;
    DECLARE @idRazonJustificada    UNIQUEIDENTIFIER;
    DECLARE @modificaDetalle       BIT = 0;

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

        -- PASO 1.5: El ejecutor es obligatorio y debe tener perfil DOCENTE
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
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.6 (SES-04): solo las acciones contractuales; ningun otro valor se interpreta como rechazo
        IF @estadoResultado = 1 AND (@accionDefecto IS NULL OR @accionDefecto NOT IN (N'APROBADA', N'RECHAZADA'))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_001',
                @p_param1 = @accion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: Resolución atómica. La solicitud, su estado y su detalle se leen bajo bloqueo dentro de la
        --         transacción; los rechazos de negocio confirman una transacción sin escrituras (así no hay ROLLBACK
        --         dentro de un INSERT ... EXEC del llamador).
        IF @estadoResultado = 1
        BEGIN
            BEGIN TRANSACTION;

            SELECT TOP 1
                @docenteTitularGrupo = g.docente,
                @idAsistencia = sra.asistencia,
                @codigoEstadoActual = e.codigo
            FROM dbo.SolicitudRevisionAsistencia sra WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Estado e ON e.id = sra.estado
            INNER JOIN dbo.Asistencia ast ON sra.asistencia = ast.id
            INNER JOIN dbo.Sesion s ON ast.sesion = s.id
            INNER JOIN dbo.Grupo g ON s.grupo = g.id
            WHERE sra.id = @idSolicitudDefecto;

            -- 2.1: solicitud existente con relacion solicitud -> asistencia -> sesion -> grupo
            IF @docenteTitularGrupo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_005',
                    @p_param1 = @idSolicitudDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            -- 2.2: titularidad del docente sobre el grupo de la sesion
            ELSE IF @docenteTitularGrupo <> @idDocenteDefecto
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_007',
                    @p_param1 = 'DocenteAmbitoRevision',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1
            BEGIN
                SET @codigoEstadoNuevo = CASE WHEN @accionDefecto = N'APROBADA' THEN 'A' ELSE 'R' END;

                -- 2.3: solo una solicitud pendiente se resuelve. La misma decision ya aplicada es un reintento
                --      idempotente (sin escrituras); una decision distinta es un conflicto.
                IF @codigoEstadoActual <> 'P'
                BEGIN
                    IF @codigoEstadoActual <> @codigoEstadoNuevo
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_002',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END
                END
                ELSE
                BEGIN
                    -- 2.4: detalle de la asistencia (bloqueado). Sin detalle no se simula una justificacion.
                    -- CULM-001 B.2 (CONTRACT §2.9): con varias tomas se bloquean todos los detalles de la asistencia y el
                    -- representativo es el de estado consolidado (SJC antes que EX antes que AN): con una toma, el mismo de antes.
                    SELECT TOP 1
                        @idDetalle = d.id,
                        @asistioAnterior = d.asistio,
                        @codigoCausaAnterior = rc.codigo
                    FROM dbo.DetalleAsistencia d WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.RazonCausa rc ON rc.id = d.razonCausa
                    WHERE d.asistencia = @idAsistencia
                    ORDER BY CASE rc.codigo WHEN N'SJC' THEN 0 WHEN N'EX' THEN 1 ELSE 2 END, d.id;

                    IF @idDetalle IS NULL
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_004',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END
                    -- 2.5: solo una ausencia es justificable; una presencia (AN / asistio = 1) no se aprueba
                    ELSE IF @codigoEstadoNuevo = 'A' AND (@asistioAnterior = 1 OR @codigoCausaAnterior = N'AN')
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_003',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END

                    -- 2.6: catalogos cerrados (Estado A/R, RazonCausa EX); nunca se elige otra fila
                    IF @estadoResultado = 1
                    BEGIN
                        SELECT @idEstadoNuevo = id FROM dbo.Estado WHERE codigo = @codigoEstadoNuevo;
                        SELECT @idRazonJustificada = id FROM dbo.RazonCausa WHERE codigo = N'EX';
                        IF @idEstadoNuevo IS NULL OR (@codigoEstadoNuevo = 'A' AND @idRazonJustificada IS NULL)
                            THROW 52401, 'SES04_CATALOGO_INCONSISTENTE: falta Estado A/R o RazonCausa EX.', 1;

                        SET @modificaDetalle = CASE WHEN @codigoEstadoNuevo = 'A' AND @codigoCausaAnterior <> N'EX' THEN 1 ELSE 0 END;

                        -- 2.7: la solicitud queda resuelta con la respuesta del docente
                        UPDATE dbo.SolicitudRevisionAsistencia
                        SET estado = @idEstadoNuevo,
                            justificacionRespuesta = CASE WHEN @respuestaDefecto IS NOT NULL THEN @respuestaDefecto ELSE '' END
                        WHERE id = @idSolicitudDefecto;

                        -- 2.8: aprobacion => JUSTIFICADA (EX, asistio = 0). El rechazo no toca DetalleAsistencia.
                        IF @modificaDetalle = 1
                        BEGIN
                            UPDATE d
                            SET razonCausa = @idRazonJustificada,
                                asistio = 0
                            FROM dbo.DetalleAsistencia d
                            INNER JOIN dbo.RazonCausa rc ON rc.id = d.razonCausa
                            WHERE d.asistencia = @idAsistencia
                              AND (d.id = @idDetalle OR rc.codigo = N'SJC');
                        END

                        -- 2.9: auditoria oficial con estado previo y nuevo, en la misma transaccion
                        INSERT INTO dbo.AuditoriaEvento (
                            id, occurredAt, actorId, actorType, action,
                            resourceType, resourceId, result, correlationId,
                            httpMethod, path, httpStatus, metadata
                        ) VALUES (
                            NEWID(),
                            SYSDATETIMEOFFSET(),
                            CAST(@idUsuarioEjecutorDefecto AS NVARCHAR(120)),
                            'USER',
                            'RESOLVER_SOLICITUD_REVISION_ASISTENCIA',
                            'SolicitudRevisionAsistencia',
                            CAST(@idSolicitudDefecto AS NVARCHAR(120)),
                            'SUCCESS',
                            @idCorrelacionDefecto,
                            'PATCH',
                            N'/api/v1/docente/reclamos/{id}',
                            200,
                            (SELECT accion = @accionDefecto,
                                    estadoSolicitudAnterior = @codigoEstadoActual,
                                    estadoSolicitudNuevo = @codigoEstadoNuevo,
                                    idAsistencia = CAST(@idAsistencia AS NVARCHAR(36)),
                                    idDetalleAsistencia = CAST(@idDetalle AS NVARCHAR(36)),
                                    razonCausaAnterior = @codigoCausaAnterior,
                                    asistioAnterior = @asistioAnterior,
                                    razonCausaNueva = CASE WHEN @modificaDetalle = 1 THEN N'EX' ELSE @codigoCausaAnterior END,
                                    asistioNuevo = CASE WHEN @modificaDetalle = 1 THEN CAST(0 AS BIT) ELSE @asistioAnterior END,
                                    respuestaDocente = @respuestaDefecto
                             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
                        );
                    END
                END
            END

            COMMIT TRANSACTION;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'SolicitudRevisionAsistencia',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
        END

    END TRY
    BEGIN CATCH
        -- REC3: solo se revierte si hay una transaccion viva (XACT_STATE <> 0); evita un segundo error en el CATCH.
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
GO
-- ---- texto previo (develop) de schema/stored-procedures/usp_consultar_solicitudes_revision_estudiante.sql
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
--
-- CULM-001 D.2 (CONTRACT §3.2, HU015/TD-060): un reclamo puede tener varios soportes. Las columnas de soporte siguen siendo las del PRIMER
-- soporte adjuntado y se agregan AL FINAL codigoCategoria, nombreCategoria (NULL si el reclamo es anterior a la categoria persistida) y
-- soportesJson: arreglo JSON [{idArchivo, nombreOriginal, tipoContenido, tamanioBytes}] ordenado por adjuncion ('[]' sin soportes).
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
        totalRegistros                = COUNT(*) OVER(),
        codigoCategoria               = cat.codigo,
        nombreCategoria               = cat.nombre,
        soportesJson                  = ISNULL((SELECT s.idArchivo AS idArchivo, s.nombreOriginal AS nombreOriginal, s.tipoContenido AS tipoContenido,
                                                              s.tamanioBytes AS tamanioBytes
                                                       FROM dbo.uv_soporte_reclamo s WHERE s.idSolicitud = sra.id ORDER BY s.orden FOR JSON PATH), N'[]')
    FROM dbo.SolicitudRevisionAsistencia sra
    INNER JOIN dbo.Estado est             ON est.id = sra.estado
    INNER JOIN dbo.Asistencia asi         ON asi.id = sra.asistencia
    INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = asi.estudianteGrupo
    INNER JOIN dbo.Estudiante estu        ON estu.id = eg.estudiante
    INNER JOIN dbo.Usuario usu            ON usu.id = estu.usuario
    INNER JOIN dbo.Sesion ses             ON ses.id = asi.sesion
    INNER JOIN dbo.Grupo gru              ON gru.id = ses.grupo
    INNER JOIN dbo.Asignatura asg         ON asg.id = gru.asignatura
    OUTER APPLY (SELECT TOP 1 a.id, a.nombreOriginal, a.tipoContenido, a.tamanioBytes, a.fechaRegistroUtc
                 FROM dbo.ArchivoSoporte a
                 WHERE a.solicitudRevisionAsistencia = sra.id AND a.estado = @estadoAdjunto
                 ORDER BY a.fechaAdjuncionUtc, a.id) arc
    LEFT  JOIN dbo.CategoriaJustificacion cat ON cat.id = sra.categoriaJustificacion
    WHERE estu.usuario = @idUsuarioDefecto
      AND (@estadoFiltro IS NULL OR est.codigo = @estadoFiltro)
    ORDER BY sra.fecha DESC, sra.nombre ASC, sra.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
GO
-- ---- texto previo (develop) de schema/stored-procedures/usp_consultar_detalle_solicitud_revision_docente.sql
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
--
-- CULM-001 D.2 (CONTRACT §3.2, HU015/TD-060): un reclamo puede tener varios soportes. Las columnas de soporte siguen siendo las del PRIMER
-- soporte adjuntado y se agregan AL FINAL codigoCategoria, nombreCategoria (NULL si el reclamo es anterior a la categoria persistida) y
-- soportesJson: arreglo JSON [{idArchivo, nombreOriginal, tipoContenido, tamanioBytes}] ordenado por adjuncion ('[]' sin soportes).
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
        fechaRegistroSoporteUtc       = arc.fechaRegistroUtc,
        codigoCategoria               = cat.codigo,
        nombreCategoria               = cat.nombre,
        soportesJson                  = ISNULL((SELECT s.idArchivo AS idArchivo, s.nombreOriginal AS nombreOriginal, s.tipoContenido AS tipoContenido,
                                                              s.tamanioBytes AS tamanioBytes
                                                       FROM dbo.uv_soporte_reclamo s WHERE s.idSolicitud = sra.id ORDER BY s.orden FOR JSON PATH), N'[]')
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
    OUTER APPLY (SELECT TOP 1 a.id, a.nombreOriginal, a.tipoContenido, a.tamanioBytes, a.fechaRegistroUtc
                 FROM dbo.ArchivoSoporte a
                 WHERE a.solicitudRevisionAsistencia = sra.id AND a.estado = @estadoAdjunto
                 ORDER BY a.fechaAdjuncionUtc, a.id) arc
    LEFT  JOIN dbo.CategoriaJustificacion cat ON cat.id = sra.categoriaJustificacion
    WHERE sra.id = @idSolicitudDefecto
      AND doc.usuario = @idUsuarioDefecto;
END;
GO
GO
-- ---- texto previo (develop) de schema/views/uv_asistencia_sesion_horas.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, DEC-012, DEC-024, [SUPUESTO-B-15], NB-9): una fila por cabecera Asistencia con las horas de la
-- sesion repartidas por toma y el estado consolidado de la sesion.
--   horasSesion = ufn_horas_sesion(inicio, fin); cada toma vale horasSesion / totalTomasSesion (0 si la sesion esta cancelada)
--   horasAsistidas (AN), horasFalta (asistio = 0 y SJC), horasExcusa (EX); horasSinRegistro = horasSesion - las tres
--   (se calcula por conteo de tomas para no acumular redondeos; sin tomas o cancelada = horasSesion).
--   codigoRazonCausaConsolidado: SJC si alguna toma es SJC; si no EX si alguna es EX; si no AN si alguna es AN; si no NULL.
--   esParcial = mezcla AN y SJC. Literales de RazonCausa de catalogo cerrado ([SUPUESTO-B-03]).
CREATE OR ALTER VIEW [dbo].[uv_asistencia_sesion_horas]
AS
SELECT  idAsistencia = a.id,
        idEstudianteGrupo = a.estudianteGrupo,
        idSesion = a.sesion,
        idGrupo = s.grupo,
        totalTomasSesion = n.totalTomas,
        tomasConRegistro = ISNULL(d.conRegistro, 0),
        horasSesion = h.horasSesion,
        horasAsistidas = CAST(IIF(x.reparte = 1, h.horasSesion * ISNULL(d.nAN, 0) / n.totalTomas, 0) AS DECIMAL(12,6)),
        horasFalta = CAST(IIF(x.reparte = 1, h.horasSesion * ISNULL(d.nFalta, 0) / n.totalTomas, 0) AS DECIMAL(12,6)),
        horasExcusa = CAST(IIF(x.reparte = 1, h.horasSesion * ISNULL(d.nEX, 0) / n.totalTomas, 0) AS DECIMAL(12,6)),
        horasSinRegistro = CAST(IIF(x.reparte = 1,
                                    h.horasSesion * (n.totalTomas - ISNULL(d.nAN, 0) - ISNULL(d.nFalta, 0) - ISNULL(d.nEX, 0)) / n.totalTomas,
                                    h.horasSesion) AS DECIMAL(12,6)),
        codigoRazonCausaConsolidado = CAST(CASE WHEN ISNULL(d.nSJC, 0) > 0 THEN N'SJC'
                                                WHEN ISNULL(d.nEX, 0) > 0 THEN N'EX'
                                                WHEN ISNULL(d.nAN, 0) > 0 THEN N'AN'
                                           END AS NVARCHAR(10)),
        esParcial = CAST(IIF(ISNULL(d.nAN, 0) > 0 AND ISNULL(d.nSJC, 0) > 0, 1, 0) AS BIT),
        tieneFaltaSinJustaCausa = CAST(IIF(ISNULL(d.nFalta, 0) > 0, 1, 0) AS BIT)
FROM    dbo.Asistencia a
INNER JOIN dbo.Sesion s
ON      s.id = a.sesion
CROSS APPLY (SELECT horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)) h
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t WHERE t.sesion = a.sesion) n
CROSS APPLY (SELECT reparte = CAST(IIF(n.totalTomas > 0 AND NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = a.sesion), 1, 0) AS BIT)) x
OUTER APPLY (
        SELECT  conRegistro = COUNT(1),
                nAN = SUM(IIF(rc.codigo = N'AN', 1, 0)),
                nFalta = SUM(IIF(rc.codigo = N'SJC' AND da.asistio = 0, 1, 0)),
                nSJC = SUM(IIF(rc.codigo = N'SJC', 1, 0)),
                nEX = SUM(IIF(rc.codigo = N'EX', 1, 0))
        FROM    dbo.DetalleAsistencia da
        INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
        WHERE   da.asistencia = a.id
) d;
GO
GO
-- ---- texto previo (develop) de schema/views/uv_toma_asistencia.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5): una fila por toma de asistencia con su modo, estado, ventana de la sesion y conteos.
--   horasSesion = ufn_horas_sesion(inicio, fin); totalTomasSesion = tomas de la sesion; horasToma = horasSesion /
--   totalTomasSesion (0 si la sesion esta cancelada). Conteos de la toma por RazonCausa (literales de catalogo cerrado,
--   [SUPUESTO-B-03]): totalPresentes AN, totalAusentes SJC, totalExcusas EX. tieneQrActivo = token sin fechaCierreUtc.
CREATE OR ALTER VIEW [dbo].[uv_toma_asistencia]
AS
SELECT  idToma = t.id,
        idSesion = t.sesion,
        idGrupo = s.grupo,
        numero = t.numero,
        idModo = m.id,
        codigoModo = m.codigo,
        nombreModo = m.nombre,
        usaCodigoQr = m.usaCodigoQr,
        marcaAusentesAlCerrar = m.marcaAusentesAlCerrar,
        idEstado = e.id,
        codigoEstado = e.codigo,
        nombreEstado = e.nombre,
        estaAbierta = e.estaAbierta,
        esImplicita = t.esImplicita,
        idDocenteApertura = t.docenteApertura,
        fechaAperturaUtc = t.fechaAperturaUtc,
        fechaCierreUtc = t.fechaCierreUtc,
        totalAusentesMarcados = t.totalAusentesMarcados,
        fechaHoraInicioSesion = s.fechaHoraInicio,
        fechaHoraFinSesion = s.fechaHoraFin,
        estaSesionCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT),
        horasSesion = h.horasSesion,
        totalTomasSesion = n.totalTomas,
        horasToma = CAST(IIF(sc.sesion IS NULL AND n.totalTomas > 0, h.horasSesion / n.totalTomas, 0) AS DECIMAL(12,6)),
        totalRegistros = ISNULL(d.totalRegistros, 0),
        totalPresentes = ISNULL(d.totalPresentes, 0),
        totalAusentes = ISNULL(d.totalAusentes, 0),
        totalExcusas = ISNULL(d.totalExcusas, 0),
        tieneQrActivo = CAST(IIF(EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma tk WHERE tk.toma = t.id AND tk.fechaCierreUtc IS NULL), 1, 0) AS BIT)
FROM    dbo.TomaAsistencia t
INNER JOIN dbo.Sesion s
ON      s.id = t.sesion
INNER JOIN dbo.ModoTomaAsistencia m
ON      m.id = t.modo
INNER JOIN dbo.EstadoTomaAsistencia e
ON      e.id = t.estado
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = t.sesion
CROSS APPLY (SELECT horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)) h
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t2 WHERE t2.sesion = t.sesion) n
OUTER APPLY (
        SELECT  totalRegistros = COUNT(1),
                totalPresentes = SUM(IIF(rc.codigo = N'AN', 1, 0)),
                totalAusentes = SUM(IIF(rc.codigo = N'SJC', 1, 0)),
                totalExcusas = SUM(IIF(rc.codigo = N'EX', 1, 0))
        FROM    dbo.DetalleAsistencia da
        INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
        WHERE   da.toma = t.id
) d;
GO
GO
-- ---- texto previo (develop) de schema/views/uv_detalle_asistencia_v2.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, DEC-011, DEC-012): detalle de asistencia por toma. Mismas columnas de uv_detalle_asistencia
-- (congelada, intacta) + la toma, la sesion, la matricula, el modo, las horas que vale la toma (0 si la sesion esta
-- cancelada), quien registro (registradoPorEstudiante) y cuando (fechaRegistroUtc).
CREATE OR ALTER VIEW [dbo].[uv_detalle_asistencia_v2]
AS
SELECT  id = da.id,
        codigo = da.codigo,
        idAsistencia = a.id,
        asistio = da.asistio,
        idRazonCausa = rc.id,
        nombreRazonCausa = rc.nombre,
        codigoRazonCausa = rc.codigo,
        fechaHoraInicio = da.fechaHoraInicio,
        fechaHoraFin = da.fechaHoraFin,
        idToma = t.id,
        numeroToma = t.numero,
        idSesion = a.sesion,
        idEstudianteGrupo = a.estudianteGrupo,
        idModoToma = m.id,
        codigoModoToma = m.codigo,
        horasToma = CAST(IIF(sc.sesion IS NULL AND n.totalTomas > 0, dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin) / n.totalTomas, 0) AS DECIMAL(12,6)),
        registradoPorEstudiante = da.registradoPorEstudiante,
        fechaRegistroUtc = da.fechaRegistroUtc,
        estaSesionCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT)
FROM    dbo.DetalleAsistencia da
INNER JOIN dbo.Asistencia a
ON      a.id = da.asistencia
INNER JOIN dbo.uv_razon_causa rc
ON      rc.id = da.razonCausa
INNER JOIN dbo.TomaAsistencia t
ON      t.id = da.toma
INNER JOIN dbo.ModoTomaAsistencia m
ON      m.id = t.modo
INNER JOIN dbo.Sesion s
ON      s.id = a.sesion
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = a.sesion
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t2 WHERE t2.sesion = t.sesion) n;
GO
GO
-- ---- texto previo (develop) de schema/views/uv_solicitud_revision_asistencia.sql
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
			justificacionRespuesta = sr.justificacionRespuesta,
			-- CULM-001 D.2 (TD-060, HU015): categoria persistida y total de soportes vinculados (columnas al final)
			idCategoriaJustificacion = cat.id,
			codigoCategoria = cat.codigo,
			nombreCategoria = cat.nombre,
			totalSoportes = (SELECT COUNT(*) FROM uv_soporte_reclamo sop WHERE sop.idSolicitud = sr.id)

FROM		SolicitudRevisionAsistencia sr
INNER JOIN	uv_asistencia asi
ON			sr.asistencia = asi.id
INNER JOIN	uv_estado est
ON			sr.estado = est.id
LEFT JOIN	CategoriaJustificacion cat
ON			sr.categoriaJustificacion = cat.id
GO
GO
-- ---- texto previo (develop) de schema/views/uv_resumen_asistencia_estudiante_grupo.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU066/HU067/HU069/HU070: una fila por matricula (EstudianteGrupo) con sus cifras de asistencia.
-- Denominador (D1): sesiones vencidas CON registro del grupo. Falta (D2): asistio = 0 con razon SJC; la excusa (EX) no cuenta.
-- CULM-001 B.2 (CONTRACT §2.6, §2.9, DEC-012, DEC-024, NB-2): inasistencia por HORAS conservando los nombres.
--   sesionesEjecutadas: sesiones vencidas, con registro (Asistencia o TomaAsistencia) y no canceladas (sin cambio de nombre).
--   asistencias / faltasSinJustaCausa / excusas: pasan a contar TOMAS (con una toma por sesion = sesiones, igual que antes).
--   tomasDictadas / horasDictadas: tomas y horas (ufn_horas_sesion) de esas mismas sesiones, sin mirar el estado de la toma.
--   horasAsistidas / horasFalta / horasExcusa: suma de uv_asistencia_sesion_horas en esas sesiones; horasSinRegistro =
--   horasDictadas - las tres (nunca negativo).
--   porcentajeInasistencia = ufn_calcular_porcentaje_inasistencia_horas(horasFalta, horasDictadas); codigoPermanencia sobre ese
--   porcentaje (ufn_clasificar_permanencia sin cambio). porcentajeInasistenciaSesiones = formula anterior por sesiones
--   (sesionesConFaltaSinJustaCausa / sesionesEjecutadas), solo trazabilidad. umbralAdvertencia / umbralPerdida: parametros.
--   sesionesAsistidas / sesionesConFaltaSinJustaCausa / sesionesConExcusa: sesiones por estado consolidado (consumidores
--   diferidos a D).
-- CULM-001 B2NM: sin idPrograma (1 fila por matricula); el resumen por programa es uv_resumen_asistencia_estudiante_programa_grupo.
CREATE OR ALTER VIEW [dbo].[uv_resumen_asistencia_estudiante_grupo]
AS
SELECT  idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        idGrupo = eg.idGrupo,
        idAsignatura = g.idAsignatura,
        idPeriodoAcademico = g.idPeriodoAcademico,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        sesionesEjecutadas = ISNULL(se.sesionesEjecutadas, 0),
        asistencias = ISNULL(de.asistencias, 0),
        faltasSinJustaCausa = ISNULL(de.faltas, 0),
        excusas = ISNULL(de.excusas, 0),
        porcentajeInasistencia = p.porcentaje,
        codigoPermanencia = dbo.ufn_clasificar_permanencia(p.porcentaje, eg.codigoEstadoEstudiante),
        tomasDictadas = ISNULL(se.tomasDictadas, 0),
        horasDictadas = hd.horasDictadas,
        horasAsistidas = hd.horasAsistidas,
        horasFalta = hd.horasFalta,
        horasExcusa = hd.horasExcusa,
        horasSinRegistro = hd.horasSinRegistro,
        porcentajeAsistenciaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasAsistidas, hd.horasDictadas),
        porcentajeExcusaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasExcusa, hd.horasDictadas),
        porcentajeSinRegistroHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasSinRegistro, hd.horasDictadas),
        porcentajeInasistenciaSesiones = CAST(IIF(ISNULL(se.sesionesEjecutadas, 0) = 0, 0,
                                                  100.0 * ISNULL(hs.sesionesConFalta, 0) / se.sesionesEjecutadas) AS DECIMAL(5,2)),
        umbralAdvertencia = u.umbralAdvertencia,
        umbralPerdida = u.umbralPerdida,
        sesionesAsistidas = ISNULL(hs.sesionesAsistidas, 0),
        sesionesConFaltaSinJustaCausa = ISNULL(hs.sesionesConFalta, 0),
        sesionesConExcusa = ISNULL(hs.sesionesConExcusa, 0)
FROM    dbo.uv_estudiante_grupo eg
INNER JOIN dbo.uv_grupo g
ON      g.id = eg.idGrupo
LEFT JOIN (
            SELECT  c.idGrupo,
                    sesionesEjecutadas = COUNT(*),
                    tomasDictadas = SUM(c.totalTomas),
                    horasDictadas = SUM(c.horasSesion)
            FROM    dbo.uv_cumplimiento_sesion_grupo c
            WHERE   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY c.idGrupo
          ) se
ON      se.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  v.idEstudianteGrupo,
                    asistencias = SUM(IIF(v.asistio = 1, 1, 0)),
                    faltas = SUM(IIF(v.asistio = 0 AND v.codigoRazonCausa = N'SJC', 1, 0)),
                    excusas = SUM(IIF(v.codigoRazonCausa = N'EX', 1, 0))
            FROM    dbo.uv_detalle_asistencia_v2 v
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = v.idSesion AND c.estaVencida = 1
            GROUP BY v.idEstudianteGrupo
          ) de
ON      de.idEstudianteGrupo = eg.id
LEFT JOIN (
            SELECT  h.idEstudianteGrupo,
                    horasAsistidas = SUM(h.horasAsistidas),
                    horasFalta = SUM(h.horasFalta),
                    horasExcusa = SUM(h.horasExcusa),
                    sesionesAsistidas = SUM(IIF(h.codigoRazonCausaConsolidado = N'AN', 1, 0)),
                    sesionesConFalta = SUM(IIF(h.tieneFaltaSinJustaCausa = 1, 1, 0)),
                    sesionesConExcusa = SUM(IIF(h.codigoRazonCausaConsolidado = N'EX', 1, 0))
            FROM    dbo.uv_asistencia_sesion_horas h
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = h.idSesion AND c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY h.idEstudianteGrupo
          ) hs
ON      hs.idEstudianteGrupo = eg.id
CROSS APPLY (
            SELECT  horasDictadas = CAST(ISNULL(se.horasDictadas, 0) AS DECIMAL(12,6)),
                    horasAsistidas = CAST(ISNULL(hs.horasAsistidas, 0) AS DECIMAL(12,6)),
                    horasFalta = CAST(ISNULL(hs.horasFalta, 0) AS DECIMAL(12,6)),
                    horasExcusa = CAST(ISNULL(hs.horasExcusa, 0) AS DECIMAL(12,6)),
                    horasSinRegistro = CAST(IIF(ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0) < 0, 0,
                                                ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0)) AS DECIMAL(12,6))
          ) hd
CROSS APPLY (SELECT porcentaje = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasFalta, hd.horasDictadas)) p
CROSS APPLY (
            SELECT  umbralAdvertencia = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA') AS NVARCHAR(20))), '') AS DECIMAL(5,2)),
                    umbralPerdida = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA') AS NVARCHAR(20))), '') AS DECIMAL(5,2))
          ) u;
GO
GO
IF OBJECT_ID(N'dbo.uv_asistencia_toma_estudiante', N'V') IS NOT NULL DROP VIEW dbo.uv_asistencia_toma_estudiante;
GO
IF OBJECT_ID(N'dbo.uv_asistencia_tramo', N'V') IS NOT NULL DROP VIEW dbo.uv_asistencia_tramo;
GO
IF OBJECT_ID(N'dbo.uv_toma_punto_control', N'V') IS NOT NULL DROP VIEW dbo.uv_toma_punto_control;
GO
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('TOM_012', 'REV_026', 'REV_027', 'REV_028', 'REV_029');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('TOM_012', 'REV_026', 'REV_027', 'REV_028', 'REV_029');
UPDATE dbo.CatalogoParametro
SET    valor = N'4', fechaModificacion = SYSUTCDATETIME()
WHERE  grupo = 'TOMA_ASISTENCIA' AND clave = 'MAXIMO_TOMAS_POR_SESION' AND valor = N'20';
UPDATE dbo.CatalogoParametro
SET    valorDefecto = N'4', fechaModificacion = SYSUTCDATETIME()
WHERE  grupo = 'TOMA_ASISTENCIA' AND clave = 'MAXIMO_TOMAS_POR_SESION' AND valorDefecto = N'20';
UPDATE dbo.ModoTomaAsistencia SET marcaAusentesAlCerrar = 0 WHERE id = '7C1E0B20-5E51-4C0A-9A01-000000000001' AND marcaAusentesAlCerrar = 1;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.SolicitudRevisionAsistencia') AND name = N'IX_SolicitudRevisionAsistencia_Asistencia_Toma')
    DROP INDEX IX_SolicitudRevisionAsistencia_Asistencia_Toma ON dbo.SolicitudRevisionAsistencia;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_SolicitudRevisionAsistencia_TomaAsistencia')
    ALTER TABLE dbo.SolicitudRevisionAsistencia DROP CONSTRAINT FK_SolicitudRevisionAsistencia_TomaAsistencia;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_SolicitudRevisionAsistencia_RazonCausaResolucion')
    ALTER TABLE dbo.SolicitudRevisionAsistencia DROP CONSTRAINT FK_SolicitudRevisionAsistencia_RazonCausaResolucion;
GO
IF COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'toma') IS NOT NULL
    ALTER TABLE dbo.SolicitudRevisionAsistencia DROP COLUMN toma;
IF COL_LENGTH(N'dbo.SolicitudRevisionAsistencia', N'razonCausaResolucion') IS NOT NULL
    ALTER TABLE dbo.SolicitudRevisionAsistencia DROP COLUMN razonCausaResolucion;
GO
PRINT 'MIGRACION 37 DOWN OK';
GO
