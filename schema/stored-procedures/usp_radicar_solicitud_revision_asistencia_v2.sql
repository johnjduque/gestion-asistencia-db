USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_radicar_solicitud_revision_asistencia_v2  (LB-004D, W2)
--
-- Radica la solicitud de revision y, si se indica @idArchivoSoporte, vincula el soporte
-- (DRAFT -> ATTACHED) en la MISMA transaccion. La v1 permanece intacta.
--
--   * Sin @soporteNombre/@soporteUrl: la v2 no confia en datos de soporte del cliente.
--   * Verifica que @idEstudiante pertenezca a @idUsuarioEjecutor (defensa en profundidad, H-01).
--   * Soporte inexistente, ajeno, ya vinculado u huerfano => ARC_001 identico, sin escritura.
--   * Reintento con la misma correlacion tras un exito => exito idempotente (sin segunda solicitud).
--   * Carrera por el mismo fileId: el UPDLOCK sobre la fila serializa; la segunda ve ATTACHED => ARC_001.
--   * CULM-001 D.1 (HU026B): el plazo de excusas se valida DESPUES de la reejecucion idempotente por correlacion y antes de
--     cualquier escritura (REV_020 vencido, REV_025 sin parametros). `fecha` es la fecha LOCAL de radicacion.
--   * CULM-001 D.2 (HU014/HU015, TD-060; CONTRACT §3.2, DEC-044 (3)): firma y resultset SIN CAMBIO (4 columnas), pero la logica vive
--     ahora en usp_internal_radicar_solicitud_revision (compartida con usp_radicar_solicitud_revision_asistencia_v3): arma
--     ["@idArchivoSoporte"] (o NULL), guarda la categoria (REV_021 si no existe en CategoriaJustificacion) y exige soporte segun
--     la categoria (REV_022: MED, ACA y LAB). Los estados de soporte salen de parametros (TD-061).
--
-- Resultset: MUTATION_COMMAND_RESULTSET (4 columnas canonicas).
-- Ownership transaccional: transaccion propia o SAVE TRANSACTION si el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia_v2]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @idArchivoSoporte   UNIQUEIDENTIFIER = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idsArchivoSoporte    NVARCHAR(MAX)    = IIF(@idArchivoSoporte IS NULL, NULL, CONCAT(N'["', CAST(@idArchivoSoporte AS NVARCHAR(36)), N'"]'));
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
            SAVE TRANSACTION sp_lb004d_radicar_v2;
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
            ROLLBACK TRANSACTION sp_lb004d_radicar_v2;
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
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados (4 columnas canonicas)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
