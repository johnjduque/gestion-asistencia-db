USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_alertas_estudiante (CULM-001 C.1, HU026C/HU013; CONTRACT §2.5.3, SUPUESTO-C-13, N-3)
--
-- READ_QUERY_RESULTSET paginado (THROW 51000 si la validacion falla). RBAC ESTUDIANTE: solo sus alertas (todas sus matriculas,
-- tambien CI). @idGrupo sin matricula propia -> SEC_002. @soloVigentes = 1 -> alertas vigentes de matriculas activas (contador del
-- menu); @soloNoLeidas -> fechaLecturaUtc IS NULL. Columnas de uv_alerta_inasistencia sin ids de usuario ni de docente, mas
-- porcentajeActual, umbralPerdidaActual y totalRegistros. Nunca columnas de la revision. Orden estaLeida ASC, fechaCruceUtc DESC.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_alertas_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 20,
    @soloNoLeidas      BIT = 0,
    @soloVigentes      BIT = 0,
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
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
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
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ESTUDIANTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1 AND @idGrupo IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg INNER JOIN dbo.Estudiante e ON e.id = eg.estudiante WHERE eg.grupo = @idGrupo AND e.usuario = @idUsuarioDefecto)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SEC_002', @p_param1 = 'Grupo del estudiante',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    SELECT
        id = a.id, idEstudianteGrupo = a.idEstudianteGrupo, idEstudiante = a.idEstudiante, nombreCompletoEstudiante = a.nombreCompletoEstudiante,
        idGrupo = a.idGrupo, codigoGrupo = a.codigoGrupo, nombreGrupo = a.nombreGrupo, idAsignatura = a.idAsignatura, nombreAsignatura = a.nombreAsignatura,
        idPeriodoAcademico = a.idPeriodoAcademico, codigoEstadoMatricula = a.codigoEstadoMatricula,
        idTipo = a.idTipo, codigoTipo = a.codigoTipo, nombreTipo = a.nombreTipo, nivel = a.nivel, codigoMensajeUsuario = a.codigoMensajeUsuario,
        idEstado = a.idEstado, codigoEstado = a.codigoEstado, estaVigente = a.estaVigente,
        porcentajeCruce = a.porcentajeCruce, umbralCruce = a.umbralCruce, horasFaltaCruce = a.horasFaltaCruce, horasDictadasCruce = a.horasDictadasCruce,
        fechaCruceUtc = a.fechaCruceUtc, porcentajeUltimaEvaluacion = a.porcentajeUltimaEvaluacion, fechaUltimaEvaluacionUtc = a.fechaUltimaEvaluacionUtc,
        fechaLecturaUtc = a.fechaLecturaUtc, estaLeida = a.estaLeida,
        porcentajeActual = r.porcentajeInasistencia,
        umbralPerdidaActual = r.umbralPerdida,
        totalRegistros = COUNT(1) OVER()
    FROM dbo.uv_alerta_inasistencia a
    LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo r ON r.idEstudianteGrupo = a.idEstudianteGrupo
    WHERE a.idUsuarioEstudiante = @idUsuarioDefecto
      AND (@idGrupo IS NULL OR a.idGrupo = @idGrupo)
      AND (@soloNoLeidas IS NULL OR @soloNoLeidas = 0 OR a.fechaLecturaUtc IS NULL)
      AND (@soloVigentes IS NULL OR @soloVigentes = 0 OR (a.estaVigente = 1 AND a.codigoEstadoMatricula = @codigoInscrita))
    ORDER BY a.estaLeida ASC, a.fechaCruceUtc DESC, a.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
