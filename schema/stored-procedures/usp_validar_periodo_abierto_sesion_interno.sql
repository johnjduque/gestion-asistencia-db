USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_validar_periodo_abierto_sesion_interno (VAL-pendientes-john PRU-15; decision del responsable 2026-11-18)
--
-- Regla de "periodo cerrado": un periodo academico queda CERRADO cuando usp_ejecutar_cierre_masivo_periodo lo cierra con exito
-- (PeriodoAcademico.fechaCierreUtc no nula). Desde ese momento no se admiten tomas nuevas ni cambios de tomas, lotes de asistencia
-- ni reclamos nuevos o cambios de reclamos de sus sesiones: este nucleo responde PER_008 (con el nombre del periodo) si la sesion
-- pertenece a un grupo de un periodo cerrado. Que el periodo haya terminado por fecha (uv_periodo_academico.estado = CERRADO) NO lo
-- cierra: entre fechaFin y el cierre masivo se pueden terminar reclamos y correcciones.
-- Consumidores: usp_validar_sesion_ventana_registro_interno (abrir toma, abrir QR, lotes por toma y por sesion, registro por token),
-- usp_cerrar_toma_asistencia, usp_radicar_solicitud_revision_interno (v2, v3 y v4), usp_radicar_solicitud_revision_asistencia (v1),
-- usp_resolver_solicitud_revision_asistencia y usp_retirar_solicitud_revision_asistencia.
-- Una sesion inexistente no se rechaza aqui (la existencia la valida el llamador). Sin escrituras ni transacciones; en exito deja
-- intactos los mensajes y @estadoResultado. No recibe GRANT del runtime.
-- ============================================================================
-- SKILLS-BD lote 9 (2026-11-26): PASO n, periodo por uv_sesion/uv_grupo_registro/uv_periodo_academico_fechas (antes, las tablas) y TRY/CATCH (relanza con transaccion abierta). Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_periodo_abierto_sesion_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT            OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPeriodo            UNIQUEIDENTIFIER;
    DECLARE @nombrePeriodo        NVARCHAR(500);
    DECLARE @fechaCierreUtc       DATETIME2(7);
    DECLARE @textoFechaCierre     NVARCHAR(40);
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: Periodo de la sesion (sesion -> grupo -> periodo)
        SELECT TOP 1 @idPeriodo = pa.id, @nombrePeriodo = pa.nombre, @fechaCierreUtc = pa.fechaCierreUtc
        FROM dbo.uv_sesion s
        INNER JOIN dbo.uv_grupo_registro g ON g.id = s.idGrupo
        INNER JOIN dbo.uv_periodo_academico_fechas pa ON pa.id = g.idPeriodoAcademico
        WHERE s.id = @idSesion;

        -- PASO 2: Periodo cerrado: PER_008. Abierto (o sesion inexistente): no toca las salidas, como antes
        IF @fechaCierreUtc IS NOT NULL
        BEGIN
            SET @textoFechaCierre = CONVERT(NVARCHAR(40), @fechaCierreUtc, 126);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PER_008',
                @p_param1 = @nombrePeriodo,
                @p_param2 = @textoFechaCierre,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Periodo: ', @idPeriodo, ' Sesion: ', @idSesion,
                                                  ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        -- PASO 3: corre dentro de la transaccion del llamador: con transaccion abierta relanza para que el llamador revierta
        -- (comportamiento previo, sin TRY); sin transaccion devuelve el triplete SYS_001.
        IF XACT_STATE() <> 0
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
END;
GO
