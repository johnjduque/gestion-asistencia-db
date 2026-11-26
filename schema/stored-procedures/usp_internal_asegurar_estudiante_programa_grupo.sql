USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_internal_asegurar_estudiante_programa_grupo]   (INTERNO: DENY EXECUTE al runtime)
-- CULM-001 B2NM (DEC-020, R7, S3): garantiza que la matricula de un estudiante en un grupo tenga al menos un
-- EstudiantePrograma en un programa del grupo (ufn_programas_grupo). Reglas, en este orden:
--   (1) si ya tiene vinculo con algun programa del grupo, lo devuelve y no crea nada;
--   (2) si no y el grupo tiene un unico programa, crea el vinculo con ese programa;
--   (3) si no y el grupo tiene varios, exige @idProgramaElegido entre los programas del grupo: EST_005 si falta,
--       EST_006 si es ajeno; y crea el vinculo.
-- Un grupo sin programa vigente (limitacion O-N10) no crea vinculo y devuelve @idProgramaResultado NULL.
-- Sin ROLLBACK propio: corre dentro de la transaccion del llamador. La unicidad se protege con UPDLOCK/HOLDLOCK sobre
-- EstudiantePrograma (y el indice unico UX_EstudiantePrograma_estudiante_programa como ultima defensa).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_asegurar_estudiante_programa_grupo]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idProgramaElegido       UNIQUEIDENTIFIER = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idProgramaResultado     UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @totalProgramas INT;

    SELECT
        @idProgramaResultado = NULL,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

    SELECT @totalProgramas = COUNT(*) FROM dbo.ufn_programas_grupo(@idGrupo);

    -- (1) vinculo previo con un programa del grupo
    SELECT TOP 1 @idProgramaResultado = ep.programa
    FROM dbo.EstudiantePrograma ep WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.ufn_programas_grupo(@idGrupo) pg ON pg.idPrograma = ep.programa
    WHERE ep.estudiante = @idEstudiante
    ORDER BY ep.programa;

    IF @idProgramaResultado IS NOT NULL OR @totalProgramas = 0
        RETURN;

    -- (2) un unico programa en el grupo
    IF @totalProgramas = 1
        SELECT @idProgramaResultado = pg.idPrograma FROM dbo.ufn_programas_grupo(@idGrupo) pg;
    ELSE
    BEGIN
        -- (3) varios programas: el programa elegido es obligatorio y debe ser del grupo
        IF @idProgramaElegido IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'EST_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) pg WHERE pg.idPrograma = @idProgramaElegido)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'EST_006',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            RETURN;
        END

        SET @idProgramaResultado = @idProgramaElegido;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WITH (UPDLOCK, HOLDLOCK)
                   WHERE estudiante = @idEstudiante AND programa = @idProgramaResultado)
        INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
        VALUES (NEWID(), @idEstudiante, @idProgramaResultado);
END;
GO
