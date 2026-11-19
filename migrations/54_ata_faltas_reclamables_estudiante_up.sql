-- ============================================================================
-- MIGRACION UP 54: ATA D10 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS J.1), faltas por reclamar del estudiante
--   1. Vista uv_falta_reclamable_estudiante: tomas reclamables (esReclamable = 1) de sesiones ya avisadas, con matricula activa.
--   2. usp_consultar_faltas_reclamables_estudiante: consulta paginada del propio estudiante (RBAC ESTUDIANTE).
--   3. EXECUTE del rol runtime. Sin cambios de tablas. Idempotente. Down: 54_ata_faltas_reclamables_estudiante_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 54 UP: ATA D10 (faltas reclamables del estudiante)';
GO
-- ---- schema/views/uv_falta_reclamable_estudiante.sql
-- ATA D10 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS J.1): una fila por (matricula activa, toma reclamable) de sesiones ya avisadas por correo.
-- Es uv_asistencia_toma_estudiante con esReclamable = 1 (marca SJC, sin solicitud no retirada, sesion no cancelada, plazo vigente) unida a
-- AvisoFaltaSesion (la sesion ya tiene su aviso) y a la matricula en estado MATRICULA/ESTADO_INSCRITA. La lista se vacia sola cuando el
-- estudiante radica el reclamo, vence el plazo o el docente corrige la marca. fechaLimiteReclamoUtc usa el mismo criterio de esReclamable
-- (ufn_calcular_fecha_limite_justificacion sobre el fin de la sesion). idUsuarioEstudiante sirve al ambito dentro del SP de consulta.
CREATE OR ALTER VIEW [dbo].[uv_falta_reclamable_estudiante]
AS
SELECT  idUsuarioEstudiante = e.usuario,
        idEstudianteGrupo = t.idEstudianteGrupo,
        idGrupo = g.id,
        nombreGrupo = g.nombre,
        idAsignatura = asig.id,
        nombreAsignatura = asig.nombre,
        idSesion = s.id,
        numeroSesion = s.numero,
        fechaHoraInicioUtc = s.fechaHoraInicio,
        fechaHoraFinUtc = s.fechaHoraFin,
        idToma = t.idToma,
        numeroToma = t.numeroToma,
        fechaPuntoControlUtc = t.fechaPuntoControlUtc,
        fechaLimiteReclamoUtc = dbo.ufn_calcular_fecha_limite_justificacion(s.fechaHoraFin)
FROM    dbo.uv_asistencia_toma_estudiante t
INNER JOIN dbo.AvisoFaltaSesion av ON av.sesion = t.idSesion
INNER JOIN dbo.EstudianteGrupo eg ON eg.id = t.idEstudianteGrupo
INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
INNER JOIN dbo.Estudiante e ON e.id = eg.estudiante
INNER JOIN dbo.Sesion s ON s.id = t.idSesion
INNER JOIN dbo.Grupo g ON g.id = s.grupo
INNER JOIN dbo.Asignatura asig ON asig.id = g.asignatura
WHERE   t.esReclamable = 1
  AND   ee.codigo = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
GO
-- ---- schema/stored-procedures/usp_consultar_faltas_reclamables_estudiante.sql
-- ============================================================================
-- usp_consultar_faltas_reclamables_estudiante (ATA D10, HU026B; ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS J.1)
--
-- READ_QUERY_RESULTSET paginado (THROW 51000 si la validacion falla: correlacion, idUsuarioEjecutor GEN_002, RBAC ESTUDIANTE, PAG_001).
-- Solo las faltas reclamables del propio estudiante (uv_falta_reclamable_estudiante): tomas en SJC de sesiones ya avisadas, sin reclamo
-- radicado, con plazo vigente y matricula activa. Columnas de la vista sin idUsuarioEstudiante, mas totalRegistros (COUNT(*) OVER()).
-- Orden fechaHoraFinUtc DESC, numeroToma ASC.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_faltas_reclamables_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 20
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
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
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ESTUDIANTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    SELECT
        idEstudianteGrupo = f.idEstudianteGrupo, idGrupo = f.idGrupo, nombreGrupo = f.nombreGrupo,
        idAsignatura = f.idAsignatura, nombreAsignatura = f.nombreAsignatura,
        idSesion = f.idSesion, numeroSesion = f.numeroSesion, fechaHoraInicioUtc = f.fechaHoraInicioUtc, fechaHoraFinUtc = f.fechaHoraFinUtc,
        idToma = f.idToma, numeroToma = f.numeroToma, fechaPuntoControlUtc = f.fechaPuntoControlUtc, fechaLimiteReclamoUtc = f.fechaLimiteReclamoUtc,
        totalRegistros = COUNT(1) OVER()
    FROM dbo.uv_falta_reclamable_estudiante f
    WHERE f.idUsuarioEstudiante = @idUsuarioDefecto
    ORDER BY f.fechaHoraFinUtc DESC, f.numeroToma ASC, f.idToma ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
-- ---- schema/security/rol_asistencias_runtime_ata_d10.sql
-- ATA D10 (ADDENDUM_ATA_ASISTENCIA_TOMAS_AVISOS J.1): permiso del rol runtime sobre las faltas reclamables del estudiante. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_faltas_reclamables_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_faltas_reclamables_estudiante] TO [rol_asistencias_runtime];
GO
PRINT 'MIGRACION 54 UP OK';
GO
