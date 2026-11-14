USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_asignatura]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @codigo             NVARCHAR(50),
    @nombre             NVARCHAR(50),
    @creditos           INT,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @semestreNumero     INT,
    @nombreArea         NVARCHAR(100),
    @nombreComponente   NVARCHAR(100),
    @idCorrelacion      UNIQUEIDENTIFIER,
    -- REC2 (auditoria BD 2026-10-28): ejecutor obligatorio (GEN_002 si llega NULL). El DEFAULT solo conserva la
    -- compatibilidad de firma; RBAC COORDINADOR + titularidad del PROGRAMA se validan en usp_validar_gestion_asignatura_coordinador_interno.
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL,
    @codigoCaracter     NVARCHAR(3) = NULL   -- CULM-001 B2NM: NULL conserva el caracter actual del vinculo
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDefecto        NVARCHAR(50)     = UPPER(TRIM(@codigo));
    DECLARE @creditosMaximo           INT              = dbo.ufn_obtener_parametro_int(NULL, 'ASIGNATURA', 'CREDITOS_MAXIMO');
    DECLARE @nombreDefecto        NVARCHAR(50)     = TRIM(@nombre);
    DECLARE @idAreaResolved       UNIQUEIDENTIFIER;
    DECLARE @idComponenteResolved UNIQUEIDENTIFIER;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @idSpeNuevo           UNIQUEIDENTIFIER;
    DECLARE @idCaracterNuevo      UNIQUEIDENTIFIER;
    DECLARE @cambiaCatalogo       BIT = 0;
    DECLARE @codigoRechazo        NVARCHAR(10);

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio, perfil COORDINADOR, existencia de la asignatura y titularidad del
        --         programa (REC2: logica comun en usp_validar_gestion_asignatura_coordinador_interno)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno
                @idAsignatura = @idAsignaturaDefecto,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @idCorrelacion = @idCorrelacionDefecto,
                @idPlanEstudio = @idPlanEstudio,   -- CULM-001 B2NM: ambito por el plan indicado (SEC_002 / ASI_004)
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.1: Creditos (decision de John 2026-11-04): si llegan deben ser mayores que cero (ASI_001); nulos
        --           conservan los actuales (actualizacion parcial, como el resto de campos)
        IF @estadoResultado = 1 AND @creditos IS NOT NULL AND @creditos <= 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ASI_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2.1b (DEC-073): los creditos no superan ASIGNATURA/CREDITOS_MAXIMO (ASI_008). Limite ausente: fail-closed.
        IF @estadoResultado = 1 AND @creditos IS NOT NULL AND (@creditosMaximo IS NULL OR @creditos > @creditosMaximo)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ASI_008',
                @p_param1 = @creditosMaximo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar unicidad del código si cambia
        IF @estadoResultado = 1 AND @codigoDefecto IS NOT NULL AND @codigoDefecto <> ''
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[Asignatura] WHERE UPPER(TRIM(codigo)) = @codigoDefecto AND id <> @idAsignaturaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ASI_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Actualización de la Asignatura
        -- P5 (2026-11-04): el área y el componente, si llegan, deben existir en sus tablas (GEN_001); vacíos conservan el actual.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_resolver_area_componente_asignatura_interno
                @area = @nombreArea,
                @componente = @nombreComponente,
                @obligatorios = 0,
                @idCorrelacion = @idCorrelacionDefecto,
                @idArea = @idAreaResolved OUTPUT,
                @idComponente = @idComponenteResolved OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4.1 (CULM-001 B2NM, S2): semestre y caracter del vinculo en el plan indicado. NULL conserva el actual.
        IF @estadoResultado = 1 AND @semestreNumero IS NOT NULL
        BEGIN
            SELECT @idSpeNuevo = spe.id
            FROM dbo.SemestrePlanEstudio spe
            INNER JOIN dbo.Semestre sm ON sm.id = spe.semestre
            WHERE spe.planEstudio = @idPlanEstudio AND sm.numero = @semestreNumero;
            IF @idSpeNuevo IS NULL
                SET @codigoRechazo = 'PLA_004';
        END
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND NULLIF(TRIM(@codigoCaracter), N'') IS NOT NULL
        BEGIN
            SELECT @idCaracterNuevo = c.id FROM dbo.CaracterAsignaturaPlan c WHERE c.codigo = TRIM(@codigoCaracter) AND c.estado = 1;
            IF @idCaracterNuevo IS NULL
                SET @codigoRechazo = 'ASI_007';
        END

        -- PASO 4.2: los datos de catalogo de una asignatura compartida solo los cambia quien coordina todos sus programas (ASI_006)
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            SELECT @cambiaCatalogo = IIF(
                   (@codigoDefecto IS NOT NULL AND @codigoDefecto <> '' AND a.codigo <> @codigoDefecto)
                OR (@nombreDefecto IS NOT NULL AND @nombreDefecto <> '' AND a.nombre <> @nombreDefecto)
                OR (@creditos IS NOT NULL AND a.credito <> @creditos)
                OR (@idAreaResolved IS NOT NULL AND a.area <> @idAreaResolved)
                OR (@idComponenteResolved IS NOT NULL AND a.componente <> @idComponenteResolved), 1, 0)
            FROM dbo.Asignatura a WHERE a.id = @idAsignaturaDefecto;

            IF @cambiaCatalogo = 1
               AND EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
                           WHERE v.idAsignatura = @idAsignaturaDefecto AND v.estaActivoVinculo = 1
                             AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE cp.idPrograma = v.idPrograma))
                SET @codigoRechazo = 'ASI_006';
        END

        -- PASO 4.3: un vinculo (inactivo) ya ocupa el semestre destino -> ASI_003
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idSpeNuevo IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape
                       WHERE ape.asignatura = @idAsignaturaDefecto AND ape.semestrePlanEstudio = @idSpeNuevo)
           AND NOT EXISTS (SELECT 1 FROM dbo.AsignaturaPlanEstudio ape2
                           WHERE ape2.asignatura = @idAsignaturaDefecto AND ape2.semestrePlanEstudio = @idSpeNuevo AND ape2.estaActivo = 1)
            SET @codigoRechazo = 'ASI_003';

        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @codigoRechazo,
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

            IF @cambiaCatalogo = 1
                UPDATE dbo.Asignatura
                SET codigo = CASE WHEN @codigoDefecto IS NOT NULL AND @codigoDefecto <> '' THEN @codigoDefecto ELSE codigo END,
                    nombre = CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE nombre END,
                    credito = CASE WHEN @creditos IS NOT NULL THEN @creditos ELSE credito END,
                    area = CASE WHEN @idAreaResolved IS NOT NULL THEN @idAreaResolved ELSE area END,
                    componente = CASE WHEN @idComponenteResolved IS NOT NULL THEN @idComponenteResolved ELSE componente END
                WHERE id = @idAsignaturaDefecto;

            -- La MISMA fila de la tabla puente cambia de semestre / caracter (no se crea otra: la asignatura de un solo plan sigue 1:1)
            UPDATE ape
            SET ape.semestrePlanEstudio = COALESCE(@idSpeNuevo, ape.semestrePlanEstudio),
                ape.caracter = COALESCE(@idCaracterNuevo, ape.caracter)
            FROM dbo.AsignaturaPlanEstudio ape
            INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
            WHERE ape.asignatura = @idAsignaturaDefecto AND spe.planEstudio = @idPlanEstudio AND ape.estaActivo = 1;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Asignatura',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            IF @transaccionPropia = 1 COMMIT TRANSACTION;
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
