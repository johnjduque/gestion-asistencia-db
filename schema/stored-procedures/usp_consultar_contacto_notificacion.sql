USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_contacto_notificacion]
-- Capacidad: Resolucion de Contacto para Notificaciones (NOTIF-002A)
-- Ambito: Fachada publica tecnica para resolver correo y correoConfirmado de un
--         lote acotado (1..100 UUID) de usuarios habilitados en el momento de
--         la entrega. Excepcion RBAC y de paginacion documentada en CONTRACT §2.3.
-- Salida:
--   Result set 1 (canonico): (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
--   Result set 2 (cuando estadoResultado=1): (idUsuario, correo, correoConfirmado)
-- =============================================================================
-- SKILLS-BD lote 8 (2026-11-26): DECLARE en la cabecera (los de un paso se asignan con SET en ese paso) y PASO n. Mismo resultado.
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): notificaciones y correo: lo invoca el backend sin usuario con perfil; exige @idCorrelacion.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_contacto_notificacion]
(
    @usuariosJson  NVARCHAR(MAX)    = NULL,
    @idCorrelacion UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @jsonTrim             NVARCHAR(MAX)    = TRIM(@usuariosJson);
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @countElem INT;
    DECLARE @hayUuidInvalido BIT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validar @usuariosJson (arreglo JSON de 1..100 UUID validos)
        IF @estadoResultado = 1
        BEGIN
            IF @jsonTrim IS NULL OR @jsonTrim = N'' OR ISJSON(@jsonTrim) <> 1 OR LEFT(@jsonTrim, 1) <> '['
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'NTF_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' @usuariosJson no es un arreglo JSON valido. Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @countElem = 0;
                SET @hayUuidInvalido = 0;

                SELECT
                    @countElem = COUNT(*),
                    @hayUuidInvalido = MAX(CASE
                        WHEN j.[type] <> 1 THEN 1
                        WHEN j.[value] IS NULL OR TRY_CONVERT(UNIQUEIDENTIFIER, j.[value]) IS NULL THEN 1
                        ELSE 0
                    END)
                FROM OPENJSON(@jsonTrim) j;

                IF @countElem < 1 OR @countElem > 100 OR @hayUuidInvalido = 1
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'NTF_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' @usuariosJson debe contener entre 1 y 100 UUID validos. Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END

        -- PASO 3: Preparar mensaje de exito GEN_003
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003',
                @p_param1 = 'ContactoNotificacion',
                @p_param2 = 'Lote',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        END
    END TRY
    BEGIN CATCH
        -- PASO 4: responde SYS_001 en el triplete (comportamiento previo); sin resultset de contactos
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- Result set 1: tupla canonica
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;

    -- PASO 5: Result set 2, contactos cuando la validacion fue exitosa
    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_consultar_contacto_notificacion_interno
            @usuariosJson = @jsonTrim;
    END
END;
GO
