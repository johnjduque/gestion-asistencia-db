USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_calendario_estudiante (ATA D7)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (sin paginacion: rango maximo de 31 dias).
-- Sesiones de los grupos con matricula inscrita del estudiante cuyo inicio cae entre @desde y @hasta (ambos inclusivos, fecha LOCAL
-- institucional), una fila por sesion de uv_sesion_calendario (solicitudes pendientes o rechazadas excluidas), ordenadas por inicio.
-- @hasta >= @desde y maximo 31 dias; si no, CAL_001. Validacion compartida en usp_validar_rango_calendario_interno (perfil
-- ESTUDIANTE); THROW 51000 si falla.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_calendario_estudiante]
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
    DECLARE @codigoInscrita          NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_validar_rango_calendario_interno
        @idUsuarioEjecutor = @idUsuario, @idCorrelacion = @idCorrelacion, @codigoPerfilRequerido = 'ESTUDIANTE',
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
      AND   c.idGrupo IN (SELECT eg.grupo
                          FROM dbo.EstudianteGrupo eg
                          INNER JOIN dbo.Estudiante est ON est.id = eg.estudiante
                          INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
                          WHERE est.usuario = @idUsuarioValidado AND ee.codigo = @codigoInscrita)
    ORDER BY c.fechaHoraInicioUtc ASC, c.idSesion ASC;
END;
GO
