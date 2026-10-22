USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_crear_programa_academico]
-- Historia de Usuario: HU076 (Agregar nuevo programa académico a la facultad)
-- Ámbito: Decano de Facultad (Nivel 2 de custodia jerárquica)
-- Estándar: Conforme a procedimientos-externos-condiciones, consulta-a-bd y AGENTS.md
-- Salida Canónica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_programa_academico]
(
    @idPrograma              UNIQUEIDENTIFIER = NULL,
    @codigo                  INT              = NULL,
    @nombre                  NVARCHAR(100)    = NULL,
    @idCoordinador           UNIQUEIDENTIFIER = NULL,
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @idTipoPrograma          UNIQUEIDENTIFIER = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idCoordinadorDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCoordinador, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idFacultadDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idFacultad, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTipoProgramaDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idTipoPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDef                NVARCHAR(100)    = TRIM(@nombre);

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

        -- PASO 1.5: Validación de presencia del ejecutor y perfil RBAC (Fail-Closed)
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

        -- PASO 2: Validaciones de Negocio e Integridad Referencial desde Vistas Canónicas (uv_*)
        -- 2.1 Validación de Nombre Obligatorio, Longitud (3 a 50 caracteres) y sin dígitos numéricos
        IF @estadoResultado = 1 AND (@nombreDef IS NULL OR LEN(@nombreDef) < 3 OR LEN(@nombreDef) > 50)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Nombre de Programa Academico',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Longitud invalida (3-50). Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@nombreDef LIKE '%[0-9]%')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Nombre de Programa Academico no debe contener numeros',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeUsuarioResultado = 'El nombre del programa academico solo debe contener letras y espacios, no debe incluir numeros.';
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Nombre contiene digitos numericos. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 2.2 Validación de Facultad Obligatoria e Integridad Referencial (uv_facultad)
        IF @estadoResultado = 1 AND (@idFacultadDefecto IS NULL OR @idFacultadDefecto = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Facultad',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Facultad obligatoria. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE id = @idFacultadDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Facultad',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Facultad inexistente. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 2.3 Validación de Titularidad Jerárquica sobre la Facultad
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idFacultadDefecto,
                @tipoEntidadPadre = 'FACULTAD',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 2.4 Validación de Tipo de Programa Obligatorio e Integridad Referencial (uv_tipo_programa)
        IF @estadoResultado = 1 AND (@idTipoProgramaDefecto IS NULL OR @idTipoProgramaDefecto = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Tipo de Programa',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Tipo de programa obligatorio. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_programa WHERE id = @idTipoProgramaDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Tipo de Programa',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Tipo de programa inexistente. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 2.5 Validación de Coordinador Obligatorio e Integridad Referencial (uv_coordinador_identidad)
        IF @estadoResultado = 1 AND (@idCoordinadorDefecto IS NULL OR @idCoordinadorDefecto = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'Coordinador',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Coordinador obligatorio. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador_identidad WHERE id = @idCoordinadorDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Coordinador',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Coordinador inexistente. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 2.6 Validación de Unicidad de Nombre (Consumo de uv_programa, permitiendo actualización idempotente del mismo @idPrograma)
        IF @estadoResultado = 1 AND EXISTS (SELECT 1 FROM dbo.uv_programa WHERE LOWER(nombrePrograma) = LOWER(@nombreDef) AND id <> @idProgramaDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003',
                @p_param1 = 'Programa Academico',
                @p_param2 = 'nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeUsuarioResultado = CONCAT('Ya existe un programa academico registrado con el nombre ''', @nombreDef, ''' en la facultad.');
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Conflicto de unicidad para nombre: ', @nombreDef, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Delegación al procedimiento interno de persistencia (*_interno)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_crear_programa_academico_interno
                @idPrograma = @idProgramaDefecto,
                @nombre = @nombreDef,
                @idCoordinador = @idCoordinadorDefecto,
                @idFacultad = @idFacultadDefecto,
                @idTipoPrograma = @idTipoProgramaDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
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

    -- BLOQUE FINAL: Retorno unificado de resultados (4 columnas canónicas)
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
