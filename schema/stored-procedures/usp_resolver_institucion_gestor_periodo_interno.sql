USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU096/HU097/HU098: valida que el ejecutor pueda gestionar periodos academicos y resuelve la institucion sobre la
-- que actua. El periodo es unico para toda la institucion, por eso solo lo gestiona el ADMINISTRADOR de esa
-- institucion (dbo.Administrador.institucion); DECANO y COORDINADOR solo lo consultan. Sin institucion => PER_005.
-- SKILLS-BD lote 9 (2026-11-26): PASO n e institucion del administrador por uv_administrador (antes, las tablas). Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_institucion_gestor_periodo_interno]
(
    @idUsuario               UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idInstitucion           UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuario, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    SELECT
        @idInstitucion = NULL,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: El ejecutor debe tener perfil ADMINISTRADOR
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ADMINISTRADOR',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Institucion activa del administrador (PER_005 si no la hay)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idInstitucion = a.idInstitucion
            FROM dbo.uv_administrador a
            WHERE a.idUsuario = @idUsuarioDefecto AND a.estaActivaInstitucion = 1;

            IF @idInstitucion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PER_005',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
    END TRY
    BEGIN CATCH
        -- PASO 3: error del motor: triplete SYS_001 (comportamiento previo)
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
