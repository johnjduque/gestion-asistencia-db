USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_asociar_asignatura_plan_interno]   (INTERNO: DENY EXECUTE al runtime)
-- CULM-001 B2NM (DEC-019, R1, R3): crea o reactiva el vinculo (asignatura, semestre de un plan) con su caracter.
--   * Resuelve el SemestrePlanEstudio por plan + numero de semestre (PLA_004 si no existe).
--   * Resuelve el caracter activo por codigo; con @codigoCaracter NULL lee ASIGNATURA_PLAN/CARACTER_DEFECTO (sin literales).
--     Un caracter inexistente o inactivo es ASI_007.
--   * Con UPDLOCK/HOLDLOCK: un vinculo activo en el mismo u otro semestre del plan es ASI_003; un vinculo inactivo en el mismo
--     semestre se reactiva (misma fila, conserva fechaVinculacionUtc, TD aceptada); si no, se inserta.
-- Sin transaccion propia: corre dentro de la del llamador (usp_crear_asignatura, usp_asociar_asignatura_plan).
-- SKILLS-BD lote 2 (2026-11-25): antes usp_internal_asociar_asignatura_plan (renombrado, D3); DECLARE en la cabecera, PASO n,
-- sin COALESCE, semestre y caracter por vistas, TRY/CATCH con SYS_001 (si condeno la transaccion del llamador, relanza el error).
-- Los vinculos se leen en la tabla con UPDLOCK/HOLDLOCK (excepcion de lecturas con bloqueo).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_asociar_asignatura_plan_interno]
(
    @idAsignatura            UNIQUEIDENTIFIER,
    @idPlanEstudio           UNIQUEIDENTIFIER,
    @semestreNumero          INT,
    @codigoCaracter          NVARCHAR(3),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSpe             UNIQUEIDENTIFIER;
    DECLARE @idCaracter        UNIQUEIDENTIFIER;
    DECLARE @idVinculoInactivo UNIQUEIDENTIFIER;
    DECLARE @codigoEfectivo    NVARCHAR(3) = TRIM(@codigoCaracter);
    DECLARE @codigoRechazo     NVARCHAR(10);
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: respuesta inicial
    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

    BEGIN TRY
        -- PASO 2: caracter efectivo (vacio o NULL => ASIGNATURA_PLAN/CARACTER_DEFECTO)
        IF @codigoEfectivo IS NULL OR @codigoEfectivo = N''
        BEGIN
            SET @codigoEfectivo = CAST(dbo.ufn_obtener_parametro('ASIGNATURA_PLAN', 'CARACTER_DEFECTO') AS NVARCHAR(3));
        END

        -- PASO 3: semestre del plan (PLA_004), caracter activo (ASI_007) y vinculo activo previo en el plan (ASI_003)
        SELECT @idSpe = spe.id
        FROM dbo.uv_semestre_plan_estudio spe
        WHERE spe.idPlanEstudio = @idPlanEstudio AND spe.numeroSemestre = @semestreNumero;

        SELECT @idCaracter = c.id FROM dbo.uv_caracter_asignatura_plan c WHERE c.codigo = @codigoEfectivo AND c.estaActivo = 1;

        IF @idSpe IS NULL
        BEGIN
            SET @codigoRechazo = 'PLA_004';
        END
        ELSE IF @idCaracter IS NULL
        BEGIN
            SET @codigoRechazo = 'ASI_007';
        END
        ELSE IF EXISTS (SELECT 1
                        FROM dbo.AsignaturaPlanEstudio ape WITH (UPDLOCK, HOLDLOCK)
                        INNER JOIN dbo.uv_semestre_plan_estudio spe ON spe.id = ape.semestrePlanEstudio
                        WHERE ape.asignatura = @idAsignatura AND spe.idPlanEstudio = @idPlanEstudio AND ape.estaActivo = 1)
        BEGIN
            SET @codigoRechazo = 'ASI_003';
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

        -- PASO 4: reactiva el vinculo inactivo del mismo semestre o inserta uno nuevo
        IF @estadoResultado = 1
        BEGIN
            SELECT @idVinculoInactivo = ape.id
            FROM dbo.AsignaturaPlanEstudio ape WITH (UPDLOCK, HOLDLOCK)
            WHERE ape.asignatura = @idAsignatura AND ape.semestrePlanEstudio = @idSpe AND ape.estaActivo = 0;

            IF @idVinculoInactivo IS NOT NULL
            BEGIN
                UPDATE dbo.AsignaturaPlanEstudio
                SET estaActivo = 1, fechaDesvinculacionUtc = NULL, caracter = @idCaracter
                WHERE id = @idVinculoInactivo;
            END
            ELSE
            BEGIN
                INSERT INTO dbo.AsignaturaPlanEstudio (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc, fechaDesvinculacionUtc)
                VALUES (NEWID(), @idAsignatura, @idSpe, @idCaracter, 1, SYSUTCDATETIME(), NULL);
            END
        END
    END TRY
    BEGIN CATCH
        -- PASO 5: error. Sin transaccion propia: la revierte el llamador
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
