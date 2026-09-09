USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_sesion_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @aula                    NVARCHAR(100),
    @descripcion             NVARCHAR(MAX),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto        NVARCHAR(50)     = TRIM(@nombre);
    DECLARE @aulaDefecto          NVARCHAR(100)    = TRIM(@aula);
    DECLARE @descripcionDefecto   NVARCHAR(MAX)    = TRIM(@descripcion);

    DECLARE @grupoId UNIQUEIDENTIFIER;
    DECLARE @cerrada BIT;

BEGIN
    SET NOCOUNT ON;
    SET @estadoResultado = 1;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');

    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validar existencia y estado de la sesión
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @grupoId = grupo, @cerrada = cerrada
            FROM dbo.Sesion
            WHERE id = @idSesionDefecto;

            IF @grupoId IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'Sesion',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @cerrada = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_007',
                    @p_param1 = 'SesionCerradaInmutable',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Actualización atómica
        IF @estadoResultado = 1
        BEGIN
            UPDATE dbo.Sesion
            SET nombre = CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE nombre END,
                fechaHoraInicio = CASE WHEN @fechaHoraInicio IS NOT NULL THEN @fechaHoraInicio ELSE fechaHoraInicio END,
                fechaHoraFin = CASE WHEN @fechaHoraFin IS NOT NULL THEN @fechaHoraFin ELSE fechaHoraFin END,
                aula = CASE WHEN @aulaDefecto IS NOT NULL AND @aulaDefecto <> '' THEN @aulaDefecto ELSE aula END,
                descripcion = CASE WHEN @descripcionDefecto IS NOT NULL AND @descripcionDefecto <> '' THEN @descripcionDefecto ELSE descripcion END
            WHERE id = @idSesionDefecto;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Sesion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
