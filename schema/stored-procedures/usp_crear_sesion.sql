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
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idSesionResultado  UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- Inicialización de variables locales
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @docenteAsignado UNIQUEIDENTIFIER;
    DECLARE @numeroSiguiente INT = 1;
    DECLARE @codigoSesion    NVARCHAR(50);
    DECLARE @nuevoIdSesion   UNIQUEIDENTIFIER = NEWID();

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

        -- PASO 2: Validación de existencia del grupo
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validación de pertenencia del grupo al docente (Regla de Ámbito)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @docenteAsignado = docente
            FROM dbo.Grupo
            WHERE id = @idGrupoDefecto;

            IF @docenteAsignado IS NULL OR @docenteAsignado <> @idDocenteDefecto
            BEGIN
                SET @estadoResultado = 0;
                SET @mensajeUsuarioResultado = 'Acceso denegado: El docente no tiene asignado este grupo académico.';
                SET @mensajeTecnicoResultado = CONCAT('Violacion de ambito: el docente ', CAST(@idDocenteDefecto AS VARCHAR(50)), ' no es titular del grupo ', CAST(@idGrupoDefecto AS VARCHAR(50)));
            END
        END

        -- PASO 4: Inserción de la sesión
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
                @nuevoIdSesion,
                ISNULL(@nombre, CONCAT('Sesión #', @numeroSiguiente)),
                @numeroSiguiente,
                @codigoSesion,
                @numeroSiguiente,
                @idGrupoDefecto,
                ISNULL(@fechaHoraInicio, CURRENT_TIMESTAMP),
                ISNULL(@fechaHoraFin, DATEADD(HOUR, 2, CURRENT_TIMESTAMP)),
                ISNULL(@aula, 'Aula Principal'),
                ISNULL(@tipo, 'REGULAR'),
                ISNULL(@descripcion, 'Control de Asistencia'),
                0
            );

            SET @idSesionResultado = @nuevoIdSesion;
            SET @mensajeUsuarioResultado = 'Sesión de clase programada exitosamente.';
            SET @mensajeTecnicoResultado = 'Sesion insertada correctamente en dbo.Sesion.';
        END

    END TRY
    BEGIN CATCH
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Ocurrió un error al intentar crear la sesión de clase.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    -- Devolución de resultado en SELECT para compatibilidad directa con llamadas JDBC
    SELECT 
        @nuevoIdSesion AS idSesion,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
