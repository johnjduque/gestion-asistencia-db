USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_sesion_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @descripcion             NVARCHAR(250),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @aula                    NVARCHAR(50),
    @tipo                    NVARCHAR(50),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto        NVARCHAR(50)     = TRIM(@nombre);
    DECLARE @descripcionDefecto   NVARCHAR(250)    = TRIM(@descripcion);
    DECLARE @aulaDefecto          NVARCHAR(50)     = TRIM(@aula);
    DECLARE @tipoDefecto          NVARCHAR(50)     = TRIM(@tipo);

    DECLARE @numeroSiguiente INT = 1;
    DECLARE @codigoSesion    NVARCHAR(50);

BEGIN
    SET NOCOUNT ON;
    SET @estadoResultado = 1;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');

    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validar existencia del grupo
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Inserción de la sesión
        IF @estadoResultado = 1
        BEGIN
            SELECT @numeroSiguiente = ISNULL(COUNT(1), 0) + 1
            FROM dbo.Sesion
            WHERE grupo = @idGrupoDefecto;

            SET @codigoSesion = CONCAT('SES-', RIGHT('00' + CAST(@numeroSiguiente AS VARCHAR(5)), 2));

            INSERT INTO dbo.Sesion (
                id, nombre, numero, codigo, numeroSemana, grupo,
                fechaHoraInicio, fechaHoraFin, aula, tipo, descripcion, cerrada
            )
            VALUES (
                @idSesionDefecto,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Sesión #', @numeroSiguiente) END,
                @numeroSiguiente,
                @codigoSesion,
                @numeroSiguiente,
                @idGrupoDefecto,
                CASE WHEN @fechaHoraInicio IS NOT NULL THEN @fechaHoraInicio ELSE CURRENT_TIMESTAMP END,
                CASE WHEN @fechaHoraFin IS NOT NULL THEN @fechaHoraFin ELSE DATEADD(HOUR, 2, CURRENT_TIMESTAMP) END,
                CASE WHEN @aulaDefecto IS NOT NULL AND @aulaDefecto <> '' THEN @aulaDefecto ELSE 'Aula Principal' END,
                CASE WHEN @tipoDefecto IS NOT NULL AND @tipoDefecto <> '' THEN @tipoDefecto ELSE 'REGULAR' END,
                CASE WHEN @descripcionDefecto IS NOT NULL AND @descripcionDefecto <> '' THEN @descripcionDefecto ELSE 'Control de Asistencia' END,
                0
            );

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Sesion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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
