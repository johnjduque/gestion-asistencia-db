USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_asegurar_estudiante_programa_grupo_interno]   (INTERNO: DENY EXECUTE al runtime)
-- CULM-001 B2NM (DEC-020, R7, S3): garantiza que la matricula de un estudiante en un grupo tenga al menos un
-- EstudiantePrograma en un programa del grupo (ufn_programas_grupo). Reglas, en este orden:
--   (1) si ya tiene vinculo con algun programa del grupo, lo devuelve y no crea nada;
--   (2) si no y el grupo tiene un unico programa, crea el vinculo con ese programa;
--   (3) si no y el grupo tiene varios, exige @idProgramaElegido entre los programas del grupo: EST_005 si falta,
--       EST_006 si es ajeno; y crea el vinculo.
-- Un grupo sin programa vigente (limitacion O-N10) no crea vinculo y devuelve @idProgramaResultado NULL.
-- Sin ROLLBACK propio: corre dentro de la transaccion del llamador. La unicidad se protege con UPDLOCK/HOLDLOCK sobre
-- EstudiantePrograma (y el indice unico UX_EstudiantePrograma_estudiante_programa como ultima defensa); esas lecturas van a
-- la tabla (excepcion de lecturas con bloqueo).
-- SKILLS-BD lote 2 (2026-11-25): antes usp_internal_asegurar_estudiante_programa_grupo (renombrado, D3); PASO n, IF con
-- BEGIN/END, un solo punto de salida y TRY/CATCH con SYS_001 (si condeno la transaccion del llamador, relanza el error).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_asegurar_estudiante_programa_grupo_interno]
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
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @totalProgramas INT;
    DECLARE @codigoRechazo  NVARCHAR(10);
    DECLARE @debeVincular   BIT = 0;
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: respuesta inicial
    SELECT
        @idProgramaResultado = NULL,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

    BEGIN TRY
        -- PASO 2: programas del grupo y vinculo previo con alguno de ellos (regla 1)
        SELECT @totalProgramas = COUNT(*) FROM dbo.ufn_programas_grupo(@idGrupo);

        SELECT TOP 1 @idProgramaResultado = ep.programa
        FROM dbo.EstudiantePrograma ep WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.ufn_programas_grupo(@idGrupo) pg ON pg.idPrograma = ep.programa
        WHERE ep.estudiante = @idEstudiante
        ORDER BY ep.programa;

        IF @idProgramaResultado IS NULL AND @totalProgramas = 1
        BEGIN
            -- PASO 3: un unico programa en el grupo (regla 2)
            SELECT @idProgramaResultado = pg.idPrograma FROM dbo.ufn_programas_grupo(@idGrupo) pg;
            SET @debeVincular = 1;
        END
        ELSE IF @idProgramaResultado IS NULL AND @totalProgramas > 1
        BEGIN
            -- PASO 4: varios programas: el programa elegido es obligatorio (EST_005) y debe ser del grupo (EST_006) (regla 3)
            IF @idProgramaElegido IS NULL
            BEGIN
                SET @codigoRechazo = 'EST_005';
            END
            ELSE IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) pg WHERE pg.idPrograma = @idProgramaElegido)
            BEGIN
                SET @codigoRechazo = 'EST_006';
            END
            ELSE
            BEGIN
                SET @idProgramaResultado = @idProgramaElegido;
                SET @debeVincular = 1;
            END
        END

        IF @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: crea el vinculo si no existe
        IF @debeVincular = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WITH (UPDLOCK, HOLDLOCK)
                           WHERE estudiante = @idEstudiante AND programa = @idProgramaResultado)
        BEGIN
            INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
            VALUES (NEWID(), @idEstudiante, @idProgramaResultado);
        END
    END TRY
    BEGIN CATCH
        -- PASO 6: error. Sin transaccion propia: la revierte el llamador
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        IF XACT_STATE() = -1
        BEGIN
            THROW;
        END
    END CATCH
END;
GO
