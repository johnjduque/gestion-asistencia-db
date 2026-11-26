USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_festivo_con_asistencia_paginado (CULM-001 B.1; CONTRACT §2.7.5, §3.2.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 ante validacion fallida).
-- Sesiones de la institucion del ADMINISTRADOR cuya fecha local cae en un festivo activo del anio y que NO se
-- cancelaron porque tienen asistencia registrada ("se reportan", §3.7 del prompt).
-- Filas: idSesion, idGrupo, nombreGrupo, nombreAsignatura, nombreDocente, fechaHoraInicio, fecha, nombreFestivo,
-- totalTomas (0 en B.1: B.2 cuenta TomaAsistencia), totalRegistrosAsistencia (cabeceras de asistencia de la sesion)
-- y totalRegistros (COUNT(1) OVER(), total de la consulta para la paginacion).
-- Paginacion: @numeroPagina >= 1 y @tamanoPagina entre 1 y PAGINACION/TAMANO_MAXIMO (PAG_001).
-- ============================================================================
-- SKILLS-BD lote 9 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END y TRY/CATCH de lectura que relanza (los rechazos siguen saliendo como THROW 51000). Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_festivo_con_asistencia_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @anio              INT,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 20
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @zonaHorariaSqlServer SYSNAME = CONVERT(SYSNAME, dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER'));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor y anio obligatorios (GEN_002)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @anio IS NULL)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/anio',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil ADMINISTRADOR
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Paginacion (PAG_001)
        IF @estadoResultado = 1
           AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
                OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
        BEGIN
            SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END

        -- PASO 5: Rechazo: THROW 51000 con el mensaje tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 6: Pagina de sesiones no canceladas en festivo con tomas o asistencias, de las instituciones del administrador
        SET @offset = (@numeroPagina - 1) * @tamanoPagina;

        SELECT
            idSesion                 = se.idSesion,
            idGrupo                  = se.idGrupo,
            nombreGrupo              = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
            nombreAsignatura         = g.nombreAsignatura,
            nombreDocente            = CAST(di.nombreCompleto AS NVARCHAR(400)),
            fechaHoraInicio          = se.fechaHoraInicio,
            fecha                    = df.fecha,
            nombreFestivo            = df.nombre,
            totalTomas               = se.totalTomas,
            totalRegistrosAsistencia = asis.total,
            totalRegistros           = COUNT(1) OVER()
        FROM dbo.uv_sesion_estado se
        INNER JOIN dbo.uv_dia_festivo df
        ON      df.estaActivo = 1 AND df.anio = @anio
        AND     df.fecha = CAST((se.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zonaHorariaSqlServer AS DATE)
        INNER JOIN dbo.uv_grupo g               ON g.id = se.idGrupo
        INNER JOIN dbo.uv_periodo_academico pa  ON pa.id = g.idPeriodoAcademico
        INNER JOIN dbo.uv_docente_identidad di  ON di.id = g.idDocente
        CROSS APPLY (SELECT total = COUNT(1) FROM dbo.uv_asistencia a WHERE a.idSesion = se.idSesion) asis
        WHERE se.estaCancelada = 0
          AND se.procedenciaTemporal IS NOT NULL
          AND (asis.total > 0 OR se.totalTomas > 0)
          AND pa.idInstitucion IN (SELECT a.idInstitucion FROM dbo.uv_administrador a WHERE a.idUsuario = @idUsuarioDefecto)
        ORDER BY se.fechaHoraInicio ASC, se.idSesion ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;
    END TRY
    BEGIN CATCH
        -- PASO 7: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
