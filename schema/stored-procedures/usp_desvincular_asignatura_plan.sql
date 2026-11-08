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
    DECLARE @idProgramaPlan UNIQUEIDENTIFIER, @codigoRechazo NVARCHAR(10);
    DECLARE @zona NVARCHAR(100) = COALESCE((SELECT TOP 1 valor FROM dbo.CatalogoParametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1), 'SA Pacific Standard Time');
    DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE);
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @transaccionPropia BIT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
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
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'COORDINADOR', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            SELECT @idProgramaPlan = pe.programa FROM dbo.PlanEstudio pe WHERE pe.id = @idPlanEstudio;
            IF @idProgramaPlan IS NULL
                SET @codigoRechazo = 'PLA_002';
            ELSE
            BEGIN
                EXEC dbo.usp_validar_titularidad_jerarquica_interno
                    @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idProgramaPlan, @tipoEntidadPadre = 'PROGRAMA',
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
        END

        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            IF NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape WITH (UPDLOCK, HOLDLOCK)
                           INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                           WHERE ape.asignatura = @idAsignatura AND spe.planEstudio = @idPlanEstudio AND ape.estaActivo = 1)
                SET @codigoRechazo = 'ASI_004';
            -- ASI_005: grupos vigentes o futuros cuyo unico programa vigente es el del plan, o matriculas activas cuyo unico
            -- programa comun con el grupo es el del plan.
            ELSE IF EXISTS (
                SELECT 1
                FROM dbo.Grupo g
                INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico AND pa.fechaFin >= @hoyLocal
                WHERE g.asignatura = @idAsignatura
                  AND EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(g.id) pg WHERE pg.idPrograma = @idProgramaPlan)
                  AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(g.id) pg WHERE pg.idPrograma <> @idProgramaPlan)
            )
                SET @codigoRechazo = 'ASI_005';
            ELSE IF EXISTS (
                SELECT 1
                FROM dbo.Grupo g
                INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico AND pa.fechaFin >= @hoyLocal
                INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
                INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado AND ee.codigo = N'A'
                WHERE g.asignatura = @idAsignatura
                  AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = eg.estudiante AND ep.programa = @idProgramaPlan)
                  AND NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                                  INNER JOIN dbo.ufn_programas_grupo(g.id) pg ON pg.idPrograma = ep.programa
                                  WHERE ep.estudiante = eg.estudiante AND ep.programa <> @idProgramaPlan)
            )
                SET @codigoRechazo = 'ASI_005';
            ELSE
            BEGIN
                UPDATE ape
                SET ape.estaActivo = 0, ape.fechaDesvinculacionUtc = SYSUTCDATETIME()
                FROM dbo.AsignaturaPlanEstudio ape
                INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                WHERE ape.asignatura = @idAsignatura AND spe.planEstudio = @idPlanEstudio AND ape.estaActivo = 1;

                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_005', @p_param1 = 'Vinculo de asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @codigoRechazo IS NULL AND @transaccionPropia = 1
                COMMIT TRANSACTION;
            ELSE IF @codigoRechazo IS NOT NULL AND @transaccionPropia = 1
                ROLLBACK TRANSACTION;
        END

        IF @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT idCorrelacion = @idCorrelacionDefecto, mensajeUsuarioResultado = @mensajeUsuarioResultado,
           mensajeTecnicoResultado = @mensajeTecnicoResultado, estadoResultado = @estadoResultado;
END;
GO
