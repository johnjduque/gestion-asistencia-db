USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEC-073: decanos, coordinadores y docentes usan el correo institucional, el mismo dominio del estudiante
-- (REGISTRO/DOMINIO_CORREO_ESTUDIANTE, con dbo.ufn_correo_cumple_dominio_institucional). Un correo que no lo cumple es VCE_008
-- con el dominio vigente. NULL o vacio no se valida aqui (el llamador decide si el correo es obligatorio). Lo llaman los altas
-- de personal con usuario nuevo y la actualizacion del coordinador cuando cambia su correo: los correos ya guardados no se
-- revalidan. No abre ni modifica transacciones.
-- SKILLS-BD lote 8 (2026-11-26): PASO n, IF con BEGIN/END y TRY/CATCH (relanza con transaccion abierta; sin ella, SYS_001). Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_correo_institucional_personal_interno]
(
    @correo                  NVARCHAR(255),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @dominioInstitucional NVARCHAR(255)    = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
BEGIN
    SET NOCOUNT ON;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado         = 1;

    BEGIN TRY
        -- PASO 1: Un correo vacio no se valida (pasa)
        IF NULLIF(TRIM(@correo), N'') IS NULL
        BEGIN
            RETURN;
        END

        -- PASO 2: El correo debe pertenecer al dominio institucional (VCE_008)
        IF dbo.ufn_correo_cumple_dominio_institucional(@correo, @dominioInstitucional) = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VCE_008',
                @p_param1 = @dominioInstitucional,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        -- PASO 3: corre dentro de la transaccion del llamador: con transaccion abierta relanza para que el llamador revierta
        -- (comportamiento previo, sin TRY); sin transaccion devuelve el triplete SYS_001.
        IF XACT_STATE() <> 0
        BEGIN
            THROW;
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
