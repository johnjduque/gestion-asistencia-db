USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_crear_decano_interno]
-- CULM-001 / DEC-065 (5): nucleo de creacion de persona + rol Decano, extraido de usp_crear_decano para componerlo con la facultad
-- (usp_crear_decano_con_facultad). SIN control transaccional propio: DEBE invocarse dentro de la transaccion (o savepoint) del llamador.
-- No valida correlacion, RBAC ni ambito (lo hace el llamador). Ejecuta, en orden:
--   1. DEC_020 si la persona ya es decano activo (no escribe nada).
--   2. Reutiliza el usuario existente (correo o identificacion) o lo crea con usp_sincronizar_usuario_interno.
--   3. Crea la fila Decano si la persona no la tenia y, si recibe @idFacultad, la deja como titular de esa facultad.
-- @idDecano es de entrada/salida: NULL genera el identificador; al terminar con exito contiene el id del decano.
-- =============================================================================
-- SKILLS-BD lote 4 (2026-11-25): DECLARE en la cabecera, lecturas por uv_decano_rol y uv_tipo_identificacion, IF con
-- BEGIN/END y TRY/CATCH (SYS_001; con transaccion abierta relanza); mismo comportamiento.
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_decano_interno]
(
    @idDecano                UNIQUEIDENTIFIER OUTPUT,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @password                NVARCHAR(500),
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioCreado      UNIQUEIDENTIFIER;
    DECLARE @idTipoIdCC           UNIQUEIDENTIFIER;
    DECLARE @codTipoDocDefectoDec NVARCHAR(50) = dbo.ufn_obtener_parametro_texto(NULL, 'IDENTIDAD', 'TIPO_IDENTIFICACION_DEFECTO');
BEGIN
    SET NOCOUNT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        -- PASO 1 (D.9-a, F-ADM-024): la persona ya es decano activo
        SELECT TOP 1 @idUsuarioCreado = id
        FROM [dbo].[uv_usuario]
        WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = CAST(@numeroIdentificacion AS VARCHAR(20));

        IF @idUsuarioCreado IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.uv_decano_rol d WHERE d.idUsuario = @idUsuarioCreado AND d.estaActivoRolDecano = 1)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'DEC_020',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: gestion reactiva de usuario (consulta en uv_usuario y delegacion a usp_sincronizar_usuario_interno)
        IF @estadoResultado = 1 AND @idUsuarioCreado IS NULL
        BEGIN
            IF @idTipoIdIdentificacion IS NOT NULL
            BEGIN
                SET @idTipoIdCC = @idTipoIdIdentificacion;
            END
            ELSE
            BEGIN
                SELECT TOP 1 @idTipoIdCC = id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = @codTipoDocDefectoDec ORDER BY id ASC;
                IF @idTipoIdCC IS NULL
                BEGIN
                    SELECT TOP 1 @idTipoIdCC = id FROM dbo.uv_tipo_identificacion ORDER BY id ASC;
                END
            END

            EXEC dbo.usp_sincronizar_usuario_interno
                @idTipoIdIdentificacion = @idTipoIdCC,
                @numeroIdentificacion = @numeroIdentificacion,
                @primerApellido = @primerApellido,
                @segundoApellido = @segundoApellido,
                @primerNombre = @primerNombre,
                @segundoNombre = @segundoNombre,
                @correo = @correo,
                @password = @password,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                SELECT TOP 1 @idUsuarioCreado = id
                FROM [dbo].[uv_usuario]
                WHERE correo = LOWER(TRIM(@correo));
            END
        END

        -- PASO 3: asignacion reactiva del rol Decano y adscripcion a la facultad
        IF @estadoResultado = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.uv_decano_rol WHERE idUsuario = @idUsuarioCreado)
            BEGIN
                IF @idDecano IS NULL
                BEGIN
                    SET @idDecano = NEWID();
                END

                INSERT INTO dbo.Decano (id, usuario)
                VALUES (@idDecano, @idUsuarioCreado);
            END
            ELSE
            BEGIN
                SELECT TOP 1 @idDecano = id FROM dbo.uv_decano_rol WHERE idUsuario = @idUsuarioCreado;
            END

            IF @idFacultad IS NOT NULL
            BEGIN
                UPDATE dbo.Facultad
                SET decano = @idDecano
                WHERE id = @idFacultad;
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Decano',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        -- PASO 4: error (SYS_001). Sin transaccion propia: con una transaccion abierta se relanza el error original para que
        -- su duenio la revierta (antes del lote 4 el error salia sin capturar)
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        IF XACT_STATE() <> 0
        BEGIN
            THROW;
        END
    END CATCH
END;
GO
