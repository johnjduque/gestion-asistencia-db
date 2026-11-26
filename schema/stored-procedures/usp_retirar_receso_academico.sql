USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_retirar_receso_academico (DEC-081) — borrado logico (estaActivo = 0) de un dia de receso, solo si NO ha cancelado ninguna sesion.
-- Solo el ADMINISTRADOR de la institucion del periodo. Reglas (la primera que falla corta):
--   * receso inexistente, ya retirado o de otra institucion => REC_009;
--   * periodo cerrado (fechaCierreUtc no nula) => REC_007;
--   * el dia ya cancelo sesiones (SesionCancelacion.recesoAcademico) => REC_010 con el conteo: no se retira ni se cambia.
-- Exito: REC_002. Resultset: tupla canonica de 4 columnas. Corregir un dia = retirarlo (si no esta aplicado) y crear otro.
-- ============================================================================
-- SKILLS-BD lote 9 (2026-11-26): periodo y cancelaciones por uv_periodo_academico_fechas/uv_sesion_cancelacion (antes, las tablas) e IF con BEGIN/END. El bloqueo del receso sigue en la tabla. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_retirar_receso_academico]
(
    @idReceso                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idRecesoDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idReceso, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucion            UNIQUEIDENTIFIER;
    DECLARE @idRecesoEncontrado       UNIQUEIDENTIFIER;
    DECLARE @fechaReceso              DATE;
    DECLARE @nombrePeriodo            NVARCHAR(50);
    DECLARE @fechaCierreUtc           DATETIME2(7);
    DECLARE @sesionesCanceladas       INT = 0;
    DECLARE @codigoRechazo            VARCHAR(20);
    DECLARE @p1                       NVARCHAR(500);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASOS 1 a 3: correlacion, ejecutor obligatorio (GEN_002) y ambito (ADMINISTRADOR de la institucion)
        EXEC dbo.usp_validar_ejecutor_administrador_periodo_interno
            @idCorrelacion = @idCorrelacionDefecto, @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idInstitucion = @idInstitucion OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 4: transaccion, bloqueo del dia y reglas del retiro
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_retirar_receso;
                SET @savepointCreado = 1;
            END

            SELECT  @idRecesoEncontrado = r.id, @fechaReceso = r.fecha, @nombrePeriodo = pa.nombre, @fechaCierreUtc = pa.fechaCierreUtc
            FROM    dbo.PeriodoRecesoAcademico r WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.uv_periodo_academico_fechas pa ON pa.id = r.periodoAcademico AND pa.idInstitucion = @idInstitucion
            WHERE   r.id = @idRecesoDefecto AND r.estaActivo = 1;

            IF @idRecesoEncontrado IS NOT NULL
            BEGIN
                SELECT @sesionesCanceladas = COUNT(1) FROM dbo.uv_sesion_cancelacion sc WHERE sc.idRecesoAcademico = @idRecesoEncontrado;
            END

            IF @idRecesoEncontrado IS NULL
            BEGIN
                SET @codigoRechazo = 'REC_009';
                SET @p1 = CONVERT(NVARCHAR(36), @idRecesoDefecto);
            END
            ELSE IF @fechaCierreUtc IS NOT NULL
            BEGIN
                SET @codigoRechazo = 'REC_007';
                SET @p1 = @nombrePeriodo;
            END
            ELSE IF @sesionesCanceladas > 0
            BEGIN
                SET @codigoRechazo = 'REC_010';
                SET @p1 = CONVERT(NVARCHAR(20), @sesionesCanceladas);
            END

            IF @codigoRechazo IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo, @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                UPDATE dbo.PeriodoRecesoAcademico SET estaActivo = 0 WHERE id = @idRecesoEncontrado;

                SET @p1 = CONVERT(NVARCHAR(10), @fechaReceso, 103);
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REC_002', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    COMMIT TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                BEGIN
                    ROLLBACK TRANSACTION;
                END
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_retirar_receso;
        END
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

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
