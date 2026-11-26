USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.9-a (F-ADM-024): DEC_020 si la persona ya es decano activo (sobre la firma con @idTipoIdIdentificacion de D.5).
-- FIX-CIERRE-001: la facultad se resuelve por id o por nombre exacto (sin LIKE); una facultad indicada que no existe -> FAC_001 sin crear nada;
-- sin facultad (id y nombre nulos o vacios) se crea el decano sin facultad (HU178).
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): DECLARE del cuerpo a la cabecera, PASO en el CATCH, IF con BEGIN/END, IIF en lugar de COALESCE y
-- estado del rol por uv_decano_rol (antes, la tabla).
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_decano]
(
    @idDecano               UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @nombreFacultad          NVARCHAR(150)    = NULL,
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDecanoDefecto          UNIQUEIDENTIFIER = @idDecano;
    DECLARE @idFacultadDefecto        UNIQUEIDENTIFIER = @idFacultad;
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreFacultadDef        NVARCHAR(150)    = TRIM(@nombreFacultad);


    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    -- Control de ownership transaccional (ver docs/procedimiento-transacciones)
    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @facultadIndicada           NVARCHAR(150);
    DECLARE @idUsuarioExistente         UNIQUEIDENTIFIER;
    DECLARE @estadoTransaccionCatch     INT;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de presencia del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
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
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2 (FIX-CIERRE-001): la facultad destino se resuelve solo por identificador o por nombre EXACTO (sin distinguir mayusculas ni
        -- espacios extremos). Antes el nombre coincidia por LIKE '%x%' y se tomaba la primera facultad alfabetica. Si se indica una facultad
        -- (id o nombre) y no existe -> FAC_001 y no se crea nada; si no se indica ninguna, el decano se crea sin facultad (HU178). Se decide
        -- ANTES de abrir la transaccion: el rechazo no escribe y el SP sigue siendo apto para INSERT ... EXEC.
        IF @estadoResultado = 1 AND @idFacultadDefecto IS NULL AND @nombreFacultadDef IS NOT NULL AND @nombreFacultadDef <> ''
        BEGIN
            SELECT TOP 1 @idFacultadDefecto = id
            FROM [dbo].[uv_facultad]
            WHERE LOWER(TRIM(nombreFacultad)) = LOWER(@nombreFacultadDef)
            ORDER BY id ASC;
        END

        IF @estadoResultado = 1
           AND (@idFacultad IS NOT NULL OR (@nombreFacultadDef IS NOT NULL AND @nombreFacultadDef <> ''))
           AND (@idFacultadDefecto IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_facultad] WHERE id = @idFacultadDefecto))
        BEGIN
            SET @facultadIndicada = IIF(@idFacultad IS NULL, @nombreFacultadDef, CONVERT(NVARCHAR(36), @idFacultad));
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FAC_001',
                @p_param1 = @facultadIndicada,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2.5 (D.9-a, F-ADM-024): la persona ya es decano activo. Se decide ANTES de abrir la transaccion o el savepoint:
        -- no hay escrituras que revertir y el SP puede invocarse con INSERT ... EXEC sin ROLLBACK interno (DEC-036).
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idUsuarioExistente = id
            FROM [dbo].[uv_usuario]
            WHERE correo = LOWER(TRIM(@correo)) OR numeroIdentificacion = CAST(@numeroIdentificacion AS VARCHAR(20));

            IF @idUsuarioExistente IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.uv_decano_rol d WHERE d.idUsuario = @idUsuarioExistente AND d.estaActivoRolDecano = 1)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DEC_020',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2.6 (DEC-073): un decano nuevo usa el correo institucional (VCE_008); una persona que ya existe conserva el suyo.
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

        -- PASO 3: apertura de transaccion (o savepoint) y delegacion de persona + rol Decano al nucleo usp_crear_decano_interno (DEC-065 (5))
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
                SAVE TRANSACTION usp_crear_decano;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_crear_decano_interno
                @idDecano = @idDecanoDefecto OUTPUT,
                @numeroIdentificacion = @numeroIdentificacion,
                @primerNombre = @primerNombre,
                @segundoNombre = @segundoNombre,
                @primerApellido = @primerApellido,
                @segundoApellido = @segundoApellido,
                @correo = @correo,
                @password = @password,
                @idFacultad = @idFacultadDefecto,
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
                BEGIN
                    COMMIT TRANSACTION;
                END
                ELSE
                BEGIN
                    ROLLBACK TRANSACTION;
                END
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            IF XACT_STATE() = 1 AND @estadoResultado = 0
            BEGIN
                ROLLBACK TRANSACTION usp_crear_decano;
            END
            -- XACT_STATE() = -1 con transacción externa: no es propietaria, no se toca (ver PASO 10 del contrato)
        END

    END TRY
    BEGIN CATCH
        -- PASO 6: reversion respetando ownership; transaccion externa condenada se propaga; si no, SYS_001
        SET @estadoTransaccionCatch = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_crear_decano;
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
