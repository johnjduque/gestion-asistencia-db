-- ============================================================================
-- MIGRACION DOWN 68: retira el receso academico del periodo (DEC-081)
--   Borra las cancelaciones hechas por recesos (esas sesiones vuelven a estar programadas), los recesos, los parametros RECESO/* y
--   SESION/CODIGO_TIPO_CANCELACION_FESTIVO, los mensajes REC_001..REC_011, las plantillas y marcadores RECESO_CLASES_CANCELADAS_*, el tipo RECESO
--   y la columna SesionCancelacion.recesoAcademico; restaura CK_SesionCancelacion_origen y UQ_TipoCancelacionSesion_esAutomatica.
--   Elimina los objetos nuevos y restaura aqui las versiones anteriores de usp_internal_aplicar_festivos_grupo,
--   usp_precargar_sesiones_grupo_interno, usp_generar_sesiones_grupo_v2 y usp_previsualizar_horario_grupo (sin recesos).
-- Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 68 DOWN: retira el receso academico del periodo';
GO
IF OBJECT_ID(N'dbo.usp_crear_receso_academico', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_crear_receso_academico];
IF OBJECT_ID(N'dbo.usp_retirar_receso_academico', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_retirar_receso_academico];
IF OBJECT_ID(N'dbo.usp_consultar_recesos_periodo', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_recesos_periodo];
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_receso_academico', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_destinatarios_receso_academico];
GO
-- Restaura la version anterior de usp_internal_aplicar_festivos_grupo
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_aplicar_festivos_grupo (CULM-001 B.1; CONTRACT §2.7.5) — nucleo, sin EXECUTE para el rol runtime.
--
-- Marca como canceladas por FESTIVO las sesiones del grupo cuya fecha LOCAL (TIEMPO/ZONA_HORARIA_SQLSERVER) es un
-- DiaFestivo activo. No abre transaccion: la controla el llamador (publico, generacion v2 o precarga).
--   * Solo sesiones con procedencia temporal confirmada y sin SesionCancelacion (idempotente).
--   * @soloFuturas = 1 (mantenimiento de grupos ya creados): solo fechaHoraInicio > SYSUTCDATETIME();
--     @soloFuturas = 0 (generacion y precarga): toda sesion nueva en festivo nace cancelada ([SUPUESTO-B-11]).
--   * Una candidata con Asistencia no se toca ([SUPUESTO-B-10]): se cuenta en @sesionesConAsistencia y se reporta con
--     usp_consultar_sesiones_festivo_con_asistencia_paginado. No se usa la tabla temporal opcional
--     #sesionesFestivoConAsistencia del contrato: sus SP publicos (que tambien llaman a este nucleo) deben seguir siendo
--     describibles por sp_describe_first_result_set (PUBLIC_CANONICAL_RESULTSET). B.2 agrega la condicion sobre TomaAsistencia.
--   * Tipo por bandera TipoCancelacionSesion.esAutomatica = 1; motivo = FESTIVOS/PREFIJO_MOTIVO_CANCELACION + nombre.
-- Bloqueo: dbo.Sesion WITH (UPDLOCK, HOLDLOCK) sobre las candidatas antes de escribir (mismo orden que la ventana).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_aplicar_festivos_grupo]
(
    @idGrupo                  UNIQUEIDENTIFIER,
    @soloFuturas              BIT,
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER,
    @sesionesCanceladas       INT OUTPUT,
    @sesionesConAsistencia    INT OUTPUT,
    @mensajeUsuarioResultado  NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000) OUTPUT,
    @estadoResultado          BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @prefijoMotivo        NVARCHAR(200)    = dbo.ufn_obtener_parametro('FESTIVOS', 'PREFIJO_MOTIVO_CANCELACION');
    DECLARE @zonaHorariaSqlServer SYSNAME;
    DECLARE @idTipoAutomatico     UNIQUEIDENTIFIER;
    DECLARE @ahoraUtc             DATETIME2 = SYSUTCDATETIME();
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
    DECLARE @mensajeUsuarioExito  NVARCHAR(4000);

    DECLARE @candidatas TABLE (
        idSesion        UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        idDiaFestivo    UNIQUEIDENTIFIER NOT NULL,
        fecha           DATE             NOT NULL,
        nombreFestivo   NVARCHAR(120)    NOT NULL,
        tieneAsistencia BIT              NOT NULL
    );

    SELECT
        @sesionesCanceladas = 0,
        @sesionesConAsistencia = 0,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: zona horaria institucional valida (GEN_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @zonaHorariaSqlServer = CONVERT(SYSNAME, p.valor)
            FROM dbo.uv_parametro p
            WHERE p.grupo = 'TIEMPO' AND p.clave = 'ZONA_HORARIA_SQLSERVER' AND p.estaActivo = 1;

            IF @zonaHorariaSqlServer IS NULL
               OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE [name] = @zonaHorariaSqlServer)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TIEMPO/ZONA_HORARIA_SQLSERVER',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: tipo automatico por bandera de catalogo (GEN_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idTipoAutomatico = t.id FROM dbo.uv_tipo_cancelacion_sesion t WHERE t.esAutomatica = 1;

            IF @idTipoAutomatico IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TipoCancelacionSesion(esAutomatica = 1)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: candidatas bloqueadas (fecha local en un festivo activo, sin cancelacion previa)
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO @candidatas (idSesion, idDiaFestivo, fecha, nombreFestivo, tieneAsistencia)
            SELECT  s.id, df.id, df.fecha, df.nombre,
                    CAST(IIF(EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = s.id)
                             OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id), 1, 0) AS BIT)
            FROM    dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.DiaFestivo df
            ON      df.estaActivo = 1
            AND     df.fecha = CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zonaHorariaSqlServer AS DATE)
            WHERE   s.grupo = @idGrupoDefecto
              AND   s.procedenciaTemporal IS NOT NULL
              AND   (@soloFuturas = 0 OR s.fechaHoraInicio > @ahoraUtc)
              AND   NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id);

            SET @sesionesConAsistencia = (SELECT COUNT(1) FROM @candidatas WHERE tieneAsistencia = 1);

            INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, fechaCancelacionUtc, idCorrelacion)
            SELECT  c.idSesion, @idTipoAutomatico, LEFT(CONCAT(@prefijoMotivo, c.nombreFestivo), 500), c.idDiaFestivo,
                    @idUsuarioEjecutor, SYSUTCDATETIME(), @idCorrelacionDefecto
            FROM    @candidatas c
            WHERE   c.tieneAsistencia = 0;
            SET @sesionesCanceladas = @@ROWCOUNT;

            -- FES_008: usuario (canceladas, con asistencia); tecnico (grupo)
            SELECT @p1 = CONVERT(NVARCHAR(20), @sesionesCanceladas), @p2 = CONVERT(NVARCHAR(20), @sesionesConAsistencia);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FES_008', @p_param1 = @p1, @p_param2 = @p2,
                @mensajeUsuarioResultado = @mensajeUsuarioExito OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @p1 = CONVERT(NVARCHAR(36), @idGrupoDefecto);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FES_008', @p_param1 = @p1,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeUsuarioResultado = @mensajeUsuarioExito;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, N' Canceladas: ', @sesionesCanceladas,
                                                  N'. Con asistencia: ', @sesionesConAsistencia, N'. Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SELECT @estadoResultado = 0, @sesionesCanceladas = 0, @sesionesConAsistencia = 0;
    END CATCH
END;
GO
GO
-- Restaura la version anterior de usp_precargar_sesiones_grupo_interno
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- F2 (2026-11-02): nucleo atomico de usp_precargar_sesiones_grupo. Alinea las sesiones FUTURAS del grupo con su horario:
--   * crea las sesiones que faltan, desde hoy (hora institucional) o desde el inicio del periodo si aun no empieza,
--     hasta el fin del periodo, sin duplicar las que ya existen (mismo grupo, inicio y fin);
--   * elimina las sesiones futuras GENERADAS (procedenciaTemporal = UTC_GENERADOR) que ya no encajan en el horario y no
--     tienen asistencia ni clasificacion. Nunca toca sesiones del pasado ni las creadas a mano por el docente.
-- No abre transaccion: la controla el SP publico (propia o savepoint). No modifica usp_generar_sesiones_grupo (congelado).
-- CULM-001 B.1 (CONTRACT §2.7.6): al final aplica los festivos (usp_internal_aplicar_festivos_grupo, @soloFuturas = 0)
-- en la misma transaccion del llamador: toda sesion creada en un dia festivo nace cancelada. Una sesion futura que se
-- borra porque ya no encaja en el horario pierde antes su SesionCancelacion. Las canceladas que siguen encajando no se
-- borran ni se recrean (idempotencia por grupo, inicio y fin). B.2 agrega la condicion NOT EXISTS TomaAsistencia.
CREATE OR ALTER PROCEDURE [dbo].[usp_precargar_sesiones_grupo_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @sesionesCreadas         INT OUTPUT,
    @sesionesEliminadas      INT OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @zonaHorariaSqlServer SYSNAME;
    DECLARE @ahoraUtc             DATETIME2 = SYSUTCDATETIME();
    DECLARE @fechaInicio          DATE;
    DECLARE @fechaFin             DATE;
    DECLARE @fechaHoy             DATE;
    DECLARE @fechaDesde           DATE;
    DECLARE @maxNumeroSesion      INT;
    DECLARE @fechaHoraLocalInexistente DATETIME2;
    DECLARE @sesionesCanceladasFestivo INT = 0;
    DECLARE @sesionesFestivoConAsistencia INT = 0;
    DECLARE @sesionesEliminables TABLE (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);

    DECLARE @slots TABLE (
        fecha       DATE      NOT NULL,
        inicioLocal DATETIME2 NOT NULL,
        finLocal    DATETIME2 NOT NULL,
        inicioUtc   DATETIME2 NULL,
        finUtc      DATETIME2 NULL
    );

    SELECT
        @sesionesCreadas = 0,
        @sesionesEliminadas = 0,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validacion del identificador de correlacion obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Zona horaria institucional valida para convertir el horario local a UTC
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @zonaHorariaSqlServer = CONVERT(SYSNAME, valor)
            FROM dbo.CatalogoParametro
            WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1;

            IF @zonaHorariaSqlServer IS NULL
               OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE [name] = @zonaHorariaSqlServer)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TIEMPO/ZONA_HORARIA_SQLSERVER',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Franjas futuras del horario del grupo, desde hoy (o desde el inicio del periodo) hasta el fin del periodo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @fechaInicio = pa.fechaInicio, @fechaFin = pa.fechaFin
            FROM dbo.Grupo g
            INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
            WHERE g.id = @idGrupoDefecto;

            SET @fechaHoy = CAST(@ahoraUtc AT TIME ZONE 'UTC' AT TIME ZONE @zonaHorariaSqlServer AS DATE);
            SET @fechaDesde = IIF(@fechaHoy > @fechaInicio, @fechaHoy, @fechaInicio);

            -- 1900-01-01 fue lunes: el resto de dividir los dias desde esa fecha entre 7 da el dia de la semana sin depender del idioma
            WITH fechas AS (
                SELECT fecha = @fechaDesde
                WHERE @fechaDesde <= @fechaFin
                UNION ALL
                SELECT DATEADD(DAY, 1, fecha) FROM fechas WHERE fecha < @fechaFin
            )
            INSERT INTO @slots (fecha, inicioLocal, finLocal)
            SELECT f.fecha,
                   CAST(CONCAT(CONVERT(CHAR(10), f.fecha, 23), 'T', CONVERT(CHAR(8), h.horaInicio, 108)) AS DATETIME2),
                   CAST(CONCAT(CONVERT(CHAR(10), f.fecha, 23), 'T', CONVERT(CHAR(8), h.horaFin, 108)) AS DATETIME2)
            FROM fechas f
            INNER JOIN dbo.Horario h ON h.grupo = @idGrupoDefecto
            INNER JOIN dbo.Dia d ON d.id = h.dia
            WHERE d.codigo = CASE DATEDIFF(DAY, '19000101', f.fecha) % 7
                                 WHEN 0 THEN 'LU' WHEN 1 THEN 'MA' WHEN 2 THEN 'MI' WHEN 3 THEN 'JU'
                                 WHEN 4 THEN 'VI' WHEN 5 THEN 'SA' ELSE 'DO' END
            OPTION (MAXRECURSION 0);

            -- Una hora local inexistente (salto de horario de verano) se desplaza en silencio: se aborta antes de escribir
            SELECT TOP 1 @fechaHoraLocalInexistente = x.horaLocal
            FROM (SELECT horaLocal = inicioLocal FROM @slots UNION ALL SELECT finLocal FROM @slots) x
            WHERE CAST(x.horaLocal AT TIME ZONE @zonaHorariaSqlServer AS DATETIME2) <> x.horaLocal
            ORDER BY x.horaLocal;

            IF @fechaHoraLocalInexistente IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_005', @p_param1 = @zonaHorariaSqlServer, @p_param2 = @fechaHoraLocalInexistente,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            UPDATE @slots
            SET inicioUtc = CAST(inicioLocal AT TIME ZONE @zonaHorariaSqlServer AT TIME ZONE 'UTC' AS DATETIME2),
                finUtc = CAST(finLocal AT TIME ZONE @zonaHorariaSqlServer AT TIME ZONE 'UTC' AS DATETIME2);

            -- Solo lo que aun no empezo: el pasado no se genera ni se toca
            DELETE FROM @slots WHERE inicioUtc <= @ahoraUtc;

            -- PASO 4: Sesiones futuras generadas que ya no encajan en el horario y no tienen asistencia ni clasificacion.
            --         CULM-001 B.1: antes se borra su SesionCancelacion (una sesion que deja de existir pierde su cancelacion).
            INSERT INTO @sesionesEliminables (id)
            SELECT s.id
            FROM dbo.Sesion s
            WHERE s.grupo = @idGrupoDefecto
              AND s.fechaHoraInicio > @ahoraUtc
              AND s.procedenciaTemporal = N'UTC_GENERADOR'
              AND NOT EXISTS (SELECT 1 FROM @slots x WHERE x.inicioUtc = s.fechaHoraInicio AND x.finUtc = s.fechaHoraFin)
              AND NOT EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = s.id)
              AND NOT EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id)
              AND NOT EXISTS (SELECT 1 FROM dbo.SesionProcedenciaClasificacion c WHERE c.sesion = s.id);

            DELETE sc
            FROM dbo.SesionCancelacion sc
            INNER JOIN @sesionesEliminables e ON e.id = sc.sesion;

            DELETE s
            FROM dbo.Sesion s
            INNER JOIN @sesionesEliminables e ON e.id = s.id;
            SET @sesionesEliminadas = @@ROWCOUNT;

            -- PASO 5: Sesiones que faltan, con correlativo protegido contra carreras con usp_crear_sesion
            SELECT @maxNumeroSesion = MAX(numero) FROM dbo.Sesion WITH (UPDLOCK, HOLDLOCK) WHERE grupo = @idGrupoDefecto;

            INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
            SELECT NEWID(),
                   CONCAT(N'Sesi', NCHAR(243), N'n ', CAST(n.numero AS NVARCHAR(10))),
                   n.numero,
                   UPPER(LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(50)), '-', ''), 6)),
                   -- SES-GEN-01 B2b: semana en bloques de 7 dias desde el inicio del periodo (1..16 en 112 dias);
                   -- DATEDIFF(WEEK, ...) cuenta cruces de semana de calendario y daba 17 si el periodo no empieza en lunes.
                   DATEDIFF(DAY, @fechaInicio, n.fecha) / 7 + 1,
                   @idGrupoDefecto,
                   n.inicioUtc,
                   n.finUtc,
                   N'UTC_GENERADOR'
            FROM (
                SELECT x.fecha, x.inicioUtc, x.finUtc,
                       numero = COALESCE(@maxNumeroSesion, 0) + ROW_NUMBER() OVER (ORDER BY x.inicioUtc)
                FROM @slots x
                WHERE NOT EXISTS (
                    SELECT 1 FROM dbo.Sesion e
                    WHERE e.grupo = @idGrupoDefecto AND e.fechaHoraInicio = x.inicioUtc AND e.fechaHoraFin = x.finUtc)
            ) n;
            SET @sesionesCreadas = @@ROWCOUNT;

            -- PASO 6 (CULM-001 B.1): festivos de las sesiones del grupo, en la misma transaccion del llamador
            EXEC dbo.usp_internal_aplicar_festivos_grupo
                @idGrupo = @idGrupoDefecto,
                @soloFuturas = 0,
                @idCorrelacion = @idCorrelacionDefecto,
                @idUsuarioEjecutor = NULL,
                @sesionesCanceladas = @sesionesCanceladasFestivo OUTPUT,
                @sesionesConAsistencia = @sesionesFestivoConAsistencia OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
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
-- Restaura la version anterior de usp_generar_sesiones_grupo_v2
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_generar_sesiones_grupo_v2 (CULM-001 B.1; CONTRACT §2.7.6) — generacion de sesiones con festivos cancelados.
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + sesionesCanceladasPorFestivo,
-- sesionesFestivoConAsistencia (NULL si estadoResultado = 0).
--
-- Fase 1: INSERT INTO @resultadoGeneracion EXEC dbo.usp_generar_sesiones_grupo (congelado: su texto no cambia ni se
--         invoca de otra forma). Sus errores de negocio (RBAC, titularidad, horarios, fechas, zona) ocurren antes de su
--         BEGIN TRANSACTION y no hacen ROLLBACK: su tupla llega intacta y se devuelve tal cual (paridad con el v1).
-- Fase 2: transaccion propia o SAVE TRANSACTION sp_generar_sesiones_v2 -> usp_internal_aplicar_festivos_grupo
--         (@soloFuturas = 0: toda sesion del grupo en festivo nace cancelada; las que tienen asistencia se reportan).
--         Exito: mensaje del SP congelado (GEN_004) + conteos.
-- CATCH (R2-1): la reversion depende solo de @@TRANCOUNT a la entrada (@trancountEntrada):
--   * = 0: ROLLBACK si @@TRANCOUNT > 0 y tupla SYS_001 con ufn_obtener_detalle_error (traduce el 3915 del ROLLBACK
--     del SP congelado dentro del INSERT ... EXEC o cualquier error de las fases 1 y 2). Al salir @@TRANCOUNT = 0.
--   * > 0: THROW sin ROLLBACK y sin tupla: con transaccion externa el BEGIN TRANSACTION del SP congelado queda
--     abierto (XACT_STATE() = -1) y solo el llamador puede revertir.
-- Las dos fases son idempotentes: si la segunda falla, repetir la llamada completa deja el estado correcto.
-- Como usa INSERT ... EXEC, este SP no puede anidarse en otro INSERT ... EXEC (error 8164).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_generar_sesiones_grupo_v2]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @trancountEntrada     INT = @@TRANCOUNT;
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 0;
    DECLARE @idCorrelacionResultado  UNIQUEIDENTIFIER = @idCorrelacionDefecto;

    DECLARE @transaccionPropia     BIT = 0;
    DECLARE @canceladasPorFestivo  INT = 0;
    DECLARE @festivoConAsistencia  INT = 0;
    DECLARE @mensajeUsuarioFase2   NVARCHAR(4000);
    DECLARE @mensajeTecnicoFase2   NVARCHAR(4000);
    DECLARE @estadoFase2           BIT;

    DECLARE @resultadoGeneracion TABLE (
        idCorrelacion           UNIQUEIDENTIFIER NULL,
        mensajeUsuarioResultado NVARCHAR(4000)   NULL,
        mensajeTecnicoResultado NVARCHAR(4000)   NULL,
        estadoResultado         BIT              NULL
    );
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- FASE 1: generacion con el SP congelado
        INSERT INTO @resultadoGeneracion (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
        EXEC dbo.usp_generar_sesiones_grupo @idGrupo = @idGrupo, @idCorrelacion = @idCorrelacion, @idUsuarioEjecutor = @idUsuarioEjecutor;

        SELECT TOP 1
            @idCorrelacionResultado = r.idCorrelacion,
            @mensajeUsuarioResultado = r.mensajeUsuarioResultado,
            @mensajeTecnicoResultado = r.mensajeTecnicoResultado,
            @estadoResultado = r.estadoResultado
        FROM @resultadoGeneracion r;

        -- FASE 2: festivos de las sesiones del grupo (solo si la fase 1 fue exitosa)
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
                SAVE TRANSACTION sp_generar_sesiones_v2;

            EXEC dbo.usp_internal_aplicar_festivos_grupo
                @idGrupo = @idGrupoDefecto,
                @soloFuturas = 0,
                @idCorrelacion = @idCorrelacionDefecto,
                @idUsuarioEjecutor = NULL,
                @sesionesCanceladas = @canceladasPorFestivo OUTPUT,
                @sesionesConAsistencia = @festivoConAsistencia OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioFase2 OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoFase2 OUTPUT,
                @estadoResultado = @estadoFase2 OUTPUT;

            IF XACT_STATE() = -1
                THROW 51000, @mensajeTecnicoFase2, 1;

            IF @estadoFase2 = 0
            BEGIN
                -- Rechazo del nucleo sin escrituras: se informa su mensaje (la fase 1 ya quedo aplicada e idempotente)
                SELECT @mensajeUsuarioResultado = @mensajeUsuarioFase2, @mensajeTecnicoResultado = @mensajeTecnicoFase2, @estadoResultado = 0;
            END

            IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        IF @trancountEntrada > 0
            THROW;

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @idCorrelacionResultado = @idCorrelacionDefecto;
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion                 = @idCorrelacionResultado,
        mensajeUsuarioResultado       = @mensajeUsuarioResultado,
        mensajeTecnicoResultado       = @mensajeTecnicoResultado,
        estadoResultado               = @estadoResultado,
        sesionesCanceladasPorFestivo  = IIF(@estadoResultado = 1, @canceladasPorFestivo, NULL),
        sesionesFestivoConAsistencia  = IIF(@estadoResultado = 1, @festivoConAsistencia, NULL);
END;
GO
GO
-- Restaura la version anterior de usp_previsualizar_horario_grupo
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- READ_QUERY_RESULTSET
-- SES-GEN-01: previsualizacion de solo lectura del horario propuesto de un grupo (nuevo o existente). No escribe ni abre transaccion.
-- Calcula, con la misma definicion de ranuras que usp_precargar_sesiones_grupo_interno (mismo dia de semana, mismo fuso institucional,
-- mismo festivo), las sesiones del periodo, las horas semanales y del periodo, el efecto de los festivos y del inicio tardio, y los
-- conflictos del horario con las reglas de usp_guardar_horarios_grupo (HOR_002, HOR_003, HOR_006, HOR_007, HOR_008, HOR_009) y la
-- advertencia de la materia sin horas (HOR_013). Los conflictos son DATOS (BLOQUEANTE / ADVERTENCIA / INFORMATIVO); un insumo invalido,
-- un recurso inexistente o fuera de ambito se rechazan con THROW 51000 (mismo contrato que las lecturas paginadas): VAL_001, VAL_002,
-- HOR_004, ASI_010, ASI_014, PER_010, SEC_001, SEC_002, GEN_001/DOC_*.
--
-- @idGrupo NULL = grupo nuevo (usa @idAsignatura, @idPeriodoAcademico y @idDocente). Con @idGrupo se toman del grupo; si se envia
-- @idAsignatura o @idPeriodoAcademico y difieren, VAL_001. @idDocente ausente con grupo = titular actual.
-- @horariosJSON: arreglo no vacio de {"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"} (mismo formato que usp_guardar_horarios_grupo).
--
-- UN SOLO conjunto de resultados (filas discriminadas por tipoFila; los totales de tiempo van en MINUTOS enteros; las columnas no usadas
-- por un tipo van en NULL). Columnas fijas y en este orden:
--   tipoFila, orden, id1, id2, id3, texto1..texto5, fecha1, fecha2, instante1, instante2, entero1..entero18, bandera1, bandera2
-- RESUMEN (1 fila, orden 0):
--   id1 idGrupo (NULL si nuevo), id2 idAsignatura, id3 idPeriodo, texto1 codigoAsignatura, texto2 nombreAsignatura, texto3 nombrePeriodo,
--   texto4 estadoPeriodo (PLANEACION/ACTIVO/CERRADO), texto5 zonaHoraria IANA, fecha1 inicioPeriodo, fecha2 finPeriodo,
--   entero1 horasSemanalesMateria (NULL = sin cargar), entero2 minutosSemanales, entero3 franjasPorSemana, entero4 diasPeriodo,
--   entero5 sesionesCalendario, entero6 sesionesProgramadas, entero7 sesionesEnFestivo, entero8 sesionesNoProgramables,
--   entero9 minutosCalendario, entero10 minutosProgramados, entero11 minutosPerdidosFestivo, entero12 minutosNoProgramables,
--   entero13 minutosEsperadosMateria (NULL si la materia no tiene horas), entero14 sesionesConservadas, entero15 minutosConservados,
--   entero16 sesionesFuturasQueSeRetiran, entero17 sesionesFuturasQueSeCrean, entero18 sesionesFuturasQueSeConservan (grupo existente; NULL si nuevo),
--   bandera1 puedeConfirmar (sin conflictos BLOQUEANTE), bandera2 esGrupoExistente.
-- FRANJA (orden = secuencia): texto1 codigoDia, texto2 nombreDia, texto3 horaInicio HH:mm, texto4 horaFin HH:mm, entero1 minutos.
-- SESION (orden = numero): entero1 numero, entero2 numeroSemana, entero3 minutos, fecha1 fecha, texto3 horaInicio, texto4 horaFin,
--   instante1/instante2 inicio y fin UTC, texto1 estado (PROGRAMADA / CANCELADA_POR_FESTIVO / NO_PROGRAMABLE_POR_FECHA), texto2 nombreFestivo.
-- FESTIVO: fecha1 fecha, texto1 nombre, entero1 sesionesAfectadas.
-- CONFLICTO (orden = secuencia): texto1 codigo, texto2 severidad, texto3 mensaje de usuario (catalogo), texto4 franja (puede ser NULL).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_previsualizar_horario_grupo]
(
    @idGrupo             UNIQUEIDENTIFIER = NULL,
    @idAsignatura        UNIQUEIDENTIFIER = NULL,
    @idPeriodoAcademico  UNIQUEIDENTIFIER = NULL,
    @idDocente           UNIQUEIDENTIFIER = NULL,
    @horariosJSON        NVARCHAR(MAX),
    @idCorrelacion       UNIQUEIDENTIFIER,
    @idUsuarioEjecutor   UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @codigoRechazo           VARCHAR(20);
    DECLARE @paramRechazo            NVARCHAR(500);

    DECLARE @ahoraUtc                DATETIME2 = SYSUTCDATETIME();
    DECLARE @zonaSql                 SYSNAME;
    DECLARE @zonaIana                NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_IANA') AS NVARCHAR(100));
    DECLARE @fechaHoy                DATE;
    DECLARE @idAsignaturaRes         UNIQUEIDENTIFIER;
    DECLARE @idPeriodoRes            UNIQUEIDENTIFIER;
    DECLARE @idDocenteRes            UNIQUEIDENTIFIER;
    DECLARE @codigoAsignatura        NVARCHAR(50);
    DECLARE @nombreAsignatura        NVARCHAR(50);
    DECLARE @horasSemanalesMateria   INT;
    DECLARE @nombrePeriodo           NVARCHAR(50);
    DECLARE @estadoPeriodo           VARCHAR(20);
    DECLARE @fechaInicioPeriodo      DATE;
    DECLARE @fechaFinPeriodo         DATE;
    DECLARE @diasPeriodo             INT;
    DECLARE @motivoInvalido          NVARCHAR(200);
    DECLARE @horaLocalInexistente    DATETIME2;

    DECLARE @duracionMinima          INT     = dbo.ufn_obtener_parametro_int(NULL, 'HORARIO', 'DURACION_MINIMA_MINUTOS');
    DECLARE @duracionMaxima          INT     = dbo.ufn_obtener_parametro_int(NULL, 'HORARIO', 'DURACION_MAXIMA_MINUTOS');
    DECLARE @ventanaInicio           TIME(0) = TRY_CAST(dbo.ufn_obtener_parametro('HORARIO', 'VENTANA_INICIO') AS TIME(0));
    DECLARE @ventanaFin              TIME(0) = TRY_CAST(dbo.ufn_obtener_parametro('HORARIO', 'VENTANA_FIN') AS TIME(0));
    DECLARE @codigoMatriculaActiva   NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    DECLARE @minutosSemanales        INT;
    DECLARE @franjasPorSemana        INT;
    DECLARE @minutosEsperados        INT;
    DECLARE @sesionesCalendario      INT;
    DECLARE @sesionesProgramadas     INT;
    DECLARE @sesionesEnFestivo       INT;
    DECLARE @sesionesNoProgramables  INT;
    DECLARE @minutosCalendario       INT;
    DECLARE @minutosProgramados      INT;
    DECLARE @minutosPerdidosFestivo  INT;
    DECLARE @minutosNoProgramables   INT;
    DECLARE @sesionesConservadas     INT = NULL;
    DECLARE @minutosConservados      INT = NULL;
    DECLARE @sesionesQueSeRetiran    INT = NULL;
    DECLARE @sesionesQueSeCrean      INT = NULL;
    DECLARE @sesionesQueSeConservan  INT = NULL;
    DECLARE @puedeConfirmar          BIT;
    DECLARE @secuenciaConflicto      INT = 0;
    DECLARE @texto                   NVARCHAR(4000);
    DECLARE @textoTecnico            NVARCHAR(4000);
    DECLARE @p1                      NVARCHAR(500);
    DECLARE @p2                      NVARCHAR(500);
    DECLARE @p3                      NVARCHAR(500);
    DECLARE @filaPendiente           INT;

    DECLARE @franjas TABLE (
        secuencia  INT IDENTITY(1, 1) PRIMARY KEY,
        idDia      UNIQUEIDENTIFIER NULL,
        codigoDia  NVARCHAR(10)     NULL,
        nombreDia  NVARCHAR(50)     NULL,
        horaInicio TIME(0)          NULL,
        horaFin    TIME(0)          NULL
    );
    DECLARE @slots TABLE (
        fecha       DATE      NOT NULL,
        inicioLocal DATETIME2 NOT NULL,
        finLocal    DATETIME2 NOT NULL,
        inicioUtc   DATETIME2 NULL,
        finUtc      DATETIME2 NULL,
        minutos     INT       NULL,
        estado      VARCHAR(30) NULL,
        nombreFestivo NVARCHAR(120) NULL
    );
    DECLARE @conflictos TABLE (
        secuencia INT IDENTITY(1, 1) PRIMARY KEY,
        codigo    VARCHAR(20)   NOT NULL,
        severidad VARCHAR(15)   NOT NULL,
        param1    NVARCHAR(500) NULL,
        param2    NVARCHAR(500) NULL,
        param3    NVARCHAR(500) NULL,
        franja    NVARCHAR(100) NULL,
        mensaje   NVARCHAR(4000) NULL
    );
    DECLARE @existentes TABLE (
        id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        inicioUtc DATETIME2 NOT NULL,
        finUtc DATETIME2 NOT NULL,
        minutos INT NOT NULL,
        esFutura BIT NOT NULL,
        esGenerada BIT NOT NULL,
        esProtegida BIT NOT NULL,
        encaja BIT NOT NULL
    );
    DECLARE @salida TABLE (
        tipoFila VARCHAR(12) NOT NULL, orden INT NOT NULL,
        id1 UNIQUEIDENTIFIER NULL, id2 UNIQUEIDENTIFIER NULL, id3 UNIQUEIDENTIFIER NULL,
        texto1 NVARCHAR(200) NULL, texto2 NVARCHAR(200) NULL, texto3 NVARCHAR(4000) NULL, texto4 NVARCHAR(200) NULL, texto5 NVARCHAR(200) NULL,
        fecha1 DATE NULL, fecha2 DATE NULL, instante1 DATETIME2 NULL, instante2 DATETIME2 NULL,
        entero1 INT NULL, entero2 INT NULL, entero3 INT NULL, entero4 INT NULL, entero5 INT NULL, entero6 INT NULL,
        entero7 INT NULL, entero8 INT NULL, entero9 INT NULL, entero10 INT NULL, entero11 INT NULL, entero12 INT NULL,
        entero13 INT NULL, entero14 INT NULL, entero15 INT NULL, entero16 INT NULL, entero17 INT NULL, entero18 INT NULL,
        bandera1 BIT NULL, bandera2 BIT NULL
    );
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion y ejecutor con perfil COORDINADOR (SEC_001)
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        SET @codigoRechazo = 'GEN_002';
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'COORDINADOR', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: resolver grupo / asignatura / periodo / docente
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
    BEGIN
        IF @idGrupo IS NOT NULL
        BEGIN
            SELECT TOP 1 @idAsignaturaRes = g.idAsignatura, @idPeriodoRes = g.idPeriodoAcademico, @idDocenteRes = g.idDocente
            FROM dbo.uv_grupo g WHERE g.id = @idGrupo;

            IF @idAsignaturaRes IS NULL
                SELECT @codigoRechazo = 'VAL_002', @paramRechazo = N'Grupo';
            ELSE IF (@idAsignatura IS NOT NULL AND @idAsignatura <> @idAsignaturaRes)
                 OR (@idPeriodoAcademico IS NOT NULL AND @idPeriodoAcademico <> @idPeriodoRes)
                SELECT @codigoRechazo = 'VAL_001';
            ELSE
                IF @idDocente IS NOT NULL SET @idDocenteRes = @idDocente;
        END
        ELSE
        BEGIN
            SELECT @idAsignaturaRes = @idAsignatura, @idPeriodoRes = @idPeriodoAcademico, @idDocenteRes = @idDocente;
            IF @idAsignaturaRes IS NULL OR @idPeriodoRes IS NULL OR @idDocenteRes IS NULL
                SET @codigoRechazo = 'VAL_001';
        END
    END

    -- PASO 3: asignatura activa (VAL_002 / ASI_010); B1 (ASI_014: vinculo activo a plan activo y todos sus programas en custodia)
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
    BEGIN
        SELECT @codigoAsignatura = a.codigo, @nombreAsignatura = a.nombre, @horasSemanalesMateria = a.horasSemanales
        FROM dbo.uv_asignatura a WHERE a.id = @idAsignaturaRes;

        IF @codigoAsignatura IS NULL
            SELECT @codigoRechazo = 'VAL_002', @paramRechazo = N'Asignatura';
        ELSE IF NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura a WHERE a.id = @idAsignaturaRes AND a.estaActivaAsignatura = 1)
            SET @codigoRechazo = 'ASI_010';
        ELSE IF NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
                            WHERE v.idAsignatura = @idAsignaturaRes AND v.estaActivoVinculo = 1 AND v.estaActivoPlan = 1 AND v.estaActivaAsignatura = 1)
             OR EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
                        WHERE v.idAsignatura = @idAsignaturaRes AND v.estaActivoVinculo = 1 AND v.estaActivoPlan = 1
                          AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto) cp WHERE cp.idPrograma = v.idPrograma))
            SET @codigoRechazo = 'ASI_014';
    END

    -- PASO 4: periodo (VAL_002) de la institucion del coordinador, no terminado ni cerrado (PER_010)
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
    BEGIN
        SELECT @nombrePeriodo = pa.nombre, @estadoPeriodo = pa.estado, @fechaInicioPeriodo = pa.fechaInicio, @fechaFinPeriodo = pa.fechaFin
        FROM dbo.uv_periodo_academico pa WHERE pa.id = @idPeriodoRes;

        IF @nombrePeriodo IS NULL
            SELECT @codigoRechazo = 'VAL_002', @paramRechazo = N'PeriodoAcademico';
        ELSE IF @estadoPeriodo = 'CERRADO'
             OR EXISTS (SELECT 1 FROM dbo.uv_periodo_academico_cierre p WHERE p.id = @idPeriodoRes AND p.fechaCierreUtc IS NOT NULL)
             OR NOT EXISTS (SELECT 1 FROM dbo.uv_periodo_academico pa
                            WHERE pa.id = @idPeriodoRes
                              AND pa.idInstitucion IN (SELECT pr.idInstitucion FROM dbo.uv_programa pr
                                                       WHERE pr.id IN (SELECT cp.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto) cp)))
            SELECT @codigoRechazo = 'PER_010', @paramRechazo = @nombrePeriodo;
    END

    -- PASO 5: docente existente con vinculo activo con el programa (B3); sus rechazos llegan como excepcion con su propio codigo
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
    BEGIN
        EXEC dbo.usp_validar_docente_exista_por_id_interno
            @idDocente = @idDocenteRes, @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_docente_vinculo_activo_programa_interno
                @idDocente = @idDocenteRes, @idAsignatura = @idAsignaturaRes, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
    END

    -- PASO 6: formato del horario (HOR_004): arreglo no vacio, solo las 3 claves, dia existente y horaFin > horaInicio
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
    BEGIN
        IF @horariosJSON IS NULL OR ISJSON(@horariosJSON, ARRAY) <> 1 OR NOT EXISTS (SELECT 1 FROM OPENJSON(@horariosJSON))
            SET @motivoInvalido = N'debe enviar al menos una franja';
        ELSE IF EXISTS (
            SELECT 1 FROM OPENJSON(@horariosJSON) item
            WHERE item.[type] <> 5
               OR EXISTS (SELECT 1 FROM OPENJSON(item.value) campo WHERE campo.[key] NOT IN ('codigoDia', 'horaInicio', 'horaFin')))
            SET @motivoInvalido = N'cada franja lleva solo codigoDia, horaInicio y horaFin';
        ELSE
        BEGIN
            INSERT INTO @franjas (idDia, codigoDia, nombreDia, horaInicio, horaFin)
            SELECT d.id, UPPER(TRIM(f.codigoDia)), d.nombre, TRY_CAST(f.horaInicio AS TIME(0)), TRY_CAST(f.horaFin AS TIME(0))
            FROM OPENJSON(@horariosJSON)
                WITH (codigoDia NVARCHAR(10) '$.codigoDia', horaInicio NVARCHAR(20) '$.horaInicio', horaFin NVARCHAR(20) '$.horaFin') f
            LEFT JOIN dbo.uv_dia d ON d.codigo = UPPER(TRIM(f.codigoDia));

            SELECT TOP 1 @motivoInvalido =
                CASE
                    WHEN idDia IS NULL THEN CONCAT(N'el dia "', codigoDia, N'" no existe')
                    WHEN horaInicio IS NULL OR horaFin IS NULL THEN N'las horas deben tener formato HH:mm'
                    ELSE CONCAT(N'en ', nombreDia, N' la hora de fin debe ser mayor que la de inicio')
                END
            FROM @franjas
            WHERE idDia IS NULL OR horaInicio IS NULL OR horaFin IS NULL OR horaFin <= horaInicio
            ORDER BY secuencia;
        END

        IF @motivoInvalido IS NOT NULL
            SELECT @codigoRechazo = 'HOR_004', @paramRechazo = @motivoInvalido;
    END

    -- Rechazo de insumo, recurso o ambito: se informa con el codigo del catalogo (la capa HTTP lo clasifica) y no se calcula nada
    IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
    BEGIN
        IF @codigoRechazo IS NOT NULL
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @paramRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = LEFT(CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto), 2000);
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 7: zona horaria institucional (GEN_001 si falta) y fecha local de hoy
    SELECT TOP 1 @zonaSql = CONVERT(SYSNAME, valor)
    FROM dbo.uv_parametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1;
    IF @zonaSql IS NULL OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE [name] = @zonaSql)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_001', @p_param1 = 'TIEMPO/ZONA_HORARIA_SQLSERVER',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = LEFT(CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto), 2000);
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
    SET @fechaHoy = CAST(@ahoraUtc AT TIME ZONE 'UTC' AT TIME ZONE @zonaSql AS DATE);
    SET @diasPeriodo = DATEDIFF(DAY, @fechaInicioPeriodo, @fechaFinPeriodo) + 1;

    -- PASO 8: ranuras del periodo completo con el MISMO calculo de dia de semana de la precarga (1900-01-01 fue lunes)
    WITH fechas AS (
        SELECT fecha = @fechaInicioPeriodo WHERE @fechaInicioPeriodo <= @fechaFinPeriodo
        UNION ALL
        SELECT DATEADD(DAY, 1, fecha) FROM fechas WHERE fecha < @fechaFinPeriodo
    )
    INSERT INTO @slots (fecha, inicioLocal, finLocal)
    SELECT f.fecha,
           CAST(CONCAT(CONVERT(CHAR(10), f.fecha, 23), 'T', CONVERT(CHAR(8), h.horaInicio, 108)) AS DATETIME2),
           CAST(CONCAT(CONVERT(CHAR(10), f.fecha, 23), 'T', CONVERT(CHAR(8), h.horaFin, 108)) AS DATETIME2)
    FROM fechas f
    INNER JOIN @franjas h ON 1 = 1
    WHERE h.codigoDia = CASE DATEDIFF(DAY, '19000101', f.fecha) % 7
                            WHEN 0 THEN 'LU' WHEN 1 THEN 'MA' WHEN 2 THEN 'MI' WHEN 3 THEN 'JU'
                            WHEN 4 THEN 'VI' WHEN 5 THEN 'SA' ELSE 'DO' END
    OPTION (MAXRECURSION 0);

    -- Una hora local inexistente (salto de horario de verano) impide calcular la ranura: conflicto bloqueante SES_005
    SELECT TOP 1 @horaLocalInexistente = x.horaLocal
    FROM (SELECT horaLocal = inicioLocal FROM @slots UNION ALL SELECT finLocal FROM @slots) x
    WHERE CAST(x.horaLocal AT TIME ZONE @zonaSql AS DATETIME2) <> x.horaLocal
    ORDER BY x.horaLocal;
    IF @horaLocalInexistente IS NOT NULL
        INSERT INTO @conflictos (codigo, severidad, param1, param2) VALUES ('SES_005', 'BLOQUEANTE', @zonaSql, CONVERT(NVARCHAR(30), @horaLocalInexistente, 120));
    ELSE
    BEGIN
        UPDATE @slots
        SET inicioUtc = CAST(inicioLocal AT TIME ZONE @zonaSql AT TIME ZONE 'UTC' AS DATETIME2),
            finUtc = CAST(finLocal AT TIME ZONE @zonaSql AT TIME ZONE 'UTC' AS DATETIME2),
            minutos = DATEDIFF(MINUTE, inicioLocal, finLocal);

        UPDATE s
        SET estado = CASE WHEN s.inicioUtc <= @ahoraUtc THEN 'NO_PROGRAMABLE_POR_FECHA'
                          WHEN df.id IS NOT NULL THEN 'CANCELADA_POR_FESTIVO'
                          ELSE 'PROGRAMADA' END,
            nombreFestivo = IIF(s.inicioUtc <= @ahoraUtc, NULL, df.nombre)
        FROM @slots s
        LEFT JOIN dbo.uv_dia_festivo df ON df.estaActivo = 1 AND df.fecha = s.fecha;
    END

    -- PASO 9: totales
    SELECT @minutosSemanales = SUM(DATEDIFF(MINUTE, horaInicio, horaFin)), @franjasPorSemana = COUNT(*) FROM @franjas;
    SELECT @sesionesCalendario = COUNT(*), @minutosCalendario = COALESCE(SUM(minutos), 0),
           @sesionesProgramadas = COALESCE(SUM(IIF(estado = 'PROGRAMADA', 1, 0)), 0),
           @minutosProgramados = COALESCE(SUM(IIF(estado = 'PROGRAMADA', minutos, 0)), 0),
           @sesionesEnFestivo = COALESCE(SUM(IIF(estado = 'CANCELADA_POR_FESTIVO', 1, 0)), 0),
           @minutosPerdidosFestivo = COALESCE(SUM(IIF(estado = 'CANCELADA_POR_FESTIVO', minutos, 0)), 0),
           @sesionesNoProgramables = COALESCE(SUM(IIF(estado = 'NO_PROGRAMABLE_POR_FECHA', 1, 0)), 0),
           @minutosNoProgramables = COALESCE(SUM(IIF(estado = 'NO_PROGRAMABLE_POR_FECHA', minutos, 0)), 0)
    FROM @slots;
    IF @horasSemanalesMateria IS NOT NULL
        SET @minutosEsperados = CAST(ROUND(@horasSemanalesMateria * 60.0 * @diasPeriodo / 7.0, 0) AS INT);

    -- PASO 10: efecto sobre un grupo existente (B10): lo ya dictado, con asistencia, toma o clasificacion, y lo creado a mano se conserva
    IF @idGrupo IS NOT NULL
    BEGIN
        INSERT INTO @existentes (id, inicioUtc, finUtc, minutos, esFutura, esGenerada, esProtegida, encaja)
        SELECT s.id, s.fechaHoraInicio, s.fechaHoraFin, DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin),
               CAST(IIF(s.fechaHoraInicio > @ahoraUtc, 1, 0) AS BIT),
               CAST(IIF(s.procedenciaTemporal = N'UTC_GENERADOR', 1, 0) AS BIT),
               CAST(IIF(s.procedenciaTemporal = N'UTC_OWNER'
                        OR EXISTS (SELECT 1 FROM dbo.uv_asistencia a WHERE a.idSesion = s.id)
                        OR EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia t WHERE t.idSesion = s.id), 1, 0) AS BIT),
               CAST(IIF(EXISTS (SELECT 1 FROM @slots x WHERE x.inicioUtc = s.fechaHoraInicio AND x.finUtc = s.fechaHoraFin), 1, 0) AS BIT)
        FROM dbo.uv_sesion_v2 s WHERE s.idGrupo = @idGrupo;

        SELECT @sesionesConservadas = COUNT(*), @minutosConservados = COALESCE(SUM(minutos), 0)
        FROM @existentes WHERE esFutura = 0 OR esGenerada = 0 OR esProtegida = 1;

        SELECT @sesionesQueSeRetiran = COUNT(*) FROM @existentes WHERE esFutura = 1 AND esGenerada = 1 AND esProtegida = 0 AND encaja = 0;
        SELECT @sesionesQueSeConservan = COUNT(*) FROM @existentes WHERE esFutura = 1 AND encaja = 1;
        SELECT @sesionesQueSeCrean = COUNT(*)
        FROM @slots x
        WHERE x.estado IN ('PROGRAMADA', 'CANCELADA_POR_FESTIVO')
          AND NOT EXISTS (SELECT 1 FROM @existentes e WHERE e.inicioUtc = x.inicioUtc AND e.finUtc = x.finUtc);
    END

    -- PASO 11: conflictos del horario (mismas reglas que usp_guardar_horarios_grupo, como datos)
    -- HOR_003: franjas traslapadas del propio horario (las contiguas se permiten)
    INSERT INTO @conflictos (codigo, severidad, param1, param2, franja)
    SELECT TOP 1 'HOR_003', 'BLOQUEANTE',
           CONCAT(a.nombreDia, ' ', CONVERT(CHAR(5), a.horaInicio, 108), '-', CONVERT(CHAR(5), a.horaFin, 108)),
           CONCAT(b.nombreDia, ' ', CONVERT(CHAR(5), b.horaInicio, 108), '-', CONVERT(CHAR(5), b.horaFin, 108)),
           CONCAT(a.nombreDia, ' ', CONVERT(CHAR(5), a.horaInicio, 108), '-', CONVERT(CHAR(5), a.horaFin, 108))
    FROM @franjas a INNER JOIN @franjas b ON b.idDia = a.idDia AND b.secuencia > a.secuencia
    WHERE a.horaInicio < b.horaFin AND a.horaFin > b.horaInicio
    ORDER BY a.secuencia, b.secuencia;

    -- HOR_007 / HOR_008: duracion de cada franja y ventana horaria (parametro ausente omite la regla)
    INSERT INTO @conflictos (codigo, severidad, param1, param2, param3, franja)
    SELECT 'HOR_007', 'BLOQUEANTE',
           CONCAT(nombreDia, ' ', CONVERT(CHAR(5), horaInicio, 108), '-', CONVERT(CHAR(5), horaFin, 108)),
           CAST(@duracionMinima AS NVARCHAR(20)), CAST(@duracionMaxima AS NVARCHAR(20)),
           CONCAT(nombreDia, ' ', CONVERT(CHAR(5), horaInicio, 108), '-', CONVERT(CHAR(5), horaFin, 108))
    FROM @franjas
    WHERE (@duracionMinima IS NOT NULL AND DATEDIFF(MINUTE, horaInicio, horaFin) < @duracionMinima)
       OR (@duracionMaxima IS NOT NULL AND DATEDIFF(MINUTE, horaInicio, horaFin) > @duracionMaxima)
    ORDER BY secuencia;

    INSERT INTO @conflictos (codigo, severidad, param1, param2, franja)
    SELECT 'HOR_008', 'BLOQUEANTE',
           CONCAT(nombreDia, ' ', CONVERT(CHAR(5), horaInicio, 108), '-', CONVERT(CHAR(5), horaFin, 108)),
           CONCAT(CONVERT(CHAR(5), @ventanaInicio, 108), '-', CONVERT(CHAR(5), @ventanaFin, 108)),
           CONCAT(nombreDia, ' ', CONVERT(CHAR(5), horaInicio, 108), '-', CONVERT(CHAR(5), horaFin, 108))
    FROM @franjas
    WHERE @ventanaInicio IS NOT NULL AND @ventanaFin IS NOT NULL AND (horaInicio < @ventanaInicio OR horaFin > @ventanaFin)
    ORDER BY secuencia;

    -- HOR_006 (B5): las horas semanales de las franjas igualan, exacto, las de la materia
    IF @horasSemanalesMateria IS NOT NULL AND @minutosSemanales <> @horasSemanalesMateria * 60
        INSERT INTO @conflictos (codigo, severidad, param1, param2)
        VALUES ('HOR_006', 'BLOQUEANTE',
                IIF(@minutosSemanales % 60 = 0, CAST(@minutosSemanales / 60 AS NVARCHAR(20)), CAST(CAST(@minutosSemanales / 60.0 AS DECIMAL(6, 2)) AS NVARCHAR(20))),
                CAST(@horasSemanalesMateria AS NVARCHAR(20)));

    -- HOR_002: el docente no tiene otro grupo a la misma hora en el periodo
    INSERT INTO @conflictos (codigo, severidad, param1, param2, franja)
    SELECT TOP 1 'HOR_002', 'BLOQUEANTE', hx.nombreGrupo,
           CONCAT(hx.nombreDia, ' ', CONVERT(CHAR(5), hx.horaInicio, 108), '-', CONVERT(CHAR(5), hx.horaFin, 108)),
           CONCAT(f.nombreDia, ' ', CONVERT(CHAR(5), f.horaInicio, 108), '-', CONVERT(CHAR(5), f.horaFin, 108))
    FROM @franjas f
    INNER JOIN dbo.uv_horario hx ON hx.idDia = f.idDia AND hx.idPeriodoAcademico = @idPeriodoRes
         AND (@idGrupo IS NULL OR hx.idGrupo <> @idGrupo)
    INNER JOIN dbo.uv_grupo gx ON gx.id = hx.idGrupo AND gx.idDocente = @idDocenteRes
    WHERE f.horaInicio < hx.horaFin AND f.horaFin > hx.horaInicio
    ORDER BY f.secuencia;

    -- HOR_009 (B9): el horario nuevo no cruza con otros grupos de los estudiantes ya inscritos (solo grupo existente)
    IF @idGrupo IS NOT NULL
        INSERT INTO @conflictos (codigo, severidad, param1, param2, franja)
        SELECT 'HOR_009', 'BLOQUEANTE', CAST(COUNT(DISTINCT egNuevo.idEstudiante) AS NVARCHAR(20)),
               MIN(CONCAT(f.nombreDia, ' ', CONVERT(CHAR(5), f.horaInicio, 108), '-', CONVERT(CHAR(5), f.horaFin, 108))),
               MIN(CONCAT(f.nombreDia, ' ', CONVERT(CHAR(5), f.horaInicio, 108), '-', CONVERT(CHAR(5), f.horaFin, 108)))
        FROM @franjas f
        INNER JOIN dbo.uv_horario hx ON hx.idDia = f.idDia AND hx.idPeriodoAcademico = @idPeriodoRes AND hx.idGrupo <> @idGrupo
        INNER JOIN dbo.uv_estudiante_grupo egOtro ON egOtro.idGrupo = hx.idGrupo AND egOtro.codigoEstadoEstudiante = @codigoMatriculaActiva
        INNER JOIN dbo.uv_estudiante_grupo egNuevo ON egNuevo.idGrupo = @idGrupo AND egNuevo.codigoEstadoEstudiante = @codigoMatriculaActiva
             AND egNuevo.idEstudiante = egOtro.idEstudiante
        WHERE f.horaInicio < hx.horaFin AND f.horaFin > hx.horaInicio
        HAVING COUNT(*) > 0;

    -- Informativos y advertencias (no bloquean)
    IF @horasSemanalesMateria IS NULL
        INSERT INTO @conflictos (codigo, severidad) VALUES ('HOR_013', 'ADVERTENCIA');
    ELSE IF @minutosProgramados + COALESCE(@minutosConservados, 0) < @minutosEsperados
        INSERT INTO @conflictos (codigo, severidad, param1, param2)
        VALUES ('HOR_010', 'INFORMATIVO',
                IIF((@minutosProgramados + COALESCE(@minutosConservados, 0)) % 60 = 0,
                    CAST((@minutosProgramados + COALESCE(@minutosConservados, 0)) / 60 AS NVARCHAR(20)),
                    CAST(CAST((@minutosProgramados + COALESCE(@minutosConservados, 0)) / 60.0 AS DECIMAL(10, 2)) AS NVARCHAR(20))),
                IIF(@minutosEsperados % 60 = 0, CAST(@minutosEsperados / 60 AS NVARCHAR(20)), CAST(CAST(@minutosEsperados / 60.0 AS DECIMAL(10, 2)) AS NVARCHAR(20))));
    IF @sesionesEnFestivo > 0
        INSERT INTO @conflictos (codigo, severidad, param1, param2)
        VALUES ('HOR_011', 'INFORMATIVO',
                IIF(@minutosPerdidosFestivo % 60 = 0, CAST(@minutosPerdidosFestivo / 60 AS NVARCHAR(20)), CAST(CAST(@minutosPerdidosFestivo / 60.0 AS DECIMAL(10, 2)) AS NVARCHAR(20))),
                CAST(@sesionesEnFestivo AS NVARCHAR(20)));
    IF @sesionesNoProgramables > 0
        INSERT INTO @conflictos (codigo, severidad, param1, param2)
        VALUES ('HOR_012', 'INFORMATIVO',
                IIF(@minutosNoProgramables % 60 = 0, CAST(@minutosNoProgramables / 60 AS NVARCHAR(20)), CAST(CAST(@minutosNoProgramables / 60.0 AS DECIMAL(10, 2)) AS NVARCHAR(20))),
                CONVERT(NVARCHAR(10), @fechaHoy, 23));
    IF @idGrupo IS NOT NULL AND @sesionesConservadas > 0
        INSERT INTO @conflictos (codigo, severidad, param1, param2)
        VALUES ('HOR_014', 'INFORMATIVO', CAST(@sesionesConservadas AS NVARCHAR(20)),
                IIF(@minutosConservados % 60 = 0, CAST(@minutosConservados / 60 AS NVARCHAR(20)), CAST(CAST(@minutosConservados / 60.0 AS DECIMAL(10, 2)) AS NVARCHAR(20))));

    -- Mensajes de usuario desde el catalogo (ningun texto vive en el codigo)
    SELECT @filaPendiente = MIN(secuencia) FROM @conflictos;
    WHILE @filaPendiente IS NOT NULL
    BEGIN
        SELECT @p1 = param1, @p2 = param2, @p3 = param3,
               @texto = (SELECT codigo FROM @conflictos WHERE secuencia = @filaPendiente)
        FROM @conflictos WHERE secuencia = @filaPendiente;
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = @texto, @p_param1 = @p1, @p_param2 = @p2, @p_param3 = @p3,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        UPDATE @conflictos SET mensaje = @mensajeUsuarioResultado WHERE secuencia = @filaPendiente;
        SELECT @filaPendiente = MIN(secuencia) FROM @conflictos WHERE secuencia > @filaPendiente;
    END

    SET @puedeConfirmar = IIF(EXISTS (SELECT 1 FROM @conflictos WHERE severidad = 'BLOQUEANTE'), 0, 1);

    -- PASO 12: filas de salida
    INSERT INTO @salida (tipoFila, orden, id1, id2, id3, texto1, texto2, texto3, texto4, texto5, fecha1, fecha2,
                         entero1, entero2, entero3, entero4, entero5, entero6, entero7, entero8, entero9, entero10, entero11, entero12,
                         entero13, entero14, entero15, entero16, entero17, entero18, bandera1, bandera2)
    VALUES ('RESUMEN', 0, @idGrupo, @idAsignaturaRes, @idPeriodoRes, @codigoAsignatura, @nombreAsignatura, @nombrePeriodo, @estadoPeriodo, @zonaIana,
            @fechaInicioPeriodo, @fechaFinPeriodo,
            @horasSemanalesMateria, @minutosSemanales, @franjasPorSemana, @diasPeriodo,
            @sesionesCalendario, @sesionesProgramadas, @sesionesEnFestivo, @sesionesNoProgramables,
            @minutosCalendario, @minutosProgramados, @minutosPerdidosFestivo, @minutosNoProgramables,
            @minutosEsperados, @sesionesConservadas, @minutosConservados, @sesionesQueSeRetiran, @sesionesQueSeCrean, @sesionesQueSeConservan,
            @puedeConfirmar, CAST(IIF(@idGrupo IS NULL, 0, 1) AS BIT));

    INSERT INTO @salida (tipoFila, orden, texto1, texto2, texto3, texto4, entero1)
    SELECT 'FRANJA', secuencia, codigoDia, nombreDia, CONVERT(CHAR(5), horaInicio, 108), CONVERT(CHAR(5), horaFin, 108), DATEDIFF(MINUTE, horaInicio, horaFin)
    FROM @franjas;

    INSERT INTO @salida (tipoFila, orden, entero1, entero2, entero3, fecha1, texto3, texto4, instante1, instante2, texto1, texto2)
    SELECT 'SESION', ROW_NUMBER() OVER (ORDER BY inicioUtc), ROW_NUMBER() OVER (ORDER BY inicioUtc),
           DATEDIFF(DAY, @fechaInicioPeriodo, fecha) / 7 + 1, minutos, fecha,
           CONVERT(CHAR(5), inicioLocal, 108), CONVERT(CHAR(5), finLocal, 108), inicioUtc, finUtc, estado, nombreFestivo
    FROM @slots WHERE inicioUtc IS NOT NULL;

    INSERT INTO @salida (tipoFila, orden, fecha1, texto1, entero1)
    SELECT 'FESTIVO', ROW_NUMBER() OVER (ORDER BY fecha), fecha, MIN(nombreFestivo), COUNT(*)
    FROM @slots WHERE estado = 'CANCELADA_POR_FESTIVO' GROUP BY fecha;

    INSERT INTO @salida (tipoFila, orden, texto1, texto2, texto3, texto4)
    SELECT 'CONFLICTO', secuencia, codigo, severidad, mensaje, franja FROM @conflictos;

    SELECT tipoFila, orden, id1, id2, id3, texto1, texto2, texto3, texto4, texto5, fecha1, fecha2, instante1, instante2,
           entero1, entero2, entero3, entero4, entero5, entero6, entero7, entero8, entero9, entero10, entero11, entero12,
           entero13, entero14, entero15, entero16, entero17, entero18, bandera1, bandera2
    FROM @salida
    ORDER BY CASE tipoFila WHEN 'RESUMEN' THEN 0 WHEN 'FRANJA' THEN 1 WHEN 'SESION' THEN 2 WHEN 'FESTIVO' THEN 3 ELSE 4 END, orden;
END;
GO
GO
IF OBJECT_ID(N'dbo.usp_validar_receso_academico_interno', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_validar_receso_academico_interno];
IF OBJECT_ID(N'dbo.usp_internal_cancelar_sesiones_receso', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_internal_cancelar_sesiones_receso];
-- SKILLS-BD lote 16: la migracion 78 renombro este nucleo a usp_cancelar_sesiones_receso_interno; se borra tambien el nombre nuevo.
DROP PROCEDURE IF EXISTS [dbo].[usp_cancelar_sesiones_receso_interno];
IF OBJECT_ID(N'dbo.uv_periodo_receso_academico', N'V') IS NOT NULL DROP VIEW [dbo].[uv_periodo_receso_academico];
GO
IF COL_LENGTH('dbo.SesionCancelacion', 'recesoAcademico') IS NOT NULL
    DELETE FROM dbo.SesionCancelacion WHERE recesoAcademico IS NOT NULL;
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SesionCancelacion_PeriodoRecesoAcademico')
    ALTER TABLE dbo.SesionCancelacion DROP CONSTRAINT FK_SesionCancelacion_PeriodoRecesoAcademico;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SesionCancelacion') AND name = 'IX_SesionCancelacion_recesoAcademico')
    DROP INDEX IX_SesionCancelacion_recesoAcademico ON dbo.SesionCancelacion;
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SesionCancelacion_origen' AND parent_object_id = OBJECT_ID('dbo.SesionCancelacion'))
    ALTER TABLE dbo.SesionCancelacion DROP CONSTRAINT CK_SesionCancelacion_origen;
GO
IF COL_LENGTH('dbo.SesionCancelacion', 'recesoAcademico') IS NOT NULL
    ALTER TABLE dbo.SesionCancelacion DROP COLUMN recesoAcademico;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SesionCancelacion_origen' AND parent_object_id = OBJECT_ID('dbo.SesionCancelacion'))
    ALTER TABLE dbo.SesionCancelacion ADD CONSTRAINT CK_SesionCancelacion_origen CHECK (diaFestivo IS NOT NULL OR usuarioEjecutor IS NOT NULL);
GO
IF OBJECT_ID('dbo.PeriodoRecesoAcademico', 'U') IS NOT NULL DROP TABLE dbo.PeriodoRecesoAcademico;
GO
DELETE FROM dbo.TipoCancelacionSesion WHERE codigo = N'RECESO';
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_TipoCancelacionSesion_esAutomatica' AND parent_object_id = OBJECT_ID('dbo.TipoCancelacionSesion'))
    ALTER TABLE dbo.TipoCancelacionSesion ADD CONSTRAINT UQ_TipoCancelacionSesion_esAutomatica UNIQUE (esAutomatica);
GO
DELETE FROM dbo.PlantillaNotificacion WHERE tipo IN (N'RECESO_CLASES_CANCELADAS_ESTUDIANTE', N'RECESO_CLASES_CANCELADAS_DOCENTE');
DELETE FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN (N'RECESO_CLASES_CANCELADAS_ESTUDIANTE', N'RECESO_CLASES_CANCELADAS_DOCENTE');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE N'REC[_]0[0-1][0-9]';
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE N'REC[_]0[0-1][0-9]';
DELETE FROM dbo.CatalogoParametro WHERE (grupo = N'RECESO') OR (grupo = N'SESION' AND clave = N'CODIGO_TIPO_CANCELACION_FESTIVO');
GO
PRINT 'MIGRACION 68 DOWN: completada';
GO
