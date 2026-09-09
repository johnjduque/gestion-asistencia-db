USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_asignatura]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @codigo             NVARCHAR(50),
    @nombre             NVARCHAR(50),
    @creditos           INT,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @semestreNumero     INT,
    @nombreArea         NVARCHAR(100),
    @nombreComponente   NVARCHAR(100),
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPlanEstudioDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPlanEstudio, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDefecto        NVARCHAR(50)     = UPPER(TRIM(@codigo));
    DECLARE @nombreDefecto        NVARCHAR(50)     = TRIM(@nombre);
    DECLARE @nombreAreaDefecto    NVARCHAR(100)    = TRIM(@nombreArea);

    DECLARE @idAreaResolved       UNIQUEIDENTIFIER;
    DECLARE @idSemestreResolved   UNIQUEIDENTIFIER;
    DECLARE @idSpeResolved        UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Resolver Área si se especifica
        IF @estadoResultado = 1 AND @nombreAreaDefecto IS NOT NULL AND @nombreAreaDefecto <> ''
        BEGIN
            SELECT TOP 1 @idAreaResolved = id 
            FROM dbo.Area 
            WHERE LOWER(nombre) LIKE '%' + LOWER(@nombreAreaDefecto) + '%'
            ORDER BY nombre ASC;
        END

        -- PASO 3: Resolver SemestrePlanEstudio si se especifica plan y semestre
        IF @estadoResultado = 1 AND @idPlanEstudioDefecto IS NOT NULL AND @semestreNumero IS NOT NULL
        BEGIN
            SELECT TOP 1 @idSemestreResolved = id FROM dbo.Semestre WHERE numero = @semestreNumero ORDER BY numero ASC;
            IF @idSemestreResolved IS NOT NULL
            BEGIN
                SELECT TOP 1 @idSpeResolved = id 
                FROM dbo.SemestrePlanEstudio 
                WHERE planEstudio = @idPlanEstudioDefecto AND semestre = @idSemestreResolved;

                IF @idSpeResolved IS NULL
                BEGIN
                    SET @idSpeResolved = NEWID();
                    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) 
                    VALUES (@idSpeResolved, @idPlanEstudioDefecto, @idSemestreResolved);
                END
            END
        END

        -- PASO 4: Invocación al procedimiento interno de actualización
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_actualizar_asignatura_interno
                @idAsignatura = @idAsignaturaDefecto,
                @codigo = @codigoDefecto,
                @nombre = @nombreDefecto,
                @creditos = @creditos,
                @idArea = @idAreaResolved,
                @idSemestrePlanEstudio = @idSpeResolved,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
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
