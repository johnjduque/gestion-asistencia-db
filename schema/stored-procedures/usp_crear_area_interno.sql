USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_crear_area_interno]
-- Ámbito: Operación atómica de persistencia para Área
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_area_interno]
(
    @id                      UNIQUEIDENTIFIER,
    @codigo                  NVARCHAR(3),
    @nombre                  NVARCHAR(50),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAreaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@id, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDefecto        NVARCHAR(3)      = UPPER(TRIM(@codigo));
    DECLARE @nombreDefecto        NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        IF @idAreaDefecto IS NULL OR @idAreaDefecto = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER)
        BEGIN
            SET @idAreaDefecto = NEWID();
        END

        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION usp_crear_area_interno;
            SET @savepointCreado = 1;
        END

        INSERT INTO dbo.Area (id, codigo, nombre)
        VALUES (@idAreaDefecto, @codigoDefecto, @nombreDefecto);

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_004',
            @p_param1 = 'Area',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' IdArea: ', @idAreaDefecto, ' Correlacion: ', @idCorrelacionDefecto);

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION usp_crear_area_interno;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
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
