USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_asistencias_sesion]
(
    @idSesion UNIQUEIDENTIFIER,
    @asistenciaJSON NVARCHAR(MAX),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
    DECLARE @idSesionDefecto UNIQUEIDENTIFIER = ISNULL(@idSesion, '00000000-0000-0000-0000-000000000000');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = '';
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = '';
    DECLARE @estadoResultado BIT = 1;

    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Validar ID de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar existencia de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 3. Cargar y procesar la lista en formato JSON de estudiantes y estados
        IF @estadoResultado = 1
        BEGIN
            -- Tabla temporal en memoria para iterar
            DECLARE @EstudiantesATrabajar TABLE (
                Secuencia INT IDENTITY(1,1),
                idEstudiante UNIQUEIDENTIFIER,
                estado NVARCHAR(5)
            );

            INSERT INTO @EstudiantesATrabajar (idEstudiante, estado)
            SELECT idEstudiante, estado
            FROM OPENJSON(@asistenciaJSON)
            WITH (
                idEstudiante UNIQUEIDENTIFIER '$.idEstudiante',
                estado NVARCHAR(5) '$.estado'
            );

            DECLARE @Total INT = (SELECT COUNT(1) FROM @EstudiantesATrabajar);
            DECLARE @Iterador INT = 1;

            DECLARE @idEstudianteActual UNIQUEIDENTIFIER;
            DECLARE @estadoActual NVARCHAR(5);

            -- Iniciamos transaccion para procesamiento en bloque
            BEGIN TRANSACTION;

            WHILE @Iterador <= @Total AND @estadoResultado = 1
            BEGIN
                SELECT 
                    @idEstudianteActual = idEstudiante,
                    @estadoActual = estado
                FROM @EstudiantesATrabajar
                WHERE Secuencia = @Iterador;

                -- Validar matricula del estudiante actual en el grupo de la sesion
                EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                    @idEstudiante = @idEstudianteActual,
                    @idSesion = @idSesionDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                -- Sincronizar asistencia individual
                IF @estadoResultado = 1
                BEGIN
                    EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
                        @idEstudiante = @idEstudianteActual,
                        @idSesion = @idSesionDefecto,
                        @codigoEstado = @estadoActual,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;
                END

                SET @Iterador = @Iterador + 1;
            END

            -- 4. Cerrar transaccion dependiendo de la validez de todo el bloque
            IF @estadoResultado = 1
            BEGIN
                COMMIT TRANSACTION;
                SELECT 
                    @mensajeUsuarioResultado = 'Las asistencias de la sesión se han registrado exitosamente.',
                    @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Registro masivo de asistencia completo para Sesión: ', @idSesionDefecto));
            END
            ELSE
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SELECT 
            @mensajeUsuarioResultado = 'Hubo un error inesperado al registrar el bloque de asistencias.',
            @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto),
            @estadoResultado = 0;
    END CATCH

    -- 5. Retornar resultado de la transaccion
    SELECT 
        id = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END
GO
