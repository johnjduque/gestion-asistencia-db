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
-- CULM-001 B.1 (CONTRACT §2.7.6): al final aplica los festivos (usp_aplicar_festivos_grupo_interno, @soloFuturas = 0)
-- en la misma transaccion del llamador: toda sesion creada en un dia festivo nace cancelada. Una sesion futura que se
-- borra porque ya no encaja en el horario pierde antes su SesionCancelacion. Las canceladas que siguen encajando no se
-- borran ni se recrean (idempotencia por grupo, inicio y fin).
-- DEC-081: despues de los festivos aplica los dias de receso academico del periodo (usp_cancelar_sesiones_receso_interno). B.2 agrega la condicion NOT EXISTS TomaAsistencia.
-- SKILLS-BD lote 13 (2026-11-26): la inicializacion de las salidas pasa de la cabecera al cuerpo (PASO 0), PASO n, IF con
-- BEGIN/END, IIF en lugar de COALESCE y lecturas sin bloqueo por vistas uv_* (antes, las tablas). La lectura con UPDLOCK, HOLDLOCK
-- del correlativo y las escrituras (DELETE de SesionCancelacion y Sesion, INSERT en Sesion) siguen en las tablas. Mismo resultado.
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
    DECLARE @sesionesCanceladasReceso INT = 0;
    DECLARE @sesionesRecesoConAsistencia INT = 0;
    DECLARE @mensajeUsuarioReceso NVARCHAR(4000);
    DECLARE @mensajeTecnicoReceso NVARCHAR(4000);
    DECLARE @estadoReceso BIT;
    DECLARE @sesionesEliminables TABLE (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);

    DECLARE @slots TABLE (
        fecha       DATE      NOT NULL,
        inicioLocal DATETIME2 NOT NULL,
        finLocal    DATETIME2 NOT NULL,
        inicioUtc   DATETIME2 NULL,
        finUtc      DATETIME2 NULL
    );
BEGIN
    SET NOCOUNT ON;
    -- PASO 0: inicializacion de las salidas desde el catalogo (antes, entre AS y BEGIN)
    SELECT
        @sesionesCreadas = 0,
        @sesionesEliminadas = 0,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
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
            FROM dbo.uv_parametro
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
            FROM dbo.uv_grupo_registro g
            INNER JOIN dbo.uv_periodo_academico_fechas pa ON pa.id = g.idPeriodoAcademico
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
            INNER JOIN dbo.uv_horario_registro h ON h.idGrupo = @idGrupoDefecto
            INNER JOIN dbo.uv_dia d ON d.id = h.idDia
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

        -- PASO 4: franjas a UTC; solo lo que aun no empezo
        IF @estadoResultado = 1
        BEGIN
            UPDATE @slots
            SET inicioUtc = CAST(inicioLocal AT TIME ZONE @zonaHorariaSqlServer AT TIME ZONE 'UTC' AS DATETIME2),
                finUtc = CAST(finLocal AT TIME ZONE @zonaHorariaSqlServer AT TIME ZONE 'UTC' AS DATETIME2);

            -- Solo lo que aun no empezo: el pasado no se genera ni se toca
            DELETE FROM @slots WHERE inicioUtc <= @ahoraUtc;

            -- PASO 5: Sesiones futuras generadas que ya no encajan en el horario y no tienen asistencia ni clasificacion.
            --         CULM-001 B.1: antes se borra su SesionCancelacion (una sesion que deja de existir pierde su cancelacion).
            INSERT INTO @sesionesEliminables (id)
            SELECT s.id
            FROM dbo.uv_sesion_registro s
            WHERE s.idGrupo = @idGrupoDefecto
              AND s.fechaHoraInicio > @ahoraUtc
              AND s.procedenciaTemporal = N'UTC_GENERADOR'
              AND NOT EXISTS (SELECT 1 FROM @slots x WHERE x.inicioUtc = s.fechaHoraInicio AND x.finUtc = s.fechaHoraFin)
              AND NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_registro a WHERE a.idSesion = s.id)
              AND NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia_registro t WHERE t.idSesion = s.id)
              AND NOT EXISTS (SELECT 1 FROM dbo.uv_sesion_procedencia_clasificacion_registro c WHERE c.idSesion = s.id);

            DELETE sc
            FROM dbo.SesionCancelacion sc
            INNER JOIN @sesionesEliminables e ON e.id = sc.sesion;

            DELETE s
            FROM dbo.Sesion s
            INNER JOIN @sesionesEliminables e ON e.id = s.id;
            SET @sesionesEliminadas = @@ROWCOUNT;

            -- PASO 6: Sesiones que faltan, con correlativo protegido contra carreras con usp_crear_sesion
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
                       numero = IIF(@maxNumeroSesion IS NULL, 0, @maxNumeroSesion) + ROW_NUMBER() OVER (ORDER BY x.inicioUtc)
                FROM @slots x
                WHERE NOT EXISTS (
                    SELECT 1 FROM dbo.uv_sesion_registro e
                    WHERE e.idGrupo = @idGrupoDefecto AND e.fechaHoraInicio = x.inicioUtc AND e.fechaHoraFin = x.finUtc)
            ) n;
            SET @sesionesCreadas = @@ROWCOUNT;

            -- PASO 7 (CULM-001 B.1): festivos de las sesiones del grupo, en la misma transaccion del llamador
            EXEC dbo.usp_aplicar_festivos_grupo_interno
                @idGrupo = @idGrupoDefecto,
                @soloFuturas = 0,
                @idCorrelacion = @idCorrelacionDefecto,
                @idUsuarioEjecutor = NULL,
                @sesionesCanceladas = @sesionesCanceladasFestivo OUTPUT,
                @sesionesConAsistencia = @sesionesFestivoConAsistencia OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            -- PASO 8 (DEC-081): dias de receso academico activos del periodo; un festivo ya aplicado gana. Si falla, informa su mensaje
            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_cancelar_sesiones_receso_interno
                    @idGrupo = @idGrupoDefecto,
                    @idReceso = NULL,
                    @soloFuturas = 0,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @idUsuarioEjecutor = NULL,
                    @sesionesCanceladas = @sesionesCanceladasReceso OUTPUT,
                    @sesionesConAsistencia = @sesionesRecesoConAsistencia OUTPUT,
                    @mensajeUsuarioResultado = @mensajeUsuarioReceso OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoReceso OUTPUT,
                    @estadoResultado = @estadoReceso OUTPUT;

                IF @estadoReceso = 0
                BEGIN
                    SELECT @mensajeUsuarioResultado = @mensajeUsuarioReceso, @mensajeTecnicoResultado = @mensajeTecnicoReceso, @estadoResultado = 0;
                END
            END
        END
    END TRY
    BEGIN CATCH
        -- PASO 9: error no controlado (SYS_001). Sin transaccion propia: la revierte el llamador
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
