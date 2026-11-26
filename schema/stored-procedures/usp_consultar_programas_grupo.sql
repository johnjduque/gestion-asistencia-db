USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- CULM-001 B2NM (S3 minimo): programas vigentes de un grupo, para el selector de la matricula manual y de la ventana QR.
-- Lo pueden usar el titular del grupo y el coordinador o decano con ambito sobre algun programa del grupo; si no, SEC_002 (403).
-- =============================================================================
-- SKILLS-BD lote 5 (2026-11-26): PASO n, IF con BEGIN/END, TRY/CATCH de lectura y titular por uv_grupo/uv_docente_identidad
-- (antes, las tablas); mismo resultado y codigos.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_programas_grupo]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idGrupo           UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoRechazo NVARCHAR(10);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion y el ejecutor
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            SET @codigoRechazo = 'VAL_001';
        END

        -- PASO 2: Validar el ambito (titular del grupo o coordinador/decano con ambito sobre algun programa del grupo)
        IF @codigoRechazo IS NULL AND @estadoResultado = 1
           AND NOT (EXISTS (SELECT 1 FROM dbo.uv_grupo g INNER JOIN dbo.uv_docente_identidad d ON d.id = g.idDocente
                            WHERE g.id = @idGrupo AND d.idUsuario = @idUsuarioEjecutor)
                    OR EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) pg
                               INNER JOIN dbo.ufn_programas_ambito_ejecutor(@idUsuarioEjecutor) amb ON amb.idPrograma = pg.idPrograma))
        BEGIN
            SET @codigoRechazo = 'SEC_002';
        END

        -- PASO 3: Rechazar con el mensaje del catalogo
        IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
        BEGIN
            IF @codigoRechazo IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo, @p_param1 = N'UsuarioEjecutor',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END;
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 4: Devolver los programas vigentes del grupo
        SELECT
            idPrograma     = p.id,
            nombrePrograma = p.nombrePrograma,
            idPlanEstudio  = pg.idPlanEstudio,
            inpPlanEstudio = pg.inpPlanEstudio
        FROM dbo.ufn_programas_grupo(@idGrupo) pg
        INNER JOIN dbo.uv_programa p ON p.id = pg.idPrograma
        ORDER BY p.nombrePrograma ASC, p.id ASC;
    END TRY
    BEGIN CATCH
        -- PASO 5: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
