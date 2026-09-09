USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_asignatura_interno]
(
    @idAsignatura            UNIQUEIDENTIFIER,
    @codigo                  NVARCHAR(50),
    @nombre                  NVARCHAR(50),
    @creditos                INT,
    @idArea                  UNIQUEIDENTIFIER,
    @idComponente            UNIQUEIDENTIFIER,
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
    DECLARE @idComponenteDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idComponente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
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

        -- PASO 2: Validar campos obligatorios
        IF @estadoResultado = 1
        BEGIN
            IF @codigoDefecto IS NULL OR @codigoDefecto = ''
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_001',
                    @p_param1 = 'CodigoAsignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            IF @nombreDefecto IS NULL OR @nombreDefecto = ''
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_001',
                    @p_param1 = 'NombreAsignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            IF @creditos IS NULL OR @creditos <= 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_001',
                    @p_param1 = 'CreditosAcademicos',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Validar unicidad del código
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Asignatura WHERE UPPER(TRIM(codigo)) = @codigoDefecto)
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

        -- PASO 4: Inserción de la Asignatura
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.Asignatura (
                id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado
            )
            VALUES (
                @idAsignaturaDefecto,
                @codigoDefecto,
                @nombreDefecto,
                @creditos,
                @idAreaDefecto,
                @idComponenteDefecto,
                @idSemestrePlanEstudioDefecto,
                1
            );

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
