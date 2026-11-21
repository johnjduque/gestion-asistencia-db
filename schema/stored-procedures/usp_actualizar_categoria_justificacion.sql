USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_actualizar_categoria_justificacion]
-- Migracion 65: el ADMINISTRADOR cambia nombre, descripcion y soporte obligatorio de una categoria. El codigo (clave de negocio)
-- no cambia. Salida canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_categoria_justificacion]
(
    @id                UNIQUEIDENTIFIER = NULL,
    @nombre            NVARCHAR(4000)   = NULL,
    @descripcion       NVARCHAR(4000)   = NULL,
    @requiereSoporte   BIT              = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDef            NVARCHAR(4000)   = TRIM(@nombre);
    DECLARE @descripcionDef       NVARCHAR(4000)   = NULLIF(TRIM(@descripcion), N'');
    DECLARE @catalogo             NVARCHAR(100)    = N'categorías de justificación';
    DECLARE @campoFaltante        NVARCHAR(30)     = NULL;
    DECLARE @existe               BIT = 0;
    DECLARE @maxNombre            INT = COLUMNPROPERTY(OBJECT_ID(N'dbo.CategoriaJustificacion'), N'nombre', 'PRECISION');
    DECLARE @maxDescripcion       INT = COLUMNPROPERTY(OBJECT_ID(N'dbo.CategoriaJustificacion'), N'descripcion', 'PRECISION');
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        EXEC dbo.usp_validar_ejecutor_administrador_interno
            @idCorrelacion = @idCorrelacionDefecto, @idUsuarioEjecutor = @idUsuarioEjecutor,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
            SET @campoFaltante = CASE WHEN @id IS NULL THEN N'id' WHEN @requiereSoporte IS NULL THEN N'requiereSoporte' END;

        IF @estadoResultado = 1 AND @campoFaltante IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = @campoFaltante,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_item_catalogo_interno
                @codigo = NULL, @maxCodigo = NULL,
                @nombre = @nombreDef, @maxNombre = @maxNombre,
                @descripcion = @descripcionDef, @maxDescripcion = @maxDescripcion,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cat_actualizar;
                SET @savepointCreado = 1;
            END

            SELECT @existe = 1 FROM dbo.CategoriaJustificacion WITH (UPDLOCK, HOLDLOCK) WHERE id = @id;

            IF @existe = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'CTG_005', @p_param1 = @catalogo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Id: ', @id, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF EXISTS (SELECT 1 FROM dbo.CategoriaJustificacion WITH (UPDLOCK, HOLDLOCK) WHERE nombre = @nombreDef AND id <> @id)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'CTG_006', @p_param1 = @catalogo, @p_param2 = N'nombre',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                UPDATE dbo.CategoriaJustificacion
                SET nombre = @nombreDef, descripcion = @descripcionDef, requiereSoporte = @requiereSoporte
                WHERE id = @id;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'CTG_007', @p_param1 = @catalogo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Id: ', @id, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
                COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION sp_cat_actualizar;
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

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
