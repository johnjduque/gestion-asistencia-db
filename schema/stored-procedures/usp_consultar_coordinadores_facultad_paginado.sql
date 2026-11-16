USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_coordinadores_facultad_paginado (CIERRE-W1B, punto 3: coordinadores del decano con filtros y
-- paginacion en servidor)
--
-- Directorio de los coordinadores de la facultad del decano ejecutor: UNA fila por coordinador, con su primer programa
-- (por nombre) si tiene alguno en la facultad, o sin programa si aun no lo tiene (HU121/HU122 D2). Cada fila trae los
-- nombres separados, el correo, el estado del usuario/rol y, del programa, los docentes con vinculacion activa y los
-- grupos habilitados (certificacion F3).
-- @busqueda compara contra nombre, documento, correo y programa (subcadena, sin comodines); @estaActivo filtra por el
-- estado efectivo del coordinador; @sinPrograma = 1 deja solo los que no tienen programa y 0 solo los que si.
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas de los comandos.
-- Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001).
-- Ambito: perfil DECANO; solo coordinadores cuya facultad es la que tiene a su cargo. Un decano sin facultad no ve filas.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_coordinadores_facultad_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @busqueda           NVARCHAR(100)    = NULL,
    @estaActivo         BIT              = NULL,
    @sinPrograma        BIT              = NULL
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @busquedaFiltro          NVARCHAR(100) = NULLIF(TRIM(@busqueda), '');
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: Correlacion, ejecutor, perfil DECANO y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'DECANO',
            @numeroPagina = @numeroPagina,
            @tamanoPagina = @tamanoPagina,
            @idUsuarioValidado = @idUsuario OUTPUT,
            @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 2: Consulta y retorno de resultados (el ambito es la facultad del decano ejecutor)
        WITH coordinadores AS (
            SELECT  c.id, c.idUsuario, c.numeroIdentificacion, c.nombreCompleto, c.idPrograma, c.nombrePrograma,
                    c.estaActivoCoordinador, c.primerNombre, c.segundoNombre, c.primerApellido, c.segundoApellido,
                    c.correo, c.estaActivoRolCoordinador, c.nombreFacultad,
                    orden = ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY c.nombrePrograma ASC, c.idPrograma ASC)
            FROM    dbo.uv_coordinador c
            WHERE   c.idFacultad IN (SELECT d.idFacultad FROM dbo.uv_decano d WHERE d.idUsuario = @idUsuario AND d.idFacultad IS NOT NULL)
        )
        SELECT
            c.id,
            c.idUsuario,
            c.numeroIdentificacion,
            c.nombreCompleto,
            c.idPrograma,
            c.nombrePrograma,
            c.estaActivoCoordinador,
            c.primerNombre,
            c.segundoNombre,
            c.primerApellido,
            c.segundoApellido,
            c.correo,
            c.estaActivoRolCoordinador,
            c.nombreFacultad,
            totalDocentes = (SELECT COUNT(DISTINCT dp.idDocente) FROM dbo.uv_docente_programa dp
                              WHERE dp.idPrograma = c.idPrograma AND dp.estaActivoDocentePrograma = 1),
            totalGrupos = (SELECT COUNT(*) FROM dbo.uv_grupo_programa gp
                            WHERE gp.idPrograma = c.idPrograma AND gp.grupoEstaHablitado = 1),
            totalRegistros = COUNT(*) OVER()
        FROM coordinadores c
        WHERE c.orden = 1
            AND (@estaActivo IS NULL OR c.estaActivoCoordinador = @estaActivo)
            AND (@sinPrograma IS NULL OR (@sinPrograma = 1 AND c.idPrograma IS NULL) OR (@sinPrograma = 0 AND c.idPrograma IS NOT NULL))
            AND (
                @busquedaFiltro IS NULL
                OR CHARINDEX(@busquedaFiltro, c.nombreCompleto) > 0
                OR CHARINDEX(@busquedaFiltro, CONVERT(NVARCHAR(20), c.numeroIdentificacion)) > 0
                OR CHARINDEX(@busquedaFiltro, ISNULL(c.correo, N'')) > 0
                OR CHARINDEX(@busquedaFiltro, ISNULL(c.nombrePrograma, N'')) > 0
            )
        ORDER BY c.nombreCompleto ASC, c.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO
