-- ============================================================================
-- MIGRACION DOWN 30: CULM-001 / DEC-065 (2), (3) y (4) - retira la solicitud de sesion extraordinaria con aval del coordinador
--   1. DROP de los SP usp_aprobar_solicitud_sesion, usp_rechazar_solicitud_sesion, usp_consultar_solicitudes_sesion_coordinador_paginado,
--      usp_consultar_destinatarios_solicitud_sesion y usp_validar_coordinador_sesion_interno, y de la vista uv_solicitud_sesion.
--   2. Restaura el texto previo (migracion 29 / D.1 / B.1) de usp_validar_sesion_ventana_registro_interno, usp_crear_sesion_interno, usp_crear_grupo
--      (vuelve a aceptar al DOCENTE), usp_consultar_destinatarios_sesion_manual, usp_consultar_sesiones_grupo_paginado, uv_sesion_manual,
--      uv_sesion_estado y uv_sesion_estudiante_reclamo.
--   3. Marca FALLIDA_DEFINITIVA las notificaciones pendientes de los tres tipos retirados (nunca DELETE, DEC-010) y borra sus plantillas y marcadores
--      creados por el sistema.
--   4. Borra los mensajes SES_022..SES_027 y el parametro SESION/PREFIJO_MOTIVO_SOLICITUD_RECHAZADA (solo si conserva su valor por defecto).
--   5. DROP de uv_estado_solicitud_sesion y de las tablas SesionSolicitud y EstadoSolicitudSesion.
-- Las solicitudes PENDIENTES se pierden: sus sesiones vuelven a ser sesiones manuales ordinarias (visibles para el estudiante). Las cancelaciones
-- registradas al rechazar (SesionCancelacion, tipo manual) se conservan. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 30 DOWN: retira la solicitud de sesion extraordinaria con aval del coordinador';
GO
IF OBJECT_ID(N'dbo.usp_aprobar_solicitud_sesion', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_aprobar_solicitud_sesion;
GO
IF OBJECT_ID(N'dbo.usp_rechazar_solicitud_sesion', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_rechazar_solicitud_sesion;
GO
IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_sesion_coordinador_paginado', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_solicitudes_sesion_coordinador_paginado;
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_solicitud_sesion', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_destinatarios_solicitud_sesion;
GO
IF OBJECT_ID(N'dbo.usp_validar_coordinador_sesion_interno', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_validar_coordinador_sesion_interno;
GO
IF OBJECT_ID(N'dbo.uv_solicitud_sesion', N'V') IS NOT NULL DROP VIEW dbo.uv_solicitud_sesion;
GO
-- ---- texto previo de schema/views/uv_sesion_manual.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: sesiones creadas manualmente por el docente (fuera de la precarga por horario). Los dos endpoints de creacion
-- (usp_crear_sesion v1 -> procedenciaTemporal NULL; usp_crear_sesion_v2 -> UTC_V2) son manuales; la precarga y el generador marcan
-- UTC_GENERADOR y la clasificacion administrativa de historicos UTC_OWNER: esas NO son manuales. Limitaciones conocidas: NULL tambien
-- es una fila historica anterior a UTC-D06 (se trata como manual; una sesion con asistencia no se puede cancelar de todos modos) y una
-- sesion generada que el docente edita por la via v2 pasa a UTC_V2.
CREATE OR ALTER VIEW [dbo].[uv_sesion_manual]
AS
SELECT  idSesion = s.id,
        idGrupo = s.grupo,
        numero = s.numero,
        nombre = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin
FROM    dbo.Sesion s
WHERE   s.procedenciaTemporal IS NULL OR s.procedenciaTemporal = N'UTC_V2';
GO
GO
-- ---- texto previo de schema/views/uv_sesion_estado.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.5): una fila por sesion (sobre uv_sesion_v2, que no se modifica) con su estado de
-- cancelacion (dbo.SesionCancelacion, LEFT) y la ventana de registro con tolerancia:
--   ventanaAperturaUtc = inicio - ASISTENCIA/TOLERANCIA_MINUTOS (NULL si la procedencia temporal es INDETERMINADA)
--   ventanaCierreUtc   = fin + ASISTENCIA/MARGEN_RETARDO_MINUTOS
--   ventanaAbierta     = no cancelada, procedencia confirmada y apertura <= SYSUTCDATETIME() < cierre
-- Los dos parametros se leen una sola vez (CROSS APPLY); un parametro ausente o negativo vale 0 (regla estricta).
-- horasSesion = minutos de la sesion / 60 (0 si fin <= inicio).
-- CULM-001 B.2 (CONTRACT §2.5): totalTomas (tomas de la sesion), tieneTomaAbierta e idTomaAbierta (la toma sin fechaCierreUtc).
CREATE OR ALTER VIEW [dbo].[uv_sesion_estado]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        numero = s.numero,
        nombre = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        procedenciaTemporal = s.procedenciaTemporal,
        estaCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT),
        idTipoCancelacion = tc.id,
        codigoTipoCancelacion = tc.codigo,
        nombreTipoCancelacion = tc.nombre,
        esCancelacionAutomatica = tc.esAutomatica,
        motivoCancelacion = sc.motivo,
        idDiaFestivo = sc.diaFestivo,
        nombreDiaFestivo = df.nombre,
        fechaCancelacionUtc = sc.fechaCancelacionUtc,
        idUsuarioCancelacion = sc.usuarioEjecutor,
        ventanaAperturaUtc = IIF(s.procedenciaTemporal IS NULL, NULL, DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio)),
        ventanaCierreUtc = DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin),
        ventanaAbierta = CAST(IIF(sc.sesion IS NULL
                                  AND s.procedenciaTemporal IS NOT NULL
                                  AND DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio) <= SYSUTCDATETIME()
                                  AND SYSUTCDATETIME() < DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin), 1, 0) AS BIT),
        horasSesion = CAST(IIF(s.fechaHoraFin > s.fechaHoraInicio,
                               CAST(DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin) AS DECIMAL(12,6)) / 60, 0) AS DECIMAL(12,6)),
        totalTomas = tm.totalTomas,
        tieneTomaAbierta = CAST(IIF(tm.idTomaAbierta IS NULL, 0, 1) AS BIT),
        idTomaAbierta = tm.idTomaAbierta
FROM    dbo.uv_sesion_v2 s
CROSS APPLY (
        SELECT  toleranciaMinutos = IIF(t.valor IS NULL OR t.valor < 0, 0, t.valor),
                margenMinutos = IIF(m.valor IS NULL OR m.valor < 0, 0, m.valor)
        FROM    (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS')) t
        CROSS JOIN (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS')) m
) p
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = s.id
LEFT JOIN dbo.uv_tipo_cancelacion_sesion tc
ON      tc.id = sc.tipoCancelacion
LEFT JOIN dbo.DiaFestivo df
ON      df.id = sc.diaFestivo
OUTER APPLY (
        SELECT  totalTomas = COUNT(1),
                idTomaAbierta = MAX(IIF(t.fechaCierreUtc IS NULL, CAST(t.id AS NVARCHAR(36)), NULL))
        FROM    dbo.TomaAsistencia t
        WHERE   t.sesion = s.id
) tm0
CROSS APPLY (SELECT totalTomas = ISNULL(tm0.totalTomas, 0), idTomaAbierta = CAST(tm0.idTomaAbierta AS UNIQUEIDENTIFIER)) tm;
GO
GO
-- ---- texto previo de schema/views/uv_sesion_estudiante_reclamo.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.1 (CONTRACT §2.2, DEC-044 (2); HU026B): una fila por (sesion, matricula del estudiante) con la fecha limite
-- para justificar. Sobre uv_sesion_v2 + uv_sesion_estado (B.1) + uv_estudiante_grupo; uv_sesion (congelada) no se toca.
--   fechaLimiteJustificacionUtc = ufn_calcular_fecha_limite_justificacion(fechaHoraFin)  (limite exclusivo; NULL si falta
--                                 ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER)
--   plazoJustificacionVigente   = 1 solo si la sesion NO esta cancelada y SYSUTCDATETIME() < limite
-- idAsignatura, codigo, numeroSemana, codigoGrupo, nombreGrupo y codigoEstadoEstudiante completan las columnas que hoy
-- entrega la consulta de sesiones de la materia y permiten al SP filtrar la matricula inscrita.
CREATE OR ALTER VIEW [dbo].[uv_sesion_estudiante_reclamo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        idAsignatura = g.idAsignatura,
        numero = s.numero,
        nombre = s.nombre,
        codigo = s.codigo,
        numeroSemana = s.numeroSemana,
        codigoGrupo = s.codigoGrupo,
        nombreGrupo = s.nombreGrupo,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaCancelada = se.estaCancelada,
        fechaLimiteJustificacionUtc = lim.fechaLimiteUtc,
        plazoJustificacionVigente = CAST(IIF(se.estaCancelada = 0 AND lim.fechaLimiteUtc IS NOT NULL
                                             AND SYSUTCDATETIME() < lim.fechaLimiteUtc, 1, 0) AS BIT)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_sesion_estado se
ON      se.idSesion = s.id
INNER JOIN dbo.uv_estudiante_grupo eg
ON      eg.idGrupo = s.idGrupo
INNER JOIN dbo.uv_grupo g
ON      g.id = s.idGrupo
CROSS APPLY (SELECT fechaLimiteUtc = dbo.ufn_calcular_fecha_limite_justificacion(s.fechaHoraFin)) lim;
GO
GO
-- ---- texto previo de schema/stored-procedures/usp_validar_sesion_ventana_registro_interno.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SES-01: ventana de registro ordinario de asistencia (cierre estricto, sin tolerancia).
--   * Solo se registra cuando fechaHoraInicio <= SYSUTCDATETIME() < fechaHoraFin. El reloj autoritativo es el
--     del motor (UTC); nunca el del cliente ni el del backend.
--   * Solo una procedencia confirmada (UTC_V2, UTC_GENERADOR, UTC_OWNER) prueba que los DATETIME2 son instantes
--     UTC. NULL (INDETERMINADA) no permite escribir: no se supone zona horaria alguna.
--   * Lee la fila de dbo.Sesion con UPDLOCK + HOLDLOCK: invocado dentro de la transaccion del llamador, el
--     bloqueo se mantiene hasta su COMMIT/ROLLBACK, de modo que el horario no cambia entre esta validacion y la
--     escritura, y los lotes concurrentes de la misma sesion se serializan y evaluan el reloj despues de
--     obtener el bloqueo (una solicitud iniciada antes del cierre que llega despues del cierre se rechaza).
--   * Codigos: SES_007 (sesion no iniciada), SES_008 (sesion cerrada), SES_009 (horario indeterminado).
--   * No escribe. El llamador decide la reversion y el resultset canonico.
-- CULM-001 B.1 (CONTRACT §2.7.1):
--   * @toleranciaMinutos / @margenMinutos (opcionales): ventana [inicio - tolerancia, fin + margen). NULL o negativos = 0,
--     es decir, la regla estricta de SES-01; los llamadores de 5 parametros (lote congelado, autonomo) no cambian.
--     Los valores los lee el LLAMADOR (ASISTENCIA/TOLERANCIA_MINUTOS y ASISTENCIA/MARGEN_RETARDO_MINUTOS).
--   * PASO 2.5 (todos los llamadores): una sesion con dbo.SesionCancelacion se rechaza con SES_010. Se lee despues del
--     UPDLOCK + HOLDLOCK sobre dbo.Sesion, el mismo bloqueo que toma usp_cancelar_sesion: registro y cancelacion se
--     serializan.
-- CULM-001 B.2 (CONTRACT §2.8.3, NB-4, alternativa aprobada de antemano): @bloqueoCompartido = 1 lee la sesion con HOLDLOCK
--   (bloqueo compartido) en lugar de UPDLOCK, HOLDLOCK. Solo lo usa usp_registrar_asistencia_por_token: los registros QR de un
--   grupo no se serializan entre si y la cancelacion (U/X) sigue serializada contra ellos; el registro no actualiza Sesion,
--   asi que no hay conversion de bloqueo. Por defecto 0: todos los demas llamadores conservan el bloqueo exclusivo.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_sesion_ventana_registro_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @toleranciaMinutos       INT = NULL,
    @margenMinutos           INT = NULL,
    @bloqueoCompartido       BIT = 0
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @existe              BIT = 0;
    DECLARE @fechaHoraInicio     DATETIME2;
    DECLARE @fechaHoraFin        DATETIME2;
    DECLARE @procedenciaTemporal NVARCHAR(24);
    DECLARE @instanteActualUtc   DATETIME2;
    DECLARE @toleranciaAplicada  INT = IIF(@toleranciaMinutos IS NULL OR @toleranciaMinutos < 0, 0, @toleranciaMinutos);
    DECLARE @margenAplicado      INT = IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos);
    DECLARE @aperturaUtc         DATETIME2;
    DECLARE @cierreUtc           DATETIME2;
    DECLARE @detalleVentana      NVARCHAR(200) = IIF(@toleranciaMinutos IS NULL AND @margenMinutos IS NULL,
                                                     dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
                                                     CONCAT(' Tolerancia: ', @toleranciaAplicada, ' min; margen: ', @margenAplicado, ' min.'));

    -- Inicialización de respuesta desde parámetros del catálogo
    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Lectura bloqueada del horario y su procedencia (misma fila, una sola sentencia)
        IF @estadoResultado = 1
        BEGIN
            IF @bloqueoCompartido = 1
                SELECT TOP 1
                    @existe = 1,
                    @fechaHoraInicio = s.fechaHoraInicio,
                    @fechaHoraFin = s.fechaHoraFin,
                    @procedenciaTemporal = s.procedenciaTemporal
                FROM dbo.Sesion s WITH (HOLDLOCK)
                WHERE s.id = @idSesionDefecto;
            ELSE
                SELECT TOP 1
                    @existe = 1,
                    @fechaHoraInicio = s.fechaHoraInicio,
                    @fechaHoraFin = s.fechaHoraFin,
                    @procedenciaTemporal = s.procedenciaTemporal
                FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
                WHERE s.id = @idSesionDefecto;

            IF @existe = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_001',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2.5 (CULM-001 B.1): sesion cancelada => SES_010 (lectura despues del bloqueo de la fila de dbo.Sesion)
        IF @estadoResultado = 1
           AND EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_010',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Procedencia temporal confirmada (NULL o desconocida = INDETERMINADA)
        IF @estadoResultado = 1
           AND (@procedenciaTemporal IS NULL OR @procedenciaTemporal NOT IN (N'UTC_V2', N'UTC_GENERADOR', N'UTC_OWNER'))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_009',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Ventana [inicio - tolerancia, fin + margen) contra el reloj UTC del motor, leído después de obtener
        --         el bloqueo. Sin tolerancia ni margen es la ventana estricta [inicio, fin) de SES-01.
        IF @estadoResultado = 1
        BEGIN
            SET @instanteActualUtc = SYSUTCDATETIME();
            SET @aperturaUtc = DATEADD(MINUTE, -@toleranciaAplicada, @fechaHoraInicio);
            SET @cierreUtc = DATEADD(MINUTE, @margenAplicado, @fechaHoraFin);

            IF @instanteActualUtc < @aperturaUtc
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_007',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, @detalleVentana, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @instanteActualUtc >= @cierreUtc
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_008',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, @detalleVentana, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
GO
-- ---- texto previo de schema/stored-procedures/usp_crear_sesion_interno.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: nucleo unico de creacion de sesion compartido por
--   * usp_crear_sesion    (v1, firma congelada DB-GP-001C) -> @procedenciaTemporal = NULL
--   * usp_crear_sesion_v2 (v2, instantes UTC confirmados)   -> @procedenciaTemporal = 'UTC_V2'
-- Las horas y la marca se escriben en el MISMO INSERT. Este SP no es publico: el rol runtime
-- tiene DENY EXECUTE directo y solo se alcanza por encadenamiento de propiedad desde los wrappers.
-- UTC_GENERADOR y UTC_OWNER NO se aceptan por esta via (generador y clasificacion propios).
-- CULM-001 A.2-10 (F-DOC-017): dentro de la transaccion y antes del INSERT, una sesion que se cruce con otra del grupo o
-- de otro grupo del mismo docente se rechaza con SES_017 (usp_validar_solape_sesion_interno); el rechazo no escribe.
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_sesion_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @procedenciaTemporal     NVARCHAR(24),
    @idCorrelacionResultado  UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idNuevoSesion   UNIQUEIDENTIFIER = NEWID();
    DECLARE @numeroSiguiente INT = 1;
    DECLARE @codigoSesion    NVARCHAR(50);

    -- Ownership transaccional (propia o savepoint bajo transacción externa)
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET @idCorrelacionResultado = @idCorrelacionDefecto;

    BEGIN TRY
        -- PASOS 0-1.6: procedencia, correlacion y seguridad antes de consultar el grupo.
        EXEC dbo.usp_validar_sesion_operacion_interno
            @idCorrelacion = @idCorrelacion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @procedenciaTemporal = @procedenciaTemporal,
            @fechaHoraInicio = @fechaHoraInicio,
            @fechaHoraFin = @fechaHoraFin,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @faseValidacion = 0;

        -- PASO 2: Validación de existencia del grupo académico
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.1: Titularidad del docente ejecutor sobre el grupo.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idGrupoDefecto,
                @tipoEntidadPadre = 'GRUPO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.5: conservar la prioridad contractual de entidad antes de fechas.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_operacion_interno
                @idCorrelacion = @idCorrelacion,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @procedenciaTemporal = @procedenciaTemporal,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @faseValidacion = 2;
        END

        -- PASO 3: Cálculo transaccional del correlativo de sesión e inserción
        -- (ownership transaccional: propia o savepoint bajo transacción externa)
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_crear_sesion;
                SET @savepointCreado = 1;
            END

            -- PASO 2.8 (CULM-001 A.2-10): solape con sesiones del grupo o del docente, bajo bloqueo
            EXEC dbo.usp_validar_solape_sesion_interno
                @idGrupo = @idGrupoDefecto,
                @idSesionExcluir = NULL,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @numeroSiguiente = COALESCE(MAX(numero), 0) + 1
            FROM [dbo].[Sesion] WITH (UPDLOCK, HOLDLOCK)
            WHERE grupo = @idGrupoDefecto;

            SET @codigoSesion = CASE
                WHEN @numeroSiguiente < 100 THEN CONCAT('SES-', RIGHT('0' + CAST(@numeroSiguiente AS VARCHAR(10)), 2))
                ELSE CONCAT('SES-', CAST(@numeroSiguiente AS VARCHAR(10)))
            END;

            -- Horas y procedencia en la MISMA sentencia (UTC-D06).
            INSERT INTO dbo.Sesion (
                id, nombre, numero, codigo, numeroSemana, grupo,
                fechaHoraInicio, fechaHoraFin, procedenciaTemporal
            )
            VALUES (
                @idNuevoSesion,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Sesión #', @numeroSiguiente) END,
                @numeroSiguiente,
                @codigoSesion,
                @numeroSiguiente,
                @idGrupoDefecto,
                @fechaHoraInicio,
                @fechaHoraFin,
                @procedenciaTemporal
            );
        END

        -- Cierre de la transaccion propia (el rechazo por solape no escribe)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Sesion', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones y reversión respetando ownership transaccional
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_crear_sesion;
        END

        -- Transacción externa condenada (XACT_STATE = -1) que no nos pertenece: propagar al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
GO
-- ---- texto previo de schema/stored-procedures/usp_crear_grupo.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idAsignatura            UNIQUEIDENTIFIER,
    @idPeriodoAcademico      UNIQUEIDENTIFIER,
    @codigo                  INT,
    @nombre                  NVARCHAR(50),
    @idDocente               UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPeriodoAcademicoDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPeriodoAcademico, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto             NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idPeriodoResolved         UNIQUEIDENTIFIER = @idPeriodoAcademicoDefecto;
    DECLARE @capacidadMaximaDefecto    INT;
    DECLARE @idDocenteEjecutor         UNIQUEIDENTIFIER;
    DECLARE @ejecutorEsCoordinador     BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
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
                @codigoPerfilRequerido = 'COORDINADOR,DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.6 (F3): el COORDINADOR crea y asigna cualquier docente; el DOCENTE solo crea grupos a su propio nombre
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.uv_coordinador_identidad ci WHERE ci.idUsuario = @idUsuarioEjecutorDefecto)
            BEGIN
                SET @ejecutorEsCoordinador = 1;
            END

            SELECT @idDocenteEjecutor = di.id
            FROM dbo.uv_docente_identidad di
            WHERE di.idUsuario = @idUsuarioEjecutorDefecto;

            IF @ejecutorEsCoordinador = 0 AND (@idDocenteEjecutor IS NULL OR @idDocenteEjecutor <> @idDocenteDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2: Validar asignatura en uv_asignatura
        IF @estadoResultado = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[uv_asignatura] WHERE id = @idAsignaturaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'Asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2B (F3): el DOCENTE solo abre grupos de asignaturas de programas con los que tiene vinculo activo
        IF @estadoResultado = 1 AND @ejecutorEsCoordinador = 0
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.uv_asignatura_plan_estudio v
                INNER JOIN dbo.uv_docente_programa dp ON dp.idPrograma = v.idPrograma
                WHERE v.idAsignatura = @idAsignaturaDefecto
                  AND v.estaActivoVinculo = 1   -- CULM-001 B2NM: algun programa de la asignatura (tabla puente)
                  AND dp.idDocente = @idDocenteEjecutor
                  AND dp.estaActivoDocentePrograma = 1
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Resolver período académico si viene nulo/guid defecto
        IF @estadoResultado = 1
        BEGIN
            IF @idPeriodoResolved IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_periodo_academico] WHERE id = @idPeriodoResolved)
            BEGIN
                SELECT TOP 1 @idPeriodoResolved = id 
                FROM [dbo].[uv_periodo_academico] 
                ORDER BY anio DESC;
            END

            IF @idPeriodoResolved IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_periodo_academico] WHERE id = @idPeriodoResolved)
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

        -- PASO 4: Validar docente mediante procedimiento interno estandarizado
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_docente_exista_por_id_interno
                @idDocente = @idDocenteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4B (HU093/D12): el titular no puede tener su vinculo con el programa inactivado
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_docente_vinculo_activo_programa_interno
                @idDocente = @idDocenteDefecto,
                @idAsignatura = @idAsignaturaDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Validar unicidad de código de grupo en el período consultando uv_grupo
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (
                SELECT 1 FROM [dbo].[uv_grupo]
                WHERE idAsignatura = @idAsignaturaDefecto AND idPeriodoAcademico = @idPeriodoResolved AND codigo = @codigo
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_006',
                    @p_param1 = 'Grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 6: Resolver capacidad máxima por defecto desde el catálogo de parámetros (GRUPO/CAPACIDAD_MAXIMA_DEFECTO)
        IF @estadoResultado = 1
        BEGIN
            SET @capacidadMaximaDefecto = dbo.ufn_obtener_parametro_int(NULL, 'GRUPO', 'CAPACIDAD_MAXIMA_DEFECTO');

            IF @capacidadMaximaDefecto IS NULL OR @capacidadMaximaDefecto <= 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ERR_CAPACIDAD_GRUPO_INVALIDA',
                    @p_param1 = @capacidadMaximaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: Inserción directa de Grupo con capacidad máxima proveniente del catálogo
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.Grupo (
                id, asignatura, periodoAcademico, codigo, nombre,
                cantidadEstudiantes, cantidadEstudiantesFinalizaron,
                cantidadEstudiantesCancelaronVoluntadPropia,
                cantidadEstudiantesCancelaronAutomaticamente,
                docente
            )
            VALUES (
                @idGrupoDefecto,
                @idAsignaturaDefecto,
                @idPeriodoResolved,
                @codigo,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Grupo ', @codigo) END,
                @capacidadMaximaDefecto, 0, 0, 0,
                @idDocenteDefecto
            );

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
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
-- ---- texto previo de schema/stored-procedures/usp_consultar_destinatarios_sesion_manual.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_sesion_manual (CULM-001 / DEC-064; HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET sin paginacion (<= cupo del grupo + coordinadores).
-- Destinatarios del aviso de una sesion creada manualmente por el docente (uv_sesion_manual; una sesion no manual devuelve 0 filas):
--   * ESTUDIANTE:  matriculas activas (MATRICULA/ESTADO_INSCRITA) del grupo con usuario activo;
--   * COORDINADOR: coordinador(es) activo(s) de TODOS los programas vigentes del grupo (ufn_programas_grupo). Un coordinador de dos
--                  programas del mismo grupo es UNA fila; un grupo mixto devuelve ambos coordinadores.
-- Ambito: RBAC DOCENTE + titularidad 'SESION' dentro del SP (THROW 51000 con el mensaje tecnico si falla). El correo es de uso
-- interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs. Mismo formato que
-- usp_consultar_destinatarios_sesion_cancelada.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_sesion_manual]
(
    @idSesion          UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idSesion IS NULL)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idSesion',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto,
            @codigoPerfilRequerido = 'DOCENTE',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @idUsuarioDefecto,
            @idEntidadPadre = @idSesionDefecto,
            @tipoEntidadPadre = 'SESION',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT  tipoDestinatario = x.tipoDestinatario,
            idUsuario        = x.idUsuario,
            nombreCompleto   = x.nombreCompleto,
            correo           = x.correo,
            nombreAsignatura = x.nombreAsignatura,
            nombreGrupo      = x.nombreGrupo,
            nombreDocente    = x.nombreDocente,
            fechaHoraInicio  = x.fechaHoraInicio,
            fechaHoraFin     = x.fechaHoraFin
    FROM (
        SELECT  tipoDestinatario = CAST(N'ESTUDIANTE' AS NVARCHAR(20)),
                ordenTipo        = 1,
                idUsuario        = ei.idUsuario,
                nombreCompleto   = CAST(ei.nombreCompleto AS NVARCHAR(400)),
                correo           = u.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = sm.fechaHoraInicio,
                fechaHoraFin     = sm.fechaHoraFin
        FROM dbo.uv_sesion_manual sm
        INNER JOIN dbo.uv_grupo g                 ON g.id = sm.idGrupo
        INNER JOIN dbo.uv_docente_identidad di    ON di.id = g.idDocente
        INNER JOIN dbo.uv_estudiante_grupo eg     ON eg.idGrupo = sm.idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante AND ei.estaActivoUsuario = 1
        INNER JOIN dbo.uv_usuario u               ON u.id = ei.idUsuario
        WHERE sm.idSesion = @idSesionDefecto

        UNION ALL

        SELECT  tipoDestinatario = CAST(N'COORDINADOR' AS NVARCHAR(20)),
                ordenTipo        = 2,
                idUsuario        = ci.idUsuario,
                nombreCompleto   = CAST(ci.nombreCompleto AS NVARCHAR(400)),
                correo           = ci.correo,
                nombreAsignatura = g.nombreAsignatura,
                nombreGrupo      = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
                nombreDocente    = CAST(di.nombreCompleto AS NVARCHAR(400)),
                fechaHoraInicio  = sm.fechaHoraInicio,
                fechaHoraFin     = sm.fechaHoraFin
        FROM dbo.uv_sesion_manual sm
        INNER JOIN dbo.uv_grupo g              ON g.id = sm.idGrupo
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        INNER JOIN (
            SELECT DISTINCT ci2.idUsuario, ci2.nombreCompleto, ci2.correo
            FROM dbo.ufn_programas_grupo(
                     (SELECT s.idGrupo FROM dbo.uv_sesion_manual s WHERE s.idSesion = @idSesionDefecto)) pg
            INNER JOIN dbo.Programa p                    ON p.id = pg.idPrograma
            INNER JOIN dbo.uv_coordinador_identidad ci2  ON ci2.id = p.coordinador
                                                        AND ci2.estaActivoRolCoordinador = 1 AND ci2.estaActivoUsuario = 1
        ) ci ON 1 = 1
        WHERE sm.idSesion = @idSesionDefecto
    ) x
    ORDER BY x.ordenTipo, x.nombreCompleto, x.idUsuario;
END;
GO
GO
-- ---- texto previo de schema/stored-procedures/usp_consultar_sesiones_grupo_paginado.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_grupo_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Búsqueda, programación e historial paginado de sesiones de clase para un grupo
--   académico consumiendo uv_auth_sesion. Aplica preservación estricta de SESSION_CONTEXT.
--   CULM-001 B.1 (CONTRACT §2.7.7): agrega al final estaCancelada, codigoTipoCancelacion, motivoCancelacion,
--   nombreDiaFestivo y fechaCancelacionUtc desde uv_sesion_estado (las sesiones canceladas se siguen listando).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_grupo_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @fechaDesde              DATETIME2        = NULL,
    @fechaHasta              DATETIME2        = NULL,
    @numeroSemana            INT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginación normalizada
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroFechaDesde DATETIME2 = @fechaDesde;
    DECLARE @filtroFechaHasta DATETIME2 = @fechaHasta;
    DECLARE @filtroSemana INT = @numeroSemana;

    -- Control de diagnóstico y contexto
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        -- Paso 3: Validación obligatoria de idGrupo
        IF @estadoResultado = 1 AND (@idGrupoDefecto IS NULL OR @idGrupoDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 4: Establecer identidad temporal en contexto para uv_auth_sesion
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @idUsuarioDefecto;

        -- Paso 5: Consulta optimizada de sesiones sobre la vista securizada
        SELECT
            s.id,
            s.idGrupo,
            s.codigoGrupo,
            s.nombreGrupo,
            s.nombre,
            s.numero,
            s.codigo,
            s.numeroSemana,
            s.fechaHoraInicio,
            s.fechaHoraFin,
            COUNT(1) OVER() AS totalRegistros,
            -- CULM-001 B.1 (CONTRACT §2.7.7): estado de la sesion desde uv_sesion_estado
            se.estaCancelada,
            se.codigoTipoCancelacion,
            se.motivoCancelacion,
            se.nombreDiaFestivo,
            se.fechaCancelacionUtc
        FROM dbo.uv_auth_sesion s
        INNER JOIN dbo.uv_sesion_estado se ON se.idSesion = s.id
        WHERE s.idGrupo = @idGrupoDefecto
          AND (@filtroFechaDesde IS NULL OR s.fechaHoraInicio >= @filtroFechaDesde)
          AND (@filtroFechaHasta IS NULL OR s.fechaHoraFin <= @filtroFechaHasta)
          AND (@filtroSemana IS NULL OR s.numeroSemana = @filtroSemana)
        ORDER BY s.fechaHoraInicio ASC, s.numero ASC, s.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

        -- Paso 6: Restaurar el contexto previo
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;

    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
        THROW;
    END CATCH;
END;
GO
GO

DECLARE @idFallidaDefinitiva UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_DEFINITIVA');
IF @idFallidaDefinitiva IS NOT NULL
    UPDATE n
    SET n.idEstado = @idFallidaDefinitiva,
        n.codigoError = 'TIPO_NOTIFICACION_RETIRADO',
        n.detalleError = N'CULM-001 DEC-065 revertido (migracion 30 down): plantilla de solicitud de sesion retirada.'
    FROM dbo.NotificacionSaliente n
    INNER JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado
    WHERE n.tipo IN ('SESION_SOLICITUD_CREADA_COORDINADOR', 'SESION_SOLICITUD_APROBADA_DOCENTE', 'SESION_SOLICITUD_RECHAZADA_DOCENTE') AND e.esTerminal = 0;

DELETE FROM dbo.PlantillaNotificacion
WHERE tipo IN ('SESION_SOLICITUD_CREADA_COORDINADOR', 'SESION_SOLICITUD_APROBADA_DOCENTE', 'SESION_SOLICITUD_RECHAZADA_DOCENTE') AND creadoPor IS NULL;
DELETE FROM dbo.PlantillaNotificacionMarcador
WHERE tipo IN ('SESION_SOLICITUD_CREADA_COORDINADOR', 'SESION_SOLICITUD_APROBADA_DOCENTE', 'SESION_SOLICITUD_RECHAZADA_DOCENTE')
  AND NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion p WHERE p.tipo = PlantillaNotificacionMarcador.tipo);

DELETE FROM dbo.CatalogoParametro
WHERE grupo = 'SESION' AND clave = 'PREFIJO_MOTIVO_SOLICITUD_RECHAZADA' AND ISNULL(valor, N'') = ISNULL(valorDefecto, N'');
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('SES_022', 'SES_023', 'SES_024', 'SES_025', 'SES_026', 'SES_027');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('SES_022', 'SES_023', 'SES_024', 'SES_025', 'SES_026', 'SES_027');
GO

IF OBJECT_ID(N'dbo.uv_estado_solicitud_sesion', N'V') IS NOT NULL DROP VIEW dbo.uv_estado_solicitud_sesion;
GO
IF OBJECT_ID(N'dbo.SesionSolicitud', N'U') IS NOT NULL DROP TABLE dbo.SesionSolicitud;
GO
IF OBJECT_ID(N'dbo.EstadoSolicitudSesion', N'U') IS NOT NULL DROP TABLE dbo.EstadoSolicitudSesion;
GO
PRINT 'MIGRACION 30 DOWN OK';
GO
