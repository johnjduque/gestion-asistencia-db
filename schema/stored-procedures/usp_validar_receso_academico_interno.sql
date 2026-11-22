USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_validar_receso_academico_interno (DEC-081) — nucleo de validacion de un dia de receso academico; sin EXECUTE para el rol
-- runtime. No abre transaccion: lo llama usp_crear_receso_academico dentro de la suya. Bloquea la fila del periodo y el indice de
-- recesos (UPDLOCK, HOLDLOCK) para serializar altas concurrentes del mismo dia.
--
-- Reglas, en este orden (la primera que falla corta; en exito deja los mensajes y @estadoResultado = 1 intactos):
--   1. @fecha obligatoria (GEN_002).
--   2. Motivo: se recorta; no vacio y <= RECESO/MOTIVO_LONGITUD_MAXIMA (REC_008). Sale recortado en @motivoNormalizado.
--   3. El periodo existe y es de la institucion indicada (PER_001).
--   4. El periodo no esta cerrado: PeriodoAcademico.fechaCierreUtc NULL (REC_007).
--   5. La fecha esta dentro del periodo, ambos extremos incluidos (REC_003).
--   6. La fecha es futura: posterior a hoy en TIEMPO/ZONA_HORARIA_SQLSERVER (REC_004). Hoy no vale.
--   7. La fecha no es un festivo activo (REC_005, con el nombre del festivo).
--   8. No hay otro receso activo del mismo periodo en esa fecha (REC_006).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_receso_academico_interno]
(
    @idPeriodo                UNIQUEIDENTIFIER,
    @fecha                    DATE,
    @motivo                   NVARCHAR(4000),
    @idInstitucion            UNIQUEIDENTIFIER,
    @idCorrelacion            UNIQUEIDENTIFIER,
    @motivoNormalizado        NVARCHAR(200) OUTPUT,
    @mensajeUsuarioResultado  NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000) OUTPUT,
    @estadoResultado          BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPeriodoDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPeriodo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @motivoLimpio         NVARCHAR(4000)   = LTRIM(RTRIM(@motivo));
    DECLARE @longitudMaxima       INT              = dbo.ufn_obtener_parametro_int(NULL, 'RECESO', 'MOTIVO_LONGITUD_MAXIMA');
    DECLARE @zonaHorariaSqlServer SYSNAME;
    DECLARE @hoy                  DATE;
    DECLARE @nombrePeriodo        NVARCHAR(50);
    DECLARE @fechaInicio          DATE;
    DECLARE @fechaFin             DATE;
    DECLARE @fechaCierreUtc       DATETIME2(7);
    DECLARE @idPeriodoEncontrado  UNIQUEIDENTIFIER;
    DECLARE @nombreFestivo        NVARCHAR(120);
    DECLARE @codigoRechazo        VARCHAR(20);
    DECLARE @p1                   NVARCHAR(500);
    DECLARE @p2                   NVARCHAR(500);

    SELECT
        @motivoNormalizado = NULL,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
BEGIN
    SET NOCOUNT ON;

    -- 1. Fecha obligatoria
    IF @fecha IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'fecha',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SELECT @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto), @estadoResultado = 0;
        RETURN;
    END

    -- 2. Motivo: parametro de longitud y valor recortado
    IF @longitudMaxima IS NULL OR @longitudMaxima < 1
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_001', @p_param1 = 'RECESO/MOTIVO_LONGITUD_MAXIMA',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SELECT @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto), @estadoResultado = 0;
        RETURN;
    END
    IF @motivoLimpio IS NULL OR LEN(@motivoLimpio) = 0 OR LEN(@motivoLimpio) > @longitudMaxima
    BEGIN
        SET @p1 = CONVERT(NVARCHAR(20), @longitudMaxima);
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'REC_008', @p_param1 = @p1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SELECT @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto), @estadoResultado = 0;
        RETURN;
    END
    SET @motivoNormalizado = CAST(@motivoLimpio AS NVARCHAR(200));

    -- 3-5. Periodo de la institucion (bloqueado), cierre y rango de fechas
    SELECT  @idPeriodoEncontrado = pa.id, @nombrePeriodo = pa.nombre, @fechaInicio = pa.fechaInicio, @fechaFin = pa.fechaFin,
            @fechaCierreUtc = pa.fechaCierreUtc
    FROM    dbo.PeriodoAcademico pa WITH (UPDLOCK, HOLDLOCK)
    WHERE   pa.id = @idPeriodoDefecto AND pa.institucion = @idInstitucion;

    IF @idPeriodoEncontrado IS NULL
        SET @codigoRechazo = 'PER_001';
    ELSE IF @fechaCierreUtc IS NOT NULL
    BEGIN
        SET @codigoRechazo = 'REC_007';
        SET @p1 = @nombrePeriodo;
    END
    ELSE IF @fecha < @fechaInicio OR @fecha > @fechaFin
    BEGIN
        SET @codigoRechazo = 'REC_003';
        SELECT @p1 = CONVERT(NVARCHAR(10), @fechaInicio, 103), @p2 = CONVERT(NVARCHAR(10), @fechaFin, 103);
    END

    -- 6. Fecha futura en la zona horaria institucional
    IF @codigoRechazo IS NULL
    BEGIN
        SELECT TOP 1 @zonaHorariaSqlServer = CONVERT(SYSNAME, p.valor)
        FROM dbo.uv_parametro p
        WHERE p.grupo = 'TIEMPO' AND p.clave = 'ZONA_HORARIA_SQLSERVER' AND p.estaActivo = 1;

        IF @zonaHorariaSqlServer IS NULL OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE [name] = @zonaHorariaSqlServer)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001', @p_param1 = 'TIEMPO/ZONA_HORARIA_SQLSERVER',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SELECT @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto), @estadoResultado = 0;
            RETURN;
        END

        SET @hoy = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @zonaHorariaSqlServer AS DATE);
        IF @fecha <= @hoy
        BEGIN
            SET @codigoRechazo = 'REC_004';
            SELECT @p1 = CONVERT(NVARCHAR(10), @fecha, 103), @p2 = CONVERT(NVARCHAR(10), @hoy, 103);
        END
    END

    -- 7. No es festivo
    IF @codigoRechazo IS NULL
    BEGIN
        SELECT TOP 1 @nombreFestivo = df.nombre FROM dbo.uv_dia_festivo df WHERE df.fecha = @fecha AND df.estaActivo = 1;
        IF @nombreFestivo IS NOT NULL
        BEGIN
            SET @codigoRechazo = 'REC_005';
            SET @p1 = @nombreFestivo;
        END
    END

    -- 8. No esta repetida en el periodo
    IF @codigoRechazo IS NULL
       AND EXISTS (SELECT 1 FROM dbo.PeriodoRecesoAcademico r WITH (UPDLOCK, HOLDLOCK)
                   WHERE r.periodoAcademico = @idPeriodoDefecto AND r.fecha = @fecha AND r.estaActivo = 1)
    BEGIN
        SET @codigoRechazo = 'REC_006';
        SET @p1 = CONVERT(NVARCHAR(10), @fecha, 103);
    END

    IF @codigoRechazo IS NOT NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = @codigoRechazo, @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SELECT @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto), @estadoResultado = 0;
    END
END;
GO
