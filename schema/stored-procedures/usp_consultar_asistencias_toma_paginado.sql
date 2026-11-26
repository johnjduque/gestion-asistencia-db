USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_asistencias_toma_paginado (CULM-001 B.2, HU175; CONTRACT §2.8.4, §3.2.5 GET /tomas/{id}/asistencias)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001,
-- PAG_001, TOM_001, SEC_002). RBAC DOCENTE titular de la sesion de la toma. Filas: matriculas ACTIVAS
-- (MATRICULA/ESTADO_INSCRITA) del grupo con su detalle en la toma (LEFT: estado NULL si no hay registro), orden
-- nombreCompletoEstudiante, + totalRegistros. @numeroPagina >= 1 y @tamanoPagina entre 1 y PAGINACION/TAMANO_MAXIMO.
-- ============================================================================
-- SKILLS-BD lote 12 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, lecturas por vistas uv_* (antes, las tablas)
-- y TRY/CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asistencias_toma_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idToma            UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 50
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTomaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idToma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @idSesion UNIQUEIDENTIFIER;
    DECLARE @codigoActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        -- PASO 2: Validar parametros obligatorios (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        -- PASO 3: Validar perfil del ejecutor (DOCENTE)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
        -- PASO 4: Validar paginacion (PAG_001)
        IF @estadoResultado = 1
           AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
                OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
        BEGIN
            SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END
        -- PASO 5: Toma existente (TOM_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idSesion = t.idSesion FROM dbo.uv_toma_asistencia_registro t WHERE t.id = @idTomaDefecto;
            IF @idSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_001', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        -- PASO 6: Titularidad del docente sobre la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioDefecto, @idEntidadPadre = @idSesion, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
        -- PASO 7: Rechazo de validacion: se lanza con el detalle tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 8: Pagina de estudiantes activos con su registro en la toma
        SET @offset = (@numeroPagina - 1) * @tamanoPagina;
        SELECT
            idEstudiante             = eg.idEstudiante,
            nombreCompletoEstudiante = eg.nombreCompletoEstudiante,
            codigoRazonCausa         = rc.codigo,
            registradoPorEstudiante  = d.registradoPorEstudiante,
            fechaRegistroUtc         = d.fechaRegistroUtc,
            totalRegistros           = COUNT(1) OVER()
        FROM dbo.uv_toma_asistencia_registro t
        INNER JOIN dbo.uv_sesion_registro s ON s.id = t.idSesion
        INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = s.idGrupo AND eg.codigoEstadoEstudiante = @codigoActiva
        OUTER APPLY (
            SELECT TOP 1 razonCausa = da.idRazonCausa, da.registradoPorEstudiante, da.fechaRegistroUtc
            FROM dbo.uv_asistencia_registro a
            INNER JOIN dbo.uv_detalle_asistencia_registro da ON da.idAsistencia = a.id AND da.idToma = t.id
            WHERE a.idEstudianteGrupo = eg.id AND a.idSesion = t.idSesion
        ) d
        LEFT JOIN dbo.uv_razon_causa rc ON rc.id = d.razonCausa
        WHERE t.id = @idTomaDefecto
        ORDER BY eg.nombreCompletoEstudiante ASC, eg.idEstudiante ASC
        OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
    END TRY
    BEGIN CATCH
        -- PASO 9: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
