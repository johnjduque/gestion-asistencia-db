:ON ERROR EXIT
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 B2NM - Migracion 17 DOWN (CONTRACT §2.3.2). Exige la columna Asignatura.semestrePlanEstudio (si no: 52903) y que cada
-- asignatura tenga EXACTAMENTE un vinculo, activo o inactivo (si no: 52902, sin cambios). Restaura el texto A+B de vistas y SP.
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
IF COL_LENGTH('dbo.Asignatura', 'semestrePlanEstudio') IS NULL
    THROW 52903, 'CULM-001 B2NM: la columna Asignatura.semestrePlanEstudio no existe; ejecute antes 18_culm001_b2nm_retirar_semestre_plan_down.sql.', 1;
IF OBJECT_ID('dbo.AsignaturaPlanEstudio', 'U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.Asignatura a WHERE (SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio x WHERE x.asignatura = a.id) <> 1)
BEGIN
    DECLARE @lista NVARCHAR(MAX) = (SELECT STRING_AGG(a.codigo, N', ') FROM dbo.Asignatura a WHERE (SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio x WHERE x.asignatura = a.id) <> 1);
    DECLARE @msg52902 NVARCHAR(2000) = CONCAT(N'CULM-001 B2NM: asignaturas con 0 o mas de 1 vinculo (activos e inactivos): ', LEFT(@lista, 1500));
    THROW 52902, @msg52902, 1;
END
GO
-- Restaura TODAS las filas desde el vinculo (durante la ventana un vinculo puede haber cambiado de semestre, O3-N2) y NOT NULL
EXEC sys.sp_executesql N'UPDATE a SET a.semestrePlanEstudio = x.semestrePlanEstudio FROM dbo.Asignatura a INNER JOIN dbo.AsignaturaPlanEstudio x ON x.asignatura = a.id;';
GO
EXEC sys.sp_executesql N'ALTER TABLE dbo.Asignatura ALTER COLUMN semestrePlanEstudio UNIQUEIDENTIFIER NOT NULL;';
GO
-- Elimina objetos nuevos que dependen de los modificados
DROP VIEW IF EXISTS dbo.uv_resumen_asistencia_estudiante_programa_grupo;
GO
DROP VIEW IF EXISTS dbo.uv_estudiante_grupo_programa;
GO
DROP VIEW IF EXISTS dbo.uv_asignatura_plan_estudio;
GO
DROP VIEW IF EXISTS dbo.uv_caracter_asignatura_plan;
GO

-- Restaura las versiones A+B de vistas y procedimientos
-- >>> views/uv_asignatura
-- CULM-001 B2NM (DEC-019): catalogo de asignaturas, 1 fila por asignatura. La pertenencia a planes vive en
-- uv_asignatura_plan_estudio (tabla puente AsignaturaPlanEstudio).
CREATE OR ALTER  VIEW [dbo].[uv_asignatura]
AS
SELECT		id = a.id,
			codigo = a.codigo,
			nombre = a.nombre,
			credito = a.credito,
			idArea = ar.id,
			nombreArea = ar.nombre,
			idComponente = co.id,
			nombreComponente = co.nombre,
			estaActivaAsignatura = a.estado,
			estaActivaTextoAsignatura = IIF(a.estado = 1, 'SI', 'NO'),
			totalPlanesActivos = (SELECT COUNT(*) FROM AsignaturaPlanEstudio x WHERE x.asignatura = a.id AND x.estaActivo = 1)

FROM		Asignatura a
INNER JOIN	uv_area ar
ON			a.area = ar.id
INNER JOIN	uv_componente co
ON			a.componente = co.id
GO

-- >>> views/uv_grupo_programa
-- HU078 / CULM-001 B2NM (DEC-019, R5): relacion grupo -> programas por la tabla puente (ufn_programas_grupo, regla S1).
-- GRANO 1:N por (grupo, programa): todo consumidor que cuente o pagine grupos, sesiones o estudiantes debe usar EXISTS o
-- DISTINCT sobre la clave de negocio. El plan es el del programa con vinculo vigente; si hay varios: activo primero,
-- mayor inp, menor id. PlanEstudio.estado = 0 NO saca un grupo de la vista (conserva la historia, O-N10).
CREATE OR ALTER VIEW [dbo].[uv_grupo_programa]
AS
SELECT  idGrupo = g.id,
        idPrograma = pg.idPrograma,
        idPeriodoAcademico = g.idPeriodoAcademico,
        grupoEstaHablitado = g.grupoEstaHablitado,
        idPlanEstudio = pg.idPlanEstudio,
        inpPlanEstudio = pg.inpPlanEstudio
FROM    uv_grupo g
CROSS APPLY dbo.ufn_programas_grupo(g.id) pg
GO

-- >>> views/uv_docente
-- CULM-001 B2NM: programa y plan desde uv_grupo_programa. Grano 1 por (docente, grupo, programa del grupo).
CREATE OR ALTER    VIEW	[dbo].[uv_docente]
AS
SELECT		di.id,
			di.idUsuario,
			di.numeroIdentificacion,
			di.nombreCompleto,
			di.estaActivoUsuario,

			idInstitucion = pr.idInstitucion,
			nombreInstitucion = pr.nombreInstitucion,

			idFacultad = pr.idFacultad,
			nombreFacultad = pr.nombreFacultad,
			idPrograma = pr.id,
			nombrePrograma = pr.nombrePrograma,

			idPlanEstudio = gp.idPlanEstudio,
			inpPlanEstudio = gp.inpPlanEstudio,
			idAsignatura = a.id,
			nombreAsignatura = a.nombre,
			idGrupo = g.id,
			nombreGrupo = g.nombre,

			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,

			estaActivoDocente = IIF(di.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 1, 0),
			estaActivoTextoDocente = IIF(di.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 'SI', 'NO')

FROM		uv_docente_identidad di
INNER JOIN	uv_grupo g
ON			di.id = g.idDocente
INNER JOIN	uv_asignatura a
ON			g.idAsignatura = a.id
INNER JOIN	uv_grupo_programa gp
ON			gp.idGrupo = g.id
INNER JOIN	uv_programa pr
ON			gp.idPrograma = pr.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'DO') p
GO

-- >>> views/uv_estudiante
-- CULM-001 B2NM (DEC-020, R6): 1 fila por (estudiante, grupo, programa del grupo); ya no exige EstudiantePrograma.
-- tieneVinculoPrograma = 1 cuando el estudiante tiene EstudiantePrograma en ese programa.
CREATE OR ALTER     VIEW	[dbo].[uv_estudiante]
AS
SELECT		ei.id,
			ei.idUsuario,
			ei.numeroIdentificacion,
			ei.nombreCompleto,
			ei.estaActivoUsuario,

			idInstitucion = pr.idInstitucion,
			nombreInstitucion = pr.nombreInstitucion,

			idFacultad = pr.idFacultad,
			nombreFacultad = pr.nombreFacultad,
			idPrograma = pr.id,
			nombrePrograma = pr.nombrePrograma,

			idPlanEstudio = gp.idPlanEstudio,
			inpPlanEstudio = gp.inpPlanEstudio,
			idAsignatura = a.id,
			nombreAsignatura = a.nombre,
			idGrupo = g.id,
			nombreGrupo = g.nombre,

			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,

			estaActivoEstudiante = IIF(ei.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 1, 0),
			estaActivoTextoEstudiante = IIF(ei.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 'SI', 'NO'),
			tieneVinculoPrograma = CAST(IIF(EXISTS (SELECT 1 FROM EstudiantePrograma ep WHERE ep.estudiante = ei.id AND ep.programa = pr.id), 1, 0) AS BIT)

FROM		uv_estudiante_identidad ei
INNER JOIN	uv_estudiante_grupo eg
ON			ei.id = eg.idEstudiante
INNER JOIN	uv_grupo g
ON			eg.idGrupo = g.id
INNER JOIN	uv_asignatura a
ON			g.idAsignatura = a.id
INNER JOIN	uv_grupo_programa gp
ON			gp.idGrupo = g.id
INNER JOIN	uv_programa pr
ON			gp.idPrograma = pr.id
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'ES') p
GO

-- >>> views/uv_estudiante_programa
-- CULM-001 B2NM: 1 fila por EstudiantePrograma, construida desde el vinculo y la identidad (ya no desde uv_estudiante).
CREATE OR ALTER  VIEW [dbo].[uv_estudiante_programa]
AS
SELECT  id = ep.id,

        idEstudiante = e.id,
        nombreEstudiante = e.nombreCompleto,
        idPrograma = p.id,
        nombrePrograma = p.nombrePrograma,
        estaActivoUsuario = e.estaActivoUsuario

FROM		EstudiantePrograma ep
INNER JOIN	uv_estudiante_identidad e
ON          ep.estudiante = e.id
INNER JOIN	uv_programa p
ON          ep.programa = p.id
GO

-- >>> views/uv_auth_grupo
CREATE OR ALTER VIEW [dbo].[uv_auth_grupo]
AS
SELECT  g.id,
        g.idPeriodoAcademico,
        g.fechaInicioPeriodoAcademico,
        g.fechaFinPeriodoAcademico,
        g.idAsignatura,
        g.nombreAsignatura,
        g.idDocente,
        g.codigo,
        g.nombre,
        g.capacidadMaximaPermitida,
        g.estudiantesActivos,
        g.estudiantesFinalizados,
        g.estudiantesCanceladosVoluntad,
        g.estudiantesCanceladosInasistencia,
        g.cuposDisponibles,
        g.grupoEstaHablitado,
        g.grupoEstaHablitadoTexto
FROM    dbo.uv_grupo g
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            -- CULM-001 B2NM: ambito por EXISTS sobre los programas del grupo (uv_grupo_programa 1:N); sigue siendo 1 fila por grupo.
            EXISTS (
            SELECT 1 FROM dbo.uv_grupo_programa gp
            INNER JOIN dbo.Programa pr ON pr.id = gp.idPrograma
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            INNER JOIN dbo.Administrador adm ON adm.institucion = f.institucion
            WHERE gp.idGrupo = g.id AND adm.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.uv_grupo_programa gp
            INNER JOIN dbo.Programa pr ON pr.id = gp.idPrograma
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            INNER JOIN dbo.Decano d ON f.decano = d.id
            WHERE gp.idGrupo = g.id AND d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.uv_grupo_programa gp
            INNER JOIN dbo.Programa pr ON pr.id = gp.idPrograma
            INNER JOIN dbo.Coordinador c ON pr.coordinador = c.id
            WHERE gp.idGrupo = g.id AND c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND g.idDocente = doc.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Estudiante e INNER JOIN dbo.EstudianteGrupo eg ON e.id = eg.estudiante WHERE e.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND eg.grupo = g.id
        )
        );
GO

-- >>> views/uv_auth_programa
-- CULM-001 B2NM: programa del grupo por uv_grupo_programa (tabla puente, S1) en lugar de Asignatura.semestrePlanEstudio.
CREATE OR ALTER VIEW [dbo].[uv_auth_programa]
AS
SELECT  p.id,
        p.nombrePrograma,
        p.estado,
        p.idFacultad,
        p.nombreFacultad,
        p.idInstitucion,
        p.nombreInstitucion,
        p.idCoordinador,
        p.nombreCoordinador,
        p.estaActivoPrograma,
        p.estaActivoTextoPrograma,
        p.idTipoPrograma,
        p.nombreTipoPrograma,
        p.idModalidad,
        p.nombreModalidad,
        p.idJornada,
        p.nombreJornada
FROM    dbo.uv_programa p
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = p.idInstitucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d INNER JOIN dbo.Facultad f ON d.id = f.decano WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.id = p.idFacultad
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND p.idCoordinador = c.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc
            INNER JOIN dbo.Grupo g ON doc.id = g.docente
            INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
            WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND gp.idPrograma = p.id
        )
        );
GO

-- >>> views/uv_auth_facultad
-- CULM-001 B2NM: programa del grupo por uv_grupo_programa (tabla puente, S1) en lugar de Asignatura.semestrePlanEstudio.
CREATE OR ALTER VIEW [dbo].[uv_auth_facultad]
AS
SELECT  f.id,
        f.nombreFacultad,
        f.idInstitucion,
        f.nombreInstitucion,
        f.idDecano,
        f.nombreCompletoDecano,
        f.estaActivaFacultad,
        f.estaActivaTextoFacultad
FROM    dbo.uv_facultad f
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = f.idInstitucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.idDecano = d.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c 
            INNER JOIN dbo.Programa pr ON c.id = pr.coordinador 
            WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.facultad = f.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc
            INNER JOIN dbo.Grupo g ON doc.id = g.docente
            INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
            INNER JOIN dbo.Programa pr ON gp.idPrograma = pr.id
            WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.facultad = f.id
        )
        );
GO

-- >>> views/uv_auth_institucion
-- CULM-001 B2NM: programa del grupo por uv_grupo_programa (tabla puente, S1) en lugar de Asignatura.semestrePlanEstudio.
CREATE OR ALTER VIEW [dbo].[uv_auth_institucion]
AS
SELECT  i.id,
        i.nombre,
        i.estaActivaInstitucion,
        i.estaActivaTextoInstitucion
FROM    dbo.uv_institucion i
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d 
            INNER JOIN dbo.Facultad f ON d.id = f.decano 
            WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c 
            INNER JOIN dbo.Programa pr ON c.id = pr.coordinador 
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc
            INNER JOIN dbo.Grupo g ON doc.id = g.docente
            INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
            INNER JOIN dbo.Programa pr ON gp.idPrograma = pr.id
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Estudiante e
            INNER JOIN dbo.EstudianteGrupo eg ON e.id = eg.estudiante
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
            INNER JOIN dbo.Programa pr ON gp.idPrograma = pr.id
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            WHERE e.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        )
        );
GO

-- >>> views/uv_auth_estudiante
-- CULM-001 B2NM (R6/R10): coordinador y decano exigen tieneVinculoPrograma = 1; administrador, docente titular y el propio estudiante no.
CREATE OR ALTER VIEW [dbo].[uv_auth_estudiante]
AS
SELECT  e.id,
        e.idUsuario,
        e.numeroIdentificacion,
        e.nombreCompleto,
        e.estaActivoUsuario,
        e.idInstitucion,
        e.nombreInstitucion,
        e.idFacultad,
        e.nombreFacultad,
        e.idPrograma,
        e.nombrePrograma,
        e.idPlanEstudio,
        e.inpPlanEstudio,
        e.idAsignatura,
        e.nombreAsignatura,
        e.idGrupo,
        e.nombreGrupo,
        e.idPerfil,
        e.codigoPerfil,
        e.nombrePerfil,
        e.estaActivoEstudiante,
        e.estaActivoTextoEstudiante,
        e.tieneVinculoPrograma
FROM    dbo.uv_estudiante e
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = e.idInstitucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano dec INNER JOIN dbo.Facultad f ON dec.id = f.decano WHERE e.tieneVinculoPrograma = 1 AND dec.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.id = e.idFacultad
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c INNER JOIN dbo.Programa pr ON c.id = pr.coordinador WHERE e.tieneVinculoPrograma = 1 AND c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.id = e.idPrograma
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc INNER JOIN dbo.Grupo g ON doc.id = g.docente WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND g.id = e.idGrupo
        )
   OR   e.idUsuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        );
GO

-- >>> views/uv_cumplimiento_sesion_grupo
-- HU065: una fila por sesion con su estado de cumplimiento (D4, D7). Consume uv_sesion_v2 (procedencia temporal) y
-- uv_grupo_programa; no altera las vistas congeladas.
-- CULM-001 B.1 (CONTRACT §2.6): una sesion cancelada (dbo.SesionCancelacion, por el docente o por festivo) sale de la
-- vista y con ello de sesionesProgramadas, vencidas, ejecutadas, cumplimiento, progreso de calendario y tendencia.
-- Columnas sin cambio.
-- CULM-001 B.2 (CONTRACT §2.6, [SUPUESTO-B-06]): tieneRegistroAsistencia = existe Asistencia O existe TomaAsistencia (una toma
-- QR abierta y cerrada sin lecturas cuenta como sesion ejecutada); columnas nuevas totalTomas y horasSesion.
-- CULM-001 B2NM: sin idPrograma (1 fila por sesion); el programa se resuelve con EXISTS uv_grupo_programa.
CREATE OR ALTER VIEW [dbo].[uv_cumplimiento_sesion_grupo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idPeriodoAcademico = g.idPeriodoAcademico,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaVencida = CAST(IIF(s.procedenciaTemporal IS NOT NULL AND s.fechaHoraFin <= SYSUTCDATETIME(), 1, 0) AS BIT),
        procedenciaIndeterminada = CAST(IIF(s.procedenciaTemporal IS NULL, 1, 0) AS BIT),
        tieneRegistroAsistencia = CAST(IIF(EXISTS (SELECT 1 FROM dbo.uv_asistencia a WHERE a.idSesion = s.id)
                                           OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id), 1, 0) AS BIT),
        totalTomas = (SELECT COUNT(1) FROM dbo.TomaAsistencia t WHERE t.sesion = s.id),
        horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_grupo g
ON      g.id = s.idGrupo
WHERE   NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id)
GO

-- >>> views/uv_resumen_asistencia_estudiante_grupo
-- HU066/HU067/HU069/HU070: una fila por matricula (EstudianteGrupo) con sus cifras de asistencia.
-- Denominador (D1): sesiones vencidas CON registro del grupo. Falta (D2): asistio = 0 con razon SJC; la excusa (EX) no cuenta.
-- CULM-001 B.2 (CONTRACT §2.6, §2.9, DEC-012, DEC-024, NB-2): inasistencia por HORAS conservando los nombres.
--   sesionesEjecutadas: sesiones vencidas, con registro (Asistencia o TomaAsistencia) y no canceladas (sin cambio de nombre).
--   asistencias / faltasSinJustaCausa / excusas: pasan a contar TOMAS (con una toma por sesion = sesiones, igual que antes).
--   tomasDictadas / horasDictadas: tomas y horas (ufn_horas_sesion) de esas mismas sesiones, sin mirar el estado de la toma.
--   horasAsistidas / horasFalta / horasExcusa: suma de uv_asistencia_sesion_horas en esas sesiones; horasSinRegistro =
--   horasDictadas - las tres (nunca negativo).
--   porcentajeInasistencia = ufn_calcular_porcentaje_inasistencia_horas(horasFalta, horasDictadas); codigoPermanencia sobre ese
--   porcentaje (ufn_clasificar_permanencia sin cambio). porcentajeInasistenciaSesiones = formula anterior por sesiones
--   (sesionesConFaltaSinJustaCausa / sesionesEjecutadas), solo trazabilidad. umbralAdvertencia / umbralPerdida: parametros.
--   sesionesAsistidas / sesionesConFaltaSinJustaCausa / sesionesConExcusa: sesiones por estado consolidado (consumidores
--   diferidos a D).
-- CULM-001 B2NM: sin idPrograma (1 fila por matricula); el resumen por programa es uv_resumen_asistencia_estudiante_programa_grupo.
CREATE OR ALTER VIEW [dbo].[uv_resumen_asistencia_estudiante_grupo]
AS
SELECT  idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        idGrupo = eg.idGrupo,
        idAsignatura = g.idAsignatura,
        idPeriodoAcademico = g.idPeriodoAcademico,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        sesionesEjecutadas = ISNULL(se.sesionesEjecutadas, 0),
        asistencias = ISNULL(de.asistencias, 0),
        faltasSinJustaCausa = ISNULL(de.faltas, 0),
        excusas = ISNULL(de.excusas, 0),
        porcentajeInasistencia = p.porcentaje,
        codigoPermanencia = dbo.ufn_clasificar_permanencia(p.porcentaje, eg.codigoEstadoEstudiante),
        tomasDictadas = ISNULL(se.tomasDictadas, 0),
        horasDictadas = hd.horasDictadas,
        horasAsistidas = hd.horasAsistidas,
        horasFalta = hd.horasFalta,
        horasExcusa = hd.horasExcusa,
        horasSinRegistro = hd.horasSinRegistro,
        porcentajeAsistenciaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasAsistidas, hd.horasDictadas),
        porcentajeExcusaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasExcusa, hd.horasDictadas),
        porcentajeSinRegistroHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasSinRegistro, hd.horasDictadas),
        porcentajeInasistenciaSesiones = CAST(IIF(ISNULL(se.sesionesEjecutadas, 0) = 0, 0,
                                                  100.0 * ISNULL(hs.sesionesConFalta, 0) / se.sesionesEjecutadas) AS DECIMAL(5,2)),
        umbralAdvertencia = u.umbralAdvertencia,
        umbralPerdida = u.umbralPerdida,
        sesionesAsistidas = ISNULL(hs.sesionesAsistidas, 0),
        sesionesConFaltaSinJustaCausa = ISNULL(hs.sesionesConFalta, 0),
        sesionesConExcusa = ISNULL(hs.sesionesConExcusa, 0)
FROM    dbo.uv_estudiante_grupo eg
INNER JOIN dbo.uv_grupo g
ON      g.id = eg.idGrupo
LEFT JOIN (
            SELECT  c.idGrupo,
                    sesionesEjecutadas = COUNT(*),
                    tomasDictadas = SUM(c.totalTomas),
                    horasDictadas = SUM(c.horasSesion)
            FROM    dbo.uv_cumplimiento_sesion_grupo c
            WHERE   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY c.idGrupo
          ) se
ON      se.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  v.idEstudianteGrupo,
                    asistencias = SUM(IIF(v.asistio = 1, 1, 0)),
                    faltas = SUM(IIF(v.asistio = 0 AND v.codigoRazonCausa = N'SJC', 1, 0)),
                    excusas = SUM(IIF(v.codigoRazonCausa = N'EX', 1, 0))
            FROM    dbo.uv_detalle_asistencia_v2 v
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = v.idSesion AND c.estaVencida = 1
            GROUP BY v.idEstudianteGrupo
          ) de
ON      de.idEstudianteGrupo = eg.id
LEFT JOIN (
            SELECT  h.idEstudianteGrupo,
                    horasAsistidas = SUM(h.horasAsistidas),
                    horasFalta = SUM(h.horasFalta),
                    horasExcusa = SUM(h.horasExcusa),
                    sesionesAsistidas = SUM(IIF(h.codigoRazonCausaConsolidado = N'AN', 1, 0)),
                    sesionesConFalta = SUM(IIF(h.tieneFaltaSinJustaCausa = 1, 1, 0)),
                    sesionesConExcusa = SUM(IIF(h.codigoRazonCausaConsolidado = N'EX', 1, 0))
            FROM    dbo.uv_asistencia_sesion_horas h
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = h.idSesion AND c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY h.idEstudianteGrupo
          ) hs
ON      hs.idEstudianteGrupo = eg.id
CROSS APPLY (
            SELECT  horasDictadas = CAST(ISNULL(se.horasDictadas, 0) AS DECIMAL(12,6)),
                    horasAsistidas = CAST(ISNULL(hs.horasAsistidas, 0) AS DECIMAL(12,6)),
                    horasFalta = CAST(ISNULL(hs.horasFalta, 0) AS DECIMAL(12,6)),
                    horasExcusa = CAST(ISNULL(hs.horasExcusa, 0) AS DECIMAL(12,6)),
                    horasSinRegistro = CAST(IIF(ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0) < 0, 0,
                                                ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0)) AS DECIMAL(12,6))
          ) hd
CROSS APPLY (SELECT porcentaje = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasFalta, hd.horasDictadas)) p
CROSS APPLY (
            SELECT  umbralAdvertencia = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA') AS NVARCHAR(20))), '') AS DECIMAL(5,2)),
                    umbralPerdida = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA') AS NVARCHAR(20))), '') AS DECIMAL(5,2))
          ) u;
GO

-- >>> stored-procedures/usp_buscar_estudiante_por_documento_grupo
-- ============================================================================
-- usp_buscar_estudiante_por_documento_grupo (CULM-001 A.2-15; DEC-027; F-DOC-013; CONTRACT §8.2.3 A2-DB-9)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo, fuera de ambito o documento
-- invalido). Busqueda del estudiante a matricular a mano (GET /api/v1/grupos/{grupoId}/estudiantes/busqueda) y unica via
-- para resolver el estudiante de una matricula manual sin correo:
--   * Titularidad dentro del SP: el ejecutor debe ser el DOCENTE titular del grupo (Grupo.docente -> Docente.usuario);
--     si no, o el grupo no existe: THROW 51000 con DBCODE=SEC_002 (403).
--   * Documento nulo o @numeroIdentificacion <= 0: THROW 51000 con DBCODE=VAL_001 (400).
--   * Busqueda EXACTA por (Usuario.tipoIdIdentificacion, Usuario.numeroIdentificacion) de un usuario CON fila Estudiante
--     (un usuario que solo es docente, coordinador, decano o administrador da 0 filas). Sin LIKE y sin listar: 0 o 1 fila.
--   * Alcance institucional: solo devuelve al estudiante si no tiene vinculos (alta pendiente de matricula; excepcion
--     deliberada al fail-closed de DEC-031 §3, A2-C1) o si alguno de sus vinculos (EstudiantePrograma o EstudianteGrupo)
--     es de la institucion del grupo. Uno de otra institucion da 0 filas, igual que uno inexistente.
--   * Datos minimos: nombres, nombreCompleto, numeroIdentificacion, correoEnmascarado (primer caracter + '***' +
--     '@dominio'; el correo real nunca sale) y codigoEstadoMatriculaGrupo (su matricula en ESE grupo o NULL).
-- Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_buscar_estudiante_por_documento_grupo]
(
    @idGrupo              UNIQUEIDENTIFIER,
    @idTipoIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion INT,
    @idCorrelacion        UNIQUEIDENTIFIER,
    @idUsuarioEjecutor    UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucionGrupo   UNIQUEIDENTIFIER;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 3: titularidad del docente ejecutor sobre el grupo (SEC_002)
    IF @estadoResultado = 1
       AND NOT EXISTS (SELECT 1 FROM dbo.Grupo g
                       INNER JOIN dbo.Docente d ON d.id = g.docente
                       INNER JOIN dbo.Usuario u ON u.id = d.usuario
                       WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor AND u.estado = 1)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SEC_002',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 4: documento obligatorio y positivo (VAL_001)
    IF @estadoResultado = 1 AND (@idTipoIdentificacion IS NULL OR @numeroIdentificacion IS NULL OR @numeroIdentificacion <= 0)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'numeroIdentificacion',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 5: institucion del grupo
    SELECT @idInstitucionGrupo = f.institucion
    FROM dbo.Grupo g
    INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
    INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = a.id AND ape.estaActivo = 1 INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
    INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
    INNER JOIN dbo.Programa p ON p.id = pe.programa
    INNER JOIN dbo.Facultad f ON f.id = p.facultad
    WHERE g.id = @idGrupo;

    -- PASO 6: busqueda exacta de un estudiante, con alcance institucional y datos minimos
    SELECT TOP 1
        idEstudiante               = e.id,
        primerNombre               = u.primerNombre,
        segundoNombre              = u.segundoNombre,
        primerApellido             = u.primerApellido,
        segundoApellido            = u.segundoApellido,
        nombreCompleto             = CAST(CONCAT(LTRIM(RTRIM(CONCAT(u.primerNombre, N' ', u.segundoNombre))), N' ',
                                         LTRIM(RTRIM(CONCAT(u.primerApellido, N' ', u.segundoApellido)))) AS NVARCHAR(400)),
        numeroIdentificacion       = u.numeroIdentificacion,
        correoEnmascarado          = CAST(IIF(CHARINDEX(N'@', u.correo) > 1,
                                         CONCAT(LEFT(u.correo, 1), N'***', SUBSTRING(u.correo, CHARINDEX(N'@', u.correo), LEN(u.correo))),
                                         CONCAT(LEFT(u.correo, 1), N'***')) AS NVARCHAR(120)),
        codigoEstadoMatriculaGrupo = (SELECT TOP 1 es.codigo FROM dbo.EstudianteGrupo eg
                                      INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.estado
                                      WHERE eg.estudiante = e.id AND eg.grupo = @idGrupo
                                      ORDER BY eg.id)
    FROM dbo.Usuario u
    INNER JOIN dbo.Estudiante e ON e.usuario = u.id
    WHERE u.tipoIdIdentificacion = @idTipoIdentificacion
      AND u.numeroIdentificacion = @numeroIdentificacion
      AND (
            -- sin vinculos: alta pendiente de matricula (A2-C1)
            (NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = e.id)
             AND NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg WHERE eg.estudiante = e.id))
            -- algun vinculo en la institucion del grupo
            OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                       INNER JOIN dbo.Programa p ON p.id = ep.programa
                       INNER JOIN dbo.Facultad f ON f.id = p.facultad
                       WHERE ep.estudiante = e.id AND f.institucion = @idInstitucionGrupo)
            OR EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg
                       INNER JOIN dbo.Grupo g ON g.id = eg.grupo
                       INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                       INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = a.id AND ape.estaActivo = 1 INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                       INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                       INNER JOIN dbo.Programa p ON p.id = pe.programa
                       INNER JOIN dbo.Facultad f ON f.id = p.facultad
                       WHERE eg.estudiante = e.id AND f.institucion = @idInstitucionGrupo)
          )
    ORDER BY e.id;
END;
GO

-- >>> stored-procedures/usp_consultar_asistencias_grupo_ambito_paginado
-- ============================================================================
-- usp_consultar_asistencias_grupo_ambito_paginado (CULM-001 A.2-2; F-COO-003; CONTRACT §8.2.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo o fuera de
-- ambito). Asistencias del grupo de GET /api/v1/grupos/{grupoId}/asistencias (WORM #4: columnas de
-- AsistenciaConsultadaDTO). INNER JOIN desde uv_detalle_asistencia / uv_asistencia (vistas congeladas, solo lectura):
-- "ausencia = sin fila" (§E). Filtro opcional por sesion.
-- Ambito validado ANTES de leer filas (ejecutor activo): DOCENTE titular y ADMINISTRADOR de la institucion del grupo ven
-- todas; COORDINADOR activo del programa del grupo solo las de los estudiantes con EstudiantePrograma en sus programas
-- (DEC-031 §4). Grupo inexistente o fuera de ambito: THROW 51000 con DBCODE=SEC_002 (403).
-- @tamanoPagina NULL = todas las filas (A2-C3); con valor, 1..100. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asistencias_grupo_ambito_paginado]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL, 2147483647, IIF(@tamanoPagina < 1, 1, IIF(@tamanoPagina > 100, 100, @tamanoPagina)));
    DECLARE @offset INT = IIF(@tamanoPagina IS NULL, 0, (@pagina - 1) * @tamano);
    DECLARE @ejecutorActivo BIT = 0;
    DECLARE @verTodos BIT = 0;
    DECLARE @esCoordinador BIT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 3: ambito del grupo, antes de leer filas
    IF @estadoResultado = 1
    BEGIN
        SET @ejecutorActivo = IIF(EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuarioEjecutor AND u.estado = 1), 1, 0);

        SET @verTodos = IIF(@ejecutorActivo = 1 AND (
                EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente
                        WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor)
             OR EXISTS (SELECT 1 FROM dbo.Grupo g
                        INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                        INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = a.id AND ape.estaActivo = 1 INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                        INNER JOIN dbo.Programa p ON p.id = pe.programa
                        INNER JOIN dbo.Facultad f ON f.id = p.facultad
                        INNER JOIN dbo.Administrador ad ON ad.institucion = f.institucion
                        WHERE g.id = @idGrupo AND ad.usuario = @idUsuarioEjecutor)), 1, 0);

        SET @esCoordinador = IIF(@ejecutorActivo = 1 AND EXISTS (
                -- CULM-001 B2NM (DEC-020): coordinador de algun programa del grupo, o decano de su facultad.
                SELECT 1 FROM dbo.Grupo g
                INNER JOIN dbo.uv_grupo_programa gpa ON gpa.idGrupo = g.id
                INNER JOIN dbo.Programa p ON p.id = gpa.idPrograma
                LEFT JOIN dbo.Coordinador c ON c.id = p.coordinador AND c.usuario = @idUsuarioEjecutor AND c.estado = 1
                LEFT JOIN dbo.Facultad fa ON fa.id = p.facultad
                LEFT JOIN dbo.Decano dc ON dc.id = fa.decano AND dc.usuario = @idUsuarioEjecutor
                WHERE g.id = @idGrupo AND (c.id IS NOT NULL OR dc.id IS NOT NULL)), 1, 0);

        IF @verTodos = 0 AND @esCoordinador = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: asistencias registradas del grupo (el coordinador, solo las de los estudiantes de sus programas)
    SELECT
        asistencia     = da.id,
        estudiante     = eg.idEstudiante,
        grupo          = eg.idGrupo,
        sesion         = a.idSesion,
        presente       = da.asistio,
        estado         = da.codigoRazonCausa,
        observacion    = CAST(N'' AS NVARCHAR(500)),
        totalRegistros = COUNT(*) OVER()
    FROM dbo.uv_detalle_asistencia da
    INNER JOIN dbo.uv_asistencia a ON a.id = da.idAsistencia
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = a.idEstudianteGrupo
    WHERE eg.idGrupo = @idGrupo
      AND (@idSesion IS NULL OR a.idSesion = @idSesion)
      AND (@verTodos = 1
           OR eg.id IN (SELECT v.idEstudianteGrupo FROM dbo.ufn_estudiantes_grupo_visibles(@idGrupo, @idUsuarioEjecutor) v))   -- CULM-001 B2NM R6
    ORDER BY a.idSesion ASC, eg.idEstudiante ASC, da.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_destinatarios_retiro_estudiante_grupo
-- ============================================================================
-- usp_consultar_destinatarios_retiro_estudiante_grupo  (HU051)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (los parametros invalidos se propagan con THROW).
-- Destinatarios del aviso de retiro: el ESTUDIANTE retirado, el DOCENTE titular del grupo y el COORDINADOR del
-- programa (Grupo -> Asignatura -> SemestrePlanEstudio -> PlanEstudio -> Programa.coordinador). Solo el docente
-- titular obtiene filas (otro ejecutor => 0 filas). No exige matricula activa: se consulta despues del retiro.
-- El correo es dato de uso interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_retiro_estudiante_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idEstudiante            UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    ;WITH contexto AS (
        SELECT g.id AS idGrupo, g.codigo AS codigoGrupo, g.nombre AS nombreGrupo, asg.nombre AS nombreAsignatura,
               d.usuario AS usuarioDocente, c.usuario AS usuarioCoordinador, e.usuario AS usuarioEstudiante
        FROM dbo.Grupo g
        INNER JOIN dbo.Docente d               ON d.id = g.docente
        INNER JOIN dbo.Asignatura asg          ON asg.id = g.asignatura
        INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = asg.id AND ape.estaActivo = 1 INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
        INNER JOIN dbo.PlanEstudio pe          ON pe.id = spe.planEstudio
        INNER JOIN dbo.Programa pr             ON pr.id = pe.programa
        INNER JOIN dbo.Coordinador c           ON c.id = pr.coordinador
        INNER JOIN dbo.EstudianteGrupo eg      ON eg.grupo = g.id AND eg.estudiante = @idEstudiante
        INNER JOIN dbo.Estudiante e            ON e.id = eg.estudiante
        WHERE g.id = @idGrupo AND d.usuario = @idUsuarioDefecto
          -- CULM-001 B2NM: coordinadores de los programas del estudiante que comparten el grupo
          AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma epx WHERE epx.estudiante = eg.estudiante AND epx.programa = pr.id)
    ),
    destinatarios AS (
        SELECT DISTINCT orden = 1, rolDestinatario = 'ESTUDIANTE', idUsuario = usuarioEstudiante, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
        UNION ALL
        SELECT DISTINCT 2, 'DOCENTE', usuarioDocente, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
        UNION ALL
        SELECT DISTINCT 3, 'COORDINADOR', usuarioCoordinador, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
    )
    SELECT
        rolDestinatario  = CAST(dst.rolDestinatario AS VARCHAR(20)),
        idUsuario        = dst.idUsuario,
        nombreCompleto   = CAST(CONCAT_WS(N' ',
                               NULLIF(TRIM(u.primerNombre), N''),
                               NULLIF(TRIM(u.segundoNombre), N''),
                               NULLIF(TRIM(u.primerApellido), N''),
                               NULLIF(TRIM(u.segundoApellido), N'')) AS NVARCHAR(400)),
        correo           = u.correo,
        idGrupo          = dst.idGrupo,
        codigoGrupo      = dst.codigoGrupo,
        nombreGrupo      = dst.nombreGrupo,
        nombreAsignatura = dst.nombreAsignatura
    FROM destinatarios dst
    INNER JOIN dbo.Usuario u ON u.id = dst.idUsuario
    ORDER BY dst.orden;
END;
GO

-- >>> stored-procedures/usp_consultar_estudiantes_grupo_ambito_paginado
-- ============================================================================
-- usp_consultar_estudiantes_grupo_ambito_paginado (CULM-001 A.2-2; F-COO-003; CONTRACT §8.2.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo o fuera de
-- ambito). Estudiantes del grupo de GET /api/v1/grupos/{grupoId}/estudiantes (WORM #3: columnas de EstudianteGrupoDTO),
-- en TODOS los estados (DR-007), orden nombreCompleto, id.
-- Ambito validado ANTES de leer filas (ejecutor activo):
--   * DOCENTE titular del grupo (Grupo.docente) y ADMINISTRADOR de la institucion del grupo: todos los estudiantes.
--   * COORDINADOR activo del programa del grupo (asignatura -> semestre -> plan -> programa): solo los estudiantes con
--     EstudiantePrograma en alguno de sus programas (DEC-031 §4; B2 completa la relacion N:M).
--   * Grupo inexistente o fuera de ambito: THROW 51000 con el mensaje tecnico de SEC_002 (DBCODE=SEC_002 -> 403).
-- @tamanoPagina NULL = todas las filas (A2-C3: el contrato WORM fija listas completas); con valor, 1..100. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_estudiantes_grupo_ambito_paginado]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL, 2147483647, IIF(@tamanoPagina < 1, 1, IIF(@tamanoPagina > 100, 100, @tamanoPagina)));
    DECLARE @offset INT = IIF(@tamanoPagina IS NULL, 0, (@pagina - 1) * @tamano);
    DECLARE @ejecutorActivo BIT = 0;
    DECLARE @verTodos BIT = 0;
    DECLARE @esCoordinador BIT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 3: ambito del grupo, antes de leer filas
    IF @estadoResultado = 1
    BEGIN
        SET @ejecutorActivo = IIF(EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuarioEjecutor AND u.estado = 1), 1, 0);

        SET @verTodos = IIF(@ejecutorActivo = 1 AND (
                EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente
                        WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor)
             OR EXISTS (SELECT 1 FROM dbo.Grupo g
                        INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                        INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = a.id AND ape.estaActivo = 1 INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
                        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                        INNER JOIN dbo.Programa p ON p.id = pe.programa
                        INNER JOIN dbo.Facultad f ON f.id = p.facultad
                        INNER JOIN dbo.Administrador ad ON ad.institucion = f.institucion
                        WHERE g.id = @idGrupo AND ad.usuario = @idUsuarioEjecutor)), 1, 0);

        SET @esCoordinador = IIF(@ejecutorActivo = 1 AND EXISTS (
                -- CULM-001 B2NM (DEC-020): coordinador de algun programa del grupo, o decano de su facultad.
                SELECT 1 FROM dbo.Grupo g
                INNER JOIN dbo.uv_grupo_programa gpa ON gpa.idGrupo = g.id
                INNER JOIN dbo.Programa p ON p.id = gpa.idPrograma
                LEFT JOIN dbo.Coordinador c ON c.id = p.coordinador AND c.usuario = @idUsuarioEjecutor AND c.estado = 1
                LEFT JOIN dbo.Facultad fa ON fa.id = p.facultad
                LEFT JOIN dbo.Decano dc ON dc.id = fa.decano AND dc.usuario = @idUsuarioEjecutor
                WHERE g.id = @idGrupo AND (c.id IS NOT NULL OR dc.id IS NOT NULL)), 1, 0);

        IF @verTodos = 0 AND @esCoordinador = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: estudiantes del grupo en todos los estados (el coordinador, solo los de sus programas)
    SELECT
        id             = eg.id,
        idEstudiante   = eg.idEstudiante,
        documento      = CAST(ei.numeroIdentificacion AS NVARCHAR(20)),
        nombreCompleto = CAST(ei.nombreCompleto AS NVARCHAR(400)),
        correo         = u.correo,
        codigoEstado   = eg.codigoEstadoEstudiante,
        nombreEstado   = eg.nombreEstadoEstudiante,
        totalRegistros = COUNT(*) OVER()
    FROM dbo.uv_estudiante_grupo eg
    INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante
    INNER JOIN dbo.uv_usuario u ON u.id = ei.idUsuario
    WHERE eg.idGrupo = @idGrupo
      AND (@verTodos = 1
           OR eg.id IN (SELECT v.idEstudianteGrupo FROM dbo.ufn_estudiantes_grupo_visibles(@idGrupo, @idUsuarioEjecutor) v))   -- CULM-001 B2NM R6
    ORDER BY ei.nombreCompleto ASC, eg.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- >>> stored-procedures/usp_consultar_reenvio_verificacion_correo
-- IDENT-001: elegibilidad del reenvio del enlace de verificacion. Valida RBAC (DOCENTE o COORDINADOR), ambito
-- (docente titular del grupo o coordinador del programa del grupo), que el estudiante pertenezca al grupo, que su correo
-- no este verificado (VCE_005) y la espera minima desde la ultima emision (VCE_003, parametro REENVIO_ESPERA_MINUTOS).
-- Devuelve una fila con el usuario del estudiante; el backend registra entonces el aviso. Los rechazos se propagan con
-- THROW 51000 y mensaje "DBCODE=<codigo>|..." (como usp_consultar_detalle_solicitud_revision_docente).
-- READ_QUERY_RESULTSET: NON_GOLDEN_PATH_EXTENSION (ver test/test_contract_closure.sql).
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_reenvio_verificacion_correo]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idEstudiante      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @enAmbito           BIT = 0;
    DECLARE @idUsuarioEstudiante UNIQUEIDENTIFIER;
    DECLARE @correoConfirmado    BIT;
    DECLARE @ultimaEmisionUtc    DATETIME2(0);
    DECLARE @esperaMinutos       INT;
    DECLARE @codigoRechazo       VARCHAR(20) = NULL;
BEGIN
    SET NOCOUNT ON;

    -- PASO 1: correlacion y ejecutor obligatorios
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idGrupo IS NULL OR @idEstudiante IS NULL)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idGrupo/idEstudiante',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 2: RBAC del ejecutor
    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioEjecutor,
            @codigoPerfilRequerido = 'DOCENTE,COORDINADOR',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    -- PASO 3: ambito jerarquico (titular del grupo o coordinador del programa del grupo) y pertenencia del estudiante
    IF @estadoResultado = 1
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM dbo.Grupo g
            INNER JOIN dbo.Docente d ON d.id = g.docente
            WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor
        )
        OR EXISTS (
            SELECT 1
            FROM dbo.Grupo g
            INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
            INNER JOIN dbo.AsignaturaPlanEstudio ape ON ape.asignatura = a.id AND ape.estaActivo = 1 INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = ape.semestrePlanEstudio
            INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
            INNER JOIN dbo.Programa pr ON pr.id = pe.programa
            INNER JOIN dbo.Coordinador c ON c.id = pr.coordinador
            WHERE g.id = @idGrupo AND c.usuario = @idUsuarioEjecutor
              AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma epx WHERE epx.estudiante = @idEstudiante AND epx.programa = pr.id)
        )
            SET @enAmbito = 1;

        SELECT @idUsuarioEstudiante = e.usuario
        FROM dbo.Estudiante e
        INNER JOIN dbo.EstudianteGrupo eg ON eg.estudiante = e.id AND eg.grupo = @idGrupo
        WHERE e.id = @idEstudiante;

        IF @enAmbito = 0 OR @idUsuarioEstudiante IS NULL
            SET @codigoRechazo = 'VCE_004';
    END

    -- PASO 4: correo aun sin verificar y espera minima
    IF @estadoResultado = 1 AND @codigoRechazo IS NULL
    BEGIN
        SELECT @correoConfirmado = u.correoConfirmado FROM dbo.Usuario u WHERE u.id = @idUsuarioEstudiante;

        IF @correoConfirmado = 1
            SET @codigoRechazo = 'VCE_005';
        ELSE
        BEGIN
            SET @esperaMinutos = dbo.ufn_obtener_parametro_int(NULL, 'VERIFICACION_CORREO', 'REENVIO_ESPERA_MINUTOS');
            SELECT @ultimaEmisionUtc = MAX(t.fechaEmisionUtc) FROM dbo.TokenVerificacionCorreo t WHERE t.usuario = @idUsuarioEstudiante;
            IF @ultimaEmisionUtc IS NOT NULL AND @ultimaEmisionUtc > DATEADD(MINUTE, -@esperaMinutos, SYSUTCDATETIME())
                SET @codigoRechazo = 'VCE_003';
        END
    END

    IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = @codigoRechazo,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT @idUsuarioEstudiante AS idUsuario;
END;
GO


-- Funciones nuevas (ya no las usa nada)
DROP FUNCTION IF EXISTS dbo.ufn_estudiantes_grupo_visibles;
GO
DROP FUNCTION IF EXISTS dbo.ufn_programas_ambito_ejecutor;
GO
DROP FUNCTION IF EXISTS dbo.ufn_programas_coordinador;
GO
DROP FUNCTION IF EXISTS dbo.ufn_programas_grupo;
GO

-- Borra los EstudiantePrograma creados por el backfill, los indices unicos, programaPorDefecto, la puente, el catalogo, el parametro y los mensajes
DELETE ep FROM dbo.EstudiantePrograma ep
WHERE EXISTS (SELECT 1 FROM dbo.zz_reporte_culm001_b2nm_estudiante_programa r WHERE r.tipo = N'CREADO' AND r.estudiante = ep.estudiante AND r.programa = ep.programa);
GO
DROP INDEX IF EXISTS UX_EstudiantePrograma_estudiante_programa ON dbo.EstudiantePrograma;
DROP INDEX IF EXISTS UX_Asignatura_codigo ON dbo.Asignatura;
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TokenMatriculaGrupo_Programa') ALTER TABLE dbo.TokenMatriculaGrupo DROP CONSTRAINT FK_TokenMatriculaGrupo_Programa;
GO
IF COL_LENGTH('dbo.TokenMatriculaGrupo', 'programaPorDefecto') IS NOT NULL ALTER TABLE dbo.TokenMatriculaGrupo DROP COLUMN programaPorDefecto;
GO
DROP TABLE IF EXISTS dbo.AsignaturaPlanEstudio;
DROP TABLE IF EXISTS dbo.CaracterAsignaturaPlan;
GO
DELETE FROM dbo.CatalogoParametro WHERE grupo = 'ASIGNATURA_PLAN' AND clave = 'CARACTER_DEFECTO';
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('ASI_002','ASI_003','ASI_004','ASI_005','ASI_006','ASI_007','EST_005','EST_006','MQR_008','COO_002','COO_003');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('ASI_002','ASI_003','ASI_004','ASI_005','ASI_006','ASI_007','EST_005','EST_006','MQR_008','COO_002','COO_003');
GO
-- zz_reporte_culm001_b2nm_estudiante_programa se conserva (solo lectura)
