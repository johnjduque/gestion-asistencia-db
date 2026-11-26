USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_tomas_sesion (CULM-001 B.2, HU175; CONTRACT §2.8.4, §3.2.5 GET /sesiones/{id}/tomas)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 con el mensaje tecnico si la validacion
-- falla). RBAC DOCENTE + titularidad sobre la sesion (SES_001 / SEC_001 / SEC_002 / GEN_002).
-- Filas: una por toma de la sesion (uv_toma_asistencia, orden numero) con los datos de la sesion y su ventana
-- (uv_sesion_estado: ventanaAperturaUtc, ventanaCierreUtc, ventanaAbierta, estaSesionCancelada, motivoCancelacion) y
-- maximoTomas (TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION). Una sesion SIN tomas devuelve una fila con los datos de la sesion
-- y las columnas de la toma en NULL (el docente ve la ventana antes de abrir la primera toma).
-- PC (puntos de control): columnas al final (NULL en la fila sin tomas):
--   fechaPuntoControlUtc, ordenPuntoControl, minutosTramoAnterior, minutosTramoSiguiente (uv_toma_asistencia);
--   esEditable       = ventana de la sesion abierta (ATA D4: toda toma, abierta o cerrada, es editable mientras la ventana siga abierta);
--   editableHastaUtc = cierre de la ventana (fin + margen) para todas las tomas.
-- horasToma (1/n) queda OBSOLETO: se conserva por compatibilidad; las horas salen de usp_consultar_resumen_tomas_sesion.
-- ============================================================================
-- SKILLS-BD lote 12 (2026-11-26): DECLARE en la cabecera, PASO n, IF con BEGIN/END, lecturas por vistas uv_* (antes, las tablas)
-- y TRY/CATCH de lectura que relanza. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_tomas_sesion]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @maximoTomas          INT = dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'MAXIMO_TOMAS_POR_SESION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: Validar correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
        -- PASO 2: Validar parametros obligatorios (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        -- PASO 3: Validar perfil del ejecutor (DOCENTE)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
        -- PASO 4: Sesion existente
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
        -- PASO 5: Titularidad del docente sobre la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioDefecto, @idEntidadPadre = @idSesionDefecto, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END
        -- PASO 6: Rechazo de validacion: se lanza con el detalle tecnico
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 7: Sesion con sus tomas (una fila sin tomas)
        SELECT
            idSesion              = se.idSesion,
            idGrupo               = se.idGrupo,
            numeroSesion          = se.numero,
            horasSesion           = se.horasSesion,
            estaSesionCancelada   = se.estaCancelada,
            motivoCancelacion     = se.motivoCancelacion,
            ventanaAperturaUtc    = se.ventanaAperturaUtc,
            ventanaCierreUtc      = se.ventanaCierreUtc,
            ventanaAbierta        = se.ventanaAbierta,
            maximoTomas           = @maximoTomas,
            totalTomasSesion      = se.totalTomas,
            idToma                = t.idToma,
            numero                = t.numero,
            idModo                = t.idModo,
            codigoModo            = t.codigoModo,
            nombreModo            = t.nombreModo,
            usaCodigoQr           = t.usaCodigoQr,
            marcaAusentesAlCerrar = t.marcaAusentesAlCerrar,
            idEstado              = t.idEstado,
            codigoEstado          = t.codigoEstado,
            nombreEstado          = t.nombreEstado,
            estaAbierta           = t.estaAbierta,
            esImplicita           = t.esImplicita,
            idDocenteApertura     = t.idDocenteApertura,
            fechaAperturaUtc      = t.fechaAperturaUtc,
            fechaCierreUtc        = t.fechaCierreUtc,
            totalAusentesMarcados = t.totalAusentesMarcados,
            horasToma             = t.horasToma,
            totalRegistros        = t.totalRegistros,
            totalPresentes        = t.totalPresentes,
            totalAusentes         = t.totalAusentes,
            totalExcusas          = t.totalExcusas,
            tieneQrActivo         = t.tieneQrActivo,
            fechaPuntoControlUtc  = t.fechaPuntoControlUtc,
            ordenPuntoControl     = t.ordenPuntoControl,
            minutosTramoAnterior  = t.minutosTramoAnterior,
            minutosTramoSiguiente = t.minutosTramoSiguiente,
            esEditable            = CAST(IIF(t.idToma IS NULL, NULL, IIF(se.ventanaAbierta = 1, 1, 0)) AS BIT),
            editableHastaUtc      = CAST(IIF(t.idToma IS NULL, NULL, se.ventanaCierreUtc) AS DATETIME2(7))
        FROM dbo.uv_sesion_estado se
        LEFT JOIN dbo.uv_toma_asistencia t ON t.idSesion = se.idSesion
        WHERE se.idSesion = @idSesionDefecto
        ORDER BY t.numero ASC;
    END TRY
    BEGIN CATCH
        -- PASO 8: consulta de lectura (READ_QUERY_RESULTSET): el error, incluido el rechazo de validacion,
        -- se propaga al llamador, que lo traduce a SYS_001 (sin triplete propio).
        THROW;
    END CATCH
END;
GO
