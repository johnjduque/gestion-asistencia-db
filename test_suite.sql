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
:r /tmp/test/test_reactive_academic.sql
:r /tmp/test/test_mass_period_close.sql
:r /tmp/test/test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql
:r /tmp/test/test_transaction_ownership.sql
-- VAL ROL-05 (migracion 39): usp_sincronizar_usuario retirado; reemplaza a test_usp_sincronizar_usuario.sql
:r /tmp/test/test_val_retiro_alta_usuarios_sin_ambito.sql
:r /tmp/test/test_val_oleada2_parametro_y_ambito.sql
-- VAL-oleada3 MSG-05 (migracion 41): mensajes de usuario del backend en el catalogo
:r /tmp/test/test_val_oleada3_mensajes_aplicacion.sql
-- VAL oleada 3: PRU-14 (bordes del umbral de horas) y OBS-03 (procedimientos sin @idCorrelacion)
:r /tmp/test/test_val_umbral_horas_bordes.sql
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
:r /tmp/test/test_usp_consultar_oferta_grupos_estudiante.sql
:r /tmp/test/test_hu008_regla_inscripcion_programa.sql
:r /tmp/test/test_int_hu01_reactivar_matricula_retirada.sql
:r /tmp/test/test_usp_crear_actualizar_grupo.sql
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
:r /tmp/test/test_usp_abrir_ventana_matricula_grupo.sql
:r /tmp/test/test_usp_cerrar_ventana_matricula_grupo.sql
:r /tmp/test/test_usp_rotar_token_matricula_grupo.sql
:r /tmp/test/test_usp_validar_token_matricula_publico.sql
:r /tmp/test/test_usp_matricular_estudiante_por_token.sql
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
-- CULM-001 D.5 (carga masiva por CSV de roles no estudiantes HU171): registro por nombre exacto (DEC-028, sin comodin)
:r /tmp/test/test_culm001_d5_carga_masiva.sql
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
