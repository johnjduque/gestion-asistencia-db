USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_corregir_documento_usuario_interno (HU159, decision de John 2026-11-05)
--
-- Unico punto que corrige el tipo y el numero de documento de un usuario (decano, coordinador, docente o estudiante;
-- la jerarquia la valida cada fachada). Aislado a proposito: se apaga con un parametro y se puede retirar sin tocar
-- la correccion de nombres.
--   * @idTipoIdIdentificacion y @numeroIdentificacion NULL conservan el valor actual (sin cambio => no-op).
--   * IDENTIDAD.PERMITIR_CORREGIR_DOCUMENTO distinto de 1: cualquier cambio de documento se rechaza con IDE_003.
--   * Si el documento cambia, el motivo es obligatorio (1..500): IDE_001.
--   * Tipo existente, numero valido (VAL_001) y unico excluyendo al propio usuario (ERR_UNICIDAD_DOCUMENTO,
--     leido con UPDLOCK/HOLDLOCK).
-- @soloValidar = 1 valida sin escribir: las fachadas lo llaman antes de cualquier escritura para que un rechazo no
-- necesite ROLLBACK (prohibido dentro de INSERT ... EXEC). @documentoCambiado = 1 indica que el documento cambia.
-- El documento es el username del proveedor de identidad: el backend lo sincroniza despues de confirmar en DB.
-- Sin transaccion propia (corre dentro de la fachada publica).
-- SKILLS-BD lote 3 (2026-11-25): PASO n y correlacion por defecto en los mensajes; mismo comportamiento.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_corregir_documento_usuario_interno]
(
    @idUsuario               UNIQUEIDENTIFIER,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @motivo                  NVARCHAR(MAX),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @documentoCambiado       BIT OUTPUT,
    @soloValidar             BIT = 0
)
AS
    DECLARE @motivoNormalizado NVARCHAR(MAX) = NULLIF(TRIM(@motivo), N'');
    DECLARE @permitido         INT = dbo.ufn_obtener_parametro_int(NULL, 'IDENTIDAD', 'PERMITIR_CORREGIR_DOCUMENTO');
    DECLARE @idTipoActual      UNIQUEIDENTIFIER;
    DECLARE @numeroActual      INT;
    DECLARE @idTipoDestino     UNIQUEIDENTIFIER;
    DECLARE @numeroDestino     INT;
    DECLARE @codigoRechazo     VARCHAR(100);
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: respuesta inicial
    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1,
        @documentoCambiado = 0;

    BEGIN TRY
        -- PASO 2: documento actual con la fila bloqueada (lectura con bloqueo en la tabla) y documento destino
        SELECT @idTipoActual = u.tipoIdIdentificacion, @numeroActual = u.numeroIdentificacion
        FROM dbo.Usuario u WITH (UPDLOCK, HOLDLOCK)
        WHERE u.id = @idUsuario;

        SET @idTipoDestino = IIF(@idTipoIdIdentificacion IS NULL, @idTipoActual, @idTipoIdIdentificacion);
        SET @numeroDestino = IIF(@numeroIdentificacion IS NULL, @numeroActual, @numeroIdentificacion);

        -- PASO 3: usuario existente (GEN_001)
        IF @idTipoActual IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001', @p_param1 = 'Usuario',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: sin cambio de documento => no-op; con cambio: permitido (IDE_003) y motivo (IDE_001)
        IF @estadoResultado = 1 AND (@idTipoDestino <> @idTipoActual OR @numeroDestino <> @numeroActual)
        BEGIN
            SET @codigoRechazo =
                CASE
                    WHEN @permitido IS NULL OR @permitido <> 1 THEN 'IDE_003'
                    WHEN @motivoNormalizado IS NULL OR LEN(@motivoNormalizado) > 500 THEN 'IDE_001'
                END;

            IF @codigoRechazo IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- PASO 5: tipo existente, numero valido (VAL_001) y unico excluyendo al propio usuario (lectura con bloqueo)
            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_validar_tipo_identificacion_exista_por_id_interno
                    @idTipoId = @idTipoDestino,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1 AND dbo.ufn_validar_numero(@numeroDestino) = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1 AND EXISTS (
                SELECT 1 FROM dbo.Usuario WITH (UPDLOCK, HOLDLOCK)
                WHERE tipoIdIdentificacion = @idTipoDestino AND numeroIdentificacion = @numeroDestino AND id <> @idUsuario)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ERR_UNICIDAD_DOCUMENTO',
                    @p_param1 = @numeroDestino,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- PASO 6: escritura (salvo @soloValidar = 1)
            IF @estadoResultado = 1 AND @soloValidar = 0
            BEGIN
                UPDATE dbo.Usuario
                SET tipoIdIdentificacion = @idTipoDestino,
                    numeroIdentificacion = @numeroDestino
                WHERE id = @idUsuario;
            END

            SET @documentoCambiado = @estadoResultado;
        END
    END TRY
    BEGIN CATCH
        -- PASO 7: error no controlado (SYS_001). Sin transaccion propia: la revierte el llamador
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SET @documentoCambiado = 0;
    END CATCH
END;
GO
