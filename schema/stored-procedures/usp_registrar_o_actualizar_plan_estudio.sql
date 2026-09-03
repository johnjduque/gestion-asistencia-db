USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_o_actualizar_plan_estudio]
(
    @idPlanEstudio UNIQUEIDENTIFIER,
    @idPrograma    UNIQUEIDENTIFIER,
    @codigo        NVARCHAR(50),
    @nombre        NVARCHAR(100),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idPlanEstudioDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPlanEstudio, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idProgramaDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @codigoDefecto       NVARCHAR(50)     = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@codigo, 'GENERAL', 'CADENA_VACIA')));
DECLARE @nombreDefecto       NVARCHAR(100)    = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@nombre, 'GENERAL', 'CADENA_VACIA')));

DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Validar presencia obligatoria de idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar existencia de Programa Académico activo vía Vista uv_programa
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_programa p WHERE p.id = @idProgramaDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Programa academico no encontrado. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3. FLUJO REACTIVO (UPSERT): Consultar existencia por ID o código en uv_plan_estudio
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.uv_plan_estudio pe WHERE pe.id = @idPlanEstudioDefecto OR pe.codigoPlanEstudio = @codigoDefecto)
            BEGIN
                -- SI EXISTE: Actualizar PlanEstudio
                UPDATE [dbo].[PlanEstudio]
                SET [programa] = @idProgramaDefecto,
                    [codigo]   = @codigoDefecto,
                    [nombre]   = @nombreDefecto
                WHERE [id] = @idPlanEstudioDefecto OR [codigo] = @codigoDefecto;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SUC_ACTUALIZACION_PLAN_ESTUDIO',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END
            ELSE
            BEGIN
                -- SI NO EXISTE: Crear nuevo PlanEstudio
                DECLARE @nuevoId UNIQUEIDENTIFIER = NEWID();

                INSERT INTO [dbo].[PlanEstudio] ([id], [programa], [codigo], [nombre], [estado])
                VALUES (@nuevoId, @idProgramaDefecto, @codigoDefecto, @nombreDefecto, 1);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SUC_REGISTRO_PLAN_ESTUDIO',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'ERR_INESPERADO_REGISTRO_PLAN_ESTUDIO',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL MANDATORIO: Retorno unificado de 4 columnas
    SELECT
        idCorrelacion = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END;
GO
