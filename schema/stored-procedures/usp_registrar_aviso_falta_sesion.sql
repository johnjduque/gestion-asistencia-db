USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_aviso_falta_sesion (ATA D1, ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS C; HU175)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando de sistema (sin usuario) con la tupla canonica (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado). Marca la sesion como ya avisada (AvisoFaltaSesion) con el total de estudiantes avisados.
-- Transaccional e idempotente: si la fila ya existe responde exito sin escribir (el total y la fecha originales se conservan); dos
-- instancias del job que avisen la misma sesion no duplican la marca. Validaciones: correlacion, GEN_002 (sesion o total nulos o
-- negativos) y SES_001 (sesion inexistente).
-- ============================================================================
-- SKILLS-BD lote 8 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END y sesion por uv_sesion (antes, la tabla). La lectura con UPDLOCK/HOLDLOCK sigue en la tabla. Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): job del servidor sin @idUsuarioEjecutor; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_aviso_falta_sesion]
(
    @idSesion                 UNIQUEIDENTIFIER,
    @totalEstudiantesAvisados INT,
    @idCorrelacion            UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @transaccionPropia       BIT = 0;
    DECLARE @savepointCreado         BIT = 0;
    DECLARE @estadoTransaccionCatch  INT;
    DECLARE @parametro               NVARCHAR(500);
    DECLARE @idSesionTexto           NVARCHAR(36) = CONVERT(NVARCHAR(36), @idSesion);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Parametros obligatorios (GEN_002)
        IF @estadoResultado = 1 AND (@idSesion IS NULL OR @totalEstudiantesAvisados IS NULL OR @totalEstudiantesAvisados < 0)
        BEGIN
            SET @parametro = IIF(@idSesion IS NULL, N'idSesion', N'totalEstudiantesAvisados');
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = @parametro,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: La sesion debe existir (SES_001)
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_sesion s WHERE s.id = @idSesion)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_001', @p_param1 = @idSesionTexto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Registrar el aviso una sola vez por sesion, en transaccion propia o savepoint
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_registrar_aviso_falta_sesion;
                SET @savepointCreado = 1;
            END

            -- Idempotente bajo concurrencia: la lectura bloquea la clave (UPDLOCK, HOLDLOCK) hasta confirmar
            IF NOT EXISTS (SELECT 1 FROM dbo.AvisoFaltaSesion a WITH (UPDLOCK, HOLDLOCK) WHERE a.sesion = @idSesion)
            BEGIN
                INSERT INTO dbo.AvisoFaltaSesion (sesion, fechaAvisoUtc, totalEstudiantesAvisados, idCorrelacion)
                VALUES (@idSesion, SYSUTCDATETIME(), @totalEstudiantesAvisados, @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    COMMIT TRANSACTION;
                END
                ELSE IF XACT_STATE() <> 0
                BEGIN
                    ROLLBACK TRANSACTION;
                END
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        -- PASO 5: Revertir lo propio; con transaccion del llamador no confirmable relanza, si no responde SYS_001
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
            ROLLBACK TRANSACTION sp_registrar_aviso_falta_sesion;
        END

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
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
