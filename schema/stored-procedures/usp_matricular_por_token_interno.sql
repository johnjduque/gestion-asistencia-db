USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: nucleo interno de la matricula atomica por token o PIN de una ventana ACTIVA. Lo invocan las fachadas
-- usp_matricular_estudiante_por_token (autenticado) y usp_registrar_estudiante_por_token_publico (publico). NO se concede
-- EXECUTE al rol de runtime. CONTRACT A2.
--   * @idUsuarioAutenticado NO NULL: modo autenticado: RBAC ESTUDIANTE; el estudiante es el de ese usuario.
--   * @idUsuarioAutenticado NULL: modo publico: crea Usuario (ACTIVO, correoConfirmado = 0) y Estudiante; el correo debe ser
--     institucional (IDENT-001: VCE_001). Documento o correo ya existentes: MQR_005 sin cambios.
--   * Revision final P3: un estudiante existente con programas se matricula solo con un programa comun con el grupo (EST_010, EST_011, MQR_008).
--   * Reglas de HU050 via usp_registrar_estudiante_en_grupo_interno (cupo, cruce, duplicado, programa). El estado de la
--     matricula es el parametro MATRICULA_QR/ESTADO_MATRICULA (sin literal quemado), validado ANTES de escribir.
--   * Atomico: la expiracion perezosa de la ventana persiste; el trabajo de negocio se revierte hasta su savepoint ante
--     cualquier falla posterior a la escritura.
-- SKILLS-BD lote 2 (2026-11-25): antes usp_internal_matricular_por_token (renombrado, D3); llama a los nucleos renombrados
-- con el triplete OUTPUT. El cuerpo se corrige en su lote de dominio.
-- SKILLS-BD lote 14 (2026-11-26, objeto congelado, decision D5): DECLARE del cuerpo a la cabecera, PASO n, IF con BEGIN/END, IIF en lugar de COALESCE y lecturas sin
-- bloqueo de estudiante, usuario, matricula, programas y ventana por vistas uv_* (antes, las tablas); el token se resuelve en el
-- nucleo (E7) y el UPDATE del contador sigue en la tabla.
-- Misma firma, mismo resultset y mismos codigos; el hash del manifiesto se actualiza en el mismo commit.
CREATE OR ALTER PROCEDURE [dbo].[usp_matricular_por_token_interno]
(
    @idCorrelacion            UNIQUEIDENTIFIER,
    @tokenHash                VARBINARY(32),
    @pin                      NCHAR(6),
    @idUsuarioAutenticado     UNIQUEIDENTIFIER,
    @idTipoIdentificacion     UNIQUEIDENTIFIER,
    @numeroIdentificacion     INT,
    @primerNombre             NVARCHAR(50),
    @segundoNombre            NVARCHAR(50),
    @primerApellido           NVARCHAR(50),
    @segundoApellido          NVARCHAR(50),
    @correo                   NVARCHAR(100),
    @password                 NVARCHAR(500),
    @mensajeUsuarioResultado  NVARCHAR(4000)   OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000)   OUTPUT,
    @estadoResultado          BIT              OUTPUT,
    @idEstudianteResultado    UNIQUEIDENTIFIER OUTPUT,
    @idUsuarioResultado       UNIQUEIDENTIFIER OUTPUT,
    @idGrupoResultado         UNIQUEIDENTIFIER OUTPUT,
    -- DEC-078: programa que elige el estudiante en un grupo compartido (uno de ufn_programas_grupo; EST_006 si es ajeno).
    @idProgramaElegido        UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    DECLARE @idVentana        UNIQUEIDENTIFIER;
    DECLARE @idGrupo          UNIQUEIDENTIFIER;
    DECLARE @idDocenteEmisor  UNIQUEIDENTIFIER;
    DECLARE @codigoRechazo    VARCHAR(20) = NULL;
    DECLARE @parametroRechazo NVARCHAR(255) = NULL;

    DECLARE @idUsuarioTarget    UNIQUEIDENTIFIER = NULL;
    DECLARE @idEstudianteTarget UNIQUEIDENTIFIER = NULL;
    DECLARE @correoNormalizado  NVARCHAR(100)    = LOWER(TRIM(@correo));
    DECLARE @mensajeUsuarioInterno   NVARCHAR(4000);  -- SKILLS-BD lote 2: triplete del nucleo interno
    DECLARE @mensajeTecnicoInterno   NVARCHAR(4000);
    DECLARE @estadoInterno           BIT;
    DECLARE @mensajeErrorInterno     NVARCHAR(2048);
    DECLARE @codigoMatricula         NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_MATRICULA') AS NVARCHAR(10));
    DECLARE @programaVentana         UNIQUEIDENTIFIER;
    DECLARE @programasComunes        INT;
    DECLARE @estadoTransaccionCatch  INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- AUD-BD M-6: un error no capturado condena la transaccion; el CATCH ya maneja XACT_STATE() = -1 (THROW si no es propia)

    -- PASO 0: inicializacion de las salidas
    SELECT @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @estadoResultado = 1,
           @idEstudianteResultado = NULL, @idUsuarioResultado = NULL, @idGrupoResultado = NULL;

    BEGIN TRY
        -- PASO 0.1: transaccion propia o savepoint
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_hu176b_matricular;
            SET @savepointCreado = 1;
        END

        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: resolver la ventana (UPDLOCK). Puede escribir solo la expiracion perezosa.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_resolver_token_matricula_interno
                @tokenHash = @tokenHash, @pin = @pin, @idCorrelacion = @idCorrelacionDefecto,
                @idVentana = @idVentana OUTPUT, @idGrupo = @idGrupo OUTPUT,
                @idDocenteEmisor = @idDocenteEmisor OUTPUT, @codigoRechazo = @codigoRechazo OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioInterno OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoInterno OUTPUT,
                @estadoResultado = @estadoInterno OUTPUT;
            IF @estadoInterno = 0
            BEGIN
                SET @mensajeErrorInterno = LEFT(@mensajeTecnicoInterno, 2048);
                THROW 52526, @mensajeErrorInterno, 1;
            END
        END

        -- PASO 3: validaciones sin escritura
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idUsuarioAutenticado IS NOT NULL
        BEGIN
            -- Modo autenticado: el usuario debe ser un ESTUDIANTE
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioAutenticado,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                SET @idUsuarioTarget = @idUsuarioAutenticado;
                SELECT TOP 1 @idEstudianteTarget = e.id FROM dbo.uv_estudiante_identidad e WHERE e.idUsuario = @idUsuarioAutenticado;

                IF @idEstudianteTarget IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'GEN_001', @p_param1 = 'Estudiante',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END
        ELSE IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            -- Modo publico: datos obligatorios
            IF @idTipoIdentificacion IS NULL OR @numeroIdentificacion IS NULL OR @primerNombre IS NULL
               OR @primerApellido IS NULL OR @correoNormalizado IS NULL OR @correoNormalizado = N''
            BEGIN
                SET @codigoRechazo = 'GEN_002';
                SET @parametroRechazo = N'datos de registro';
            END
            -- Persona ya registrada (documento o correo): debe iniciar sesion
            ELSE IF EXISTS (
                SELECT 1 FROM dbo.uv_usuario u
                WHERE u.correo = @correoNormalizado
                   OR (u.idTipoIdentificacion = @idTipoIdentificacion AND u.numeroIdentificacion = @numeroIdentificacion)
            )
            BEGIN
                SET @codigoRechazo = 'MQR_005';
            END
            -- IDENT-001: el correo de un alta nueva debe ser institucional
            ELSE IF dbo.ufn_correo_cumple_dominio_institucional(@correo, dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE')) = 0
            BEGIN
                SET @codigoRechazo = 'VCE_001';
                SET @parametroRechazo = CAST(dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE') AS NVARCHAR(255));
            END
        END

        -- PASO 3.1: ya matriculado (solo se puede evaluar con estudiante conocido: modo autenticado)
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idEstudianteTarget IS NOT NULL
           AND EXISTS (
                SELECT 1
                FROM dbo.uv_estudiante_grupo_registro eg
                INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.idEstado
                WHERE eg.idEstudiante = @idEstudianteTarget AND eg.idGrupo = @idGrupo AND es.codigo = @codigoMatricula
           )
        BEGIN
            SET @codigoRechazo = 'MQR_004';
        END

        -- PASO 3.2 (DEC-078): el programa de la ventana (si el docente lo fijo) o el que eligio el estudiante.
        SET @programaVentana = (SELECT t.idProgramaPorDefecto FROM dbo.uv_token_matricula_grupo_registro t WHERE t.id = @idVentana);
        SET @programaVentana = IIF(@programaVentana IS NULL, @idProgramaElegido, @programaVentana);
        -- DEC-078: un programa elegido que no es del grupo se rechaza antes de crear usuario o matricula (EST_006).
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @programaVentana IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) pg WHERE pg.idPrograma = @programaVentana)
        BEGIN
            SET @codigoRechazo = 'EST_006';
        END
        -- Revision final P3 (decision 2026-11-22, igual que la matricula manual BD-4): un estudiante EXISTENTE con vinculos en EstudiantePrograma solo se
        -- matricula con un programa comun con el grupo. Ninguno comun: EST_010; programa de la ventana o elegido que no es suyo: EST_011; un unico programa
        -- comun y ninguno fijado: se usa ese; varios y ninguno fijado: MQR_008. Nunca se crea un vinculo nuevo a quien ya tiene programas (usp_asegurar_estudiante_programa_grupo_interno
        -- devuelve el existente). Estudiante nuevo o sin ningun vinculo: sin cambio (elige entre los programas del grupo).
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idEstudianteTarget IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa_registro ep WHERE ep.idEstudiante = @idEstudianteTarget)
        BEGIN
            SET @programasComunes = (SELECT COUNT(*) FROM dbo.uv_estudiante_programa_registro ep
                                     INNER JOIN dbo.ufn_programas_grupo(@idGrupo) pg ON pg.idPrograma = ep.idPrograma
                                     WHERE ep.idEstudiante = @idEstudianteTarget);
            IF @programasComunes = 0
            BEGIN
                SET @codigoRechazo = 'EST_010';
            END
            ELSE IF @programaVentana IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa_registro ep WHERE ep.idEstudiante = @idEstudianteTarget AND ep.idPrograma = @programaVentana)
            BEGIN
                SET @codigoRechazo = 'EST_011';
            END
            ELSE IF @programaVentana IS NULL AND @programasComunes = 1
            BEGIN
                SELECT @programaVentana = ep.idPrograma FROM dbo.uv_estudiante_programa_registro ep
                INNER JOIN dbo.ufn_programas_grupo(@idGrupo) pg ON pg.idPrograma = ep.idPrograma
                WHERE ep.idEstudiante = @idEstudianteTarget;
            END
            ELSE IF @programaVentana IS NULL AND @programasComunes > 1
            BEGIN
                SET @codigoRechazo = 'MQR_008';
            END
        END
        -- CULM-001 B2NM (S3) / DEC-078: grupo multiprograma sin programa (ni de la ventana ni elegido) y sin vinculo previo ->
        -- MQR_008 (el estudiante debe elegir su programa), antes de crear usuario o matricula.
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
           AND (SELECT COUNT(*) FROM dbo.ufn_programas_grupo(@idGrupo)) > 1
           AND @programaVentana IS NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa_registro ep
                           INNER JOIN dbo.ufn_programas_grupo(@idGrupo) pg ON pg.idPrograma = ep.idPrograma
                           WHERE ep.idEstudiante = @idEstudianteTarget)
        BEGIN
            SET @codigoRechazo = 'MQR_008';
        END

        -- PASO 3.3: cupo, antes de crear nada
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno
                @idGrupo = @idGrupo,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- Estado de matricula configurado y existente, ANTES de escribir (falla rapida: un parametro mal
        -- configurado no debe dejar usuarios a medias; ademas ROLLBACK no es valido bajo INSERT ... EXEC).
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_estado_estudiante_grupo es WHERE es.codigo = UPPER(TRIM(@codigoMatricula)))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001', @p_param1 = 'Estado de matricula por QR',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3.4: mensaje del rechazo por catalogo
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @parametroRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: escrituras de negocio bajo un savepoint propio (la expiracion perezosa del paso 2 no se revierte)
        IF @estadoResultado = 1
        BEGIN
            SAVE TRANSACTION sp_hu176b_negocio;

            IF @idEstudianteTarget IS NULL
            BEGIN
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correo,
                    @password = @password,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @estaActivo = 1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1 @idUsuarioTarget = u.id FROM dbo.uv_usuario u WHERE u.correo = @correoNormalizado;
                END

                IF @estadoResultado = 1
                BEGIN
                    EXEC dbo.usp_sincronizar_estudiante_interno
                        @idUsuario = @idUsuarioTarget,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;

                    IF @estadoResultado = 1
                    BEGIN
                        SELECT TOP 1 @idEstudianteTarget = e.id FROM dbo.uv_estudiante_identidad e WHERE e.idUsuario = @idUsuarioTarget;
                    END
                END
            END

            IF @estadoResultado = 1 AND @idEstudianteTarget IS NOT NULL
            BEGIN
                EXEC dbo.usp_registrar_estudiante_en_grupo_interno
                    @idEstudiante = @idEstudianteTarget,
                    @idGrupo = @idGrupo,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @codigoEstado = @codigoMatricula,
                    @idProgramaElegido = @programaVentana,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                UPDATE dbo.TokenMatriculaGrupo SET totalMatriculas = totalMatriculas + 1 WHERE id = @idVentana;
            END
            ELSE IF XACT_STATE() = 1
            BEGIN
                -- Falla despues de escribir: se revierte solo el trabajo de negocio
                ROLLBACK TRANSACTION sp_hu176b_negocio;
                SELECT @idUsuarioTarget = NULL, @idEstudianteTarget = NULL;
            END
        END

        -- PASO 5: cierre de la transaccion propia (confirma tambien la expiracion perezosa)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                COMMIT TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
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
            ROLLBACK TRANSACTION sp_hu176b_matricular;
        END

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
        SELECT @idUsuarioTarget = NULL, @idEstudianteTarget = NULL;
    END CATCH

    IF @estadoResultado = 1
    BEGIN
        SELECT @idEstudianteResultado = @idEstudianteTarget, @idUsuarioResultado = @idUsuarioTarget, @idGrupoResultado = @idGrupo;
    END
END;
GO
