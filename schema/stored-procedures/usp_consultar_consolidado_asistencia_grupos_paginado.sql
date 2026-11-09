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
