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
-- C6 (DEC-077): al final del resultado (despues de totalRegistros, solo en este SP) se agregan nombreProgramaResponsable (programa
-- responsable del grupo, el mismo idPrograma/nombrePrograma de la fila) y nombreCoordinadorResolutor (nombre completo del coordinador
-- de ese programa, NULL si no tiene), para que el docente sepa quien resuelve cada solicitud.
-- Validacion compartida (correlacion, ejecutor, RBAC DOCENTE, PAG_001) en usp_validar_consulta_paginada_interno; THROW 51000 si falla.
-- ============================================================================
-- SKILLS-BD lote 13 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, lecturas por vistas uv_* (programa y docente por uv_programa_registro y uv_docente_identidad; IIF en lugar de ISNULL) y
-- TRY/CATCH de lectura que relanza (READ_QUERY_RESULTSET). Mismas columnas y mismas filas.
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

    BEGIN TRY
        -- PASO 1: ejecutor DOCENTE y paginacion
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuario, @idCorrelacion = @idCorrelacion, @codigoPerfilRequerido = 'DOCENTE',
            @numeroPagina = @numeroPagina, @tamanoPagina = @tamanoPagina,
            @idUsuarioValidado = @idUsuarioValidado OUTPUT, @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        -- PASO 2: restaurar el contexto de sesion previo
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        -- PASO 3: rechazo de validacion: se propaga al llamador
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 4: solicitudes de sesion del docente (una fila por sesion), paginadas
        SELECT  v.*, totalRegistros = COUNT(*) OVER(),
                nombreProgramaResponsable = CAST(v.nombrePrograma AS NVARCHAR(200)),
                nombreCoordinadorResolutor = CAST(ci.nombreCompleto AS NVARCHAR(400))
        FROM    dbo.uv_solicitud_sesion v
        LEFT JOIN dbo.uv_programa_registro pr ON pr.id = v.idPrograma
        LEFT JOIN dbo.uv_coordinador_identidad ci ON ci.id = pr.idCoordinador
        WHERE   v.idDocente IN (SELECT d.id FROM dbo.uv_docente_identidad d WHERE d.idUsuario = @idUsuarioValidado)
          AND   (@idGrupo IS NULL OR v.idGrupo = @idGrupo)
          AND   (IIF(@soloPendientes IS NULL, 1, @soloPendientes) = 0 OR v.pendienteAprobacion = 1)
          AND   v.idPrograma = (SELECT TOP 1 x.idPrograma FROM dbo.uv_solicitud_sesion x WHERE x.idSesion = v.idSesion ORDER BY x.nombrePrograma, x.idPrograma)
        ORDER BY v.fechaSolicitudUtc DESC, v.idSesion ASC
        OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
    END TRY
    BEGIN CATCH
        -- PASO 5: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
