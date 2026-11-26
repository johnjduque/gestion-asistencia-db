USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_obtener_mensaje_catalogo
--
-- Resuelve un codigo del catalogo en el mensaje de usuario y el tecnico ("DBCODE=<codigo>|<detalle>"), con hasta tres
-- parametros de plantilla, y devuelve el tipo y la severidad. Un codigo sin texto configurado devuelve los textos de reserva
-- ("... no configurado para el codigo: <codigo>"), tipo SYSTEM_ERROR y severidad ALTO (usuario) o CRITICO (tecnico).
-- Lo llaman casi todos los SP, por eso su firma no cambia: los parametros @p_* se conservan (excepcion E8 de
-- docs/arquitectura/excepciones-skills-bd.md) y el triplete se completa con @estadoResultado OUTPUT opcional al final.
-- SKILLS-BD lote 3 (2026-11-25): DECLARE en la cabecera, sin ISNULL, PASO n, TRY/CATCH y @estadoResultado; mismos textos.
-- SKILLS-BD lote 16 (2026-11-26): un codigo NULL vuelve a resolverse sin leer CatalogoParametro (DBCODE=DESCONOCIDO aunque falte
-- GENERAL/CADENA_VACIA), como antes del lote 3.
-- ============================================================================
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): utilidad transversal sin ejecutor propio (la llaman otros SP).
CREATE OR ALTER PROCEDURE [dbo].[usp_obtener_mensaje_catalogo]
    @p_codigo                  VARCHAR(100),
    @p_param1                  NVARCHAR(500) = NULL,
    @p_param2                  NVARCHAR(500) = NULL,
    @p_param3                  NVARCHAR(500) = NULL,
    @mensajeUsuarioResultado   NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado   NVARCHAR(4000) OUTPUT,
    @tipoMensajeResultado      VARCHAR(50) = NULL OUTPUT,
    @severidadResultado        VARCHAR(20) = NULL OUTPUT,
    @estadoResultado           BIT = NULL OUTPUT
AS
    DECLARE @codigoLimpio    VARCHAR(100) = IIF(@p_codigo IS NULL, '', TRIM(@p_codigo));
    DECLARE @rawUsuario      NVARCHAR(4000) = NULL;
    DECLARE @rawTecnico      NVARCHAR(4000) = NULL;
    DECLARE @tipoUsr         VARCHAR(50) = NULL;
    DECLARE @sevUsr          VARCHAR(20) = NULL;
    DECLARE @tipoTec         VARCHAR(50) = NULL;
    DECLARE @sevTec          VARCHAR(20) = NULL;
    DECLARE @codigoResultado VARCHAR(100) = IIF(@codigoLimpio = '', 'DESCONOCIDO', @codigoLimpio);
    DECLARE @detalleTecnico  NVARCHAR(3900) = NULL;
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: respuesta inicial
    SET @estadoResultado = 1;

    BEGIN TRY
        -- PASO 2: textos del catalogo (solo vistas)
        SELECT
            @rawUsuario = contenido,
            @tipoUsr    = tipoMensaje,
            @sevUsr     = severidad
        FROM dbo.uv_mensaje_usuario
        WHERE codigo = @codigoLimpio;

        SELECT
            @rawTecnico = contenido,
            @tipoTec    = tipoMensaje,
            @sevTec     = severidad
        FROM dbo.uv_mensaje_tecnico
        WHERE codigo = @codigoLimpio;

        -- PASO 3: mensaje de usuario (texto de reserva si el codigo no esta configurado)
        IF @rawUsuario IS NULL
        BEGIN
            SET @mensajeUsuarioResultado = CONCAT('Mensaje de usuario no configurado para el código: ', @codigoLimpio);
            SET @tipoUsr = 'SYSTEM_ERROR';
            SET @sevUsr  = 'ALTO';
        END
        ELSE
        BEGIN
            SET @mensajeUsuarioResultado = dbo.ufn_reemplazar_plantilla_mensaje(@rawUsuario, @p_param1, @p_param2, @p_param3);
        END

        -- PASO 4: mensaje tecnico (texto de reserva si el codigo no esta configurado)
        IF @rawTecnico IS NULL
        BEGIN
            SET @detalleTecnico = CONCAT('Mensaje técnico no configurado para el código: ', @codigoResultado);
            SET @tipoTec = 'SYSTEM_ERROR';
            SET @sevTec  = 'CRITICO';
        END
        ELSE
        BEGIN
            SET @detalleTecnico = dbo.ufn_reemplazar_plantilla_mensaje(@rawTecnico, @p_param1, @p_param2, @p_param3);
        END

        SET @mensajeTecnicoResultado = CONCAT('DBCODE=', @codigoResultado, '|', @detalleTecnico);

        -- PASO 5: tipo y severidad sin nulos (primero los del mensaje de usuario, luego los del tecnico)
        SET @tipoMensajeResultado = @tipoUsr;
        IF @tipoMensajeResultado IS NULL
        BEGIN
            SET @tipoMensajeResultado = @tipoTec;
        END
        IF @tipoMensajeResultado IS NULL
        BEGIN
            SET @tipoMensajeResultado = 'BUSINESS_ERROR';
        END

        SET @severidadResultado = @sevUsr;
        IF @severidadResultado IS NULL
        BEGIN
            SET @severidadResultado = @sevTec;
        END
        IF @severidadResultado IS NULL
        BEGIN
            SET @severidadResultado = 'MEDIO';
        END
    END TRY
    BEGIN CATCH
        -- PASO 6: error. Este SP es el que resuelve SYS_001 para los demas, asi que no puede llamarse a si mismo:
        -- arma los textos de reserva con el detalle del error (excepcion E8).
        SET @mensajeUsuarioResultado = CONCAT('Mensaje de usuario no configurado para el código: ', @codigoLimpio);
        SET @mensajeTecnicoResultado = LEFT(CONCAT('DBCODE=SYS_001|', dbo.ufn_obtener_detalle_error(NULL)), 4000);
        SET @tipoMensajeResultado = 'SYSTEM_ERROR';
        SET @severidadResultado = 'CRITICO';
        SET @estadoResultado = 0;
        -- Transaccion del llamador condenada: se relanza el error original a su CATCH
        IF XACT_STATE() = -1
        BEGIN
            THROW;
        END
    END CATCH
END;
GO
