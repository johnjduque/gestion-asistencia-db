USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_oferta_creacion_grupo_docente (F3, 2026-11-02)
--
-- Resultset: READ_QUERY_RESULTSET (una fila por asignatura que el docente puede abrir como grupo). NO es un
-- MUTATION_COMMAND_RESULTSET. Las fallas de RBAC se propagan con THROW (mensaje tecnico de catalogo, que lleva el
-- codigo para el clasificador del backend). Solo lectura: sin XACT_ABORT.
-- Que devuelve: el idDocente del ejecutor y las asignaturas activas de los planes activos de los programas con los
-- que el docente tiene vinculo activo. No expone nada fuera de esos programas. El periodo no se elige:
-- usp_crear_grupo toma el mas reciente cuando no se envia.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_oferta_creacion_grupo_docente]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    -- PASO 1: Validar el identificador de correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: Ejecutor obligatorio (GEN_002) y perfil DOCENTE (SEC_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto,
            @codigoPerfilRequerido = 'DOCENTE',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 3: Asignaturas activas con vinculo activo en un programa donde el docente tiene vinculo activo (CULM-001 B2NM:
    -- 1 fila por asignatura; programas = nombres de los programas del docente que la incluyen).
    SELECT
        idDocente          = x.idDocente,
        idAsignatura       = x.idAsignatura,
        codigoAsignatura   = x.codigo,
        nombreAsignatura   = x.nombre,
        programas          = CAST(STRING_AGG(x.nombrePrograma, N', ') WITHIN GROUP (ORDER BY x.nombrePrograma) AS NVARCHAR(1000))
    FROM (
        SELECT DISTINCT dp.idDocente, idAsignatura = a.id, a.codigo, a.nombre, dp.nombrePrograma
        FROM dbo.uv_docente_programa dp
        INNER JOIN dbo.uv_asignatura_plan_estudio v ON v.idPrograma = dp.idPrograma AND v.estaActivoVinculo = 1 AND v.estaActivoPlan = 1
        INNER JOIN dbo.uv_asignatura a ON a.id = v.idAsignatura AND a.estaActivaAsignatura = 1
        WHERE dp.idUsuario = @idUsuarioDefecto
          AND dp.estaActivoDocentePrograma = 1
    ) x
    GROUP BY x.idDocente, x.idAsignatura, x.codigo, x.nombre
    ORDER BY x.nombre, x.codigo;
END;
GO
