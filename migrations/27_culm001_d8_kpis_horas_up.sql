USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION UP 27: CULM-001 D.8 - comparativas, tendencia y consolidado por HORAS (CONTRACT D 9.2; HU061, HU103, HU134, HU139)
-- Crea o altera los cuatro SP diferidos por B (SUPUESTO-B-23) con la formula por horas (DEC-012, DEC-024) y columnas nuevas AL FINAL:
--   usp_consultar_comparativa_facultades / usp_consultar_comparativa_programas_facultad: horasDictadas, horasFalta (DECIMAL(12,2), horas)
--   usp_consultar_tendencia_ausentismo: horasDictadasEstudiante, horasFalta (DECIMAL(14,2), horas-estudiante)
--   usp_consultar_consolidado_asistencia_grupos_paginado: horasDictadas (DECIMAL(12,2), horas del grupo), porcentajeExcusa,
--   porcentajeSinRegistro (DECIMAL(5,2)); los cuatro porcentajes suman 100.00 (R-1)
-- y leen el estado de matricula de MATRICULA/ESTADO_INSCRITA (sin literal). Sin cambios de datos ni de permisos (CREATE OR ALTER conserva
-- los GRANT). Idempotente. El texto de los SP es el de schema/stored-procedures (el que despliega deploy_schema.ps1).
-- ============================================================================
PRINT 'MIGRACION 27 UP: KPI por horas (D.8)';
GO
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

USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_tendencia_ausentismo (HU134). READ_QUERY_RESULTSET sin paginar. Solo lectura.
-- Serie temporal del ausentismo del periodo por SEMANA (calendario, inicia el lunes) o MES, segun la hora local institucional
-- (parametro TIEMPO/ZONA_HORARIA_SQLSERVER) del inicio de la sesion. Solo sesiones vencidas con registro; solo intervalos con datos.
-- Ausentismo del intervalo = faltas SJC / sesiones-estudiante (matriculas activas de cada sesion ejecutada), igual que los KPIs.
-- CULM-001 D.8 (CONTRACT D 9.2, DEC-012/DEC-024, HU134): porcentajeAusentismo por HORAS = ROUND(100 x SUM(horasFalta) /
-- SUM(horasSesion x matriculas activas de la sesion), 2) (NULL si el denominador es 0); las sesiones canceladas no cuentan (salen de
-- uv_cumplimiento_sesion_grupo). sesionesEjecutadas y faltasSinJustaCausa siguen en sesiones-estudiante. Columnas nuevas al final:
-- horasDictadasEstudiante y horasFalta (horas-estudiante, 2 decimales).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_tendencia_ausentismo]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @granularidad       NVARCHAR(6)      = N'SEMANA'
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_institucion_administrador_interno)
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idInstitucion = @idInstitucion OUTPUT;

    DECLARE @g NVARCHAR(6) = UPPER(TRIM(ISNULL(@granularidad, N'SEMANA')));
    -- PASO 2: Validacion de negocio (GEN_002)
    IF @g NOT IN (N'SEMANA', N'MES')
    BEGIN
        SET @msgP1 = CAST(N'granularidad' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 3: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_institucion_interno)
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @zona NVARCHAR(100) = COALESCE(
        (SELECT TOP 1 valor FROM dbo.CatalogoParametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1),
        'SA Pacific Standard Time');

    -- PASO 4: Consulta y retorno de resultados
    WITH ejecutadas AS (
        SELECT  c.idSesion, c.idGrupo, c.horasSesion,
                fechaLocal = CAST(c.fechaHoraInicio AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE)
        FROM    dbo.uv_cumplimiento_sesion_grupo c
        WHERE   EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
                        WHERE gp.idGrupo = c.idGrupo AND p.idInstitucion = @idInstitucion) AND c.idPeriodoAcademico = @idPeriodo
          AND   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
    ),
    activos AS (
        SELECT idGrupo, n = COUNT(*) FROM dbo.uv_estudiante_grupo WHERE codigoEstadoEstudiante = @codigoInscrita GROUP BY idGrupo
    ),
    faltas AS (
        -- CULM-001 B.2 (CONTRACT 2.9): una falta por estudiante y sesion segun el estado consolidado (uv_asistencia_sesion_horas);
        -- CULM-001 D.8: ademas las horas de falta sin justa causa de esas matriculas activas.
        SELECT  h.idSesion, f = SUM(IIF(h.tieneFaltaSinJustaCausa = 1, 1, 0)), hf = CAST(SUM(h.horasFalta) AS DECIMAL(19,6))
        FROM    dbo.uv_asistencia_sesion_horas h
        INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = h.idEstudianteGrupo AND eg.codigoEstadoEstudiante = @codigoInscrita
        GROUP BY h.idSesion
    ),
    intervalo AS (
        SELECT  e.idSesion,
                inicio = CASE @g WHEN N'MES' THEN DATEFROMPARTS(YEAR(e.fechaLocal), MONTH(e.fechaLocal), 1)
                                 ELSE DATEADD(DAY, -(DATEDIFF(DAY, '19000101', e.fechaLocal) % 7), e.fechaLocal) END,
                fin = CASE @g WHEN N'MES' THEN EOMONTH(e.fechaLocal)
                              ELSE DATEADD(DAY, 6, DATEADD(DAY, -(DATEDIFF(DAY, '19000101', e.fechaLocal) % 7), e.fechaLocal)) END,
                sesionesEstudiante = ISNULL(ac.n, 0),
                faltas = ISNULL(fa.f, 0),
                horasDictadasEstudiante = CAST(e.horasSesion * ISNULL(ac.n, 0) AS DECIMAL(19,6)),
                horasFalta = ISNULL(fa.hf, 0)
        FROM    ejecutadas e
        LEFT JOIN activos ac ON ac.idGrupo = e.idGrupo
        LEFT JOIN faltas fa ON fa.idSesion = e.idSesion
    )
    -- PASO 5: Consulta y retorno de resultados
    SELECT
        inicioIntervalo = inicio,
        finIntervalo = fin,
        sesionesEjecutadas = SUM(sesionesEstudiante),
        faltasSinJustaCausa = SUM(faltas),
        porcentajeAusentismo = CAST(IIF(SUM(horasDictadasEstudiante) = 0, NULL, ROUND(100.0 * SUM(horasFalta) / SUM(horasDictadasEstudiante), 2)) AS DECIMAL(5,2)),
        horasDictadasEstudiante = CAST(SUM(horasDictadasEstudiante) AS DECIMAL(14,2)),
        horasFalta = CAST(SUM(horasFalta) AS DECIMAL(14,2))
    FROM intervalo
    GROUP BY inicio, fin
    ORDER BY inicio ASC;
END;
GO

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
            porcentajeSinRegistro   = CAST(q.sinRegistro AS DECIMAL(5,2))
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

