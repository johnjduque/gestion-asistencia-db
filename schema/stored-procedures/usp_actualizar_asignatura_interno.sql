USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_asignatura_interno]
(
    @idAsignatura            UNIQUEIDENTIFIER,
    @codigo                  NVARCHAR(50),
    @nombre                  NVARCHAR(50),
    @creditos                INT,
    @idArea                  UNIQUEIDENTIFIER,
    @idSemestrePlanEstudio   UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAreaDefecto                 UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idArea, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSemestrePlanEstudioDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSemestrePlanEstudio, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDefecto                 NVARCHAR(50)     = UPPER(TRIM(@codigo));
    DECLARE @nombreDefecto                 NVARCHAR(50)     = TRIM(@nombre);

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

        -- PASO 2: Validar existencia de la asignatura
        IF @estadoResultado = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id = @idAsignaturaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'Asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Validar conflicto de unicidad en código
        IF @estadoResultado = 1 AND @codigoDefecto IS NOT NULL AND @codigoDefecto <> ''
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Asignatura WHERE UPPER(TRIM(codigo)) = @codigoDefecto AND id <> @idAsignaturaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_006',
                    @p_param1 = 'Asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Actualización atómica
        IF @estadoResultado = 1
        BEGIN
            UPDATE dbo.Asignatura
            SET codigo = CASE WHEN @codigoDefecto IS NOT NULL AND @codigoDefecto <> '' THEN @codigoDefecto ELSE codigo END,
                nombre = CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE nombre END,
                credito = CASE WHEN @creditos IS NOT NULL AND @creditos > 0 THEN @creditos ELSE credito END,
                area = CASE WHEN @idAreaDefecto IS NOT NULL THEN @idAreaDefecto ELSE area END,
                semestrePlanEstudio = CASE WHEN @idSemestrePlanEstudioDefecto IS NOT NULL THEN @idSemestrePlanEstudioDefecto ELSE semestrePlanEstudio END
            WHERE id = @idAsignaturaDefecto;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Asignatura',
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
