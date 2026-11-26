USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU121/HU122: valida que el coordinador exista y pertenezca a la facultad indicada.
-- Devuelve GEN_001 ('Coordinador') tanto si no existe como si es de otra facultad, para no revelar su existencia.
-- Sin transaccion propia: corre dentro de la fachada publica que la invoca.
-- SKILLS-BD lote 4 (2026-11-25): PASO n y correlacion por defecto (@idCorrelacionDefecto) en los mensajes; mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_coordinador_de_facultad_interno]
(
    @idCoordinador           UNIQUEIDENTIFIER,
    @idFacultad              UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
BEGIN
    SET NOCOUNT ON;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

    BEGIN TRY
        -- PASO 1: el coordinador existe y es de la facultad (GEN_001 en ambos casos)
        IF @idCoordinador IS NULL OR @idFacultad IS NULL
           OR NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idCoordinador AND idFacultad = @idFacultad)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Coordinador',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
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
