USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_internal_asociar_asignatura_plan]   (INTERNO: DENY EXECUTE al runtime)
-- CULM-001 B2NM (DEC-019, R1, R3): crea o reactiva el vinculo (asignatura, semestre de un plan) con su caracter.
--   * Resuelve el SemestrePlanEstudio por plan + numero de semestre (PLA_004 si no existe).
--   * Resuelve el caracter activo por codigo; con @codigoCaracter NULL lee ASIGNATURA_PLAN/CARACTER_DEFECTO (sin literales).
--     Un caracter inexistente o inactivo es ASI_007.
--   * Con UPDLOCK/HOLDLOCK: un vinculo activo en el mismo u otro semestre del plan es ASI_003; un vinculo inactivo en el mismo
--     semestre se reactiva (misma fila, conserva fechaVinculacionUtc, TD aceptada); si no, se inserta.
-- Sin transaccion propia: corre dentro de la del llamador (usp_crear_asignatura, usp_asociar_asignatura_plan).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_asociar_asignatura_plan]
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
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSpe UNIQUEIDENTIFIER, @idCaracter UNIQUEIDENTIFIER, @idVinculoInactivo UNIQUEIDENTIFIER;
    DECLARE @codigoEfectivo NVARCHAR(3) = COALESCE(NULLIF(TRIM(@codigoCaracter), N''),
                                                   CAST(dbo.ufn_obtener_parametro('ASIGNATURA_PLAN', 'CARACTER_DEFECTO') AS NVARCHAR(3)));
    DECLARE @codigoRechazo NVARCHAR(10);

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

    SELECT @idSpe = spe.id
    FROM dbo.SemestrePlanEstudio spe
    INNER JOIN dbo.Semestre s ON s.id = spe.semestre
    WHERE spe.planEstudio = @idPlanEstudio AND s.numero = @semestreNumero;

    SELECT @idCaracter = c.id FROM dbo.CaracterAsignaturaPlan c WHERE c.codigo = @codigoEfectivo AND c.estado = 1;

    IF @idSpe IS NULL
        SET @codigoRechazo = 'PLA_004';
    ELSE IF @idCaracter IS NULL
        SET @codigoRechazo = 'ASI_007';
    ELSE IF EXISTS (SELECT 1
                    FROM dbo.AsignaturaPlanEstudio ape WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                    WHERE ape.asignatura = @idAsignatura AND spe.planEstudio = @idPlanEstudio AND ape.estaActivo = 1)
        SET @codigoRechazo = 'ASI_003';

    IF @codigoRechazo IS NOT NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = @codigoRechazo,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
        RETURN;
    END

    SELECT @idVinculoInactivo = ape.id
    FROM dbo.AsignaturaPlanEstudio ape WITH (UPDLOCK, HOLDLOCK)
    WHERE ape.asignatura = @idAsignatura AND ape.semestrePlanEstudio = @idSpe AND ape.estaActivo = 0;

    IF @idVinculoInactivo IS NOT NULL
        UPDATE dbo.AsignaturaPlanEstudio
        SET estaActivo = 1, fechaDesvinculacionUtc = NULL, caracter = @idCaracter
        WHERE id = @idVinculoInactivo;
    ELSE
        INSERT INTO dbo.AsignaturaPlanEstudio (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc, fechaDesvinculacionUtc)
        VALUES (NEWID(), @idAsignatura, @idSpe, @idCaracter, 1, SYSUTCDATETIME(), NULL);
END;
GO
