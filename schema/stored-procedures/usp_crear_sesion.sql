USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Contrato v1 (DB-GP-001C): firma y resultset de 4 columnas sin cambios.
-- UTC-D06-POST-FREEZE: la logica vive en usp_crear_sesion_interno. v1 no transmite zona horaria,
-- por eso la sesion creada por esta via queda con procedenciaTemporal = NULL (INDETERMINADA),
-- escrita en el mismo INSERT que las horas.
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): PASO n y TRY/CATCH que relanza (antes, sin TRY).
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_sesion]
(
    @idGrupo            UNIQUEIDENTIFIER,
    @nombre             NVARCHAR(50),
    @fechaHoraInicio    DATETIME2,
    @fechaHoraFin       DATETIME2,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: crear la sesion con el nucleo compartido (procedencia por defecto)
        EXEC dbo.usp_crear_sesion_interno
            @idGrupo = @idGrupo,
            @nombre = @nombre,
            @fechaHoraInicio = @fechaHoraInicio,
            @fechaHoraFin = @fechaHoraFin,
            @idCorrelacion = @idCorrelacion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @procedenciaTemporal = NULL,
            @idCorrelacionResultado = @idCorrelacionDefecto OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END TRY
    BEGIN CATCH
        -- PASO 2: el nucleo ya captura sus errores; el CATCH solo relanza (mismo flujo)
        THROW;
    END CATCH

    -- PASO 3: retorno unificado de resultados
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
