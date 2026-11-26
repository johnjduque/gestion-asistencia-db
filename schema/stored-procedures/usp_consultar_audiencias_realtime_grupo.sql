USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_audiencias_realtime_grupo (CULM-001 C.1, F-TRX-006; CONTRACT §2.5.10, SUPUESTO-C-11, O-11)
--
-- Audiencias del SSE de un grupo para el usuario autenticado, en una fila: esDocenteTitular (Grupo.docente), esEstudianteActivo
-- (matricula MATRICULA/ESTADO_INSCRITA), esAmbitoLectura (programas del grupo en ufn_programas_ambito_ejecutor: coordinador -> sus
-- programas, decano -> los de su facultad; o administrador activo de la institucion del periodo). Sin RBAC por perfil: un grupo
-- inexistente o ajeno devuelve los tres en 0. THROW 51000 solo si faltan la correlacion o el ejecutor.
-- ============================================================================
-- SKILLS-BD lote 5 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, TRY/CATCH de lectura y lecturas por
-- uv_grupo/uv_docente_identidad/uv_estudiante_grupo/uv_periodo_academico (antes, las tablas); mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_audiencias_realtime_grupo]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idGrupo           UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion y los parametros obligatorios
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idGrupo IS NULL)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idGrupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 2: Resolver las tres audiencias del ejecutor sobre el grupo
        SELECT
            esDocenteTitular = CAST(IIF(EXISTS (SELECT 1 FROM dbo.uv_grupo g INNER JOIN dbo.uv_docente_identidad d ON d.id = g.idDocente
                                                WHERE g.id = @idGrupo AND d.idUsuario = @idUsuarioEjecutor), 1, 0) AS BIT),
            esEstudianteActivo = CAST(IIF(EXISTS (
                SELECT 1 FROM dbo.uv_estudiante_grupo eg
                INNER JOIN dbo.uv_estudiante_identidad e ON e.id = eg.idEstudiante
                WHERE eg.idGrupo = @idGrupo AND eg.codigoEstadoEstudiante = @codigoInscrita AND e.idUsuario = @idUsuarioEjecutor), 1, 0) AS BIT),
            esAmbitoLectura = CAST(IIF(
                EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) pg INNER JOIN dbo.ufn_programas_ambito_ejecutor(@idUsuarioEjecutor) a ON a.idPrograma = pg.idPrograma)
                OR EXISTS (SELECT 1 FROM dbo.uv_grupo g INNER JOIN dbo.uv_periodo_academico pa ON pa.id = g.idPeriodoAcademico
                           INNER JOIN dbo.uv_administrador ad ON ad.idInstitucion = pa.idInstitucion
                           WHERE g.id = @idGrupo AND ad.idUsuario = @idUsuarioEjecutor AND ad.estaActivoAdministrador = 1), 1, 0) AS BIT);
    END TRY
    BEGIN CATCH
        -- PASO 3: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
