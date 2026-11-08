-- ============================================================================
-- MIGRACION DOWN 24: CULM-001 D.5 - revierte la carga masiva de usuarios (CONTRACT D §6.3, §14.2)
-- Proteccion D-RB-02: aborta con THROW 50024 si usp_crear_decano contiene DEC_020 (D.9 aplicada).
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

PRINT 'MIGRACION 24 DOWN: revierte carga masiva de usuarios';
GO

-- 1. Proteccion D-RB-02
IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'dbo.usp_crear_decano') AND definition LIKE N'%DEC_020%')
BEGIN
    THROW 50024, 'No es posible revertir la migracion 24: usp_crear_decano contiene modificaciones posteriores (DEC_020).', 1;
END
GO

-- 2. DROP SP de validacion
IF OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_carga_masiva_usuarios];
GO

-- 3. DROP Vista uv_jerarquia_alta_usuario
IF OBJECT_ID(N'dbo.uv_jerarquia_alta_usuario', N'V') IS NOT NULL
    DROP VIEW [dbo].[uv_jerarquia_alta_usuario];
GO

-- 4. DROP Tabla JerarquiaAltaUsuario (y FKs)
IF OBJECT_ID(N'dbo.JerarquiaAltaUsuario', N'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_JerarquiaAltaUsuario_PerfilEjecutor')
        ALTER TABLE dbo.JerarquiaAltaUsuario DROP CONSTRAINT FK_JerarquiaAltaUsuario_PerfilEjecutor;
    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_JerarquiaAltaUsuario_PerfilDestino')
        ALTER TABLE dbo.JerarquiaAltaUsuario DROP CONSTRAINT FK_JerarquiaAltaUsuario_PerfilDestino;
    DROP TABLE dbo.JerarquiaAltaUsuario;
END
GO

-- 5. Eliminar mensajes CMA_*
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo LIKE 'CMA[_]%';
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo LIKE 'CMA[_]%';
GO

-- 6. Eliminar parametros de CARGA_MASIVA e IDENTIDAD/TIPO_IDENTIFICACION_DEFECTO
IF OBJECT_ID(N'dbo.CatalogoParametroEdicion', N'U') IS NOT NULL
BEGIN
    DELETE e 
    FROM dbo.CatalogoParametroEdicion e
    INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
    WHERE p.grupo = 'CARGA_MASIVA';
END
GO

DELETE FROM [dbo].[CatalogoParametro] 
WHERE grupo = 'CARGA_MASIVA' OR (grupo = 'IDENTIDAD' AND clave = 'TIPO_IDENTIFICACION_DEFECTO');
GO

-- 7. Restaurar usp_crear_coordinador (version previa a D.5, sin @idTipoIdIdentificacion)
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_coordinador]
(
    @idCoordinador           UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @idPrograma              UNIQUEIDENTIFIER = NULL,
    @idFacultad              UNIQUEIDENTIFIER,
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idCoordinadorDefecto     UNIQUEIDENTIFIER = @idCoordinador;
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = @idPrograma;
    DECLARE @idFacultadDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idFacultad, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @idUsuarioCreado UNIQUEIDENTIFIER;
    DECLARE @idTipoIdCC      UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    -- Control de ownership transaccional (ver docs/procedimiento-transacciones)
    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de presencia del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de presencia del ejecutor y perfil RBAC
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
                @codigoPerfilRequerido = 'DECANO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validación de parámetros requeridos (número de documento y correo)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_crear_coordinador_parametros_requeridos_interno 
                @numeroIdentificacion = @numeroIdentificacion, 
                @correo = @correo, 
                @primerNombre = @primerNombre, 
                @primerApellido = @primerApellido, 
                @idFacultad = @idFacultadDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validación de existencia y pertenencia de la Facultad
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_facultad_existe_interno 
                @idFacultad = @idFacultadDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3.5: Validación de custodia/ownership del Decano sobre la Facultad (HU120)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_custodia_decano_facultad_interno
                @idUsuarioEjecutor = @idUsuarioEjecutorDefecto,
                @idFacultad = @idFacultadDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validación de unicidad de identidad del usuario
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_coordinador_unicidad_usuario_interno 
                @numeroIdentificacion = @numeroIdentificacion, 
                @correo = @correo, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Validación del Programa (opcional al crear)
        IF @estadoResultado = 1 AND @idProgramaDefecto IS NOT NULL
        BEGIN
            EXEC dbo.usp_validar_programa_existe_interno 
                @idPrograma = @idProgramaDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_validar_programa_pertenece_a_facultad_interno 
                    @idPrograma = @idProgramaDefecto, 
                    @idFacultad = @idFacultadDefecto, 
                    @idCorrelacion = @idCorrelacionDefecto, 
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_validar_programa_no_tiene_coordinador_activo_interno 
                    @idPrograma = @idProgramaDefecto, 
                    @idCorrelacion = @idCorrelacionDefecto, 
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                    @estadoResultado = @estadoResultado OUTPUT;
            END
        END

        -- SECCIÓN OPERACIONAL: Mutaciones transaccionales atómicas
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;

            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_crear_coordinador;
                SET @savepointCreado = 1;
            END

            SELECT TOP 1 @idUsuarioCreado = id
            FROM [dbo].[uv_usuario]
            WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = @numeroIdentificacion;

            IF @idUsuarioCreado IS NULL
            BEGIN
                SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC' ORDER BY id ASC;
                IF @idTipoIdCC IS NULL SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion ORDER BY id ASC;

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

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_sincronizar_coordinador_interno
                    @idCoordinador = @idCoordinadorDefecto OUTPUT,
                    @idUsuario = @idUsuarioCreado,
                    @idFacultad = @idFacultadDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1 AND @idProgramaDefecto IS NOT NULL
            BEGIN
                EXEC dbo.usp_asignar_coordinador_a_programa_interno
                    @idPrograma = @idProgramaDefecto,
                    @idCoordinador = @idCoordinadorDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                IF @transaccionPropia = 1
                BEGIN
                    COMMIT TRANSACTION;
                END
            END
            ELSE
            BEGIN
                IF @savepointCreado = 1 AND @@TRANCOUNT > 0
                BEGIN
                    ROLLBACK TRANSACTION usp_crear_coordinador;
                END
                ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
                BEGIN
                    ROLLBACK TRANSACTION;
                END
            END
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION usp_crear_coordinador;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        SET @estadoResultado = 0;
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Error SQL: ', ERROR_MESSAGE(), ' (Linea: ', ERROR_LINE(), ')');
    END CATCH;

    SELECT 
        @idCorrelacionDefecto AS idCorrelacion,
        @mensajeUsuarioResultado AS mensajeUsuarioResultado,
        @mensajeTecnicoResultado AS mensajeTecnicoResultado,
        @estadoResultado AS estadoResultado,
        CASE WHEN @estadoResultado = 1 THEN @idCoordinadorDefecto ELSE NULL END AS idCoordinador;
END;
GO

-- 8. Restaurar usp_crear_decano (version previa a D.5, sin @idTipoIdIdentificacion)
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_decano]
(
    @idDecano               UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @nombreFacultad          NVARCHAR(150)    = NULL,
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDecanoDefecto          UNIQUEIDENTIFIER = @idDecano;
    DECLARE @idFacultadDefecto        UNIQUEIDENTIFIER = @idFacultad;
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreFacultadDef        NVARCHAR(150)    = TRIM(@nombreFacultad);

    DECLARE @idUsuarioCreado Uniqueidentifier;
    DECLARE @idTipoIdCC      Uniqueidentifier;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    -- Control de ownership transaccional
    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de presencia del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de presencia del ejecutor y perfil RBAC (ADMINISTRADOR)
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

        -- PASO 2: Validación de parámetros requeridos
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_crear_decano_parametros_requeridos_interno 
                @numeroIdentificacion = @numeroIdentificacion, 
                @correo = @correo, 
                @primerNombre = @primerNombre, 
                @primerApellido = @primerApellido, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validación de existencia o nombre de Facultad
        IF @estadoResultado = 1
        BEGIN
            IF @idFacultadDefecto IS NOT NULL
            BEGIN
                EXEC dbo.usp_validar_facultad_existe_interno 
                    @idFacultad = @idFacultadDefecto, 
                    @idCorrelacion = @idCorrelacionDefecto, 
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                BEGIN
                    EXEC dbo.usp_validar_facultad_no_tiene_decano_activo_interno 
                        @idFacultad = @idFacultadDefecto, 
                        @idCorrelacion = @idCorrelacionDefecto, 
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                        @estadoResultado = @estadoResultado OUTPUT;
                END
            END
            ELSE IF @nombreFacultadDef IS NOT NULL AND LEN(@nombreFacultadDef) > 0
            BEGIN
                EXEC dbo.usp_validar_facultad_nombre_disponible_interno
                    @nombreFacultad = @nombreFacultadDef,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
        END

        -- PASO 4: Validación de unicidad de identidad del usuario
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_decano_unicidad_usuario_interno 
                @numeroIdentificacion = @numeroIdentificacion, 
                @correo = @correo, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- SECCIÓN OPERACIONAL: Mutaciones atómicas
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;

            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_crear_decano;
                SET @savepointCreado = 1;
            END

            SELECT TOP 1 @idUsuarioCreado = id
            FROM [dbo].[uv_usuario]
            WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = CAST(@numeroIdentificacion AS VARCHAR(20));

            IF @idUsuarioCreado IS NULL
            BEGIN
                SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC' ORDER BY id ASC;
                IF @idTipoIdCC IS NULL SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion ORDER BY id ASC;

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

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_sincronizar_decano_interno
                    @idDecano = @idDecanoDefecto OUTPUT,
                    @idUsuario = @idUsuarioCreado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                IF @idFacultadDefecto IS NULL AND @nombreFacultadDef IS NOT NULL AND LEN(@nombreFacultadDef) > 0
                BEGIN
                    DECLARE @idInstitucionDecano UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'ID_INSTITUCION_DEFECTO');
                    IF @idInstitucionDecano IS NULL
                    BEGIN
                        SELECT TOP 1 @idInstitucionDecano = institucion FROM dbo.uv_administrador WHERE idUsuario = @idUsuarioEjecutorDefecto;
                    END
                    IF @idInstitucionDecano IS NULL
                    BEGIN
                        SELECT TOP 1 @idInstitucionDecano = id FROM dbo.Institucion;
                    END

                    EXEC dbo.usp_crear_facultad_interna
                        @nombre = @nombreFacultadDef,
                        @idInstitucion = @idInstitucionDecano,
                        @idDecano = @idDecanoDefecto,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @idFacultadCreada = @idFacultadDefecto OUTPUT,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;
                END
                ELSE IF @idFacultadDefecto IS NOT NULL
                BEGIN
                    EXEC dbo.usp_asignar_decano_a_facultad_interno
                        @idFacultad = @idFacultadDefecto,
                        @idDecano = @idDecanoDefecto,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;
                END
            END

            IF @estadoResultado = 1
            BEGIN
                IF @transaccionPropia = 1
                BEGIN
                    COMMIT TRANSACTION;
                END
            END
            ELSE
            BEGIN
                IF @savepointCreado = 1 AND @@TRANCOUNT > 0
                BEGIN
                    ROLLBACK TRANSACTION usp_crear_decano;
                END
                ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
                BEGIN
                    ROLLBACK TRANSACTION;
                END
            END
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION usp_crear_decano;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        SET @estadoResultado = 0;
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Error SQL: ', ERROR_MESSAGE(), ' (Linea: ', ERROR_LINE(), ')');
    END CATCH;

    SELECT 
        @idCorrelacionDefecto AS idCorrelacion,
        @mensajeUsuarioResultado AS mensajeUsuarioResultado,
        @mensajeTecnicoResultado AS mensajeTecnicoResultado,
        @estadoResultado AS estadoResultado,
        CASE WHEN @estadoResultado = 1 THEN @idDecanoDefecto ELSE NULL END AS idDecano;
END;
GO
