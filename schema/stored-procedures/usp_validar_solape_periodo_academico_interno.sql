USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- BD-3 (decision del responsable 2026-11-22): los periodos academicos de una misma institucion no pueden tener fechas solapadas.
-- Validador interno (sin escrituras, sin transaccion propia: lo llaman usp_crear_periodo_academico y usp_actualizar_periodo_academico dentro
-- de la transaccion que ya bloquea los periodos de la institucion). Dos periodos se solapan si comparten al menos un dia (limites inclusivos):
-- existente.fechaInicio <= @fechaFin AND existente.fechaFin >= @fechaInicio. @idPeriodoExcluir omite el periodo que se esta editando.
-- Si se solapa: estadoResultado = 0, PER_012 con el nombre del primer periodo en conflicto (el de inicio mas antiguo).
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_solape_periodo_academico_interno]
(
    @idInstitucion           UNIQUEIDENTIFIER,
    @fechaInicio             DATE,
    @fechaFin                DATE,
    @idPeriodoExcluir        UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreEnConflicto    NVARCHAR(50);

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT TOP (1) @nombreEnConflicto = pa.nombre
        FROM dbo.PeriodoAcademico pa
        WHERE pa.institucion = @idInstitucion
          AND (@idPeriodoExcluir IS NULL OR pa.id <> @idPeriodoExcluir)
          AND pa.fechaInicio <= @fechaFin
          AND pa.fechaFin >= @fechaInicio
        ORDER BY pa.fechaInicio, pa.id;

        IF @nombreEnConflicto IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PER_012', @p_param1 = @nombreEnConflicto,
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
