USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_validar_gestion_asignatura_coordinador_interno]   (INTERNO)
-- REC2 + CULM-001 B2NM (DEC-019, S2, R8): valida que el ejecutor sea COORDINADOR activo y que pueda gestionar la asignatura.
--   * Sin @idPlanEstudio: basta coordinar ALGUN programa con vinculo activo de la asignatura (sin TOP 1). Con
--     @exigirTodosLosProgramas = 1 debe coordinar TODOS (datos de catalogo / estado global): si coordina solo algunos -> ASI_006.
--   * Con @idPlanEstudio: el plan debe ser de un programa que coordina (SEC_002) y la asignatura debe tener un vinculo
--     activo en ese plan (ASI_004).
-- Asignatura inexistente: VAL_002. Sin ningun programa coordinado con vinculo activo: SEC_002.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_gestion_asignatura_coordinador_interno]
(
    @idAsignatura            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @idPlanEstudio           UNIQUEIDENTIFIER = NULL,
    @exigirTodosLosProgramas BIT = 0
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaPlan           UNIQUEIDENTIFIER;
    DECLARE @totalProgramas           INT;
    DECLARE @totalCoordinados         INT;
    DECLARE @codigoRechazo            NVARCHAR(10);

BEGIN
    SET NOCOUNT ON;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;
    BEGIN TRY
        -- PASO 1: Ejecutor obligatorio
        IF @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: Perfil COORDINADOR activo
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Existencia de la asignatura
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @idAsignaturaDefecto)
            SET @codigoRechazo = 'VAL_002';

        -- PASO 4: Ambito
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            IF @idPlanEstudio IS NOT NULL
            BEGIN
                SELECT @idProgramaPlan = pe.programa FROM dbo.PlanEstudio pe WHERE pe.id = @idPlanEstudio;
                IF @idProgramaPlan IS NULL
                    SET @codigoRechazo = 'PLA_002';
                ELSE IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto) cp WHERE cp.idPrograma = @idProgramaPlan)
                    SET @codigoRechazo = 'SEC_002';
                ELSE IF NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape
                                    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                                    WHERE ape.asignatura = @idAsignaturaDefecto AND spe.planEstudio = @idPlanEstudio AND ape.estaActivo = 1)
                    SET @codigoRechazo = 'ASI_004';
            END
            ELSE
            BEGIN
                SELECT @totalProgramas = COUNT(DISTINCT v.idPrograma),
                       @totalCoordinados = COUNT(DISTINCT CASE WHEN cp.idPrograma IS NOT NULL THEN v.idPrograma END)
                FROM dbo.uv_asignatura_plan_estudio v
                LEFT JOIN dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto) cp ON cp.idPrograma = v.idPrograma
                WHERE v.idAsignatura = @idAsignaturaDefecto AND v.estaActivoVinculo = 1;

                IF @totalCoordinados = 0
                    SET @codigoRechazo = 'SEC_002';
                ELSE IF @exigirTodosLosProgramas = 1 AND @totalCoordinados < @totalProgramas
                    SET @codigoRechazo = 'ASI_006';
            END
        END

        IF @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @p_param1 = 'Asignatura',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
