USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- CULM-001 B2NM (DEC-019, R3): asignaturas activas de la institucion del plan sin vinculo activo en el. 1 fila por asignatura,
-- con planes = "Programa · Plan inp · S n" de sus vinculos activos. Plan inexistente -> PLA_002; plan ajeno -> SEC_002.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asignaturas_asociables_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idPlanEstudio     UNIQUEIDENTIFIER,
    @numeroPagina      INT,
    @tamanoPagina      INT,
    @busqueda          NVARCHAR(100) = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoRechazo NVARCHAR(10);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        SET @codigoRechazo = 'VAL_001';

    DECLARE @idPrograma UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER;
    IF @codigoRechazo IS NULL AND @estadoResultado = 1
    BEGIN
        SELECT @idPrograma = pe.programa, @idInstitucion = f.institucion
        FROM dbo.PlanEstudio pe
        INNER JOIN dbo.Programa p ON p.id = pe.programa
        INNER JOIN dbo.Facultad f ON f.id = p.facultad
        WHERE pe.id = @idPlanEstudio;
        IF @idPrograma IS NULL
            SET @codigoRechazo = 'PLA_002';
        ELSE IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutor) cp WHERE cp.idPrograma = @idPrograma)
            SET @codigoRechazo = 'SEC_002';
    END

    IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
    BEGIN
        IF @codigoRechazo IS NOT NULL
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = N'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    DECLARE @patron NVARCHAR(220) = IIF(NULLIF(TRIM(@busqueda), N'') IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(UPPER(TRIM(@busqueda)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));

    SELECT
        idAsignatura     = a.id,
        codigo           = a.codigo,
        nombre           = a.nombre,
        credito          = a.credito,
        nombreArea       = a.nombreArea,
        nombreComponente = a.nombreComponente,
        planes           = CAST((SELECT STRING_AGG(CONCAT(v.nombrePrograma, N' · Plan ', v.inpPlanEstudio, N' · S', v.numeroSemestre), N'; ')
                                 WITHIN GROUP (ORDER BY v.nombrePrograma, v.inpPlanEstudio)
                                 FROM dbo.uv_asignatura_plan_estudio v
                                 WHERE v.idAsignatura = a.id AND v.estaActivoVinculo = 1) AS NVARCHAR(1000)),
        totalRegistros   = COUNT(*) OVER()
    FROM dbo.uv_asignatura a
    WHERE a.estaActivaAsignatura = 1
      AND EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v WHERE v.idAsignatura = a.id AND v.estaActivoVinculo = 1 AND v.idInstitucion = @idInstitucion)
      AND NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v WHERE v.idAsignatura = a.id AND v.estaActivoVinculo = 1 AND v.idPlanEstudio = @idPlanEstudio)
      AND (@patron IS NULL OR UPPER(a.nombre) LIKE @patron ESCAPE N'\' OR UPPER(a.codigo) LIKE @patron ESCAPE N'\')
    ORDER BY a.nombre ASC, a.codigo ASC, a.id ASC
    OFFSET @offset ROWS FETCH NEXT @tamano ROWS ONLY;
END;
GO
