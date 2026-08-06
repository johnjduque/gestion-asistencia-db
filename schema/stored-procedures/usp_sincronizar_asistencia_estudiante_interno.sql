USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_sincronizar_asistencia_estudiante_interno]
(
    @idEstudiante UNIQUEIDENTIFIER,
    @idSesion UNIQUEIDENTIFIER,
    @codigoEstado NVARCHAR(5), -- 'A', 'F', 'T', 'J'
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS
BEGIN
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))));
    DECLARE @idEstudianteDefecto UNIQUEIDENTIFIER = ISNULL(@idEstudiante, '00000000-0000-0000-0000-000000000000');
    DECLARE @idSesionDefecto UNIQUEIDENTIFIER = ISNULL(@idSesion, '00000000-0000-0000-0000-000000000000');
    DECLARE @codigoEstadoDefecto NVARCHAR(5) = UPPER(LTRIM(RTRIM(ISNULL(@codigoEstado, 'A'))));

    SELECT 
        @mensajeUsuarioResultado = '', 
        @mensajeTecnicoResultado = '', 
        @estadoResultado = 1;

    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Validar ID de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 0
            RETURN;

        -- 2. Obtener el idGrupo y horas de la sesion para verificacion
        DECLARE @idGrupo UNIQUEIDENTIFIER;
        DECLARE @fechaInicioSesion DATETIME2;
        DECLARE @fechaFinSesion DATETIME2;

        SELECT TOP 1 
            @idGrupo = grupo,
            @fechaInicioSesion = fechaHoraInicio,
            @fechaFinSesion = fechaHoraFin
        FROM [dbo].[Sesion]
        WHERE id = @idSesionDefecto;

        IF @idGrupo IS NULL
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'La sesión de clase especificada no existe.',
                @mensajeTecnicoResultado = CONCAT('Fallo: No se encontró la sesión [', CAST(@idSesionDefecto AS NVARCHAR(50)), ']. Correlación: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
            RETURN;
        END

        -- 3. Obtener el idEstudianteGrupo
        DECLARE @idEstudianteGrupo UNIQUEIDENTIFIER;
        SELECT TOP 1 
            @idEstudianteGrupo = id
        FROM [dbo].[EstudianteGrupo]
        WHERE estudiante = @idEstudianteDefecto 
          AND grupo = @idGrupo;

        IF @idEstudianteGrupo IS NULL
        BEGIN
            SELECT 
                @mensajeUsuarioResultado = 'El estudiante no está inscrito en el grupo de esta sesión.',
                @mensajeTecnicoResultado = CONCAT('Fallo: No se encontró matrícula en EstudianteGrupo para Estudiante: ', @idEstudianteDefecto, ' Grupo: ', @idGrupo, '. Correlación: ', @idCorrelacionDefecto),
                @estadoResultado = 0;
            RETURN;
        END

        -- 4. Asegurar o resolver la existencia de la razón de asistencia en RazonCausa
        DECLARE @idRazonCausa UNIQUEIDENTIFIER;
        SELECT TOP 1 @idRazonCausa = id 
        FROM [dbo].[RazonCausa] 
        WHERE codigo = @codigoEstadoDefecto;

        IF @idRazonCausa IS NULL
        BEGIN
            SET @idRazonCausa = NEWID();
            DECLARE @nombreEstado NVARCHAR(50) = 
                CASE @codigoEstadoDefecto
                    WHEN 'A' THEN 'Asistió'
                    WHEN 'F' THEN 'Faltó'
                    WHEN 'T' THEN 'Tarde'
                    WHEN 'J' THEN 'Justificado'
                    ELSE 'Otro/Desconocido'
                END;

            INSERT INTO [dbo].[RazonCausa] (id, nombre, codigo)
            VALUES (@idRazonCausa, @nombreEstado, @codigoEstadoDefecto);
        END

        DECLARE @asistio BIT = CASE WHEN @codigoEstadoDefecto IN ('A', 'T') THEN 1 ELSE 0 END;

        -- 5. Sincronizar cabecera de Asistencia
        DECLARE @idAsistencia UNIQUEIDENTIFIER;
        SELECT TOP 1 @idAsistencia = id
        FROM [dbo].[Asistencia]
        WHERE estudianteGrupo = @idEstudianteGrupo 
          AND sesion = @idSesionDefecto;

        IF @idAsistencia IS NULL
        BEGIN
            SET @idAsistencia = NEWID();
            INSERT INTO [dbo].[Asistencia] (id, estudianteGrupo, sesion)
            VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
        END

        -- 6. Sincronizar detalle de Asistencia
        DECLARE @idDetalleAsistencia UNIQUEIDENTIFIER;
        SELECT TOP 1 @idDetalleAsistencia = id
        FROM [dbo].[DetalleAsistencia]
        WHERE asistencia = @idAsistencia;

        IF @idDetalleAsistencia IS NULL
        BEGIN
            DECLARE @nuevoCodigo INT = ISNULL((SELECT MAX(codigo) FROM [dbo].[DetalleAsistencia]), 0) + 1;
            SET @idDetalleAsistencia = NEWID();

            INSERT INTO [dbo].[DetalleAsistencia] (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
            VALUES (@idDetalleAsistencia, @nuevoCodigo, @idAsistencia, @asistio, @idRazonCausa, @fechaInicioSesion, @fechaFinSesion);
        END
        ELSE
        BEGIN
            UPDATE [dbo].[DetalleAsistencia]
            SET asistio = @asistio,
                razonCausa = @idRazonCausa,
                fechaHoraInicio = @fechaInicioSesion,
                fechaHoraFin = @fechaFinSesion
            WHERE id = @idDetalleAsistencia;
        END

        -- 7. Respuesta exitosa
        SELECT 
            @mensajeUsuarioResultado = 'Asistencia registrada con éxito.',
            @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Sincronización de asistencia completa. Asistencia ID: ', @idAsistencia, ', Estado: ', @codigoEstadoDefecto)),
            @estadoResultado = 1;

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Error al procesar el guardado de la asistencia.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en [usp_sincronizar_asistencia_estudiante_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO
