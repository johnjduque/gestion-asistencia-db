USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_buscar_estudiante_por_documento_grupo (CULM-001 A.2-15; DEC-027; F-DOC-013; CONTRACT §8.2.3 A2-DB-9)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo, fuera de ambito o documento
-- invalido). Busqueda del estudiante a matricular a mano (GET /api/v1/grupos/{grupoId}/estudiantes/busqueda) y unica via
-- para resolver el estudiante de una matricula manual sin correo:
--   * Titularidad dentro del SP: el ejecutor debe ser el DOCENTE titular del grupo (Grupo.docente -> Docente.usuario);
--     si no, o el grupo no existe: THROW 51000 con DBCODE=SEC_002 (403).
--   * Documento nulo o @numeroIdentificacion <= 0: THROW 51000 con DBCODE=VAL_001 (400).
--   * Busqueda EXACTA por (Usuario.tipoIdIdentificacion, Usuario.numeroIdentificacion) de un usuario CON fila Estudiante
--     (un usuario que solo es docente, coordinador, decano o administrador da 0 filas). Sin LIKE y sin listar: 0 o 1 fila.
--   * Alcance institucional: solo devuelve al estudiante si no tiene vinculos (alta pendiente de matricula; excepcion
--     deliberada al fail-closed de DEC-031 §3, A2-C1) o si alguno de sus vinculos (EstudiantePrograma o EstudianteGrupo)
--     es de la institucion del grupo. Uno de otra institucion da 0 filas, igual que uno inexistente.
--   * Datos minimos: nombres, nombreCompleto, numeroIdentificacion, correoEnmascarado (primer caracter + '***' +
--     '@dominio'; el correo real nunca sale) y codigoEstadoMatriculaGrupo (su matricula en ESE grupo o NULL).
-- Solo lectura.
-- ============================================================================
-- SKILLS-BD lote 7 (2026-11-26): lecturas por uv_grupo, uv_docente_identidad, uv_usuario, uv_estudiante_identidad,
-- uv_estudiante_programa, uv_estudiante_grupo y uv_programa (antes, las tablas) y TRY/CATCH de lectura; mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_buscar_estudiante_por_documento_grupo]
(
    @idGrupo              UNIQUEIDENTIFIER,
    @idTipoIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion INT,
    @idCorrelacion        UNIQUEIDENTIFIER,
    @idUsuarioEjecutor    UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucionGrupo   UNIQUEIDENTIFIER;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio (VAL_001)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: titularidad del docente ejecutor sobre el grupo (SEC_002)
        IF @estadoResultado = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_grupo g
                           INNER JOIN dbo.uv_docente_identidad d ON d.id = g.idDocente
                           WHERE g.id = @idGrupo AND d.idUsuario = @idUsuarioEjecutor AND d.estaActivoUsuario = 1)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: documento obligatorio y positivo (VAL_001)
        IF @estadoResultado = 1 AND (@idTipoIdentificacion IS NULL OR @numeroIdentificacion IS NULL OR @numeroIdentificacion <= 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001', @p_param1 = 'numeroIdentificacion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 5: institucion del grupo
        SELECT @idInstitucionGrupo = p.idInstitucion
        FROM dbo.uv_grupo_programa gpx   -- CULM-001 B2NM: vigencia S1
        INNER JOIN dbo.uv_programa p ON p.id = gpx.idPrograma
        WHERE gpx.idGrupo = @idGrupo;

        -- PASO 6: busqueda exacta de un estudiante, con alcance institucional y datos minimos
        SELECT TOP 1
            idEstudiante               = e.id,
            primerNombre               = u.primerNombre,
            segundoNombre              = u.segundoNombre,
            primerApellido             = u.primerApellido,
            segundoApellido            = u.segundoApellido,
            nombreCompleto             = CAST(CONCAT(LTRIM(RTRIM(CONCAT(u.primerNombre, N' ', u.segundoNombre))), N' ',
                                             LTRIM(RTRIM(CONCAT(u.primerApellido, N' ', u.segundoApellido)))) AS NVARCHAR(400)),
            numeroIdentificacion       = u.numeroIdentificacion,
            correoEnmascarado          = CAST(IIF(CHARINDEX(N'@', u.correo) > 1,
                                             CONCAT(LEFT(u.correo, 1), N'***', SUBSTRING(u.correo, CHARINDEX(N'@', u.correo), LEN(u.correo))),
                                             CONCAT(LEFT(u.correo, 1), N'***')) AS NVARCHAR(120)),
            codigoEstadoMatriculaGrupo = (SELECT TOP 1 eg.codigoEstadoEstudiante FROM dbo.uv_estudiante_grupo eg
                                          WHERE eg.idEstudiante = e.id AND eg.idGrupo = @idGrupo
                                          ORDER BY eg.id)
        FROM dbo.uv_usuario u
        INNER JOIN dbo.uv_estudiante_identidad e ON e.idUsuario = u.id
        WHERE u.idTipoIdentificacion = @idTipoIdentificacion
          AND u.numeroIdentificacion = @numeroIdentificacion
          AND (
                -- sin vinculos: alta pendiente de matricula (A2-C1)
                (NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa ep WHERE ep.idEstudiante = e.id)
                 AND NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo eg WHERE eg.idEstudiante = e.id))
                -- algun vinculo en la institucion del grupo
                OR EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa ep
                           INNER JOIN dbo.uv_programa p ON p.id = ep.idPrograma
                           WHERE ep.idEstudiante = e.id AND p.idInstitucion = @idInstitucionGrupo)
                OR EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo eg
                           INNER JOIN dbo.uv_grupo_programa gpx ON gpx.idGrupo = eg.idGrupo   -- CULM-001 B2NM: vigencia S1
                           INNER JOIN dbo.uv_programa p ON p.id = gpx.idPrograma
                           WHERE eg.idEstudiante = e.id AND p.idInstitucion = @idInstitucionGrupo)
              )
        ORDER BY e.id;
    END TRY
    BEGIN CATCH
        -- PASO 7: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
