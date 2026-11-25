USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU092: actualiza solo los nombres/apellidos de un usuario (los parametros NULL no se tocan). No modifica correo,
-- documento, contrasena ni estado. Las fachadas publicas aportan RBAC, titularidad, validacion y transaccion.
-- SKILLS-BD lote 2 (2026-11-25): triplete OUTPUT, PASO n y TRY/CATCH con SYS_001 (si condeno la transaccion del llamador, relanza
-- el error original). @idCorrelacion es opcional para no obligar a cambiar la llamada de pruebas antiguas.
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_nombres_usuario_interno]
(
    @idUsuario               UNIQUEIDENTIFIER,
    @primerNombre            NVARCHAR(50) = NULL,
    @segundoNombre           NVARCHAR(50) = NULL,
    @primerApellido          NVARCHAR(50) = NULL,
    @segundoApellido         NVARCHAR(50) = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER = NULL,
    @mensajeUsuarioResultado NVARCHAR(4000) = NULL OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) = NULL OUTPUT,
    @estadoResultado         BIT = NULL OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: respuesta inicial
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        -- PASO 2: solo cambian los nombres y apellidos que llegan
        UPDATE dbo.Usuario
        SET primerNombre    = IIF(@primerNombre    IS NULL, primerNombre,    @primerNombre),
            segundoNombre   = IIF(@segundoNombre   IS NULL, segundoNombre,   @segundoNombre),
            primerApellido  = IIF(@primerApellido  IS NULL, primerApellido,  @primerApellido),
            segundoApellido = IIF(@segundoApellido IS NULL, segundoApellido, @segundoApellido)
        WHERE id = @idUsuario;
    END TRY
    BEGIN CATCH
        -- PASO 3: error. Sin transaccion propia: la revierte el llamador
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        -- Transaccion del llamador condenada: se relanza el error original a su CATCH (mismo comportamiento que antes del lote 2)
        IF XACT_STATE() = -1
        BEGIN
            THROW;
        END
    END CATCH
END;
GO
