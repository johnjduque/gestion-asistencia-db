USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_sesion_coordinador_paginado (CULM-001 / DEC-065 (2); HU030, HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET paginado (PAG_001 + totalRegistros).
-- Solicitudes de sesion extraordinaria de los programas que coordina el usuario (uv_solicitud_sesion INTERSECT ufn_programas_coordinador),
-- una fila por sesion (en un grupo mixto, el programa alfabeticamente primero entre los que coordina el usuario), ordenadas por
-- fechaSolicitudUtc DESC. @soloPendientes = 1 (por defecto) deja solo las solicitudes en espera de aval que no fueron canceladas;
-- 0 incluye aprobadas, rechazadas y canceladas. Filtros opcionales por programa y por grupo. RBAC COORDINADOR dentro del SP
-- (THROW 51000 con el mensaje tecnico si falla). Paginacion normalizada (pagina >= 1; tamano 1..100, por defecto 20).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_sesion_coordinador_paginado]
(
    @idUsuario      UNIQUEIDENTIFIER,
    @soloPendientes BIT              = 1,
    @idPrograma     UNIQUEIDENTIFIER = NULL,
    @idGrupo        UNIQUEIDENTIFIER = NULL,
    @numeroPagina   INT              = 1,
    @tamanoPagina   INT              = 20,
    @idCorrelacion  UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuario, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @soloEnEspera BIT = IIF(@soloPendientes IS NULL, 1, @soloPendientes);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND @idUsuario IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuario',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto,
            @codigoPerfilRequerido = 'COORDINADOR',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    ;WITH ambito AS (
        SELECT  v.idSesion, v.nombreSesion, v.codigoSesion, v.idGrupo, v.nombreGrupo, v.nombreAsignatura,
                v.idPrograma, v.nombrePrograma, v.idDocente, v.nombreDocente, v.fechaHoraInicio, v.fechaHoraFin,
                v.estadoSolicitud, v.nombreEstadoSolicitud, v.fechaSolicitudUtc, v.fechaResolucionUtc, v.observacion,
                v.usuarioSolicitante, v.pendienteAprobacion, v.estaCancelada,
                rn = ROW_NUMBER() OVER (PARTITION BY v.idSesion ORDER BY v.nombrePrograma, v.idPrograma)
        FROM    dbo.uv_solicitud_sesion v
        WHERE   v.idPrograma IN (SELECT pc.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioDefecto) pc)
          AND   (@idPrograma IS NULL OR v.idPrograma = @idPrograma)
          AND   (@idGrupo IS NULL OR v.idGrupo = @idGrupo)
          AND   (@soloEnEspera = 0 OR v.pendienteAprobacion = 1)
    )
    SELECT  a.idSesion, a.nombreSesion, a.codigoSesion, a.idGrupo, a.nombreGrupo, a.nombreAsignatura,
            a.idPrograma, a.nombrePrograma, a.idDocente, a.nombreDocente, a.fechaHoraInicio, a.fechaHoraFin,
            a.estadoSolicitud, a.nombreEstadoSolicitud, a.fechaSolicitudUtc, a.fechaResolucionUtc, a.observacion,
            a.usuarioSolicitante, a.pendienteAprobacion, a.estaCancelada,
            totalRegistros = COUNT(*) OVER()
    FROM    ambito a
    WHERE   a.rn = 1
    ORDER BY a.fechaSolicitudUtc DESC, a.idSesion ASC
    OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
END;
GO
