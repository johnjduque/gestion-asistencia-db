USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_horarios_grupo_interno]
(
    @idGrupo UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = UPPER(LTRIM(RTRIM(ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000'))));
    DECLARE @idGrupoDefecto UNIQUEIDENTIFIER = ISNULL(@idGrupo, '00000000-0000-0000-0000-000000000000');

    SELECT 
        @mensajeUsuarioResultado = '', 
        @mensajeTecnicoResultado = '', 
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[Horario] WHERE grupo = @idGrupoDefecto)
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'El grupo especificado no tiene horarios semanales configurados.',
                    @mensajeTecnicoResultado = CONCAT('Fallo: No se encontraron registros en Horario para Grupo [', CAST(@idGrupoDefecto AS NVARCHAR(50)), ']. Correlación: ', @idCorrelacionDefecto),
                    @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SELECT 
                    @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Operación exitosa completa. Grupo tiene horarios asignados: ', @idGrupoDefecto)),
                    @estadoResultado = 1;
            END
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Error al validar los horarios del grupo.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en [usp_validar_horarios_grupo_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO
