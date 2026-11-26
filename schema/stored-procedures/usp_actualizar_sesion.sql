USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Contrato v1 (DB-GP-001C): firma y resultset de 4 columnas sin cambios.
-- UTC-D06-POST-FREEZE: la logica vive en usp_actualizar_sesion_interno. v1 no transmite zona horaria:
-- toda actualizacion v1 deja procedenciaTemporal = NULL (INDETERMINADA) en el mismo UPDATE que las horas,
-- incluso si la sesion estaba confirmada y el valor temporal no cambia.
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): PASO n y TRY/CATCH que relanza (antes, sin TRY).
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_sesion]
(
    @idSesion           UNIQUEIDENTIFIER,
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
        -- PASO 1: actualizar la sesion con el nucleo compartido (procedencia por defecto)
        EXEC dbo.usp_actualizar_sesion_interno
            @idSesion = @idSesion,
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
