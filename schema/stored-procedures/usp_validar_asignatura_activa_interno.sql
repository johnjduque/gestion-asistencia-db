USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_validar_asignatura_activa_interno]   (INTERNO: sin EXECUTE para el runtime)
-- HU074 (migracion 58): una asignatura inactiva (Asignatura.estado = 0) no se usa para crear grupos ni para asociarla a un
-- plan: ASI_010. La existencia la valida el llamador (VAL_002 / GEN_001); una asignatura inexistente pasa esta validacion.
-- Llamadores: usp_crear_grupo y usp_asociar_asignatura_plan. Los grupos existentes no cambian.
-- @bloquearFila = 1: lee dbo.Asignatura con UPDLOCK, HOLDLOCK; el llamador debe tener una transaccion abierta (el bloqueo dura
-- hasta su COMMIT). usp_crear_grupo lo usa para serializarse con usp_toggle_estado_asignatura, que toma el mismo bloqueo.
-- =============================================================================
-- SKILLS-BD lote 6 (2026-11-26): IF con BEGIN/END y TRY/CATCH (relanza dentro de transaccion; si no, SYS_001). La lectura
-- con UPDLOCK, HOLDLOCK sigue en la tabla. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_asignatura_activa_interno]
(
    @idAsignatura            UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @bloquearFila            BIT = 0
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @estaActiva           BIT;

BEGIN
    SET NOCOUNT ON;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        -- PASO 1: estado de la asignatura (con bloqueo de fila si el llamador lo pide)
        IF @bloquearFila = 1
        BEGIN
            SELECT @estaActiva = a.estado FROM dbo.Asignatura a WITH (UPDLOCK, HOLDLOCK) WHERE a.id = @idAsignatura;
        END
        ELSE
        BEGIN
            SELECT @estaActiva = a.estaActivaAsignatura FROM dbo.uv_asignatura a WHERE a.id = @idAsignatura;
        END

        -- PASO 2: ASI_010 si la asignatura existe y esta inactiva
        IF @estaActiva = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ASI_010',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        -- PASO 3: corre dentro de la transaccion del llamador: con transaccion abierta relanza para que el llamador revierta
        -- (comportamiento previo, sin TRY); sin transaccion devuelve el triplete SYS_001.
        IF XACT_STATE() <> 0
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
