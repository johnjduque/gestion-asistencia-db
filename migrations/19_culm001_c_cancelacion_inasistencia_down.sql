USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 C.1 - Migracion 19 DOWN (CONTRACT §2.11, SUPUESTO-C-17, O-6): restaura el estado inmediatamente anterior a C (el de
-- integracion/CULM-001 con B2 aplicado).
--   1. Reporta las matriculas en CI por revision aprobada (no se revierten: se archivan las tablas, no se reactivan matriculas).
--   2. Archiva AlertaInasistencia, RevisionCancelacion y RevisionCancelacionHistorial en zz_archivo_*_culm001_c (sin FKs).
--   3. DROP de los SP, vistas y funciones de C.
--   4. Restaura LITERALMENTE usp_consultar_resumen_asistencia_grupo_docente_paginado (version B2, sin idPrograma) y
--      usp_ejecutar_cierre_masivo_periodo (version B.2, que B2 no toca).
--   5. DROP de las tablas en orden inverso.
--   6. Borra parametros, mensajes y plantillas de C solo si siguen en su valor por defecto; restaura el cuerpo anterior de las dos
--      ALERTA_*; cancela las notificaciones pendientes de los 4 tipos nuevos (FALLIDA_DEFINITIVA, DEC-010, nunca DELETE).
-- Orden de down entre paquetes: C (19) -> B2 (18, 17) -> B.2 (16) -> B.1 (15).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
IF OBJECT_ID(N'dbo.RevisionCancelacion', N'U') IS NOT NULL
    SELECT matriculasCanceladasPorRevisionAprobada = COUNT(1)
    FROM dbo.RevisionCancelacion r INNER JOIN dbo.EstadoRevisionCancelacion e ON e.id = r.estado WHERE e.cancelaMatricula = 1;
GO
-- 2. Archivo (sin FKs); idempotente: se reemplaza el archivo de una ejecucion anterior
IF OBJECT_ID(N'dbo.AlertaInasistencia', N'U') IS NOT NULL
BEGIN
    IF OBJECT_ID(N'dbo.zz_archivo_AlertaInasistencia_culm001_c', N'U') IS NOT NULL DROP TABLE dbo.zz_archivo_AlertaInasistencia_culm001_c;
    SELECT * INTO dbo.zz_archivo_AlertaInasistencia_culm001_c FROM dbo.AlertaInasistencia;
END
IF OBJECT_ID(N'dbo.RevisionCancelacion', N'U') IS NOT NULL
BEGIN
    IF OBJECT_ID(N'dbo.zz_archivo_RevisionCancelacion_culm001_c', N'U') IS NOT NULL DROP TABLE dbo.zz_archivo_RevisionCancelacion_culm001_c;
    SELECT * INTO dbo.zz_archivo_RevisionCancelacion_culm001_c FROM dbo.RevisionCancelacion;
END
IF OBJECT_ID(N'dbo.RevisionCancelacionHistorial', N'U') IS NOT NULL
BEGIN
    IF OBJECT_ID(N'dbo.zz_archivo_RevisionCancelacionHistorial_culm001_c', N'U') IS NOT NULL DROP TABLE dbo.zz_archivo_RevisionCancelacionHistorial_culm001_c;
    SELECT * INTO dbo.zz_archivo_RevisionCancelacionHistorial_culm001_c FROM dbo.RevisionCancelacionHistorial;
END
GO
-- 3. SP, vistas y funciones de C
IF OBJECT_ID(N'dbo.usp_evaluar_alertas_inasistencia_grupo', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_evaluar_alertas_inasistencia_grupo];
GO
IF OBJECT_ID(N'dbo.usp_consultar_grupos_pendientes_evaluacion_alertas', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_grupos_pendientes_evaluacion_alertas];
GO
IF OBJECT_ID(N'dbo.usp_consultar_alertas_estudiante', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_alertas_estudiante];
GO
IF OBJECT_ID(N'dbo.usp_decidir_revision_cancelacion', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_decidir_revision_cancelacion];
GO
IF OBJECT_ID(N'dbo.usp_resolver_revision_cancelacion', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_resolver_revision_cancelacion];
GO
IF OBJECT_ID(N'dbo.usp_consultar_audiencias_realtime_grupo', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_audiencias_realtime_grupo];
GO
IF OBJECT_ID(N'dbo.usp_consultar_revisiones_cancelacion_coordinador_paginado', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_revisiones_cancelacion_coordinador_paginado];
GO
IF OBJECT_ID(N'dbo.usp_consultar_revisiones_cancelacion_decano_paginado', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_revisiones_cancelacion_decano_paginado];
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_revision_cancelacion', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_destinatarios_revision_cancelacion];
GO
IF OBJECT_ID(N'dbo.usp_actualizar_resolutores_revisiones_cancelacion', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_actualizar_resolutores_revisiones_cancelacion];
GO
IF OBJECT_ID(N'dbo.uv_alerta_inasistencia', N'V') IS NOT NULL DROP VIEW [dbo].[uv_alerta_inasistencia];
GO
IF OBJECT_ID(N'dbo.uv_revision_cancelacion', N'V') IS NOT NULL DROP VIEW [dbo].[uv_revision_cancelacion];
GO
IF OBJECT_ID(N'dbo.uv_marca_inasistencia_estudiante_grupo', N'V') IS NOT NULL DROP VIEW [dbo].[uv_marca_inasistencia_estudiante_grupo];
GO
IF OBJECT_ID(N'dbo.uv_tipo_alerta_inasistencia', N'V') IS NOT NULL DROP VIEW [dbo].[uv_tipo_alerta_inasistencia];
GO
IF OBJECT_ID(N'dbo.uv_estado_alerta_inasistencia', N'V') IS NOT NULL DROP VIEW [dbo].[uv_estado_alerta_inasistencia];
GO
IF OBJECT_ID(N'dbo.uv_estado_revision_cancelacion', N'V') IS NOT NULL DROP VIEW [dbo].[uv_estado_revision_cancelacion];
GO
IF OBJECT_ID(N'dbo.uv_transicion_revision_cancelacion', N'V') IS NOT NULL DROP VIEW [dbo].[uv_transicion_revision_cancelacion];
GO
IF OBJECT_ID(N'dbo.ufn_umbral_alerta_inasistencia') IS NOT NULL DROP FUNCTION [dbo].[ufn_umbral_alerta_inasistencia];
GO
IF OBJECT_ID(N'dbo.ufn_revision_cancelacion_resolutores') IS NOT NULL DROP FUNCTION [dbo].[ufn_revision_cancelacion_resolutores];
GO

-- 4. Texto literal anterior a C (copiado de integracion/CULM-001 con B2 al iniciar el GREEN)
-- schema/stored-procedures/usp_consultar_resumen_asistencia_grupo_docente_paginado.sql (version B2)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_asistencia_grupo_docente_paginado (CULM-001 B.2, HU040/HU041; CONTRACT §2.8.4, §3.2.8, F-DOC-004)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001,
-- PAG_001, GRU_*, SEC_002). RBAC DOCENTE titular del grupo. Filas: columnas de uv_resumen_asistencia_estudiante_grupo
-- (indicadores por horas) + nombreCompletoEstudiante + totalRegistros, orden nombreCompletoEstudiante (sabana del docente:
-- el cliente no calcula porcentajes).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_asistencia_grupo_docente_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idGrupo           UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 50
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
            OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_grupo_exista_por_id_interno
            @idGrupo = @idGrupoDefecto, @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @idUsuarioDefecto, @idEntidadPadre = @idGrupoDefecto, @tipoEntidadPadre = 'GRUPO',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    SELECT
        idEstudianteGrupo              = r.idEstudianteGrupo,
        idEstudiante                   = r.idEstudiante,
        idGrupo                        = r.idGrupo,
        idAsignatura                   = r.idAsignatura,
        idPeriodoAcademico             = r.idPeriodoAcademico,
        codigoEstadoEstudiante         = r.codigoEstadoEstudiante,
        sesionesEjecutadas             = r.sesionesEjecutadas,
        asistencias                    = r.asistencias,
        faltasSinJustaCausa            = r.faltasSinJustaCausa,
        excusas                        = r.excusas,
        porcentajeInasistencia         = r.porcentajeInasistencia,
        codigoPermanencia              = r.codigoPermanencia,
        tomasDictadas                  = r.tomasDictadas,
        horasDictadas                  = r.horasDictadas,
        horasAsistidas                 = r.horasAsistidas,
        horasFalta                     = r.horasFalta,
        horasExcusa                    = r.horasExcusa,
        horasSinRegistro               = r.horasSinRegistro,
        porcentajeAsistenciaHoras      = r.porcentajeAsistenciaHoras,
        porcentajeExcusaHoras          = r.porcentajeExcusaHoras,
        porcentajeSinRegistroHoras     = r.porcentajeSinRegistroHoras,
        porcentajeInasistenciaSesiones = r.porcentajeInasistenciaSesiones,
        umbralAdvertencia              = r.umbralAdvertencia,
        umbralPerdida                  = r.umbralPerdida,
        sesionesAsistidas              = r.sesionesAsistidas,
        sesionesConFaltaSinJustaCausa  = r.sesionesConFaltaSinJustaCausa,
        sesionesConExcusa              = r.sesionesConExcusa,
        nombreCompletoEstudiante       = eg.nombreCompletoEstudiante,
        totalRegistros                 = COUNT(1) OVER()
    FROM dbo.uv_resumen_asistencia_estudiante_grupo r
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = r.idEstudianteGrupo
    WHERE r.idGrupo = @idGrupoDefecto
    ORDER BY eg.nombreCompletoEstudiante ASC, r.idEstudiante ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO

-- schema/stored-procedures/usp_ejecutar_cierre_masivo_periodo.sql (version B.2)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_ejecutar_cierre_masivo_periodo]
(
    @codigoPeriodo          NVARCHAR(50),
    @idActor                NVARCHAR(100),
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoPeriodoDefecto     NVARCHAR(50)     = TRIM(@codigoPeriodo);
    DECLARE @idActorDefecto           NVARCHAR(100)    = TRIM(@idActor);

    DECLARE @idPeriodoTarget               UNIQUEIDENTIFIER;
    DECLARE @idEstadoFinalizado            UNIQUEIDENTIFIER;
    DECLARE @idEstadoCanceladoInasistencia UNIQUEIDENTIFIER;
    DECLARE @totalEstudiantes              INT = 0;
    DECLARE @totalReprobados               INT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    -- REC3 (auditoria BD 2026-10-28): cualquier error o cancelacion del cliente revierte la transaccion completa.
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
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

        -- PASO 2: Buscar período académico objetivo consultando uv_periodo_academico
        IF @estadoResultado = 1
        BEGIN
            IF @codigoPeriodoDefecto IS NOT NULL AND @codigoPeriodoDefecto <> ''
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM [dbo].[uv_periodo_academico]
                WHERE nombre = @codigoPeriodoDefecto 
                   OR CAST(codigo AS NVARCHAR(50)) = @codigoPeriodoDefecto
                ORDER BY anio DESC;
            END

            IF @idPeriodoTarget IS NULL
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM [dbo].[uv_periodo_academico]
                ORDER BY anio DESC, codigo DESC;
            END

            IF @idPeriodoTarget IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'PeriodoAcademico',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Ejecución transaccional de Cierre Masivo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoFinalizado = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'F' ORDER BY id ASC;
            SELECT TOP 1 @idEstadoCanceladoInasistencia = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'CI' ORDER BY id ASC;

            BEGIN TRANSACTION;

            -- 1. Conteo de estudiantes procesados
            SELECT @totalEstudiantes = COUNT(eg.id)
            FROM dbo.EstudianteGrupo eg
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            WHERE g.periodoAcademico = @idPeriodoTarget;

            -- 3. Actualizar estudiantes con fallas críticas (>= 3 inasistencias en DetalleAsistencia) a Cancelado por Inasistencia
            ;WITH InasistenciasPorEstudiante AS (
                SELECT 
                    eg.estudiante,
                    eg.grupo,
                    -- CULM-001 B.2 (B-7): varias tomas ausentes de una misma sesion cuentan como una sesion (C lo reescribe por horas)
                    COUNT(DISTINCT a.sesion) AS totalFallas
                FROM dbo.DetalleAsistencia da
                INNER JOIN dbo.Asistencia a ON da.asistencia = a.id
                INNER JOIN dbo.EstudianteGrupo eg ON a.estudianteGrupo = eg.id
                INNER JOIN dbo.Sesion s ON a.sesion = s.id
                INNER JOIN dbo.Grupo g ON s.grupo = g.id
                WHERE g.periodoAcademico = @idPeriodoTarget
                  AND da.asistio = 0
                GROUP BY eg.estudiante, eg.grupo
                HAVING COUNT(DISTINCT a.sesion) >= 3
            )
            UPDATE eg
            SET eg.estado = @idEstadoCanceladoInasistencia
            FROM dbo.EstudianteGrupo eg
            INNER JOIN InasistenciasPorEstudiante ipe 
                ON eg.estudiante = ipe.estudiante AND eg.grupo = ipe.grupo
            WHERE eg.estado = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');

            SET @totalReprobados = @@ROWCOUNT;

            -- 4. Actualizar resto de estudiantes activos a Finalizado
            UPDATE eg
            SET eg.estado = @idEstadoFinalizado
            FROM dbo.EstudianteGrupo eg
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            WHERE g.periodoAcademico = @idPeriodoTarget
              AND eg.estado = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');

            -- 5. Actualizar contadores en tabla Grupo
            UPDATE g
            SET 
                cantidadEstudiantesFinalizaron = (
                    SELECT COUNT(1) FROM dbo.EstudianteGrupo eg 
                    WHERE eg.grupo = g.id AND eg.estado = @idEstadoFinalizado
                ),
                cantidadEstudiantesCancelaronAutomaticamente = (
                    SELECT COUNT(1) FROM dbo.EstudianteGrupo eg 
                    WHERE eg.grupo = g.id AND eg.estado = @idEstadoCanceladoInasistencia
                )
            FROM dbo.Grupo g
            WHERE g.periodoAcademico = @idPeriodoTarget;

            -- 6. Auditoría de evento
            INSERT INTO dbo.AuditoriaEvento (
                id, occurredAt, actorId, actorType, action,
                resourceType, resourceId, result, correlationId,
                httpMethod, path, httpStatus, metadata
            ) VALUES (
                NEWID(),
                SYSDATETIMEOFFSET(),
                CASE WHEN @idActorDefecto IS NOT NULL AND @idActorDefecto <> '' THEN @idActorDefecto ELSE 'ADMIN_SISTEMA' END,
                CASE WHEN @idActorDefecto IS NOT NULL AND @idActorDefecto <> '' THEN 'USER' ELSE 'SYSTEM' END,
                'CIERRE_MASIVO_PERIODO',
                'PeriodoAcademico',
                CAST(@idPeriodoTarget AS NVARCHAR(50)),
                'SUCCESS',
                @idCorrelacionDefecto,
                'POST',
                '/api/v1/admin/cierre-masivo',
                200,
                CONCAT('{"procesados":', @totalEstudiantes, ',"reprobadosPorFallas":', @totalReprobados, '}')
            );

            COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'CierreMasivoPeriodo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- REC3: solo se revierte si hay una transaccion viva (XACT_STATE <> 0); evita un segundo error en el CATCH.
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

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

IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
BEGIN
    IF OBJECT_ID(N'dbo.usp_consultar_resumen_asistencia_grupo_docente_paginado', N'P') IS NOT NULL
        GRANT EXECUTE ON [dbo].[usp_consultar_resumen_asistencia_grupo_docente_paginado] TO [rol_asistencias_runtime];
    IF OBJECT_ID(N'dbo.usp_ejecutar_cierre_masivo_periodo', N'P') IS NOT NULL
        GRANT EXECUTE ON [dbo].[usp_ejecutar_cierre_masivo_periodo] TO [rol_asistencias_runtime];
END
GO

-- 5. Tablas en orden inverso de dependencia
IF OBJECT_ID(N'dbo.RevisionCancelacionHistorial', N'U') IS NOT NULL DROP TABLE [dbo].[RevisionCancelacionHistorial];
GO
IF OBJECT_ID(N'dbo.RevisionCancelacion', N'U') IS NOT NULL DROP TABLE [dbo].[RevisionCancelacion];
GO
IF OBJECT_ID(N'dbo.AlertaInasistencia', N'U') IS NOT NULL DROP TABLE [dbo].[AlertaInasistencia];
GO
IF OBJECT_ID(N'dbo.EvaluacionAlertaGrupo', N'U') IS NOT NULL DROP TABLE [dbo].[EvaluacionAlertaGrupo];
GO
IF OBJECT_ID(N'dbo.TransicionRevisionCancelacion', N'U') IS NOT NULL DROP TABLE [dbo].[TransicionRevisionCancelacion];
GO
IF OBJECT_ID(N'dbo.EstadoRevisionCancelacion', N'U') IS NOT NULL DROP TABLE [dbo].[EstadoRevisionCancelacion];
GO
IF OBJECT_ID(N'dbo.EstadoAlertaInasistencia', N'U') IS NOT NULL DROP TABLE [dbo].[EstadoAlertaInasistencia];
GO
IF OBJECT_ID(N'dbo.TipoAlertaInasistencia', N'U') IS NOT NULL DROP TABLE [dbo].[TipoAlertaInasistencia];
GO

-- 6. Parametros, mensajes y plantillas de C (solo si conservan su valor por defecto) y notificaciones pendientes
DELETE FROM dbo.CatalogoParametro
WHERE ((grupo = 'ALERTA_INASISTENCIA' AND clave IN ('HABILITADA', 'LOTE_EVALUACION_AUTOMATICA', 'SOLAPE_MARCA_SEGUNDOS', 'MAXIMO_LECTURA_POR_SOLICITUD'))
    OR (grupo = 'REVISION_CANCELACION' AND clave IN ('MOTIVO_LONGITUD_MINIMA', 'MOTIVO_LONGITUD_MAXIMA'))
    OR (grupo = 'MATRICULA' AND clave IN ('ESTADO_CANCELADA_INASISTENCIA', 'ESTADO_FINALIZADA')))
  AND ISNULL(valor, N'') = ISNULL(valorDefecto, N'');
DELETE FROM dbo.CatalogoMensajeUsuario
WHERE codigo IN ('ALR_001', 'ALR_002', 'ALR_003', 'ALR_004', 'ALR_005', 'ALR_006', 'ALR_007', 'ALR_010', 'ALR_011', 'RCN_001', 'RCN_002', 'RCN_003', 'RCN_004', 'RCN_005',
                 'RCN_006', 'RCN_007', 'RCN_008', 'RCN_009', 'RCN_010', 'RCN_011', 'RCN_012', 'RCN_013', 'RCN_014', 'RCN_015');
DELETE FROM dbo.CatalogoMensajeTecnico
WHERE codigo IN ('ALR_001', 'ALR_002', 'ALR_003', 'ALR_004', 'ALR_005', 'ALR_006', 'ALR_007', 'ALR_010', 'ALR_011', 'RCN_001', 'RCN_002', 'RCN_003', 'RCN_004', 'RCN_005',
                 'RCN_006', 'RCN_007', 'RCN_008', 'RCN_009', 'RCN_010', 'RCN_011', 'RCN_012', 'RCN_013', 'RCN_014', 'RCN_015');

DECLARE @idFallidaDefinitiva UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_DEFINITIVA');
IF @idFallidaDefinitiva IS NOT NULL
    UPDATE n
    SET n.idEstado = @idFallidaDefinitiva,
        n.codigoError = 'TIPO_NOTIFICACION_RETIRADO',
        n.detalleError = N'CULM-001 C.1 revertido (migracion 19 down): plantilla retirada.'
    FROM dbo.NotificacionSaliente n
    INNER JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado
    WHERE n.tipo IN ('REVISION_CANCELACION_PENDIENTE', 'PROPUESTA_CANCELACION', 'CANCELACION_APROBADA', 'CANCELACION_RECHAZADA') AND e.esTerminal = 0;

DELETE FROM dbo.PlantillaNotificacion WHERE tipo IN ('REVISION_CANCELACION_PENDIENTE', 'PROPUESTA_CANCELACION', 'CANCELACION_APROBADA', 'CANCELACION_RECHAZADA') AND creadoPor IS NULL;
IF NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo IN ('REVISION_CANCELACION_PENDIENTE', 'PROPUESTA_CANCELACION', 'CANCELACION_APROBADA', 'CANCELACION_RECHAZADA'))
    DELETE FROM dbo.PlantillaNotificacionMarcador WHERE tipo IN ('REVISION_CANCELACION_PENDIENTE', 'PROPUESTA_CANCELACION', 'CANCELACION_APROBADA', 'CANCELACION_RECHAZADA');
DELETE FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'ALERTA_RIESGO_INASISTENCIA' AND marcador = 'limite';

-- Cuerpo anterior de las dos ALERTA_* (solo si conservan el texto por defecto de C)
UPDATE dbo.PlantillaNotificacion
SET cuerpo = N'Estimado(a) {estudiante}, se informa que acumula un {porcentaje}% de inasistencias en la asignatura {grupo}. Le recordamos que el límite institucional de inasistencia no justificada es del 20%.'
WHERE tipo = 'ALERTA_RIESGO_INASISTENCIA' AND idioma = 'es' AND version = 1
  AND cuerpo = N'Estimado(a) {estudiante}, se informa que acumula un {porcentaje}% de inasistencias en la asignatura {grupo}. Le recordamos que el límite institucional de inasistencia no justificada es del {limite}%.';
UPDATE dbo.PlantillaNotificacion
SET cuerpo = N'Estimado(a) {estudiante}, se informa que ha alcanzado el {porcentaje}% de inasistencias en la asignatura {grupo}, superando el límite institucional permitido. Por favor contacte a su docente o coordinación académica.'
WHERE tipo = 'ALERTA_PERDIDA_INASISTENCIA' AND idioma = 'es' AND version = 1
  AND cuerpo = N'Estimado(a) {estudiante}, se informa que ha alcanzado el {porcentaje}% de inasistencias en la asignatura {grupo}, superando el límite institucional permitido del {limite}%. Por favor contacte a su docente o coordinación académica.';
GO

PRINT CONCAT('MIGRACION 19 DOWN OK | AlertaInasistencia=', IIF(OBJECT_ID(N'dbo.AlertaInasistencia', N'U') IS NULL, 'retirada', 'presente'),
             ' | archivo=', IIF(OBJECT_ID(N'dbo.zz_archivo_RevisionCancelacion_culm001_c', N'U') IS NULL, 'ausente', 'presente'), ' | @@TRANCOUNT=', @@TRANCOUNT);
GO
