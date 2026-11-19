USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_validar_asignatura_activa_interno]   (INTERNO: sin EXECUTE para el runtime)
-- HU074 (migracion 57): una asignatura inactiva (Asignatura.estado = 0) no se usa para crear grupos ni para asociarla a un
-- plan: ASI_010. La existencia la valida el llamador (VAL_002 / GEN_001); una asignatura inexistente pasa esta validacion.
-- Llamadores: usp_crear_grupo y usp_asociar_asignatura_plan. Los grupos existentes no cambian.
-- @bloquearFila = 1: lee dbo.Asignatura con UPDLOCK, HOLDLOCK; el llamador debe tener una transaccion abierta (el bloqueo dura
-- hasta su COMMIT). usp_crear_grupo lo usa para serializarse con usp_toggle_estado_asignatura, que toma el mismo bloqueo.
-- =============================================================================
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

    -- PASO 1: estado de la asignatura (con bloqueo de fila si el llamador lo pide)
    IF @bloquearFila = 1
        SELECT @estaActiva = a.estado FROM dbo.Asignatura a WITH (UPDLOCK, HOLDLOCK) WHERE a.id = @idAsignatura;
    ELSE
        SELECT @estaActiva = a.estaActivaAsignatura FROM dbo.uv_asignatura a WHERE a.id = @idAsignatura;

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
END;
GO
