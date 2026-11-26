USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- IDENT-001: elegibilidad del reenvio del enlace de verificacion. Valida RBAC (DOCENTE o COORDINADOR), ambito
-- (docente titular del grupo o coordinador del programa del grupo), que el estudiante pertenezca al grupo, que su correo
-- no este verificado (VCE_005) y la espera minima desde la ultima emision (VCE_003, parametro REENVIO_ESPERA_MINUTOS).
-- Devuelve una fila con el usuario del estudiante; el backend registra entonces el aviso. Los rechazos se propagan con
-- THROW 51000 y mensaje "DBCODE=<codigo>|..." (como usp_consultar_detalle_solicitud_revision_docente).
-- READ_QUERY_RESULTSET: NON_GOLDEN_PATH_EXTENSION (ver test/test_contract_closure.sql).
-- SKILLS-BD lote 8 (2026-11-26): ambito, estudiante, usuario y tokens por uv_grupo, uv_docente_identidad, uv_grupo_programa, uv_programa, uv_coordinador_identidad, uv_estudiante_programa, uv_estudiante_identidad, uv_estudiante_grupo, uv_usuario y uv_token_verificacion_correo (antes, las tablas); IF con BEGIN/END y TRY/CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_reenvio_verificacion_correo]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idEstudiante      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @enAmbito           BIT = 0;
    DECLARE @idUsuarioEstudiante UNIQUEIDENTIFIER;
    DECLARE @correoConfirmado    BIT;
    DECLARE @ultimaEmisionUtc    DATETIME2(0);
    DECLARE @esperaMinutos       INT;
    DECLARE @codigoRechazo       VARCHAR(20) = NULL;
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorios
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idGrupo IS NULL OR @idEstudiante IS NULL)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idGrupo/idEstudiante',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC del ejecutor
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutor,
                @codigoPerfilRequerido = 'DOCENTE,COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: ambito jerarquico (titular del grupo o coordinador del programa del grupo) y pertenencia del estudiante
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM dbo.uv_grupo g
                INNER JOIN dbo.uv_docente_identidad d ON d.id = g.idDocente
                WHERE g.id = @idGrupo AND d.idUsuario = @idUsuarioEjecutor
            )
            OR EXISTS (
                SELECT 1
                FROM dbo.uv_grupo g
                INNER JOIN dbo.uv_grupo_programa gpx ON gpx.idGrupo = g.id   -- CULM-001 B2NM: vigencia S1
                INNER JOIN dbo.uv_programa pr ON pr.id = gpx.idPrograma
                INNER JOIN dbo.uv_coordinador_identidad c ON c.id = pr.idCoordinador
                WHERE g.id = @idGrupo AND c.idUsuario = @idUsuarioEjecutor
                  AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa epx WHERE epx.idEstudiante = @idEstudiante AND epx.idPrograma = pr.id)
            )
            BEGIN
                SET @enAmbito = 1;
            END

            SELECT @idUsuarioEstudiante = e.idUsuario
            FROM dbo.uv_estudiante_identidad e
            INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idEstudiante = e.id AND eg.idGrupo = @idGrupo
            WHERE e.id = @idEstudiante;

            IF @enAmbito = 0 OR @idUsuarioEstudiante IS NULL
            BEGIN
                SET @codigoRechazo = 'VCE_004';
            END
        END

        -- PASO 4: correo aun sin verificar y espera minima
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            SELECT @correoConfirmado = u.correoConfirmado FROM dbo.uv_usuario u WHERE u.id = @idUsuarioEstudiante;

            IF @correoConfirmado = 1
            BEGIN
                SET @codigoRechazo = 'VCE_005';
            END
            ELSE
            BEGIN
                SET @esperaMinutos = dbo.ufn_obtener_parametro_int(NULL, 'VERIFICACION_CORREO', 'REENVIO_ESPERA_MINUTOS');
                SELECT @ultimaEmisionUtc = MAX(t.fechaEmisionUtc) FROM dbo.uv_token_verificacion_correo t WHERE t.idUsuario = @idUsuarioEstudiante;
                IF @ultimaEmisionUtc IS NOT NULL AND @ultimaEmisionUtc > DATEADD(MINUTE, -@esperaMinutos, SYSUTCDATETIME())
                BEGIN
                    SET @codigoRechazo = 'VCE_003';
                END
            END
        END

        -- PASO 5: rechazo por codigo y THROW 51000 (DBCODE); si pasa, una fila con el usuario del estudiante
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        SELECT @idUsuarioEstudiante AS idUsuario;
    END TRY
    BEGIN CATCH
        -- PASO 6: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
