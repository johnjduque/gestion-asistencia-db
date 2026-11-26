USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 15 (2026-11-26): cobertura que faltaba segun la re-auditoria de la rama refactor/skills-bd
-- (informes/AUDITORIA_BD_SKILLS_2026-11-26_rama_skills-bd.md). Solo pruebas: no cambia ningun objeto.
--   SKL15_V01_VISTAS_FINAS_COLUMNAS  las 29 vistas finas que crearon los lotes 5-14 existen y exponen exactamente las columnas
--                                    que leen sus SP (en el mismo orden)
--   SKL15_V02_VISTAS_FINAS_FILAS     cada vista fina devuelve las mismas filas que su tabla base (no filtra ni duplica)
--   SKL15_V03_VISTAS_FINAS_SECRETOS  ninguna vista fina expone hash de token, PIN ni contrasena (el runtime tiene SELECT sobre uv_%)
--   SKL15_I01_NOMBRES_USUARIO        usp_actualizar_nombres_usuario_interno: cambia solo los nombres que llegan, no toca correo,
--                                    documento ni estado, y un usuario inexistente no escribe nada (triplete OK)
--   SKL15_I02_AUDITORIA_IDENTIDAD    usp_registrar_auditoria_identidad_interno: registra el evento con motivo, identidad anterior y
--                                    nueva; motivo en blanco queda NULL
--   SKL15_I03_AUDITORIA_JSON_INVALIDO identidad anterior que no es JSON: relanza el error original (13609) con la transaccion
--                                    del llamador condenada y no deja el evento
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote15_cobertura';

-- Vistas: uv_administrador_registro, uv_archivo_soporte_registro, uv_asignatura_registro, uv_asistencia_registro, uv_aviso_sesion_sin_toma, uv_detalle_asistencia_registro, uv_estado_notificacion, uv_estudiante_grupo_registro, uv_estudiante_programa_registro, uv_estudiante_programa_semestre, uv_evaluacion_alerta_grupo, uv_facultad_registro, uv_grupo_registro, uv_horario_registro, uv_notificacion_saliente, uv_parametro_edicion_registro, uv_parametro_registro, uv_periodo_academico_fechas, uv_programa_registro, uv_receso_academico_registro, uv_revision_cancelacion_registro, uv_sesion_cancelacion, uv_sesion_procedencia_clasificacion_registro, uv_sesion_registro, uv_sincronizacion_parametro_externo_registro, uv_solicitud_revision_asistencia_registro, uv_solicitud_sesion_registro, uv_token_matricula_grupo_registro, uv_toma_asistencia_registro
DECLARE @esperadas TABLE (vista SYSNAME PRIMARY KEY, columnas NVARCHAR(MAX) NOT NULL);
INSERT INTO @esperadas (vista, columnas) VALUES
    (N'uv_administrador_registro', N'id,idUsuario,idInstitucion'),
    (N'uv_archivo_soporte_registro', N'id,idUsuarioPropietario,idSolicitudRevisionAsistencia,nombreOriginal,tipoContenido,tamanioBytes,checksumSha256,estado,fechaRegistroUtc,fechaAdjuncionUtc,fechaCambioEstadoUtc,idCorrelacionRegistro,idCorrelacionAdjuncion'),
    (N'uv_asignatura_registro', N'id,codigo,nombre,credito,idArea,idComponente,estado,horasSemanales'),
    (N'uv_asistencia_registro', N'id,idEstudianteGrupo,idSesion'),
    (N'uv_aviso_sesion_sin_toma', N'idSesion,fechaAvisoUtc,totalCoordinadoresAvisados,idCorrelacion'),
    (N'uv_detalle_asistencia_registro', N'id,codigo,idAsistencia,asistio,idRazonCausa,fechaHoraInicio,fechaHoraFin,idToma,registradoPorEstudiante,fechaRegistroUtc'),
    (N'uv_estado_notificacion', N'id,codigo,nombre,esTerminal'),
    (N'uv_estudiante_grupo_registro', N'id,idEstado,idEstudiante,idGrupo'),
    (N'uv_estudiante_programa_registro', N'id,idEstudiante,idPrograma'),
    (N'uv_estudiante_programa_semestre', N'id,idEstudiante,idPrograma,semestreActual'),
    (N'uv_evaluacion_alerta_grupo', N'idGrupo,fechaCorteUtc,idCorrelacionUltima,totalEvaluaciones'),
    (N'uv_facultad_registro', N'id,nombre,idInstitucion,idDecano,estado'),
    (N'uv_grupo_registro', N'id,idAsignatura,idPeriodoAcademico,codigo,nombre,cantidadEstudiantes,cantidadEstudiantesFinalizaron,cantidadEstudiantesCancelaronVoluntadPropia,cantidadEstudiantesCancelaronAutomaticamente,idDocente'),
    (N'uv_horario_registro', N'id,idGrupo,idDia,horaInicio,horaFin'),
    (N'uv_notificacion_saliente', N'id,tipo,asunto,mensaje,destinatarios,datos,idEstado,intentos,creadoEn,proximoIntentoEn,reservadoHasta,reservadoPor,entregadoEn,codigoError,detalleError,idCorrelacion,traceId,spanId'),
    (N'uv_parametro_edicion_registro', N'idParametro,esEditable,valorMinimo,valorMaximo,valoresPermitidos,idParametroDebeSerMenorQue,etiqueta,descripcion,unidad,categoriaVisual,orden,formato'),
    (N'uv_parametro_registro', N'id,grupo,clave,valor,tipoDato,valorDefecto,estaActivo,fechaCreacion,fechaModificacion'),
    (N'uv_periodo_academico_fechas', N'id,idInstitucion,nombre,codigo,fechaInicio,fechaFin,anio,fechaCierreUtc'),
    (N'uv_programa_registro', N'id,nombre,idFacultad,idTipoPrograma,idCoordinador,estado,idModalidad,idJornada'),
    (N'uv_receso_academico_registro', N'id,idPeriodoAcademico,fecha,motivo,estaActivo,fechaCreacionUtc,idUsuarioCreador,idCorrelacion'),
    (N'uv_revision_cancelacion_registro', N'id,idEstudianteGrupo,idEstado,idAlertaOrigen,fechaCreacionUtc,fechaActualizacionUtc,porcentajeCreacion,horasFaltaCreacion,horasDictadasCreacion,idCorrelacionCreacion,codigoDecisionDocente,motivoDocente,idUsuarioDecisionDocente,porcentajeDecisionDocente,fechaDecisionDocenteUtc,codigoPerfilResolutorActual,huellaResolutoresActual,fechaEscalamientoUtc,codigoDecisionResolucion,motivoResolucion,idUsuarioResolucion,codigoPerfilResolucion,idProgramaResolucion,porcentajeResolucion,fechaResolucionUtc,idEstadoMatriculaAnterior'),
    (N'uv_sesion_cancelacion', N'idSesion,idTipoCancelacion,motivo,idDiaFestivo,idRecesoAcademico,idUsuarioEjecutor,fechaCancelacionUtc,idCorrelacion'),
    (N'uv_sesion_procedencia_clasificacion_registro', N'id,idSesion,ambiente,idManifiesto,hashEvidencia,procedenciaAnterior,procedenciaNueva,fechaHoraInicioAnterior,fechaHoraFinAnterior,fechaHoraInicioUtc,fechaHoraFinUtc,idUsuarioEjecutor,idUsuarioAprobador,idCorrelacion,fechaRegistro'),
    (N'uv_sesion_registro', N'id,nombre,numero,codigo,numeroSemana,idGrupo,fechaHoraInicio,fechaHoraFin,procedenciaTemporal'),
    (N'uv_sincronizacion_parametro_externo_registro', N'id,idEvento,idParametro,grupo,clave,operacion,resultado,ocurridoEnUtc,idCorrelacion,fechaRegistroUtc'),
    (N'uv_solicitud_revision_asistencia_registro', N'id,nombre,idAsistencia,fecha,idEstado,justificacionSolicitud,justificacionRespuesta,idCategoriaJustificacion,idToma,idRazonCausaResolucion'),
    (N'uv_solicitud_sesion_registro', N'idSesion,idEstado,idUsuarioSolicitante,fechaSolicitudUtc,idUsuarioResolucion,fechaResolucionUtc,observacion,idCorrelacion'),
    (N'uv_token_matricula_grupo_registro', N'id,idGrupo,idDocenteEmisor,estado,fechaEmisionUtc,fechaRotacionUtc,fechaExpiracionUtc,fechaCierreUtc,totalMatriculas,idProgramaPorDefecto'),
    (N'uv_toma_asistencia_registro', N'id,idSesion,numero,idModo,idEstado,esImplicita,idDocenteApertura,fechaAperturaUtc,fechaCierreUtc,totalAusentesMarcados,idCorrelacionApertura,idCorrelacionCierre');

DECLARE @difColumnas NVARCHAR(MAX) = N'';
SELECT @difColumnas = CONCAT(@difColumnas, N' ', e.vista, N'=[', IIF(r.columnas IS NULL, N'NO EXISTE', r.columnas), N']')
FROM @esperadas e
LEFT JOIN (
    SELECT v.name AS vista, STRING_AGG(CONVERT(NVARCHAR(MAX), c.name), N',') WITHIN GROUP (ORDER BY c.column_id) AS columnas
    FROM sys.views v INNER JOIN sys.columns c ON c.object_id = v.object_id
    WHERE SCHEMA_NAME(v.schema_id) = N'dbo'
    GROUP BY v.name
) r ON r.vista = e.vista
WHERE r.columnas IS NULL OR r.columnas <> e.columnas;
IF @difColumnas <> N''
BEGIN
    DECLARE @m1 NVARCHAR(2048) = LEFT(CONCAT(N'TEST FAILED: SKL15_V01_VISTAS_FINAS_COLUMNAS', @difColumnas), 2048);
    THROW 56500, @m1, 1;
END
PRINT 'TEST_PASS:SKL15_V01_VISTAS_FINAS_COLUMNAS';

DECLARE @difFilas NVARCHAR(MAX) = N'';
IF (SELECT COUNT_BIG(1) FROM dbo.uv_administrador_registro) <> (SELECT COUNT_BIG(1) FROM dbo.Administrador) SET @difFilas = CONCAT(@difFilas, N' uv_administrador_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_archivo_soporte_registro) <> (SELECT COUNT_BIG(1) FROM dbo.ArchivoSoporte) SET @difFilas = CONCAT(@difFilas, N' uv_archivo_soporte_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_asignatura_registro) <> (SELECT COUNT_BIG(1) FROM dbo.Asignatura) SET @difFilas = CONCAT(@difFilas, N' uv_asignatura_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_asistencia_registro) <> (SELECT COUNT_BIG(1) FROM dbo.Asistencia) SET @difFilas = CONCAT(@difFilas, N' uv_asistencia_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_aviso_sesion_sin_toma) <> (SELECT COUNT_BIG(1) FROM dbo.AvisoSesionSinToma) SET @difFilas = CONCAT(@difFilas, N' uv_aviso_sesion_sin_toma');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_detalle_asistencia_registro) <> (SELECT COUNT_BIG(1) FROM dbo.DetalleAsistencia) SET @difFilas = CONCAT(@difFilas, N' uv_detalle_asistencia_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_estado_notificacion) <> (SELECT COUNT_BIG(1) FROM dbo.EstadoNotificacion) SET @difFilas = CONCAT(@difFilas, N' uv_estado_notificacion');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_estudiante_grupo_registro) <> (SELECT COUNT_BIG(1) FROM dbo.EstudianteGrupo) SET @difFilas = CONCAT(@difFilas, N' uv_estudiante_grupo_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_estudiante_programa_registro) <> (SELECT COUNT_BIG(1) FROM dbo.EstudiantePrograma) SET @difFilas = CONCAT(@difFilas, N' uv_estudiante_programa_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_estudiante_programa_semestre) <> (SELECT COUNT_BIG(1) FROM dbo.EstudiantePrograma) SET @difFilas = CONCAT(@difFilas, N' uv_estudiante_programa_semestre');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_evaluacion_alerta_grupo) <> (SELECT COUNT_BIG(1) FROM dbo.EvaluacionAlertaGrupo) SET @difFilas = CONCAT(@difFilas, N' uv_evaluacion_alerta_grupo');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_facultad_registro) <> (SELECT COUNT_BIG(1) FROM dbo.Facultad) SET @difFilas = CONCAT(@difFilas, N' uv_facultad_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_grupo_registro) <> (SELECT COUNT_BIG(1) FROM dbo.Grupo) SET @difFilas = CONCAT(@difFilas, N' uv_grupo_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_horario_registro) <> (SELECT COUNT_BIG(1) FROM dbo.Horario) SET @difFilas = CONCAT(@difFilas, N' uv_horario_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_notificacion_saliente) <> (SELECT COUNT_BIG(1) FROM dbo.NotificacionSaliente) SET @difFilas = CONCAT(@difFilas, N' uv_notificacion_saliente');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_parametro_edicion_registro) <> (SELECT COUNT_BIG(1) FROM dbo.CatalogoParametroEdicion) SET @difFilas = CONCAT(@difFilas, N' uv_parametro_edicion_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_parametro_registro) <> (SELECT COUNT_BIG(1) FROM dbo.CatalogoParametro) SET @difFilas = CONCAT(@difFilas, N' uv_parametro_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_periodo_academico_fechas) <> (SELECT COUNT_BIG(1) FROM dbo.PeriodoAcademico) SET @difFilas = CONCAT(@difFilas, N' uv_periodo_academico_fechas');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_programa_registro) <> (SELECT COUNT_BIG(1) FROM dbo.Programa) SET @difFilas = CONCAT(@difFilas, N' uv_programa_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_receso_academico_registro) <> (SELECT COUNT_BIG(1) FROM dbo.PeriodoRecesoAcademico) SET @difFilas = CONCAT(@difFilas, N' uv_receso_academico_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_revision_cancelacion_registro) <> (SELECT COUNT_BIG(1) FROM dbo.RevisionCancelacion) SET @difFilas = CONCAT(@difFilas, N' uv_revision_cancelacion_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_sesion_cancelacion) <> (SELECT COUNT_BIG(1) FROM dbo.SesionCancelacion) SET @difFilas = CONCAT(@difFilas, N' uv_sesion_cancelacion');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_sesion_procedencia_clasificacion_registro) <> (SELECT COUNT_BIG(1) FROM dbo.SesionProcedenciaClasificacion) SET @difFilas = CONCAT(@difFilas, N' uv_sesion_procedencia_clasificacion_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_sesion_registro) <> (SELECT COUNT_BIG(1) FROM dbo.Sesion) SET @difFilas = CONCAT(@difFilas, N' uv_sesion_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_sincronizacion_parametro_externo_registro) <> (SELECT COUNT_BIG(1) FROM dbo.SincronizacionParametroExterno) SET @difFilas = CONCAT(@difFilas, N' uv_sincronizacion_parametro_externo_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_solicitud_revision_asistencia_registro) <> (SELECT COUNT_BIG(1) FROM dbo.SolicitudRevisionAsistencia) SET @difFilas = CONCAT(@difFilas, N' uv_solicitud_revision_asistencia_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_solicitud_sesion_registro) <> (SELECT COUNT_BIG(1) FROM dbo.SesionSolicitud) SET @difFilas = CONCAT(@difFilas, N' uv_solicitud_sesion_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_token_matricula_grupo_registro) <> (SELECT COUNT_BIG(1) FROM dbo.TokenMatriculaGrupo) SET @difFilas = CONCAT(@difFilas, N' uv_token_matricula_grupo_registro');
IF (SELECT COUNT_BIG(1) FROM dbo.uv_toma_asistencia_registro) <> (SELECT COUNT_BIG(1) FROM dbo.TomaAsistencia) SET @difFilas = CONCAT(@difFilas, N' uv_toma_asistencia_registro');
IF @difFilas <> N''
BEGIN
    DECLARE @m2 NVARCHAR(2048) = LEFT(CONCAT(N'TEST FAILED: SKL15_V02_VISTAS_FINAS_FILAS', @difFilas), 2048);
    THROW 56501, @m2, 1;
END
PRINT 'TEST_PASS:SKL15_V02_VISTAS_FINAS_FILAS';

IF EXISTS (
    SELECT 1
    FROM sys.views v INNER JOIN sys.columns c ON c.object_id = v.object_id
    INNER JOIN @esperadas e ON e.vista = v.name
    WHERE c.name LIKE N'%tokenHash%' OR c.name LIKE N'pin%' OR c.name LIKE N'%password%' OR c.name LIKE N'%contrasena%'
)
    THROW 56502, 'TEST FAILED: SKL15_V03_VISTAS_FINAS_SECRETOS (una vista fina expone hash de token, PIN o contrasena)', 1;
PRINT 'TEST_PASS:SKL15_V03_VISTAS_FINAS_SECRETOS';
GO

DECLARE @u UNIQUEIDENTIFIER, @ejecutor UNIQUEIDENTIFIER;
SELECT TOP 1 @u = id FROM dbo.Usuario WHERE estado = 1 ORDER BY id;
SELECT TOP 1 @ejecutor = a.usuario FROM dbo.Administrador a ORDER BY a.usuario;
IF @u IS NULL OR @ejecutor IS NULL
    THROW 56510, 'TEST FAILED: SKL15 faltan fixtures del seed (usuario activo y administrador).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @antes TABLE (correo NVARCHAR(100), numeroIdentificacion INT, tipo UNIQUEIDENTIFIER, estado BIT, segundoNombre NVARCHAR(50),
                          primerApellido NVARCHAR(50), segundoApellido NVARCHAR(50));
    INSERT INTO @antes SELECT correo, numeroIdentificacion, tipoIdIdentificacion, estado, segundoNombre, primerApellido, segundoApellido
    FROM dbo.Usuario WHERE id = @u;

    -- SKL15_I01: solo el primer nombre llega; lo demas no cambia
    EXEC dbo.usp_actualizar_nombres_usuario_interno @idUsuario = @u, @primerNombre = N'NombreSKL15', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @@TRANCOUNT <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario x INNER JOIN @antes a
                        ON a.correo = x.correo AND a.numeroIdentificacion = x.numeroIdentificacion AND a.tipo = x.tipoIdIdentificacion
                       AND a.estado = x.estado AND a.segundoNombre = x.segundoNombre AND a.primerApellido = x.primerApellido
                       AND a.segundoApellido = x.segundoApellido
                      WHERE x.id = @u AND x.primerNombre = N'NombreSKL15')
        THROW 56511, 'TEST FAILED: SKL15_I01_NOMBRES_USUARIO (solo primer nombre)', 1;
    -- usuario inexistente: no escribe nada y no es error
    EXEC dbo.usp_actualizar_nombres_usuario_interno @idUsuario = '5C6A0000-0000-0000-0000-0000000000F1', @primerNombre = N'Nadie',
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE primerNombre = N'Nadie')
        THROW 56512, 'TEST FAILED: SKL15_I01_NOMBRES_USUARIO (usuario inexistente)', 1;
    PRINT 'TEST_PASS:SKL15_I01_NOMBRES_USUARIO';

    -- SKL15_I02: evento con motivo, anterior y nuevo
    DECLARE @anterior NVARCHAR(MAX) = N'{"primerNombre":"Anterior"}', @idRecurso UNIQUEIDENTIFIER = NEWID(), @corr2 UNIQUEIDENTIFIER = NEWID();
    EXEC dbo.usp_registrar_auditoria_identidad_interno @idUsuario = @u, @identidadAnterior = @anterior, @motivo = N'  Motivo SKL15  ',
         @accion = 'SKL15_CORREGIR', @tipoRecurso = 'USUARIO', @idRecurso = @idRecurso, @ruta = N'/skl15', @idUsuarioEjecutor = @ejecutor,
         @idCorrelacion = @corr2, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @@TRANCOUNT <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento e
                      WHERE e.correlationId = @corr2 AND e.action = 'SKL15_CORREGIR' AND e.resourceId = CAST(@idRecurso AS NVARCHAR(120))
                        AND e.actorId = CAST(@ejecutor AS NVARCHAR(120)) AND e.result = 'SUCCESS' AND e.path = N'/skl15'
                        AND JSON_VALUE(e.metadata, '$.motivo') = N'Motivo SKL15'
                        AND JSON_VALUE(e.metadata, '$.anterior.primerNombre') = N'Anterior'
                        AND JSON_VALUE(e.metadata, '$.nuevo.primerNombre') = N'NombreSKL15')
        THROW 56513, 'TEST FAILED: SKL15_I02_AUDITORIA_IDENTIDAD (evento)', 1;
    -- motivo en blanco => NULL
    DECLARE @corr3 UNIQUEIDENTIFIER = NEWID();
    EXEC dbo.usp_registrar_auditoria_identidad_interno @idUsuario = @u, @identidadAnterior = @anterior, @motivo = N'   ',
         @accion = 'SKL15_CORREGIR', @tipoRecurso = 'USUARIO', @idRecurso = @idRecurso, @ruta = N'/skl15', @idUsuarioEjecutor = @ejecutor,
         @idCorrelacion = @corr3, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento e WHERE e.correlationId = @corr3 AND JSON_VALUE(e.metadata, '$.motivo') IS NULL)
        THROW 56514, 'TEST FAILED: SKL15_I02_AUDITORIA_IDENTIDAD (motivo en blanco)', 1;
    PRINT 'TEST_PASS:SKL15_I02_AUDITORIA_IDENTIDAD';

    -- SKL15_I03: identidad anterior que no es JSON => el error condena la transaccion del llamador y el interno relanza el error
    -- original (Msg 13609) a la fachada, sin escribir el evento. Va al final porque deja la transaccion condenada.
    DECLARE @corr4 UNIQUEIDENTIFIER = NEWID(), @errorRelanzado INT = 0;
    BEGIN TRY
        EXEC dbo.usp_registrar_auditoria_identidad_interno @idUsuario = @u, @identidadAnterior = N'no es json', @motivo = N'x',
             @accion = 'SKL15_CORREGIR', @tipoRecurso = 'USUARIO', @idRecurso = @idRecurso, @ruta = N'/skl15', @idUsuarioEjecutor = @ejecutor,
             @idCorrelacion = @corr4, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    END TRY
    BEGIN CATCH
        SET @errorRelanzado = ERROR_NUMBER();
    END CATCH
    IF @errorRelanzado <> 13609 OR XACT_STATE() <> -1
        THROW 56515, 'TEST FAILED: SKL15_I03_AUDITORIA_JSON_INVALIDO (se esperaba Msg 13609 relanzado y transaccion condenada)', 1;
    ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corr4)
        THROW 56516, 'TEST FAILED: SKL15_I03_AUDITORIA_JSON_INVALIDO (escribio el evento)', 1;
    PRINT 'TEST_PASS:SKL15_I03_AUDITORIA_JSON_INVALIDO';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
PRINT 'TEST END: test_skills_lote15_cobertura';
GO
