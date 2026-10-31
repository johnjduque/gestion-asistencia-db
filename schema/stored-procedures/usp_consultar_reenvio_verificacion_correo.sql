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
            FROM dbo.Grupo g
            INNER JOIN dbo.Docente d ON d.id = g.docente
            WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor
        )
        OR EXISTS (
            SELECT 1
            FROM dbo.Grupo g
            INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
            INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
            INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
            INNER JOIN dbo.Programa pr ON pr.id = pe.programa
            INNER JOIN dbo.Coordinador c ON c.id = pr.coordinador
            WHERE g.id = @idGrupo AND c.usuario = @idUsuarioEjecutor
        )
            SET @enAmbito = 1;

        SELECT @idUsuarioEstudiante = e.usuario
        FROM dbo.Estudiante e
        INNER JOIN dbo.EstudianteGrupo eg ON eg.estudiante = e.id AND eg.grupo = @idGrupo
        WHERE e.id = @idEstudiante;

        IF @enAmbito = 0 OR @idUsuarioEstudiante IS NULL
            SET @codigoRechazo = 'VCE_004';
    END

    -- PASO 4: correo aun sin verificar y espera minima
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
    BEGIN
        SELECT @correoConfirmado = u.correoConfirmado FROM dbo.Usuario u WHERE u.id = @idUsuarioEstudiante;

        IF @correoConfirmado = 1
            SET @codigoRechazo = 'VCE_005';
        ELSE
        BEGIN
            SET @esperaMinutos = dbo.ufn_obtener_parametro_int(NULL, 'VERIFICACION_CORREO', 'REENVIO_ESPERA_MINUTOS');
            SELECT @ultimaEmisionUtc = MAX(t.fechaEmisionUtc) FROM dbo.TokenVerificacionCorreo t WHERE t.usuario = @idUsuarioEstudiante;
            IF @ultimaEmisionUtc IS NOT NULL AND @ultimaEmisionUtc > DATEADD(MINUTE, -@esperaMinutos, SYSUTCDATETIME())
                SET @codigoRechazo = 'VCE_003';
        END
    END

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
END;
GO
