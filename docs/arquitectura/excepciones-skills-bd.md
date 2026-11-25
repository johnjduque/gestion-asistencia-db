---
status: active
type: architecture
scope: database
owner: db-team
last-reviewed: 2026-11-25
---

# Excepciones justificadas a los skills de BD

Los skills de `.agents/skills/` recogen las reglas de organización del código de la BD acordadas con el asesor, y **no se modifican**. El código las cumple. Este documento lista los únicos casos en que el código no puede cumplirlas sin romper el funcionamiento de la app o sin cambiar el backend. Para cada caso se da la razón técnica y la condición que lo acota.

Origen: auditoría y plan por lotes del 2026-11-25. Las decisiones son de John (2026-11-25, D1 a D7).

## E1. SP de sistema sin `@idUsuarioEjecutor`

**Regla afectada:** `modelo-jerarquico-rbac` §3 (validar `@idUsuarioEjecutor` con RBAC).

**Por qué:** estos SP no los ejecuta un usuario con perfil. Los ejecuta el backend por su cuenta (jobs programados), una integración o un visitante con un token. No hay ejecutor que validar, y exigirlo obligaría a cambiar el backend.

| Tipo | SP |
|---|---|
| Jobs programados | `usp_rotar_token_asistencia_automatico`, `usp_rotar_token_matricula_automatico`, `usp_cerrar_tomas_vencidas`, `usp_consultar_tomas_qr_por_rotar`, `usp_consultar_ventanas_matricula_por_rotar`, `usp_consultar_sesiones_pendientes_aviso_falta`, `usp_consultar_sesiones_pendientes_aviso_sin_toma`, `usp_consultar_destinatarios_aviso_sin_toma`, `usp_consultar_faltas_sesion_aviso`, `usp_registrar_aviso_falta_sesion`, `usp_registrar_aviso_sesion_sin_toma`, `usp_consultar_grupos_pendientes_evaluacion_alertas`, `usp_evaluar_alertas_inasistencia_grupo`, `usp_actualizar_resolutores_revisiones_cancelacion`, `usp_aplicar_festivos_automatico`, `usp_cargar_dias_festivos_automatico`, `usp_consultar_carga_festivos_anio` |
| Flujos públicos por token | `usp_registrar_estudiante_por_token_publico`, `usp_validar_token_matricula_publico`, `usp_matricular_estudiante_por_token` |
| Notificaciones y correo | `usp_registrar_notificacion_saliente`, `usp_reservar_notificaciones_salientes`, `usp_marcar_notificacion_entregada`, `usp_registrar_fallo_notificacion`, `usp_depurar_notificaciones_salientes`, `usp_consultar_contacto_notificacion`, `usp_emitir_token_verificacion_correo`, `usp_consultar_token_verificacion_correo`, `usp_confirmar_verificacion_correo` |
| Integraciones externas | `usp_vincular_identidad_externa`, `usp_revocar_identidad_externa`, `usp_sincronizar_parametro_catalogo_externo`, `usp_sincronizar_mensaje_usuario` |
| Utilidades | `usp_obtener_mensaje_catalogo`, `usp_establecer_contexto_usuario_ejecutor`, `usp_validar_carga_masiva_usuarios` |

**Condiciones:**
- exigen `@idCorrelacion`;
- ningún endpoint los expone recibiendo la identidad del usuario como parámetro libre;
- los públicos por token validan el token, su vigencia y su ámbito;
- su cabecera lleva la marca `SP_SISTEMA` con el motivo (se agrega al intervenirlos en su lote).

## E2. Ejecutor recibido como `@idUsuario`

**Regla afectada:** convención de nombre `@idUsuarioEjecutor`.

**Por qué:** `usp_consultar_sesiones_calendario_docente`, `usp_consultar_sesiones_calendario_estudiante`, `usp_consultar_solicitudes_sesion_coordinador_paginado`, `usp_consultar_solicitudes_sesion_docente_paginado` y `usp_consultar_revisiones_cancelacion_docente_paginado` reciben el ejecutor como `@idUsuario`. Validan el perfil igual. Renombrar el parámetro cambiaría la firma que usa el backend. El código nuevo usa `@idUsuarioEjecutor`.

## E3. El backend lee vistas base `uv_*`

**Regla afectada:** `consulta-a-bd` §1 (consumo externo solo por `uv_auth_*`).

**Por qué:** el backend lee unas 59 vistas base mediante JPA (catálogos, identidades y entidades). Quitarle el permiso rompería la app.

**Condiciones:**
- la validación de rol y ámbito nunca depende de una vista base: se hace con `uv_auth_*`, en un SP público o en el PDP del componente de seguridad;
- el backend nunca lee tablas, salvo `AuditoriaEvento` (`SELECT, INSERT`, LB-008).

## E4. ADMINISTRADOR en lecturas transversales y en HU156

**Regla afectada:** `modelo-jerarquico-rbac` §2.A (el administrador no interviene en niveles inferiores).

**Por qué:** el negocio le pidió al administrador consultas institucionales: consolidados, comparativas, historial, búsqueda de estudiantes, y docentes y asignaturas del ámbito. HU156 le permite admitir un estudiante sin grupo (`usp_admitir_estudiante`).

**Condiciones:**
- solo en lectura y acotado a su institución;
- su única escritura sobre un estudiante es HU156;
- nunca escribe en grupos, sesiones, asistencia ni matrículas en grupo.

## E5. `XACT_ABORT ON` en el patrón de savepoint

**Regla afectada:** `procedimientos-externos-condiciones`, REC4 §4 (el patrón savepoint no lleva `XACT_ABORT`).

**Por qué:** 73 SP que escriben combinan `SAVE TRANSACTION` con `XACT_ABORT ON`, y la auditoría del 2026-11-22 (M-6) lo extendió a propósito. Quitarlo cambia cómo se comportan ante errores, con riesgo de dejar transacciones abiertas.

**Condiciones:**
- el backend los invoca sin transacción externa, así que siempre usan su transacción propia;
- en el CATCH revisan `XACT_STATE()`;
- los SP cuyo contrato exige preservar la transacción del llamador siguen sin `XACT_ABORT`: `usp_crear_decano`, `usp_crear_coordinador` y `usp_registrar_o_actualizar_plan_estudio`.

## E6. Objetos congelados

**Regla afectada:** ninguna directamente. Los 38 SP con hash en `docs/contracts/*.sha256` o en `test_golden_path_immutability.sql` se corrigen en el lote 14 sin cambiar su firma ni su resultset, y se regeneran sus manifiestos.

## E7. Búsqueda del token QR de asistencia en la tabla

**Regla afectada:** `consultas-a-vistas` (las lecturas van a vistas `uv_*`).

**Por qué:** `usp_resolver_token_asistencia_interno` busca el token por `tokenHash`/`tokenHashAnterior` (o PIN) en `dbo.TokenAsistenciaToma` y la toma y la sesión en `dbo.TomaAsistencia` y `dbo.Sesion`. Ninguna vista expone `tokenHash`, y no se debe publicar: el rol de runtime recibe `SELECT` sobre todas las `uv_%`, así que una vista con el hash lo dejaría legible desde el backend. Además `uv_toma_asistencia` y la vista del token calculan totales por grupo que harían más lento el registro QR concurrente (40 estudiantes a la vez).

**Condiciones:**
- solo lectura, sin `UPDLOCK` (`READ COMMITTED`), y solo de las columnas que identifican el token, la toma, la sesión y el grupo;
- el resultado sale por OUTPUT a su único llamador (`usp_registrar_asistencia_por_token`), que valida titularidad, ventana y RBAC como antes;
- cualquier token desconocido, cerrado o vencido devuelve el mismo `AQR_001` (no revela si existió).

Las lecturas con bloqueo (`UPDLOCK, HOLDLOCK`) de las filas que se van a escribir dentro de la misma transacción (tomas, tokens de matrícula, matrículas) siguen en la tabla: es la excepción de lecturas con bloqueo que ya recogen los skills. En el mismo grupo queda el job `usp_cerrar_tomas_vencidas`: busca las tomas candidatas en `dbo.TomaAsistencia` con `READPAST` para saltar las que otra transacción tiene bloqueadas (una vista no admite esa pista sobre la tabla base de forma fiable).

## E8. Utilidades transversales con la firma heredada

**Reglas afectadas:** prefijo `id` / nombres de parámetros sin `p_`, triplete OUTPUT y `CATCH` con `SYS_001` por `usp_obtener_mensaje_catalogo`.

**Por qué:** `usp_obtener_mensaje_catalogo` (parámetros `@p_codigo`, `@p_param1..3`) lo llaman por nombre casi todos los SP, y `usp_establecer_contexto_usuario_ejecutor` (`@p_idUsuario`) lo llaman por nombre 12 consultas y las pruebas de RBAC. Renombrar sus parámetros obligaría a tocar cientos de SP a la vez, justo lo que el plan por lotes evita, sin cambiar nada de su comportamiento. Además `usp_obtener_mensaje_catalogo` es quien resuelve `SYS_001` para los demás: su `CATCH` no puede llamarse a sí mismo.

**Condiciones (lote 3, 2026-11-25):**
- los dos SP se corrigieron en todo lo demás: `DECLARE` en la cabecera, sin `ISNULL`, `PASO n`, `IF` con `BEGIN/END` y `TRY/CATCH`;
- `usp_obtener_mensaje_catalogo` completa el triplete con `@estadoResultado BIT = NULL OUTPUT` opcional al final (los llamadores no cambian); en su `CATCH` arma los textos de reserva con `DBCODE=SYS_001|` y `ufn_obtener_detalle_error`, deja `@estadoResultado = 0` y relanza si la transacción del llamador quedó condenada;
- `usp_establecer_contexto_usuario_ejecutor` no devuelve resultset ni triplete (es un helper de `SESSION_CONTEXT`): su `CATCH` relanza el error al llamador, que lo traduce a `SYS_001`;
- `test/test_skills_lote3_caracterizacion.sql` (`SKL3_N01_ESTRUCTURA`) falla si alguien cambia estas firmas.

## Lo que ya no es excepción

- **Familia `usp_internal_*`:** renombrada a `usp_..._interno` en el lote 2 (decisión de John, D3). La migración 78 retira los nombres viejos.
