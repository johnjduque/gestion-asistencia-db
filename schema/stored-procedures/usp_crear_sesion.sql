USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_sesion]
(
    @idGrupo            UNIQUEIDENTIFIER,
    @idDocente          UNIQUEIDENTIFIER,
    @nombre             NVARCHAR(50),
    @descripcion        NVARCHAR(250),
    @fechaHoraInicio    DATETIME2,
    @fechaHoraFin       DATETIME2,
    @aula               NVARCHAR(50),
    @tipo               NVARCHAR(50),
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto        NVARCHAR(50)     = TRIM(@nombre);
    DECLARE @descripcionDefecto   NVARCHAR(250)    = NULLIF(TRIM(@descripcion), '');
    DECLARE @aulaDefecto          NVARCHAR(50)     = NULLIF(TRIM(@aula), '');
    DECLARE @tipoDefecto          NVARCHAR(50)     = NULLIF(TRIM(@tipo), '');

    DECLARE @idNuevoSesion   UNIQUEIDENTIFIER = NEWID();
    DECLARE @numeroSiguiente INT = 1;
    DECLARE @codigoSesion    NVARCHAR(50);

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de presencia del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validación de pertenencia del grupo al docente titular mediante procedimiento interno
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_para_docente_interno
                @idGrupo = @idGrupoDefecto,
                @idDocente = @idDocenteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Cálculo reactivo de correlativo de sesión e inserción
        IF @estadoResultado = 1
        BEGIN
            SELECT @numeroSiguiente = ISNULL(COUNT(1), 0) + 1
            FROM [dbo].[uv_sesion]
            WHERE idGrupo = @idGrupoDefecto;

            SET @codigoSesion = CONCAT('SES-', RIGHT('00' + CAST(@numeroSiguiente AS VARCHAR(5)), 2));

            INSERT INTO dbo.Sesion (
                id, nombre, numero, codigo, numeroSemana, grupo,
                fechaHoraInicio, fechaHoraFin, descripcion, aula, tipo
            )
            VALUES (
                @idNuevoSesion,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Sesión #', @numeroSiguiente) END,
                @numeroSiguiente,
                @codigoSesion,
                @numeroSiguiente,
                @idGrupoDefecto,
                CASE WHEN @fechaHoraInicio IS NOT NULL THEN @fechaHoraInicio ELSE CURRENT_TIMESTAMP END,
                CASE WHEN @fechaHoraFin IS NOT NULL THEN @fechaHoraFin ELSE DATEADD(HOUR, 2, CURRENT_TIMESTAMP) END,
                @descripcionDefecto,
                @aulaDefecto,
                @tipoDefecto
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
