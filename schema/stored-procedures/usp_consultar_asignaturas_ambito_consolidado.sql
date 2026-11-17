USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_asignaturas_ambito_consolidado (CIERRE-W2A, punto 3)
--
-- Opciones del filtro asignaturas del consolidado de asistencia (HU061): asignaturas
-- con grupos dentro del ambito del ejecutor (uv_auth_grupo, fail-closed: el coordinador ve su programa, el decano su
-- facultad y el administrador su institucion) para el periodo consultado (@idPeriodoAcademico NULL = todos). Sin
-- paginacion: es una lista de opciones de un selector, acotada por la cantidad de asignaturas distintos del ambito.
--
-- Resultset: READ_QUERY_RESULTSET (id, nombre); NO es el resultset canonico de 4 columnas de los comandos. Las
-- fallas de validacion se propagan con THROW (VAL_001 / SEC_001). SESSION_CONTEXT: se captura el previo y SIEMPRE se
-- restaura (exito y error). Solo lectura: sin transaccion.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asignaturas_ambito_consolidado]
(
    @idUsuarioEjecutor   UNIQUEIDENTIFIER,
    @idCorrelacion       UNIQUEIDENTIFIER,
    @idPeriodoAcademico  UNIQUEIDENTIFIER = NULL
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
        -- PASO 1: Correlacion, ejecutor y perfil; fija el contexto para uv_auth_grupo (pagina 1 de tamano 1: no se pagina)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'COORDINADOR,DECANO,ADMINISTRADOR',
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

        -- PASO 2: asignaturas distintos de los grupos del ambito, por nombre
        SELECT  id     = g.idAsignatura,
                nombre = MAX(g.nombreAsignatura)
        FROM    dbo.uv_auth_grupo g
        WHERE   @idPeriodoAcademico IS NULL OR g.idPeriodoAcademico = @idPeriodoAcademico
        GROUP BY g.idAsignatura
        ORDER BY MAX(g.nombreAsignatura) ASC, g.idAsignatura ASC;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO
