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
--   DOCENTE        -> programa (DocentePrograma; detalle = facultad; activo = estado del vinculo)
--   COORDINADOR    -> programa que coordina (Programa.coordinador; detalle = facultad)
--   DECANO         -> facultad (Facultad.decano; detalle = institucion)
--   ADMINISTRADOR  -> institucion (Administrador.institucion)
-- Sin vinculos devuelve UNA fila con las columnas del vinculo en NULL. Usuario inexistente => 0 filas.
-- No expone la contrasena ni datos de otros usuarios. Solo lectura.
-- SKILLS-BD lote 3 (2026-11-25): vinculos leidos desde las vistas uv_* (antes, tablas base) y TRY/CATCH; mismo resultset.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_perfil_usuario]
(
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validacion de entrada
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 4: vinculos institucionales del usuario (solo vistas)
        ;WITH vinculos AS (
            SELECT rol = 'ESTUDIANTE', orden = 1, idEntidad = p.id, nombreEntidad = p.nombrePrograma, detalle = p.nombreFacultad, activo = p.estado
            FROM dbo.uv_estudiante_identidad ei
            INNER JOIN dbo.uv_estudiante_programa ep ON ep.idEstudiante = ei.id
            INNER JOIN dbo.uv_programa p ON p.id = ep.idPrograma
            WHERE ei.idUsuario = @idUsuarioDefecto
            UNION ALL
            -- MEJORAS-SERGIO-2026-11-18 (migracion 56): el detalle del vinculo docente es la facultad del programa (antes, el tipo de vinculacion)
            SELECT 'DOCENTE', 2, dp.idPrograma, dp.nombrePrograma, dp.nombreFacultad, dp.estaActivoVinculacion
            FROM dbo.uv_docente_programa dp
            WHERE dp.idUsuario = @idUsuarioDefecto
            UNION ALL
            SELECT 'COORDINADOR', 3, p.id, p.nombrePrograma, p.nombreFacultad, p.estado
            FROM dbo.uv_coordinador_identidad ci
            INNER JOIN dbo.uv_programa p ON p.idCoordinador = ci.id
            WHERE ci.idUsuario = @idUsuarioDefecto
            UNION ALL
            SELECT 'DECANO', 4, f.id, f.nombreFacultad, f.nombreInstitucion, f.estaActivaFacultad
            FROM dbo.uv_decano_identidad di
            INNER JOIN dbo.uv_facultad f ON f.idDecano = di.id
            WHERE di.idUsuario = @idUsuarioDefecto
            UNION ALL
            SELECT 'ADMINISTRADOR', 5, a.idInstitucion, a.nombreInstitucion, NULL, a.estaActivaInstitucion
            FROM dbo.uv_administrador a
            WHERE a.idUsuario = @idUsuarioDefecto
        )
        -- PASO 5: datos personales con una fila por vinculo
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
    END TRY
    BEGIN CATCH
        -- PASO 6: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo del paso 3, se propaga al llamador
        THROW;
    END CATCH
END;
GO
