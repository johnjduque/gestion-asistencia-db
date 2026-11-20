USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_materia_estudiante (CULM-001 D.1, HU026B; CONTRACT §2.2, DEC-044 (2))
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001,
-- PAG_001). Sesiones de GET /api/v1/estudiante/materias/{materiaId}/sesiones. RBAC ESTUDIANTE; el ambito esta dentro del SP:
-- solo las matriculas del ejecutor con el estado de MATRICULA/ESTADO_INSCRITA en los grupos de la asignatura @idMateria
-- (los grupos I, CI, CVP y F no devuelven filas: cambio intencional de DEC-022 §3; una materia ajena devuelve 0 filas).
-- Columnas: id, nombre, numero, codigo, numeroSemana, idGrupo, codigoGrupo, nombreGrupo, fechaHoraInicio, fechaHoraFin
-- (las de la consulta que sustituye), fechaLimiteJustificacionUtc, plazoJustificacionVigente y totalRegistros
-- (COUNT(1) OVER()). Paginacion: @numeroPagina >= 1 y @tamanoPagina entre 1 y PAGINACION/TAMANO_MAXIMO. Solo lectura.
-- CIERRE-W2B: orden determinista y cronologico: fechaHoraInicio ASC, numero ASC, id ASC (el mismo criterio que antes aplicaba la
-- pantalla en el cliente, con el identificador como desempate estable: dos paginas nunca repiten ni saltan filas). Parametro
-- opcional @idGrupo (NULL = todos los grupos de la asignatura en los que el estudiante esta inscrito): un grupo en el que el
-- ejecutor no esta inscrito devuelve 0 filas, igual que una materia ajena.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_materia_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idMateria         UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 100,
    @idGrupo           UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @codigoInscrita       NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

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
    IF @estadoResultado = 1 AND @idMateria IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idMateria',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ESTUDIANTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
            OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    -- PERF-EST-MM: primero se filtran las matriculas inscritas del ejecutor en la materia (y el grupo opcional), se cuentan y se
    -- toma la pagina con las columnas baratas; la fecha limite (ufn_calcular_fecha_limite_justificacion_conjunto, la misma regla
    -- de la vista) se calcula solo para las filas de la pagina. Mismas columnas, mismo orden, mismo total y mismo plazo que
    -- cuando se leian fechaLimiteJustificacionUtc / plazoJustificacionVigente de uv_sesion_estudiante_reclamo.
    SELECT
        id                          = pag.idSesion,
        nombre                      = pag.nombre,
        numero                      = pag.numero,
        codigo                      = pag.codigo,
        numeroSemana                = pag.numeroSemana,
        idGrupo                     = pag.idGrupo,
        codigoGrupo                 = pag.codigoGrupo,
        nombreGrupo                 = pag.nombreGrupo,
        fechaHoraInicio             = pag.fechaHoraInicio,
        fechaHoraFin                = pag.fechaHoraFin,
        fechaLimiteJustificacionUtc = lim.fechaLimiteUtc,
        plazoJustificacionVigente   = CAST(IIF(pag.estaCancelada = 0 AND lim.fechaLimiteUtc IS NOT NULL
                                               AND SYSUTCDATETIME() < lim.fechaLimiteUtc, 1, 0) AS BIT),
        totalRegistros              = pag.totalRegistros
    FROM (
        SELECT  r.idSesion, r.nombre, r.numero, r.codigo, r.numeroSemana, r.idGrupo, r.codigoGrupo, r.nombreGrupo,
                r.fechaHoraInicio, r.fechaHoraFin, r.estaCancelada,
                totalRegistros = COUNT(1) OVER()
        FROM dbo.uv_sesion_estudiante_reclamo r
        INNER JOIN dbo.Estudiante e ON e.id = r.idEstudiante
        WHERE e.usuario = @idUsuarioDefecto
          AND r.idAsignatura = @idMateria
          AND r.codigoEstadoEstudiante = @codigoInscrita
          AND (@idGrupo IS NULL OR r.idGrupo = @idGrupo)
        ORDER BY r.fechaHoraInicio ASC, r.numero ASC, r.idSesion ASC
        OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY
    ) pag
    CROSS APPLY dbo.ufn_calcular_fecha_limite_justificacion_conjunto(pag.fechaHoraFin) lim
    ORDER BY pag.fechaHoraInicio ASC, pag.numero ASC, pag.idSesion ASC;
END;
GO
