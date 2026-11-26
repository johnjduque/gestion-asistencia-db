USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_grupos_docente (CIERRE-W3I)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET de UNA fila. Solo lectura: sin transaccion.
-- Totales de los grupos del DOCENTE titular para su tablero y su lista de grupos (el cliente ya no suma ni calcula):
--   * gruposHabilitados    = grupos del docente cuyo periodo esta vigente hoy (uv_grupo.grupoEstaHablitado = 1);
--   * estudiantesActivos   = suma de las matriculas activas de esos grupos (uv_grupo.estudiantesActivos);
--   * cupoTotal            = suma de la capacidad maxima de esos grupos;
--   * tasaOcupacion        = 100 x estudiantesActivos / cupoTotal, DECIMAL(7,2); NULL si el cupo total es 0 (no se asume un valor).
-- Ambito DENTRO del SP: solo los grupos donde el ejecutor es titular (uv_docente_identidad.idUsuario). Perfil DOCENTE validado con
-- usp_validar_consulta_paginada_interno (correlacion, ejecutor y perfil: VAL_001 / SEC_001); la pagina 1 de tamano 1 que se le pasa
-- es solo para reutilizar la validacion, esta consulta no pagina. Un docente sin grupos habilitados recibe una fila en cero.
-- El SESSION_CONTEXT que fija la validacion se restaura siempre (exito y error).
-- ============================================================================
-- SKILLS-BD lote 10 (2026-11-26): PASO n tambien en el restablecimiento del contexto y en el CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_grupos_docente]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Correlacion, ejecutor y perfil DOCENTE (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'DOCENTE',
            @numeroPagina = 1,
            @tamanoPagina = 1,
            @idUsuarioValidado = @idUsuario OUTPUT,
            @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 2: Consulta y retorno de resultados (el ambito son los grupos del docente ejecutor)
        -- ISNULL sobre agregacion (permitido): SUM de un conjunto vacio es NULL y el contrato devuelve 0.
        SELECT
            gruposHabilitados  = COUNT(g.id),
            estudiantesActivos = ISNULL(SUM(g.estudiantesActivos), 0),
            cupoTotal          = ISNULL(SUM(g.capacidadMaximaPermitida), 0),
            tasaOcupacion      = CAST(IIF(ISNULL(SUM(g.capacidadMaximaPermitida), 0) = 0, NULL,
                                          100.0 * SUM(g.estudiantesActivos) / SUM(g.capacidadMaximaPermitida)) AS DECIMAL(7,2))
        FROM dbo.uv_grupo g
        WHERE g.grupoEstaHablitado = 1
          AND EXISTS (SELECT 1 FROM dbo.uv_docente_identidad di WHERE di.id = g.idDocente AND di.idUsuario = @idUsuario);

        -- PASO 3: Restaurar el contexto de sesion previo
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        -- PASO 4: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO
