USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_crear_decano_con_facultad (CULM-001 / DEC-065 (5); HU116, F-ADM-024)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con la tupla canonica (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado) + idDecano, idFacultad, nombreFacultad (NULL si estadoResultado = 0).
--
-- El administrador registra, en UNA transaccion, a la persona decano y la facultad que titulara. Las validaciones de la facultad y del decano
-- (que no escriben) se resuelven ANTES de abrir la transaccion; el resto de la escritura es todo o nada:
--   * RBAC ADMINISTRADOR (SEC_001), igual que usp_crear_decano y usp_crear_facultad; ejecutor obligatorio (GEN_002);
--   * nombre de la facultad de 3 a 50 caracteres (GEN_002) y unico (GEN_003), como usp_crear_facultad;
--   * institucion existente (GEN_001); si se omite, la primera activa (misma regla de usp_crear_facultad);
--   * la persona no puede ser ya decano activo (DEC_020).
--   Luego, dentro de la transaccion: usp_crear_decano_interno (persona + rol) y usp_crear_facultad_interno (con ese decano). Cualquier error
--   revierte persona, rol y facultad: no queda ninguna persona huerfana.
-- @codigoFacultad se acepta por compatibilidad con el formulario; dbo.Facultad no tiene columna de codigo, de modo que no se persiste.
-- Transaccion propia o SAVE TRANSACTION cuando el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_decano_con_facultad]
(
    @idDecano               UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion   INT,
    @primerNombre           NVARCHAR(50),
    @segundoNombre          NVARCHAR(50),
    @primerApellido         NVARCHAR(50),
    @segundoApellido        NVARCHAR(50),
    @correo                 NVARCHAR(100),
    @password               NVARCHAR(500),
    @nombreFacultad         NVARCHAR(150),
    @codigoFacultad         NVARCHAR(20)     = NULL,
    @idInstitucion          UNIQUEIDENTIFIER,
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor      UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucionDefecto     UNIQUEIDENTIFIER = @idInstitucion;
    DECLARE @idDecanoDefecto          UNIQUEIDENTIFIER = @idDecano;
    DECLARE @idFacultadNueva          UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreFacultadDef        NVARCHAR(150)    = TRIM(@nombreFacultad);
    DECLARE @idUsuarioExistente       UNIQUEIDENTIFIER;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;
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

        -- PASO 2: ejecutor obligatorio y perfil ADMINISTRADOR
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: institucion por defecto (primera activa), igual que usp_crear_facultad
        IF @estadoResultado = 1 AND @idInstitucionDefecto IS NULL
        BEGIN
            SELECT TOP 1 @idInstitucionDefecto = id
            FROM dbo.uv_institucion
            WHERE estaActivaInstitucion = 1
            ORDER BY id ASC;
        END

        -- PASO 4: validaciones de la facultad (mismos codigos que usp_crear_facultad), ANTES de crear la persona
        IF @estadoResultado = 1 AND (@nombreFacultadDef IS NULL OR LEN(@nombreFacultadDef) < 3 OR LEN(@nombreFacultadDef) > 50)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Nombre de Facultad',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Longitud invalida (3-50). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE LOWER(nombreFacultad) = LOWER(@nombreFacultadDef))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003',
                @p_param1 = 'Facultad',
                @p_param2 = 'nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Conflicto de unicidad para nombre: ', @nombreFacultadDef, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@idInstitucionDefecto IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_institucion WHERE id = @idInstitucionDefecto))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Institucion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5 (D.9-a, F-ADM-024): la persona ya es decano activo; se decide antes de abrir la transaccion (no hay escrituras que revertir)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idUsuarioExistente = id
            FROM [dbo].[uv_usuario]
            WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = CAST(@numeroIdentificacion AS VARCHAR(20));

            IF @idUsuarioExistente IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.Decano d WHERE d.usuario = @idUsuarioExistente AND d.estado = 1)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DEC_020',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5.5 (DEC-073): un decano nuevo usa el correo institucional (VCE_008); una persona que ya existe conserva el suyo.
        --          Se decide ANTES de abrir la transaccion: el rechazo no escribe y el SP sigue siendo apto para INSERT ... EXEC (DEC-036).
        IF @estadoResultado = 1
           AND NOT EXISTS (SELECT 1 FROM [dbo].[uv_usuario]
                           WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = CAST(@numeroIdentificacion AS VARCHAR(20)))
        BEGIN
            EXEC dbo.usp_validar_correo_institucional_personal_interno
                @correo = @correo,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 6: transaccion unica (propia o savepoint): persona + rol Decano y despues la facultad con ese decano
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION svp_crear_decano_facultad;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_crear_decano_interno
                @idDecano = @idDecanoDefecto OUTPUT,
                @numeroIdentificacion = @numeroIdentificacion,
                @primerNombre = @primerNombre,
                @segundoNombre = @segundoNombre,
                @primerApellido = @primerApellido,
                @segundoApellido = @segundoApellido,
                @correo = @correo,
                @password = @password,
                @idFacultad = NULL,
                @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_crear_facultad_interno
                    @id = @idFacultadNueva,
                    @nombre = @nombreFacultadDef,
                    @idInstitucion = @idInstitucionDefecto,
                    @idDecano = @idDecanoDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'Decano y facultad',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' IdDecano: ', @idDecanoDefecto, ' IdFacultad: ', @idFacultadNueva, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- Cierre respetando el ownership: un fallo tras abrir la transaccion revierte persona, rol y facultad
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    IF @estadoResultado = 1
                        COMMIT TRANSACTION;
                    ELSE
                        ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
            ELSE IF @savepointCreado = 1 AND XACT_STATE() = 1 AND @estadoResultado = 0
                ROLLBACK TRANSACTION svp_crear_decano_facultad;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION svp_crear_decano_facultad;

        -- Transaccion externa condenada que no nos pertenece: se propaga al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idDecano                = IIF(@estadoResultado = 1, @idDecanoDefecto, NULL),
        idFacultad              = IIF(@estadoResultado = 1, @idFacultadNueva, NULL),
        nombreFacultad          = IIF(@estadoResultado = 1, @nombreFacultadDef, NULL);
END;
GO
