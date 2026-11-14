USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEC-072 / DEC-073: una sesion empieza y termina el mismo dia en la zona institucional (TIEMPO/ZONA_HORARIA_SQLSERVER).
-- Recibe los instantes en UTC (como se guardan en dbo.Sesion). Fail-closed: una zona ausente o desconocida es GEN_001.
-- Cruzar la medianoche local es SES_028. No abre ni modifica transacciones: lo llaman usp_crear_sesion_interno (siempre) y
-- usp_actualizar_sesion_interno (solo cuando cambia el horario guardado, para poder renombrar sesiones antiguas).
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_sesion_mismo_dia_interno]
(
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @zonaHoraria          SYSNAME = CONVERT(SYSNAME, dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER'));
BEGIN
    SET NOCOUNT ON;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado         = 1;

    -- Sin instantes no hay nada que comparar: los obligatorios y el orden los valida usp_validar_sesion_operacion_interno.
    IF @fechaHoraInicio IS NULL OR @fechaHoraFin IS NULL
        RETURN;

    IF @zonaHoraria IS NULL OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE [name] = @zonaHoraria)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_001',
            @p_param1 = 'TIEMPO/ZONA_HORARIA_SQLSERVER',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
        RETURN;
    END

    IF CAST((@fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zonaHoraria AS DATE)
       <> CAST((@fechaHoraFin AT TIME ZONE 'UTC') AT TIME ZONE @zonaHoraria AS DATE)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SES_028',
            @p_param1 = @zonaHoraria,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
END;
GO
