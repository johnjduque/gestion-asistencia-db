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
--   -> PC (reclamo por toma, solo con @idToma; v2 y v3 no lo informan): toma de la sesion (TOM_001), SJC del estudiante en
--      esa toma con cabecera y detalle bloqueados (REV_026) y sin otra solicitud no retirada de la toma (REV_027)
--   -> plazo de excusas (usp_internal_validar_plazo_justificacion, D.1: REV_020 / REV_025; por sesion, igual para sus tomas)
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
    @estadoResultado          BIT              OUTPUT,
    @idToma                   UNIQUEIDENTIFIER = NULL
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
    DECLARE @codigoRetirado           NVARCHAR(5)      = CAST(dbo.ufn_obtener_parametro('RECLAMO', 'ESTADO_RETIRADO') AS NVARCHAR(5));
    DECLARE @codigoSinJustaCausa      NVARCHAR(5)      = CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_SIN_JUSTA_CAUSA') AS NVARCHAR(5));
    DECLARE @numeroToma               INT;
    DECLARE @codigoRazonToma          NVARCHAR(5);
    DECLARE @solicitudTomaExistente   UNIQUEIDENTIFIER;
    DECLARE @textoNumeroToma          NVARCHAR(20);

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

        -- PASO 10b (PC, reclamo por toma): con @idToma la toma debe ser de la sesion (TOM_001), el estudiante debe tener SJC en
        -- ella (REV_026; cabecera y detalle bloqueados) y no debe existir otra solicitud no retirada de la misma toma (REV_027).
        IF @estadoResultado = 1 AND @esReintento = 0 AND @idToma IS NOT NULL
        BEGIN
            SELECT @numeroToma = t.numero FROM dbo.TomaAsistencia t WHERE t.id = @idToma AND t.sesion = @idSesionDefecto;
            IF @numeroToma IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'TOM_001', @p_param1 = @idToma,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @textoNumeroToma = CONVERT(NVARCHAR(20), @numeroToma);
                SELECT TOP 1 @idEstudianteGrupo = eg.id
                FROM dbo.Sesion s
                INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
                WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

                SELECT TOP 1 @idAsistencia = a.id, @codigoRazonToma = rc.codigo
                FROM dbo.Asistencia a WITH (UPDLOCK, HOLDLOCK)
                LEFT JOIN dbo.DetalleAsistencia d WITH (UPDLOCK, HOLDLOCK) ON d.asistencia = a.id AND d.toma = @idToma
                LEFT JOIN dbo.RazonCausa rc ON rc.id = d.razonCausa
                WHERE a.estudianteGrupo = @idEstudianteGrupo AND a.sesion = @idSesionDefecto;

                IF @codigoRazonToma IS NULL OR @codigoRazonToma <> @codigoSinJustaCausa
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'REV_026', @p_param1 = @textoNumeroToma, @p_param2 = @idSesionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
                ELSE
                BEGIN
                    SELECT TOP 1 @solicitudTomaExistente = sra.id
                    FROM dbo.SolicitudRevisionAsistencia sra WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.Estado e ON e.id = sra.estado
                    WHERE sra.asistencia = @idAsistencia AND sra.toma = @idToma AND e.codigo <> @codigoRetirado
                    ORDER BY sra.id;
                    IF @solicitudTomaExistente IS NOT NULL
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_027', @p_param1 = @textoNumeroToma, @p_param2 = @solicitudTomaExistente,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                        SET @estadoResultado = 0;
                    END
                END
            END
            IF @estadoResultado = 0
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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
                justificacionSolicitud, justificacionRespuesta, categoriaJustificacion, toma
            )
            VALUES (
                @nuevaSolicitudId,
                @nombreSolicitud,
                @idAsistencia,
                @fechaLocalRadicacion,
                @idEstadoPendiente,
                CASE WHEN @justificacionDefecto IS NOT NULL AND @justificacionDefecto <> '' THEN @justificacionDefecto ELSE 'Solicitud de revision de asistencia radicada por estudiante.' END,
                '',
                @idCategoria,
                @idToma
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
