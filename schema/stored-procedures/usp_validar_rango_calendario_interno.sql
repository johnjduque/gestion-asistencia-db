USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_validar_rango_calendario_interno (ATA D7)
--
-- Validacion compartida de las consultas del calendario de sesiones: correlacion, ejecutor y perfil (via
-- usp_validar_consulta_paginada_interno; aqui se restaura el SESSION_CONTEXT) y rango de fechas locales institucionales:
-- @desde y @hasta presentes, @hasta >= @desde y como maximo @maximoDias dias (CAL_001). Devuelve el ejecutor normalizado y el rango
-- como instantes UTC [@desdeUtc, @hastaUtcExclusivo) segun TIEMPO/ZONA_HORARIA_SQLSERVER. El caller hace THROW 51000 con el
-- mensaje tecnico cuando @estadoResultado = 0. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_rango_calendario_interno]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @codigoPerfilRequerido   NVARCHAR(50),
    @desde                   DATE,
    @hasta                   DATE,
    @idUsuarioValidado       UNIQUEIDENTIFIER OUTPUT,
    @desdeUtc                DATETIME2(7) OUTPUT,
    @hastaUtcExclusivo       DATETIME2(7) OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @maximoDias      INT = 31;
    DECLARE @contextoPrevio  SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @offsetIgnorado  INT;
    DECLARE @zonaTexto       NVARCHAR(128) = CAST(dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(128));
    DECLARE @zona            NVARCHAR(128) = IIF(@zonaTexto IS NULL OR @zonaTexto = N'', N'SA Pacific Standard Time', @zonaTexto);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500), @p3 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;

    SELECT @desdeUtc = NULL, @hastaUtcExclusivo = NULL;
    EXEC dbo.usp_validar_consulta_paginada_interno
        @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @codigoPerfilRequerido = @codigoPerfilRequerido,
        @numeroPagina = 1, @tamanoPagina = 1,
        @idUsuarioValidado = @idUsuarioValidado OUTPUT, @offset = @offsetIgnorado OUTPUT,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;

    IF @estadoResultado = 1
       AND (@desde IS NULL OR @hasta IS NULL OR @hasta < @desde OR DATEDIFF(DAY, @desde, @hasta) + 1 > @maximoDias)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(10), @desde, 23), @p2 = CONVERT(NVARCHAR(10), @hasta, 23), @p3 = CONVERT(NVARCHAR(10), @maximoDias);
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'CAL_001', @p_param1 = @p1, @p_param2 = @p2, @p_param3 = @p3,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacion AS NVARCHAR(50)));
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
        SELECT @desdeUtc = CAST((CAST(@desde AS DATETIME2(7)) AT TIME ZONE @zona) AT TIME ZONE 'UTC' AS DATETIME2(7)),
               @hastaUtcExclusivo = CAST((CAST(DATEADD(DAY, 1, @hasta) AS DATETIME2(7)) AT TIME ZONE @zona) AT TIME ZONE 'UTC' AS DATETIME2(7));
END;
GO
