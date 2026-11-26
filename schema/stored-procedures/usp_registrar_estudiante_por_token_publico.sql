USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: registro PUBLICO de una persona sin cuenta y su matricula con el token o PIN de una ventana ACTIVA. No tiene
-- parametro de ejecutor: la credencial es el token/PIN (excepcion declarada en CONTRACT §2.1 y A2); solo se concede
-- EXECUTE al rol de runtime. Crea Usuario ACTIVO (correoConfirmado = 0), Estudiante y la matricula, de forma atomica.
-- Correo institucional obligatorio (VCE_001). Documento o correo ya registrados: MQR_005. Token invalido: MQR_001.
-- Resultset: tupla canonica + idEstudiante, idUsuario, idGrupo (extension documentada, CONTRACT §2.5).
-- SP_SISTEMA (excepcion E1, docs/arquitectura/excepciones-skills-bd.md): flujo publico por token, sin @idUsuarioEjecutor; el nucleo
-- valida el token, su vigencia y su ambito. SKILLS-BD lote 2 (2026-11-25): TRY/CATCH con SYS_001 y PASO n.
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_estudiante_por_token_publico]
(
    @idCorrelacion         UNIQUEIDENTIFIER,
    @tokenHash             VARBINARY(32)    = NULL,
    @pin                   NCHAR(6)         = NULL,
    @idTipoIdentificacion  UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion  INT              = NULL,
    @primerNombre          NVARCHAR(50)     = NULL,
    @segundoNombre         NVARCHAR(50)     = NULL,
    @primerApellido        NVARCHAR(50)     = NULL,
    @segundoApellido       NVARCHAR(50)     = NULL,
    @correo                NVARCHAR(100)    = NULL,
    @password              NVARCHAR(500)    = NULL,
    @idPrograma            UNIQUEIDENTIFIER = NULL   -- DEC-078: programa elegido en un grupo compartido
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @idEstudianteResultado UNIQUEIDENTIFIER = NULL;
    DECLARE @idUsuarioResultado    UNIQUEIDENTIFIER = NULL;
    DECLARE @idGrupoResultado      UNIQUEIDENTIFIER = NULL;
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: registro y matricula con el token o PIN (nucleo con transaccion propia)
        EXEC dbo.usp_matricular_por_token_interno
            @idCorrelacion = @idCorrelacionDefecto, @tokenHash = @tokenHash, @pin = @pin,
            @idUsuarioAutenticado = NULL,
            @idTipoIdentificacion = @idTipoIdentificacion, @numeroIdentificacion = @numeroIdentificacion,
            @primerNombre = @primerNombre, @segundoNombre = @segundoNombre,
            @primerApellido = @primerApellido, @segundoApellido = @segundoApellido,
            @correo = @correo, @password = @password,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idEstudianteResultado = @idEstudianteResultado OUTPUT,
            @idUsuarioResultado = @idUsuarioResultado OUTPUT,
            @idGrupoResultado = @idGrupoResultado OUTPUT,
            @idProgramaElegido = @idPrograma;
    END TRY
    BEGIN CATCH
        -- PASO 2: error no controlado. Si la transaccion del llamador quedo condenada (el nucleo relanza en ese caso)
        -- se relanza el error original, como antes del lote 2 (SKILLS-BD lote 16); si no, SYS_001. El nucleo gestiona y
        -- revierte su propia transaccion
        IF XACT_STATE() = -1 AND @@TRANCOUNT > 0
        BEGIN
            THROW;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SELECT @idEstudianteResultado = NULL, @idUsuarioResultado = NULL, @idGrupoResultado = NULL;
    END CATCH

    -- PASO 3: resultset unificado (tupla canonica + extension documentada)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idEstudiante            = @idEstudianteResultado,
        idUsuario               = @idUsuarioResultado,
        idGrupo                 = @idGrupoResultado;
END;
GO
