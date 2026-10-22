USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_crear_programa_academico_interno]
-- Historia de Usuario: HU076 (Agregar nuevo programa académico a la facultad)
-- Ámbito: Operación atómica de persistencia para Programa Académico
-- Estándar: Conforme a procedimientos-internos-condiciones y AGENTS.md
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_programa_academico_interno]
(
    @idPrograma              UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(100),
    @idCoordinador           UNIQUEIDENTIFIER,
    @idFacultad              UNIQUEIDENTIFIER,
    @idTipoPrograma          UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- 1. Declaración e inicialización estricta en cabecera (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idCoordinadorDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCoordinador, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idFacultadDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idFacultad, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTipoProgramaDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idTipoPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto         NVARCHAR(100)    = TRIM(@nombre);

    -- Ownership transaccional
    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Inicialización de variables de salida usando catálogos
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Asignación de ID si no viene definido o es el guid por defecto
        IF @estadoResultado = 1
        BEGIN
            IF @idProgramaDefecto IS NULL OR @idProgramaDefecto = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER)
            BEGIN
                SET @idProgramaDefecto = NEWID();
            END

            -- PASO 3: Control transaccional y persistencia
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_crear_programa_in;
                SET @savepointCreado = 1;
            END

            IF EXISTS (SELECT 1 FROM dbo.uv_programa WHERE id = @idProgramaDefecto)
            BEGIN
                UPDATE dbo.Programa
                SET nombre = @nombreDefecto,
                    coordinador = @idCoordinadorDefecto,
                    facultad = @idFacultadDefecto,
                    tipoDePrograma = @idTipoProgramaDefecto,
                    estado = 1
                WHERE id = @idProgramaDefecto;
            END
            ELSE
            BEGIN
                INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
                VALUES (@idProgramaDefecto, @idFacultadDefecto, @idTipoProgramaDefecto, @nombreDefecto, @idCoordinadorDefecto, 1);
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Programa Academico',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION usp_crear_programa_in;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
