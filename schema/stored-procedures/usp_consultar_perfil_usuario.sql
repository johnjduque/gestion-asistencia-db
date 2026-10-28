USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_perfil_usuario (HU006)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Perfil del USUARIO EJECUTOR (solo el propio; no recibe otro id): datos personales de dbo.Usuario y una fila por
-- cada vinculo institucional:
--   ESTUDIANTE     -> programa (EstudiantePrograma; detalle = facultad)
--   DOCENTE        -> programa (DocentePrograma; detalle = tipo de vinculacion; activo = estado del vinculo)
--   COORDINADOR    -> programa que coordina (Programa.coordinador; detalle = facultad)
--   DECANO         -> facultad (Facultad.decano; detalle = institucion)
--   ADMINISTRADOR  -> institucion (Administrador.institucion)
-- Sin vinculos devuelve UNA fila con las columnas del vinculo en NULL. Usuario inexistente => 0 filas.
-- No expone la contrasena ni datos de otros usuarios. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_perfil_usuario]
(
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    ;WITH vinculos AS (
        SELECT rol = 'ESTUDIANTE', orden = 1, idEntidad = p.id, nombreEntidad = p.nombre, detalle = f.nombre, activo = p.estado
        FROM dbo.Estudiante e
        INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = e.id
        INNER JOIN dbo.Programa p ON p.id = ep.programa
        INNER JOIN dbo.Facultad f ON f.id = p.facultad
        WHERE e.usuario = @idUsuarioDefecto
        UNION ALL
        SELECT 'DOCENTE', 2, p.id, p.nombre, tv.nombre, dp.estado
        FROM dbo.Docente d
        INNER JOIN dbo.DocentePrograma dp ON dp.docente = d.id
        INNER JOIN dbo.Programa p ON p.id = dp.programa
        INNER JOIN dbo.TipoVinculacion tv ON tv.id = dp.tipoVinculacion
        WHERE d.usuario = @idUsuarioDefecto
        UNION ALL
        SELECT 'COORDINADOR', 3, p.id, p.nombre, f.nombre, p.estado
        FROM dbo.Coordinador c
        INNER JOIN dbo.Programa p ON p.coordinador = c.id
        INNER JOIN dbo.Facultad f ON f.id = p.facultad
        WHERE c.usuario = @idUsuarioDefecto
        UNION ALL
        SELECT 'DECANO', 4, f.id, f.nombre, i.nombre, f.estado
        FROM dbo.Decano dc
        INNER JOIN dbo.Facultad f ON f.decano = dc.id
        INNER JOIN dbo.Institucion i ON i.id = f.institucion
        WHERE dc.usuario = @idUsuarioDefecto
        UNION ALL
        SELECT 'ADMINISTRADOR', 5, i.id, i.nombre, NULL, i.estado
        FROM dbo.Administrador a
        INNER JOIN dbo.Institucion i ON i.id = a.institucion
        WHERE a.usuario = @idUsuarioDefecto
    )
    SELECT
        idUsuario                = u.id,
        codigoTipoIdentificacion = u.TipoIdentificacion,
        nombreTipoIdentificacion = u.nombreTipoIdentificacion,
        numeroIdentificacion     = u.numeroIdentificacion,
        primerNombre             = u.primerNombre,
        segundoNombre            = u.segundoNombre,
        primerApellido           = u.primerApellido,
        segundoApellido          = u.segundoApellido,
        nombreCompleto           = CAST(CONCAT_WS(N' ',
                                       NULLIF(TRIM(u.primerNombre), N''),
                                       NULLIF(TRIM(u.segundoNombre), N''),
                                       NULLIF(TRIM(u.primerApellido), N''),
                                       NULLIF(TRIM(u.segundoApellido), N'')) AS NVARCHAR(400)),
        correo                   = u.correo,
        correoConfirmado         = u.correoConfirmado,
        estaActivoUsuario        = u.estaActivoUsuario,
        rolVinculo               = CAST(v.rol AS VARCHAR(20)),
        idEntidadVinculo         = v.idEntidad,
        nombreEntidadVinculo     = v.nombreEntidad,
        detalleVinculo           = v.detalle,
        estaActivoVinculo        = v.activo
    FROM dbo.uv_usuario u
    LEFT JOIN vinculos v ON 1 = 1
    WHERE u.id = @idUsuarioDefecto
    ORDER BY v.orden ASC, v.nombreEntidad ASC, v.idEntidad ASC;
END;
GO
