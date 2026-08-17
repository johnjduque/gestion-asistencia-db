USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_asistencias_sesion]
(
    @idSesion       UNIQUEIDENTIFIER,
    @asistenciaJSON NVARCHAR(MAX),
    @idCorrelacion  UNIQUEIDENTIFIER
)
AS
    -- 1. Estandarización e inicialización de variables locales utilizando catálogo de parámetros (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @totalEstudiantes     INT = 0;
    DECLARE @iterador             INT = 1;
    DECLARE @idEstudianteActual   UNIQUEIDENTIFIER;
    DECLARE @estadoActual         NVARCHAR(5);

    -- Tabla temporal en memoria para iterar el JSON de asistencias
    DECLARE @EstudiantesATrabajar TABLE (
        secuencia    INT IDENTITY(1,1),
        idEstudiante UNIQUEIDENTIFIER,
        estado       NVARCHAR(5)
    );

    -- Inicialización interna de variables de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación de presencia del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validación de existencia de la sesión de clase
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Carga, desglose iterativo y sincronización de asistencias recibidas en formato JSON
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO @EstudiantesATrabajar (idEstudiante, estado)
            SELECT idEstudiante, estado
            FROM OPENJSON(@asistenciaJSON)
            WITH (
                idEstudiante UNIQUEIDENTIFIER '$.idEstudiante',
                estado       NVARCHAR(5)      '$.estado'
            );

            SELECT @totalEstudiantes = COUNT(1) FROM @EstudiantesATrabajar;
            SET @iterador = 1;

            BEGIN TRANSACTION;

            WHILE @iterador <= @totalEstudiantes AND @estadoResultado = 1
            BEGIN
                SELECT 
                    @idEstudianteActual = idEstudiante,
                    @estadoActual       = estado
                FROM @EstudiantesATrabajar
                WHERE secuencia = @iterador;

                -- Validación de pertenencia activa del estudiante al grupo de la sesión
                EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                    @idEstudiante = @idEstudianteActual,
                    @idSesion = @idSesionDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                -- Sincronización de asistencia individual por estudiante
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

                SET @iterador = @iterador + 1;
            END

            -- Control transaccional de cierre del bloque de asistencias
            IF @estadoResultado = 1
            BEGIN
                COMMIT TRANSACTION;
            END
            ELSE
            BEGIN
                IF @@TRANCOUNT > 0
                    ROLLBACK TRANSACTION;
            END
        END

        -- PASO 4: Evaluación de resultado final y generación de mensaje de éxito desde el Catálogo de Mensajes
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'BloqueAsistenciasSesion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones y reversión de transacción activa
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados garantizando el nombre de columna idCorrelacion
    SELECT 
        idCorrelacion = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END;
GO
