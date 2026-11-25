USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU159 (correccion de identidad de usuarios, 2026-11-05): registra en dbo.AuditoriaEvento una correccion de datos de
-- identidad con el motivo y los valores anteriores (instantanea tomada por la fachada antes de escribir) y nuevos
-- (ufn_obtener_identidad_usuario_json despues de escribir). Visible en la auditoria del administrador (HU172).
-- Sin transaccion propia (corre dentro de la fachada publica).
-- SKILLS-BD lote 2 (2026-11-25): triplete OUTPUT, PASO n y TRY/CATCH con SYS_001; si condeno la transaccion del llamador,
-- el CATCH relanza el error original a la fachada (como antes).
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_auditoria_identidad_interno]
(
    @idUsuario               UNIQUEIDENTIFIER,
    @identidadAnterior       NVARCHAR(MAX),
    @motivo                  NVARCHAR(500),
    @accion                  VARCHAR(120),
    @tipoRecurso             VARCHAR(120),
    @idRecurso               UNIQUEIDENTIFIER,
    @ruta                    NVARCHAR(240),
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
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
        -- PASO 2: evento de auditoria con la identidad anterior y la nueva
        INSERT INTO dbo.AuditoriaEvento (
            id, occurredAt, actorId, actorType, action,
            resourceType, resourceId, result, correlationId,
            httpMethod, path, httpStatus, metadata
        ) VALUES (
            NEWID(),
            SYSDATETIMEOFFSET(),
            CAST(@idUsuarioEjecutor AS NVARCHAR(120)),
            'USER',
            @accion,
            @tipoRecurso,
            CAST(@idRecurso AS NVARCHAR(120)),
            'SUCCESS',
            @idCorrelacion,
            'PUT',
            @ruta,
            200,
            (SELECT idUsuario = CAST(@idUsuario AS NVARCHAR(36)),
                    motivo = NULLIF(TRIM(@motivo), N''),
                    anterior = JSON_QUERY(@identidadAnterior),
                    nuevo = JSON_QUERY(dbo.ufn_obtener_identidad_usuario_json(@idUsuario))
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        );
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
