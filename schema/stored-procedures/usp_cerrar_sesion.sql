USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_cerrar_sesion]
(
    @idSesion           UNIQUEIDENTIFIER,
    @idDocente          UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @docenteTitular UNIQUEIDENTIFIER;
    DECLARE @estaCerrada    BIT;

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

        -- PASO 2: Validación de existencia de sesión
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validación de ámbito (el docente debe ser el titular del grupo de la sesión)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 
                @docenteTitular = g.docente,
                @estaCerrada = s.cerrada
            FROM dbo.Sesion s
            INNER JOIN dbo.Grupo g ON s.grupo = g.id
            WHERE s.id = @idSesionDefecto;

            IF @docenteTitular IS NULL OR @docenteTitular <> @idDocenteDefecto
            BEGIN
                SET @estadoResultado = 0;
                SET @mensajeUsuarioResultado = 'Acceso denegado: Solo el docente titular del grupo puede cerrar esta sesión.';
                SET @mensajeTecnicoResultado = CONCAT('Violacion de ambito: el docente ', CAST(@idDocenteDefecto AS VARCHAR(50)), ' no es titular de la sesion ', CAST(@idSesionDefecto AS VARCHAR(50)));
            END
            ELSE IF @estaCerrada = 1
            BEGIN
                SET @mensajeUsuarioResultado = 'La sesión ya se encontraba cerrada previamente.';
                SET @mensajeTecnicoResultado = 'Sesion previamente cerrada. Operacion idempotente.';
            END
        END

        -- PASO 4: Cierre efectivo de sesión
        IF @estadoResultado = 1 AND @estaCerrada = 0
        BEGIN
            UPDATE dbo.Sesion
            SET cerrada = 1
            WHERE id = @idSesionDefecto;

            SET @mensajeUsuarioResultado = 'Sesión cerrada y consolidada exitosamente.';
            SET @mensajeTecnicoResultado = 'Sesion cerrada en dbo.Sesion.';
        END

    END TRY
    BEGIN CATCH
        SET @estadoResultado = 0;
        SET @mensajeUsuarioResultado = 'Ocurrió un error al intentar cerrar la sesión.';
        SET @mensajeTecnicoResultado = ERROR_MESSAGE();
    END CATCH;

    SELECT 
        @idSesionDefecto AS idSesion,
        @estadoResultado AS exitoso,
        @mensajeUsuarioResultado AS mensajeUsuario,
        @mensajeTecnicoResultado AS mensajeTecnico;
END;
GO
