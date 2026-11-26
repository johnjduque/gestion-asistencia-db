USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_revisiones_cancelacion_decano_paginado (CULM-001 C.1; CONTRACT §2.5.7, SUPUESTO-C-14, DEC-043, DEC-065 (1))
--
-- READ_QUERY_RESULTSET paginado (THROW 51000 si la validacion falla). RBAC DECANO. SOLO CONSULTA Y AUDITORIA: todas las revisiones (cualquier
-- estado) de los grupos que tienen algun programa de la facultad del decano (ufn_programas_ambito_ejecutor); la decision final es del
-- coordinador, por eso esResolutorActual es siempre 0 y accionesPermitidas siempre vacio. @soloPendientes = revisiones que esperan al
-- resolutor (propuestas). @idPrograma fuera de su facultad -> COO_003; @codigoEstado inexistente -> RCN_002. Mismas columnas que la
-- bandeja del coordinador.
-- ============================================================================
-- SKILLS-BD lote 11 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, lecturas por vistas uv_* (antes, las tablas)
-- y TRY/CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_revisiones_cancelacion_decano_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 20,
    @soloPendientes    BIT = 0,
    @codigoEstado      NVARCHAR(20) = NULL,
    @idPrograma        UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        -- PASO 2: Validar parametros obligatorios (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        -- PASO 3: Validar perfil del ejecutor
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DECANO', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
        -- PASO 4: Validar paginacion (PAG_001)
        IF @estadoResultado = 1
           AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
        BEGIN
            SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END
        -- PASO 5: Estado de revision existente (RCN_002)
        IF @estadoResultado = 1 AND @codigoEstado IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.uv_estado_revision_cancelacion e WHERE e.codigo = UPPER(TRIM(@codigoEstado)))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCN_002', @p_param1 = @codigoEstado,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END
        -- PASO 6: Programa de la facultad del decano (COO_003)
        IF @estadoResultado = 1 AND @idPrograma IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_ambito_ejecutor(@idUsuarioDefecto) a WHERE a.idPrograma = @idPrograma AND a.rol = N'DECANO')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'COO_003',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END
        -- PASO 7: Rechazo de validacion: se lanza con el detalle tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 8: Pagina de revisiones de la facultad del decano
        SET @offset = (@numeroPagina - 1) * @tamanoPagina;
        SELECT
            rv.*,
            idPrograma = x.idPrograma,
            nombrePrograma = x.nombre,
            porcentajeActual = rs.porcentajeInasistencia,
            horasFaltaActual = rs.horasFalta,
            horasDictadasActual = rs.horasDictadas,
            umbralPerdida = rs.umbralPerdida,
            esResolutorActual = CAST(0 AS BIT),
            accionesPermitidas = CAST(N'' AS NVARCHAR(200)),
            totalRegistros = COUNT(1) OVER(),
            -- CIERRE-W3I: nivel de permanencia vigente (REGULAR/RIESGO/PERDIDA) con la unica regla y los umbrales del catalogo
            codigoPermanenciaActual = rs.codigoPermanencia
        FROM dbo.uv_revision_cancelacion rv
        CROSS APPLY (
            SELECT TOP 1 idPrograma = p.id, nombre = p.nombrePrograma
            FROM dbo.ufn_programas_grupo(rv.idGrupo) pg
            INNER JOIN dbo.ufn_programas_ambito_ejecutor(@idUsuarioDefecto) a ON a.idPrograma = pg.idPrograma AND a.rol = N'DECANO'
            INNER JOIN dbo.uv_programa p ON p.id = pg.idPrograma
            WHERE (@idPrograma IS NULL OR p.id = @idPrograma)
            ORDER BY p.nombrePrograma ASC, p.id ASC
        ) x
        LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo rs ON rs.idEstudianteGrupo = rv.idEstudianteGrupo
        WHERE (@codigoEstado IS NULL OR rv.codigoEstado = UPPER(TRIM(@codigoEstado)))
          AND (@soloPendientes IS NULL OR @soloPendientes = 0 OR rv.requiereAccionResolutor = 1)
        ORDER BY rv.requiereAccionResolutor DESC, rv.fechaActualizacionUtc DESC, rv.id ASC
        OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
    END TRY
    BEGIN CATCH
        -- PASO 9: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
