USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- CULM-001 D.9-a (CONTRACT D §11.1/§11.2, F-DEC-003): detalle de un grupo de la facultad del decano ejecutor.
-- Mismas columnas que usp_consultar_grupos_facultad_paginado (sin totalRegistros). El grupo inexistente y el grupo que no tiene
-- ningun programa en la facultad del decano son indistinguibles: THROW con SEC_002 (403, [SUPUESTO-D-14]); asi el decano no
-- puede averiguar que existen grupos de otras facultades. Solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador.
-- Resultset: READ_QUERY_RESULTSET (0 o 1 fila).
-- =============================================================================
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): PASO n, IF con BEGIN/END, facultad y decano por uv_facultad_registro y uv_decano_identidad (antes, las
-- tablas) y TRY/CATCH de lectura que relanza (antes, sin TRY).
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_grupo_facultad_detalle]
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
    DECLARE @idFacultad UNIQUEIDENTIFIER;
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor y grupo obligatorios (VAL_001)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idGrupo IS NULL)
        BEGIN
            SET @codigoRechazo = 'VAL_001';
        END

        -- PASO 3: facultad del decano que contiene un programa del grupo (SEC_002)
        IF @codigoRechazo IS NULL AND @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idFacultad = f.id
            FROM dbo.uv_facultad_registro f
            INNER JOIN dbo.uv_decano_identidad d ON d.id = f.idDecano
            WHERE d.idUsuario = @idUsuarioEjecutor
              AND EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
                          WHERE gp.idGrupo = @idGrupo AND p.idFacultad = f.id)
            ORDER BY f.id;
            IF @idFacultad IS NULL
            BEGIN
                SET @codigoRechazo = 'SEC_002';
            END
        END

        -- PASO 4: rechazo de validacion: se propaga al llamador
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

        -- PASO 5: detalle del grupo y programas de la facultad
        SELECT
            idGrupo                  = g.id,
            codigo                   = g.codigo,
            nombre                   = g.nombre,
            idPeriodoAcademico       = g.idPeriodoAcademico,
            idAsignatura             = g.idAsignatura,
            nombreAsignatura         = g.nombreAsignatura,
            idDocente                = g.idDocente,
            capacidadMaximaPermitida = g.capacidadMaximaPermitida,
            estudiantesActivos       = g.estudiantesActivos,
            cuposDisponibles         = g.cuposDisponibles,
            grupoEstaHablitado       = g.grupoEstaHablitado,
            programas                = CAST((SELECT STRING_AGG(p.nombrePrograma, N', ') WITHIN GROUP (ORDER BY p.nombrePrograma)
                                             FROM dbo.uv_grupo_programa gp
                                             INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
                                             WHERE gp.idGrupo = g.id AND p.idFacultad = @idFacultad) AS NVARCHAR(1000))
        FROM dbo.uv_grupo g
        WHERE g.id = @idGrupo;
    END TRY
    BEGIN CATCH
        -- PASO 6: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
