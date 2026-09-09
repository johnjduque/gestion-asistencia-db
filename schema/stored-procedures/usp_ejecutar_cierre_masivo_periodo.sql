USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_ejecutar_cierre_masivo_periodo]
(
    @codigoPeriodo          NVARCHAR(50),
    @idActor                NVARCHAR(100),
    @idCorrelacion          UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoPeriodoDefecto NVARCHAR(50)     = TRIM(@codigoPeriodo);
    DECLARE @idActorDefecto       NVARCHAR(100)    = TRIM(@idActor);

    DECLARE @idPeriodoTarget UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Buscar período académico objetivo
        IF @estadoResultado = 1
        BEGIN
            IF @codigoPeriodoDefecto IS NOT NULL AND @codigoPeriodoDefecto <> ''
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM dbo.PeriodoAcademico
                WHERE nombre = @codigoPeriodoDefecto 
                   OR CAST(codigo AS NVARCHAR(50)) = @codigoPeriodoDefecto
                ORDER BY anio DESC;
            END

            IF @idPeriodoTarget IS NULL
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM dbo.PeriodoAcademico
                ORDER BY anio DESC, codigo DESC;
            END
        END

        -- PASO 3: Invocación al procedimiento interno de Cierre Masivo
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_ejecutar_cierre_masivo_periodo_interno
                @idPeriodo = @idPeriodoTarget,
                @codigoPeriodo = @codigoPeriodoDefecto,
                @idActor = @idActorDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
