-- ============================================================================
-- MIGRACION DOWN 66: restaura dbo.Usuario.password (SEG-11)
--   1. Se agrega la columna NOT NULL con DEFAULT N'' (DF_Usuario_password): las filas existentes quedan validas y las altas que no
--      la informen siguen funcionando. Las claves/hashes que tenia antes del up NO se recuperan (el up los borra).
--   2. El texto de develop (antes de la 66) de uv_usuario, uv_administrador, uv_usuario_autenticacion, usp_sincronizar_usuario_interno,
--      usp_admitir_estudiante, usp_internal_matricular_por_token y usp_vincular_docente_programa.
-- Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 66 DOWN: restaura dbo.Usuario.password';
GO
-- ---- schema/tables/Usuario.sql (columna password)
IF COL_LENGTH(N'dbo.Usuario', N'password') IS NULL
    ALTER TABLE [dbo].[Usuario] ADD [password] nvarchar(500) NOT NULL CONSTRAINT [DF_Usuario_password] DEFAULT N'';
GO
-- ---- schema/views/uv_usuario.sql (texto de develop antes de la 66)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_usuario]
AS
SELECT		u.id,
			idTipoIdentificacion = ti.id,
			TipoIdentificacion = ti.tipoIdentificacion,
			nombreTipoIdentificacion = ti.nombre,
			numeroIdentificacion,
			primerApellido,
			segundoApellido,
			primerNombre,
			segundoNombre,
			nombreCompleto = CONCAT(LTRIM(RTRIM(CONCAT(primerNombre, ' ', segundoNombre))), ' ', LTRIM(RTRIM(CONCAT(primerApellido, ' ', segundoApellido)))),
			correo,
			correoConfirmado,
			correoConfirmadoTexto = IIF(correoConfirmado = 1, 'SI', 'NO'),
			estaActivoUsuario = estado,
			estaActivoTextoUsuario = IIF(estado = 1, 'SI', 'NO'),
			password = '*****'

FROM		Usuario u
INNER JOIN	uv_tipo_identificacion ti
ON			u.tipoIdIdentificacion = ti.id
GO
GO
-- ---- schema/views/uv_administrador.sql (texto de develop antes de la 66)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_administrador]
AS
SELECT		a.id,
			idUsuario = u.id,
			idTipoIdentificacionUsuario = u.idTipoIdentificacion,
			TipoIdentificacionUsuario = u.TipoIdentificacion,
			nombreTipoIdentificacionUsuario = u.nombreTipoIdentificacion,
			numeroIdentificacionUsuario = u.numeroIdentificacion,
			primerApellidoUsuario = u.primerApellido,
			segundoApellidoUsuario = u.segundoApellido,
			primerNombreUsuario = u.primerNombre,
			segundoNombreUsuario = u.segundoNombre,
			nombreCompletoUsuario = u.nombreCompleto,
			correoUsuario = u.correo,
			correoConfirmadoUsuario = u.correoConfirmado,
			correoConfirmadoTextoUsuario = u.correoConfirmadoTexto,
			estaActivoUsuario = u.estaActivoUsuario,
			estaActivoTextoUsuario = u.estaActivoTextoUsuario,
			passwordUsuario = u.password,

			idInstitucion = i.id,
			nombreInstitucion = i.nombre,
			estaActivaInstitucion = i.estaActivaInstitucion,
			estaActivoTextoInstitucion = i.estaActivaTextoInstitucion,

			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			nivelAccesoPerfil = p.nivel_acceso,
			estaActivoAdministrador = IIF(u.estaActivoUsuario = 0 OR i.estaActivaInstitucion = 0, 0, 1),
			estaActivoTextoAdministrador = IIF(u.estaActivoUsuario = 0 OR i.estaActivaInstitucion = 0, 'NO', 'SI'),
			justificacionEstado =	CASE
										WHEN u.estaActivoUsuario = 0 THEN CONCAT('Perfil ', p.nombre, ' inactivo porque usuario est? inactivo.')
										WHEN i.estaActivaInstitucion = 0 THEN CONCAT('Perfil ', p.nombre, ' inactivo porque instituci?n est? inactivd.')
										ELSE CONCAT('Perfil ', p.nombre, ' activo.')
									END
FROM		Administrador a
INNER JOIN	uv_usuario u
ON			a.usuario = u.id
INNER JOIN	uv_institucion i
ON			a.institucion = i.id,
			(SELECT TOP 1 id, codigo, nombre, nivel_acceso FROM uv_perfil WHERE codigo = 'AD') p
GO
GO
-- ---- schema/views/uv_usuario_autenticacion.sql (texto de develop antes de la 66)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_usuario_autenticacion]
AS
SELECT		idUsuario = u.id,
			correo = u.correo,
			password = u.password,
			correoConfirmado = u.correoConfirmado,
			estaActivoUsuario = u.estado

FROM		Usuario u
GO
GO
-- ---- schema/stored-procedures/usp_sincronizar_usuario_interno.sql (texto de develop antes de la 66)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_sincronizar_usuario_interno]
    (
    @idTipoIdIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion   INT,
    @primerApellido         NVARCHAR(255),
    @segundoApellido        NVARCHAR(255),
    @primerNombre           NVARCHAR(255),
    @segundoNombre          NVARCHAR(255),
    @correo                 NVARCHAR(255),
    @password               NVARCHAR(500),
    @idCorrelacion          UNIQUEIDENTIFIER,
    @estaActivo             BIT = 1,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado        BIT OUTPUT
)
AS
-- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
DECLARE @idCorrelacionDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idTipoIdIdentificacionDefecto   UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idTipoIdIdentificacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @estaActivoDefecto               BIT = dbo.ufn_obtener_parametro_int(@estaActivo, 'GENERAL', 'ENTERO_UNO');

    DECLARE @numeroIdentificacionDefecto     INT = dbo.ufn_obtener_parametro_int(@numeroIdentificacion, 'GENERAL', 'ENTERO_CERO');
    DECLARE @primerApellidoDefecto           NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@primerApellido, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @segundoApellidoDefecto          NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@segundoApellido, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @primerNombreDefecto             NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@primerNombre, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @segundoNombreDefecto            NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@segundoNombre, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @correoDefecto                   NVARCHAR(255) = LOWER(TRIM(dbo.ufn_obtener_parametro_texto(@correo, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @passwordDefecto                 NVARCHAR(500) = TRIM(dbo.ufn_obtener_parametro_texto(@password, 'GENERAL', 'CADENA_VACIA'));

-- Inicialización de respuesta desde parámetros del catálogo
SELECT
    @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
    @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
    @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validaciones de reglas de negocio en sub-procedimientos
        IF @estadoResultado = 1 
        BEGIN
        EXEC dbo.usp_validar_tipo_identificacion_exista_por_id_interno
                @idTipoId = @idTipoIdIdentificacionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
    END

        IF @estadoResultado = 1 
        BEGIN
        EXEC dbo.usp_validar_unicidad_usuario_interno 
                @idTipoIdIdentificacion = @idTipoIdIdentificacionDefecto,
                @numeroIdentificacion = @numeroIdentificacionDefecto,
                @correo = @correoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
    END

        -- PASO 3: Validación de formatos y restricciones utilizando funciones UFN y mensajes del catálogo
        
        -- A. Validar Tipo de Identificación (GUID por defecto)
        IF @estadoResultado = 1 AND @idTipoIdIdentificacionDefecto = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER)
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- B. Validar Número de Identificación
        IF @estadoResultado = 1 AND dbo.ufn_validar_numero(@numeroIdentificacionDefecto) = 0
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- C. Validar Textos Obligatorios (Nombre y Apellido)
        IF @estadoResultado = 1 AND (dbo.ufn_validar_texto(@primerNombreDefecto) = 0 OR dbo.ufn_validar_texto(@primerApellidoDefecto) = 0)
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_003',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- D. Validar Textos Opcionales (Segundo Nombre y Apellido)
        IF @estadoResultado = 1 AND @segundoNombreDefecto <> '' AND dbo.ufn_validar_texto(@segundoNombreDefecto) = 0
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004',
                @p_param1 = 'segundo nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        IF @estadoResultado = 1 AND @segundoApellidoDefecto <> '' AND dbo.ufn_validar_texto(@segundoApellidoDefecto) = 0
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004',
                @p_param1 = 'segundo apellido',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- E. Validar Correo Electrónico
        IF @estadoResultado = 1 AND dbo.ufn_validar_correo(@correoDefecto) = 0
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- F. Validar presencia de Password/Hash
        IF @estadoResultado = 1 AND (@passwordDefecto IS NULL OR TRIM(@passwordDefecto) = '')
        BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_007',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

        -- PASO 4: Registro final del usuario en dbo.Usuario
        IF @estadoResultado = 1 
        BEGIN
        INSERT INTO dbo.Usuario
            (
            id, tipoIdIdentificacion, numeroIdentificacion,
            primerApellido, segundoApellido, primerNombre, segundoNombre,
            correo, correoConfirmado, estado, password
            )
        VALUES
            (
                NEWID(), @idTipoIdIdentificacionDefecto, @numeroIdentificacionDefecto,
                @primerApellidoDefecto, @segundoApellidoDefecto,
                @primerNombreDefecto, @segundoNombreDefecto,
                @correoDefecto, 0, @estaActivoDefecto, @passwordDefecto
            );

        EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Usuario',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 1;
    END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
GO
-- ---- schema/stored-procedures/usp_admitir_estudiante.sql (texto de develop antes de la 66)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_admitir_estudiante (CULM-001 D.4, HU156; CONTRACT §5.2, SUPUESTO-D-07, SUPUESTO-D-11)
--
-- El ADMINISTRADOR crea (o reutiliza) un estudiante y lo vincula a un programa de SU institucion, sin matricularlo en grupos.
-- Orden: correlacion -> ejecutor (GEN_002) -> RBAC ADMINISTRADOR -> programa activo de su institucion (ADS_003) -> lectura bloqueada
-- (UPDLOCK, HOLDLOCK) de Usuario por documento y por correo -> documento y correo de personas distintas (ADS_004) -> en alta nueva:
-- correo institucional (ADS_005) y contrasena inicial (ADS_006) -> ya admitido en el programa (ADS_002) -> escrituras: Usuario
-- (usp_sincronizar_usuario_interno, solo si no existe), Estudiante (usp_sincronizar_estudiante_interno, solo si no existe) y
-- EstudiantePrograma. Todos los rechazos de negocio ocurren ANTES de escribir; un error del motor revierte lo escrito (transaccion
-- propia o savepoint). Persona existente (mismo documento y correo): no se revalida el dominio ni se pide contrasena (D5).
-- El vinculo se inserta aqui y no con usp_registrar_estudiante_en_programa_interno: ese nucleo resuelve la institucion del
-- estudiante desde uv_estudiante, que exige un programa, asi que fallaria para un estudiante sin programa.
-- @password es el HASH que arma el backend (nunca texto plano); no se escribe en ningun mensaje.
-- Resultset: MUTATION_COMMAND_RESULTSET (4 columnas canonicas) + idUsuario, idEstudiante, esUsuarioNuevo, esEstudianteNuevo
-- (nulos si falla, salvo ADS_002 que devuelve la persona ya admitida para que el backend repare su cuenta de identidad).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_admitir_estudiante]
(
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50) = NULL,
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50) = NULL,
    @correo                  NVARCHAR(255),
    @password                NVARCHAR(500) = NULL,
    @idPrograma              UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @correoNormalizado        NVARCHAR(255) = LOWER(TRIM(@correo));
    DECLARE @passwordNormalizado      NVARCHAR(500) = NULLIF(TRIM(@password), N'');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @idInstitucion           UNIQUEIDENTIFIER;
    DECLARE @idUsuarioPorDocumento   UNIQUEIDENTIFIER;
    DECLARE @idUsuarioPorCorreo      UNIQUEIDENTIFIER;
    DECLARE @idUsuarioResultado      UNIQUEIDENTIFIER;
    DECLARE @idEstudianteResultado   UNIQUEIDENTIFIER;
    DECLARE @esUsuarioNuevo          BIT = 0;
    DECLARE @esEstudianteNuevo       BIT = 0;
    DECLARE @dominioInstitucional    NVARCHAR(255);
    DECLARE @devolverPersona         BIT = 0;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @escrituraRealizada         BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: RBAC ADMINISTRADOR
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

        -- PASO 4: programa activo de la institucion del administrador (ADS_003; indistinguible de uno inexistente)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idInstitucion = a.institucion
            FROM dbo.Administrador a
            WHERE a.usuario = @idUsuarioEjecutorDefecto
            ORDER BY a.id;

            IF @idInstitucion IS NULL
               OR NOT EXISTS (SELECT 1 FROM dbo.uv_programa p
                              WHERE p.id = @idProgramaDefecto AND p.idInstitucion = @idInstitucion AND p.estaActivoPrograma = 1)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ADS_003',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: transaccion (propia o savepoint) y lectura bloqueada de la persona por documento y por correo
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
                SAVE TRANSACTION sp_admitir_estudiante;
                SET @savepointCreado = 1;
            END

            SELECT TOP 1 @idUsuarioPorDocumento = u.id
            FROM dbo.Usuario u WITH (UPDLOCK, HOLDLOCK)
            WHERE u.tipoIdIdentificacion = @idTipoIdIdentificacion AND u.numeroIdentificacion = @numeroIdentificacion;

            SELECT TOP 1 @idUsuarioPorCorreo = u.id
            FROM dbo.Usuario u WITH (UPDLOCK, HOLDLOCK)
            WHERE u.correo = @correoNormalizado;

            -- ADS_004: documento y correo deben ser de la misma persona (ambos inexistentes o ambos del mismo usuario)
            IF (@idUsuarioPorDocumento IS NULL AND @idUsuarioPorCorreo IS NOT NULL)
               OR (@idUsuarioPorDocumento IS NOT NULL AND @idUsuarioPorCorreo IS NULL)
               OR (@idUsuarioPorDocumento IS NOT NULL AND @idUsuarioPorDocumento <> @idUsuarioPorCorreo)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ADS_004',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @idUsuarioResultado = @idUsuarioPorDocumento;
            END

            -- Alta nueva: correo institucional (ADS_005) y contrasena inicial (ADS_006)
            IF @estadoResultado = 1 AND @idUsuarioResultado IS NULL
            BEGIN
                SET @dominioInstitucional = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
                IF dbo.ufn_correo_cumple_dominio_institucional(@correoNormalizado, @dominioInstitucional) = 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ADS_005', @p_param1 = @dominioInstitucional,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
                ELSE IF @passwordNormalizado IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ADS_006',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            -- Persona existente: estudiante y vinculo previos (ADS_002 si ya esta admitida en el programa)
            IF @estadoResultado = 1 AND @idUsuarioResultado IS NOT NULL
            BEGIN
                SELECT TOP 1 @idEstudianteResultado = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioResultado;
                IF @idEstudianteResultado IS NOT NULL
                   AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                               WHERE ep.estudiante = @idEstudianteResultado AND ep.programa = @idProgramaDefecto)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ADS_002',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                    SET @devolverPersona = 1;
                END
            END

            -- PASO 6: escrituras
            IF @estadoResultado = 1 AND @idUsuarioResultado IS NULL
            BEGIN
                SET @escrituraRealizada = 1;
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correoNormalizado,
                    @password = @passwordNormalizado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1 @idUsuarioResultado = u.id FROM dbo.Usuario u WHERE u.correo = @correoNormalizado;
                    SET @esUsuarioNuevo = 1;
                END
            END

            IF @estadoResultado = 1 AND @idEstudianteResultado IS NULL
            BEGIN
                SET @escrituraRealizada = 1;
                EXEC dbo.usp_sincronizar_estudiante_interno
                    @idUsuario = @idUsuarioResultado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1 @idEstudianteResultado = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioResultado;
                    SET @esEstudianteNuevo = 1;
                END
            END

            IF @estadoResultado = 1
            BEGIN
                SET @escrituraRealizada = 1;
                INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
                VALUES (NEWID(), @idEstudianteResultado, @idProgramaDefecto);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ADS_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- PASO 7: cierre respetando el ownership (rollback solo si hubo escrituras y el resultado es fallido)
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    IF @estadoResultado = 1 OR @escrituraRealizada = 0
                        COMMIT TRANSACTION;
                    ELSE
                        ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
            ELSE IF @savepointCreado = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @escrituraRealizada = 1
                    ROLLBACK TRANSACTION sp_admitir_estudiante;
            END
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
        BEGIN
            ROLLBACK TRANSACTION sp_admitir_estudiante;
        END
        -- Transaccion externa condenada que no nos pertenece: se propaga la excepcion al propietario
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
        SET @devolverPersona = 0;
        SET @esUsuarioNuevo = 0;
        SET @esEstudianteNuevo = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idUsuario               = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @idUsuarioResultado, NULL),
        idEstudiante            = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @idEstudianteResultado, NULL),
        esUsuarioNuevo          = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @esUsuarioNuevo, NULL),
        esEstudianteNuevo       = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @esEstudianteNuevo, NULL);
END;
GO
GO
-- ---- schema/stored-procedures/usp_internal_matricular_por_token.sql (texto de develop antes de la 66)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: nucleo interno de la matricula atomica por token o PIN de una ventana ACTIVA. Lo invocan las fachadas
-- usp_matricular_estudiante_por_token (autenticado) y usp_registrar_estudiante_por_token_publico (publico). NO se concede
-- EXECUTE al rol de runtime. CONTRACT A2.
--   * @idUsuarioAutenticado NO NULL: modo autenticado: RBAC ESTUDIANTE; el estudiante es el de ese usuario.
--   * @idUsuarioAutenticado NULL: modo publico: crea Usuario (ACTIVO, correoConfirmado = 0) y Estudiante; el correo debe ser
--     institucional (IDENT-001: VCE_001). Documento o correo ya existentes: MQR_005 sin cambios.
--   * Reglas de HU050 via usp_registrar_estudiante_en_grupo_interno (cupo, cruce, duplicado, programa). El estado de la
--     matricula es el parametro MATRICULA_QR/ESTADO_MATRICULA (sin literal quemado), validado ANTES de escribir.
--   * Atomico: la expiracion perezosa de la ventana persiste; el trabajo de negocio se revierte hasta su savepoint ante
--     cualquier falla posterior a la escritura.
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_matricular_por_token]
(
    @idCorrelacion            UNIQUEIDENTIFIER,
    @tokenHash                VARBINARY(32),
    @pin                      NCHAR(6),
    @idUsuarioAutenticado     UNIQUEIDENTIFIER,
    @idTipoIdentificacion     UNIQUEIDENTIFIER,
    @numeroIdentificacion     INT,
    @primerNombre             NVARCHAR(50),
    @segundoNombre            NVARCHAR(50),
    @primerApellido           NVARCHAR(50),
    @segundoApellido          NVARCHAR(50),
    @correo                   NVARCHAR(100),
    @password                 NVARCHAR(500),
    @mensajeUsuarioResultado  NVARCHAR(4000)   OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000)   OUTPUT,
    @estadoResultado          BIT              OUTPUT,
    @idEstudianteResultado    UNIQUEIDENTIFIER OUTPUT,
    @idUsuarioResultado       UNIQUEIDENTIFIER OUTPUT,
    @idGrupoResultado         UNIQUEIDENTIFIER OUTPUT,
    -- DEC-078: programa que elige el estudiante en un grupo compartido (uno de ufn_programas_grupo; EST_006 si es ajeno).
    @idProgramaElegido        UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    DECLARE @idVentana        UNIQUEIDENTIFIER;
    DECLARE @idGrupo          UNIQUEIDENTIFIER;
    DECLARE @idDocenteEmisor  UNIQUEIDENTIFIER;
    DECLARE @codigoRechazo    VARCHAR(20) = NULL;
    DECLARE @parametroRechazo NVARCHAR(255) = NULL;

    DECLARE @idUsuarioTarget    UNIQUEIDENTIFIER = NULL;
    DECLARE @idEstudianteTarget UNIQUEIDENTIFIER = NULL;
    DECLARE @correoNormalizado  NVARCHAR(100)    = LOWER(TRIM(@correo));
BEGIN
    SET NOCOUNT ON;

    SELECT @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @estadoResultado = 1,
           @idEstudianteResultado = NULL, @idUsuarioResultado = NULL, @idGrupoResultado = NULL;

    BEGIN TRY
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_hu176b_matricular;
            SET @savepointCreado = 1;
        END

        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: resolver la ventana (UPDLOCK). Puede escribir solo la expiracion perezosa.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_internal_resolver_token_matricula
                @tokenHash = @tokenHash, @pin = @pin,
                @idVentana = @idVentana OUTPUT, @idGrupo = @idGrupo OUTPUT,
                @idDocenteEmisor = @idDocenteEmisor OUTPUT, @codigoRechazo = @codigoRechazo OUTPUT;
        END

        -- PASO 3: validaciones sin escritura
        DECLARE @codigoMatricula NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_MATRICULA') AS NVARCHAR(10));

        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idUsuarioAutenticado IS NOT NULL
        BEGIN
            -- Modo autenticado: el usuario debe ser un ESTUDIANTE
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioAutenticado,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                SET @idUsuarioTarget = @idUsuarioAutenticado;
                SELECT TOP 1 @idEstudianteTarget = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioAutenticado;

                IF @idEstudianteTarget IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'GEN_001', @p_param1 = 'Estudiante',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END
        ELSE IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            -- Modo publico: datos obligatorios
            IF @idTipoIdentificacion IS NULL OR @numeroIdentificacion IS NULL OR @primerNombre IS NULL
               OR @primerApellido IS NULL OR @correoNormalizado IS NULL OR @correoNormalizado = N'' OR @password IS NULL
            BEGIN
                SET @codigoRechazo = 'GEN_002';
                SET @parametroRechazo = N'datos de registro';
            END
            -- Persona ya registrada (documento o correo): debe iniciar sesion
            ELSE IF EXISTS (
                SELECT 1 FROM dbo.Usuario u
                WHERE u.correo = @correoNormalizado
                   OR (u.tipoIdIdentificacion = @idTipoIdentificacion AND u.numeroIdentificacion = @numeroIdentificacion)
            )
                SET @codigoRechazo = 'MQR_005';
            -- IDENT-001: el correo de un alta nueva debe ser institucional
            ELSE IF dbo.ufn_correo_cumple_dominio_institucional(@correo, dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE')) = 0
            BEGIN
                SET @codigoRechazo = 'VCE_001';
                SET @parametroRechazo = CAST(dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE') AS NVARCHAR(255));
            END
        END

        -- Ya matriculado (solo se puede evaluar con estudiante conocido: modo autenticado)
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idEstudianteTarget IS NOT NULL
           AND EXISTS (
                SELECT 1
                FROM dbo.EstudianteGrupo eg
                INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.estado
                WHERE eg.estudiante = @idEstudianteTarget AND eg.grupo = @idGrupo AND es.codigo = @codigoMatricula
           )
            SET @codigoRechazo = 'MQR_004';

        -- DEC-078: el programa de la ventana (si el docente lo fijo) o el que eligio el estudiante.
        DECLARE @programaVentana UNIQUEIDENTIFIER = COALESCE(
            (SELECT t.programaPorDefecto FROM dbo.TokenMatriculaGrupo t WHERE t.id = @idVentana), @idProgramaElegido);
        -- DEC-078: un programa elegido que no es del grupo se rechaza antes de crear usuario o matricula (EST_006).
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @programaVentana IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) pg WHERE pg.idPrograma = @programaVentana)
            SET @codigoRechazo = 'EST_006';
        -- CULM-001 B2NM (S3) / DEC-078: grupo multiprograma sin programa (ni de la ventana ni elegido) y sin vinculo previo ->
        -- MQR_008 (el estudiante debe elegir su programa), antes de crear usuario o matricula.
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
           AND (SELECT COUNT(*) FROM dbo.ufn_programas_grupo(@idGrupo)) > 1
           AND @programaVentana IS NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                           INNER JOIN dbo.ufn_programas_grupo(@idGrupo) pg ON pg.idPrograma = ep.programa
                           WHERE ep.estudiante = @idEstudianteTarget)
            SET @codigoRechazo = 'MQR_008';

        -- Cupo, antes de crear nada
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno
                @idGrupo = @idGrupo,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- Estado de matricula configurado y existente, ANTES de escribir (falla rapida: un parametro mal
        -- configurado no debe dejar usuarios a medias; ademas ROLLBACK no es valido bajo INSERT ... EXEC).
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_estado_estudiante_grupo es WHERE es.codigo = UPPER(TRIM(@codigoMatricula)))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001', @p_param1 = 'Estado de matricula por QR',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- Mensaje del rechazo por catalogo
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @parametroRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: escrituras de negocio bajo un savepoint propio (la expiracion perezosa del paso 2 no se revierte)
        IF @estadoResultado = 1
        BEGIN
            SAVE TRANSACTION sp_hu176b_negocio;

            IF @idEstudianteTarget IS NULL
            BEGIN
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correo,
                    @password = @password,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @estaActivo = 1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                    SELECT TOP 1 @idUsuarioTarget = u.id FROM dbo.Usuario u WHERE u.correo = @correoNormalizado;

                IF @estadoResultado = 1
                BEGIN
                    EXEC dbo.usp_sincronizar_estudiante_interno
                        @idUsuario = @idUsuarioTarget,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;

                    IF @estadoResultado = 1
                        SELECT TOP 1 @idEstudianteTarget = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioTarget;
                END
            END

            IF @estadoResultado = 1 AND @idEstudianteTarget IS NOT NULL
            BEGIN
                EXEC dbo.usp_registrar_estudiante_en_grupo_interno
                    @idEstudiante = @idEstudianteTarget,
                    @idGrupo = @idGrupo,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @codigoEstado = @codigoMatricula,
                    @idProgramaElegido = @programaVentana,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                UPDATE dbo.TokenMatriculaGrupo SET totalMatriculas = totalMatriculas + 1 WHERE id = @idVentana;
            END
            ELSE IF XACT_STATE() = 1
            BEGIN
                -- Falla despues de escribir: se revierte solo el trabajo de negocio
                ROLLBACK TRANSACTION sp_hu176b_negocio;
                SELECT @idUsuarioTarget = NULL, @idEstudianteTarget = NULL;
            END
        END

        -- PASO 5: cierre de la transaccion propia (confirma tambien la expiracion perezosa)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() = -1
                ROLLBACK TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_hu176b_matricular;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SELECT @idUsuarioTarget = NULL, @idEstudianteTarget = NULL;
    END CATCH

    IF @estadoResultado = 1
        SELECT @idEstudianteResultado = @idEstudianteTarget, @idUsuarioResultado = @idUsuarioTarget, @idGrupoResultado = @idGrupo;
END;
GO
GO
-- ---- schema/stored-procedures/usp_vincular_docente_programa.sql (texto de develop antes de la 66)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU091: vincula un docente al programa del coordinador. Tres modos excluyentes:
--   (a) @idDocente        docente existente (p. ej. de otro programa de la misma institucion)
--   (b) @idUsuario        usuario existente que aun no es docente
--   (c) datos de persona  alta nueva (usuario + docente + vinculo); documento/correo existentes => DOC_003
-- RBAC COORDINADOR + titularidad PROGRAMA se validan DENTRO del SP. @password es el HASH (nunca texto plano).
-- Una sola transaccion con ownership (transaccion propia o savepoint si el llamador ya tiene una).
-- MEJORAS-SERGIO-2026-11-18 (migracion 56): sin tipo de vinculacion (el sistema ya no lo administra; se retiro DOC_004).
CREATE OR ALTER PROCEDURE [dbo].[usp_vincular_docente_programa]
(
    @idDocente              UNIQUEIDENTIFIER = NULL,
    @idUsuario              UNIQUEIDENTIFIER = NULL,
    @idTipoIdentificacion   UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion   INT              = NULL,
    @primerNombre           NVARCHAR(50)     = NULL,
    @segundoNombre          NVARCHAR(50)     = NULL,
    @primerApellido         NVARCHAR(50)     = NULL,
    @segundoApellido        NVARCHAR(50)     = NULL,
    @correo                 NVARCHAR(100)    = NULL,
    @password               NVARCHAR(500)    = NULL,
    @idPrograma             UNIQUEIDENTIFIER,
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor      UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @modoDocente BIT = IIF(@idDocente IS NULL, 0, 1);
    DECLARE @modoUsuario BIT = IIF(@idUsuario IS NULL, 0, 1);
    DECLARE @modoNuevo   BIT = IIF(@numeroIdentificacion IS NULL AND @correo IS NULL AND @idTipoIdentificacion IS NULL
                                   AND @primerNombre IS NULL AND @primerApellido IS NULL AND @password IS NULL, 0, 1);
    DECLARE @idUsuarioResuelto  UNIQUEIDENTIFIER;
    DECLARE @idDocenteResuelto  UNIQUEIDENTIFIER;
    DECLARE @idInstitucion      UNIQUEIDENTIFIER;
    DECLARE @correoNormalizado  NVARCHAR(100) = LOWER(TRIM(@correo));

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: RBAC COORDINADOR
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: titularidad sobre el programa
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idProgramaDefecto,
                @tipoEntidadPadre = 'PROGRAMA',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4B: programa activo
        IF @estadoResultado = 1
        BEGIN
            SELECT @idInstitucion = idInstitucion FROM dbo.uv_programa WHERE id = @idProgramaDefecto AND estaActivoPrograma = 1;
            IF @idInstitucion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PROG_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: exactamente un modo (DOC_005)
        IF @estadoResultado = 1 AND (CAST(@modoDocente AS INT) + CAST(@modoUsuario AS INT) + CAST(@modoNuevo AS INT)) <> 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'DOC_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 7: validaciones de solo lectura ANTES de abrir la transaccion (sin escrituras no hay rollback que hacer)
        IF @estadoResultado = 1
        BEGIN
            IF @modoNuevo = 1
            BEGIN
                IF EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE numeroIdentificacion = @numeroIdentificacion OR correo = @correoNormalizado)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_003',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
                -- DEC-073: el docente nuevo usa el correo institucional (VCE_008)
                IF @estadoResultado = 1
                EXEC dbo.usp_validar_correo_institucional_personal_interno
                    @correo = @correo,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
            ELSE IF @modoUsuario = 1
            BEGIN
                SELECT TOP 1 @idUsuarioResuelto = id FROM dbo.uv_usuario WHERE id = @idUsuario AND estaActivoUsuario = 1;
                IF @idUsuarioResuelto IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
                ELSE
                    SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE idUsuario = @idUsuarioResuelto;
            END
            ELSE
            BEGIN
                SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE id = @idDocente AND estaActivoUsuario = 1;
                IF @idDocenteResuelto IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
            END

            -- El docente no puede pertenecer solo a otra institucion
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.uv_docente_programa WHERE idDocente = @idDocenteResuelto AND idInstitucion <> @idInstitucion)
               AND NOT EXISTS (SELECT 1 FROM dbo.uv_docente_programa WHERE idDocente = @idDocenteResuelto AND idInstitucion = @idInstitucion)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DOC_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END

            -- Vinculo duplicado
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @idDocenteResuelto AND programa = @idProgramaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DOC_006',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 0
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 8: escrituras en una sola transaccion con ownership
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
                SAVE TRANSACTION usp_vincular_docente_programa;
                SET @savepointCreado = 1;
            END

            -- 8A: persona nueva
            IF @modoNuevo = 1
            BEGIN
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdentificacion,
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
                    SELECT TOP 1 @idUsuarioResuelto = id FROM dbo.uv_usuario WHERE correo = @correoNormalizado;
            END

            -- 8B: rol Docente para la persona (modos nuevo y usuario sin rol)
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NULL
            BEGIN
                EXEC dbo.usp_sincronizar_docente_interno
                    @idUsuario = @idUsuarioResuelto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
                IF @estadoResultado = 1
                    SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE idUsuario = @idUsuarioResuelto;
            END

            -- 8C: vinculo (revalida la unicidad bajo UPDLOCK, HOLDLOCK)
            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_vincular_docente_programa_interno
                    @idDocente = @idDocenteResuelto,
                    @idPrograma = @idProgramaDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            -- PASO 9: cierre respetando ownership
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    IF @estadoResultado = 1 COMMIT TRANSACTION; ELSE ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
            ELSE IF @savepointCreado = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 0
                    ROLLBACK TRANSACTION usp_vincular_docente_programa;
            END
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0 ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_vincular_docente_programa;
        END

        -- Transaccion externa doomed: no nos pertenece, se propaga al propietario.
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

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
GO
IF COL_LENGTH(N'dbo.Usuario', N'password') IS NULL
    THROW 55703, 'MIGRACION 66 DOWN: la columna dbo.Usuario.password no quedo restaurada.', 1;
GO
PRINT 'MIGRACION 66 DOWN OK';
GO
