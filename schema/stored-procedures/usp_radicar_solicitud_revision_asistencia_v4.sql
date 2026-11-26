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
-- Toda la logica y la transaccion viven en usp_internal_radicar_solicitud_revision (transaccion propia si @@TRANCOUNT = 0, si no
-- SAVE TRANSACTION; un rechazo no escribe). _v3 se conserva para el reclamo de la sesion completa (compatibilidad).
--
-- Resultset: MUTATION_COMMAND_RESULTSET extendido: las 4 columnas canonicas + idSolicitudRevision, totalSoportes e idToma
-- (NULL / 0 / NULL si fallo).
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
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudRevision     UNIQUEIDENTIFIER = NULL;
    DECLARE @totalSoportes           INT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

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
        EXEC dbo.usp_internal_radicar_solicitud_revision
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
