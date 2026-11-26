USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_archivo_soporte_autorizado  (LB-004D, R1)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (0..1 fila de datos). NO es un MUTATION_COMMAND_RESULTSET: el
-- resultset de 4 columnas aplica solo a comandos, por eso este SP queda excluido de esa regla en
-- test/test_contract_closure.sql. Los parametros invalidos se propagan con THROW (como
-- usp_consultar_grupos_paginado).
--
-- Autorizacion (se resuelve aqui, ANTES de que el backend pida bytes al storage):
--   PROPIETARIO     usuarioPropietario = ejecutor y estado IN (DRAFT, ATTACHED)
--   DOCENTE_TITULAR estado = ATTACHED y el ejecutor es Docente.usuario del Grupo.docente de la
--                   sesion de la asistencia de la solicitud
-- Cualquier otro caso (inexistente, otro estudiante incluso del mismo grupo, docente no titular,
-- administrador, decano, coordinador, ORPHAN) => 0 filas, sin senal que distinga los casos.
-- CULM-001 D.2 (TD-061, CONTRACT §3.2): un reclamo tiene varios soportes y CADA uno se autoriza por separado con estas mismas reglas;
-- los estados DRAFT/ATTACHED salen de ARCHIVO/ESTADO_BORRADOR y ARCHIVO/ESTADO_ADJUNTO (sin literales quemados).
-- Une tablas base: NO usa SESSION_CONTEXT ni uv_auth_* (que exponen reclamos a companeros/roles
-- administrativos, hallazgo H-03).
-- ============================================================================
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): DECLARE en la cabecera, PASO n, lecturas por vistas uv_* (uv_archivo_soporte_registro,
-- uv_solicitud_revision_asistencia_registro, uv_asistencia_registro, uv_sesion_registro, uv_grupo_registro y uv_docente_identidad;
-- antes, las tablas) y TRY/CATCH de lectura que relanza (antes, sin TRY). El manifiesto LB-004D se regenera en el mismo commit.
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_archivo_soporte_autorizado]
(
    @idArchivoSoporte   UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idArchivoDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idArchivoSoporte, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @estadoBorrador       VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_BORRADOR') AS VARCHAR(10));
    DECLARE @estadoAdjunto        VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio (VAL_001)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END

        -- PASO 3: archivo obligatorio (GEN_002)
        IF @estadoResultado = 1 AND (@idArchivoSoporte IS NULL OR @idArchivoDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idArchivoSoporte',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END

        -- PASO 4: rechazo de validacion: se propaga al llamador
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 5: metadatos del soporte si el ejecutor es su propietario o el docente titular de la sesion
        SELECT
            idArchivoSoporte              = a.id,
            estado                        = a.estado,
            nombreOriginal                = a.nombreOriginal,
            tipoContenido                 = a.tipoContenido,
            tamanioBytes                  = a.tamanioBytes,
            checksumSha256                = a.checksumSha256,
            fechaRegistroUtc              = a.fechaRegistroUtc,
            fechaAdjuncionUtc             = a.fechaAdjuncionUtc,
            idSolicitudRevisionAsistencia = a.idSolicitudRevisionAsistencia,
            relacionAcceso                = CAST(CASE
                                                WHEN a.idUsuarioPropietario = @idUsuarioDefecto
                                                     AND a.estado IN (@estadoBorrador, @estadoAdjunto) THEN 'PROPIETARIO'
                                                ELSE 'DOCENTE_TITULAR'
                                            END AS VARCHAR(20))
        FROM dbo.uv_archivo_soporte_registro a
        WHERE a.id = @idArchivoDefecto
          AND (
                (a.idUsuarioPropietario = @idUsuarioDefecto AND a.estado IN (@estadoBorrador, @estadoAdjunto))
             OR (a.estado = @estadoAdjunto
                 AND EXISTS (
                    SELECT 1
                    FROM dbo.uv_solicitud_revision_asistencia_registro sra
                    INNER JOIN dbo.uv_asistencia_registro asi ON asi.id = sra.idAsistencia
                    INNER JOIN dbo.uv_sesion_registro ses ON ses.id = asi.idSesion
                    INNER JOIN dbo.uv_grupo_registro gru ON gru.id = ses.idGrupo
                    INNER JOIN dbo.uv_docente_identidad doc ON doc.id = gru.idDocente
                    WHERE sra.id = a.idSolicitudRevisionAsistencia
                      AND doc.idUsuario = @idUsuarioDefecto))
              );
    END TRY
    BEGIN CATCH
        -- PASO 6: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
