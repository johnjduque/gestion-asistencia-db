USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_toggle_estado_asignatura]
-- Alterna Asignatura.estado (activa <-> inactiva). RBAC COORDINADOR que coordine TODOS los programas con vinculo activo de la
-- asignatura (usp_validar_gestion_asignatura_coordinador_interno con @exigirTodosLosProgramas = 1; si no, SEC_002 / ASI_006).
-- HU074 (migracion 58):
--   * Inactivar (1 -> 0) se rechaza con ASI_009 si la asignatura tiene grupos en un periodo academico vigente o futuro, en
--     cualquier programa: uv_periodo_academico.estado distinto de CERRADO (fecha local institucional, TIEMPO/ZONA_HORARIA_SQLSERVER;
--     misma regla que ASI_005 en usp_desvincular_asignatura_plan: fechaFin >= hoy). Grupo no tiene baja logica: cuentan todos.
--   * Reactivar (0 -> 1) siempre se permite tras las validaciones anteriores.
--   * Exito: ASI_011 (quedo activa) o ASI_012 (quedo inactiva). Resultset canonico sin cambios.
--   * @estaActivaDeseada (aditivo, opcional): NULL alterna el estado leido; 1 / 0 fija ese estado. Si la asignatura ya esta en el
--     estado pedido responde exito sin cambios (ASI_011 / ASI_012) y no evalua la regla de grupos (idempotente ante reintentos).
--   * Concurrencia: la fila de dbo.Asignatura se lee con UPDLOCK, HOLDLOCK dentro de la transaccion, antes de buscar grupos, y el
--     UPDATE ocurre en la misma transaccion. usp_crear_grupo toma el mismo bloqueo antes de validar ASI_010 e insertar: una
--     inactivacion y una creacion de grupo simultaneas sobre la misma asignatura se serializan.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_toggle_estado_asignatura]
(
    @idAsignatura   UNIQUEIDENTIFIER,
    @idCorrelacion  UNIQUEIDENTIFIER,
    -- REC2 (auditoria BD 2026-10-28): ejecutor obligatorio (GEN_002 si llega NULL). El DEFAULT solo conserva la
    -- compatibilidad de firma; RBAC COORDINADOR + titularidad del PROGRAMA se validan en usp_validar_gestion_asignatura_coordinador_interno.
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL,
    -- HU074: estado deseado (1 activa, 0 inactiva). NULL conserva el comportamiento de alternar.
    @estaActivaDeseada BIT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @estaActivaActual     BIT;
    DECLARE @estaActivaNueva      BIT;
    DECLARE @codigoResultado      NVARCHAR(10);
    DECLARE @transaccionPropia    BIT = 0;

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
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @exigirTodosLosProgramas = 1,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3 (HU074): con la fila bloqueada, ASI_009 si se pide inactivar y hay grupos en un periodo vigente o futuro; si no,
        --         fija el estado pedido (o el contrario al leido). Sin cambio cuando ya esta en el estado pedido.
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            SELECT @estaActivaActual = a.estado
            FROM dbo.Asignatura a WITH (UPDLOCK, HOLDLOCK)
            WHERE a.id = @idAsignaturaDefecto;

            SET @estaActivaNueva = COALESCE(@estaActivaDeseada, IIF(@estaActivaActual = 1, 0, 1));

            IF @estaActivaActual = 1 AND @estaActivaNueva = 0
               AND EXISTS (SELECT 1
                           FROM dbo.uv_grupo g
                           INNER JOIN dbo.uv_periodo_academico pa ON pa.id = g.idPeriodoAcademico
                           WHERE g.idAsignatura = @idAsignaturaDefecto AND pa.estado <> 'CERRADO')
            BEGIN
                SET @codigoResultado = 'ASI_009';
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                IF @estaActivaNueva <> @estaActivaActual
                    UPDATE dbo.Asignatura
                    SET estado = @estaActivaNueva
                    WHERE id = @idAsignaturaDefecto;

                SET @codigoResultado = IIF(@estaActivaNueva = 1, 'ASI_011', 'ASI_012');
            END

            IF @transaccionPropia = 1 COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoResultado,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;

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
