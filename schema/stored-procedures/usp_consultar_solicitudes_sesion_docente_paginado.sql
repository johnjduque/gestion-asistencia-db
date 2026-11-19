USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_sesion_docente_paginado (ATA D6, HU030, HU047)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET paginado (PAG_001 + totalRegistros).
-- Solicitudes de sesion extraordinaria de los grupos donde el ejecutor es docente titular (uv_solicitud_sesion). Mismas columnas y
-- mismo orden que usp_consultar_solicitudes_sesion_coordinador_paginado (incluido idPrograma/nombrePrograma: el programa
-- alfabeticamente primero del grupo, una fila por sesion), fechaSolicitudUtc DESC. @soloPendientes = 1 (por defecto) deja las
-- solicitudes en espera de aval que no fueron canceladas; 0 incluye aprobadas, rechazadas y canceladas. @idGrupo ajeno: sin filas.
-- Validacion compartida (correlacion, ejecutor, RBAC DOCENTE, PAG_001) en usp_validar_consulta_paginada_interno; THROW 51000 si falla.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_sesion_docente_paginado]
(
    @idUsuario      UNIQUEIDENTIFIER,
    @soloPendientes BIT              = 1,
    @idGrupo        UNIQUEIDENTIFIER = NULL,
    @numeroPagina   INT              = 1,
    @tamanoPagina   INT              = 20,
    @idCorrelacion  UNIQUEIDENTIFIER
)
AS
    DECLARE @idUsuarioValidado       UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_validar_consulta_paginada_interno
        @idUsuarioEjecutor = @idUsuario, @idCorrelacion = @idCorrelacion, @codigoPerfilRequerido = 'DOCENTE',
        @numeroPagina = @numeroPagina, @tamanoPagina = @tamanoPagina,
        @idUsuarioValidado = @idUsuarioValidado OUTPUT, @offset = @offset OUTPUT,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT  v.*, totalRegistros = COUNT(*) OVER()
    FROM    dbo.uv_solicitud_sesion v
    WHERE   v.idDocente IN (SELECT d.id FROM dbo.Docente d WHERE d.usuario = @idUsuarioValidado)
      AND   (@idGrupo IS NULL OR v.idGrupo = @idGrupo)
      AND   (ISNULL(@soloPendientes, 1) = 0 OR v.pendienteAprobacion = 1)
      AND   v.idPrograma = (SELECT TOP 1 x.idPrograma FROM dbo.uv_solicitud_sesion x WHERE x.idSesion = v.idSesion ORDER BY x.nombrePrograma, x.idPrograma)
    ORDER BY v.fechaSolicitudUtc DESC, v.idSesion ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
