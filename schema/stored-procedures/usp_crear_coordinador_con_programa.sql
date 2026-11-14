USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_crear_coordinador_con_programa (CULM-001 / DEC-065 (5); HU076, HU121)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con la tupla canonica (idCorrelacion, mensajeUsuarioResultado,
-- mensajeTecnicoResultado, estadoResultado) + idCoordinador, idPrograma, nombrePrograma (NULL si estadoResultado = 0).
--
-- El decano registra, en UNA transaccion, a la persona coordinadora y el programa academico que coordinara en su facultad. Las validaciones
-- que no escriben se resuelven ANTES de abrir la transaccion; el resto de la escritura es todo o nada:
--   * RBAC DECANO (SEC_001), ejecutor obligatorio (GEN_002), facultad obligatoria (GEN_002);
--   * titularidad del decano sobre @idFacultad (SEC_002), como usp_crear_programa_academico y usp_crear_coordinador;
--   * facultad existente y activa (GEN_001);
--   * programa: nombre (GEN_002), unico en la facultad (PROG_003), tipo (PROG_004), modalidad y jornada (PROG_006). Son las reglas de
--     usp_validar_programa_academico_interno, que se invoca sin coordinador y cuyo unico rechazo esperado (PROG_005, aun no existe) se descarta;
--   Luego, dentro de la transaccion: usp_crear_coordinador_interno (persona + rol, con la facultad) y usp_insertar_programa_academico_interno
--   (que revalida el programa ya con el coordinador: PROG_005 si ya tiene otro programa). Cualquier error revierte persona, rol y programa.
-- Transaccion propia o SAVE TRANSACTION cuando el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_coordinador_con_programa]
(
    @idCoordinador          UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion   INT,
    @primerNombre           NVARCHAR(50),
    @segundoNombre          NVARCHAR(50),
    @primerApellido         NVARCHAR(50),
    @segundoApellido        NVARCHAR(50),
    @correo                 NVARCHAR(100),
    @password               NVARCHAR(500),
    @nombrePrograma         NVARCHAR(100),
    @idTipoPrograma         UNIQUEIDENTIFIER,
    @idModalidad            UNIQUEIDENTIFIER = NULL,
    @idJornada              UNIQUEIDENTIFIER = NULL,
    @idFacultad             UNIQUEIDENTIFIER,
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor      UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idCoordinadorDefecto     UNIQUEIDENTIFIER = @idCoordinador;
    DECLARE @idProgramaNuevo          UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreProgramaDef        NVARCHAR(100)    = TRIM(@nombrePrograma);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio y perfil DECANO
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

        -- PASO 3: facultad obligatoria y titularidad del decano sobre ella
        IF @estadoResultado = 1 AND @idFacultad IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idFacultad',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idFacultad,
                @tipoEntidadPadre = 'FACULTAD',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_facultad f WHERE f.id = @idFacultad AND f.estaActivaFacultad = 1)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Facultad',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: reglas del programa (nombre, unicidad, tipo, modalidad, jornada) ANTES de crear la persona. Sin coordinador el validador termina
        -- siempre en PROG_005; ese unico rechazo es el esperado y se descarta, cualquier otro es el error real.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_programa_academico_interno
                @idPrograma = NULL,
                @idFacultad = @idFacultad,
                @nombre = @nombreProgramaDef,
                @idTipoPrograma = @idTipoPrograma,
                @idCoordinador = NULL,
                @idModalidad = @idModalidad,
                @idJornada = @idJornada,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 0 AND @mensajeTecnicoResultado LIKE N'DBCODE=PROG[_]005|%'
            BEGIN
                SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
                SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
                SET @estadoResultado = 1;
            END
        END

        -- PASO 4.5 (DEC-073): un coordinador nuevo usa el correo institucional (VCE_008); una persona que ya existe conserva el suyo.
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

        -- PASO 5: transaccion unica (propia o savepoint): persona + rol Coordinador (con la facultad) y despues el programa con ese coordinador
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION svp_crear_coord_programa;
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
                @idFacultad = @idFacultad,
                @idPrograma = NULL,
                @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_insertar_programa_academico_interno
                    @idPrograma = @idProgramaNuevo,
                    @idFacultad = @idFacultad,
                    @nombre = @nombreProgramaDef,
                    @idTipoPrograma = @idTipoPrograma,
                    @idCoordinador = @idCoordinadorDefecto,
                    @idModalidad = @idModalidad,
                    @idJornada = @idJornada,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'Coordinador y programa',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' IdCoordinador: ', @idCoordinadorDefecto, ' IdPrograma: ', @idProgramaNuevo, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- Cierre respetando el ownership: un fallo tras abrir la transaccion revierte persona, rol y programa
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
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
            ELSE IF @savepointCreado = 1 AND XACT_STATE() = 1 AND @estadoResultado = 0
                ROLLBACK TRANSACTION svp_crear_coord_programa;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION svp_crear_coord_programa;

        -- Transaccion externa condenada que no nos pertenece: se propaga al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idCoordinador           = IIF(@estadoResultado = 1, @idCoordinadorDefecto, NULL),
        idPrograma              = IIF(@estadoResultado = 1, @idProgramaNuevo, NULL),
        nombrePrograma          = IIF(@estadoResultado = 1, @nombreProgramaDef, NULL);
END;
GO
