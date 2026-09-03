USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_o_actualizar_programa_academico]
(
    @idPrograma       UNIQUEIDENTIFIER,
    @idFacultad       UNIQUEIDENTIFIER,
    @idTipoDePrograma UNIQUEIDENTIFIER,
    @nombre           NVARCHAR(50),
    @idCoordinador    UNIQUEIDENTIFIER,
    @idCorrelacion    UNIQUEIDENTIFIER
)
AS
DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idProgramaDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idFacultadDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idFacultad, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idTipoDeProgramaDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idTipoDePrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idCoordinadorDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCoordinador, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @nombreDefecto           NVARCHAR(50)     = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@nombre, 'GENERAL', 'CADENA_VACIA')));

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

        -- 2. Validar que la Facultad exista y esté activa vía Vista uv_facultad
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_facultad f WHERE f.id = @idFacultadDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Facultad no encontrada. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3. Validar que el Tipo de Programa exista vía Vista uv_tipo_programa
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_programa tp WHERE tp.id = @idTipoDeProgramaDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Tipo de programa no valido. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 4. Validar existencia del Coordinador asignado vía Vista uv_usuario
        IF @estadoResultado = 1 AND @idCoordinadorDefecto IS NOT NULL AND @idCoordinadorDefecto <> CAST('00000000-0000-0000-0000-000000000000' AS UNIQUEIDENTIFIER)
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.uv_usuario u WHERE u.id = @idCoordinadorDefecto AND u.estado = 1)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Coordinador invalido o inactivo. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- 5. FLUJO REACTIVO (UPSERT): Evaluar existencia por ID o por nombre en la misma facultad vía Vista uv_programa
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.uv_programa p WHERE p.id = @idProgramaDefecto OR (p.nombrePrograma = @nombreDefecto AND p.idFacultad = @idFacultadDefecto))
            BEGIN
                -- SI EXISTE: Actualizar registro en la tabla física Programa
                UPDATE [dbo].[Programa]
                SET [facultad]       = @idFacultadDefecto,
                    [tipoDePrograma] = @idTipoDeProgramaDefecto,
                    [nombre]         = @nombreDefecto,
                    [coordinador]    = CASE WHEN @idCoordinadorDefecto = CAST('00000000-0000-0000-0000-000000000000' AS UNIQUEIDENTIFIER) THEN [coordinador] ELSE @idCoordinadorDefecto END
                WHERE [id] = @idProgramaDefecto OR ([nombre] = @nombreDefecto AND [facultad] = @idFacultadDefecto);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SUC_ACTUALIZACION_PROGRAMA',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END
            ELSE
            BEGIN
                -- SI NO EXISTE: Crear nuevo programa en la tabla física Programa
                DECLARE @nuevoId UNIQUEIDENTIFIER = NEWID();

                INSERT INTO [dbo].[Programa] ([id], [facultad], [tipoDePrograma], [nombre], [coordinador], [estado])
                VALUES (@nuevoId, @idFacultadDefecto, @idTipoDeProgramaDefecto, @nombreDefecto, @idCoordinadorDefecto, 1);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SUC_REGISTRO_PROGRAMA',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'ERR_INESPERADO_REGISTRO_PROGRAMA',
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
