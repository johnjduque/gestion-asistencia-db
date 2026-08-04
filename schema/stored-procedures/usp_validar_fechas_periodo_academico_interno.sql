USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_fechas_periodo_academico_interno]
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
            DECLARE @idPeriodo UNIQUEIDENTIFIER;
            DECLARE @fechaInicio DATE;
            DECLARE @fechaFin DATE;

            -- 1. Obtener Periodo
            SELECT TOP 1 
                @idPeriodo = periodoAcademico
            FROM [dbo].[Grupo]
            WHERE id = @idGrupoDefecto;

            IF @idPeriodo IS NULL
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'No se encontró un periodo académico asociado al grupo.',
                    @mensajeTecnicoResultado = CONCAT('Fallo: No se pudo obtener el periodoAcademico del Grupo [', CAST(@idGrupoDefecto AS NVARCHAR(50)), ']. Correlación: ', @idCorrelacionDefecto),
                    @estadoResultado = 0;
                RETURN;
            END

            -- 2. Validar fechas en PeriodoAcademico
            SELECT TOP 1 
                @fechaInicio = fechaInicio,
                @fechaFin = fechaFin
            FROM [dbo].[PeriodoAcademico]
            WHERE id = @idPeriodo;

            IF @fechaInicio IS NULL OR @fechaFin IS NULL
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'Las fechas del periodo académico no están configuradas correctamente.',
                    @mensajeTecnicoResultado = CONCAT('Fallo: fechaInicio o fechaFin son NULL en PeriodoAcademico [', CAST(@idPeriodo AS NVARCHAR(50)), ']. Correlación: ', @idCorrelacionDefecto),
                    @estadoResultado = 0;
            END
            ELSE IF @fechaInicio >= @fechaFin
            BEGIN
                SELECT 
                    @mensajeUsuarioResultado = 'Las fechas del periodo académico son inconsistentes.',
                    @mensajeTecnicoResultado = CONCAT('Fallo: fechaInicio [', CAST(@fechaInicio AS NVARCHAR(50)), '] es mayor o igual a fechaFin [', CAST(@fechaFin AS NVARCHAR(50)), '] en PeriodoAcademico [', CAST(@idPeriodo AS NVARCHAR(50)), ']. Correlación: ', @idCorrelacionDefecto),
                    @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SELECT 
                    @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Operación exitosa completa. Fechas de PeriodoAcadémico validadas correctamente. Inicio: ', @fechaInicio, ' Fin: ', @fechaFin)),
                    @estadoResultado = 1;
            END
        END

    END TRY
    BEGIN CATCH
        SELECT 
            @mensajeUsuarioResultado = 'Error al validar las fechas del periodo académico.',
            @mensajeTecnicoResultado = CONCAT('Error crítico en [usp_validar_fechas_periodo_academico_interno]: ', ERROR_MESSAGE(), '. Línea: ', ERROR_LINE()),
            @estadoResultado = 0;
    END CATCH
END
GO
