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
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_aviso_falta_sesion]
(
    @idSesion                 UNIQUEIDENTIFIER,
    @totalEstudiantesAvisados INT,
    @idCorrelacion            UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @transaccionPropia       BIT = 0;
    DECLARE @savepointCreado         BIT = 0;
    DECLARE @estadoTransaccionCatch  INT;
    DECLARE @parametro               NVARCHAR(500);
    DECLARE @idSesionTexto           NVARCHAR(36) = CONVERT(NVARCHAR(36), @idSesion);

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idSesion IS NULL OR @totalEstudiantesAvisados IS NULL OR @totalEstudiantesAvisados < 0)
        BEGIN
            SET @parametro = IIF(@idSesion IS NULL, N'idSesion', N'totalEstudiantesAvisados');
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = @parametro,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.Sesion s WHERE s.id = @idSesion)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_001', @p_param1 = @idSesionTexto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

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
                INSERT INTO dbo.AvisoFaltaSesion (sesion, fechaAvisoUtc, totalEstudiantesAvisados, idCorrelacion)
                VALUES (@idSesion, SYSUTCDATETIME(), @totalEstudiantesAvisados, @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() <> 0
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_registrar_aviso_falta_sesion;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

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
