-- ============================================================================
-- MIGRACION DOWN 50: retira ATA D4 + D2 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS A y B)
--   1. Restaura el texto de develop (antes de la 50) de los SP usp_registrar_asistencias_toma (con TOM_012), usp_consultar_tomas_sesion (edicion
--      hasta la toma siguiente), usp_consultar_comparativa_facultades, usp_consultar_comparativa_programas_facultad, usp_consultar_kpis_decano,
--      usp_consultar_kpis_institucion y usp_consultar_consolidado_asistencia_grupos_paginado (denominador horasDictadas) y de las vistas
--      uv_resumen_asistencia_estudiante_programa_grupo, uv_resumen_asistencia_estudiante_grupo y uv_cumplimiento_sesion_grupo (sin
--      cuentaParaPeriodo, sesionesPeriodo ni horasPeriodo).
--   2. ASISTENCIA/MARGEN_RETARDO_MINUTOS vuelve a 30 por defecto; el valor vigente solo se restaura si seguia en 0 (un valor administrado distinto se respeta).
-- Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 50 DOWN: retira ATA D4 + D2';
GO
-- ---- schema/stored-procedures/usp_registrar_asistencias_toma.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_asistencias_toma (CULM-001 B.2, HU175; CONTRACT §2.8.2, DEC-013; PC puntos de control)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idToma, idSesion, idGrupo, totalRegistros
-- (NULL si estadoResultado = 0).
--
-- Lote del docente titular sobre UNA toma, siempre dentro de la ventana [inicio - TOLERANCIA, fin + MARGEN) (SES_007..010).
-- PC (puntos de control, reemplaza [SUPUESTO-B-08]): la toma abierta se edita; una toma cerrada solo se corrige mientras no
-- exista una toma posterior (TOM_012 en cuanto se abre la siguiente); la ultima, hasta el fin de la ventana. Despues, la
-- correccion es por reclamo del estudiante. @asistenciaJSON = [{"idEstudiante":"uuid","estado":"AN|SJC|EX"}] con las mismas
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

            -- PC (puntos de control): una toma cerrada solo se corrige hasta que se abre la siguiente (TOM_012). Bajo el bloqueo
            -- de la Sesion (UPDLOCK, HOLDLOCK hasta el fin de la transaccion) ninguna apertura concurrente cambia esta respuesta.
            IF @estadoResultado = 1
            BEGIN
                SELECT TOP 1 @p1 = CONVERT(NVARCHAR(20), t.numero), @p2 = CONVERT(NVARCHAR(20), t2.numero)
                FROM dbo.TomaAsistencia t
                INNER JOIN dbo.TomaAsistencia t2 ON t2.sesion = t.sesion AND t2.numero > t.numero
                WHERE t.id = @idTomaDefecto AND t.fechaCierreUtc IS NOT NULL
                ORDER BY t2.numero;
                IF @p2 IS NOT NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_012', @p_param1 = @p1, @p_param2 = @p2,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

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
-- ---- schema/stored-procedures/usp_consultar_tomas_sesion.sql (texto de develop antes de la 50)
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
-- PC (puntos de control): columnas al final (NULL en la fila sin tomas):
--   fechaPuntoControlUtc, ordenPuntoControl, minutosTramoAnterior, minutosTramoSiguiente (uv_toma_asistencia);
--   esEditable       = ventana abierta y la toma es la abierta o no tiene toma posterior (regla TOM_012);
--   editableHastaUtc = apertura de la toma siguiente o, para la ultima, el cierre de la ventana (fin + margen).
-- horasToma (1/n) queda OBSOLETO: se conserva por compatibilidad; las horas salen de usp_consultar_resumen_tomas_sesion.
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
        tieneQrActivo         = t.tieneQrActivo,
        fechaPuntoControlUtc  = t.fechaPuntoControlUtc,
        ordenPuntoControl     = t.ordenPuntoControl,
        minutosTramoAnterior  = t.minutosTramoAnterior,
        minutosTramoSiguiente = t.minutosTramoSiguiente,
        esEditable            = CAST(IIF(t.idToma IS NULL, NULL,
                                         IIF(se.ventanaAbierta = 1 AND (t.estaAbierta = 1 OR t.fechaAperturaSiguienteUtc IS NULL), 1, 0)) AS BIT),
        editableHastaUtc      = CAST(IIF(t.idToma IS NULL, NULL, COALESCE(CAST(t.fechaAperturaSiguienteUtc AS DATETIME2(7)), se.ventanaCierreUtc)) AS DATETIME2(7))
    FROM dbo.uv_sesion_estado se
    LEFT JOIN dbo.uv_toma_asistencia t ON t.idSesion = se.idSesion
    WHERE se.idSesion = @idSesionDefecto
    ORDER BY t.numero ASC;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_comparativa_facultades.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_comparativa_facultades (HU139). READ_QUERY_RESULTSET sin paginar. Solo lectura.
-- Una fila por facultad de la institucion (activas e inactivas, D4). Mismas definiciones que usp_consultar_kpis_institucion.
-- Orden: ausentismo descendente (NULL al final), luego nombre.
-- CULM-001 D.8 (CONTRACT D 9.2, DEC-012/DEC-024, HU139): porcentajeAusentismo por HORAS = ROUND(100 x SUM(horasFalta) / SUM(horasDictadas), 2)
-- (NULL si no hay horas dictadas) sobre las matriculas activas con vinculo en la facultad (cada matricula una sola vez);
-- sesionesEjecutadas y faltasSinJustaCausa siguen en sesiones. Columnas nuevas al final: horasDictadas y horasFalta (horas, 2 decimales).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_comparativa_facultades]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_institucion_administrador_interno)
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idInstitucion = @idInstitucion OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_institucion_interno)
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 3: Consulta y retorno de resultados
    WITH persona AS (
        SELECT  p.idFacultad, r.idEstudiante,
                peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
        FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idInstitucion = @idInstitucion AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = @codigoInscrita
        GROUP BY p.idFacultad, r.idEstudiante
    ),
    conteo AS (
        SELECT  idFacultad,
                total = COUNT(*),
                regulares = SUM(IIF(peor = 1, 1, 0)),
                riesgo = SUM(IIF(peor = 2, 1, 0)),
                perdida = SUM(IIF(peor = 3, 1, 0))
        FROM    persona
        GROUP BY idFacultad
    ),
    asistencia AS (
        SELECT  p.idFacultad,
                sesiones = SUM(r.sesionesEjecutadas),
                faltas = SUM(r.sesionesConFaltaSinJustaCausa),
                -- CULM-001 D.8: horas dictadas y de falta sin justa causa de las mismas matriculas
                horasDictadas = CAST(SUM(r.horasDictadas) AS DECIMAL(19,6)),
                horasFalta = CAST(SUM(r.horasFalta) AS DECIMAL(19,6))
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN (SELECT DISTINCT p.idFacultad, idEstudianteGrupo = egp.id
                    FROM dbo.uv_estudiante_grupo_programa egp
                    INNER JOIN dbo.uv_programa p ON p.id = egp.idPrograma
                    WHERE p.idInstitucion = @idInstitucion) p ON p.idEstudianteGrupo = r.idEstudianteGrupo
        WHERE   r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = @codigoInscrita
        GROUP BY p.idFacultad
    ),
    programas AS (
        SELECT idFacultad, total = COUNT(*) FROM dbo.uv_programa WHERE idInstitucion = @idInstitucion GROUP BY idFacultad
    ),
    resultado AS (
        SELECT
            idFacultad = f.id,
            nombreFacultad = f.nombreFacultad,
            estaActivaFacultad = CAST(f.estaActivaFacultad AS BIT),
            totalProgramas = ISNULL(pr.total, 0),
            totalEstudiantes = ISNULL(c.total, 0),
            estudiantesRiesgo = ISNULL(c.riesgo, 0),
            estudiantesPerdida = ISNULL(c.perdida, 0),
            tasaRetencion = CAST(IIF(ISNULL(c.total, 0) = 0, NULL, 100.0 * (c.regulares + c.riesgo) / c.total) AS DECIMAL(5,2)),
            sesionesEjecutadas = ISNULL(a.sesiones, 0),
            faltasSinJustaCausa = ISNULL(a.faltas, 0),
            porcentajeAusentismo = CAST(IIF(ISNULL(a.horasDictadas, 0) = 0, NULL, ROUND(100.0 * a.horasFalta / a.horasDictadas, 2)) AS DECIMAL(5,2)),
            horasDictadas = CAST(ISNULL(a.horasDictadas, 0) AS DECIMAL(12,2)),
            horasFalta = CAST(ISNULL(a.horasFalta, 0) AS DECIMAL(12,2))
        FROM dbo.uv_facultad f
        LEFT JOIN programas pr ON pr.idFacultad = f.id
        LEFT JOIN conteo c ON c.idFacultad = f.id
        LEFT JOIN asistencia a ON a.idFacultad = f.id
        WHERE f.idInstitucion = @idInstitucion
    )
    -- PASO 4: Consulta y retorno de resultados
    SELECT idFacultad, nombreFacultad, estaActivaFacultad, totalProgramas, totalEstudiantes, estudiantesRiesgo, estudiantesPerdida,
           tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, horasDictadas, horasFalta
    FROM resultado
    ORDER BY IIF(porcentajeAusentismo IS NULL, 1, 0) ASC, porcentajeAusentismo DESC, nombreFacultad ASC, idFacultad ASC;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_comparativa_programas_facultad.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_comparativa_programas_facultad (HU103). READ_QUERY_RESULTSET sin paginar (D6). Solo lectura.
-- Una fila por programa de la facultad (activos e inactivos, D5). Mismas definiciones que usp_consultar_kpis_decano.
-- Orden: ausentismo descendente (NULL al final), luego nombre.
-- CULM-001 D.8 (CONTRACT D 9.2, DEC-012/DEC-024, HU103): porcentajeAusentismo por HORAS = ROUND(100 x SUM(horasFalta) / SUM(horasDictadas), 2)
-- (NULL si no hay horas dictadas) por programa sobre uv_resumen_asistencia_estudiante_programa_grupo; sesionesEjecutadas y
-- faltasSinJustaCausa siguen en sesiones. Columnas nuevas al final: horasDictadas y horasFalta (horas, 2 decimales).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_comparativa_programas_facultad]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idFacultad UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_facultad_decano_interno)
    EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idFacultad = @idFacultad OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_facultad_interno)
    EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @idFacultad, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 3: Consulta y retorno de resultados
    WITH persona AS (
        SELECT  r.idPrograma, r.idEstudiante,
                peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
        FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = @codigoInscrita
        GROUP BY r.idPrograma, r.idEstudiante
    ),
    conteo AS (
        SELECT  idPrograma,
                total = COUNT(*),
                regulares = SUM(IIF(peor = 1, 1, 0)),
                riesgo = SUM(IIF(peor = 2, 1, 0)),
                perdida = SUM(IIF(peor = 3, 1, 0))
        FROM    persona
        GROUP BY idPrograma
    ),
    asistencia AS (
        SELECT  r.idPrograma,
                sesiones = SUM(r.sesionesEjecutadas),
                faltas = SUM(r.sesionesConFaltaSinJustaCausa),
                -- CULM-001 D.8: horas dictadas y de falta sin justa causa de las mismas matriculas
                horasDictadas = CAST(SUM(r.horasDictadas) AS DECIMAL(19,6)),
                horasFalta = CAST(SUM(r.horasFalta) AS DECIMAL(19,6))
        FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = @codigoInscrita
        GROUP BY r.idPrograma
    ),
    resultado AS (
        SELECT
            idPrograma = p.id,
            nombrePrograma = p.nombrePrograma,
            estaActivoPrograma = CAST(p.estaActivoPrograma AS BIT),
            totalEstudiantes = ISNULL(c.total, 0),
            estudiantesRiesgo = ISNULL(c.riesgo, 0),
            estudiantesPerdida = ISNULL(c.perdida, 0),
            tasaRetencion = CAST(IIF(ISNULL(c.total, 0) = 0, NULL, 100.0 * (c.regulares + c.riesgo) / c.total) AS DECIMAL(5,2)),
            sesionesEjecutadas = ISNULL(a.sesiones, 0),
            faltasSinJustaCausa = ISNULL(a.faltas, 0),
            porcentajeAusentismo = CAST(IIF(ISNULL(a.horasDictadas, 0) = 0, NULL, ROUND(100.0 * a.horasFalta / a.horasDictadas, 2)) AS DECIMAL(5,2)),
            horasDictadas = CAST(ISNULL(a.horasDictadas, 0) AS DECIMAL(12,2)),
            horasFalta = CAST(ISNULL(a.horasFalta, 0) AS DECIMAL(12,2))
        FROM dbo.uv_programa p
        LEFT JOIN conteo c ON c.idPrograma = p.id
        LEFT JOIN asistencia a ON a.idPrograma = p.id
        WHERE p.idFacultad = @idFacultad
    )
    -- PASO 4: Consulta y retorno de resultados
    SELECT idPrograma, nombrePrograma, estaActivoPrograma, totalEstudiantes, estudiantesRiesgo, estudiantesPerdida,
           tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo, horasDictadas, horasFalta
    FROM resultado
    ORDER BY IIF(porcentajeAusentismo IS NULL, 1, 0) ASC, porcentajeAusentismo DESC, nombrePrograma ASC, idPrograma ASC;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_kpis_decano.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_kpis_decano (HU102, HU106, HU144). READ_QUERY_RESULTSET de una fila. Solo lectura.
-- Estudiante = persona con la peor clasificacion de sus matriculas activas de la facultad (D3).
-- Retencion = (regular + riesgo) / total (D2). Ausentismo = faltas / sesiones ejecutadas, ponderado por matricula activa (D1).
-- sesionesEjecutadas = suma por matricula activa (denominador del ausentismo). Aforo = matriculados activos / cupo de los grupos habilitados (D4).
-- Lo que no puede calcularse es NULL; nunca un valor por defecto.
-- CIERRE-W3I: columnas nuevas AL FINAL: totalCoordinadores (coordinadores activos de la facultad) y totalDocentes (docentes con vinculo
-- activo en algun programa de la facultad, contados una sola vez aunque esten en varios programas).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_kpis_decano]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idFacultad UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_facultad_decano_interno)
    EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idFacultad = @idFacultad OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_facultad_interno)
    EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @idFacultad, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @programas INT = (SELECT COUNT(*) FROM dbo.uv_programa p WHERE p.idFacultad = @idFacultad);
    DECLARE @total INT = 0, @regulares INT = 0, @riesgo INT = 0, @perdida INT = 0;
    DECLARE @sesiones INT = 0, @faltas INT = 0;
    DECLARE @tomasDictadas INT = 0, @horasDictadas DECIMAL(12,6) = 0, @horasFalta DECIMAL(12,6) = 0;
    DECLARE @grupos INT = 0, @cupo INT = 0, @matriculados INT = 0;
    DECLARE @coordinadores INT = (SELECT COUNT(DISTINCT c.id) FROM dbo.uv_coordinador c WHERE c.idFacultad = @idFacultad AND c.estaActivoCoordinador = 1);
    DECLARE @docentes INT = (SELECT COUNT(DISTINCT dp.idDocente) FROM dbo.uv_docente_programa dp WHERE dp.idFacultad = @idFacultad AND dp.estaActivoDocentePrograma = 1);

    -- PASO 3: Calcular los indicadores del periodo
    IF @idPeriodo IS NOT NULL
    BEGIN
        SELECT  @total = COUNT(*),
                @regulares = ISNULL(SUM(IIF(x.peor = 1, 1, 0)), 0),
                @riesgo = ISNULL(SUM(IIF(x.peor = 2, 1, 0)), 0),
                @perdida = ISNULL(SUM(IIF(x.peor = 3, 1, 0)), 0)
        FROM (
                SELECT  r.idEstudiante,
                        peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
                FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
                WHERE   EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa egp INNER JOIN dbo.uv_programa p ON p.id = egp.idPrograma WHERE egp.id = r.idEstudianteGrupo AND p.idFacultad = @idFacultad) AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
                GROUP BY r.idEstudiante
             ) x;

        SELECT  @sesiones = ISNULL(SUM(r.sesionesEjecutadas), 0),
                @faltas = ISNULL(SUM(r.faltasSinJustaCausa), 0),
                @tomasDictadas = ISNULL(SUM(r.tomasDictadas), 0),
                @horasDictadas = ISNULL(SUM(r.horasDictadas), 0),
                @horasFalta = ISNULL(SUM(r.horasFalta), 0)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        WHERE   EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa egp INNER JOIN dbo.uv_programa p ON p.id = egp.idPrograma WHERE egp.id = r.idEstudianteGrupo AND p.idFacultad = @idFacultad) AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A';

        SELECT  @grupos = COUNT(*),
                @cupo = ISNULL(SUM(g.capacidadMaximaPermitida), 0),
                @matriculados = ISNULL(SUM(g.estudiantesActivos), 0)
        FROM    dbo.uv_grupo g
        WHERE   EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
                        WHERE gp.idGrupo = g.id AND p.idFacultad = @idFacultad) AND g.idPeriodoAcademico = @idPeriodo AND g.grupoEstaHablitado = 1;
    END

    -- CULM-001 B.2 (CONTRACT §2.9, DEC-012/DEC-024): ausentismo por horas = 100 * Sigma horasFalta / Sigma horasDictadas de las
    -- matriculas A (antes faltas / sesiones); con sesiones de igual duracion y una toma, identico.
    DECLARE @ausentismo DECIMAL(5,2) = CAST(IIF(@horasDictadas = 0, NULL, 100.0 * @horasFalta / @horasDictadas) AS DECIMAL(5,2));

    -- PASO 4: Consulta y retorno de resultados
    SELECT
        idFacultad = f.id,
        nombreFacultad = f.nombreFacultad,
        idPeriodoAcademico = pa.id,
        nombrePeriodoAcademico = pa.nombre,
        totalProgramas = @programas,
        totalEstudiantes = @total,
        estudiantesRegulares = @regulares,
        estudiantesRiesgo = @riesgo,
        estudiantesPerdida = @perdida,
        tasaRetencion = CAST(IIF(@total = 0, NULL, 100.0 * (@regulares + @riesgo) / @total) AS DECIMAL(5,2)),
        sesionesEjecutadas = @sesiones,
        faltasSinJustaCausa = @faltas,
        porcentajeAusentismo = @ausentismo,
        porcentajeAsistencia = CAST(IIF(@ausentismo IS NULL, NULL, 100.0 - @ausentismo) AS DECIMAL(5,2)),
        gruposActivos = @grupos,
        cupoTotal = @cupo,
        matriculadosActivos = @matriculados,
        tasaAforo = CAST(IIF(@cupo = 0, NULL, 100.0 * @matriculados / @cupo) AS DECIMAL(7,2)),
        umbralAdvertencia = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA')), '') AS DECIMAL(5,2)),
        umbralPerdida = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA')), '') AS DECIMAL(5,2)),
        tomasDictadas = @tomasDictadas,
        horasDictadas = @horasDictadas,
        horasFalta = @horasFalta,
        totalCoordinadores = @coordinadores,
        totalDocentes = @docentes
    FROM dbo.uv_facultad f
    LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = @idPeriodo
    WHERE f.id = @idFacultad;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_kpis_institucion.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_kpis_institucion (HU133, HU135, HU136, HU138). READ_QUERY_RESULTSET de una fila. Solo lectura.
-- Mismas definiciones que las olas 1 y 2: persona = peor clasificacion de sus matriculas activas; ausentismo ponderado por
-- matricula activa (sesionesEjecutadas = suma por matricula); retencion = (regular + riesgo) / total.
-- Cumplimiento (HU138) = sesiones vencidas con registro / sesiones vencidas. Censo (HU135/HU136): con matricula o grupo activo
-- en el periodo y registrados (usuario activo; docentes = titulares de al menos un grupo de la institucion, sin depender del periodo).
-- Lo que no puede calcularse es NULL; nunca un valor por defecto.
-- CIERRE-W3I: columnas nuevas AL FINAL: facultadesActivas, totalDecanos y decanosActivos (decanos de las facultades de la institucion; un decano sin
-- facultad no tiene institucion resoluble y no se cuenta, igual que el directorio de estudiantes).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_kpis_institucion]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_institucion_administrador_interno)
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idInstitucion = @idInstitucion OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_institucion_interno)
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @facultades INT = (SELECT COUNT(*) FROM dbo.uv_facultad f WHERE f.idInstitucion = @idInstitucion);
    DECLARE @programas INT = (SELECT COUNT(*) FROM dbo.uv_programa p WHERE p.idInstitucion = @idInstitucion);
    DECLARE @estudiantesRegistrados INT = (
        SELECT COUNT(DISTINCT ep.idEstudiante)
        FROM dbo.uv_estudiante_programa ep
        INNER JOIN dbo.uv_programa p ON p.id = ep.idPrograma
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = ep.idEstudiante
        WHERE p.idInstitucion = @idInstitucion AND ei.estaActivoUsuario = 1);
    DECLARE @docentesRegistrados INT = (
        SELECT COUNT(DISTINCT g.idDocente)
        FROM dbo.uv_grupo g
        INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
        INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        WHERE p.idInstitucion = @idInstitucion AND di.estaActivoUsuario = 1);

    DECLARE @totalDecanos INT = (SELECT COUNT(DISTINCT d.id) FROM dbo.uv_decano d WHERE d.idInstitucion = @idInstitucion);
    DECLARE @facultadesActivas INT = (SELECT COUNT(*) FROM dbo.uv_facultad f WHERE f.idInstitucion = @idInstitucion AND f.estaActivaFacultad = 1);
    DECLARE @decanosActivos INT = (SELECT COUNT(DISTINCT d.id) FROM dbo.uv_decano d WHERE d.idInstitucion = @idInstitucion AND d.estaActivoDecano = 1);

    DECLARE @total INT = 0, @regulares INT = 0, @riesgo INT = 0, @perdida INT = 0;
    DECLARE @sesiones INT = 0, @faltas INT = 0;
    DECLARE @tomasDictadas INT = 0, @horasDictadas DECIMAL(12,6) = 0, @horasFalta DECIMAL(12,6) = 0;
    DECLARE @vencidas INT = 0, @conRegistro INT = 0;
    DECLARE @docentesActivos INT = 0;

    -- PASO 3: Calcular los indicadores del periodo
    IF @idPeriodo IS NOT NULL
    BEGIN
        SELECT  @total = COUNT(*),
                @regulares = ISNULL(SUM(IIF(x.peor = 1, 1, 0)), 0),
                @riesgo = ISNULL(SUM(IIF(x.peor = 2, 1, 0)), 0),
                @perdida = ISNULL(SUM(IIF(x.peor = 3, 1, 0)), 0)
        FROM (
                SELECT  r.idEstudiante,
                        peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
                FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
                WHERE   EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa egp INNER JOIN dbo.uv_programa p ON p.id = egp.idPrograma WHERE egp.id = r.idEstudianteGrupo AND p.idInstitucion = @idInstitucion) AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
                GROUP BY r.idEstudiante
             ) x;

        SELECT  @sesiones = ISNULL(SUM(r.sesionesEjecutadas), 0),
                @faltas = ISNULL(SUM(r.faltasSinJustaCausa), 0),
                @tomasDictadas = ISNULL(SUM(r.tomasDictadas), 0),
                @horasDictadas = ISNULL(SUM(r.horasDictadas), 0),
                @horasFalta = ISNULL(SUM(r.horasFalta), 0)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        WHERE   EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo_programa egp INNER JOIN dbo.uv_programa p ON p.id = egp.idPrograma WHERE egp.id = r.idEstudianteGrupo AND p.idInstitucion = @idInstitucion) AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A';

        SELECT  @vencidas = ISNULL(SUM(IIF(c.estaVencida = 1, 1, 0)), 0),
                @conRegistro = ISNULL(SUM(IIF(c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1, 1, 0)), 0)
        FROM    dbo.uv_cumplimiento_sesion_grupo c
        WHERE   EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma WHERE gp.idGrupo = c.idGrupo AND p.idInstitucion = @idInstitucion) AND c.idPeriodoAcademico = @idPeriodo;

        SELECT  @docentesActivos = COUNT(DISTINCT g.idDocente)
        FROM    dbo.uv_grupo g
        INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
        INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        WHERE   p.idInstitucion = @idInstitucion AND gp.idPeriodoAcademico = @idPeriodo AND gp.grupoEstaHablitado = 1 AND di.estaActivoUsuario = 1;
    END

    -- CULM-001 B.2 (CONTRACT §2.9, DEC-012/DEC-024): ausentismo por horas = 100 * Sigma horasFalta / Sigma horasDictadas de las
    -- matriculas A (antes faltas / sesiones); con sesiones de igual duracion y una toma, identico.
    DECLARE @ausentismo DECIMAL(5,2) = CAST(IIF(@horasDictadas = 0, NULL, 100.0 * @horasFalta / @horasDictadas) AS DECIMAL(5,2));

    -- PASO 4: Consulta y retorno de resultados
    SELECT
        idInstitucion = i.id,
        nombreInstitucion = i.nombre,
        idPeriodoAcademico = pa.id,
        nombrePeriodoAcademico = pa.nombre,
        totalFacultades = @facultades,
        totalProgramas = @programas,
        totalEstudiantes = @total,
        estudiantesRegulares = @regulares,
        estudiantesRiesgo = @riesgo,
        estudiantesPerdida = @perdida,
        tasaRetencion = CAST(IIF(@total = 0, NULL, 100.0 * (@regulares + @riesgo) / @total) AS DECIMAL(5,2)),
        sesionesEjecutadas = @sesiones,
        faltasSinJustaCausa = @faltas,
        porcentajeAusentismo = @ausentismo,
        porcentajeAsistencia = CAST(IIF(@ausentismo IS NULL, NULL, 100.0 - @ausentismo) AS DECIMAL(5,2)),
        sesionesVencidas = @vencidas,
        sesionesConRegistro = @conRegistro,
        porcentajeCumplimiento = CAST(IIF(@vencidas = 0, NULL, 100.0 * @conRegistro / @vencidas) AS DECIMAL(5,2)),
        estudiantesConMatriculaActiva = @total,
        estudiantesRegistrados = @estudiantesRegistrados,
        docentesConGrupoActivo = @docentesActivos,
        docentesRegistrados = @docentesRegistrados,
        umbralAdvertencia = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA')), '') AS DECIMAL(5,2)),
        umbralPerdida = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA')), '') AS DECIMAL(5,2)),
        tomasDictadas = @tomasDictadas,
        horasDictadas = @horasDictadas,
        horasFalta = @horasFalta,
        totalDecanos = @totalDecanos,
        decanosActivos = @decanosActivos,
        facultadesActivas = @facultadesActivas
    FROM dbo.uv_institucion i
    LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = @idPeriodo
    WHERE i.id = @idInstitucion;
END;
GO
GO
-- ---- schema/stored-procedures/usp_consultar_consolidado_asistencia_grupos_paginado.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_consolidado_asistencia_grupos_paginado (HU061 consolidado por cohorte, materia y docente)
--
-- Una fila por grupo con el consolidado de asistencia de sus estudiantes. Decision de John (2026-11-04): la cohorte es
-- el PERIODO ACADEMICO del grupo (el modelo no tiene cohorte de ingreso). Filtros opcionales: periodo, programa,
-- asignatura y docente.
-- CULM-001 D.8 (CONTRACT D 9.2, DEC-012/DEC-024/DEC-044 (9), R-1, HU061): los porcentajes pasan a HORAS sobre D = horasDictadas x activos del
-- programa en el grupo: asistencia, inasistencia y excusa = ROUND(100 x horas / D, 2); sinRegistro = MAX(0, 100 - las tres). Si la suma de los
-- tres redondeos supera 100, el exceso se resta del mayor (en empate: asistencia, inasistencia, excusa); asi los cuatro suman 100.00 y ninguno
-- es negativo. Con D = 0 los cuatro son 0. Columnas nuevas AL FINAL (tras totalRegistros): horasDictadas, porcentajeExcusa, porcentajeSinRegistro.
-- Metricas: estudiantes activos (A), sesiones ejecutadas (vencidas con registro de asistencia), asistencias, faltas sin
-- justa causa y excusas de los estudiantes activos; % de asistencia y de inasistencia sobre (sesiones x activos);
-- estudiantes activos en RIESGO y estudiantes en PERDIDA (incluye cancelados por inasistencia).
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001).
-- Ambito: perfiles COORDINADOR, DECANO o ADMINISTRADOR; los grupos salen de uv_auth_grupo (fail-closed): el
-- coordinador ve su programa, el decano su facultad y el administrador su institucion.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_consolidado_asistencia_grupos_paginado]
(
    @idUsuarioEjecutor   UNIQUEIDENTIFIER,
    @idCorrelacion       UNIQUEIDENTIFIER,
    @numeroPagina        INT,
    @tamanoPagina        INT,
    @idPeriodoAcademico  UNIQUEIDENTIFIER = NULL,
    @idPrograma          UNIQUEIDENTIFIER = NULL,
    @idAsignatura        UNIQUEIDENTIFIER = NULL,
    @idDocente           UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @codigoInscrita          NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    -- Grupos del ambito materializados una vez: evita que el optimizador combine uv_auth_grupo con el resumen de
    -- asistencia en un solo plan con una reserva de memoria desproporcionada (Msg 701 en instancias pequenas).
    DECLARE @grupos TABLE (
        id UNIQUEIDENTIFIER, codigo INT, nombre NVARCHAR(100), idPeriodoAcademico UNIQUEIDENTIFIER,
        idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idDocente UNIQUEIDENTIFIER, idPrograma UNIQUEIDENTIFIER, PRIMARY KEY (id, idPrograma));
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: Correlacion, ejecutor, perfil y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'COORDINADOR,DECANO,ADMINISTRADOR',
            @numeroPagina = @numeroPagina,
            @tamanoPagina = @tamanoPagina,
            @idUsuarioValidado = @idUsuario OUTPUT,
            @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 2: Grupos del ambito del ejecutor con los filtros
        INSERT INTO @grupos (id, codigo, nombre, idPeriodoAcademico, idAsignatura, nombreAsignatura, idDocente, idPrograma)
            SELECT  g.id, g.codigo, g.nombre, g.idPeriodoAcademico, g.idAsignatura, g.nombreAsignatura, g.idDocente,
                    gp.idPrograma
            FROM    dbo.uv_auth_grupo g
            INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
            WHERE   (@idPeriodoAcademico IS NULL OR g.idPeriodoAcademico = @idPeriodoAcademico)
               AND  (@idPrograma IS NULL OR gp.idPrograma = @idPrograma)
               AND  (@idAsignatura IS NULL OR g.idAsignatura = @idAsignatura)
               AND  (@idDocente IS NULL OR g.idDocente = @idDocente);

        -- PASO 3: Consolidado de asistencia y retorno de resultados
        WITH consolidado AS (
            -- ISNULL/COALESCE permitidos solo sobre agregaciones (REC4 #3): un grupo sin estudiantes suma 0.
            SELECT  r.idGrupo, r.idPrograma,
                    activos = SUM(IIF(r.codigoEstadoEstudiante = @codigoInscrita, 1, 0)),
                    sesionesEjecutadas = MAX(r.sesionesEjecutadas),
                    -- Conteos en unidades de sesion (estado consolidado, B.2); los porcentajes salen de las horas (D.8)
                    asistencias = SUM(IIF(r.codigoEstadoEstudiante = @codigoInscrita, r.sesionesAsistidas, 0)),
                    faltas = SUM(IIF(r.codigoEstadoEstudiante = @codigoInscrita, r.sesionesConFaltaSinJustaCausa, 0)),
                    excusas = SUM(IIF(r.codigoEstadoEstudiante = @codigoInscrita, r.sesionesConExcusa, 0)),
                    horasDictadas = CAST(MAX(r.horasDictadas) AS DECIMAL(19,6)),
                    horasAsistidas = CAST(SUM(IIF(r.codigoEstadoEstudiante = @codigoInscrita, r.horasAsistidas, 0)) AS DECIMAL(19,6)),
                    horasFalta = CAST(SUM(IIF(r.codigoEstadoEstudiante = @codigoInscrita, r.horasFalta, 0)) AS DECIMAL(19,6)),
                    horasExcusa = CAST(SUM(IIF(r.codigoEstadoEstudiante = @codigoInscrita, r.horasExcusa, 0)) AS DECIMAL(19,6)),
                    riesgo = SUM(IIF(r.codigoEstadoEstudiante = @codigoInscrita AND r.codigoPermanencia = N'RIESGO', 1, 0)),
                    perdida = SUM(IIF(r.codigoPermanencia = N'PERDIDA', 1, 0))
            -- CULM-001 B2NM (R9): grano (grupo, programa del ambito); cuenta solo a los estudiantes con vinculo en ese programa.
            FROM    dbo.uv_resumen_asistencia_estudiante_programa_grupo r
            INNER JOIN @grupos gg ON gg.id = r.idGrupo AND gg.idPrograma = r.idPrograma
            GROUP BY r.idGrupo, r.idPrograma
        )
        SELECT
            idGrupo                 = g.id,
            codigoGrupo             = g.codigo,
            nombreGrupo             = g.nombre,
            idPeriodoAcademico      = g.idPeriodoAcademico,
            nombrePeriodoAcademico  = pa.nombre,
            idPrograma              = g.idPrograma,
            nombrePrograma          = p.nombrePrograma,
            idAsignatura            = g.idAsignatura,
            nombreAsignatura        = g.nombreAsignatura,
            idDocente               = g.idDocente,
            nombreDocente           = d.nombreCompleto,
            estudiantesActivos      = ISNULL(c.activos, 0),
            sesionesEjecutadas      = ISNULL(c.sesionesEjecutadas, 0),
            asistencias             = ISNULL(c.asistencias, 0),
            faltasSinJustaCausa     = ISNULL(c.faltas, 0),
            excusas                 = ISNULL(c.excusas, 0),
            porcentajeAsistencia    = CAST(q.asistenciaFinal AS DECIMAL(5,2)),
            porcentajeInasistencia  = CAST(q.inasistenciaFinal AS DECIMAL(5,2)),
            estudiantesRiesgo       = ISNULL(c.riesgo, 0),
            estudiantesPerdida      = ISNULL(c.perdida, 0),
            totalRegistros          = COUNT(*) OVER(),
            horasDictadas           = CAST(ISNULL(c.horasDictadas, 0) AS DECIMAL(12,2)),
            porcentajeExcusa        = CAST(q.excusaFinal AS DECIMAL(5,2)),
            porcentajeSinRegistro   = CAST(q.sinRegistro AS DECIMAL(5,2)),
            -- CIERRE-W3I: clasificacion del grupo (REGULAR/RIESGO/PERDIDA) con la unica regla de permanencia y los umbrales del catalogo
            codigoPermanencia       = dbo.ufn_clasificar_permanencia(CAST(q.inasistenciaFinal AS DECIMAL(5,2)), NULL)
        FROM @grupos g
        LEFT JOIN consolidado c ON c.idGrupo = g.id AND c.idPrograma = g.idPrograma
        -- D = horasDictadas x activos; p* = porcentajes redondeados; exceso = lo que la suma de los tres supera 100 (R-1)
        CROSS APPLY (SELECT denominador = ISNULL(c.horasDictadas, 0) * ISNULL(c.activos, 0)) den
        CROSS APPLY (SELECT pAsistencia = CAST(IIF(den.denominador = 0, 0, ROUND(100.0 * c.horasAsistidas / den.denominador, 2)) AS DECIMAL(9,2)),
                            pInasistencia = CAST(IIF(den.denominador = 0, 0, ROUND(100.0 * c.horasFalta / den.denominador, 2)) AS DECIMAL(9,2)),
                            pExcusa = CAST(IIF(den.denominador = 0, 0, ROUND(100.0 * c.horasExcusa / den.denominador, 2)) AS DECIMAL(9,2))) pr
        CROSS APPLY (SELECT exceso = CAST(IIF(pr.pAsistencia + pr.pInasistencia + pr.pExcusa > 100, pr.pAsistencia + pr.pInasistencia + pr.pExcusa - 100, 0) AS DECIMAL(9,2)),
                            mayor = CASE WHEN pr.pAsistencia >= pr.pInasistencia AND pr.pAsistencia >= pr.pExcusa THEN 1
                                         WHEN pr.pInasistencia >= pr.pExcusa THEN 2 ELSE 3 END) x
        CROSS APPLY (SELECT asistenciaFinal = pr.pAsistencia - IIF(x.mayor = 1, x.exceso, 0),
                            inasistenciaFinal = pr.pInasistencia - IIF(x.mayor = 2, x.exceso, 0),
                            excusaFinal = pr.pExcusa - IIF(x.mayor = 3, x.exceso, 0),
                            sinRegistro = CAST(IIF(den.denominador = 0 OR pr.pAsistencia + pr.pInasistencia + pr.pExcusa >= 100, 0,
                                                   100 - (pr.pAsistencia + pr.pInasistencia + pr.pExcusa)) AS DECIMAL(9,2))) q
        LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = g.idPeriodoAcademico
        LEFT JOIN dbo.uv_programa p ON p.id = g.idPrograma
        LEFT JOIN dbo.uv_docente_identidad d ON d.id = g.idDocente
        ORDER BY pa.fechaInicio DESC, g.nombreAsignatura ASC, g.codigo ASC, g.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO
GO
-- ---- schema/views/uv_resumen_asistencia_estudiante_programa_grupo.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (R9): resumen por (matricula, programa) para los KPI por programa; las columnas son las de
-- uv_resumen_asistencia_estudiante_grupo (B.2) mas idPrograma, solo para estudiantes con vinculo en ese programa.
CREATE OR ALTER VIEW [dbo].[uv_resumen_asistencia_estudiante_programa_grupo]
AS
SELECT  r.idEstudianteGrupo,
        r.idEstudiante,
        r.idGrupo,
        r.idAsignatura,
        idPrograma = egp.idPrograma,
        r.idPeriodoAcademico,
        r.codigoEstadoEstudiante,
        r.sesionesEjecutadas,
        r.asistencias,
        r.faltasSinJustaCausa,
        r.excusas,
        r.porcentajeInasistencia,
        r.codigoPermanencia,
        r.tomasDictadas,
        r.horasDictadas,
        r.horasAsistidas,
        r.horasFalta,
        r.horasExcusa,
        r.horasSinRegistro,
        r.porcentajeAsistenciaHoras,
        r.porcentajeExcusaHoras,
        r.porcentajeSinRegistroHoras,
        r.porcentajeInasistenciaSesiones,
        r.umbralAdvertencia,
        r.umbralPerdida,
        r.sesionesAsistidas,
        r.sesionesConFaltaSinJustaCausa,
        r.sesionesConExcusa
FROM    uv_resumen_asistencia_estudiante_grupo r
INNER JOIN uv_estudiante_grupo_programa egp ON egp.id = r.idEstudianteGrupo
GO
GO
-- ---- schema/views/uv_resumen_asistencia_estudiante_grupo.sql (texto de develop antes de la 50)
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
-- PC BD-4 (rendimiento, sin cambio de resultado): las horas se agrupan tambien por idGrupo (grupo de la sesion = grupo de la
-- matricula) y se unen por (idEstudianteGrupo, idGrupo); asi un filtro por grupo llega a uv_asistencia_sesion_horas antes de
-- calcular los tramos de todas las cabeceras.
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
            SELECT  h.idEstudianteGrupo, h.idGrupo,
                    horasAsistidas = SUM(h.horasAsistidas),
                    horasFalta = SUM(h.horasFalta),
                    horasExcusa = SUM(h.horasExcusa),
                    sesionesAsistidas = SUM(IIF(h.codigoRazonCausaConsolidado = N'AN', 1, 0)),
                    sesionesConFalta = SUM(IIF(h.tieneFaltaSinJustaCausa = 1, 1, 0)),
                    sesionesConExcusa = SUM(IIF(h.codigoRazonCausaConsolidado = N'EX', 1, 0))
            FROM    dbo.uv_asistencia_sesion_horas h
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = h.idSesion AND c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY h.idEstudianteGrupo, h.idGrupo
          ) hs
ON      hs.idEstudianteGrupo = eg.id AND hs.idGrupo = eg.idGrupo
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
-- ---- schema/views/uv_cumplimiento_sesion_grupo.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU065: una fila por sesion con su estado de cumplimiento (D4, D7). Consume uv_sesion_v2 (procedencia temporal) y
-- uv_grupo_programa; no altera las vistas congeladas.
-- CULM-001 B.1 (CONTRACT §2.6): una sesion cancelada (dbo.SesionCancelacion, por el docente o por festivo) sale de la
-- vista y con ello de sesionesProgramadas, vencidas, ejecutadas, cumplimiento, progreso de calendario y tendencia.
-- Columnas sin cambio.
-- CULM-001 B.2 (CONTRACT §2.6, [SUPUESTO-B-06]): tieneRegistroAsistencia = existe Asistencia O existe TomaAsistencia (una toma
-- QR abierta y cerrada sin lecturas cuenta como sesion ejecutada); columnas nuevas totalTomas y horasSesion.
-- CULM-001 B2NM: sin idPrograma (1 fila por sesion); el programa se resuelve con EXISTS uv_grupo_programa.
CREATE OR ALTER VIEW [dbo].[uv_cumplimiento_sesion_grupo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idPeriodoAcademico = g.idPeriodoAcademico,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaVencida = CAST(IIF(s.procedenciaTemporal IS NOT NULL AND s.fechaHoraFin <= SYSUTCDATETIME(), 1, 0) AS BIT),
        procedenciaIndeterminada = CAST(IIF(s.procedenciaTemporal IS NULL, 1, 0) AS BIT),
        tieneRegistroAsistencia = CAST(IIF(EXISTS (SELECT 1 FROM dbo.uv_asistencia a WHERE a.idSesion = s.id)
                                           OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id), 1, 0) AS BIT),
        totalTomas = (SELECT COUNT(1) FROM dbo.TomaAsistencia t WHERE t.sesion = s.id),
        horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_grupo g
ON      g.id = s.idGrupo
WHERE   NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id)
GO
GO
UPDATE [dbo].[CatalogoParametro]
SET    [valor] = IIF([valor] = N'0', N'30', [valor]),
       [valorDefecto] = N'30',
       [fechaModificacion] = SYSUTCDATETIME()
WHERE  [grupo] = 'ASISTENCIA' AND [clave] = 'MARGEN_RETARDO_MINUTOS';
GO
PRINT 'MIGRACION 50 DOWN OK';
GO
