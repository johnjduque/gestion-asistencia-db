USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_o_actualizar_asignatura]
(
    @idAsignatura   UNIQUEIDENTIFIER,
    @nombre         NVARCHAR(100),
    @codigo         NVARCHAR(50),
    @creditos       INT,
    @horasSemanales INT,
    @idCorrelacion  UNIQUEIDENTIFIER
)
AS
DECLARE @idCorrelacionDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idAsignaturaDefecto   UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @nombreDefecto         NVARCHAR(100)    = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@nombre, 'GENERAL', 'CADENA_VACIA')));
DECLARE @codigoDefecto         NVARCHAR(50)     = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@codigo, 'GENERAL', 'CADENA_VACIA')));
DECLARE @creditosDefecto       INT              = dbo.ufn_obtener_parametro_int(@creditos, 'GENERAL', 'ENTERO_CERO');
DECLARE @horasSemanalesDefecto INT              = dbo.ufn_obtener_parametro_int(@horasSemanales, 'GENERAL', 'ENTERO_CERO');

DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Validar presencia obligatoria de idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar que el código o nombre de la asignatura no estén vacíos
        IF @estadoResultado = 1 AND (@codigoDefecto = '' OR @nombreDefecto = '')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Nombre y codigo de asignatura son requeridos. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3. FLUJO REACTIVO (UPSERT): Consultar existencia en uv_asignatura
        IF @estadoResultado = 1
        BEGIN
            DECLARE @idAreaDefecto UNIQUEIDENTIFIER;
            SELECT TOP 1 @idAreaDefecto = id FROM dbo.Area ORDER BY id ASC;

            DECLARE @idComponenteDefecto UNIQUEIDENTIFIER;
            SELECT TOP 1 @idComponenteDefecto = id FROM dbo.Componente ORDER BY id ASC;

            DECLARE @idSpeDefecto UNIQUEIDENTIFIER;
            SELECT TOP 1 @idSpeDefecto = id FROM dbo.SemestrePlanEstudio ORDER BY id ASC;

            IF EXISTS (SELECT 1 FROM dbo.uv_asignatura a WHERE a.id = @idAsignaturaDefecto OR a.codigo = @codigoDefecto)
            BEGIN
                UPDATE [dbo].[Asignatura]
                SET [nombre]  = @nombreDefecto,
                    [codigo]  = @codigoDefecto,
                    [credito] = @creditosDefecto
                WHERE [id] = @idAsignaturaDefecto OR [codigo] = @codigoDefecto;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SUC_ACTUALIZACION_ASIGNATURA',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END
            ELSE
            BEGIN
                DECLARE @nuevoId UNIQUEIDENTIFIER = NEWID();

                INSERT INTO [dbo].[Asignatura] ([id], [codigo], [nombre], [credito], [area], [componente], [semestrePlanEstudio], [estado])
                VALUES (@nuevoId, @codigoDefecto, @nombreDefecto, @creditosDefecto, @idAreaDefecto, @idComponenteDefecto, @idSpeDefecto, 1);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SUC_REGISTRO_ASIGNATURA',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'ERR_INESPERADO_REGISTRO_ASIGNATURA',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL MANDATORIO: Retorno unificado de 4 columnas
    SELECT
        idCorrelacion = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END;
GO
