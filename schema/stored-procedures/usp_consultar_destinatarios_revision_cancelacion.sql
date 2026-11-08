USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_revision_cancelacion (CULM-001 C.1; CONTRACT §2.5.9, O-2)
--
-- READ_QUERY_RESULTSET sin paginacion. Destinatarios de los avisos de una revision: ESTUDIANTE, DOCENTE (titular) y RESOLUTOR
-- (ufn_revision_cancelacion_resolutores, nunca el proponente), con el contexto del caso. El ejecutor debe ser el docente titular,
-- un resolutor (actual) o quien resolvio; si no, THROW 51000 con RCN_001. El correo es de uso interno del NotificacionPort;
-- el backend no lo expone por HTTP ni lo escribe en logs (mismas reglas que usp_consultar_destinatarios_sesion_cancelada).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_revision_cancelacion]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idRevision        UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idRevisionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idRevision, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @idEstudianteGrupo UNIQUEIDENTIFIER, @usuarioProponente UNIQUEIDENTIFIER, @autorizado BIT = 0;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idRevision IS NULL)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idRevision',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
    BEGIN
        SELECT @idEstudianteGrupo = rv.idEstudianteGrupo, @usuarioProponente = rv.idUsuarioDecisionDocente,
               @autorizado = CAST(IIF(rv.idUsuarioDocenteTitular = @idUsuarioDefecto OR rv.idUsuarioResolucion = @idUsuarioDefecto, 1, 0) AS BIT)
        FROM dbo.uv_revision_cancelacion rv WHERE rv.id = @idRevisionDefecto;
        IF @idEstudianteGrupo IS NOT NULL AND @autorizado = 0
           AND EXISTS (SELECT 1 FROM dbo.ufn_revision_cancelacion_resolutores(@idEstudianteGrupo, @usuarioProponente) f WHERE f.idUsuario = @idUsuarioDefecto)
            SET @autorizado = 1;
        IF @idEstudianteGrupo IS NULL OR @autorizado = 0
        BEGIN
            SELECT @p1 = CONVERT(NVARCHAR(36), @idRevisionDefecto), @p2 = CONVERT(NVARCHAR(36), @idUsuarioDefecto);
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'RCN_001', @p_param1 = @p1, @p_param2 = @p2,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END
    END
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT d.rolDestinatario, d.codigoPerfil, d.idUsuario, d.nombreCompleto, d.correo, d.idPrograma, d.esEscalamiento,
           idGrupo = rv.idGrupo, codigoGrupo = rv.codigoGrupo, nombreGrupo = rv.nombreGrupo, nombreAsignatura = rv.nombreAsignatura,
           nombreCompletoEstudiante = rv.nombreCompletoEstudiante, nombreCompletoDocente = rv.nombreCompletoDocente, codigoEstado = rv.codigoEstado,
           porcentajeActual = rs.porcentajeInasistencia, umbralPerdida = rs.umbralPerdida,
           motivoDocente = rv.motivoDocente, motivoResolucion = rv.motivoResolucion, nombreCompletoResolucion = rv.nombreCompletoResolucion
    FROM dbo.uv_revision_cancelacion rv
    LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo rs ON rs.idEstudianteGrupo = rv.idEstudianteGrupo
    CROSS APPLY (
        SELECT rolDestinatario = CAST(N'ESTUDIANTE' AS NVARCHAR(20)), codigoPerfil = CAST(N'ESTUDIANTE' AS NVARCHAR(20)), idUsuario = u.id,
               nombreCompleto = CAST(rv.nombreCompletoEstudiante AS NVARCHAR(400)), correo = u.correo, idPrograma = CAST(NULL AS UNIQUEIDENTIFIER), esEscalamiento = CAST(0 AS BIT)
        FROM dbo.Usuario u WHERE u.id = rv.idUsuarioEstudiante
        UNION ALL
        SELECT N'DOCENTE', N'DOCENTE', u.id, CAST(rv.nombreCompletoDocente AS NVARCHAR(400)), u.correo, CAST(NULL AS UNIQUEIDENTIFIER), CAST(0 AS BIT)
        FROM dbo.Usuario u WHERE u.id = rv.idUsuarioDocenteTitular
        UNION ALL
        SELECT N'RESOLUTOR', f.codigoPerfil, u.id,
               CAST(CONCAT(LTRIM(RTRIM(CONCAT(u.primerNombre, N' ', u.segundoNombre))), N' ', LTRIM(RTRIM(CONCAT(u.primerApellido, N' ', u.segundoApellido)))) AS NVARCHAR(400)),
               u.correo, f.idPrograma, f.esEscalamiento
        FROM dbo.ufn_revision_cancelacion_resolutores(rv.idEstudianteGrupo, rv.idUsuarioDecisionDocente) f
        INNER JOIN dbo.Usuario u ON u.id = f.idUsuario
    ) d
    WHERE rv.id = @idRevisionDefecto
    ORDER BY d.rolDestinatario, d.nombreCompleto, d.idUsuario;
END;
GO
