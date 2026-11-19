USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- SES-GEN-01: previsualizacion de solo lectura del horario propuesto de un grupo (nuevo o existente). No escribe ni abre transaccion.
-- Calcula, con la misma definicion de ranuras que usp_precargar_sesiones_grupo_interno (mismo dia de semana, mismo fuso institucional,
-- mismo festivo), las sesiones del periodo, las horas semanales y del periodo, el efecto de los festivos y del inicio tardio, y los
-- conflictos del horario con las reglas de usp_guardar_horarios_grupo (HOR_002, HOR_003, HOR_006, HOR_007, HOR_008, HOR_009) y la
-- advertencia de la materia sin horas (HOR_013). Los conflictos son DATOS (BLOQUEANTE / ADVERTENCIA / INFORMATIVO); un insumo invalido,
-- un recurso inexistente o fuera de ambito se rechazan con THROW 51000 (mismo contrato que las lecturas paginadas): VAL_001, VAL_002,
-- HOR_004, ASI_010, PER_010, SEC_001, SEC_002, GEN_001/DOC_*.
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
                SET @idDocenteRes = COALESCE(@idDocente, @idDocenteRes);
        END
        ELSE
        BEGIN
            SELECT @idAsignaturaRes = @idAsignatura, @idPeriodoRes = @idPeriodoAcademico, @idDocenteRes = @idDocente;
            IF @idAsignaturaRes IS NULL OR @idPeriodoRes IS NULL OR @idDocenteRes IS NULL
                SET @codigoRechazo = 'VAL_001';
        END
    END

    -- PASO 3: asignatura (VAL_002), B1 (ASI_010: activa, vinculada a un plan activo y todos sus programas coordinados por el ejecutor)
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
    BEGIN
        SELECT @codigoAsignatura = a.codigo, @nombreAsignatura = a.nombre, @horasSemanalesMateria = a.horasSemanales
        FROM dbo.uv_asignatura a WHERE a.id = @idAsignaturaRes;

        IF @codigoAsignatura IS NULL
            SELECT @codigoRechazo = 'VAL_002', @paramRechazo = N'Asignatura';
        ELSE IF NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura a WHERE a.id = @idAsignaturaRes AND a.estaActivaAsignatura = 1)
             OR NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
                            WHERE v.idAsignatura = @idAsignaturaRes AND v.estaActivoVinculo = 1 AND v.estaActivoPlan = 1)
             OR EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
                        WHERE v.idAsignatura = @idAsignaturaRes AND v.estaActivoVinculo = 1 AND v.estaActivoPlan = 1
                          AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto) cp WHERE cp.idPrograma = v.idPrograma))
            SET @codigoRechazo = 'ASI_010';
    END

    -- PASO 4: periodo (VAL_002) de la institucion del coordinador, no terminado ni cerrado (PER_010)
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
    BEGIN
        SELECT @nombrePeriodo = pa.nombre, @estadoPeriodo = pa.estado, @fechaInicioPeriodo = pa.fechaInicio, @fechaFinPeriodo = pa.fechaFin
        FROM dbo.uv_periodo_academico pa WHERE pa.id = @idPeriodoRes;

        IF @nombrePeriodo IS NULL
            SELECT @codigoRechazo = 'VAL_002', @paramRechazo = N'PeriodoAcademico';
        ELSE IF @estadoPeriodo = 'CERRADO'
             OR EXISTS (SELECT 1 FROM dbo.PeriodoAcademico p WHERE p.id = @idPeriodoRes AND p.fechaCierreUtc IS NOT NULL)
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
    FROM dbo.CatalogoParametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1;
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
        LEFT JOIN dbo.DiaFestivo df ON df.estaActivo = 1 AND df.fecha = s.fecha;
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
               CAST(IIF(EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = s.id)
                        OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id)
                        OR EXISTS (SELECT 1 FROM dbo.SesionProcedenciaClasificacion c WHERE c.sesion = s.id), 1, 0) AS BIT),
               CAST(IIF(EXISTS (SELECT 1 FROM @slots x WHERE x.inicioUtc = s.fechaHoraInicio AND x.finUtc = s.fechaHoraFin), 1, 0) AS BIT)
        FROM dbo.Sesion s WHERE s.grupo = @idGrupo;

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
