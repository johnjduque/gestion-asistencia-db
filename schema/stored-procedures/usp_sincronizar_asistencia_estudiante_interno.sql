USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_sincronizar_asistencia_estudiante_interno]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idSesion                UNIQUEIDENTIFIER,
    @codigoEstado            NVARCHAR(5),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto         UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoEstadoDefecto     NVARCHAR(5) = TRIM(dbo.ufn_obtener_parametro_texto(@codigoEstado, 'GENERAL', 'CADENA_VACIA'));

    DECLARE @idGrupo                 UNIQUEIDENTIFIER;
    DECLARE @fechaInicioSesion       DATETIME2;
    DECLARE @fechaFinSesion          DATETIME2;
    DECLARE @idEstudianteGrupo        UNIQUEIDENTIFIER;
    DECLARE @idRazonCausa            UNIQUEIDENTIFIER;
    DECLARE @nombreEstado            NVARCHAR(50);
    DECLARE @asistio                 BIT;
    DECLARE @idAsistencia            UNIQUEIDENTIFIER;
    DECLARE @idDetalleAsistencia     UNIQUEIDENTIFIER;
    DECLARE @nuevoCodigo             INT;

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

        -- PASO 2: Estandarización de código de estado por defecto
        IF @estadoResultado = 1 AND (@codigoEstadoDefecto IS NULL OR @codigoEstadoDefecto = '')
        BEGIN
            SET @codigoEstadoDefecto = 'A';
        END

        -- PASO 3: Verificación de la sesión de clase y obtención de franja horaria
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 
                @idGrupo = grupo,
                @fechaInicioSesion = fechaHoraInicio,
                @fechaFinSesion = fechaHoraFin
            FROM dbo.Sesion
            WHERE id = @idSesionDefecto;

            IF @idGrupo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_001',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Verificación de la matrícula del estudiante en el grupo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 
                @idEstudianteGrupo = id
            FROM dbo.EstudianteGrupo
            WHERE estudiante = @idEstudianteDefecto 
              AND grupo = @idGrupo;

            IF @idEstudianteGrupo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'EST_004',
                    @p_param1 = @idEstudianteDefecto,
                    @p_param2 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: Resolución de la razón de causa/asistencia en dbo.RazonCausa
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idRazonCausa = id 
            FROM dbo.RazonCausa 
            WHERE codigo = @codigoEstadoDefecto
               OR (@codigoEstadoDefecto = 'A' AND codigo = 'AN')
               OR (@codigoEstadoDefecto = 'F' AND codigo = 'SJC');

            IF @idRazonCausa IS NULL
            BEGIN
                SET @idRazonCausa = NEWID();
                SET @nombreEstado = 
                    CASE @codigoEstadoDefecto
                        WHEN 'A' THEN 'Asistió'
                        WHEN 'F' THEN 'Faltó'
                        WHEN 'T' THEN 'Tarde'
                        WHEN 'J' THEN 'Justificado'
                        ELSE 'Otro/Desconocido'
                    END;

                INSERT INTO dbo.RazonCausa (id, nombre, codigo)
                VALUES (@idRazonCausa, @nombreEstado, @codigoEstadoDefecto);
            END

            SET @asistio = CASE WHEN @codigoEstadoDefecto IN ('A', 'T', 'AN') THEN 1 ELSE 0 END;
        END

        -- PASO 6: Sincronización de cabecera y detalle de asistencia
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idAsistencia = id
            FROM dbo.Asistencia
            WHERE estudianteGrupo = @idEstudianteGrupo 
              AND sesion = @idSesionDefecto;

            IF @idAsistencia IS NULL
            BEGIN
                SET @idAsistencia = NEWID();
                INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
                VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
            END

            SELECT TOP 1 @idDetalleAsistencia = id
            FROM dbo.DetalleAsistencia
            WHERE asistencia = @idAsistencia;

            IF @idDetalleAsistencia IS NULL
            BEGIN
                SELECT @nuevoCodigo = dbo.ufn_obtener_parametro_int(MAX(codigo), 'GENERAL', 'ENTERO_CERO') + 1 FROM dbo.DetalleAsistencia;
                SET @idDetalleAsistencia = NEWID();

                INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
                VALUES (@idDetalleAsistencia, @nuevoCodigo, @idAsistencia, @asistio, @idRazonCausa, @fechaInicioSesion, @fechaFinSesion);
            END
            ELSE
            BEGIN
                UPDATE dbo.DetalleAsistencia
                SET asistio = @asistio,
                    razonCausa = @idRazonCausa,
                    fechaHoraInicio = @fechaInicioSesion,
                    fechaHoraFin = @fechaFinSesion
                WHERE id = @idDetalleAsistencia;
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Asistencia Estudiante',
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
