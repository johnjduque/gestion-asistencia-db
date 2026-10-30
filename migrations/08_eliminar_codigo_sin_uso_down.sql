-- Rollback de 08_eliminar_codigo_sin_uso_up.sql: restaura los 18 objetos tal como estaban en develop (b27c865).
-- Solo para revertir el commit. Orden: funciones, internos y publicos.

-- ===== schema/functions/fn_diagramobjects.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  FUNCTION dbo.fn_diagramobjects() 
	RETURNS int
	WITH EXECUTE AS N'dbo'
	AS
	BEGIN
		declare @id_upgraddiagrams		int
		declare @id_sysdiagrams			int
		declare @id_helpdiagrams		int
		declare @id_helpdiagramdefinition	int
		declare @id_creatediagram	int
		declare @id_renamediagram	int
		declare @id_alterdiagram 	int 
		declare @id_dropdiagram		int
		declare @InstalledObjects	int

		select @InstalledObjects = 0

		select 	@id_upgraddiagrams = object_id(N'dbo.sp_upgraddiagrams'),
			@id_sysdiagrams = object_id(N'dbo.sysdiagrams'),
			@id_helpdiagrams = object_id(N'dbo.sp_helpdiagrams'),
			@id_helpdiagramdefinition = object_id(N'dbo.sp_helpdiagramdefinition'),
			@id_creatediagram = object_id(N'dbo.sp_creatediagram'),
			@id_renamediagram = object_id(N'dbo.sp_renamediagram'),
			@id_alterdiagram = object_id(N'dbo.sp_alterdiagram'), 
			@id_dropdiagram = object_id(N'dbo.sp_dropdiagram')

		if @id_upgraddiagrams is not null
			select @InstalledObjects = @InstalledObjects + 1
		if @id_sysdiagrams is not null
			select @InstalledObjects = @InstalledObjects + 2
		if @id_helpdiagrams is not null
			select @InstalledObjects = @InstalledObjects + 4
		if @id_helpdiagramdefinition is not null
			select @InstalledObjects = @InstalledObjects + 8
		if @id_creatediagram is not null
			select @InstalledObjects = @InstalledObjects + 16
		if @id_renamediagram is not null
			select @InstalledObjects = @InstalledObjects + 32
		if @id_alterdiagram  is not null
			select @InstalledObjects = @InstalledObjects + 64
		if @id_dropdiagram is not null
			select @InstalledObjects = @InstalledObjects + 128
		
		return @InstalledObjects 
	END
GO


-- ===== schema/functions/ufn_validar_password.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    FUNCTION [dbo].[ufn_validar_password] (
    @p_password NVARCHAR(MAX),
    @p_numeroIdentificacionDefecto INT
)
RETURNS BIT
AS
BEGIN
    DECLARE @resultado BIT = 0;
    DECLARE @passwordString NVARCHAR(MAX) = dbo.ufn_obtener_parametro_texto(@p_password, 'GENERAL', 'CADENA_VACIA');
    DECLARE @idString NVARCHAR(MAX) = CAST(@p_numeroIdentificacionDefecto AS NVARCHAR(MAX));

    -- 1. Regla de Oro: Si es el valor por defecto, ES V?LIDO
    IF @passwordString = @idString
    BEGIN
        SET @resultado = 1;
    END
    -- 2. Si no es el defecto, validar condiciones de seguridad
    ELSE
    BEGIN
        IF LEN(@passwordString) >= 8                          -- M?nimo 8 caracteres
           AND @passwordString LIKE '%[0-9]%'                -- Al menos un n?mero
           AND @passwordString LIKE '%[A-Z]%'                -- Al menos una may?scula
           AND @passwordString LIKE '%[a-z]%'                -- Al menos una min?scula
           AND @passwordString LIKE '%[!@#$%^&*()_+-=%]%'    -- Al menos un car?cter especial
        BEGIN
            SET @resultado = 1;
        END
    END

    RETURN @resultado;
END
GO


-- ===== schema/functions/ufn_obtener_perfil_usuario_contexto.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION [dbo].[ufn_obtener_perfil_usuario_contexto] (
    @p_idUsuario UNIQUEIDENTIFIER
)
RETURNS VARCHAR(10)
AS
BEGIN
    IF @p_idUsuario IS NULL
        RETURN NULL;

    DECLARE @v_codigoPerfil VARCHAR(10);

    SELECT TOP 1 @v_codigoPerfil = codigoPerfil
    FROM dbo.uv_usuario_perfil
    WHERE idUsuario = @p_idUsuario;

    RETURN @v_codigoPerfil;
END;
GO


-- ===== schema/stored-procedures/usp_validar_estudiante_grupo_exista_interno.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_estudiante_grupo_exista_interno]
(
    @idEstudianteGrupo       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteGrupoDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudianteGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @existe        BIT = 0;
    DECLARE @estadoActivo  BIT = 0;

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

        -- PASO 2: Validación de GUID por defecto
        IF @estadoResultado = 1 AND @idEstudianteGrupoDefecto = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'idEstudianteGrupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validación de existencia y estado en la vista uv_estudiante_grupo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 
                @existe = 1,
                @estadoActivo = CASE WHEN codigoEstadoEstudiante = 'A' THEN 1 ELSE 0 END
            FROM dbo.uv_estudiante_grupo
            WHERE id = @idEstudianteGrupoDefecto;

            IF @existe = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001',
                    @p_param1 = 'EstudianteGrupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @estadoActivo = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'USU_002',
                    @p_param1 = @idEstudianteGrupoDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
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


-- ===== schema/stored-procedures/usp_registrar_docente_en_grupo_interno.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_docente_en_grupo_interno]
(
    @idDocente               UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

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
            EXEC dbo.usp_validar_docente_exista_por_id_interno 
                @idDocente = @idDocenteDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_para_docente_interno 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_cruce_horario_docente_interno 
                @idDocente = @idDocenteDefecto, 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Asignación final del docente al grupo en dbo.Grupo
        IF @estadoResultado = 1 
        BEGIN
            UPDATE dbo.Grupo 
            SET docente = @idDocenteDefecto 
            WHERE id = @idGrupoDefecto;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_005',
                @p_param1 = 'Docente en Grupo',
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


-- ===== schema/stored-procedures/usp_registrar_docente_en_grupo.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_docente_en_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteRegistrado      UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
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
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.8: Validar existencia del grupo antes de sincronizar identidad
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Sincronización de identidad (Usuario y Docente) y asignación a grupo
        IF @estadoResultado = 1
        BEGIN
            DECLARE @idTipoIdCC UNIQUEIDENTIFIER;
            SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC';
            IF @idTipoIdCC IS NULL SELECT TOP 1 @idTipoIdCC = id FROM dbo.TipoIdentificacion;

            DECLARE @idUsuarioTarget UNIQUEIDENTIFIER;
            SELECT TOP 1 @idUsuarioTarget = id FROM dbo.Usuario WHERE correo = LOWER(TRIM(@correo));

            IF @idUsuarioTarget IS NULL
            BEGIN
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
                    SELECT TOP 1 @idUsuarioTarget = id FROM dbo.Usuario WHERE correo = LOWER(TRIM(@correo));
            END

            IF @estadoResultado = 1 AND @idUsuarioTarget IS NOT NULL
            BEGIN
                SELECT TOP 1 @idDocenteRegistrado = id FROM dbo.Docente WHERE usuario = @idUsuarioTarget;

                IF @idDocenteRegistrado IS NULL
                BEGIN
                    EXEC dbo.usp_sincronizar_docente_interno
                        @idUsuario = @idUsuarioTarget,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;

                    IF @estadoResultado = 1
                        SELECT TOP 1 @idDocenteRegistrado = id FROM dbo.Docente WHERE usuario = @idUsuarioTarget;
                END
            END

            IF @estadoResultado = 1 AND @idDocenteRegistrado IS NOT NULL
            BEGIN
                EXEC dbo.usp_registrar_docente_en_grupo_interno
                    @idDocente = @idDocenteRegistrado,
                    @idGrupo = @idGrupoDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO


-- ===== schema/stored-procedures/usp_registrar_asistencia_estudiante.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_asistencia_estudiante]
(
    @idEstudianteGrupo  UNIQUEIDENTIFIER,
    @idGrupoSesion      UNIQUEIDENTIFIER,
    @idEstadoAsistencia UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    -- 1. Estandarización e inicialización de variables locales utilizando catálogo de parámetros (Sin ISNULL)
    DECLARE @idCorrelacionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteGrupoDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudianteGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupoSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstadoAsistenciaDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstadoAsistencia, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @idEstudiante UNIQUEIDENTIFIER;
    DECLARE @codigoEstado NVARCHAR(5);

    -- Inicialización interna de variables de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación de presencia del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
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
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validación de la matrícula activa del estudiante (EstudianteGrupo)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_grupo_exista_interno
                @idEstudianteGrupo = @idEstudianteGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validación de la existencia de la sesión de clase
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idGrupoSesionDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Recuperación de datos de identidad y sincronización de asistencia
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 
                @idEstudiante = estudiante 
            FROM [dbo].[EstudianteGrupo]
            WHERE id = @idEstudianteGrupoDefecto;

            SELECT TOP 1 
                @codigoEstado = codigo 
            FROM [dbo].[RazonCausa]
            WHERE id = @idEstadoAsistenciaDefecto;

            IF @codigoEstado IS NULL OR @codigoEstado = ''
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'RC_001',
                    @p_param1 = @idEstadoAsistenciaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- Invocación al sincronizador interno de asistencia
            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
                    @idEstudiante = @idEstudiante,
                    @idSesion = @idGrupoSesionDefecto,
                    @codigoEstado = @codigoEstado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
        END

        -- PASO 5: Evaluación de resultado final y generación de mensaje de éxito desde el Catálogo de Mensajes
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'AsistenciaEstudiante',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones inesperadas
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados garantizando el nombre de columna idCorrelacion
    SELECT 
        idCorrelacion = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END;
GO


-- ===== schema/stored-procedures/usp_resolver_solicitud_matricula.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_solicitud_matricula]
(
    @idSolicitud            UNIQUEIDENTIFIER,
    @idCoordinador          UNIQUEIDENTIFIER,
    @accion                 NVARCHAR(20),
    @respuestaCoordinador   NVARCHAR(MAX),
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor      UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación del usuario ejecutor si es suministrado
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
            EXEC dbo.usp_validar_usuario_existe_por_id_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Capability explícitamente no implementada en el esquema actual.
        -- SolicitudMatricula no está modelada en schema/tables ni existe lógica de negocio
        -- real para resolverla; se retorna siempre un error controlado en lugar de simular
        -- un éxito ficticio (ver DOCUMENTACION_PROCEDIMIENTOS_ORQUESTADORES.md).
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO


-- ===== schema/stored-procedures/usp_consultar_asignaturas_paginado.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_asignaturas_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Búsqueda y catálogo paginado de asignaturas curriculares consumiendo uv_asignatura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asignaturas_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @filtroTexto             NVARCHAR(100)    = NULL,
    @codigo                  NVARCHAR(50)     = NULL,
    @estaActivo              BIT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Normalización de paginación
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroTextoNormalizado NVARCHAR(102) = IIF(TRIM(@filtroTexto) IS NULL OR TRIM(@filtroTexto) = '', NULL, CONCAT('%', TRIM(@filtroTexto), '%'));
    DECLARE @filtroCodigo NVARCHAR(50) = IIF(TRIM(@codigo) IS NULL OR TRIM(@codigo) = '', NULL, TRIM(@codigo));
    DECLARE @filtroActivo BIT = @estaActivo;

    -- Control de diagnóstico
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 3: Consulta optimizada de asignaturas
        SELECT
            a.id,
            a.codigo,
            a.nombre,
            a.credito,
            a.idArea,
            a.nombreArea,
            a.idComponente,
            a.nombreComponente,
            a.inp,
            a.nombrePrograma,
            a.codigoSemestre,
            a.estaActivaAsignatura,
            COUNT(1) OVER() AS totalRegistros
        FROM dbo.uv_asignatura a
        WHERE (@filtroActivo IS NULL OR a.estaActivaAsignatura = @filtroActivo)
          AND (@filtroCodigo IS NULL OR a.codigo = @filtroCodigo)
          AND (
              @filtroTextoNormalizado IS NULL
              OR a.nombre LIKE @filtroTextoNormalizado
              OR a.nombrePrograma LIKE @filtroTextoNormalizado
          )
        ORDER BY a.nombre ASC, a.codigo ASC, a.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO


-- ===== schema/stored-procedures/usp_consultar_asistencias_estudiante_paginado.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_asistencias_estudiante_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Consultar el historial y auditoría de asistencia de un estudiante en un grupo
--   académico específico consumiendo uv_auth_sesion, uv_asistencia y uv_detalle_asistencia.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asistencias_estudiante_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idEstudiante            UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginación normalizada
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Control de diagnóstico y contexto
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        -- Paso 3: Validación obligatoria de idEstudiante e idGrupo
        IF @estadoResultado = 1 AND (@idEstudianteDefecto IS NULL OR @idEstudianteDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Estudiante',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@idGrupoDefecto IS NULL OR @idGrupoDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 4: Establecer identidad temporal en contexto
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @idUsuarioDefecto;

        -- Paso 5: Consulta de asistencias históricas del estudiante
        SELECT
            da.id                       AS idDetalleAsistencia,
            da.codigo                   AS codigoDetalleAsistencia,
            asi.id                      AS idAsistencia,
            se.id                       AS idSesion,
            se.nombre                   AS nombreSesion,
            se.codigo                   AS codigoSesion,
            se.numeroSemana             AS numeroSemana,
            se.fechaHoraInicio          AS fechaHoraInicio,
            se.fechaHoraFin             AS fechaHoraFin,
            da.asistio                  AS asistio,
            da.idRazonCausa             AS idRazonCausa,
            da.codigoRazonCausa         AS codigoRazonCausa,
            da.nombreRazonCausa         AS nombreRazonCausa,
            COUNT(1) OVER()             AS totalRegistros
        FROM dbo.uv_auth_sesion se
        INNER JOIN dbo.uv_asistencia asi ON se.id = asi.idSesion
        INNER JOIN dbo.uv_detalle_asistencia da ON asi.id = da.idAsistencia
        INNER JOIN dbo.uv_estudiante_grupo eg ON asi.idEstudianteGrupo = eg.id
        WHERE eg.idEstudiante = @idEstudianteDefecto
          AND eg.idGrupo = @idGrupoDefecto
        ORDER BY se.fechaHoraInicio ASC, se.numero ASC, da.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

        -- Paso 6: Restaurar contexto previo
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;

    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
        THROW;
    END CATCH;
END;
GO


-- ===== schema/stored-procedures/usp_consultar_docente_por_id.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_docente_por_id
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta individual de docente
--   READ_QUERY_RESULTSET             Retorna datos de identidad y usuario
--
-- Proposito:
--   Recuperar la información consolidada de un docente específico consumiendo
--   uv_docente_identidad y uv_usuario.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_docente_por_id]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idDocente               UNIQUEIDENTIFIER
)
AS
    -- 1. Declaraciones y normalizaciones previas obligatorias (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Control de diagnóstico
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        -- Paso 3: Validación obligatoria de idDocente
        IF @estadoResultado = 1 AND (@idDocenteDefecto IS NULL OR @idDocenteDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Docente',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 4: Consulta de docente por identificador
        SELECT
            d.id                    AS id,
            u.id                    AS idUsuario,
            u.idTipoIdentificacion  AS tipoIdentificacionId,
            u.numeroIdentificacion  AS numeroIdentificacion,
            u.primerApellido        AS primerApellido,
            u.segundoApellido       AS segundoApellido,
            u.primerNombre          AS primerNombre,
            u.segundoNombre         AS segundoNombre,
            u.nombreCompleto        AS nombreCompleto,
            u.correo                AS correo,
            u.estaActivoUsuario     AS estaActivoUsuario
        FROM dbo.uv_docente_identidad d
        INNER JOIN dbo.uv_usuario u ON d.idUsuario = u.id
        WHERE d.id = @idDocenteDefecto;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO


-- ===== schema/stored-procedures/usp_consultar_docentes_paginado.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_docentes_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Búsqueda, filtrado y paginación determinística de docentes institucionales
--   consumiendo las vistas base uv_docente_identidad, uv_usuario y uv_docente.
--   Permite filtrar opcionalmente por tipo/número de documento, nombres/correo,
--   facultad, programa y estado activo.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_docentes_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idTipoIdentificacion    UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion    NVARCHAR(50)     = NULL,
    @filtroTexto             NVARCHAR(100)    = NULL,
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @idPrograma              UNIQUEIDENTIFIER = NULL,
    @estaActivo              BIT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones y normalizaciones previas obligatorias (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Normalización de paginación
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroDocNormalizado NVARCHAR(50) = IIF(TRIM(@numeroIdentificacion) IS NULL OR TRIM(@numeroIdentificacion) = '', NULL, TRIM(@numeroIdentificacion));
    DECLARE @filtroTextoNormalizado NVARCHAR(102) = IIF(TRIM(@filtroTexto) IS NULL OR TRIM(@filtroTexto) = '', NULL, CONCAT('%', TRIM(@filtroTexto), '%'));
    DECLARE @filtroTipoId UNIQUEIDENTIFIER = @idTipoIdentificacion;
    DECLARE @filtroFacId UNIQUEIDENTIFIER = @idFacultad;
    DECLARE @filtroProgId UNIQUEIDENTIFIER = @idPrograma;
    DECLARE @filtroActivo BIT = @estaActivo;

    -- Control de diagnóstico
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 3: Consulta optimizada de docentes sobre vistas base
        SELECT
            d.id                    AS id,
            u.id                    AS idUsuario,
            u.idTipoIdentificacion  AS tipoIdentificacionId,
            u.numeroIdentificacion  AS numeroIdentificacion,
            u.primerApellido        AS primerApellido,
            u.segundoApellido       AS segundoApellido,
            u.primerNombre          AS primerNombre,
            u.segundoNombre         AS segundoNombre,
            u.nombreCompleto        AS nombreCompleto,
            u.correo                AS correo,
            u.estaActivoUsuario     AS estaActivoUsuario,
            COUNT(1) OVER()         AS totalRegistros
        FROM dbo.uv_docente_identidad d
        INNER JOIN dbo.uv_usuario u ON d.idUsuario = u.id
        WHERE
            (@filtroTipoId IS NULL OR u.idTipoIdentificacion = @filtroTipoId)
            AND (@filtroDocNormalizado IS NULL OR u.numeroIdentificacion = @filtroDocNormalizado)
            AND (@filtroActivo IS NULL OR u.estaActivoUsuario = @filtroActivo)
            AND (
                @filtroTextoNormalizado IS NULL
                OR u.nombreCompleto LIKE @filtroTextoNormalizado
                OR u.correo LIKE @filtroTextoNormalizado
            )
            AND (
                @filtroFacId IS NULL
                OR EXISTS (
                    SELECT 1 
                    FROM dbo.uv_docente vd 
                    WHERE vd.id = d.id 
                      AND vd.idFacultad = @filtroFacId
                )
            )
            AND (
                @filtroProgId IS NULL
                OR EXISTS (
                    SELECT 1 
                    FROM dbo.uv_docente vd 
                    WHERE vd.id = d.id 
                      AND vd.idPrograma = @filtroProgId
                )
            )
        ORDER BY u.primerApellido ASC, u.primerNombre ASC, u.numeroIdentificacion ASC, d.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO


-- ===== schema/stored-procedures/usp_consultar_estudiante_por_id.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_estudiante_por_id
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta individual de estudiante
--   READ_QUERY_RESULTSET             Retorna datos de identidad y contexto academico
--
-- Proposito:
--   Recuperar la información consolidada de un estudiante específico (datos de
--   usuario y sus adscripciones académicas activas) consumiendo uv_estudiante_identidad,
--   uv_usuario y uv_estudiante.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_estudiante_por_id]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idEstudiante            UNIQUEIDENTIFIER
)
AS
    -- 1. Declaraciones y normalizaciones previas obligatorias (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Control de diagnóstico
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        -- Paso 3: Validación obligatoria de idEstudiante
        IF @estadoResultado = 1 AND (@idEstudianteDefecto IS NULL OR @idEstudianteDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Estudiante',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 4: Consulta de estudiante por identificador
        SELECT
            e.id                    AS id,
            u.id                    AS idUsuario,
            u.idTipoIdentificacion  AS tipoIdentificacionId,
            u.numeroIdentificacion  AS numeroIdentificacion,
            u.primerApellido        AS primerApellido,
            u.segundoApellido       AS segundoApellido,
            u.primerNombre          AS primerNombre,
            u.segundoNombre         AS segundoNombre,
            u.nombreCompleto        AS nombreCompleto,
            u.correo                AS correo,
            u.estaActivoUsuario     AS estaActivoUsuario
        FROM dbo.uv_estudiante_identidad e
        INNER JOIN dbo.uv_usuario u ON e.idUsuario = u.id
        WHERE e.id = @idEstudianteDefecto;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO


-- ===== schema/stored-procedures/usp_consultar_estudiantes_grupo_paginado.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_estudiantes_grupo_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Listar de forma paginada y filtrada los estudiantes matriculados en un grupo
--   académico específico, incluyendo su estado de matrícula e indicadores acumulados
--   de inasistencia. Consume uv_estudiante_grupo, uv_estudiante_identidad, uv_usuario,
--   uv_asistencia y uv_detalle_asistencia.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_estudiantes_grupo_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @filtroTexto             NVARCHAR(100)    = NULL,
    @idEstadoEstudiante      UNIQUEIDENTIFIER = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones y normalizaciones previas obligatorias (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Normalización de paginación
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroTextoNormalizado NVARCHAR(102) = IIF(TRIM(@filtroTexto) IS NULL OR TRIM(@filtroTexto) = '', NULL, CONCAT('%', TRIM(@filtroTexto), '%'));
    DECLARE @filtroEstadoId UNIQUEIDENTIFIER = @idEstadoEstudiante;

    -- Control de diagnóstico
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        -- Paso 3: Validación obligatoria de idGrupo
        IF @estadoResultado = 1 AND (@idGrupoDefecto IS NULL OR @idGrupoDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 4: Consulta optimizada de alumnos del grupo con cálculo acumulado de inasistencias
        ;WITH ResumenInasistencias AS (
            SELECT
                a.idEstudianteGrupo,
                totalFallas = COUNT(CASE WHEN da.asistio = 0 AND da.codigoRazonCausa = 'SJC' THEN 1 END),
                totalJustificadas = COUNT(CASE WHEN da.codigoRazonCausa = 'EX' THEN 1 END),
                totalAsistencias = COUNT(CASE WHEN da.asistio = 1 THEN 1 END),
                totalRegistrosAsistencia = COUNT(da.id)
            FROM dbo.uv_asistencia a
            INNER JOIN dbo.uv_detalle_asistencia da ON a.id = da.idAsistencia
            GROUP BY a.idEstudianteGrupo
        )
        SELECT
            eg.id                               AS idEstudianteGrupo,
            eg.idEstudiante                     AS idEstudiante,
            u.id                                AS idUsuario,
            u.idTipoIdentificacion              AS tipoIdentificacionId,
            u.numeroIdentificacion              AS numeroIdentificacion,
            u.primerApellido                    AS primerApellido,
            u.segundoApellido                   AS segundoApellido,
            u.primerNombre                      AS primerNombre,
            u.segundoNombre                     AS segundoNombre,
            u.nombreCompleto                    AS nombreCompleto,
            u.correo                            AS correo,
            eg.idEstadoEstudiante               AS idEstadoEstudiante,
            eg.codigoEstadoEstudiante           AS codigoEstadoEstudiante,
            eg.nombreEstadoEstudiante           AS nombreEstadoEstudiante,
            u.estaActivoUsuario                 AS estaActivoUsuario,
            IIF(ri.totalFallas IS NULL, 0, ri.totalFallas)                     AS totalFallas,
            IIF(ri.totalJustificadas IS NULL, 0, ri.totalJustificadas)         AS totalJustificadas,
            IIF(ri.totalAsistencias IS NULL, 0, ri.totalAsistencias)           AS totalAsistencias,
            IIF(ri.totalRegistrosAsistencia IS NULL, 0, ri.totalRegistrosAsistencia) AS totalRegistrosAsistencia,
            COUNT(1) OVER()                     AS totalRegistros
        FROM dbo.uv_estudiante_grupo eg
        INNER JOIN dbo.uv_estudiante_identidad ei ON eg.idEstudiante = ei.id
        INNER JOIN dbo.uv_usuario u ON ei.idUsuario = u.id
        LEFT JOIN ResumenInasistencias ri ON eg.id = ri.idEstudianteGrupo
        WHERE eg.idGrupo = @idGrupoDefecto
          AND (@filtroEstadoId IS NULL OR eg.idEstadoEstudiante = @filtroEstadoId)
          AND (
              @filtroTextoNormalizado IS NULL
              OR u.numeroIdentificacion LIKE @filtroTextoNormalizado
              OR u.nombreCompleto LIKE @filtroTextoNormalizado
              OR u.correo LIKE @filtroTextoNormalizado
          )
        ORDER BY u.primerApellido ASC, u.primerNombre ASC, u.numeroIdentificacion ASC, eg.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO


-- ===== schema/stored-procedures/usp_consultar_estudiantes_paginado.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_estudiantes_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Búsqueda, filtrado y paginación determinística de estudiantes consumiendo
--   las vistas base uv_estudiante_identidad y uv_usuario.
--   Aplica filtros opcionales por tipo de documento, número de identificación,
--   texto (nombre/correo), idPrograma, idGrupo y estado activo.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_estudiantes_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idTipoIdentificacion    UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion    NVARCHAR(50)     = NULL,
    @filtroTexto             NVARCHAR(100)    = NULL,
    @idPrograma              UNIQUEIDENTIFIER = NULL,
    @idGrupo                 UNIQUEIDENTIFIER = NULL,
    @estaActivo              BIT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones y normalizaciones previas obligatorias (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Normalización de paginación (mínimo 1, máximo 100 por seguridad)
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Normalización defensiva de filtros de texto (mitigación de parameter sniffing)
    DECLARE @filtroDocNormalizado NVARCHAR(50) = IIF(TRIM(@numeroIdentificacion) IS NULL OR TRIM(@numeroIdentificacion) = '', NULL, TRIM(@numeroIdentificacion));
    DECLARE @filtroTextoNormalizado NVARCHAR(102) = IIF(TRIM(@filtroTexto) IS NULL OR TRIM(@filtroTexto) = '', NULL, CONCAT('%', TRIM(@filtroTexto), '%'));
    DECLARE @filtroTipoId UNIQUEIDENTIFIER = @idTipoIdentificacion;
    DECLARE @filtroProgId UNIQUEIDENTIFIER = @idPrograma;
    DECLARE @filtroGrupId UNIQUEIDENTIFIER = @idGrupo;
    DECLARE @filtroActivo BIT = @estaActivo;

    -- Control de diagnóstico
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 3: Consulta optimizada de estudiantes sobre vistas base
        SELECT
            e.id                    AS id,
            u.id                    AS idUsuario,
            u.idTipoIdentificacion  AS tipoIdentificacionId,
            u.numeroIdentificacion  AS numeroIdentificacion,
            u.primerApellido        AS primerApellido,
            u.segundoApellido       AS segundoApellido,
            u.primerNombre          AS primerNombre,
            u.segundoNombre         AS segundoNombre,
            u.nombreCompleto        AS nombreCompleto,
            u.correo                AS correo,
            u.estaActivoUsuario     AS estaActivoUsuario,
            COUNT(1) OVER()         AS totalRegistros
        FROM dbo.uv_estudiante_identidad e
        INNER JOIN dbo.uv_usuario u ON e.idUsuario = u.id
        WHERE
            (@filtroTipoId IS NULL OR u.idTipoIdentificacion = @filtroTipoId)
            AND (@filtroDocNormalizado IS NULL OR u.numeroIdentificacion = @filtroDocNormalizado)
            AND (@filtroActivo IS NULL OR u.estaActivoUsuario = @filtroActivo)
            AND (
                @filtroTextoNormalizado IS NULL
                OR u.nombreCompleto LIKE @filtroTextoNormalizado
                OR u.correo LIKE @filtroTextoNormalizado
            )
            AND (
                @filtroGrupId IS NULL
                OR EXISTS (
                    SELECT 1 
                    FROM dbo.uv_estudiante_grupo eg 
                    WHERE eg.idEstudiante = e.id 
                      AND eg.idGrupo = @filtroGrupId
                )
            )
            AND (
                @filtroProgId IS NULL
                OR EXISTS (
                    SELECT 1 
                    FROM dbo.uv_estudiante ve 
                    WHERE ve.id = e.id 
                      AND ve.idPrograma = @filtroProgId
                )
            )
        ORDER BY u.primerApellido ASC, u.primerNombre ASC, u.numeroIdentificacion ASC, e.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO


-- ===== schema/stored-procedures/usp_consultar_facultades_paginado.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_facultades_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Catálogo paginado de facultades institucionales consumiendo uv_facultad.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_facultades_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @filtroTexto             NVARCHAR(100)    = NULL,
    @estaActivo              BIT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginación normalizada
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroTextoNormalizado NVARCHAR(102) = IIF(TRIM(@filtroTexto) IS NULL OR TRIM(@filtroTexto) = '', NULL, CONCAT('%', TRIM(@filtroTexto), '%'));
    DECLARE @filtroActivo BIT = @estaActivo;

    -- Control de diagnóstico
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 3: Consulta optimizada de facultades
        SELECT
            f.id,
            f.nombreFacultad,
            f.idInstitucion,
            f.nombreInstitucion,
            f.idDecano,
            f.nombreCompletoDecano,
            f.estaActivaFacultad,
            COUNT(1) OVER() AS totalRegistros
        FROM dbo.uv_facultad f
        WHERE (@filtroActivo IS NULL OR f.estaActivaFacultad = @filtroActivo)
          AND (
              @filtroTextoNormalizado IS NULL
              OR f.nombreFacultad LIKE @filtroTextoNormalizado
              OR f.nombreCompletoDecano LIKE @filtroTextoNormalizado
          )
        ORDER BY f.nombreFacultad ASC, f.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO


-- ===== schema/stored-procedures/usp_consultar_programas_paginado.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_programas_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Catálogo paginado de programas académicos institucionales consumiendo uv_programa.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_programas_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @filtroTexto             NVARCHAR(100)    = NULL,
    @estaActivo              BIT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginación normalizada
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroFacId UNIQUEIDENTIFIER = @idFacultad;
    DECLARE @filtroTextoNormalizado NVARCHAR(102) = IIF(TRIM(@filtroTexto) IS NULL OR TRIM(@filtroTexto) = '', NULL, CONCAT('%', TRIM(@filtroTexto), '%'));
    DECLARE @filtroActivo BIT = @estaActivo;

    -- Control de diagnóstico
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 3: Consulta optimizada de programas
        SELECT
            pr.id,
            pr.nombrePrograma,
            pr.idFacultad,
            pr.nombreFacultad,
            pr.idInstitucion,
            pr.nombreInstitucion,
            pr.idCoordinador,
            pr.nombreCoordinador,
            pr.estaActivoPrograma,
            COUNT(1) OVER() AS totalRegistros
        FROM dbo.uv_programa pr
        WHERE (@filtroFacId IS NULL OR pr.idFacultad = @filtroFacId)
          AND (@filtroActivo IS NULL OR pr.estaActivoPrograma = @filtroActivo)
          AND (
              @filtroTextoNormalizado IS NULL
              OR pr.nombrePrograma LIKE @filtroTextoNormalizado
              OR pr.nombreCoordinador LIKE @filtroTextoNormalizado
          )
        ORDER BY pr.nombrePrograma ASC, pr.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO


-- ===== schema/stored-procedures/usp_consultar_solicitudes_revision_asistencia_paginado.sql =====
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_revision_asistencia_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Bandeja institucional de solicitudes de justificación y revisión de asistencia
--   consumiendo uv_solicitud_revision_asistencia, uv_asistencia, uv_sesion,
--   uv_estudiante_grupo, uv_estudiante_identidad y uv_usuario.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_revision_asistencia_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER = NULL,
    @idEstudiante            UNIQUEIDENTIFIER = NULL,
    @idEstado                UNIQUEIDENTIFIER = NULL,
    @fechaDesde              DATE             = NULL,
    @fechaHasta              DATE             = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Normalización de paginación
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroGrupoId UNIQUEIDENTIFIER = @idGrupo;
    DECLARE @filtroEstudianteId UNIQUEIDENTIFIER = @idEstudiante;
    DECLARE @filtroEstadoId UNIQUEIDENTIFIER = @idEstado;
    DECLARE @filtroFechaDesde DATE = @fechaDesde;
    DECLARE @filtroFechaHasta DATE = @fechaHasta;

    -- Control de diagnóstico
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 3: Consulta sobre vistas base sin manipulación de SESSION_CONTEXT
        SELECT
            sr.id                       AS idSolicitud,
            sr.nombre                   AS radicadoSolicitud,
            sr.fecha                    AS fechaRadicacion,
            sr.idEstado                 AS idEstado,
            sr.nombreEstado             AS nombreEstado,
            sr.justificacionSolicitud   AS justificacionSolicitud,
            sr.justificacionRespuesta   AS justificacionRespuesta,
            asi.id                      AS idAsistencia,
            se.id                       AS idSesion,
            se.nombre                   AS nombreSesion,
            se.codigo                   AS codigoSesion,
            se.idGrupo                  AS idGrupo,
            eg.id                       AS idEstudianteGrupo,
            ei.id                       AS idEstudiante,
            u.id                        AS idUsuario,
            u.numeroIdentificacion      AS numeroIdentificacion,
            u.nombreCompleto            AS nombreCompletoEstudiante,
            u.correo                    AS correoEstudiante,
            COUNT(1) OVER()             AS totalRegistros
        FROM dbo.uv_solicitud_revision_asistencia sr
        INNER JOIN dbo.uv_asistencia asi ON sr.idAsistencia = asi.id
        INNER JOIN dbo.uv_sesion se ON asi.idSesion = se.id
        INNER JOIN dbo.uv_estudiante_grupo eg ON asi.idEstudianteGrupo = eg.id
        INNER JOIN dbo.uv_estudiante_identidad ei ON eg.idEstudiante = ei.id
        INNER JOIN dbo.uv_usuario u ON ei.idUsuario = u.id
        WHERE (@filtroGrupoId IS NULL OR se.idGrupo = @filtroGrupoId)
          AND (@filtroEstudianteId IS NULL OR ei.id = @filtroEstudianteId)
          AND (@filtroEstadoId IS NULL OR sr.idEstado = @filtroEstadoId)
          AND (@filtroFechaDesde IS NULL OR sr.fecha >= @filtroFechaDesde)
          AND (@filtroFechaHasta IS NULL OR sr.fecha <= @filtroFechaHasta)
        ORDER BY sr.fecha DESC, sr.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO

