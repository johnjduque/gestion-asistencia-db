USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_faltas_reclamables_estudiante (ATA D10, HU026B; ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS J.1)
--
-- READ_QUERY_RESULTSET paginado (THROW 51000 si la validacion falla: correlacion, idUsuarioEjecutor GEN_002, RBAC ESTUDIANTE, PAG_001).
-- Solo las faltas reclamables del propio estudiante (uv_falta_reclamable_estudiante): tomas en SJC de sesiones ya avisadas, sin reclamo
-- radicado, con plazo vigente y matricula activa. Columnas de la vista sin idUsuarioEstudiante, mas totalRegistros (COUNT(*) OVER()).
-- Orden fechaHoraFinUtc DESC, numeroToma ASC.
-- ============================================================================
-- SKILLS-BD lote 7 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END y TRY/CATCH de lectura; mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_faltas_reclamables_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 20
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
        -- PASO 1: Validar el identificador de correlacion y el ejecutor (GEN_002)
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        -- PASO 2: Perfil ESTUDIANTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ESTUDIANTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
        -- PASO 3: Validar la paginacion (PAG_001)
        IF @estadoResultado = 1
           AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
        BEGIN
            SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END
        -- PASO 4: Rechazo de validacion
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 5: Faltas reclamables del estudiante ejecutor
        SET @offset = (@numeroPagina - 1) * @tamanoPagina;
        SELECT
            idEstudianteGrupo = f.idEstudianteGrupo, idGrupo = f.idGrupo, nombreGrupo = f.nombreGrupo,
            idAsignatura = f.idAsignatura, nombreAsignatura = f.nombreAsignatura,
            idSesion = f.idSesion, numeroSesion = f.numeroSesion, fechaHoraInicioUtc = f.fechaHoraInicioUtc, fechaHoraFinUtc = f.fechaHoraFinUtc,
            idToma = f.idToma, numeroToma = f.numeroToma, fechaPuntoControlUtc = f.fechaPuntoControlUtc, fechaLimiteReclamoUtc = f.fechaLimiteReclamoUtc,
            totalRegistros = COUNT(1) OVER()
        FROM dbo.uv_falta_reclamable_estudiante f
        WHERE f.idUsuarioEstudiante = @idUsuarioDefecto
        ORDER BY f.fechaHoraFinUtc DESC, f.numeroToma ASC, f.idToma ASC
        OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
    END TRY
    BEGIN CATCH
        -- PASO 6: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
