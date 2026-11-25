USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_contacto_notificacion_interno]
-- Capacidad: Resolucion de Contacto para Notificaciones (NOTIF-002A)
-- Ambito: Consulta interna atomica por lote acotado (<=100 UUID) sobre Usuario
--         habilitado (estado = 1). Excepcion a paginacion documentada en CONTRACT §2.3.
-- SKILLS-BD lote 2 (2026-11-25): lectura por uv_usuario, PASO n, triplete OUTPUT (opcional: el llamador valida antes y
-- la invoca como segundo resultset) y TRY/CATCH con SYS_001. Devuelve las filas de contacto (READ_QUERY_RESULTSET).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_contacto_notificacion_interno]
(
    @usuariosJson            NVARCHAR(MAX),
    @idCorrelacion           UNIQUEIDENTIFIER = NULL,
    @mensajeUsuarioResultado NVARCHAR(4000) = NULL OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) = NULL OUTPUT,
    @estadoResultado         BIT = NULL OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: respuesta inicial
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        -- PASO 2: contactos de los usuarios activos solicitados (UUID validos, sin repetir)
        ;WITH Solicitados AS (
            SELECT DISTINCT
                idUsuario = TRY_CONVERT(UNIQUEIDENTIFIER, j.[value])
            FROM OPENJSON(@usuariosJson) j
            WHERE TRY_CONVERT(UNIQUEIDENTIFIER, j.[value]) IS NOT NULL
        )
        SELECT
            idUsuario        = u.id,
            correo           = u.correo,
            correoConfirmado = u.correoConfirmado
        FROM dbo.uv_usuario u
        INNER JOIN Solicitados s ON s.idUsuario = u.id
        WHERE u.estaActivoUsuario = 1
        ORDER BY u.id ASC;
    END TRY
    BEGIN CATCH
        -- PASO 3: error no controlado (SYS_001)
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
