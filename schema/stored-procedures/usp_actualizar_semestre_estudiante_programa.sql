USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_actualizar_semestre_estudiante_programa (migracion 63)
--
-- El coordinador registra el semestre que cursa un estudiante en un programa que el coordina (EstudiantePrograma.semestreActual).
-- @semestreActual NULL limpia el valor. Clasificacion: MUTATION_COMMAND_RESULTSET (4 columnas canonicas).
--   * RBAC COORDINADOR y titularidad del PROGRAMA (usp_validar_*_interno): otro coordinador recibe SEC_002.
--   * El estudiante debe tener vinculo con el programa: EST_008.
--   * Rango: entre el menor y el mayor Semestre.numero del catalogo dbo.Semestre (sin literales): EST_009.
--   * Exito: EST_007. La validacion ocurre antes de abrir la transaccion; la auditoria la deja el backend (AuditableOperation).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_semestre_estudiante_programa]
(
    @idEstudiante      UNIQUEIDENTIFIER,
    @idPrograma        UNIQUEIDENTIFIER,
    @semestreActual    INT              = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @semestreMinimo INT, @semestreMaximo INT;
    DECLARE @msgP1 NVARCHAR(500), @msgP2 NVARCHAR(500);
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idProgramaDefecto,
                @tipoEntidadPadre = 'PROGRAMA', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = @idEstudianteDefecto AND ep.programa = @idProgramaDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'EST_008',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND @semestreActual IS NOT NULL
        BEGIN
            SELECT @semestreMinimo = MIN(s.numero), @semestreMaximo = MAX(s.numero) FROM dbo.Semestre s;
            IF @semestreMinimo IS NULL OR @semestreActual < @semestreMinimo OR @semestreActual > @semestreMaximo
            BEGIN
                SET @msgP1 = CAST(@semestreMinimo AS NVARCHAR(500));
                SET @msgP2 = CAST(@semestreMaximo AS NVARCHAR(500));
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'EST_009', @p_param1 = @msgP1, @p_param2 = @msgP2,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_semestre_estudiante_prog;
                SET @savepointCreado = 1;
            END

            UPDATE dbo.EstudiantePrograma
            SET semestreActual = CAST(@semestreActual AS TINYINT)
            WHERE estudiante = @idEstudianteDefecto AND programa = @idProgramaDefecto;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'EST_007',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1 COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1 ROLLBACK TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0 ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_semestre_estudiante_prog;
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
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
