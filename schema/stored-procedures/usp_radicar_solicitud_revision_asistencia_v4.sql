USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_radicar_solicitud_revision_asistencia_v4  (PC puntos de control: reclamo POR TOMA; docs/work-items/PC-puntos-control-tomas)
--
-- Igual que _v3 (categoria persistida y de 0 a ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO soportes) pero el reclamo es de UNA toma:
--   @idToma obligatorio (GEN_002 si es NULL). Solo se reclama una toma de la sesion (TOM_001) en la que el estudiante quedo
--   ausente (SJC, REV_026) y sin otra solicitud no retirada de esa toma (REV_027): un reclamo retirado permite radicar otro; uno
--   rechazado o aprobado no. El plazo HU026B es el de la sesion (REV_020 / REV_025).
-- Toda la logica y la transaccion viven en usp_radicar_solicitud_revision_interno (transaccion propia si @@TRANCOUNT = 0, si no
-- SAVE TRANSACTION; un rechazo no escribe). _v3 se conserva para el reclamo de la sesion completa (compatibilidad).
--
-- Resultset: MUTATION_COMMAND_RESULTSET extendido: las 4 columnas canonicas + idSolicitudRevision, totalSoportes e idToma
-- (NULL / 0 / NULL si fallo).
-- SKILLS-BD lote 2 (2026-11-25): DECLARE en la cabecera, PASO n, TRY/CATCH con SYS_001 (si la transaccion del llamador quedo
-- condenada relanza el error original) y llamada al nucleo renombrado (antes usp_internal_radicar_solicitud_revision, D3).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia_v4]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @idToma             UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @idsArchivoSoporte  NVARCHAR(MAX) = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudRevision     UNIQUEIDENTIFIER;
    DECLARE @totalSoportes           INT;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000);
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000);
    DECLARE @estadoResultado         BIT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: respuesta inicial
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;
    SET @idSolicitudRevision = NULL;
    SET @totalSoportes = 0;

    BEGIN TRY
        -- PASO 2: la toma es obligatoria (GEN_002)
        IF @idToma IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idToma',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        ELSE
        BEGIN
            -- PASO 3: radicacion del reclamo de la toma (nucleo con transaccion propia o savepoint)
            EXEC dbo.usp_radicar_solicitud_revision_interno
                @idEstudiante = @idEstudiante,
                @idSesion = @idSesion,
                @categoria = @categoria,
                @justificacion = @justificacion,
                @idsArchivoSoporte = @idsArchivoSoporte,
                @idCorrelacion = @idCorrelacionDefecto,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @idSolicitudRevision = @idSolicitudRevision OUTPUT,
                @totalSoportes = @totalSoportes OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @idToma = @idToma;
        END
    END TRY
    BEGIN CATCH
        -- PASO 4: error no controlado. Transaccion del llamador condenada: se relanza el error original (como antes del lote 2)
        IF XACT_STATE() = -1
        BEGIN
            THROW;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SET @idSolicitudRevision = NULL;
        SET @totalSoportes = 0;
    END CATCH

    -- PASO 5: resultset unificado (tupla canonica + extension documentada)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idSolicitudRevision     = @idSolicitudRevision,
        totalSoportes           = @totalSoportes,
        idToma                  = IIF(@estadoResultado = 1, @idToma, NULL);
END;
GO
