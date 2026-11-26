USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_validar_plazo_justificacion_interno (CULM-001 D.1, HU026B; CONTRACT §2.2)
-- SKILLS-BD lote 2 (2026-11-25): antes usp_internal_validar_plazo_justificacion (renombrado, D3); el cuerpo se corrige en su lote de dominio.
--
-- Nucleo interno: NO se concede a ningun rol. Valida que la radicacion de una excusa este dentro del plazo de la sesion.
--   * limite NULL (falta ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER, o la sesion no existe) => REV_025
--   * SYSUTCDATETIME() >= limite                                                                                       => REV_020
-- Devuelve el limite en @fechaLimiteUtc (NULL si no se pudo calcular). Sin escrituras ni transacciones: lo invocan los
-- SP de radicacion v1 y v2, que deciden el commit o rollback. En exito deja intactos los mensajes y @estadoResultado.
-- REV_020 informa la ULTIMA fecha local admitida (yyyy-MM-dd); su mensaje tecnico lleva instante, limite y N.
-- ============================================================================
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): DECLARE en la cabecera (uno por variable), PASO n, fin de la
-- sesion por uv_sesion_registro (antes, la tabla) y TRY/CATCH que solo relanza (antes, sin TRY; mismo flujo de error).
-- Misma firma, mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_plazo_justificacion_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @fechaLimiteUtc          DATETIME2(7)   OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT            OUTPUT
)
AS
    DECLARE @fin         DATETIME2(7);
    DECLARE @ahora       DATETIME2(7) = SYSUTCDATETIME();
    DECLARE @dias        NVARCHAR(20);
    DECLARE @ultimoDia   NVARCHAR(10);
    DECLARE @instante    NVARCHAR(40);
    DECLARE @limiteTexto NVARCHAR(40);
    DECLARE @descartado  NVARCHAR(4000);
    DECLARE @zona        NVARCHAR(128) = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: fin de la sesion y limite de radicacion
        SET @fin = (SELECT s.fechaHoraFin FROM dbo.uv_sesion_registro s WHERE s.id = @idSesion);
        SET @fechaLimiteUtc = dbo.ufn_calcular_fecha_limite_justificacion(@fin);

        -- PASO 2: sin limite calculable (REV_025)
        IF @fechaLimiteUtc IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_025',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
            RETURN;
        END

        -- PASO 3: plazo vencido (REV_020)
        IF @ahora >= @fechaLimiteUtc
        BEGIN
            SET @dias = CONVERT(NVARCHAR(20), dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION'));
            SET @ultimoDia = CONVERT(NVARCHAR(10), DATEADD(DAY, -1, CAST((@fechaLimiteUtc AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE)), 23);
            SET @instante = CONVERT(NVARCHAR(40), @ahora, 126);
            SET @limiteTexto = CONVERT(NVARCHAR(40), @fechaLimiteUtc, 126);
            -- El mensaje de usuario usa solo {1} (ultimo dia local); el tecnico usa {1}=instante, {2}=limite, {3}=N.
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_020', @p_param1 = @ultimoDia,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @descartado OUTPUT;
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_020', @p_param1 = @instante, @p_param2 = @limiteTexto, @p_param3 = @dias,
                @mensajeUsuarioResultado = @descartado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        -- PASO 4: sin transaccion propia; el llamador decide (mismo flujo que antes, el error sube)
        THROW;
    END CATCH
END;
GO
