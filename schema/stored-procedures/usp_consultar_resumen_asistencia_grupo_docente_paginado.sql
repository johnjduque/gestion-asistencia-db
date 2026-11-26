USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_asistencia_grupo_docente_paginado (CULM-001 B.2, HU040/HU041; CONTRACT §2.8.4, §3.2.8, F-DOC-004;
-- CULM-001 C.1, CONTRACT §2.6)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001,
-- PAG_001, GRU_*, SEC_002). RBAC DOCENTE titular del grupo. Filas: columnas de uv_resumen_asistencia_estudiante_grupo
-- (indicadores por horas) + nombreCompletoEstudiante + totalRegistros, orden nombreCompletoEstudiante (sabana del docente:
-- el cliente no calcula porcentajes).
-- C.1: al final, la marca de inasistencia de la matricula (uv_marca_inasistencia_estudiante_grupo): alertas vigentes, estado de la
-- revision de cancelacion y las decisiones que el docente puede tomar (accionesPermitidasRevision; vacio si la matricula no esta activa).
-- CIERRE-W3M: @busqueda opcional AL FINAL (el resultset NO cambia): subcadena del nombre o del documento (CHARINDEX, como el padron);
-- NULL o vacio = sin filtro. totalRegistros cuenta con el filtro y el ambito se valida antes de leer filas.
-- ============================================================================
-- SKILLS-BD lote 10 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, sin ISNULL sobre columnas (IIF equivalentes),
-- transiciones y revision por uv_transicion_revision_cancelacion/uv_revision_cancelacion_registro (antes, las tablas) y TRY/CATCH de
-- lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_asistencia_grupo_docente_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idGrupo           UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 50,
    @busqueda          NVARCHAR(100) = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoInscrita       NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @busquedaFiltro NVARCHAR(100) = NULLIF(TRIM(@busqueda), '');
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar correlacion, ejecutor, docente titular del grupo y paginacion
        EXEC dbo.usp_validar_consulta_grupo_docente_titular_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacionDefecto, @idGrupo = @idGrupo,
            @validarPaginacion = 1, @numeroPagina = @numeroPagina, @tamanoPagina = @tamanoPagina,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        -- PASO 2: Rechazo de validacion: se lanza con el detalle tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 3: Pagina del resumen de asistencia de los estudiantes del grupo, con marcas y revision vigente
        SET @offset = (@numeroPagina - 1) * @tamanoPagina;
        SELECT
            idEstudianteGrupo              = r.idEstudianteGrupo,
            idEstudiante                   = r.idEstudiante,
            idGrupo                        = r.idGrupo,
            idAsignatura                   = r.idAsignatura,
            idPeriodoAcademico             = r.idPeriodoAcademico,
            codigoEstadoEstudiante         = r.codigoEstadoEstudiante,
            sesionesEjecutadas             = r.sesionesEjecutadas,
            asistencias                    = r.asistencias,
            faltasSinJustaCausa            = r.faltasSinJustaCausa,
            excusas                        = r.excusas,
            porcentajeInasistencia         = r.porcentajeInasistencia,
            codigoPermanencia              = r.codigoPermanencia,
            tomasDictadas                  = r.tomasDictadas,
            horasDictadas                  = r.horasDictadas,
            horasAsistidas                 = r.horasAsistidas,
            horasFalta                     = r.horasFalta,
            horasExcusa                    = r.horasExcusa,
            horasSinRegistro               = r.horasSinRegistro,
            porcentajeAsistenciaHoras      = r.porcentajeAsistenciaHoras,
            porcentajeExcusaHoras          = r.porcentajeExcusaHoras,
            porcentajeSinRegistroHoras     = r.porcentajeSinRegistroHoras,
            porcentajeInasistenciaSesiones = r.porcentajeInasistenciaSesiones,
            umbralAdvertencia              = r.umbralAdvertencia,
            umbralPerdida                  = r.umbralPerdida,
            sesionesAsistidas              = r.sesionesAsistidas,
            sesionesConFaltaSinJustaCausa  = r.sesionesConFaltaSinJustaCausa,
            sesionesConExcusa              = r.sesionesConExcusa,
            nombreCompletoEstudiante       = eg.nombreCompletoEstudiante,
            totalRegistros                 = COUNT(1) OVER(),
            tieneAdvertenciaVigente        = IIF(m.tieneAdvertenciaVigente IS NULL, CAST(0 AS BIT), m.tieneAdvertenciaVigente),
            fechaAdvertenciaUtc            = m.fechaAdvertenciaUtc,
            tienePerdidaVigente            = IIF(m.tienePerdidaVigente IS NULL, CAST(0 AS BIT), m.tienePerdidaVigente),
            fechaPerdidaUtc                = m.fechaPerdidaUtc,
            idRevisionCancelacion          = m.idRevisionCancelacion,
            codigoEstadoRevision           = m.codigoEstadoRevision,
            nombreEstadoRevision           = m.nombreEstadoRevision,
            requiereAccionDocente          = IIF(m.requiereAccionDocente IS NULL, CAST(0 AS BIT), m.requiereAccionDocente),
            codigoPerfilResolutorActual    = m.codigoPerfilResolutorActual,
            accionesPermitidasRevision     = CASE WHEN m.idRevisionCancelacion IS NOT NULL AND r.codigoEstadoEstudiante = @codigoInscrita THEN ISNULL(acc.acciones, N'') ELSE N'' END -- ISNULL sobre agregacion (permitido): STRING_AGG
        FROM dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = r.idEstudianteGrupo
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = r.idEstudiante
        LEFT JOIN dbo.uv_marca_inasistencia_estudiante_grupo m ON m.idEstudianteGrupo = r.idEstudianteGrupo
        OUTER APPLY (
            SELECT acciones = STRING_AGG(t.codigoDecision, N',') WITHIN GROUP (ORDER BY t.codigoDecision ASC)
            FROM dbo.uv_transicion_revision_cancelacion t
            INNER JOIN dbo.uv_revision_cancelacion_registro rc ON rc.id = m.idRevisionCancelacion AND rc.idEstado = t.idEstadoOrigen
            WHERE t.esDecisionResolutor = 0
        ) acc
        WHERE r.idGrupo = @idGrupoDefecto
          AND (@busquedaFiltro IS NULL
               OR CHARINDEX(@busquedaFiltro, ei.nombreCompleto) > 0
               OR CHARINDEX(@busquedaFiltro, CONVERT(NVARCHAR(20), ei.numeroIdentificacion)) > 0)
        ORDER BY eg.nombreCompletoEstudiante ASC, r.idEstudiante ASC
        OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
    END TRY
    BEGIN CATCH
        -- PASO 4: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
