USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU093 (D12): un docente cuyo vinculo con el programa de la asignatura fue INACTIVADO no puede ser titular de grupos
-- nuevos ni asignarse a un grupo existente (DOC_009). Un docente sin ningun vinculo no se bloquea, para no romper
-- flujos de asignacion previos a la adscripcion; los grupos ya asignados se conservan (esta regla solo se aplica
-- cuando se designa un titular).
-- SKILLS-BD lote 5 (2026-11-26): vinculos por uv_docente_programa (antes, la tabla), PASO n y TRY/CATCH (relanza dentro
-- de transaccion; si no, SYS_001). Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_docente_vinculo_activo_programa_interno]
(
    @idDocente               UNIQUEIDENTIFIER,
    @idAsignatura            UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPrograma UNIQUEIDENTIFIER;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: CULM-001 B2NM (R8): sin TOP 1. DOC_009 si el docente solo tiene vinculos inactivos con los programas de la asignatura
        -- (vinculos activos de la asignatura en planes) y ninguno activo.
        SELECT TOP 1 @idPrograma = v.idPrograma
        FROM dbo.uv_asignatura_plan_estudio v
        INNER JOIN dbo.uv_docente_programa dpi ON dpi.idPrograma = v.idPrograma AND dpi.idDocente = @idDocente AND dpi.estaActivoVinculacion = 0
        WHERE v.idAsignatura = @idAsignatura AND v.estaActivoVinculo = 1
          AND NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio w
                          INNER JOIN dbo.uv_docente_programa dpa ON dpa.idPrograma = w.idPrograma AND dpa.idDocente = @idDocente AND dpa.estaActivoVinculacion = 1
                          WHERE w.idAsignatura = @idAsignatura AND w.estaActivoVinculo = 1)
        ORDER BY v.idPrograma;

        -- PASO 2: rechazo DOC_009
        IF @idPrograma IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.uv_docente_programa WHERE idDocente = @idDocente AND idPrograma = @idPrograma AND estaActivoVinculacion = 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'DOC_009',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        -- Corre dentro de la transaccion del llamador: con transaccion abierta relanza para que el llamador revierta
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
