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
-- ATA D4 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS A; reemplaza la regla PC de edicion hasta la toma siguiente): mientras la ventana de la
-- sesion este abierta se registra y corrige CUALQUIER toma, abierta o cerrada; la unica barrera temporal es la ventana (SES_007..010).
-- TOM_012 ya no se emite (el mensaje se conserva en el catalogo). Despues de la ventana, la correccion es por reclamo del estudiante.
-- @asistenciaJSON = [{"idEstudiante":"uuid","estado":"AN|SJC|EX"}] con las mismas
-- reglas del lote congelado: ATT_001 (no es arreglo o claves distintas de idEstudiante/estado), ATT_002 (vacio), GEN_002
-- (idEstudiante nulo o invalido), RC_001 (estado fuera de AN/SJC/EX), ATT_003 (duplicado), EST_004 (sin matricula A).
-- Todo se valida antes de escribir; el lote es atomico; la ventana se revalida al confirmar. Exito TOM_010.
-- Bloqueos: Sesion (ventana) -> TomaAsistencia -> EstudianteGrupo -> Asistencia -> DetalleAsistencia.
-- ============================================================================
-- SKILLS-BD lote 12 (2026-11-26): PASO n, IF con BEGIN/END y lecturas sin bloqueo por vistas uv_* (antes, las tablas).
-- Las lecturas con UPDLOCK/HOLDLOCK y las escrituras siguen en las tablas. Mismo resultado.
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
        -- PASO 1: Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validar parametros obligatorios (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar perfil del ejecutor (DOCENTE)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Toma existente (TOM_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idSesion = t.idSesion, @idGrupo = s.idGrupo
            FROM dbo.uv_toma_asistencia_registro t INNER JOIN dbo.uv_sesion_registro s ON s.id = t.idSesion
            WHERE t.id = @idTomaDefecto;

            IF @idSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_001', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        -- PASO 5: Titularidad del docente sobre la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idSesion, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 6: JSON valido (ATT_001)
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

        -- PASO 7: Estudiantes del lote (ATT_002)
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
        -- PASO 8: idEstudiante valido (GEN_002)
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
        -- PASO 9: Estado del catalogo cerrado (RC_001)
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
        -- PASO 10: Sin estudiantes repetidos (ATT_003)
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
        -- PASO 11: Matricula activa de cada estudiante en el grupo (EST_004)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstudianteInvalido = et.idEstudiante
            FROM @EstudiantesATrabajar et
            WHERE NOT EXISTS (
                SELECT 1 FROM dbo.uv_estudiante_grupo_registro eg
                INNER JOIN dbo.uv_estado_estudiante_grupo eeg ON eeg.id = eg.idEstado
                WHERE eg.idEstudiante = et.idEstudiante AND eg.idGrupo = @idGrupo AND eeg.codigo = @codigoActiva)
            ORDER BY et.secuencia;
            IF @idEstudianteInvalido IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'EST_004', @p_param1 = @idEstudianteInvalido, @p_param2 = @idSesion,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 12: Escritura atomica: ventana, bloqueo de la toma, sincronizacion por estudiante y ventana al confirmar (TOM_010)
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
            BEGIN
                SELECT @idSesion = t.sesion FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK) WHERE t.id = @idTomaDefecto;
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
            BEGIN
                EXEC dbo.usp_validar_sesion_ventana_registro_interno
                    @idSesion = @idSesion, @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT,
                    @toleranciaMinutos = @toleranciaMinutos, @margenMinutos = @margenMinutos;
            END

            IF @estadoResultado = 1
            BEGIN
                SET @p1 = CONVERT(NVARCHAR(36), @idTomaDefecto);
                SET @p2 = CONVERT(NVARCHAR(20), @totalEstudiantes);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_010', @p_param1 = @p1, @p_param2 = @p2,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- PASO 13: Confirmar o revertir la transaccion propia o el punto de guardado
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1 AND (@estadoResultado = 1 OR @huboEscritura = 0)
                BEGIN
                    COMMIT TRANSACTION;
                END
                ELSE IF XACT_STATE() <> 0
                BEGIN
                    ROLLBACK TRANSACTION;
                END
                SET @transaccionPropia = 0;
            END
            ELSE IF @savepointCreado = 1 AND XACT_STATE() = 1 AND @estadoResultado = 0 AND @huboEscritura = 1
            BEGIN
                ROLLBACK TRANSACTION sp_asistencias_toma;
            END
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
            ROLLBACK TRANSACTION sp_asistencias_toma;
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
