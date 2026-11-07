USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_asociar_asignatura_plan]
-- CULM-001 B2NM (DEC-019, R3): asocia una asignatura existente (catalogo) a un plan de estudios, con semestre y caracter.
-- RBAC COORDINADOR; el plan existe (PLA_002) y es de un programa suyo (SEC_002); la asignatura existe y esta activa, y tiene
-- algun vinculo en un programa de la misma institucion (si no, GEN_001). Reglas de vinculo en usp_internal_asociar_asignatura_plan
-- (PLA_004, ASI_003, ASI_007). Salida canonica (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_asociar_asignatura_plan]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @semestreNumero     INT,
    @codigoCaracter     NVARCHAR(3) = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaPlan UNIQUEIDENTIFIER, @idInstitucionPlan UNIQUEIDENTIFIER;
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
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
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

        -- Plan existente (PLA_002) y titularidad del programa del plan (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idProgramaPlan = pe.programa, @idInstitucionPlan = f.institucion
            FROM dbo.PlanEstudio pe
            INNER JOIN dbo.Programa p ON p.id = pe.programa
            INNER JOIN dbo.Facultad f ON f.id = p.facultad
            WHERE pe.id = @idPlanEstudio;

            IF @idProgramaPlan IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PLA_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
                EXEC dbo.usp_validar_titularidad_jerarquica_interno
                    @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idProgramaPlan, @tipoEntidadPadre = 'PROGRAMA',
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
        END

        -- La asignatura existe, esta activa y pertenece a la institucion del plan (tiene algun vinculo en ella)
        IF @estadoResultado = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
                           WHERE v.idAsignatura = @idAsignatura AND v.estaActivaAsignatura = 1 AND v.idInstitucion = @idInstitucionPlan)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_001', @p_param1 = 'Asignatura',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            EXEC dbo.usp_internal_asociar_asignatura_plan
                @idAsignatura = @idAsignatura, @idPlanEstudio = @idPlanEstudio, @semestreNumero = @semestreNumero,
                @codigoCaracter = @codigoCaracter, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Vinculo de asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                IF @transaccionPropia = 1 COMMIT TRANSACTION;
            END
            ELSE IF @transaccionPropia = 1
                ROLLBACK TRANSACTION;
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
