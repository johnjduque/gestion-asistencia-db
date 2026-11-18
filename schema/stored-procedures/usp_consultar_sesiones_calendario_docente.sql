USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_calendario_docente (ATA D7)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (sin paginacion: rango maximo de 31 dias).
-- Sesiones de los grupos donde el ejecutor es docente titular cuyo inicio cae entre @desde y @hasta (ambos inclusivos, fecha LOCAL
-- institucional), con las mismas columnas y orden que usp_consultar_sesiones_calendario_estudiante. @hasta >= @desde y maximo 31
-- dias; si no, CAL_001. Validacion compartida en usp_validar_rango_calendario_interno (perfil DOCENTE); THROW 51000 si falla.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_calendario_docente]
(
    @idUsuario      UNIQUEIDENTIFIER,
    @desde          DATE,
    @hasta          DATE,
    @idCorrelacion  UNIQUEIDENTIFIER
)
AS
    DECLARE @idUsuarioValidado       UNIQUEIDENTIFIER;
    DECLARE @desdeUtc                DATETIME2(7);
    DECLARE @hastaUtcExclusivo       DATETIME2(7);
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_validar_rango_calendario_interno
        @idUsuarioEjecutor = @idUsuario, @idCorrelacion = @idCorrelacion, @codigoPerfilRequerido = 'DOCENTE',
        @desde = @desde, @hasta = @hasta,
        @idUsuarioValidado = @idUsuarioValidado OUTPUT, @desdeUtc = @desdeUtc OUTPUT, @hastaUtcExclusivo = @hastaUtcExclusivo OUTPUT,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT  c.idSesion, c.idGrupo, c.codigoGrupo, c.nombreGrupo, c.idAsignatura, c.codigoAsignatura, c.nombreAsignatura,
            c.idDocente, c.nombreDocente, c.fechaHoraInicioUtc, c.fechaHoraFinUtc, c.esExtraordinaria, c.estaCancelada,
            c.motivoCancelacion, c.esCancelacionAutomatica, c.nombreDiaFestivo
    FROM    dbo.uv_sesion_calendario c
    WHERE   c.fechaHoraInicioUtc >= @desdeUtc AND c.fechaHoraInicioUtc < @hastaUtcExclusivo
      AND   c.idDocente IN (SELECT d.id FROM dbo.Docente d WHERE d.usuario = @idUsuarioValidado)
    ORDER BY c.fechaHoraInicioUtc ASC, c.idSesion ASC;
END;
GO
