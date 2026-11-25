USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_desvincular_asignatura_plan]
-- CULM-001 B2NM (DEC-019, F-COO-005): baja logica del vinculo asignatura-plan (reemplaza el 501 del DELETE).
-- RBAC COORDINADOR; plan existente (PLA_002) y de un programa suyo (SEC_002). Sin vinculo activo en el plan: ASI_004.
-- ASI_005 si hay grupos de la asignatura en un periodo vigente o futuro cuyo UNICO programa vigente es el de este plan,
-- o matriculas activas de esos grupos cuyo unico programa comun con el grupo es este. Si pasa: estaActivo = 0 y
-- fechaDesvinculacionUtc = ahora (los grupos pasados conservan el programa por la regla S1).
-- SKILLS-BD lote 2 (2026-11-25): PASO n, IF con BEGIN/END, sin COALESCE (zona horaria por ufn_obtener_parametro), lecturas por
-- vistas (uv_plan_estudio, uv_semestre_plan_estudio, uv_grupo, uv_estudiante_grupo, uv_estudiante_programa), XACT_STATE() en el
-- CATCH. El vinculo activo se comprueba en la tabla con UPDLOCK/HOLDLOCK (excepcion de lecturas con bloqueo).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_desvincular_asignatura_plan]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaPlan UNIQUEIDENTIFIER;
    DECLARE @codigoRechazo  NVARCHAR(10);
    DECLARE @zona           NVARCHAR(100) = CONVERT(NVARCHAR(100), dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER'));
    DECLARE @hoyLocal       DATE;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @transaccionPropia BIT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: fecha local institucional (zona TIEMPO/ZONA_HORARIA_SQLSERVER; sin parametro, la zona por defecto de uv_grupo)
        IF @zona IS NULL
        BEGIN
            SET @zona = N'SA Pacific Standard Time';
        END
        SET @hoyLocal = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);

        -- PASO 2: correlacion, ejecutor obligatorio (GEN_002) y RBAC COORDINADOR
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'COORDINADOR', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: plan existente (PLA_002) y titularidad del programa del plan (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idProgramaPlan = pe.idPrograma FROM dbo.uv_plan_estudio pe WHERE pe.id = @idPlanEstudio;
            IF @idProgramaPlan IS NULL
            BEGIN
                SET @codigoRechazo = 'PLA_002';
            END
            ELSE
            BEGIN
                EXEC dbo.usp_validar_titularidad_jerarquica_interno
                    @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idProgramaPlan, @tipoEntidadPadre = 'PROGRAMA',
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
        END

        -- PASO 4: vinculo activo (ASI_004), grupos o matriculas que dependen solo de este programa (ASI_005) y baja logica
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            IF NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape WITH (UPDLOCK, HOLDLOCK)
                           INNER JOIN dbo.uv_semestre_plan_estudio spe ON spe.id = ape.semestrePlanEstudio
                           WHERE ape.asignatura = @idAsignatura AND spe.idPlanEstudio = @idPlanEstudio AND ape.estaActivo = 1)
            BEGIN
                SET @codigoRechazo = 'ASI_004';
            END
            -- ASI_005: grupos vigentes o futuros cuyo unico programa vigente es el del plan, o matriculas activas cuyo unico
            -- programa comun con el grupo es el del plan.
            ELSE IF EXISTS (
                SELECT 1
                FROM dbo.uv_grupo g
                WHERE g.idAsignatura = @idAsignatura
                  AND g.fechaFinPeriodoAcademico >= @hoyLocal
                  AND EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(g.id) pg WHERE pg.idPrograma = @idProgramaPlan)
                  AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(g.id) pg WHERE pg.idPrograma <> @idProgramaPlan)
            )
            BEGIN
                SET @codigoRechazo = 'ASI_005';
            END
            ELSE IF EXISTS (
                SELECT 1
                FROM dbo.uv_grupo g
                INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = g.id AND eg.codigoEstadoEstudiante = N'A'
                WHERE g.idAsignatura = @idAsignatura
                  AND g.fechaFinPeriodoAcademico >= @hoyLocal
                  AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa ep WHERE ep.idEstudiante = eg.idEstudiante AND ep.idPrograma = @idProgramaPlan)
                  AND NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa ep
                                  INNER JOIN dbo.ufn_programas_grupo(g.id) pg ON pg.idPrograma = ep.idPrograma
                                  WHERE ep.idEstudiante = eg.idEstudiante AND ep.idPrograma <> @idProgramaPlan)
            )
            BEGIN
                SET @codigoRechazo = 'ASI_005';
            END
            ELSE
            BEGIN
                UPDATE ape
                SET ape.estaActivo = 0, ape.fechaDesvinculacionUtc = SYSUTCDATETIME()
                FROM dbo.AsignaturaPlanEstudio ape
                INNER JOIN dbo.uv_semestre_plan_estudio spe ON spe.id = ape.semestrePlanEstudio
                WHERE ape.asignatura = @idAsignatura AND spe.idPlanEstudio = @idPlanEstudio AND ape.estaActivo = 1;

                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_005', @p_param1 = 'Vinculo de asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @codigoRechazo IS NULL AND @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
            END
            ELSE IF @codigoRechazo IS NOT NULL AND @transaccionPropia = 1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END

        -- PASO 5: mensaje de rechazo
        IF @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        -- PASO 6: error no controlado (SYS_001); revierte solo la transaccion propia
        IF @transaccionPropia = 1 AND XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- PASO 7: resultset unificado
    SELECT idCorrelacion = @idCorrelacionDefecto, mensajeUsuarioResultado = @mensajeUsuarioResultado,
           mensajeTecnicoResultado = @mensajeTecnicoResultado, estadoResultado = @estadoResultado;
END;
GO
