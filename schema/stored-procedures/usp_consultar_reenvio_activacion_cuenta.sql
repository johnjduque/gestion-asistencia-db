USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- ============================================================================
-- IDENT-002: elegibilidad del reenvio del enlace de activacion de una cuenta registrada por otra persona (decano,
-- coordinador, docente o estudiante). Valida RBAC (ADMINISTRADOR, DECANO o COORDINADOR), que el usuario destino exista,
-- que su correo no este verificado (ACT_002: la cuenta ya esta activa) y la espera minima desde la ultima emision
-- (VCE_003, parametro VERIFICACION_CORREO/REENVIO_ESPERA_MINUTOS). AUD-BD A-1: el alcance jerarquico (decano: su facultad;
-- coordinador: su programa; administrador: toda la institucion) se fuerza DENTRO del SP (SEC_002, antes de revelar si el
-- destino existe o esta activo), con las mismas reglas que InstitutionalScopePort.canGestionarCuenta de la aplicacion. Devuelve una fila con el usuario destino; el backend registra entonces el aviso.
-- Los rechazos se propagan con THROW 51000 y mensaje "DBCODE=<codigo>|..." (como usp_consultar_reenvio_verificacion_correo).
-- READ_QUERY_RESULTSET: NON_GOLDEN_PATH_EXTENSION (ver test/test_contract_closure.sql).
-- SKILLS-BD lote 3 (2026-11-25): lecturas desde uv_usuario_autenticacion y uv_token_verificacion_correo (antes, tablas base),
-- IF con BEGIN/END y TRY/CATCH (el rechazo sigue saliendo con THROW 51000); mismo comportamiento.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_reenvio_activacion_cuenta]
(
    @idUsuario         UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @correoConfirmado BIT;
    DECLARE @ultimaEmisionUtc DATETIME2(0);
    DECLARE @esperaMinutos    INT;
    DECLARE @codigoRechazo    VARCHAR(20) = NULL;
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: correlacion y parametros obligatorios
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuario IS NULL)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idUsuario',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC del ejecutor (quien puede registrar cuentas de otras personas)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutor,
                @codigoPerfilRequerido = 'ADMINISTRADOR,DECANO,COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2B (AUD-BD A-1): alcance jerarquico del ejecutor sobre el usuario destino. El administrador gestiona cualquier cuenta; el
        --          decano las de coordinadores, docentes y estudiantes de su facultad; el coordinador las de docentes y estudiantes de su
        --          programa. Fuera del ambito el rechazo es SEC_002, igual para un destino inexistente (no revela existencia).
        IF @estadoResultado = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_administrador a WHERE a.idUsuario = @idUsuarioEjecutor AND a.estaActivoUsuario = 1)
           AND NOT EXISTS (
                SELECT 1 FROM dbo.uv_decano d
                WHERE d.idUsuario = @idUsuarioEjecutor AND d.estaActivoDecano = 1 AND (
                    EXISTS (SELECT 1 FROM dbo.uv_coordinador c WHERE c.idUsuario = @idUsuario AND c.idFacultad = d.idFacultad)
                    OR EXISTS (SELECT 1 FROM dbo.uv_docente_programa dp WHERE dp.idUsuario = @idUsuario AND dp.idFacultad = d.idFacultad)
                    OR EXISTS (
                        SELECT 1 FROM dbo.uv_estudiante_programa ep
                        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = ep.idEstudiante
                        INNER JOIN dbo.uv_programa p ON p.id = ep.idPrograma
                        WHERE ei.idUsuario = @idUsuario AND p.idFacultad = d.idFacultad)))
           AND NOT EXISTS (
                SELECT 1 FROM dbo.uv_coordinador cc
                WHERE cc.idUsuario = @idUsuarioEjecutor AND cc.estaActivoCoordinador = 1 AND (
                    EXISTS (SELECT 1 FROM dbo.uv_docente_programa dp WHERE dp.idUsuario = @idUsuario AND dp.idPrograma = cc.idPrograma)
                    OR EXISTS (
                        SELECT 1 FROM dbo.uv_estudiante_programa ep
                        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = ep.idEstudiante
                        WHERE ei.idUsuario = @idUsuario AND ep.idPrograma = cc.idPrograma)))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: usuario destino existente y activo (VCE_007)
        IF @estadoResultado = 1
        BEGIN
            SELECT @correoConfirmado = u.correoConfirmado FROM dbo.uv_usuario_autenticacion u WHERE u.idUsuario = @idUsuario AND u.estaActivoUsuario = 1;
            IF @correoConfirmado IS NULL
            BEGIN
                SET @codigoRechazo = 'VCE_007';
            END
        END

        -- PASO 4: cuenta aun sin activar (ACT_002) y espera minima entre envios (VCE_003)
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            IF @correoConfirmado = 1
            BEGIN
                SET @codigoRechazo = 'ACT_002';
            END
            ELSE
            BEGIN
                SET @esperaMinutos = dbo.ufn_obtener_parametro_int(NULL, 'VERIFICACION_CORREO', 'REENVIO_ESPERA_MINUTOS');
                SELECT @ultimaEmisionUtc = MAX(t.fechaEmisionUtc) FROM dbo.uv_token_verificacion_correo t WHERE t.idUsuario = @idUsuario;
                IF @ultimaEmisionUtc IS NOT NULL AND @ultimaEmisionUtc > DATEADD(MINUTE, -@esperaMinutos, SYSUTCDATETIME())
                BEGIN
                    SET @codigoRechazo = 'VCE_003';
                END
            END
        END

        -- PASO 5: traducir el rechazo a su mensaje de catalogo
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: rechazo => THROW 51000; exito => una fila con el usuario destino
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        SELECT @idUsuario AS idUsuario;
    END TRY
    BEGIN CATCH
        -- PASO 7: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo del paso 6, se propaga al llamador
        THROW;
    END CATCH
END;
GO
