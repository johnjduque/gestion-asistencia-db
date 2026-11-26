USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: validacion PUBLICA (sin ejecutor) de un token o PIN de matricula. La credencial es el hash del token o el PIN
-- de una ventana ACTIVA y vigente. Devuelve los datos MINIMOS del curso (sin datos de estudiantes).
--   * Exactamente uno de @tokenHash / @pin (si no: MQR_007).
--   * Token o PIN inexistente, cerrado, vencido o rotado fuera de tolerancia: MQR_001, el MISMO error en todos los casos
--     (anti-enumeracion). La ventana vencida se marca EXPIRADA de forma perezosa (persistida antes de responder el error).
-- Los rechazos se propagan con THROW 51000 y mensaje "DBCODE=<codigo>|..." (como usp_consultar_reenvio_verificacion_correo).
-- READ_QUERY_RESULTSET: NON_GOLDEN_PATH_EXTENSION (ver test/test_contract_closure.sql).
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): flujo publico por token, sin ejecutor obligatorio; exige @idCorrelacion.
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): DECLARE del CATCH a la cabecera, PASO n, IF con BEGIN/END y lecturas de ventana, programa, estudiante y
-- vinculo por vistas uv_* (antes, las tablas); el token se sigue resolviendo en el nucleo interno (E7).
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_token_matricula_publico]
(
    @tokenHash     VARBINARY(32) = NULL,
    @pin           NCHAR(6)      = NULL,
    @idCorrelacion UNIQUEIDENTIFIER,
    -- Revision final P3: si se conoce al estudiante (sesion iniciada), programasElegibles es la interseccion entre sus programas y los del
    -- grupo; con un unico programa comun o ninguno la lista es NULL (no hay nada que elegir). Anonimo (NULL): los programas del grupo.
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    DECLARE @idVentana       UNIQUEIDENTIFIER;
    DECLARE @idGrupo         UNIQUEIDENTIFIER;
    DECLARE @idDocenteEmisor UNIQUEIDENTIFIER;
    DECLARE @codigoRechazo   VARCHAR(20);
    DECLARE @mensajeUsuarioInterno   NVARCHAR(4000);  -- SKILLS-BD lote 2: triplete del nucleo interno
    DECLARE @mensajeTecnicoInterno   NVARCHAR(4000);
    DECLARE @estadoInterno           BIT;
    DECLARE @mensajeErrorInterno     NVARCHAR(2048);
    DECLARE @estadoTransaccionCatch  INT;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: transaccion propia o savepoint (la expiracion perezosa puede escribir)
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_hu176b_validar;
            SET @savepointCreado = 1;
        END

        -- PASO 2: resolver el token o PIN en el nucleo (MQR_001 / MQR_007 como codigo de rechazo)
        EXEC dbo.usp_resolver_token_matricula_interno
            @tokenHash = @tokenHash, @pin = @pin, @idCorrelacion = @idCorrelacionDefecto,
            @idVentana = @idVentana OUTPUT, @idGrupo = @idGrupo OUTPUT,
            @idDocenteEmisor = @idDocenteEmisor OUTPUT, @codigoRechazo = @codigoRechazo OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioInterno OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoInterno OUTPUT,
            @estadoResultado = @estadoInterno OUTPUT;
        IF @estadoInterno = 0
        BEGIN
            SET @mensajeErrorInterno = LEFT(@mensajeTecnicoInterno, 2048);
            THROW 52525, @mensajeErrorInterno, 1;
        END

        -- PASO 3: la unica escritura posible es la expiracion perezosa, que debe persistir aun cuando se rechace.
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                COMMIT TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END

        -- PASO 4: mensaje del rechazo
        IF @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        -- PASO 5: reversion respetando ownership; transaccion externa condenada se propaga; si no, SYS_001
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_hu176b_validar;
        END

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- PASO 6: los rechazos se propagan con THROW 51000
    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 7: datos minimos del curso (sin datos de estudiantes)
    SELECT
        idGrupo            = v.grupo,
        nombreAsignatura   = v.nombreAsignatura,
        nombreGrupo        = v.nombreGrupo,
        nombreDocente      = v.nombreDocente,
        fechaExpiracionUtc = v.fechaExpiracionUtc,
        cupoDisponible     = v.cupoDisponible,
        -- DEC-078: programas entre los que elige el estudiante (JSON [{idPrograma, nombre}] por nombre); NULL si la ventana fija
        -- el programa o el grupo tiene uno solo. Solo nombres de programas: ningun dato de estudiantes.
        programasElegibles = CASE
            WHEN t.idProgramaPorDefecto IS NULL AND est.idEstudiante IS NULL AND (SELECT COUNT(*) FROM dbo.ufn_programas_grupo(v.grupo)) > 1
            THEN (SELECT pg.idPrograma, p.nombre
                  FROM dbo.ufn_programas_grupo(v.grupo) pg
                  INNER JOIN dbo.uv_programa_registro p ON p.id = pg.idPrograma
                  ORDER BY p.nombre, p.id
                  FOR JSON PATH)
            WHEN t.idProgramaPorDefecto IS NULL AND est.idEstudiante IS NOT NULL
                 AND (SELECT COUNT(*) FROM dbo.uv_estudiante_programa_registro ep INNER JOIN dbo.ufn_programas_grupo(v.grupo) pg ON pg.idPrograma = ep.idPrograma
                      WHERE ep.idEstudiante = est.idEstudiante) > 1
            THEN (SELECT pg.idPrograma, p.nombre
                  FROM dbo.uv_estudiante_programa_registro ep
                  INNER JOIN dbo.ufn_programas_grupo(v.grupo) pg ON pg.idPrograma = ep.idPrograma
                  INNER JOIN dbo.uv_programa_registro p ON p.id = pg.idPrograma
                  WHERE ep.idEstudiante = est.idEstudiante
                  ORDER BY p.nombre, p.id
                  FOR JSON PATH)
        END
    FROM dbo.uv_token_matricula_grupo v
    INNER JOIN dbo.uv_token_matricula_grupo_registro t ON t.id = v.id
    -- estudiante conocido con al menos un programa (sin programas: se comporta como el anonimo)
    OUTER APPLY (SELECT TOP 1 idEstudiante = e.id FROM dbo.uv_estudiante_identidad e
                 WHERE e.idUsuario = @idUsuarioEjecutor AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa_registro ep WHERE ep.idEstudiante = e.id)) est
    WHERE v.id = @idVentana;
END;
GO
