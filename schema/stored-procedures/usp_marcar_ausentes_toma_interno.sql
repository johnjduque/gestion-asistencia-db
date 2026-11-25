USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_marcar_ausentes_toma_interno (CULM-001 B.2; CONTRACT §2.8.2, DEC-013) - NUCLEO, no se concede EXECUTE.
-- SKILLS-BD lote 2 (2026-11-25): antes usp_internal_marcar_ausentes_toma (renombrado, D3); triplete OUTPUT, TRY/CATCH con SYS_001.
--
-- Inserta, en conjunto (sin iterar estudiante por estudiante), un detalle SJC en la toma para cada matricula ACTIVA
-- (MATRICULA/ESTADO_INSCRITA) del grupo que no tiene detalle en ella; crea antes la cabecera Asistencia que falte.
-- registradoPorEstudiante = 0 y fechaRegistroUtc = @fechaRegistroUtc (= fechaCierreUtc de la toma: asi uv_faltantes_toma
-- reconoce el SJC marcado al cerrar). Nunca sobrescribe un detalle existente. No abre transaccion: la del llamador, que ya
-- tiene bloqueadas la sesion y la toma. Codigo desde dbo.seq_detalle_asistencia_codigo.
-- Las lecturas de matriculas, cabeceras y sesion van a la tabla con UPDLOCK/HOLDLOCK (excepcion de lecturas con bloqueo):
-- son las filas que se van a escribir dentro de la transaccion del llamador. Los catalogos se leen por sus vistas.
-- Un error devuelve @estadoResultado = 0 con SYS_001 (el llamador lo relanza a su CATCH); si condeno la transaccion del llamador,
-- el CATCH relanza el error original.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_marcar_ausentes_toma_interno]
(
    @idToma                  UNIQUEIDENTIFIER,
    @idSesion                UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @fechaRegistroUtc        DATETIME2(0),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @totalMarcados           INT OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoActiva NVARCHAR(10);
    DECLARE @codigoSjc    NVARCHAR(10);
    DECLARE @idRazonSjc   UNIQUEIDENTIFIER;
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: respuesta inicial
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;
    SET @totalMarcados = 0;

    BEGIN TRY
        -- PASO 2: codigos de catalogo (matricula activa y razon SJC)
        SET @codigoActiva = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
        SET @codigoSjc = CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_SIN_JUSTA_CAUSA') AS NVARCHAR(10));
        SELECT @idRazonSjc = rc.id FROM dbo.uv_razon_causa rc WHERE rc.codigo = @codigoSjc;

        IF @idRazonSjc IS NULL OR @codigoActiva IS NULL
        BEGIN
            THROW 52520, 'CULM001_B2_CATALOGO_INCONSISTENTE: ASISTENCIA/CODIGO_RAZON_SIN_JUSTA_CAUSA o MATRICULA/ESTADO_INSCRITA no resuelven.', 1;
        END

        -- PASO 3: cabeceras de asistencia que falten
        INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
        SELECT NEWID(), eg.id, @idSesion
        FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.uv_estado_estudiante_grupo e ON e.id = eg.estado AND e.codigo = @codigoActiva
        WHERE eg.grupo = @idGrupo
          AND NOT EXISTS (SELECT 1 FROM dbo.Asistencia a WITH (UPDLOCK, HOLDLOCK) WHERE a.estudianteGrupo = eg.id AND a.sesion = @idSesion);

        -- PASO 4: detalle SJC en la toma para quien no tiene registro
        INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma,
                                           registradoPorEstudiante, fechaRegistroUtc)
        SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, 0, @idRazonSjc, s.fechaHoraInicio, s.fechaHoraFin, @idToma,
               0, @fechaRegistroUtc
        FROM dbo.Asistencia a WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK) ON eg.id = a.estudianteGrupo
        INNER JOIN dbo.uv_estado_estudiante_grupo e ON e.id = eg.estado AND e.codigo = @codigoActiva
        INNER JOIN dbo.Sesion s WITH (UPDLOCK, HOLDLOCK) ON s.id = a.sesion
        WHERE a.sesion = @idSesion
          AND eg.grupo = @idGrupo
          AND NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da WITH (UPDLOCK, HOLDLOCK) WHERE da.asistencia = a.id AND da.toma = @idToma);

        SET @totalMarcados = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        -- PASO 5: error. Sin transaccion propia: la revierte el llamador
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        -- Transaccion del llamador condenada: se relanza el error original a su CATCH (mismo comportamiento que antes del lote 2)
        IF XACT_STATE() = -1
        BEGIN
            THROW;
        END
        SET @totalMarcados = 0;
    END CATCH
END;
GO
