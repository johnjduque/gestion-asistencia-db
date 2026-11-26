USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

PRINT '======================================================================';
PRINT '  DB QUALITY GATE - gestionasistenciadb';
PRINT '======================================================================';

-- CULM-001 B.2 ([SUPUESTO-B-20]): helper de pruebas (procedimientos temporales de la sesion) para la columna obligatoria
-- DetalleAsistencia.toma; lo usan las pruebas que insertan detalles o borran sesiones directamente.
:r /tmp/test/fixtures/culm001_b2_toma_fixture.sql
:r /tmp/test/test_culm001_b2nm_compilacion.sql
:r /tmp/test/test_culm001_b2nm_asignatura_plan.sql
:r /tmp/test/test_culm001_b2nm_ambito_grupo_mixto.sql
:r /tmp/test/test_culm001_b2nm_matricula.sql
:r /tmp/test/test_culm001_b2nm_oferta_y_decano.sql
:r /tmp/test/test_culm001_b2nm_coordinador_dos_programas.sql
:r /tmp/test/test_public_objects.sql
:r /tmp/test/test_contract_closure.sql
:r /tmp/test/test_usp_crear_facultad.sql
:r /tmp/test/test_usp_actualizar_facultad.sql
:r /tmp/test/test_usp_cambiar_estado_facultad.sql
:r /tmp/test/test_uv_tipo_programa_contrato.sql
:r /tmp/test/test_uv_area_contrato.sql
:r /tmp/test/test_user_dean_close.sql
:r /tmp/test/test_subject_catalog.sql
:r /tmp/test/test_rec2_rbac_asignatura.sql
-- HU074 (migracion 58): activar o inactivar asignaturas (ASI_009..ASI_012, @estaActivaDeseada idempotente, bordes de fecha) y efecto
-- del estado en grupos, planes y ofertas
:r /tmp/test/test_hu074_estado_asignatura.sql
-- SKILLS-BD lote 1 (2026-11-25): caracterizacion de 5 funciones, 10 vistas y 2 nucleos internos sin prueba directa
:r /tmp/test/test_skills_lote1_cobertura.sql
-- SKILLS-BD lote 2 (2026-11-25): nombres usp_*_interno, triplete OUTPUT de los nucleos y rechazos de los SP corregidos en el lote
:r /tmp/test/test_skills_lote2_caracterizacion.sql
-- SKILLS-BD lote 3 (2026-11-25): nucleos de usuario, validadores, mensajes, contexto y perfil por rol (parametros, usuarios e identidad)
:r /tmp/test/test_skills_lote3_caracterizacion.sql
-- SKILLS-BD lote 4 (2026-11-25): decano, facultad, coordinador y programas (vista uv_decano_rol, nucleos y resolvers)
:r /tmp/test/test_skills_lote4_caracterizacion.sql
-- SKILLS-BD lote 5 (2026-11-26): docentes y grupos (vinculos docente-programa, grupos y consultas por vistas uv_*)
:r /tmp/test/test_skills_lote5_caracterizacion.sql
-- SKILLS-BD lote 6 (2026-11-26): asignaturas y planes de estudio (validadores de asignatura y consultas por vistas uv_*)
:r /tmp/test/test_skills_lote6_caracterizacion.sql
-- SKILLS-BD lote 7 (2026-11-26): estudiantes y matricula en grupo (internos de estudiante y consultas por vistas uv_*)
:r /tmp/test/test_skills_lote7_caracterizacion.sql
-- SKILLS-BD lote 8 (2026-11-26): notificaciones (internos del outbox, avisos de falta y verificacion de correo)
:r /tmp/test/test_skills_lote8_caracterizacion.sql
-- SKILLS-BD lote 9 (2026-11-26): periodos, festivos y recesos (validadores de periodo y lecturas por vistas uv_*)
:r /tmp/test/test_skills_lote9_caracterizacion.sql
-- SKILLS-BD lote 10 (2026-11-26): indicadores y consultas (resolutores del periodo de los KPI)
:r /tmp/test/test_skills_lote10_caracterizacion.sql
-- SKILLS-BD lote 11 (2026-11-26): revisiones de cancelacion y reclamos (destinatarios del reclamo y lecturas por vistas uv_*)
:r /tmp/test/test_skills_lote11_caracterizacion.sql
-- SKILLS-BD lote 13 (2026-11-26): sesiones y horarios (validadores de sesion y de horario y lecturas por vistas uv_*)
:r /tmp/test/test_skills_lote13_caracterizacion.sql
-- SKILLS-BD lote 14 (2026-11-26): objetos congelados (validador de parametro externo y nucleo de actualizacion de sesion)
:r /tmp/test/test_skills_lote14_caracterizacion.sql
:r /tmp/test/test_reactive_academic.sql
:r /tmp/test/test_mass_period_close.sql
:r /tmp/test/test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql
:r /tmp/test/test_transaction_ownership.sql
-- VAL ROL-05 (migracion 39): usp_sincronizar_usuario retirado; reemplaza a test_usp_sincronizar_usuario.sql
:r /tmp/test/test_val_retiro_alta_usuarios_sin_ambito.sql
:r /tmp/test/test_val_oleada2_parametro_y_ambito.sql
-- VAL-oleada3 MSG-05 (migracion 41): mensajes de usuario del backend en el catalogo
:r /tmp/test/test_val_oleada3_mensajes_aplicacion.sql
-- VAL MSG-03 (migracion 42): mensajes ERR_* del backend en el catalogo
:r /tmp/test/test_val_mensajes_err_pendientes.sql
-- REA-02 (VAL-oleada9, migracion 47): mensaje del almacenamiento no disponible
:r /tmp/test/test_val_oleada9_mensaje_almacenamiento.sql
-- Mensaje ERR_BD_NO_DISPONIBLE (migracion 67)
:r /tmp/test/test_err_bd_no_disponible.sql
-- VAL oleada 3: PRU-14 (bordes del umbral de horas) y OBS-03 (procedimientos sin @idCorrelacion)
:r /tmp/test/test_val_umbral_horas_bordes.sql
-- VAL PRU-13 / decision 3A: borde del 20 % y del 15 % en la vista de resumen y el motor de alertas
:r /tmp/test/test_val_umbral_borde_alertas.sql
:r /tmp/test/test_val_obs03_id_correlacion.sql
:r /tmp/test/test_usp_registrar_o_actualizar_plan_estudio.sql
:r /tmp/test/test_usp_plan_estudio_estado_semestres.sql
:r /tmp/test/test_usp_periodo_academico_gestion.sql
:r /tmp/test/test_consultas_coordinador_programa.sql
:r /tmp/test/test_consultas_decano_facultad.sql
:r /tmp/test/test_consultas_transversales_hu112_hu157.sql
:r /tmp/test/test_consolidado_auditoria_catalogos.sql
:r /tmp/test/test_consultas_reclamos_estudiante.sql
:r /tmp/test/test_usp_retirar_estudiante_grupo.sql
:r /tmp/test/test_usp_consultar_perfil_usuario.sql
:r /tmp/test/test_runtime_grants_backend_inventory.sql
:r /tmp/test/test_usp_consultar_historial_grupos_docente_programa.sql
:r /tmp/test/test_usp_consultar_resumen_docentes_programa.sql
:r /tmp/test/test_hu008_regla_inscripcion_programa.sql
:r /tmp/test/test_int_hu01_reactivar_matricula_retirada.sql
:r /tmp/test/test_usp_crear_actualizar_grupo.sql
:r /tmp/test/test_dec076_dec077_creacion_grupo.sql
:r /tmp/test/test_usp_crear_actualizar_sesion.sql
:r /tmp/test/test_usp_validar_sesion_operacion_interno.sql
:r /tmp/test/test_maint_003k_error_priority.sql
:r /tmp/test/test_usp_generar_sesiones_grupo.sql
:r /tmp/test/test_group_capacity_decoupling.sql
:r /tmp/test/test_titularidad_jerarquica.sql
:r /tmp/test/test_attendance_commands.sql
:r /tmp/test/test_ses01_ventana_asistencia.sql
:r /tmp/test/test_attendance_review.sql
:r /tmp/test/test_ses04_reclamo_justificada.sql
:r /tmp/test/test_rec3_falla_intermedia_transaccion.sql
:r /tmp/test/test_lb004d_support_binding.sql
:r /tmp/test/test_usp_crear_coordinador.sql
:r /tmp/test/test_usp_actualizar_coordinador.sql
:r /tmp/test/test_usp_corregir_identidad_usuario.sql
:r /tmp/test/test_usp_cambiar_estado_coordinador.sql
:r /tmp/test/test_hu121_hu122_esquema_coordinador.sql
:r /tmp/test/test_sec_baseline_identidad_externa.sql
:r /tmp/test/test_migracion_docente_programa.sql
:r /tmp/test/test_usp_vincular_docente_programa.sql
:r /tmp/test/test_usp_consultar_docentes_programa.sql
:r /tmp/test/test_usp_consultar_candidatos_docente_programa.sql
:r /tmp/test/test_usp_actualizar_docente_programa.sql
:r /tmp/test/test_usp_cambiar_estado_docente_programa.sql
:r /tmp/test/test_cruce_horario_docente.sql
:r /tmp/test/test_usp_guardar_horarios_grupo.sql
:r /tmp/test/test_usp_consultar_oferta_creacion_grupo_docente.sql
:r /tmp/test/test_usp_precargar_sesiones_grupo.sql
:r /tmp/test/test_golden_path_immutability.sql
:r /tmp/test/test_utc_d06_readonly_contract.sql
:r /tmp/test/test_utc_d06_procedencia_temporal.sql
:r /tmp/test/test_authorized_views_rbac.sql
:r /tmp/test/test_usp_consultar_grupos_paginado.sql
:r /tmp/test/test_usp_crear_programa_academico.sql
:r /tmp/test/test_usp_actualizar_programa_academico.sql
:r /tmp/test/test_usp_cambiar_estado_programa_academico.sql
:r /tmp/test/test_usp_consultar_programas_academicos.sql
:r /tmp/test/test_uv_estudiante_programa_no_duplicates.sql
:r /tmp/test/test_usp_consultar_detalle_solicitud_revision_docente.sql
:r /tmp/test/test_usp_consultar_sesiones_y_asistencias_paginado.sql
:r /tmp/test/test_ufn_clasificar_permanencia.sql
:r /tmp/test/test_uv_resumen_asistencia_estudiante_grupo.sql
:r /tmp/test/test_usp_consultar_kpis_coordinador.sql
:r /tmp/test/test_usp_consultar_alerta_temprana_programa.sql
:r /tmp/test/test_usp_consultar_bitacora_estudiante_programa.sql
:r /tmp/test/test_usp_consultar_ficha_estudiante_programa.sql
:r /tmp/test/test_usp_resolvers_decano.sql
:r /tmp/test/test_usp_consultar_kpis_decano.sql
:r /tmp/test/test_usp_consultar_comparativa_programas_facultad.sql
:r /tmp/test/test_usp_consultar_aforo_grupos_facultad.sql
:r /tmp/test/test_usp_resolvers_institucion_admin.sql
:r /tmp/test/test_usp_consultar_kpis_institucion.sql
:r /tmp/test/test_usp_consultar_comparativa_facultades.sql
:r /tmp/test/test_usp_consultar_tendencia_ausentismo.sql
:r /tmp/test/test_usp_registrar_notificacion_saliente.sql
:r /tmp/test/test_usp_reservar_notificaciones_salientes.sql
:r /tmp/test/test_usp_marcar_notificacion_entregada.sql
:r /tmp/test/test_usp_registrar_fallo_notificacion.sql
:r /tmp/test/test_usp_depurar_notificaciones_salientes.sql
:r /tmp/test/test_notificacion_migracion_catalogo.sql
:r /tmp/test/test_notif002a_plantillas_contacto.sql
:r /tmp/test/test_ident001_correo_verificacion.sql
:r /tmp/test/test_ident002_activacion_cuentas.sql
:r /tmp/test/test_usp_abrir_ventana_matricula_grupo.sql
:r /tmp/test/test_usp_cerrar_ventana_matricula_grupo.sql
:r /tmp/test/test_usp_rotar_token_matricula_grupo.sql
:r /tmp/test/test_usp_validar_token_matricula_publico.sql
:r /tmp/test/test_usp_matricular_estudiante_por_token.sql
:r /tmp/test/test_dec078_matricula_programa_estudiante.sql
:r /tmp/test/test_semestre_estudiante_programa.sql
:r /tmp/test/test_culm001_a_retiro_solicitudes.sql
:r /tmp/test/test_culm001_a_correcciones.sql
:r /tmp/test/test_culm001_a_fixture_segundo_ambito.sql
-- CULM-001 B.1 (sesion cancelada, festivos y ventana con tolerancia): registro por nombre exacto (DEC-028)
:r /tmp/test/test_culm001_b1_ventana_tolerancia.sql
:r /tmp/test/test_culm001_b1_sesion_cancelada.sql
:r /tmp/test/test_culm001_b1_festivos.sql
-- CULM-001 B.2 (tomas por horas, QR de asistencia, faltantes y cierre): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_culm001_b2_tomas.sql
:r /tmp/test/test_culm001_b2_horas.sql
:r /tmp/test/test_culm001_b2_qr.sql
-- CULM-001 C.1 (alertas de inasistencia, revision de cancelacion, cierre masivo por horas y audiencias SSE): nombre exacto (DEC-028)
:r /tmp/test/test_culm001_c_alertas.sql
:r /tmp/test/test_culm001_c_revisiones.sql
:r /tmp/test/test_culm001_c_cierre_masivo.sql
:r /tmp/test/test_culm001_c_realtime_audiencias.sql
-- CULM-001 D.3 y D.6 (parametros editables y auditoria de /admin/**): registro por nombre exacto (DEC-028, sin comodin)
-- CULM-001 / DEC-065 (solicitud de sesion extraordinaria con aval del coordinador): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_mrm_solicitud_sesion.sql
-- CULM-001 / DEC-065 (5) (registro compuesto decano + facultad y coordinador + programa): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_mrm_registro_compuesto.sql
:r /tmp/test/test_culm001_d3_parametros.sql
:r /tmp/test/test_culm001_d6_auditoria.sql
-- Alta individual con tipo de documento (casos de D.5 conservados al retirar la carga masiva, DEC-074): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_alta_individual_tipo_documento.sql
-- CULM-001 D.4 (admision de estudiantes HU156): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_culm001_d4_admision.sql
-- CULM-001 D.1 (plazo de excusas HU026B): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_culm001_d1_plazo_justificacion.sql
-- CULM-001 D.2 (varios soportes, categoria persistida y soporte obligatorio): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_culm001_d2_soportes_categoria.sql
-- CULM-001 D.7 (retiro del registro individual autonomo, TD-009): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_culm001_d7_retiro.sql
-- CULM-001 D.8 (comparativas, tendencia y consolidado por horas): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_culm001_d8_kpis_horas.sql
-- HU018 / HU019 (plan de estudios por semestres y horas programadas del estudiante): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_hu018_hu019_plan_horas_estudiante.sql
-- PC BD-1 (tomas como puntos de control: minutos por tramos): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_pc_calculo_tramos.sql
-- PC BD-2 / BD-3 (ciclo de vida de la toma y reclamo por toma): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_pc_puntos_control.sql
-- PC (mejora bandeja de reclamos del docente: toma en R2, migracion 38): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_pc_toma_en_bandeja_reclamos.sql
-- DEC-073 (validaciones de formularios, migracion 43): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_dec073_validaciones.sql
-- CIERRE-W1A (busqueda y filtro de grupo en reclamos del docente; busqueda en el padron): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_cierre_w1a_docente_reclamos_padron.sql
-- DEC-074 (retiro de la carga masiva, migracion 44): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_dec074_retiro_carga_masiva.sql
-- INT-003 (sincronizacion de mensajes desde MessageUcoLab, migracion 45): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_int003_sincronizar_mensaje.sql
-- INT-004 (sincronizacion de parametros desde el Catalogo externo, migracion 73): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_int004_sincronizar_parametro.sql
-- INT-004 (formato CIDR_LIST de parametros, migracion 74): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_int004_formato_cidr.sql
-- CULM-001 D.9-a (hallazgos medios y bajos, migracion 28): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_culm001_d9_hallazgos.sql
-- SES-GEN-01 (calendario de sesiones del semestre, migracion 64): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_ses_gen_01_calendario_semestre.sql
-- DEC-081 (receso academico del periodo, migracion 68): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_receso_academico.sql
-- Revision final P3 (BD-1..BD-10, migracion 69): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_p3_revision_final_bd.sql
:r /tmp/test/test_auditoria_bd_2026_11_22.sql
-- Regresion P3 (D1 y D2, 2026-11-22): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_p3_regresion_2026_11_22.sql
-- CULM-001 / DEC-064 (sesiones manuales: destinatarios y cancelacion por el coordinador, migracion 29): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_sesiones_manuales_notificacion.sql
-- FIX-CIERRE-001 (cierre masivo sin caer al periodo mas reciente): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_fix_cierre_001_cierre_masivo.sql
-- FIX-CIERRE-001 (alta de decano con facultad por id o nombre exacto): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_fix_cierre_001_decano.sql
-- FIX-CIERRE-002 (cierre masivo solo de un periodo terminado): vigente, planeacion y dia de fechaFin rechazados con PER_007; terminado cierra
:r /tmp/test/test_fix_cierre_002_periodo_no_terminado.sql
-- VAL-pendientes-john PRU-13 (borde exacto del plazo de reclamo): ultimo minuto valido contra primer minuto vencido, en hora local y con N parametrizado
:r /tmp/test/test_val_pru13_borde_plazo_reclamo.sql
-- VAL-pendientes-john PRU-15 (periodo cerrado): tomas, lotes y reclamos de un periodo cerrado => PER_008; doble cierre => PER_009
:r /tmp/test/test_val_pru15_periodo_cerrado.sql
-- CIERRE-W1B (directorios de personas con ambito y paginacion): RBAC por perfil exacto, coordinadores paginados del decano y nombres separados
:r /tmp/test/test_w1b_directorios.sql
-- CIERRE-W2A (listados del coordinador en la base): filtro por caracter, opciones del consolidado con ambito y estado del periodo
:r /tmp/test/test_w2a_coordinador_listados.sql
-- CIERRE-W2B (sesiones y resumen del estudiante en la base): orden cronologico determinista, filtro por grupo, resumen coherente con el listado
:r /tmp/test/test_w2b_estudiante_resumen.sql
-- CIERRE-W3M (matriz de asistencia del docente en la base): matriz estudiantes x sesiones paginada, resumen de sesiones y busqueda del resumen
:r /tmp/test/test_w3m_matriz_asistencia.sql
-- CIERRE-W3I (indicadores en la base): totales de los tableros por rol, aforo, resumen de grupos del docente y nivel de permanencia del consolidado
:r /tmp/test/test_w3i_indicadores.sql
-- ATA P1-A/B (edicion de tomas durante la sesion, cierre al fin con margen 0 y denominador por horas del periodo): TOM_012 retirado, ventana unica, cuentaParaPeriodo y horasPeriodo
:r /tmp/test/test_ata_p1_tomas_denominador.sql
-- ATA P1-C (aviso de falta por sesion): sesiones pendientes, faltas por toma, marca idempotente, parametros y plantilla
:r /tmp/test/test_ata_p1_aviso_falta.sql
-- NOTOMA-001 (aviso al coordinador de la sesion sin toma): pendientes, destinatarios, marca idempotente, parametros y plantilla
:r /tmp/test/test_notoma_aviso_sin_toma.sql
-- ATA D6/D7 (migracion 52): solicitudes de sesion del docente y calendario de sesiones con fechas
:r /tmp/test/test_ata_p2_solicitudes_calendario.sql
-- ATA D10 (migracion 54): faltas por reclamar del estudiante (vista y SP de consulta paginada)
:r /tmp/test/test_ata_d10_faltas_reclamables.sql
-- ATA D11 (migracion 55): la oferta de grupos del estudiante (HU008) y su parametro ya no existen tras el despliegue
:r /tmp/test/test_ata_k_retiro_oferta_estudiante.sql
-- PERF-EST-MM (migracion 59): rendimiento de Mis materias del estudiante; mismos resultados que la regla escalar
:r /tmp/test/test_perf_estudiante_mis_materias.sql
-- COMP-ELE (migracion 60): componente de formacion electivas (ELE)
:r /tmp/test/test_componente_electiva.sql

IF @@TRANCOUNT <> 0
BEGIN
    THROW 51999, 'TEST FAILED: test_suite.sql dejo transacciones abiertas.', 1;
END

PRINT 'TEST PASS: test_suite final @@TRANCOUNT = 0';
PRINT 'TEST_PASS:SUITE_TRANCOUNT_ZERO';
PRINT '======================================================================';
PRINT '  DB QUALITY GATE FINISHED';
PRINT '======================================================================';
GO
