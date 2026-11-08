USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_radicar_solicitud_revision_asistencia_v3  (CULM-001 D.2, HU014/HU015; CONTRACT §3.2)
--
-- Radica el reclamo con CATEGORIA persistida (FK a CategoriaJustificacion) y de 0 a ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO soportes
-- (DRAFT -> ATTACHED, todos en la MISMA transaccion). Toda la logica vive en usp_internal_radicar_solicitud_revision (compartida con
-- v2, DEC-044 (3)); aqui solo se gestiona la transaccion y se emite el resultset (los resultados vuelven por parametros OUTPUT, Msg 3915).
--
--   @categoria         codigo (MED, CAL...) o nombre de la categoria (REV_021 si no existe)
--   @idsArchivoSoporte arreglo JSON de GUID (["guid", ...]) o NULL/'[]' sin soportes; categoria con requiereSoporte exige >= 1 (REV_022)
--
-- Resultset: MUTATION_COMMAND_RESULTSET extendido: las 4 columnas canonicas (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado) + idSolicitudRevision y totalSoportes (NULL / 0 si fallo).
-- Ownership transaccional: transaccion propia o SAVE TRANSACTION si el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia_v3]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @idsArchivoSoporte  NVARCHAR(MAX) = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudRevision  UNIQUEIDENTIFIER = NULL;
    DECLARE @totalSoportes        INT = 0;

    DECLARE @conteoTransaccionesInicial INT;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_culm001_d2_radicar_v3;
            SET @savepointCreado = 1;
        END

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
            @estadoResultado = @estadoResultado OUTPUT;

        -- Finalizacion respetando ownership: commit solo si el resultado es exitoso
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        -- Con savepoint (transaccion del llamador) no se revierte aqui: usp_internal_radicar_solicitud_revision ya revierte a su propio
        -- savepoint lo que escribio si fallo, y un rechazo previo a las escrituras no deja nada que deshacer (ROLLBACK esta
        -- prohibido dentro de un INSERT-EXEC del llamador, Msg 3915).
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_culm001_d2_radicar_v3;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar la excepcion original al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @idSolicitudRevision = NULL;
        SET @totalSoportes = 0;
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: las 4 columnas canonicas + el resultado de la radicacion
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idSolicitudRevision     = @idSolicitudRevision,
        totalSoportes           = @totalSoportes;
END;
GO
