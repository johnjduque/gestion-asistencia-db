USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_coordinador]
(
    @idCoordinador           UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @idPrograma              UNIQUEIDENTIFIER = NULL,
    @idFacultad              UNIQUEIDENTIFIER,
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idCoordinadorDefecto     UNIQUEIDENTIFIER = @idCoordinador;
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = @idPrograma;
    DECLARE @idFacultadDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idFacultad, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');


    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    -- Control de ownership transaccional (ver docs/procedimiento-transacciones)
    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de presencia del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de presencia del ejecutor y perfil RBAC
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'DECANO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        END

        -- PASO 2: Validar programa académico consultando uv_programa (cuando se suministra @idPrograma)
        IF @estadoResultado = 1 AND @idProgramaDefecto IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[uv_programa] WHERE id = @idProgramaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PROG_001',
                    @p_param1 = 'Programa',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2B: Validar existencia de la facultad indicada consultando uv_facultad
        IF @estadoResultado = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[uv_facultad] WHERE id = @idFacultadDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001',
                    @p_param1 = 'Facultad',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2C: Validar que el Programa pertenezca a la Facultad indicada (cuando se suministra @idPrograma)
        IF @estadoResultado = 1 AND @idProgramaDefecto IS NOT NULL
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM [dbo].[uv_programa]
                WHERE id = @idProgramaDefecto AND idFacultad = @idFacultadDefecto
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ERR_PROGRAMA_FACULTAD_INCONSISTENTE',
                    @p_param1 = @idProgramaDefecto,
                    @p_param2 = @idFacultadDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2D: Validar titularidad jerárquica sobre la Facultad ya existente y coherente
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idFacultadDefecto,
                @tipoEntidadPadre = 'FACULTAD',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2E (DEC-073): un coordinador nuevo usa el correo institucional (VCE_008); una persona que ya existe conserva el suyo.
        --          Se decide ANTES de abrir la transaccion: el rechazo no escribe y el SP sigue siendo apto para INSERT ... EXEC (DEC-036).
        IF @estadoResultado = 1
           AND NOT EXISTS (SELECT 1 FROM [dbo].[uv_usuario]
                           WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = CAST(@numeroIdentificacion AS VARCHAR(20)))
        BEGIN
            EXEC dbo.usp_validar_correo_institucional_personal_interno
                @correo = @correo,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: apertura de transaccion (o savepoint) y delegacion de persona + rol Coordinador al nucleo usp_crear_coordinador_interno (DEC-065 (5))
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;

            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_crear_coordinador;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_crear_coordinador_interno
                @idCoordinador = @idCoordinadorDefecto OUTPUT,
                @numeroIdentificacion = @numeroIdentificacion,
                @primerNombre = @primerNombre,
                @segundoNombre = @segundoNombre,
                @primerApellido = @primerApellido,
                @segundoApellido = @segundoApellido,
                @correo = @correo,
                @password = @password,
                @idFacultad = @idFacultadDefecto,
                @idPrograma = @idProgramaDefecto,
                @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Finalización de la transacción respetando ownership (ver docs/procedimiento-transacciones)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            IF XACT_STATE() = 1 AND @estadoResultado = 0
                ROLLBACK TRANSACTION usp_crear_coordinador;
            -- XACT_STATE() = -1 con transacción externa: no es propietaria, no se toca (ver PASO 10 del contrato)
        END

    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_crear_coordinador;
        END

        -- Transacción externa quedó doomed y no nos pertenece: propagar la excepción original al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

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
