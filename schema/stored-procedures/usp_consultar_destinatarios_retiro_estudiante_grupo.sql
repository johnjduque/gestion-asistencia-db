USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_retiro_estudiante_grupo  (HU051)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (los parametros invalidos se propagan con THROW).
-- Destinatarios del aviso de retiro: el ESTUDIANTE retirado, el DOCENTE titular del grupo y el COORDINADOR del
-- programa (Grupo -> Asignatura -> SemestrePlanEstudio -> PlanEstudio -> Programa.coordinador). Solo el docente
-- titular obtiene filas (otro ejecutor => 0 filas). No exige matricula activa: se consulta despues del retiro.
-- El correo es dato de uso interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs.
-- ============================================================================
-- SKILLS-BD lote 7 (2026-11-26): DECLARE en la cabecera, PASO n, TRY/CATCH de lectura y lecturas por uv_grupo,
-- uv_docente_identidad, uv_programa, uv_coordinador_identidad, uv_estudiante_* y uv_usuario (antes, las tablas); mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_retiro_estudiante_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idEstudiante            UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY

        -- PASO 1: Validar el identificador de correlacion y el ejecutor (VAL_001)
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END

        -- PASO 2: Rechazo de validacion
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 3: Destinatarios del aviso (estudiante, docente titular y coordinadores de los programas comunes)
        ;WITH contexto AS (
            SELECT g.id AS idGrupo, g.codigo AS codigoGrupo, g.nombre AS nombreGrupo, g.nombreAsignatura AS nombreAsignatura,
                   d.idUsuario AS usuarioDocente, c.idUsuario AS usuarioCoordinador, e.idUsuario AS usuarioEstudiante
            FROM dbo.uv_grupo g
            INNER JOIN dbo.uv_docente_identidad d     ON d.id = g.idDocente
            INNER JOIN dbo.uv_grupo_programa gpx      ON gpx.idGrupo = g.id   -- CULM-001 B2NM: vigencia S1
            INNER JOIN dbo.uv_programa pr             ON pr.id = gpx.idPrograma
            INNER JOIN dbo.uv_coordinador_identidad c ON c.id = pr.idCoordinador
            INNER JOIN dbo.uv_estudiante_grupo eg     ON eg.idGrupo = g.id AND eg.idEstudiante = @idEstudiante
            INNER JOIN dbo.uv_estudiante_identidad e  ON e.id = eg.idEstudiante
            WHERE g.id = @idGrupo AND d.idUsuario = @idUsuarioDefecto
              -- CULM-001 B2NM: coordinadores de los programas del estudiante que comparten el grupo
              AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa epx WHERE epx.idEstudiante = eg.idEstudiante AND epx.idPrograma = pr.id)
        ),
        destinatarios AS (
            SELECT DISTINCT orden = 1, rolDestinatario = 'ESTUDIANTE', idUsuario = usuarioEstudiante, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
            UNION ALL
            SELECT DISTINCT 2, 'DOCENTE', usuarioDocente, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
            UNION ALL
            SELECT DISTINCT 3, 'COORDINADOR', usuarioCoordinador, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
        )
        SELECT
            rolDestinatario  = CAST(dst.rolDestinatario AS VARCHAR(20)),
            idUsuario        = dst.idUsuario,
            nombreCompleto   = CAST(CONCAT_WS(N' ',
                                   NULLIF(TRIM(u.primerNombre), N''),
                                   NULLIF(TRIM(u.segundoNombre), N''),
                                   NULLIF(TRIM(u.primerApellido), N''),
                                   NULLIF(TRIM(u.segundoApellido), N'')) AS NVARCHAR(400)),
            correo           = u.correo,
            idGrupo          = dst.idGrupo,
            codigoGrupo      = dst.codigoGrupo,
            nombreGrupo      = dst.nombreGrupo,
            nombreAsignatura = dst.nombreAsignatura
        FROM destinatarios dst
        INNER JOIN dbo.uv_usuario u ON u.id = dst.idUsuario
        ORDER BY dst.orden ASC;
    END TRY
    BEGIN CATCH
        -- PASO 4: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
