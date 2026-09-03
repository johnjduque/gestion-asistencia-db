# Especificación Técnica de Transacciones y Procedimientos Reactivos Compuestos
## Sistema de Gestión de Asistencia Académica (`gestionasistenciadb`)

---

## 🏛️ Introducción Arquitectónica

El presente documento define la arquitectura detallada de **180 Transacciones y Procedimientos Reactivos Compuestos** para el ecosistema `gestionasistenciadb`.

A diferencia de las operaciones CRUD tradicionales que ejecutan mutaciones simples aisladas, una **Transacción Reactiva Compuesta (PR)** es un procedimiento atómico orquestado a nivel de negocio que:
1. **Consolida múltiples Historias de Usuario (HUs)** en una sola llamada desde la aplicación cliente.
2. **Previene datos huérfanos e inconsistencias en el MER** (ej. crear usuarios sin asignación institucional o registrar asistencias sin verificar la validez de la sesión/matrícula).
3. **Garantiza la integridad referencial y atómica** ejecutando validaciones de entrada, transformaciones de estado y propagaciones en cascada en un solo bloque de transacción.

---

## 🗺️ ÍNDICE GENERAL GLOBAL DE PROCEDIMIENTOS REACTIVOS COMPUESTOS (PR-001 A PR-180)

### 📦 MÓDULO 1: Gestión de Usuarios, Identidades y Seguridad Institucional (PR-001 a PR-030)
* **[PR-001]** Sincronización y Alta Reactiva de Usuario Externo a Interno con Verificación de Tipo de Documento.
* **[PR-002]** Registrar Docente Institucional en Grupo (Creación/Actualización Reactiva de Usuario + Asignación de Rol + Enrolamiento a Grupo).
* **[PR-003]** Registrar Estudiante Institucional en Grupo (Sincronización de Usuario + Asignación de Perfil Estudiante + Inscripción a Programa + Matrícula en Grupo).
* **[PR-004]** Asignar Decano a Facultad con Validación/Creación de Usuario e Inactivación de Decano Previas.
* **[PR-005]** Asignar Coordinador a Programa Académico con Actualización Reactiva de Usuario y Transferencia de Dirección.
* **[PR-006]** Actualización Perfilada de Datos Personales de Usuario con Re-validación de Credenciales e Institución.
* **[PR-007]** Desactivación Reactiva de Usuario con Inactivación en Cascada de Roles (Docente, Estudiante, Coordinador, Decano).
* **[PR-008]** Reactivación Integral de Usuario y Reincorporación a Estructuras Académicas Activas.
* **[PR-009]** Sincronización Masiva de Cuentas Institucionales con Detección Automática de Duplicados.
* **[PR-010]** Conversión Reactiva de Rol (Promoción de Estudiante/Docente a Coordinador o Decano).
* **[PR-011]** Autenticación y Emisión de Contexto de Seguridad con Carga de Perfiles y Grupos Asignados.
* **[PR-012]** Cambio de Contraseña y Expiración de Credenciales con Auditoría de Seguridad.
* **[PR-013]** Transferencia Institucional de Usuario entre Sedes/Instituciones con Conservación de Histórico.
* **[PR-014]** Depuración de Usuarios Inactivos sin Registro Operativo en el MER.
* **[PR-015]** Asignación de Tipo de Documento e Identificación Institucional con Re-indexación de Registros.
* **[PR-016]** Auditoría y Bloqueo Preventivo de Cuentas por Intentos Fallidos o Accesos Anómalos.
* **[PR-017]** Asignación Reactiva de Administrador Institucional con Configuración de Alcance.
* **[PR-018]** Sincronización de Correo Electrónico Institucional y Actualización de Dominios Habilitados.
* **[PR-019]** Registro y Validación de Documentos de Identidad Especiales/Extranjeros en la Plataforma.
* **[PR-020]** Inactivación Temporal de Docente con Suspensión de Asignaciones a Grupos Activos.
* **[PR-021]** Inactivación Temporal de Estudiante con Suspensión de Matrículas en Periodo Académico.
* **[PR-022]** Sincronización Lote de Identidades de Estudiantes de Nuevo Ingreso.
* **[PR-023]** Sincronización Lote de Identidades de Planta Docente y Cátedra.
* **[PR-024]** Validación de Unicidad de Correo e Identificación con Generación de Reporte de Inconsistencias.
* **[PR-025]** Registro de Usuario con Rol Único Temporal para Evaluadores Externos.
* **[PR-026]** Reasignación Masiva de Grupo por Baja Definitiva de Docente.
* **[PR-027]** Reincorporación de Estudiante Graduado/Egresado como Docente o Investigador.
* **[PR-028]** Limpieza y Unificación de Registros Duplicados de Usuario con Fusionado de Historial.
* **[PR-029]** Actualización de Términos, Condiciones y Políticas de Privacidad por Usuario.
* **[PR-030]** Cierre y Archivo Definitivo de Expediente de Usuario Institucional.

---

### 📦 MÓDULO 2: Estructura Académica, Programas y Planes de Estudio (PR-031 a PR-060)
* **[PR-031]** Crear Institución Académica con Configuración de Parámetros Globales Iniciales.
* **[PR-032]** Crear Facultad con Vinculación Inmediata de Decano y Áreas Iniciales.
* **[PR-033]** Crear Programa Académico con Coordinador Asignado, Tipo de Programa y Facultad.
* **[PR-034]** Estructurar Plan de Estudio con Asignación Automática de Semestres Académicos.
* **[PR-035]** Registrar Asignatura en Plan de Estudio con Clasificación de Área, Componente y Semestre.
* **[PR-036]** Asociar Asignaturas a Semestres en el Plan de Estudios con Validación de Coherencia Curricular.
* **[PR-037]** Inactivar Programa Académico con Verificación de Planes de Estudio y Estudiantes Inscritos.
* **[PR-038]** Crear Periodo Académico con Apertura de Calendario y Rangos de Fechas Validados.
* **[PR-039]** Actualizar Periodo Académico con Reprogramación de Rangos de Fechas en Sesiones y Grupos.
* **[PR-040]** Cierre Oficial de Periodo Académico con Consolidación de Estadísticas de Ausentismo.
* **[PR-041]** Transferir Asignatura entre Áreas Académicas con Ajuste de Competencias.
* **[PR-042]** Duplicación de Plan de Estudio para Nueva Versión Curricular con Migración de Malla.
* **[PR-043]** Crear Componente Académico Institucional con Mapeo a Asignaturas Existentes.
* **[PR-044]** Crear Área de Conocimiento Institucional y Vinculación a Facultades.
* **[PR-045]** Registrar Tipo de Programa Académico con Definición de Niveles de Formación.
* **[PR-046]** Asignar Múltiples Coordinadores de Apoyo a Programas Académicos Complejos.
* **[PR-047]** Reestructuración de Semestres dentro de un Plan de Estudio Activo.
* **[PR-048]** Retiro de Asignatura de Plan de Estudio con Verificación de Estudiantes Matriculados.
* **[PR-049]** Fusionar Dos Áreas Académicas con Re-asociación Automática de Asignaturas.
* **[PR-050]** Configurar Parámetros de Ausentismo Máximo Permitido por Programa Académico.
* **[PR-051]** Inactivar Facultad con Reubicación o Inactivación de Programas Académicos.
* **[PR-052]** Habilitar Oferta de Asignaturas Electivas / Optativas por Periodo Académico.
* **[PR-053]** Actualizar Créditos y Horas Semanales de Asignatura con Recálculo de Intensidad.
* **[PR-054]** Asociar Programa Académico a Múltiples Sedes/Instituciones.
* **[PR-055]** Generar Versión Histórica de Malla Curricular con Congelamiento de Cambios.
* **[PR-056]** Registrar Homologación Institucional de Asignaturas entre Programas.
* **[PR-057]** Asignar Decano Interino a Facultad por Licencia o Vacante.
* **[PR-058]** Asignar Coordinador Interino a Programa Académico.
* **[PR-059]** Auditoría Cambios Malla Curricular y Planes de Estudio.
* **[PR-060]** Eliminación Lógica de Periodo Académico Sin Oferta Registrada.

---

### 📦 MÓDULO 3: Oferta Académica, Grupos, Horarios y Asignación Docente (PR-061 a PR-090)
* **[PR-061]** Apertura de Grupo Académico en Periodo con Asignación de Asignatura, Cupo Máximo y Docente Titular.
* **[PR-062]** Programación de Horario para Grupo con Validación de Cruces Horarios de Docente y Aula/Día.
* **[PR-063]** Reasignación de Docente Titular de Grupo con Ajuste de Horarios y Notificación de Cambio.
* **[PR-064]** Cancelación de Grupo Académico con Desinscripción en Cascada de Estudiantes y Liberación de Horarios.
* **[PR-065]** Modificación de Cupo Máximo de Grupo con Verificación de Matriculados Activos.
* **[PR-066]** Reprogramación de Horario de Grupo con Actualización Masiva de Fechas de Sesiones.
* **[PR-067]** Asignación de Docente Auxiliar/Co-tutor a Grupo Académico Existente.
* **[PR-068]** Fusionar Dos Grupos Académicos de la Misma Asignatura en un Periodo.
* **[PR-069]** División/Desdoblamiento de Grupo Académico por Exceso de Cupo.
* **[PR-070]** Inactivación Temporizada de Grupo por Falta de Cupo Mínimo.
* **[PR-071]** Apertura Masiva de Grupos para Periodo Académico Basado en Oferta del Periodo Anterior.
* **[PR-072]** Definición de Horarios Intensivos (Fin de Semana / Bloque) para Grupos Especiales.
* **[PR-073]** Validar Cruces Horarios de Docente en Múltiples Grupos e Instituciones.
* **[PR-074]** Asignación de Aula / Ubicación Física a Horario de Grupo.
* **[PR-075]** Retiro de Horario de Grupo con Cancelación de Sesiones Futuras Afectadas.
* **[PR-076]** Registrar Grupo Magistral con Subgrupos de Práctica o Laboratorio.
* **[PR-077]** Cambiar Estado de Grupo de "En Preparación" a "Habilitado para Matrícula".
* **[PR-078]** Bloquear Grupo para Nuevas Matrículas Manteniendo Sesiones Activas.
* **[PR-079]** Reubicación de Grupo a Nuevo Horario por Fuerza Mayor.
* **[PR-080]** Asignar Docente Suplente Temporal para un Rango de Fechas en un Grupo.
* **[PR-081]** Generar Calendario Teórico de Sesiones del Grupo Basado en sus Horarios y Días.
* **[PR-082]** Extensión de Fecha Fin de Grupo Académico con Ajuste de Calendario.
* **[PR-083]** Ajustar Cupos Reservados para Estudiantes de Reingreso o Transferencia.
* **[PR-084]** Auditoría de Asignación Docente y Cambios de Horarios en Grupos.
* **[PR-085]** Sincronización de Grupos desde Sistema Externo de Registro Académico.
* **[PR-086]** Cierre Definitivo de Grupo Académico al Concluir el Periodo.
* **[PR-087]** Habilitación de Grupo Extemporáneo/Vacacional.
* **[PR-088]** Asignación de Días No Lectivos / Festivos a Calendario de Grupos.
* **[PR-089]** Intercambio de Docentes Titulares entre Dos Grupos Sin Aflicción de Horarios.
* **[PR-090]** Consulta y Validación de Carga Horaria Máxima Docente Permitida.

---

### 📦 MÓDULO 4: Matrículas, Enrolamiento de Estudiantes y Estado en Grupos (PR-091 a PR-120)
* **[PR-091]** Enrolamiento de Estudiante en Programa Académico (Sincronización de Estudiante + Registro en Programa).
* **[PR-092]** Matrícula Reactiva de Estudiante en Grupo con Validación de Asignaturas y Plan de Estudios, Cupos y Cruces Horarios.
* **[PR-093]** Matrícula Masiva por Lote de Estudiantes en Lista de Clases.
* **[PR-094]** Cambio de Estado de Estudiante en Grupo (Activo, Retirado, Cancelado por Ausentismo).
* **[PR-095]** Cancelación de Matrícula de Estudiante en Grupo por Solicitud Voluntaria.
* **[PR-096]** Cancelación Automática de Matrícula en Grupo por Exceso de Inasistencias (Reglamentaria).
* **[PR-097]** Transferencia de Estudiante de un Grupo a Otro en la Misma Asignatura con Migración de Asistencias.
* **[PR-098]** Procesar Solicitud de Inscripción Exclusiva/Extemporánea de Estudiante en Grupo.
* **[PR-099]** Rechazo de Solicitud de Inscripción de Estudiante con Notificación y Liberación de Cupo.
* **[PR-100]** Inactivación de Estudiante en Programa Académico por Retiro Definitivo o Graduación.
* **[PR-101]** Reincorporación/Reingreso de Estudiante a Programa Académico.
* **[PR-102]** Matrícula de Estudiante Asistente / Oyente en Grupo Académico.
* **[PR-103]** Registro de Estudiante en Plan de Estudio Específico.
* **[PR-104]** Validación de Límite de Créditos / Asignaturas Simultáneas por Estudiante en Periodo.
* **[PR-105]** Cambio Masivo de Estado en Grupo para Estudiantes Inactivos o No Regulados.
* **[PR-106]** Enrolamiento Directo por Archivo Masivo CSV/Excel de Estudiantes en Grupos.
* **[PR-107]** Reserva de Cupo de Estudiante en Grupo para Periodo Siguiente.
* **[PR-108]** Habilitación Excepcional de Matrícula con Sobre-cupo Autorizado por Coordinador.
* **[PR-109]** Registro de Estudiante en Modalidad Intercambio / Movilidad Académica.
* **[PR-110]** Retiro Masivo de Estudiantes por Cierre Definitivo de Grupo.
* **[PR-111]** Homologación y Marcaje de Asignatura Cursada en Otro Grupo o Institución.
* **[PR-112]** Auditoría de Cambios de Estado de Estudiante en Grupo (`EstadoEstudianteGrupo`).
* **[PR-113]** Bloqueo Administrativo de Matrícula de Estudiante en Grupos.
* **[PR-114]** Desbloqueo Administrativo de Matrícula de Estudiante.
* **[PR-115]** Asignación de Tutor Académico a Estudiante en Riesgo de Ausentismo.
* **[PR-116]** Sincronización de Estados de Matrícula con Sistema ERP/SGA Institucional.
* **[PR-117]** Generación de Ficha de Inscripción y Matrícula Consolidada del Estudiante.
* **[PR-118]** Confirmación de Asistencia Inicial Obligatoria en Primera Semana de Clase.
* **[PR-119]** Regularización de Estudiantes Extemporáneos con Marcaje Retroactivo de Sesiones.
* **[PR-120]** Archivo de Expediente de Matrículas de Periodos Anteriores.

---

### 📦 MÓDULO 5: Sesiones, Captura y Registro de Asistencia (PR-121 a PR-150)
* **[PR-121]** Apertura o Generación Reactiva de Sesión de Clase (Creación al Vuelo + Validación Horaria + Retorno Plantilla Grupo).
* **[PR-122]** Toma de Asistencia Masiva por Lote en Sesión por el Docente (Asistió, Faltó, Tarde).
* **[PR-123]** Registro de Asistencia Autónoma por Estudiante mediante QR/Token Dinámico con Geolocalización/Tolerancia.
* **[PR-124]** Cierre Definitivo de Sesión con Marcado Automático de Inasistencias no Registradas y Recálculo de Ausentismo.
* **[PR-125]** Modificación Atómica de Registro de Asistencia de un Estudiante en Sesión Específica.
* **[PR-126]** Cancelación de Sesión de Clase Programada con Notificación a Estudiantes y Opción de Reprogramación.
* **[PR-127]** Reprogramación de Sesión Cancelada en Nueva Fecha/Hora sin Cruces Horarios.
* **[PR-128]** Apertura de Sesión Extraordinaria / Extracurricular fuera del Horario Habitual.
* **[PR-129]** Toma de Asistencia por Escaneo Masivo de Código de Estudiante (Barcode/NFC).
* **[PR-130]** Corrección Lote de Asistencia en Sesión por Error del Docente en el Llamado.
* **[PR-131]** Marcaje Automático de Llegada Tarde por Superación de Tolerancia de Minutos.
* **[PR-132]** Consolidar Cierre Automático Nocturno de Sesiones Olvidadas Abiertas por Docentes.
* **[PR-133]** Inactivación / Anulación de Registro de Asistencia Duplicado.
* **[PR-134]** Consulta de Plantilla de Asistencia en Tiempo Real para Sesión Activa.
* **[PR-135]** Registro de Asistencia para Estudiantes Asistentes / Oyentes Autorizados.
* **[PR-136]** Bloqueo de Edición de Asistencia en Sesiones con Fecha Mayor a Límite Reglamentario (ej. 8 días).
* **[PR-137]** Desbloqueo Excepcional de Sesión de Asistencia por Solicitud de Coordinador.
* **[PR-138]** Registro de Observación / Comentario Individual en Marcaje de Asistencia.
* **[PR-139]** Generación de Token Dinámico / Código QR Temporal para Sesión por el Docente.
* **[PR-140]** Validación de Token Dinámico de Asistencia y Expulsión por Token Vencido.
* **[PR-141]** Registro de Asistencia en Modalidad Virtual / Remota con Enlace de Conexión.
* **[PR-142]** Sincronización Offline de Registros de Asistencia Tomados desde App Móvil Sin Conexión.
* **[PR-143]** Marcaje de Asistencia Grupal Total por Evento Institucional / Salida de Campo.
* **[PR-144]** Auditoría Fila a Fila de Modificaciones en la Tabla `Asistencia`.
* **[PR-145]** Verificación de Integridad entre `Sesion`, `EstudianteGrupo` y `Asistencia`.
* **[PR-146]** Re-apertura de Sesión Cerrada para Inclusión de Estudiante Extemporáneo.
* **[PR-147]** Marcaje de Permiso Institucional Previo en Asistencia por Representación Deportiva/Académica.
* **[PR-148]** Reporte Reactivo de Faltas Consecutivas en el Transcurso de las Sesiones.
* **[PR-149]** Notificación Push / Correo Inmediata al Estudiante por Inasistencia Registrada.
* **[PR-150]** Purga / Limpieza de Registros Temporales de Control de Asistencia.

---

### 📦 MÓDULO 6: Novedades, Justificaciones, Alertas de Ausentismo y Reportes Auditados (PR-151 a PR-180)
* **[PR-151]** Radicar Solicitud de Revisión / Justificación de Inasistencia por el Estudiante con Soporte.
* **[PR-152]** Resolver Solicitud de Justificación por el Docente (Aprobación/Rechazo + Cambio Atómico en `Asistencia`).
* **[PR-153]** Resolver Solicitud de Justificación por el Coordinador de Programa (Instancia Superior).
* **[PR-154]** Cancelación de Solicitud de Revisión por el Estudiante antes de ser Evaluada.
* **[PR-155]** Generación de Alerta Temprana de Ausentismo Crítico al Superar Umbral (ej. 15% y 20% de Faltas).
* **[PR-156]** Envío de Notificación Consolidada a Coordinación por Estudiantes en Riesgo de Pérdida por Inasistencias.
* **[PR-157]** Emisión de Certificado Oficial de Porcentaje de Asistencia por Asignatura y Estudiante.
* **[PR-158]** Registro de Razón / Causa de Inasistencia Institucional (Mantenimiento del Catálogo `RazonCausa`).
* **[PR-159]** Consulta Consolidada de Histórico de Asistencias del Estudiante (`uv_asistencia`).
* **[PR-160]** Consulta Consolidada de Estadísticas de Asistencia por Grupo para Coordinación (`uv_estadistica_grupo`).
* **[PR-161]** Generación de Reporte Macro de Deserción y Ausentismo para Decanatura por Facultad.
* **[PR-162]** Auditoría de Solicitudes de Revisión y Resoluciones de Docentes.
* **[PR-163]** Reabrir Solicitud de Revisión Rechazada por Presentación de Nuevo Soporte Oficial.
* **[PR-164]** Justificación Masiva de Inasistencias para un Grupo por Paro / Incapacidad Institucional.
* **[PR-165]** Inactivación / Anulación de Solicitud de Revisión Fraudulenta con Notificación a Decanatura.
* **[PR-166]** Configuración de Tipos de Causa Justificable por Programa Académico.
* **[PR-167]** Mapeo de Solicitudes de Revisión con Expediente Médico de Bienestar Universitario.
* **[PR-168]** Recálculo General de Porcentajes de Ausentismo por Modificación Retroactiva de Calendario.
* **[PR-169]** Generación de Indicador KPI de Cumplimiento de Toma de Lista por Docente.
* **[PR-170]** Exportación Registros de Asistencia a Formato Oficial de Acta de Notas y Faltas.
* **[PR-171]** Consulta de Solicitudes de Justificación Vencidas Sin Respuesta del Docente.
* **[PR-172]** Aprobación Automática de Justificación por Silencio Administrativo del Docente (Vencimiento de Plazo).
* **[PR-173]** Notificación a Acudiente / Tutor Externo por Ausentismo Reiterado de Estudiante.
* **[PR-174]** Reporte de Inconsistencias entre Horarios de Grupo y Fechas de Sesiones Realizadas.
* **[PR-175]** Consolidación de Histórico Académico de Asistencias para Proceso de Graduación.
* **[PR-176]** Auditoría General de Trazabilidad de Transacciones (`idCorrelacion`).
* **[PR-177]** Consulta de Log de Errores y Excepciones en Procedimientos Reactivos.
* **[PR-178]** Mantenimiento de Parámetros Globales de Sistema (`Parametro`).
* **[PR-179]** Respaldar y Archivar Registros de Asistencia de Periodos Académicos Históricos.
* **[PR-180]** Cierre Anual Auditoría de Integridad del Ecosistema `gestionasistenciadb`.

---

## 📑 ESPECIFICACIÓN DETALLADA DE PROCEDIMIENTOS REACTIVOS (BLOQUE 1: PR-001 A PR-015)

---

### [PR-001] - Sincronización y Alta Reactiva de Usuario Externo a Interno
- **Historias de Usuario que satisface:** HU050 (Sincronización de cuentas de usuarios externos a internos).
- **Propósito de Negocio:** Evita duplicar usuarios en la BD al recibir peticiones de autenticación externa (OAuth/AD). Si el usuario existe por documento o correo, actualiza sus nombres y estado; si no existe, lo crea atómicamente retornando su `id` para consumo inmediato por subsistemas.
- **Entidades del MER Involucradas:** `Usuario`, `TipoIdentificacion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar presencia del `idCorrelacion` y formato válido del correo institucional y número de identificación.
  2. Validar que el `idTipoIdentificacion` exista y se encuentre activo en la tabla `TipoIdentificacion`.
  3. Consultar la tabla `Usuario` buscando coincidencia por `(tipoIdentificacion, numeroIdentificacion)` o `correo`.
  4. **Si el usuario existe:** Actualizar `primerNombre`, `segundoNombre`, `primerApellido`, `segundoApellido`, `correo` y asegurar `estado = 1`.
  5. **Si el usuario NO existe:** Insertar nuevo registro en `Usuario` generando un nuevo `UUID` para `id`.
  6. Retornar el `id` del usuario, el `idCorrelacion` y el estado final de la transacción.
- **Reglas de Negocio y Validaciones Específicas:**
  * No permite registrar dos usuarios activos con el mismo correo electrónico.
  * El número de identificación debe ser un entero positivo.
- **Estado Resultante en la BD:** Registro creado o actualizado de forma consistente en la tabla `Usuario` sin registros duplicados ni huérfanos.

---

### [PR-002] - Registrar Docente Institucional en Grupo (Creación/Actualización Reactiva de Usuario + Rol Docente + Asignación a Grupo)
- **Historias de Usuario que satisface:** HU052 (Registro de docentes en grupos con validación de existencia), HU050 (Sincronización de usuarios).
- **Propósito de Negocio:** Permite asignar un docente a un grupo académico en un solo paso. Si la persona no está registrada como usuario o no tiene perfil de docente instituido, la transacción lo crea y categoriza reactivamente antes de vincularlo al grupo, evitando fallos por clave foránea o datos incompletos.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Grupo`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idGrupo` exista y esté en un estado activo.
  2. Ejecutar la sincronización interna de usuario (`PR-001` / `usp_sincronizar_usuario_interno`): crear o actualizar datos personales en `Usuario`.
  3. Verificar si el usuario ya tiene un registro en la tabla `Docente` para la `Institucion` del grupo:
     * **Si NO existe:** Insertar en `Docente` relacionando `idUsuario`, `idInstitucion` y `estado = 1`.
     * **Si existe:** Asegurar que su estado sea activo.
  4. Validar que el docente no tenga cruces de horario incompatibles en otros grupos activos para el mismo periodo académico.
  5. Asignar el `idDocente` como titular en la tabla `Grupo` (o tabla de vinculación docente-grupo).
- **Reglas de Negocio y Validaciones Específicas:**
  * Un docente no puede ser asignado a un grupo cuyo periodo académico ya esté cerrado.
  * Se verifica la unicidad de la relación docente-grupo para evitar duplicaciones.
- **Estado Resultante en la BD:** Usuario registrado/actualizado, perfil de `Docente` asegurado y tabla `Grupo` vinculada al docente en estado activo.

---

### [PR-003] - Registrar Estudiante Institucional en Grupo (Sincronización + Perfil Estudiante + Programa + Matrícula en Grupo)
- **Historias de Usuario que satisface:** HU053 (Registro e inscripción de estudiantes en grupos académicos), HU051 (Registro en programas académicos), HU050.
- **Propósito de Negocio:** Orquesta el enrolamiento completo de un estudiante en un grupo. Registra/actualiza al usuario, le otorga el rol de `Estudiante`, lo inscribe en el `Programa` correspondiente a la asignatura del grupo si no lo está, y finalmente lo matricula en `EstudianteGrupo` con estado activo.
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `EstudiantePrograma`, `Programa`, `Grupo`, `Asignatura`, `EstudianteGrupo`, `EstadoEstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la existencia del `idGrupo` y que el cupo máximo (`cupoMaximo`) no haya sido superado por las matrículas activas existentes.
  2. Ejecutar la sincronización reactiva de usuario (`Usuario`): crear o actualizar los datos personales.
  3. Validar/Insertar el registro del rol en la tabla `Estudiante` (`idUsuario`, `idInstitucion`).
  4. Identificar el `Programa` académico a través de la `Asignatura` del `Grupo`:
     * Verificar si existe la relación en `EstudiantePrograma`. Si no existe, crear la vinculación reactivamente.
  5. Obtener el `idEstadoEstudianteGrupo` correspondiente a "MATRICULADO / ACTIVO".
  6. Insertar el registro de matrícula en `EstudianteGrupo` (`idEstudiante`, `idGrupo`, `estadoEstudianteGrupo`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Rechaza la matrícula si el número de inscritos en `EstudianteGrupo` es igual o mayor a `cupoMaximo` del `Grupo`.
  * Evita la doble matrícula activa de un mismo estudiante en el mismo grupo.
- **Estado Resultante en la BD:** Estudiante dado de alta en `Usuario`, `Estudiante`, `EstudiantePrograma` y matriculado formalmente en `EstudianteGrupo`.

---

### [PR-004] - Asignar Decano a Facultad con Validación/Creación de Usuario e Inactivación de Decano Previo
- **Historias de Usuario que satisface:** HU102 (Gestión macro de facultades y decanaturas), HU050.
- **Propósito de Negocio:** Garantizar que una facultad tenga exactamente un Decano activo titular. Si ya existía un decano previo en la facultad, lo inactiva o desvincula en la misma transacción antes de promover al nuevo usuario y asignarlo a la `Facultad`.
- **Entidades del MER Involucradas:** `Usuario`, `Decano`, `Facultad`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la existencia y estado activo de la `Facultad` y de la `Institucion`.
  2. Sincronizar/Crear los datos personales del nuevo candidato a Decano en `Usuario`.
  3. Verificar/Crear el rol de `Decano` para el usuario en la `Institucion`.
  4. Consultar el decano actual en `Facultad`:
     * Si la `Facultad` tiene un `decano` (FK) asignado diferente al nuevo, cambiar el estado del decano saliente en la tabla `Decano` a inactivo o remover la titularidad.
  5. Actualizar la clave foránea `decano` en la tabla `Facultad` apuntando al nuevo ID de `Decano`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Una `Facultad` no puede quedarse con una referencia nula a `Decano` a menos que esté en estado inactivo.
  * El usuario asignado como decano debe estar en estado activo en `Usuario`.
- **Estado Resultante en la BD:** Nuevo decano promovido en `Decano` y actualizado como titular de la `Facultad`; decano anterior archivado/inactivado de forma limpia.

---

### [PR-005] - Asignar Coordinador a Programa Académico con Actualización Reactiva y Transferencia de Dirección
- **Historias de Usuario que satisface:** HU066 (Gestión de coordinación de programas), HU050.
- **Propósito de Negocio:** Permite asignar la dirección de un programa académico a un profesional. Crea/actualiza la cuenta de usuario, le asigna el rol de `Coordinador` institucional y actualiza la FK `coordinador` en la entidad `Programa`.
- **Entidades del MER Involucradas:** `Usuario`, `Coordinador`, `Programa`, `Institucion`, `Facultad`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idPrograma` exista y pertenezca a una `Facultad` activa.
  2. Sincronizar los datos del usuario en la tabla `Usuario`.
  3. Verificar la presencia del rol en la tabla `Coordinador` para la `Institucion` dada; si no existe, insertarlo en estado activo.
  4. Actualizar el campo `coordinador` en `Programa` asignando la FK del nuevo `Coordinador`.
  5. Registrar el evento en la bitácora de cambios de administración académica.
- **Reglas de Negocio y Validaciones Específicas:**
  * Un coordinador debe estar asociado a la misma institución a la que pertenece la facultad del programa.
- **Estado Resultante en la BD:** El campo `coordinador` en `Programa` queda actualizado atómicamente con el rol `Coordinador` vigente.

---

### [PR-006] - Actualización Perfilada de Datos Personales de Usuario con Re-validación de Credenciales
- **Historias de Usuario que satisface:** HU050 (Gestión de cuentas de usuarios).
- **Propósito de Negocio:** Actualizar de forma segura nombres, apellidos, correo y contraseña de un usuario existente, verificando la no duplicidad del correo con otros usuarios activos antes de confirmar los cambios.
- **Entidades del MER Involucradas:** `Usuario`, `TipoIdentificacion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idUsuario` exista en la BD.
  2. Si el correo electrónico va a ser modificado, validar que no pertenezca a ningún otro usuario diferente en `Usuario`.
  3. Validar que el `idTipoIdentificacion` sea válido.
  4. Actualizar los campos `primerNombre`, `segundoNombre`, `primerApellido`, `segundoApellido`, `correo` y opcionalmente `password` en la tabla `Usuario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * No se permite cambiar el número de identificación ni el tipo de documento a menos que se invoque una transacción especial de rectificación de identidad (`PR-015`).
- **Estado Resultante en la BD:** `Usuario` actualizado con datos personales consistentes y correo único.

---

### [PR-007] - Desactivación Reactiva de Usuario con Inactivación en Cascada de Roles
- **Historias de Usuario que satisface:** HU050 (Gestión del estado de usuarios y seguridad).
- **Propósito de Negocio:** Cuando un usuario es inhabilitado (ej. por retiro de la universidad), la transacción marca `estado = 0` en `Usuario` y desactiva en cascada todos sus roles activos (`Docente`, `Estudiante`, `Coordinador`, `Decano`), evitando que conserve permisos en el sistema.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Estudiante`, `Coordinador`, `Decano`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idUsuario`.
  2. Actualizar el campo `estado = 0` en la tabla `Usuario`.
  3. Desactivar (`estado = 0`) en la tabla `Docente` si el usuario tenía registro.
  4. Desactivar (`estado = 0`) en la tabla `Estudiante` si el usuario tenía registro.
  5. Desactivar (`estado = 0`) en la tabla `Coordinador` si el usuario tenía registro.
  6. Desactivar (`estado = 0`) en la tabla `Decano` si el usuario tenía registro.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el usuario es el único `Decano` activo de una facultad o `Coordinador` de un programa, la transacción retorna una advertencia o exige la reasignación previa para evitar FKs inconsistentes.
- **Estado Resultante en la BD:** Usuario y todos sus registros de rol asociados quedan en `estado = 0` (inactivo).

---

### [PR-008] - Reactivación Integral de Usuario y Reincorporación a Estructuras Académicas
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Reactivar un usuario previamente inhabilitado, cambiando su estado a activo y restaurando sus roles institucionales principales tras verificación administrativa.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Estudiante`, `Coordinador`, `Decano`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idUsuario` inactivo (`estado = 0`).
  2. Actualizar `estado = 1` en la tabla `Usuario`.
  3. Reactivar reactivamente los roles de `Estudiante` o `Docente` asociados al usuario según la solicitud de reincorporación.
- **Reglas de Negocio y Validaciones Específicas:**
  * No reactiva automáticamente asignaciones a grupos cerrados o periodos académicos vencidos.
- **Estado Resultante en la BD:** Usuario con `estado = 1` y roles institucionales vigentes reactivados.

---

### [PR-009] - Sincronización Masiva de Cuentas Institucionales con Detección Automática de Duplicados
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Procesar un lote masivo de cuentas provenientes de sistemas externos. Por cada registro en el lote, ejecuta la lógica de creación/actualización reactiva omitiendo duplicados o registrándolos en una tabla de auditoría.
- **Entidades del MER Involucradas:** `Usuario`, `TipoIdentificacion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir lote de usuarios con datos de identificación y correo.
  2. Por cada elemento del lote, invocar internamente la lógica de `PR-001`.
  3. Capturar excepciones individuales y consolidar el conteo de insertados, actualizados y rechazados.
- **Reglas de Negocio y Validaciones Específicas:**
  * La transacción procesa el lote bajo un único `idCorrelacion` para garantizar la trazabilidad de la carga masiva.
- **Estado Resultante en la BD:** Múltiples registros sincronizados en `Usuario` con reporte consolidado de ejecución.

---

### [PR-010] - Conversión Reactiva de Rol (Promoción de Estudiante/Docente a Coordinador o Decano)
- **Historias de Usuario que satisface:** HU050, HU066, HU102.
- **Propósito de Negocio:** Permitir que un usuario que ya posee el rol de `Estudiante` o `Docente` adquiera un nuevo rol de gestión (`Coordinador` o `Decano`) sin necesidad de duplicar su cuenta de usuario ni alterar su histórico académico previo.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Estudiante`, `Coordinador`, `Decano`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idUsuario` exista y esté en estado activo (`estado = 1`).
  2. Identificar el nuevo rol a asignar (`Coordinador` o `Decano`).
  3. Verificar si el registro en la tabla de rol de destino ya existe:
     * Si no existe, insertar un nuevo registro relacionando `idUsuario`, `idInstitucion` y `estado = 1`.
     * Si existe pero estaba inactivo, reactivarlo (`estado = 1`).
  4. Mantener intactos los registros existentes en `Docente` o `Estudiante`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Un mismo `idUsuario` puede poseer múltiples roles activos en la misma `Institucion` manteniendo la integridad de sus claves primarias.
- **Estado Resultante en la BD:** El usuario mantiene su identidad única en `Usuario` y adquiere una nueva tupla en la tabla del rol otorgado.

---

### [PR-011] - Autenticación y Emisión de Contexto de Seguridad con Carga de Perfiles y Grupos Asignados
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Consultar y validar las credenciales de un usuario y, en un solo paso reactivo de lectura/auditoría, retornar todo el árbol de contexto: sus roles activos (`Docente`, `Estudiante`, etc.), instituciones vinculadas y lista de `Grupo` académicos asignados en el periodo vigente.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Estudiante`, `Coordinador`, `Decano`, `EstudianteGrupo`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar credenciales (`correo` / `password` o token de identidad externa) contra la tabla `Usuario`.
  2. Verificar que `estado = 1` en `Usuario`.
  3. Consultar la existencia de registros activos en `Docente`, `Estudiante`, `Coordinador` y `Decano`.
  4. Si es `Docente`, obtener los grupos vigentes donde es titular.
  5. Si es `Estudiante`, obtener sus matrículas activas en `EstudianteGrupo`.
  6. Retornar el objeto consolidado de sesión del usuario.
- **Reglas de Negocio y Validaciones Específicas:**
  * Deniega el acceso si el usuario está inactivo (`estado = 0`), retornando el mensaje descriptivo correspondiente.
- **Estado Resultante en la BD:** Lectura y verificación atómica con registro opcional de fecha de último acceso.

---

### [PR-012] - Cambio de Contraseña y Expiración de Credenciales con Auditoría de Seguridad
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Permite la actualización segura de la clave de acceso de un usuario previa validación de la contraseña anterior o token de recuperación, registrando la traza del cambio.
- **Entidades del MER Involucradas:** `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idUsuario`.
  2. Verificar que la contraseña anterior o el token de restablecimiento sea correcto.
  3. Hash/Encriptar la nueva contraseña e implemetarla en el campo `password` de `Usuario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * La nueva contraseña no debe ser igual a la anterior.
- **Estado Resultante en la BD:** Campo `password` en `Usuario` actualizado atómicamente.

---

### [PR-013] - Transferencia Institucional de Usuario entre Sedes/Instituciones con Conservación de Histórico
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Migrar la adscripción institucional de un estudiante o docente de una `Institucion` a otra, manteniendo su historial de notas y asistencias previo pero actualizando sus vinculaciones activas.
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `Docente`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la existencia de ambas entidades `Institucion` (origen y destino).
  2. Desactivar o archivar los registros de rol en la institución de origen.
  3. Insertar reactivamente los nuevos registros de rol (`Estudiante` / `Docente`) asociados a la `Institucion` de destino.
- **Reglas de Negocio y Validaciones Específicas:**
  * Conserva los registros pasados en `Asistencia` y `EstudianteGrupo` intactos para fines de auditoría histórica.
- **Estado Resultante en la BD:** Usuario adscrito a la nueva institución con historial previo preservado.

---

### [PR-014] - Depuración de Usuarios Inactivos sin Registro Operativo en el MER
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Eliminar de forma segura registros de usuarios en estado inactivo que fueron creados por error o pruebas y que NUNCA hayan registrado asistencias, matrículas ni notas en el sistema.
- **Entidades del MER Involucradas:** `Usuario`, `EstudianteGrupo`, `Asistencia`, `Docente`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idUsuario` tenga `estado = 0`.
  2. Verificar que el usuario no tenga referencias en `EstudianteGrupo`, `Asistencia`, `SolicitudRevisionAsistencia` ni sea titular en `Grupo`, `Facultad` o `Programa`.
  3. Si no tiene referencias operativas, eliminar sus registros en tablas de rol (`Docente`, `Estudiante`, etc.).
  4. Eliminar el registro en la tabla `Usuario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el usuario tiene al menos un registro operativo histórico, la transacción aborta la eliminación y retorna un mensaje de restricción de integridad.
- **Estado Resultante en la BD:** Eliminación física segura del registro sin violar claves foráneas.

---

---

### [PR-016] - Auditoría y Bloqueo Preventivo de Cuentas por Intentos Fallidos o Accesos Anómalos
- **Historias de Usuario que satisface:** HU050 (Seguridad y Control de Cuentas).
- **Propósito de Negocio:** Prevenir accesos no autorizados bloqueando atómicamente la cuenta (`estado = 0`) tras superar un umbral de intentos fallidos de autenticación, emitiendo un identificador de correlación para auditoría de seguridad.
- **Entidades del MER Involucradas:** `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir el `idUsuario` o `correo` objetivo y el contador de fallos.
  2. Verificar si el número de intentos supera el parámetro global de seguridad.
  3. Si lo supera, actualizar el campo `estado = 0` en la tabla `Usuario`.
  4. Registrar la traza en la bitácora de auditoría con `idCorrelacion`.
- **Reglas de Negocio y Validaciones Específicas:**
  * El bloqueo previene cualquier inicio de sesión adicional hasta que un administrador invoque `PR-008` o `PR-012`.
- **Estado Resultante en la BD:** `Usuario` inactivado por seguridad con registro de auditoría.

---

### [PR-017] - Asignación Reactiva de Administrador Institucional con Configuración de Alcance
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Otorga privilegios de administración global o de sede a un usuario existente o nuevo, vinculándolo a la entidad `Institucion`.
- **Entidades del MER Involucradas:** `Usuario`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la existencia de la `Institucion`.
  2. Sincronizar/Crear los datos del usuario en la tabla `Usuario`.
  3. Registrar o actualizar la tupla del perfil administrador asociándolo a la `Institucion`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere confirmación del Administrador raíz para otorgar alcance global.
- **Estado Resultante en la BD:** Usuario configurado con rol y permisos administrativos sobre la institución.

---

### [PR-018] - Sincronización de Correo Electrónico Institucional y Actualización de Dominios Habilitados
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Actualizar el dominio del correo institucional de un grupo de usuarios cuando la universidad cambia su dominio de correo (ej. de `@uco.edu.co` a `@uco.edu`), manteniendo la integridad de las cuentas.
- **Entidades del MER Involucradas:** `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir el dominio anterior y el nuevo dominio institucional.
  2. Identificar los registros en `Usuario` cuyo correo coincida con el dominio anterior.
  3. Reemplazar la extensión de correo conservando el identificador local previa validación de no duplicidad.
  4. Actualizar masivamente la tabla `Usuario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Aborta cualquier registro individual que genere conflicto de unicidad con un correo preexistente.
- **Estado Resultante en la BD:** Correos actualizados en `Usuario` bajo el nuevo dominio institucional.

---

### [PR-019] - Registro y Validación de Documentos de Identidad Especiales/Extranjeros
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Permitir dar de alta a estudiantes y docentes con pasaporte, cédula de extranjería o permiso especial de permanencia garantizando su correcta vinculación con `TipoIdentificacion`.
- **Entidades del MER Involucradas:** `Usuario`, `TipoIdentificacion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idTipoIdentificacion` corresponda a un código especial de documento (ej. 'PAS', 'CE', 'PEP').
  2. Sincronizar o crear el registro en `Usuario` validando el formato alfanumérico del número de identificación.
- **Reglas de Negocio y Validaciones Específicas:**
  * Acepta caracteres alfanuméricos para números de pasaporte o extranjería según la regla de validación del tipo.
- **Estado Resultante en la BD:** Registro en `Usuario` creado con documento extranjero validado.

---

### [PR-020] - Inactivación Temporal de Docente con Suspensión de Asignaciones a Grupos Activos
- **Historias de Usuario que satisface:** HU052, HU050.
- **Propósito de Negocio:** Suspender temporalmente el rol de un docente (ej. por comisión de estudios o licencia médica) sin borrar su usuario, desvinculándolo reactivamente de los grupos activos donde figura como titular.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idDocente`.
  2. Cambiar `estado = 0` en la tabla `Docente`.
  3. Identificar los `Grupo` activos del periodo donde el docente es titular.
  4. Dejar el campo `docente` en estado nulo o reasignar temporalmente según requerimiento.
- **Reglas de Negocio y Validaciones Específicas:**
  * Genera una lista de advertencia con los grupos que quedaron sin docente asignado para requerir su pronta reasignación (`PR-026`).
- **Estado Resultante en la BD:** `Docente` inactivo y grupos involucrados notificados para asignación de reemplazo.

---

### [PR-021] - Inactivación Temporal de Estudiante con Suspensión de Matrículas en Periodo Académico
- **Historias de Usuario que satisface:** HU053, HU050.
- **Propósito de Negocio:** Registrar la reserva de cupo o suspensión temporal de estudios de un alumno, inactivando su perfil de `Estudiante` y marcando sus matrículas activas en `EstudianteGrupo` como "SUSPENDIDA / CANCELADA VOLUNTARIA".
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `EstudianteGrupo`, `EstadoEstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idEstudiante` tenga matrículas activas en el periodo vigente.
  2. Actualizar `estado = 0` en la entidad `Estudiante`.
  3. Actualizar todas las filas en `EstudianteGrupo` para el periodo vigente al estado "CANCELADO_VOLUNTARIO".
  4. Liberar el cupo reservado en los respectivos `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * No elimina las asistencias históricas previamente tomadas en las sesiones transcurridas.
- **Estado Resultante en la BD:** Estudiante suspendido y cupos liberados en los grupos matriculados.

---

### [PR-022] - Sincronización Lote de Identidades de Estudiantes de Nuevo Ingreso
- **Historias de Usuario que satisface:** HU050, HU051, HU053.
- **Propósito de Negocio:** Procesar masivamente el listado de admisiones de un nuevo periodo. Crea usuarios, perfiles de `Estudiante` y su adscripción inicial en `EstudiantePrograma` en una sola transacción batch.
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `EstudiantePrograma`, `Programa`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir lista de estudiantes de nuevo ingreso con su `idPrograma`.
  2. Por cada estudiante:
     * Crear/Actualizar en `Usuario`.
     * Crear/Verificar en `Estudiante`.
     * Crear vinculación en `EstudiantePrograma`.
  3. Confirmar la carga masiva y retornar los IDs de estudiantes matriculados.
- **Reglas de Negocio y Validaciones Específicas:**
  * Valida que todos los programas indicados en el archivo estén activos.
- **Estado Resultante en la BD:** Cuentas de nuevo ingreso dadas de alta e inscritas formalmente en sus programas.

---

### [PR-023] - Sincronización Lote de Identidades de Planta Docente y Cátedra
- **Historias de Usuario que satisface:** HU050, HU052.
- **Propósito de Negocio:** Carga masiva de la nómina de profesores enviada por gestión humana para habilitar su disponibilidad antes del inicio del periodo académico.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir lista de docentes institucionales.
  2. Iterar ejecutando la creación reactiva en `Usuario` y `Docente`.
  3. Reportar en bitácora los docentes habilitados.
- **Reglas de Negocio y Validaciones Específicas:**
  * Evita la creación de duplicados por número de documento o correo institucional.
- **Estado Resultante en la BD:** Tabla `Docente` poblada con el personal académico activo.

---

### [PR-024] - Validación de Unicidad de Correo e Identificación con Generación de Reporte de Inconsistencias
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Procedimiento reactivo de diagnóstico e higiene de datos para detectar registros homónimos o colisiones de correo/documento antes de migraciones de periodo.
- **Entidades del MER Involucradas:** `Usuario`, `TipoIdentificacion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Escanear la tabla `Usuario` buscando duplicidades en `(tipoIdentificacion, numeroIdentificacion)` y en `correo`.
  2. Marcar temporalmente los registros con bandera de inconsistencia.
  3. Retornar el reporte detallado para acción administrativa.
- **Reglas de Negocio y Validaciones Específicas:**
  * Operación atómica de solo lectura de inconsistencias sin alterar datos sin autorización.
- **Estado Resultante en la BD:** Reporte de calidad de datos generado.

---

### [PR-025] - Registro de Usuario con Rol Único Temporal para Evaluadores Externos
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Registrar pares académicos o auditores externos otorgándoles un acceso temporal con fecha de expiración automática.
- **Entidades del MER Involucradas:** `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Sincronizar datos del usuario externo en `Usuario`.
  2. Configurar la vigencia de acceso temporal.
- **Reglas de Negocio y Validaciones Específicas:**
  * Al vencer la fecha de vigencia, la cuenta pasa automáticamente a `estado = 0`.
- **Estado Resultante en la BD:** Usuario temporal registrado en el sistema.

---

### [PR-026] - Reasignación Masiva de Grupo por Baja Definitiva de Docente
- **Historias de Usuario que satisface:** HU052, HU031.
- **Propósito de Negocio:** Cuando un docente renuncia o es dado de baja, este procedimiento transfiere atómicamente la titularidad de TODOS sus grupos activos a un nuevo docente asignado.
- **Entidades del MER Involucradas:** `Docente`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idDocenteSaliente` y el `idDocenteEntrante` sean docentes activos.
  2. Buscar todos los `Grupo` del periodo vigente donde el docente titular sea el saliente.
  3. Actualizar la clave foránea del docente en cada grupo asignando el `idDocenteEntrante`.
  4. Inactivar al docente saliente (`PR-020`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Verifica que el docente entrante no tenga conflictos de horario insuperables con los nuevos grupos transferidos.
- **Estado Resultante en la BD:** Grupos actualizados con el nuevo docente titular y docente saliente inactivado.

---

### [PR-027] - Reincorporación de Estudiante Graduado/Egresado como Docente o Investigador
- **Historias de Usuario que satisface:** HU050, HU052.
- **Propósito de Negocio:** Permitir que un egresado de la universidad que ya figura en la BD como `Estudiante` asuma el rol de `Docente` sin duplicar su cuenta original ni perder su historial de alumno.
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `Docente`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Localizar al usuario por documento en `Usuario`.
  2. Verificar que posea el rol `Estudiante` en estado inactivo/egresado.
  3. Insertar reactivamente una nueva fila en la tabla `Docente` vinculada al mismo `idUsuario`.
  4. Garantizar que el usuario quede en `estado = 1`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Mantiene intactas las tablas de historial del estudiante (`EstudianteGrupo`, `Asistencia`).
- **Estado Resultante en la BD:** Usuario con doble rol histórico (`Estudiante` egresado y `Docente` activo).

---

### [PR-028] - Limpieza y Unificación de Registros Duplicados de Usuario con Fusionado de Historial
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Corregir duplicados de usuarios creados por error en el pasado, re-vinculando todas sus matrículas, asistencias y grupos al `idUsuario` principal y eliminando el registro secundario.
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `Docente`, `EstudianteGrupo`, `Asistencia`, `SolicitudRevisionAsistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir `idUsuarioPrincipal` y `idUsuarioDuplicado`.
  2. Re-asignar las claves foráneas en `Estudiante` y `Docente` al `idUsuarioPrincipal`.
  3. Actualizar los registros en `EstudianteGrupo` y `Asistencia` que apuntaban al duplicado.
  4. Eliminar el registro en `Usuario` del ID duplicado.
- **Reglas de Negocio y Validaciones Específicas:**
  * Transacción estrictamente atómica: si falla la actualización de alguna tabla de asistencia, se deshace todo el fusionado.
- **Estado Resultante en la BD:** Historial unificado bajo un único `idUsuario` y duplicado eliminado.

---

### [PR-029] - Actualización de Términos, Condiciones y Políticas de Privacidad por Usuario
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Registrar la aceptación obligatoria de políticas de tratamiento de datos personales por parte de un usuario antes de permitirle navegar en la app.
- **Entidades del MER Involucradas:** `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idUsuario`.
  2. Registrar fecha, versión de política y confirmación en la entidad `Usuario` o su extensión.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el usuario rechaza los términos, su acceso permanece restringido a la pantalla de aceptación.
- **Estado Resultante en la BD:** Estado de conformidad de políticas guardado en la cuenta del usuario.

---

### [PR-030] - Cierre y Archivo Definitivo de Expediente de Usuario Institucional
- **Historias de Usuario que satisface:** HU050.
- **Propósito de Negocio:** Archivar de forma permanente el expediente de un usuario que se ha desvinculado de la universidad por más de 5 años, marcando la cuenta como archivada históricamente.
- **Entidades del MER Involucradas:** `Usuario`, `Docente`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el usuario lleve inactivo el tiempo reglamentario.
  2. Marcar `estado = 0` y bandera de archivo histórico en `Usuario`.
  3. Inactivar de forma definitiva todos los roles institucionales.
- **Reglas de Negocio y Validaciones Específicas:**
  * Conserva la integridad referencial para no romper consultas de reportes macro de periodos antiguos.
- **Estado Resultante en la BD:** Usuario archivado históricamente sin acceso a la plataforma.

---

### 📦 MÓDULO 2: Estructura Académica, Programas y Planes de Estudio (PR-031 a PR-060)

---

### [PR-031] - Crear Institución Académica con Configuración de Parámetros Globales Iniciales
- **Historias de Usuario que satisface:** Configuración Ecosistema BD.
- **Propósito de Negocio:** Registrar una nueva sede o institución universitaria en la base de datos, inicializando atómicamente sus parámetros de ausentismo, estados de estudiante y tipos de documento permitidos.
- **Entidades del MER Involucradas:** `Institucion`, `TipoIdentificacion`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el nombre de la institución sea único.
  2. Insertar nueva tupla en `Institucion` (`id`, `nombre`, `estado = 1`).
  3. Poblar los parámetros globales por defecto para la nueva institución.
- **Reglas de Negocio y Validaciones Específicas:**
  * El nombre de la institución no puede estar vacío ni repetido.
- **Estado Resultante en la BD:** `Institucion` creada y lista para alojar facultades y programas.

---

### [PR-032] - Crear Facultad con Vinculación Inmediata de Decano y Áreas Iniciales
- **Historias de Usuario que satisface:** HU102 (Gestión de Facultades).
- **Propósito de Negocio:** Dar de alta una `Facultad` académica asociándola a una `Institucion`, nombrando atómicamente a su `Decano` titular e inicializando sus áreas del conocimiento.
- **Entidades del MER Involucradas:** `Facultad`, `Institucion`, `Decano`, `Area`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Institucion` exista y esté activa.
  2. Validar o registrar al usuario decano y asegurar su perfil en `Decano` (`PR-004`).
  3. Insertar la nueva `Facultad` relacionando `nombre`, `institucion` y `decano`.
  4. Crear el `Area` general por defecto para la facultad.
- **Reglas de Negocio y Validaciones Específicas:**
  * No se permite crear una facultad sin un decano válido asignado.
- **Estado Resultante en la BD:** `Facultad` creada y vinculada a su institución, decano y área base.

---

### [PR-033] - Crear Programa Académico con Coordinador Asignado, Tipo de Programa y Facultad
- **Historias de Usuario que satisface:** HU051, HU066.
- **Propósito de Negocio:** Registrar una carrera profesional o posgrado (ej. Ingeniería de Sistemas). Asigna el `TipoPrograma`, lo vincula a la `Facultad` y nombra atómicamente al `Coordinador` responsable.
- **Entidades del MER Involucradas:** `Programa`, `Facultad`, `TipoPrograma`, `Coordinador`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia y estado activo de la `Facultad` y `TipoPrograma`.
  2. Sincronizar/Asignar al `Coordinador` institucional (`PR-005`).
  3. Insertar en `Programa` relacionando `nombre`, `facultad`, `tipoPrograma`, `coordinador` y `estado = 1`.
- **Reglas de Negocio y Validaciones Específicas:**
  * El nombre del programa debe ser único dentro de la misma facultad.
- **Estado Resultante en la BD:** `Programa` registrado y listo para estructurar planes de estudio.

---

### [PR-034] - Estructurar Plan de Estudio con Asignación Automática de Semestres Académicos
- **Historias de Usuario que satisface:** HU018, HU019.
- **Propósito de Negocio:** Crear la malla curricular (`PlanEstudio`) para un programa académico y generar automáticamente los registros de `SemestrePlanEstudio` para la cantidad de semestres definida (ej. 1 a 10 semestres).
- **Entidades del MER Involucradas:** `PlanEstudio`, `Programa`, `Semestre`, `SemestrePlanEstudio`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idPrograma` esté activo.
  2. Insertar el nuevo `PlanEstudio` (`nombre`, `programa`, `estado = 1`).
  3. Consultar los registros de la tabla `Semestre` (del 1 al N).
  4. Por cada semestre, crear la tupla en `SemestrePlanEstudio` asociando `planEstudio` y `semestre`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Un programa puede tener múltiples planes de estudio (ej. Plan 2018, Plan 2024), pero solo uno vigente para nuevos ingresos.
- **Estado Resultante en la BD:** `PlanEstudio` creado con toda la estructura de semestres lista para asociar materias.

---

---

### [PR-036] - Asociar Asignaturas a Semestres en el Plan de Estudios con Validación de Coherencia Curricular
- **Historias de Usuario que satisface:** HU025 (Consultar asignaturas por semestre en el plan de estudios).
- **Propósito de Negocio:** Asociar una asignatura a un semestre de un plan de estudios. La transacción valida atómicamente que no existan ciclos infinitos de prerrequisitos (ej. A depende de B y B depende de A).
- **Entidades del MER Involucradas:** `Asignatura`, `SemestrePlanEstudio`, `PlanEstudio`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la asignatura origen y la asignatura requerida pertenezcan al mismo `PlanEstudio`.
  2. Verificar que la asignatura prerrequisito esté en un `Semestre` anterior a la asignatura objetivo.
  3. Ejecutar algoritmo recursivo de grafos para verificar la ausencia de dependencias circulares.
  4. Registrar la relación de prerrequisito.
- **Reglas de Negocio y Validaciones Específicas:**
  * No se permite que una asignatura sea prerrequisito de sí misma ni de asignaturas de su mismo semestre.
- **Estado Resultante en la BD:** Prerrequisito registrado y validado en la estructura curricular.

---

### [PR-037] - Inactivar Programa Académico con Verificación de Planes de Estudio y Estudiantes Inscritos
- **Historias de Usuario que satisface:** HU051, HU066.
- **Propósito de Negocio:** Inactivar un programa académico que entra en liquidación o sustitución, deshabilitando sus nuevos ingresos mientras se protegen las matrículas de estudiantes activos hasta su graduación.
- **Entidades del MER Involucradas:** `Programa`, `PlanEstudio`, `EstudiantePrograma`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idPrograma`.
  2. Verificar la cantidad de estudiantes activos en `EstudiantePrograma`.
  3. Cambiar `estado = 0` en `Programa` impidiendo nuevas inscripciones.
  4. Inactivar los `PlanEstudio` asociados para nuevas aperturas.
- **Reglas de Negocio y Validaciones Específicas:**
  * Mantiene habilitados los grupos vigentes para estudiantes antiguos en proceso de culminación.
- **Estado Resultante en la BD:** `Programa` marcado con `estado = 0` para admisiones de nuevos estudiantes.

---

### [PR-038] - Crear Periodo Académico con Apertura de Calendario y Rangos de Fechas Validados
- **Historias de Usuario que satisface:** HU028, HU034, HU027.
- **Propósito de Negocio:** Registrar un nuevo ciclo lectivo (ej. "2026-1"), definiendo atómicamente la fecha de inicio (`fechaInicio`) y fin (`fechaFin`) que regirán los rangos válidos para abrir sesiones y registrar asistencias.
- **Entidades del MER Involucradas:** `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el código del periodo (ej. "2026-1") no exista previamente en `PeriodoAcademico`.
  2. Validar que `fechaFin` sea posterior a `fechaInicio`.
  3. Insertar la tupla en `PeriodoAcademico` (`id`, `codigo`, `fechaInicio`, `fechaFin`, `estado = 1`).
- **Reglas de Negocio y Validaciones Específicas:**
  * No se pueden solapar dos periodos académicos regulares en el mismo rango de fechas salvo periodos especiales vacacionales.
- **Estado Resultante en la BD:** `PeriodoAcademico` activo habilitado para aperturar oferta de grupos.

---

### [PR-039] - Actualizar Periodo Académico con Reprogramación de Rangos de Fechas en Sesiones y Grupos
- **Historias de Usuario que satisface:** HU028.
- **Propósito de Negocio:** Reajustar las fechas de inicio o fin de un periodo lectivo en curso (ej. por extensiones del calendario académico), actualizando reactivamente los límites de vigencia de todos sus grupos y sesiones programadas.
- **Entidades del MER Involucradas:** `PeriodoAcademico`, `Grupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idPeriodoAcademico` exista.
  2. Actualizar `fechaInicio` y/o `fechaFin` en `PeriodoAcademico`.
  3. Ajustar los rangos de vigencia de las entidades `Grupo` asociadas a este periodo.
  4. Reprogramar o validar las fechas en la tabla `Sesion` que queden fuera del nuevo rango.
- **Reglas de Negocio y Validaciones Específicas:**
  * No permite acortar un periodo a una fecha pasada que invalide sesiones que ya tengan asistencias registradas.
- **Estado Resultante en la BD:** Rangos del periodo y sesiones del calendario sincronizados.

---

### [PR-040] - Cierre Oficial de Periodo Académico con Consolidación de Estadísticas de Ausentismo
- **Historias de Usuario que satisface:** HU001, HU002, HU066, HU102.
- **Propósito de Negocio:** Concluir formalmente un periodo académico. Cierra reactivamente todas las sesiones pendientes, congela las asistencias, calcula los porcentajes finales de inasistencia por estudiante/grupo y cambia `estado = 0` en `PeriodoAcademico`.
- **Entidades del MER Involucradas:** `PeriodoAcademico`, `Grupo`, `Sesion`, `Asistencia`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el periodo académico se encuentre en la fecha de cierre o posterior.
  2. Cerrar atómicamente todas las `Sesion` del periodo que permanezcan en estado abierto (`PR-124`).
  3. Calcular y congelar el porcentaje final de ausentismo acumulado para cada `EstudianteGrupo`.
  4. Cambiar `estado = 0` en `PeriodoAcademico`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Al cerrar el periodo, se bloquean todas las modificaciones posteriores a registros de asistencia a través del flujo regular docente.
- **Estado Resultante en la BD:** `PeriodoAcademico` cerrado y consolidado estadísticamente.

---

### [PR-041] - Transferir Asignatura entre Áreas Académicas con Ajuste de Competencias
- **Historias de Usuario que satisface:** HU007.
- **Propósito de Negocio:** Reorganizar la estructura departamental reasignando una materia a una nueva `Area` del conocimiento dentro de la misma facultad o entre facultades.
- **Entidades del MER Involucradas:** `Asignatura`, `Area`, `Facultad`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idArea` de destino exista y esté activo.
  2. Actualizar el campo `area` en la tabla `Asignatura`.
- **Reglas de Negocio y Validaciones Específicas:**
  * No afecta las asignaciones previas de docentes ni las asistencias de grupos en curso.
- **Estado Resultante en la BD:** `Asignatura` adscrita a la nueva área académica.

---

### [PR-042] - Duplicación de Plan de Estudio para Nueva Versión Curricular con Migración de Malla
- **Historias de Usuario que satisface:** HU019.
- **Propósito de Negocio:** Agilizar la creación de un nuevo plan de estudio (ej. Plan 2026) clonando atómicamente toda la malla de asignaturas, semestres y componentes de un plan previo (ej. Plan 2020).
- **Entidades del MER Involucradas:** `PlanEstudio`, `SemestrePlanEstudio`, `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar el `idPlanEstudioOrigen`.
  2. Crear la nueva tupla en `PlanEstudio` con el nuevo nombre y versión.
  3. Clonar las relaciones de `SemestrePlanEstudio`.
  4. Clonar todas las `Asignatura` asociadas manteniendo sus clasificaciones.
- **Reglas de Negocio y Validaciones Específicas:**
  * El plan clonado se crea en estado borrador/inactivo hasta que sea habilitado formalmente.
- **Estado Resultante en la BD:** Nueva versión de `PlanEstudio` duplicada de forma idéntica.

---

### [PR-043] - Crear Componente Académico Institucional con Mapeo a Asignaturas Existentes
- **Historias de Usuario que satisface:** HU007.
- **Propósito de Negocio:** Crear un tipo de componente curricular (ej. "Núcleo Básico", "Electivas") y asociarlo reactivamente a un listado de materias del sistema.
- **Entidades del MER Involucradas:** `Componente`, `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el nombre del `Componente` no exista previamente.
  2. Insertar nueva tupla en `Componente` (`id`, `nombre`, `estado = 1`).
  3. Si se pasa una lista de `idAsignatura`, actualizar atómicamente la FK `componente` en cada una.
- **Reglas de Negocio y Validaciones Específicas:**
  * El nombre del componente debe ser representativo del plan formativo.
- **Estado Resultante en la BD:** `Componente` registrado y asignaturas vinculadas.

---

### [PR-044] - Crear Área de Conocimiento Institucional y Vinculación a Facultades
- **Historias de Usuario que satisface:** HU007.
- **Propósito de Negocio:** Dar de alta un departamento o área académica (ej. "Área de Ciencias de la Computación") asociándola a su respectiva `Facultad`.
- **Entidades del MER Involucradas:** `Area`, `Facultad`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Facultad` exista y esté activa.
  2. Insertar el nuevo registro en `Area` relacionando `nombre`, `facultad` y `estado = 1`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Un área debe pertenecer a una única facultad titular.
- **Estado Resultante en la BD:** Registro en `Area` creado correctamente.

---

### [PR-045] - Registrar Tipo de Programa Académico con Definición de Niveles de Formación
- **Historias de Usuario que satisface:** HU023, HU058.
- **Propósito de Negocio:** Mantenimiento del catálogo de niveles educativos (ej. Pregrado, Especialización, Maestría, Doctorado) utilizados para tipificar los programas institucionales.
- **Entidades del MER Involucradas:** `TipoPrograma`, `Programa`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el nombre en `TipoPrograma` no exista previamente.
  2. Insertar nueva tupla en `TipoPrograma` (`id`, `nombre`, `estado = 1`).
- **Reglas de Negocio and Validaciones Específicas:**
  * No se permite inactivar un `TipoPrograma` que tenga programas académicos activos asignados.
- **Estado Resultante en la BD:** `TipoPrograma` disponible en el catálogo de referencia.

---

### [PR-046] - Asignar Múltiples Coordinadores de Apoyo a Programas Académicos Complejos
- **Historias de Usuario que satisface:** HU066.
- **Propósito de Negocio:** Permitir que programas con alta matrícula asignen coordinadores auxiliares sin alterar el coordinador titular del programa.
- **Entidades del MER Involucradas:** `Programa`, `Coordinador`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la existencia del `Programa` y del `Coordinador`.
  2. Registrar la vinculación secundaria de coordinación de apoyo.
- **Reglas de Negocio y Validaciones Específicas:**
  * Todos los coordinadores auxiliares deben tener cuentas activas en `Usuario` y `Coordinador`.
- **Estado Resultante en la BD:** Coordinación de apoyo establecida.

---

### [PR-047] - Reestructuración de Semestres dentro de un Plan de Estudio Activo
- **Historias de Usuario que satisface:** HU018, HU019.
- **Propósito de Negocio:** Reordenar las asignaturas entre semestres dentro de un mismo plan de estudio (ej. mover "Matemáticas II" de 2do a 3er semestre).
- **Entidades del MER Involucradas:** `Asignatura`, `SemestrePlanEstudio`, `Semestre`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Asignatura` pertenezca al `PlanEstudio`.
  2. Localizar el nuevo `SemestrePlanEstudio` de destino.
  3. Actualizar la FK `semestrePlanEstudio` en la entidad `Asignatura`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Re-valida que la reestructuración no viole la coherencia de semestres con los prerrequisitos asignados (`PR-036`).
- **Estado Resultante en la BD:** Asignatura reubicada en el nuevo semestre del plan.

---

### [PR-048] - Retiro de Asignatura de Plan de Estudio con Verificación de Estudiantes Matriculados
- **Historias de Usuario que satisface:** HU007.
- **Propósito de Negocio:** Eliminar una asignatura obsoleta de un plan de estudio asegurando que no tenga grupos activos ni registros de estudiantes inscritos en el periodo vigente.
- **Entidades del MER Involucradas:** `Asignatura`, `Grupo`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Asignatura` no tenga grupos activos en el periodo actual.
  2. Si no tiene grupos vigentes, cambiar `estado = 0` en `Asignatura`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si tiene históricos de asistencias pasadas, se inactiva lógicamente (`estado = 0`) sin borrar el registro físico.
- **Estado Resultante en la BD:** `Asignatura` deshabilitada en la malla curricular.

---

### [PR-049] - Fusionar Dos Áreas Académicas con Re-asociación Automática de Asignaturas
- **Historias de Usuario que satisface:** HU007.
- **Propósito de Negocio:** Combinar dos áreas departamentales en una sola, transfiriendo atómicamente todas sus materias y reasignando el personal docente.
- **Entidades del MER Involucradas:** `Area`, `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que `idAreaOrigen` y `idAreaDestino` existan.
  2. Buscar todas las `Asignatura` que pertenezcan a `idAreaOrigen`.
  3. Actualizar el campo `area` asignando `idAreaDestino`.
  4. Inactivar `idAreaOrigen` (`estado = 0`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Transacción atómica integral para evitar asignaturas huérfanas sin área asociada.
- **Estado Resultante en la BD:** Materias re-asociadas a `idAreaDestino` y área de origen inactivada.

---

### [PR-050] - Configurar Parámetros de Ausentismo Máximo Permitido por Programa Académico
- **Historias de Usuario que satisface:** HU013, HU066.
- **Propósito de Negocio:** Definir o actualizar la regla institucional de porcentaje máximo de faltas permitido (ej. 20% para materias teóricas, 10% para laboratorios) que aplicará a los programas académicos.
- **Entidades del MER Involucradas:** `Programa`, `Parametro`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el porcentaje ingresado esté en el rango de 1 a 100.
  2. Actualizar o insertar el parámetro de ausentismo para el `Programa`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Aplica de forma inmediata a los cálculos reactivos de faltas en las sesiones de clase.
- **Estado Resultante en la BD:** Parámetro de ausentismo registrado y vigente.

---

### [PR-051] - Inactivar Facultad con Reubicación o Inactivación de Programas Académicos
- **Historias de Usuario que satisface:** HU102.
- **Propósito de Negocio:** Inactivar una facultad universitaria reubicando o cerrando en cascada sus programas académicos adscritos.
- **Entidades del MER Involucradas:** `Facultad`, `Programa`, `Decano`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Facultad` no tenga grupos activos en curso.
  2. Inactivar los `Programa` asociados que no hayan sido transferidos.
  3. Inactivar la titularidad del `Decano`.
  4. Actualizar `estado = 0` en `Facultad`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Bloquea la inactivación si existen materias con clases dictándose en el periodo actual.
- **Estado Resultante en la BD:** `Facultad` y sus dependencias inactivadas ordenadamente.

---

### [PR-052] - Habilitar Oferta de Asignaturas Electivas / Optativas por Periodo Académico
- **Historias de Usuario que satisface:** HU007, HU008.
- **Propósito de Negocio:** Marcar materias electivas para ser ofertadas en un periodo determinado sin necesidad de matricular a todos los programas de origen.
- **Entidades del MER Involucradas:** `Asignatura`, `PeriodoAcademico`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `PeriodoAcademico`.
  2. Marcar disponibilidad de la `Asignatura` para apertura de grupos opcionales.
- **Reglas de Negocio y Validaciones Específicas:**
  * Permite la inscripción cruzada de estudiantes de diferentes programas.
- **Estado Resultante en la BD:** Electivas habilitadas para programación de grupos.

---

### [PR-053] - Actualizar Créditos y Horas Semanales de Asignatura con Recálculo de Intensidad
- **Historias de Usuario que satisface:** HU007.
- **Propósito de Negocio:** Modificar la intensidad horaria o créditos académicos de una materia, recalculando el número estimado de sesiones teóricas del periodo.
- **Entidades del MER Involucradas:** `Asignatura`, `Grupo`, `Horario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la `Asignatura`.
  2. Actualizar los datos de intensidad horaria en `Asignatura`.
- **Reglas de Negocio y Validaciones Específicas:**
  * No altera de forma retroactiva las sesiones que ya han sido ejecutadas en periodos cerrados.
- **Estado Resultante en la BD:** Intensidad horaria de la asignatura actualizada.

---

### [PR-054] - Asociar Programa Académico a Múltiples Sedes/Instituciones
- **Historias de Usuario que satisface:** HU051.
- **Propósito de Negocio:** Habilitar la impartición de un programa académico en una nueva sede o institución adscrita.
- **Entidades del MER Involucradas:** `Programa`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia de `Programa` e `Institucion`.
  2. Crear la relación de disponibilidad multi-sede.
- **Reglas de Negocio y Validaciones Específicas:**
  * Permite aperturar grupos en la nueva institución bajo el mismo plan de estudio.
- **Estado Resultante en la BD:** Programa disponible en la nueva sede.

---

### [PR-055] - Generar Versión Histórica de Malla Curricular con Congelamiento de Cambios
- **Historias de Usuario que satisface:** HU019.
- **Propósito de Negocio:** Marcar un plan de estudio como "Histórico / Congelado", impidiendo cualquier modificación de asignaturas, créditos o semestres.
- **Entidades del MER Involucradas:** `PlanEstudio`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia de `PlanEstudio`.
  2. Deshabilitar permisos de edición sobre la malla curricular del plan.
- **Reglas de Negocio y Validaciones Específicas:**
  * Garantiza la inmutabilidad de los planes de estudio antiguos para fines de auditoría de graduados.
- **Estado Resultante en la BD:** `PlanEstudio` congelado históricamente.

---

### [PR-056] - Registrar Homologación Institucional de Asignaturas entre Programas
- **Historias of Usuario que satisface:** HU007.
- **Propósito de Negocio:** Establecer equivalencias oficiales entre dos asignaturas de programas distintos para reconocimiento automático de asistencias y contenidos.
- **Entidades del MER Involucradas:** `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que ambas `Asignatura` existan y estén activas.
  2. Registrar la tabla de equivalencias de homologación.
- **Reglas de Negocio y Validaciones Específicas:**
  * Exige que ambas materias tengan equivalencia en intensidad horaria o créditos.
- **Estado Resultante en la BD:** Tabla de homologación registrada.

---

### [PR-057] - Asignar Decano Interino a Facultad por Licencia o Vacante
- **Historias de Usuario que satisface:** HU102.
- **Propósito de Negocio:** Asignar temporalmente la decanatura de una facultad a un docente o coordinador por vacancia temporal.
- **Entidades del MER Involucradas:** `Facultad`, `Decano`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el usuario tenga perfil en `Decano` o crearlo reactivamente (`PR-004`).
  2. Actualizar el campo `decano` en `Facultad` marcando la condición de interinaje.
- **Reglas de Negocio y Validaciones Específicas:**
  * El interinaje tiene una fecha de vencimiento configurada en el sistema.
- **Estado Resultante en la BD:** Decano interino asignado a la facultad.

---

### [PR-058] - Asignar Coordinador Interino a Programa Académico
- **Historias de Usuario que satisface:** HU066.
- **Propósito de Negocio:** Asignar temporalmente la dirección de un programa académico durante una ausencia del titular.
- **Entidades del MER Involucradas:** `Programa`, `Coordinador`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar/Crear perfil en `Coordinador` para el usuario designado (`PR-005`).
  2. Actualizar el campo `coordinador` en `Programa`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Otorga temporalmente todos los permisos de gestión de grupos y justificaciones del programa.
- **Estado Resultante en la BD:** Coordinador interino registrado.

---

### [PR-059] - Auditoría Cambios Malla Curricular y Planes de Estudio
- **Historias de Usuario que satisface:** HU019.
- **Propósito de Negocio:** Registrar en la bitácora de auditoría cualquier adición, modificación o retiro de asignaturas en los planes de estudio.
- **Entidades del MER Involucradas:** `PlanEstudio`, `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir los datos de la modificación realizada sobre la malla.
  2. Insertar la traza con `idCorrelacion`, usuario responsable y valores anteriores/nuevos.
- **Reglas de Negocio y Validaciones Específicas:**
  * Inmutable y atómica con la mutación realizada sobre la estructura académica.
- **Estado Resultante en la BD:** Registro de auditoría de malla curricular guardado.

---

---

### 📦 MÓDULO 3: Oferta Académica, Grupos, Horarios y Asignación Docente (PR-061 a PR-090)

---

### [PR-061] - Apertura de Grupo Académico en Periodo con Asignación de Asignatura, Cupo Máximo y Docente Titular
- **Historias de Usuario que satisface:** HU043 (Crear nuevo grupo para materia), HU052 (Registro de docente en grupo).
- **Propósito de Negocio:** Abrir una clase/sección para una materia en el periodo lectivo activo. Define el nombre del grupo (ej. "Grupo 01"), establece el `cupoMaximo` y asigna atómicamente al `Docente` titular previa validación de su disponibilidad.
- **Entidades del MER Involucradas:** `Grupo`, `Asignatura`, `PeriodoAcademico`, `Docente`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia y estado activo de `Asignatura` y `PeriodoAcademico`.
  2. Validar que el `cupoMaximo` sea un entero mayor a cero.
  3. Si se especifica docente, verificar que el `idDocente` exista y no tenga cruce de horario.
  4. Insertar la tupla en `Grupo` (`nombre`, `asignatura`, `periodoAcademico`, `cupoMaximo`, `estado = 1`).
- **Reglas de Negocio y Validaciones Específicas:**
  * No se permite crear dos grupos con el mismo nombre para la misma asignatura en el mismo periodo académico.
- **Estado Resultante en la BD:** `Grupo` aperturado y disponible para asociar horarios e inscribir estudiantes.

---

### [PR-062] - Programación de Horario para Grupo con Validación de Cruces Horarios de Docente y Día
- **Historias de Usuario que satisface:** HU048 (Crear horarios para clases), HU034 (Validar cruce horario docente).
- **Propósito de Negocio:** Asignar la franja horaria (`horaInicio` a `horaFin`) y el día (`Dia`) a un grupo. La transacción valida reactivamente que el docente asignado al grupo no tenga otra clase programada a esa misma hora en otro grupo.
- **Entidades del MER Involucradas:** `Horario`, `Grupo`, `Dia`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `Grupo` y que `horaFin` sea posterior a `horaInicio`.
  2. Validar que el `idDia` exista en la tabla `Dia`.
  3. Consultar los horarios del docente titular del grupo para el mismo `Dia` en el periodo académico:
     * **Si existe superposición de horas:** Abortar la transacción emitiendo un mensaje descriptivo de cruce de horario.
  4. Insertar en `Horario` (`grupo`, `dia`, `horaInicio`, `horaFin`, `estado = 1`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Un grupo puede tener múltiples registros en `Horario` (ej. Lunes 08:00-10:00 y Miércoles 08:00-10:00).
- **Estado Resultante en la BD:** Franja horaria registrada en `Horario` sin colisión de agenda docente.

---

### [PR-063] - Reasignación de Docente Titular de Grupo con Ajuste de Horarios y Notificación de Cambio
- **Historias de Usuario que satisface:** HU044 (Actualizar datos de grupo), HU052.
- **Propósito de Negocio:** Reemplazar al profesor a cargo de una materia en curso. Valida que el nuevo docente cumpla con la disponibilidad horaria requerida para los horarios ya programados en el grupo.
- **Entidades del MER Involucradas:** `Grupo`, `Docente`, `Horario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el nuevo `idDocente` esté activo.
  2. Obtener todos los registros en `Horario` configurados para el `Grupo`.
  3. Verificar que el nuevo docente no tenga cruces de horario en ninguno de esos franjas.
  4. Actualizar la referencia del docente en la entidad `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el nuevo docente presenta cruces en alguna de las franjas horarias del grupo, la transacción rechaza el cambio.
- **Estado Resultante en la BD:** `Grupo` actualizado con el nuevo docente titular.

---

### [PR-064] - Cancelación de Grupo Académico con Desinscripción en Cascada y Liberación de Horarios
- **Historias de Usuario que satisface:** HU047 (Cancelar sesión/grupo), HU051 (Retirar estudiantes).
- **Propósito de Negocio:** Cancelar un grupo por baja matrícula u orden administrativa. Inactiva el grupo (`estado = 0`), cambia todas sus matrículas en `EstudianteGrupo` a "GRUPO_CANCELADO" e inactiva sus franjas horarias en una sola transacción atómica.
- **Entidades del MER Involucradas:** `Grupo`, `EstudianteGrupo`, `Horario`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `Grupo`.
  2. Cambiar `estado = 0` en `Grupo`.
  3. Inactivar (`estado = 0`) todas las tuplas en `Horario` asociadas al grupo.
  4. Actualizar las matrículas en `EstudianteGrupo` al estado "CANCELADO_POR_INSTITUCION".
  5. Inactivar o cancelar las `Sesion` futuras programadas que no tengan asistencias registradas.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el grupo ya tiene asistencias tomadas en sesiones dictadas, se preserva el historial atómicamente.
- **Estado Resultante en la BD:** Grupo e inscripciones canceladas ordenadamente.

---

### [PR-065] - Modificación de Cupo Máximo de Grupo con Verificación de Matriculados Activos
- **Historias de Usuario que satisface:** HU044.
- **Propósito de Negocio:** Ampliar o reducir la capacidad de estudiantes de un grupo, asegurando que el nuevo cupo no sea inferior al número de estudiantes ya matriculados activos.
- **Entidades del MER Involucradas:** `Grupo`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Contar la cantidad de estudiantes con matrícula activa en `EstudianteGrupo` para el `Grupo`.
  2. Validar que `nuevoCupoMaximo` sea mayor o igual al conteo de matriculados activos.
  3. Actualizar `cupoMaximo` en `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el nuevo cupo es menor a los alumnos inscritos, la transacción retorna error de restricción de capacidad.
- **Estado Resultante en la BD:** Campo `cupoMaximo` en `Grupo` actualizado.

---

### [PR-066] - Reprogramación de Horario de Grupo con Actualización Masiva de Fechas de Sesiones
- **Historias de Usuario que satisface:** HU049 (Modificar horarios), HU046 (Cambiar datos de sesión).
- **Propósito de Negocio:** Modificar el día u hora de una clase ya iniciada en el periodo y recalcular atómicamente las fechas de las futuras sesiones programadas en la tabla `Sesion`.
- **Entidades del MER Involucradas:** `Horario`, `Grupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar el `idHorario` y los nuevos datos de `dia`, `horaInicio` y `horaFin`.
  2. Verificar disponibilidad del docente en el nuevo horario (`PR-073`).
  3. Actualizar la tupla en `Horario`.
  4. Actualizar la fecha y horas en la tabla `Sesion` para las sesiones futuras sin asistencia tomada.
- **Reglas de Negocio y Validaciones Específicas:**
  * Las sesiones pasadas que ya cuentan con registros en `Asistencia` se mantienen inmutables.
- **Estado Resultante en la BD:** Horarios y sesiones futuras re-sincronizadas.

---

### [PR-067] - Asignación de Docente Auxiliar/Co-tutor a Grupo Académico Existente
- **Historias de Usuario que satisface:** HU052.
- **Propósito de Negocio:** Vincular a un docente secundario o jefe de laboratorio a un grupo que requiere acompañamiento sin reemplazar al docente principal.
- **Entidades del MER Involucradas:** `Grupo`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `Grupo` y el `Docente` auxiliar existan y estén activos.
  2. Registrar la co-titularidad docente en la estructura de asignación.
- **Reglas de Negocio y Validaciones Específicas:**
  * El docente auxiliar adquiere permisos para toma de asistencia en las sesiones del grupo.
- **Estado Resultante en la BD:** Docente auxiliar vinculado al grupo.

---

### [PR-068] - Fusionar Dos Grupos Académicos de la Misma Asignatura en un Periodo
- **Historias de Usuario que satisface:** HU044, HU050.
- **Propósito de Negocio:** Unir dos grupos con baja matrícula (ej. Grupo 1 con 5 alumnos y Grupo 2 con 8 alumnos) en un solo grupo destino, migrando reactivamente todas las matrículas y asistencias tomadas.
- **Entidades del MER Involucradas:** `Grupo`, `EstudianteGrupo`, `Asistencia`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que `idGrupoOrigen` y `idGrupoDestino` correspondan a la misma `Asignatura` y `PeriodoAcademico`.
  2. Verificar que la suma de matriculados activos no supere el `cupoMaximo` de `idGrupoDestino`.
  3. Re-vincular los registros de `EstudianteGrupo` del grupo origen al grupo destino.
  4. Inactivar `idGrupoOrigen` (`PR-064`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Mantiene la trazabilidad de las asistencias pasadas de los alumnos migrados.
- **Estado Resultante en la BD:** Estudiantes unificados en `idGrupoDestino` y grupo origen cerrado.

---

### [PR-069] - División/Desdoblamiento de Grupo Académico por Exceso de Cupo
- **Historias de Usuario que satisface:** HU043, HU050.
- **Propósito de Negocio:** Dividir un grupo con sobre-cupo en dos grupos independientes, creando el nuevo grupo, asignando docente y transfiriendo un porcentaje de los estudiantes matriculados.
- **Entidades del MER Involucradas:** `Grupo`, `EstudianteGrupo`, `Horario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Crear el nuevo `Grupo` secundario (`PR-061`).
  2. Asignar el horario y docente del nuevo grupo.
  3. Transferir el listado de estudiantes seleccionados de `EstudianteGrupo` al nuevo grupo.
- **Reglas de Negocio y Validaciones Específicas:**
  * Valida que la transferencia no deje a ninguno de los dos grupos en incumplimiento de cupos.
- **Estado Resultante en la BD:** Dos grupos funcionales con sus matriculados distribuidos.

---

### [PR-070] - Inactivación Temporizada de Grupo por Falta de Cupo Mínimo
- **Historias de Usuario que satisface:** HU047.
- **Propósito de Negocio:** Marcar en suspenso un grupo que no alcanzó el umbral mínimo de matriculados al cierre del periodo de inscripciones, notificando a coordinación para su cancelación o fusión.
- **Entidades del MER Involucradas:** `Grupo`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Verificar el número de inscritos en `EstudianteGrupo`.
  2. Si es menor al parámetro de cupo mínimo institucional, cambiar el estado del grupo a "EN_REVISION_CANCELACION".
- **Reglas de Negocio y Validaciones Específicas:**
  * Impide la generación de sesiones de clase mientras el grupo se encuentre en este estado.
- **Estado Resultante en la BD:** Grupo suspendido temporalmente.

---

### [PR-071] - Apertura Masiva de Grupos para Periodo Académico Basado en Oferta del Periodo Anterior
- **Historias de Usuario que satisface:** HU043.
- **Propósito de Negocio:** Clonar la estructura de grupos de un periodo anterior para el nuevo periodo lectivo, agilizando la preparación del calendario académico.
- **Entidades del MER Involucradas:** `Grupo`, `Horario`, `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar el `idPeriodoAnterior` y el `idPeriodoNuevo`.
  2. Obtener la lista de grupos activos del periodo anterior.
  3. Por cada grupo, crear la nueva tupla en `Grupo` para el nuevo periodo y clonar sus franjas en `Horario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Se crean sin docente asignado ni estudiantes matriculados para posterior ajuste.
- **Estado Resultante en la BD:** Oferta de grupos del nuevo periodo creada en lote.

---

### [PR-072] - Definición de Horarios Intensivos (Fin de Semana / Bloque) para Grupos Especiales
- **Historias de Usuario que satisface:** HU048.
- **Propósito de Negocio:** Configurar franjas horarias prolongadas (ej. Sábados de 08:00 a 16:00) para módulos postgrados o diplomados.
- **Entidades del MER Involucradas:** `Horario`, `Grupo`, `Dia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar los bloques de hora del horario intensivo.
  2. Verificar ausencia de cruce horario para el docente en todo el rango intensivo.
  3. Insertar los registros en `Horario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Valida que la duración total en horas no supere la intensidad semanal permitida.
- **Estado Resultante en la BD:** Horario intensivo programado.

---

### [PR-073] - Validar Cruces Horarios de Docente en Múltiples Grupos e Instituciones
- **Historias de Usuario que satisface:** HU034 (Validar consistencia horaria).
- **Propósito de Negocio:** Procedimiento de diagnóstico atómico que escanea todas las asignaciones horarias de un profesor en la universidad para certificar que no tenga traslapes de horas.
- **Entidades del MER Involucradas:** `Docente`, `Grupo`, `Horario`, `Dia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar todas las tuplas de `Horario` donde el docente sea titular en grupos activos.
  2. Evaluar colisiones en la fórmula `(horaInicioA < horaFinB) AND (horaFinA > horaInicioB)` para el mismo `Dia`.
  3. Retornar `estado = 1` si está libre o `estado = 0` con el detalle de los grupos en conflicto.
- **Reglas de Negocio y Validaciones Específicas:**
  * Función reactiva de validación previa consumida por `PR-062` y `PR-063`.
- **Estado Resultante en la BD:** Resultado de validación sin efectos secundarios de modificación.

---

### [PR-074] - Asignación de Aula / Ubicación Física a Horario de Grupo
- **Historias de Usuario que satisface:** HU048, HU044.
- **Propósito de Negocio:** Vincular el espacio físico (ej. "Aula 302", "Laboratorio de Cómputo 1") a un horario de clase, validando la no ocupación del aula por otro grupo.
- **Entidades del MER Involucradas:** `Horario`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la disponibilidad del aula en el día y rango horario.
  2. Registrar la asignación del espacio físico en la tupla de `Horario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Previene la asignación simultánea de una misma aula a dos grupos distintos.
- **Estado Resultante en la BD:** Aula asignada al horario de clase.

---

### [PR-075] - Retiro de Horario de Grupo con Cancelación de Sesiones Futuras Afectadas
- **Historias de Usuario que satisface:** HU049.
- **Propósito de Negocio:** Eliminar una de las franjas semanales de un grupo (ej. eliminar la clase de los Viernes), cancelando o ajustando automáticamente las sesiones asociadas a esa franja.
- **Entidades del MER Involucradas:** `Horario`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia del `idHorario`.
  2. Inactivar el registro en `Horario`.
  3. Eliminar o cancelar las `Sesion` futuras que dependían exclusivamente de ese horario y no tengan asistencias tomadas.
- **Reglas de Negocio y Validaciones Específicas:**
  * Preserva las sesiones pasadas que ya tienen asistencias registradas.
- **Estado Resultante en la BD:** Franja horaria retirada y sesiones futuras limpiadas.

---

### [PR-076] - Registrar Grupo Magistral con Subgrupos de Práctica o Laboratorio
- **Historias de Usuario que satisface:** HU043.
- **Propósito de Negocio:** Aperturar una clase magistral teórica que se subdivide en varios grupos pequeños de laboratorio o talleres prácticos.
- **Entidades del MER Involucradas:** `Grupo`, `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Crear el grupo principal teórico (`PR-061`).
  2. Crear reactivamente los subgrupos vinculados al grupo principal.
- **Reglas de Negocio y Validaciones Específicas:**
  * Los estudiantes matriculados en el grupo magistral deben quedar asignados a uno de los subgrupos de práctica.
- **Estado Resultante en la BD:** Estructura de grupo teóricopráctico establecida.

---

### [PR-077] - Cambiar Estado de Grupo de "En Preparación" a "Habilitado para Matrícula"
- **Historias de Usuario que satisface:** HU044.
- **Propósito de Negocio:** Confirmar que un grupo tiene docente y horario configurados, cambiando su estado a activo para permitir las inscripciones de estudiantes.
- **Entidades del MER Involucradas:** `Grupo`, `Horario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `Grupo` tenga al menos una franja horaria configurada en `Horario`.
  2. Validar que tenga docente titular asignado.
  3. Actualizar `estado = 1` en `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Impide habilitar la matrícula en grupos sin horarios válidos registrados.
- **Estado Resultante en la BD:** `Grupo` abierto para inscripciones.

---

### [PR-078] - Bloquear Grupo para Nuevas Matrículas Manteniendo Sesiones Activas
- **Historias de Usuario que satisface:** HU044.
- **Propósito de Negocio:** Cerrar las inscripciones de un grupo que ya inició clases o completó su cupo de sobre-demanda, sin suspender el dictado de las sesiones.
- **Entidades del MER Involucradas:** `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Actualizar la bandera de bloqueo de matrícula en `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Impide que los estudiantes o coordinadores agreguen nuevos matriculados por el canal regular.
- **Estado Resultante en la BD:** Grupo cerrado para inscripciones.

---

### [PR-079] - Reubicación de Grupo a Nuevo Horario por Fuerza Mayor
- **Historias de Usuario que satisface:** HU049.
- **Propósito de Negocio:** Mover en bloque todo el esquema de horarios de un grupo debido a imprevistos en la infraestructura universitaria.
- **Entidades del MER Involucradas:** `Grupo`, `Horario`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Actualizar las tuplas en `Horario`.
  2. Regenerar las fechas de las `Sesion` pendientes del periodo.
- **Reglas de Negocio y Validaciones Específicas:**
  * Re-valida la disponibilidad del docente y la no colisión con las matrículas de los estudiantes.
- **Estado Resultante en la BD:** Horario del grupo reubicado.

---

### [PR-080] - Asignar Docente Suplente Temporal para un Rango de Fechas en un Grupo
- **Historias de Usuario que satisface:** HU052.
- **Propósito de Negocio:** Habilitar a un profesor reemplazante para tomar asistencia en un grupo durante una o dos semanas por incapacidad del titular.
- **Entidades del MER Involucradas:** `Grupo`, `Docente`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar el `idDocenteSuplente` y el rango de fechas.
  2. Registrar la suplencia otorgando permisos sobre las `Sesion` del rango especificado.
- **Reglas de Negocio y Validaciones Específicas:**
  * Al vencer el rango de fechas, la titularidad vuelve exclusivamente al docente principal.
- **Estado Resultante en la BD:** Suplencia docente configurada.

---

### [PR-081] - Generar Calendario Teórico de Sesiones del Grupo Basado en sus Horarios y Días
- **Historias de Usuario que satisface:** HU028, HU045.
- **Propósito de Negocio:** Generar de forma preventiva todas las tuplas de la tabla `Sesion` para un grupo desde la fecha de inicio hasta el fin del periodo lectivo según sus horarios.
- **Entidades del MER Involucradas:** `Grupo`, `Horario`, `Dia`, `Sesion`, `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Obtener las fechas de inicio y fin del `PeriodoAcademico`.
  2. Obtener los días de la semana y horas configurados en `Horario`.
  3. Iterar por cada fecha del calendario correspondiente a esos días.
  4. Insertar las tuplas correspondientes en `Sesion` (`grupo`, `fechaHoraInicio`, `fechaHoraFin`, `estado = ABIERTA`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Omite automáticamente las fechas marcadas como festivas o días no lectivos (`PR-088`).
- **Estado Resultante en la BD:** Calendario de sesiones poblado en `Sesion`.

---

### [PR-082] - Extensión de Fecha Fin de Grupo Académico con Ajuste de Calendario
- **Historias de Usuario que satisface:** HU046.
- **Propósito de Negocio:** Extender la duración de un grupo por dictado de clases de recuperación, adicionando nuevas sesiones al final del periodo.
- **Entidades del MER Involucradas:** `Grupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la nueva fecha límite del grupo.
  2. Generar e insertar las nuevas tuplas en `Sesion` para las clases adicionales.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere autorización de la coordinación del programa.
- **Estado Resultante en la BD:** Sesiones adicionales incorporadas al grupo.

---

### [PR-083] - Ajustar Cupos Reservados para Estudiantes de Reingreso o Transferencia
- **Historias de Usuario que satisface:** HU044.
- **Propósito de Negocio:** Bloquear temporalmente 2 o 3 vacantes del `cupoMaximo` de un grupo para admisiones especiales.
- **Entidades del MER Involucradas:** `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Registrar la reserva de cupos en la entidad `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Reduce el cupo disponible para matrícula regular en el portal público.
- **Estado Resultante en la BD:** Cupos reservados en el grupo.

---

### [PR-084] - Auditoría de Asignación Docente y Cambios de Horarios en Grupos
- **Historias de Usuario que satisface:** HU044, HU049.
- **Propósito de Negocio:** Registrar en la bitácora la traza de modificaciones sobre docentes titulares, aulas y franjas horarias de los grupos.
- **Entidades del MER Involucradas:** `Grupo`, `Horario`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Insertar el evento en la tabla de auditoría con `idCorrelacion` y detalle de cambios.
- **Reglas de Negocio y Validaciones Específicas:**
  * Inmutable y atómico.
- **Estado Resultante en la BD:** Traza de auditoría guardada.

---

### [PR-085] - Sincronización de Grupos desde Sistema Externo de Registro Académico
- **Historias de Usuario que satisface:** HU043.
- **Propósito de Negocio:** Integrar masivamente la oferta de clases proveniente de la plataforma central ERP.
- **Entidades del MER Involucradas:** `Grupo`, `Asignatura`, `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir lote de grupos externos.
  2. Ejecutar inserción/actualización reactiva de `Grupo` y `Horario`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Evita la creación de grupos duplicados.
- **Estado Resultante en la BD:** Grupos externos sincronizados.

---

### [PR-086] - Cierre Definitivo de Grupo Académico al Concluir el Periodo
- **Historias de Usuario que satisface:** HU044.
- **Propósito de Negocio:** Concluir las actividades de un grupo, deshabilitando cualquier modificación a su plantilla y asistencias.
- **Entidades del MER Involucradas:** `Grupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que todas las `Sesion` del grupo estén en estado cerrado.
  2. Actualizar `estado = 0` o "FINALIZADO" en `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Congela las planillas de asistencia para consulta histórica.
- **Estado Resultante en la BD:** Grupo finalizado.

---

### [PR-087] - Habilitación de Grupo Extemporáneo/Vacacional
- **Historias de Usuario que satisface:** HU043.
- **Propósito de Negocio:** Crear un grupo de cursos de verano o nivelación rápida fuera del calendario regular.
- **Entidades del MER Involucradas:** `Grupo`, `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar el periodo especial vacacional.
  2. Aperturar el grupo con su docente e intensidad horaria rápida.
- **Reglas de Negocio y Validaciones Específicas:**
  * Permite horarios diarios intensivos.
- **Estado Resultante en la BD:** Grupo vacacional activo.

---

### [PR-088] - Asignación de Días No Lectivos / Festivos a Calendario de Grupos
- **Historias de Usuario que satisface:** HU045.
- **Propósito de Negocio:** Registrar feriados nacionales o suspensiones institucionales, cancelando automáticamente las sesiones de clase programadas en esos días.
- **Entidades del MER Involucradas:** `Sesion`, `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir la fecha festiva.
  2. Identificar las `Sesion` programadas en esa fecha.
  3. Marcar las sesiones como "CANCELADA_FESTIVO".
- **Reglas de Negocio y Validaciones Específicas:**
  * Las sesiones canceladas por festivo no cuentan como faltas de inasistencia para los estudiantes.
- **Estado Resultante en la BD:** Sesiones en días festivos omitidas.

---

### [PR-089] - Intercambio de Docentes Titulares entre Dos Grupos Sin Aflicción de Horarios
- **Historias de Usuario que satisface:** HU044, HU052.
- **Propósito de Negocio:** Permutar los profesores de dos materias (ej. Profesor A pasa al Grupo 2 y Profesor B pasa al Grupo 1) en una única transacción atómica.
- **Entidades del MER Involucradas:** `Grupo`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que ambos docentes estén disponibles para los respectivos horarios permutados.
  2. Actualizar el docente en `Grupo1` asignando a `DocenteB`.
  3. Actualizar el docente en `Grupo2` asignando a `DocenteA`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si cualquiera de los dos presenta cruce de horario en la permutación, toda la transacción se revierte.
- **Estado Resultante en la BD:** Docentes permutados en sus grupos.

---

---

### 📦 MÓDULO 4: Matrículas, Enrolamiento de Estudiantes y Estado en Grupos (PR-091 a PR-120)

---

### [PR-091] - Enrolamiento de Estudiante en Programa Académico (Sincronización de Estudiante + Registro en Programa)
- **Historias de Usuario que satisface:** HU051 (Registro automático de estudiantes en programa), HU050.
- **Propósito de Negocio:** Vincular a un estudiante a una carrera o programa universitario. Sincroniza la cuenta en `Usuario`, asegura el perfil en `Estudiante` y crea la tupla en `EstudiantePrograma` en una sola llamada.
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `Programa`, `EstudiantePrograma`, `Institucion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la existencia del `idPrograma` y que pertenezca a una `Institucion` activa.
  2. Sincronizar/Crear datos en `Usuario` (`PR-001`).
  3. Asegurar la presencia del perfil en `Estudiante` (`idUsuario`, `idInstitucion`).
  4. Consultar si ya existe la vinculación en `EstudiantePrograma`:
     * **Si NO existe:** Insertar en `EstudiantePrograma` (`estudiante`, `programa`, `estado = 1`).
     * **Si existe:** Asegurar que `estado = 1`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Un estudiante puede estar matriculado en más de un programa académico si la institución lo permite.
- **Estado Resultante en la BD:** Estudiante matriculado en el programa académico.

---

### [PR-092] - Matrícula Reactiva de Estudiante en Grupo con Validación de Asignaturas y Plan de Estudios, Cupos y Cruces Horarios
- **Historias de Usuario que satisface:** HU053 (Inscripción de estudiantes en grupo), HU026, HU034.
- **Propósito de Negocio:** Inscribir a un estudiante en una asignatura/grupo específica. Valida atómicamente el cupo disponible, la vigencia del grupo, los prerrequisitos de la asignatura y que el alumno no tenga colisión de horario con otras materias matriculadas.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`, `Estudiante`, `EstadoEstudianteGrupo`, `Horario`, `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `Grupo` esté activo y con `cupoMaximo` disponible.
  2. Validar que el estudiante no esté ya matriculado en el mismo grupo o en otro grupo de la misma asignatura en el mismo periodo.
  3. Verificar el pertenencia de la `Asignatura` al `PlanEstudio` del estudiante.
  4. Verificar ausencia de cruce horario con sus otros grupos matriculados en el periodo.
  5. Obtener el `idEstadoEstudianteGrupo` correspondiente a "MATRICULADO / ACTIVO".
  6. Insertar en `EstudianteGrupo` (`estudiante`, `grupo`, `estadoEstudianteGrupo`, `estado = 1`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el cupo está agotado o existe cruce horario, rechaza la transacción informando el motivo técnico.
- **Estado Resultante en la BD:** Tupla creada en `EstudianteGrupo` con estado activo.

---

### [PR-093] - Matrícula Masiva por Lote de Estudiantes en Lista de Clases
- **Historias de Usuario que satisface:** HU053.
- **Propósito de Negocio:** Procesar masivamente el listado de alumnos para una sección antes del inicio de clases (ej. carga de archivo plano de admisiones).
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir lista de estudiantes y el `idGrupo`.
  2. Por cada estudiante en el lote:
     * Ejecutar la lógica atómica de `PR-092`.
  3. Retornar el número de alumnos inscritos exitosamente y la lista de rechazados con causa.
- **Reglas de Negocio y Validaciones Específicas:**
  * La transacción evalúa el cupo máximo restante por cada iteración.
- **Estado Resultante en la BD:** Grupo poblado con su plantilla de estudiantes.

---

### [PR-094] - Cambio de Estado de Estudiante en Grupo (Activo, Retirado, Cancelado por Ausentismo)
- **Historias de Usuario que satisface:** HU004 (Ver estado de estudiante en grupo).
- **Propósito de Negocio:** Actualizar la condición administrativa de un estudiante dentro de un grupo (ej. cambiar de "MATRICULADO" a "RETIRADO_DISCIPLINARIO" o "CANCELADO_AUSENTISMO").
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `EstadoEstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idEstadoEstudianteGrupo` exista en el catálogo de referencia.
  2. Actualizar el campo `estadoEstudianteGrupo` en la entidad `EstudianteGrupo`.
  3. Registrar la fecha y usuario responsable de la mutación de estado.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el estado cambia a cancelado o retirado, se libera el cupo reservado para el grupo.
- **Estado Resultante en la BD:** Campo `estadoEstudianteGrupo` actualizado atómicamente.

---

### [PR-095] - Cancelación de Matrícula de Estudiante en Grupo por Solicitud Voluntaria
- **Historias de Usuario que satisface:** HU026, HU051.
- **Propósito de Negocio:** Procesar el retiro voluntario de una materia por parte del alumno dentro de las fechas límites permitidas por el reglamento académico.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `EstadoEstudianteGrupo`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la solicitud esté dentro de la fecha límite de retiros de asignaturas.
  2. Actualizar el estado en `EstudianteGrupo` a "CANCELADO_VOLUNTARIO".
  3. Liberar la vacante en la capacidad del `Grupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Conserva las asistencias previamente registradas para fines de historial académico.
- **Estado Resultante en la BD:** Estudiante retirado del grupo y cupo disponible.

---

### [PR-096] - Cancelación Automática de Matrícula en Grupo por Exceso de Inasistencias
- **Historias de Usuario que satisface:** HU013, HU096.
- **Propósito de Negocio:** Aplicar la norma reglamentaria de pérdida de materia por faltas. Cuando el porcentaje de inasistencias supera el límite (ej. 20%), el procedimiento cancela automáticamente la matrícula.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Asistencia`, `EstadoEstudianteGrupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Calcular el % de faltas sobre el total de sesiones programadas o dictadas.
  2. Verificar si supera el umbral parametrizado en la institución (`PR-050`).
  3. Si lo supera, actualizar el estado en `EstudianteGrupo` a "CANCELADO_POR_INASISTENCIA".
  4. Generar la notificación oficial para el estudiante y la coordinación.
- **Reglas de Negocio y Validaciones Específicas:**
  * Procedimiento atómico invocado al cerrar sesiones (`PR-124`) o por ejecutor programado.
- **Estado Resultante en la BD:** Matrícula cancelada automáticamente con causal de ausentismo.

---

### [PR-097] - Transferencia de Estudiante de un Grupo a Otro en la Misma Asignatura con Migración de Asistencias
- **Historias de Usuario que satisface:** HU026, HU053.
- **Propósito de Negocio:** Cambiar a un estudiante del Grupo 1 al Grupo 2 de la misma materia, migrando sus asistencias previas para no perjudicar su registro.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar disponibilidad de cupo en `GrupoDestino`.
  2. Inactivar la tupla en `EstudianteGrupo` del grupo origen.
  3. Crear la nueva tupla en `EstudianteGrupo` en el grupo destino.
  4. Re-vincular o ajustar las asistencias pasadas a las fechas equivalentes del nuevo grupo.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere que ambos grupos pertenezcan a la misma `Asignatura` y `PeriodoAcademico`.
- **Estado Resultante en la BD:** Estudiante transferido al nuevo grupo con histórico adaptado.

---

### [PR-098] - Procesar Solicitud de Inscripción Exclusiva/Extemporánea de Estudiante en Grupo
- **Historias de Usuario que satisface:** HU053 (Aceptar solicitud para unirse a grupo).
- **Propósito de Negocio:** Permitir que el docente o coordinador apruebe la adición de un estudiante fuera del periodo regular de matrículas.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`, `EstadoEstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la solicitud pendiente del estudiante.
  2. Crear/Actualizar la tupla en `EstudianteGrupo` en estado "MATRICULADO_EXTEMPORANEO".
- **Reglas de Negocio y Validaciones Específicas:**
  * Permite sobrepasar excepcionalmente el `cupoMaximo` si cuenta con la firma digital del coordinador (`PR-108`).
- **Estado Resultante en la BD:** Estudiante inscrito extemporáneamente.

---

### [PR-099] - Rechazo de Solicitud de Inscripción de Estudiante con Notificación y Liberación de Cupo
- **Historias de Usuario que satisface:** HU054 (Rechazar solicitud para unirse a grupo).
- **Propósito de Negocio:** Rechazar formalmente una petición de ingreso a un grupo con sobre-demanda.
- **Entidades del MER Involucradas:** `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Actualizar la solicitud a estado "RECHAZADA".
  2. Notificar al estudiante la causa de no aceptación.
- **Reglas de Negocio y Validaciones Específicas:**
  * No genera ningún registro de asistencia ni reserva en el grupo.
- **Estado Resultante en la BD:** Solicitud rechazada.

---

### [PR-100] - Inactivación de Estudiante en Programa Académico por Retiro Definitivo o Graduación
- **Historias de Usuario que satisface:** HU051, HU100.
- **Propósito de Negocio:** Dar de baja la vinculación de un alumno con su programa académico por graduación o deserción formal.
- **Entidades del MER Involucradas:** `EstudiantePrograma`, `Programa`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Actualizar `estado = 0` en `EstudiantePrograma`.
  2. Inactivar o cerrar las matrículas activas en `EstudianteGrupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Registra el motivo oficial de la desvinculación.
- **Estado Resultante en la BD:** Estudiante desvinculado del programa.

---

### [PR-101] - Reincorporación/Reingreso de Estudiante a Programa Académico
- **Historias de Usuario que satisface:** HU051.
- **Propósito de Negocio:** Reactivar la ficha académica de un estudiante que vuelve a la universidad tras un periodo de retiro.
- **Entidades del MER Involucradas:** `EstudiantePrograma`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el estudiante tenga historial previo en `EstudiantePrograma`.
  2. Reactivar `estado = 1` en `EstudiantePrograma`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Habilita al estudiante para matricular nuevos grupos en el periodo vigente.
- **Estado Resultante en la BD:** Ficha académica reincorporada.

---

### [PR-102] - Matrícula de Estudiante Asistente / Oyente en Grupo Académico
- **Historias de Usuario que satisface:** HU026.
- **Propósito de Negocio:** Registrar a un estudiante en modalidad de "Oyente" para seguimiento de asistencia sin efectos de nota ni créditos.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `EstadoEstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar disponibilidad de cupo para oyentes.
  2. Insertar en `EstudianteGrupo` con el estado especial "OYENTE_AUTORIZADO".
- **Reglas de Negocio y Validaciones Específicas:**
  * Se incluye en la lista de asistencia del docente pero se excluye de reportes de ausentismo obligatorio.
- **Estado Resultante en la BD:** Estudiante registrado como oyente.

---

### [PR-103] - Registro de Estudiante en Plan de Estudio Específico
- **Historias de Usuario que satisface:** HU019, HU051.
- **Propósito de Negocio:** Asignar la versión exacta de la malla curricular (`PlanEstudio`) a un estudiante dentro de su programa.
- **Entidades del MER Involucradas:** `EstudiantePrograma`, `PlanEstudio`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `PlanEstudio` pertenezca al `Programa`.
  2. Asignar la referencia del plan en la ficha del estudiante.
- **Reglas de Negocio y Validaciones Específicas:**
  * Determina cuáles asignaturas son obligatorias para la graduación del alumno.
- **Estado Resultante en la BD:** Plan de estudio asignado al alumno.

---

### [PR-104] - Validación de Límite de Créditos / Asignaturas Simultáneas por Estudiante en Periodo
- **Historias de Usuario que satisface:** HU026.
- **Propósito de Negocio:** Verificar que un estudiante no matricule más materias de las permitidas por el reglamento en un mismo periodo.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`, `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Contar la cantidad de grupos activos matriculados por el alumno en el periodo.
  2. Comparar contra el límite máximo parametrizado.
  3. Retornar estado de validez.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si excede el límite, la transacción de matrícula (`PR-092`) es bloqueada.
- **Estado Resultante en la BD:** Resultado de diagnóstico de carga académica.

---

### [PR-105] - Cambio Masivo de Estado en Grupo para Estudiantes Inactivos o No Regulados
- **Historias de Usuario que satisface:** HU004, HU051.
- **Propósito de Negocio:** Depurar las listas de clase inactivando en bloque a los alumnos que no formalizaron su pago de matrícula financiera.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `EstadoEstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir lista de estudiantes no regulados.
  2. Actualizar su estado en `EstudianteGrupo` a "NO_REGULADO_FINANCIERO".
  3. Liberar sus cupos en los grupos correspondientes.
- **Reglas de Negocio y Validaciones Específicas:**
  * Impide que los docentes sigan marcando asistencias para estos estudiantes.
- **Estado Resultante en la BD:** Plantillas de clase depuradas.

---

### [PR-106] - Enrolamiento Directo por Archivo Masivo CSV/Excel de Estudiantes en Grupos
- **Historias de Usuario que satisface:** HU053, HU050.
- **Propósito de Negocio:** Importar la lista definitiva de matriculados enviada por la oficina de registro académico.
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `EstudianteGrupo`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Procesar el archivo masivo creando usuarios nuevos si no existen.
  2. Registrar matrículas en `EstudianteGrupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Operación batch que omite duplicados y genera reporte de consistencia.
- **Estado Resultante en la BD:** Enrolamiento masivo completado.

---

### [PR-107] - Reserva de Cupo de Estudiante en Grupo para Periodo Siguiente
- **Historias de Usuario que satisface:** HU026.
- **Propósito de Negocio:** Pre-matricular a un alumno en un grupo para el semestre venidero.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `EstadoEstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Insertar en `EstudianteGrupo` con estado "PRE_MATRICULADO_RESERVA".
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere confirmación final al iniciar el nuevo periodo lectivo.
- **Estado Resultante en la BD:** Pre-matrícula registrada.

---

### [PR-108] - Habilitación Excepcional de Matrícula con Sobre-cupo Autorizado por Coordinador
- **Historias de Usuario que satisface:** HU053, HU066.
- **Propósito de Negocio:** Permitir matricular a un estudiante en un grupo cuyo `cupoMaximo` está lleno, previa autorización de la coordinación.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`, `Coordinador`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la firma digital del `Coordinador`.
  2. Incrementar temporalmente en 1 el `cupoMaximo` del `Grupo`.
  3. Insertar la tupla en `EstudianteGrupo`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Registra en la traza de auditoría quién autorizó el sobre-cupo.
- **Estado Resultante en la BD:** Estudiante matriculado con sobre-cupo.

---

### [PR-109] - Registro de Estudiante en Modalidad Intercambio / Movilidad Académica
- **Historias de Usuario que satisface:** HU051, HU053.
- **Propósito de Negocio:** Matricular a estudiantes de otras universidades internacionales que cursan asignaturas temporales.
- **Entidades del MER Involucradas:** `Usuario`, `Estudiante`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Registrar usuario con documento especial (`PR-019`).
  2. Asignar perfil `Estudiante` en modalidad movilidad.
  3. Matricular en los grupos autorizados.
- **Reglas de Negocio y Validaciones Específicas:**
  * Otorga control completo de asistencia durante su estancia.
- **Estado Resultante en la BD:** Estudiante de intercambio enrolado.

---

### [PR-110] - Retiro Masivo de Estudiantes por Cierre Definitivo de Grupo
- **Historias de Usuario que satisface:** HU051.
- **Propósito de Negocio:** Desmarcar las matrículas de todos los alumnos de un grupo que ha sido cancelado antes de iniciar clases.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Identificar todas las tuplas de `EstudianteGrupo` para el grupo cancelado.
  2. Actualizar su estado a "GRUPO_CANCELADO_REUBICAR".
- **Reglas de Negocio y Validaciones Específicas:**
  * Notifica a los estudiantes para seleccionar un grupo alternativo.
- **Estado Resultante en la BD:** Estudiantes liberados para nueva elección.

---

### [PR-111] - Homologación y Marcaje de Asignatura Cursada en Otro Grupo o Institución
- **Historias de Usuario que satisface:** HU051.
- **Propósito de Negocio:** Registrar que un estudiante ya aprobó la materia por homologación, eximiéndolo de cursar el grupo.
- **Entidades del MER Involucradas:** `EstudiantePrograma`, `Asignatura`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Registrar la aprobación por homologación en el expediente del alumno.
- **Reglas de Negocio y Validaciones Específicas:**
  * Impide la matrícula duplicada en grupos de la misma materia homologada.
- **Estado Resultante en la BD:** Asignatura homologada en expediente.

---

### [PR-112] - Auditoría de Cambios de Estado de Estudiante en Grupo
- **Historias de Usuario que satisface:** HU004.
- **Propósito de Negocio:** Guardar el historial de mutaciones de estado de un alumno en una materia (ej. de Matriculado a Retirado y luego Reincorporado).
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `EstadoEstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Insertar el registro de auditoría con `idCorrelacion`, fecha y estado anterior/nuevo.
- **Reglas de Negocio y Validaciones Específicas:**
  * Inmutable.
- **Estado Resultante en la BD:** Traza de auditoría de matrícula guardada.

---

### [PR-113] - Bloqueo Administrativo de Matrícula de Estudiante en Grupos
- **Historias de Usuario que satisface:** HU051.
- **Propósito de Negocio:** Bloquear la facultad de un estudiante para inscribir nuevas materias por sanción disciplinaria o mora.
- **Entidades del MER Involucradas:** `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Activar la bandera de bloqueo administrativo en la entidad `Estudiante`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Rechaza cualquier invocación de `PR-092` por parte del estudiante.
- **Estado Resultante en la BD:** Estudiante bloqueado administrativamente.

---

### [PR-114] - Desbloqueo Administrativo de Matrícula de Estudiante
- **Historias de Usuario que satisface:** HU051.
- **Propósito de Negocio:** Retirar la sanción administrativa permitiendo al alumno matricularse nuevamente.
- **Entidades del MER Involucradas:** `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Desactivar la bandera de bloqueo en `Estudiante`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Restablece inmediatamente sus permisos en el portal.
- **Estado Resultante en la BD:** Estudiante habilitado.

---

### [PR-115] - Asignación de Tutor Académico a Estudiante en Riesgo de Ausentismo
- **Historias de Usuario que satisface:** HU013, HU066.
- **Propósito de Negocio:** Asignar a un docente consejero para dar seguimiento a un alumno con alto porcentaje de inasistencias.
- **Entidades del MER Involucradas:** `Estudiante`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Registrar la pareja Estudiante-Tutor en la estructura de consejería.
- **Reglas de Negocio y Validaciones Específicas:**
  * Otorga acceso al tutor para visualizar el reporte de asistencias del estudiante (`uv_asistencia`).
- **Estado Resultante en la BD:** Tutoría asignada.

---

### [PR-116] - Sincronización de Estados de Matrícula con Sistema ERP/SGA Institucional
- **Historias de Usuario que satisface:** HU053.
- **Propósito de Negocio:** Reconciliar las matrículas de la BD con el sistema central universitario.
- **Entidades del MER Involucradas:** `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Comparar estados de la BD local vs archivo externo.
  2. Actualizar diferencias detectadas.
- **Reglas de Negocio y Validaciones Específicas:**
  * Garantiza la paridad de datos entre la app de asistencia y el ERP.
- **Estado Resultante en la BD:** Estados de matrícula sincronizados.

---

### [PR-117] - Generación de Ficha de Inscripción y Matrícula Consolidada del Estudiante
- **Historias de Usuario que satisface:** HU002, HU053.
- **Propósito de Negocio:** Retornar en un solo paso reactivo de lectura todo el horario y lista de grupos donde el estudiante está inscrito activamente en el periodo.
- **Entidades del MER Involucradas:** `Estudiante`, `EstudianteGrupo`, `Grupo`, `Horario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar `EstudianteGrupo` para el estudiante en el periodo vigente.
  2. Obtener materias, docentes y franjas horarias.
  3. Retornar el resumen consolidado.
- **Reglas de Negocio y Validaciones Específicas:**
  * Lectura atómica optimizada para la app del alumno.
- **Estado Resultante en la BD:** Ficha de horario y matrícula retornada.

---

### [PR-118] - Confirmación de Asistencia Inicial Obligatoria en Primera Semana de Clase
- **Historias de Usuario que satisface:** HU027, HU053.
- **Propósito de Negocio:** Marcar la confirmación física del alumno en el primer día de clase para validar su cupo.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Asistencia`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar el marcaje de asistencia en la primera sesión.
  2. Confirmar la condición de "MATRICULA_VALIDADA".
- **Reglas de Negocio y Validaciones Específicas:**
  * Si el alumno no asiste a la primera semana sin justificación, el cupo puede ser reasignado.
- **Estado Resultante en la BD:** Matrícula validada presencialmente.

---

### [PR-119] - Regularización de Estudiantes Extemporáneos con Marcaje Retroactivo de Sesiones
- **Historias de Usuario que satisface:** HU027, HU053.
- **Propósito de Negocio:** Ajustar la plantilla de asistencia para un alumno que se matriculó tarde en el periodo, eximiéndolo de las faltas de las sesiones dictadas antes de su fecha de matrícula.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Asistencia`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Obtener la fecha exacta de matrícula del alumno.
  2. Buscar las `Sesion` del grupo con fecha anterior a su matrícula.
  3. Registrar en `Asistencia` el estado "EXENTO_INGRESO_TARDIO".
- **Reglas de Negocio y Validaciones Específicas:**
  * Evita que el cálculo de ausentismo castigue al estudiante por clases dictadas previo a su adición oficial.
- **Estado Resultante en la BD:** Sesiones pasadas marcadas como exentas para el estudiante tardío.

---

---

### 📦 MÓDULO 5: Sesiones, Captura y Registro de Asistencia (PR-121 a PR-150)

---

### [PR-121] - Apertura o Generación Reactiva de Sesión de Clase
- **Historias de Usuario que satisface:** HU028 (Crear/Abrir sesión de clase), HU034, HU029.
- **Propósito de Negocio:** Abrir la clase del día. Si la sesión no existe previamente en la tabla `Sesion` para el horario actual del grupo, la genera reactivamente al vuelo, valida los permisos del docente y retorna la plantilla completa de estudiantes matriculados para iniciar la toma de lista.
- **Entidades del MER Involucradas:** `Sesion`, `Grupo`, `Docente`, `EstudianteGrupo`, `Usuario`, `Estudiante`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `idDocente` sea el titular o suplente activo del `idGrupo`.
  2. Consultar si existe una tupla en `Sesion` para la fecha y horario del grupo:
     * **Si NO existe:** Crear reactivamente la tupla en `Sesion` (`grupo`, `fechaHoraInicio`, `fechaHoraFin`, `estado = ABIERTA`).
     * **Si YA existe:** Verificar que no esté en estado cerrada o congelada.
  3. Consultar todos los `EstudianteGrupo` activos del grupo.
  4. Retornar el `idSesion` y el listado de estudiantes habilitados para marcaje.
- **Reglas de Negocio y Validaciones Específicas:**
  * Valida la tolerancia temporal configurada para iniciar clase (ej. máximo 15 minutos antes o después de la hora programada).
- **Estado Resultante en la BD:** `Sesion` creada o recuperada en estado activo y plantilla retornada.

---

### [PR-122] - Toma de Asistencia Masiva por Lote en Sesión por el Docente
- **Historias de Usuario que satisface:** HU027 (Registrar asistencia), HU029, HU033.
- **Propósito de Negocio:** Guardar en un solo envío atómico desde la app toda la lista de clase con los estados de asistencia asignados a cada estudiante (Asistió, Faltó, Tarde).
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `EstudianteGrupo`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Sesion` esté activa y pertenezca al docente en sesión.
  2. Recibir la colección de pares `(idEstudianteGrupo, idEstadoAsistencia)`.
  3. Por cada elemento del lote:
     * Validar que el `EstudianteGrupo` pertenezca al grupo de la sesión.
     * Evaluar si ya existe registro en `Asistencia`:
       * **Si NO existe:** Insertar nueva tupla en `Asistencia` (`estudianteGrupo`, `sesion`, `fechaHora`, `estado`).
       * **Si YA existe:** Actualizar el `estado` en `Asistencia`.
  4. Retornar el resumen de procesados.
- **Reglas de Negocio y Validaciones Específicas:**
  * Transacción atómica integral: si un `idEstudianteGrupo` es inválido, aborta la operación completa para garantizar consistencia.
- **Estado Resultante en la BD:** Registros creados o actualizados en `Asistencia` para toda la plantilla.

---

### [PR-123] - Registro de Asistencia Autónoma por Estudiante mediante QR/Token Dinámico
- **Historias de Usuario que satisface:** HU027 (Auto-registro de asistencia estudiante), HU053.
- **Propósito de Negocio:** Permitir que el estudiante escanee el QR dinámico o ingrese el token de clase en su celular para registrar de forma autónoma su asistencia a la sesión activa.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `EstudianteGrupo`, `Estudiante`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el token dinámico de la `Sesion` sea válido y no haya expirado.
  2. Identificar la matrícula activa del alumno en `EstudianteGrupo` para el grupo de la sesión.
  3. Verificar que no exista ya un marcaje de asistencia para este estudiante en esta sesión.
  4. Comparar `fechaHora` actual con la hora de inicio de la sesión:
     * Si está dentro de la tolerancia de tiempo (ej. 10 min), registrar con `Estado = ASISTIO`.
     * Si supera la tolerancia pero está dentro del margen de retardo, registrar con `Estado = TARDE`.
  5. Insertar la tupla en `Asistencia`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Valida la geolocalización o IP si el parámetro institucional de presencia está activo.
- **Estado Resultante en la BD:** Registro individual en `Asistencia` creado autónomamente.

---

### [PR-124] - Cierre Definitivo de Sesión con Marcado Automático de Inasistencias no Registradas
- **Historias de Usuario que satisface:** HU028 (Cerrar sesión), HU013, HU096.
- **Propósito de Negocio:** Concluir la sesión de clase. Identifica a todos los estudiantes de la lista que no fueron marcados manualmente o de forma autónoma y les asigna automáticamente la inasistencia ("FALTA_UNILATERAL"), recalculando el ausentismo del grupo.
- **Entidades del MER Involucradas:** `Sesion`, `Asistencia`, `EstudianteGrupo`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Sesion` esté en estado abierto.
  2. Consultar los `EstudianteGrupo` del grupo que no tengan tupla en `Asistencia` para esta sesión.
  3. Por cada estudiante omitido, insertar tupla en `Asistencia` con `Estado = FALTA`.
  4. Cambiar el estado de la `Sesion` a "CERRADA / FINALIZADA".
  5. Invocar el recálculo de porcentaje de inasistencias acumuladas y verificar alertas (`PR-155`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Al cerrar la sesión se desactiva el token de marcaje autónomo para evitar asistencias extemporáneas.
- **Estado Resultante en la BD:** Sesión cerrada y plantilla de asistencias 100% completada.

---

### [PR-125] - Modificación Atómica de Registro de Asistencia de un Estudiante en Sesión Específica
- **Historias de Usuario que satisface:** HU033 (Modificar asistencia tomada), HU027.
- **Propósito de Negocio:** Permitir al docente corregir de forma individual la asistencia de un alumno (ej. cambiar de "FALTA" a "ASISTIO" o "JUSTIFICADA") tras verificar su presencia.
- **Entidades del MER Involucradas:** `Asistencia`, `Estado`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar existencia de la tupla en `Asistencia`.
  2. Verificar que la fecha de la sesión no supere el límite reglamentario de edición (ej. máximo 8 días).
  3. Actualizar el campo `estado` en la entidad `Asistencia`.
  4. Recalcular el % de ausentismo acumulado del estudiante.
- **Reglas de Negocio y Validaciones Específicas:**
  * Registra en la auditoría el usuario y la justificación del cambio de estado.
- **Estado Resultante en la BD:** Registro en `Asistencia` corregido y ausentismo recalculado.

---

### [PR-126] - Cancelación de Sesión de Clase Programada con Notificación a Estudiantes
- **Historias de Usuario que satisface:** HU047 (Cancelar sesión).
- **Propósito de Negocio:** Marcar una sesión como cancelada (ej. por calamidad del docente o suspensión institucional), evitando que compute como falta para los estudiantes.
- **Entidades del MER Involucradas:** `Sesion`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Sesion` no haya concluido.
  2. Actualizar el estado en `Sesion` a "CANCELADA".
  3. Si existían registros de asistencia parciales, actualizarlos o inactivarlos.
  4. Emite evento de notificación para la App de los estudiantes.
- **Reglas de Negocio y Validaciones Específicas:**
  * Una sesión cancelada no afecta negativamente el porcentaje de asistencias requeridas del curso.
- **Estado Resultante en la BD:** `Sesion` marcada como cancelada.

---

### [PR-127] - Reprogramación de Sesión Cancelada en Nueva Fecha/Hora sin Cruces Horarios
- **Historias de Usuario que satisface:** HU045, HU046.
- **Propósito de Negocio:** Agendar la reposición de una clase cancelada en una nueva fecha/hora, verificando previamente la disponibilidad del docente y del aula.
- **Entidades del MER Involucradas:** `Sesion`, `Grupo`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la nueva fecha y horas no generen colisión para el docente (`PR-073`).
  2. Actualizar `fechaHoraInicio` y `fechaHoraFin` en la tupla de `Sesion`.
  3. Reabrir la sesión en estado "REPROGRAMADA / ABIERTA".
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere confirmación de disponibilidad enviada a los alumnos del grupo.
- **Estado Resultante en la BD:** Clase de reposición reprogramada en el calendario.

---

### [PR-128] - Apertura de Sesión Extraordinaria / Extracurricular fuera del Horario Habitual
- **Historias de Usuario que satisface:** HU028, HU045.
- **Propósito de Negocio:** Permitir al docente abrir una clase adicional fuera del horario regular (ej. clase de refuerzo o taller pre-examen) para toma de lista.
- **Entidades del MER Involucradas:** `Sesion`, `Grupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `Grupo` esté activo.
  2. Insertar nueva tupla en `Sesion` con tipo/bandera "EXTRAORDINARIA".
- **Reglas de Negocio y Validaciones Específicas:**
  * Las inasistencias a sesiones extraordinarias no cuentan como faltas punibles reglamentarias salvo acuerdo previo.
- **Estado Resultante en la BD:** Sesión extraordinaria aperturada.

---

### [PR-129] - Toma de Asistencia por Escaneo Masivo de Código de Estudiante (Barcode/NFC)
- **Historias de Usuario que satisface:** HU027.
- **Propósito de Negocio:** Permitir que el docente escanee rápidamente con el carné de los estudiantes (código de barras o NFC) para registrar la asistencia en tiempo real.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `Usuario`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir el número de documento escaneado y el `idSesion`.
  2. Localizar la matrícula activa en `EstudianteGrupo`.
  3. Insertar/Actualizar la asistencia con `Estado = ASISTIO`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Emite respuesta sonora/visual en la app cliente por cada carné escaneado exitosamente.
- **Estado Resultante en la BD:** Registro de asistencia individual creado por escaneo.

---

### [PR-130] - Corrección Lote de Asistencia en Sesión por Error del Docente en el Llamado
- **Historias de Usuario que satisface:** HU033.
- **Propósito de Negocio:** Permitir re-enviar la plantilla completa de asistencia de una sesión previa para sobrescribir errores de marcaje cometidos por el docente.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Sesion` no haya sido cerrada formalmente por la coordinación.
  2. Recibir la plantilla corregida.
  3. Sobrescribir los estados de `Asistencia` en una sola transacción atómica.
- **Reglas de Negocio y Validaciones Específicas:**
  * Guarda la traza en auditoría con la versión anterior y la nueva versión de la plantilla.
- **Estado Resultante en la BD:** Plantilla de asistencia en la sesión corregida.

---

### [PR-131] - Marcaje Automático de Llegada Tarde por Superación de Tolerancia de Minutos
- **Historias de Usuario que satisface:** HU027.
- **Propósito de Negocio:** Evaluar atómicamente la hora exacta de marcaje y asignarle el estado de "LLEGADA_TARDE" al estudiante si ingresó tras los minutos de tolerancia (ej. 15 minutos).
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Calcular la diferencia en minutos entre `fechaHoraInicio` de `Sesion` y el timestamp actual.
  2. Si `diferencia > tolerancia_minutos`, asignar `Estado = TARDE`.
  3. Insertar/Actualizar en `Asistencia`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Tres llegadas tardes equivalen reglamentariamente a 1 inasistencia para el ausentismo acumulado.
- **Estado Resultante en la BD:** Asistencia registrada con estado de retardo.

---

### [PR-132] - Consolidar Cierre Automático Nocturno de Sesiones Olvidadas Abiertas por Docentes
- **Historias de Usuario que satisface:** HU028, Configuración Ecosistema.
- **Propósito de Negocio:** Proceso batch automático ejecutado a medianoche. Detecta sesiones que quedaron en estado "ABIERTA" por olvido del docente, marcando las inasistencias omitidas y cerrándolas de forma segura.
- **Entidades del MER Involucradas:** `Sesion`, `Asistencia`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar todas las `Sesion` con `fechaHoraFin < NOW()` que permanezcan en estado abierto.
  2. Ejecutar la lógica de cierre automático (`PR-124`) para cada una.
  3. Registrar la traza en la bitácora del sistema.
- **Reglas de Negocio y Validaciones Específicas:**
  * Envía un correo recordatorio al docente notificando el cierre automático de la sesión.
- **Estado Resultante en la BD:** Sesiones olvidadas cerradas de forma atómica.

---

### [PR-133] - Inactivación / Anulación de Registro de Asistencia Duplicado
- **Historias de Usuario que satisface:** HU027.
- **Propósito de Negocio:** Eliminar de forma segura marcas de asistencia duplicadas o generadas por error técnico en la app móvil.
- **Entidades del MER Involucradas:** `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Identificar registros redundantes para el mismo `estudianteGrupo` y `sesion`.
  2. Eliminar la tupla duplicada conservando el marcaje original válido.
- **Reglas de Negocio y Validaciones Específicas:**
  * Preserva la integridad de la clave primaria única.
- **Estado Resultante en la BD:** Registro duplicado purgado.

---

### [PR-134] - Consulta de Plantilla de Asistencia en Tiempo Real para Sesión Activa
- **Historias de Usuario que satisface:** HU029 (Consultar listado de asistencia de sesión).
- **Propósito de Negocio:** Retornar al dispositivo del docente el estado actual de la toma de lista de la sesión en curso (cuántos asistieron, cuántos faltan y cuántos han marcado por QR).
- **Entidades del MER Involucradas:** `Sesion`, `Asistencia`, `EstudianteGrupo`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar los estudiantes matriculados en el grupo.
  2. Hacer `LEFT JOIN` con la tabla `Asistencia` para la `Sesion` indicada.
  3. Retornar el listado completo consolidado.
- **Reglas de Negocio y Validaciones Específicas:**
  * Lectura optimizada para alta concurrencia durante la toma de lista.
- **Estado Resultante en la BD:** Plantilla consolidada retornada al cliente.

---

### [PR-135] - Registro de Asistencia para Estudiantes Asistentes / Oyentes Autorizados
- **Historias de Usuario que satisface:** HU027.
- **Propósito de Negocio:** Marcar la asistencia de alumnos registrados como oyentes (`PR-102`) en la sesión.
- **Entidades del MER Involucradas:** `Asistencia`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la tupla en `EstudianteGrupo` tenga el estado oyente.
  2. Insertar en `Asistencia`.
- **Reglas de Negocio y Validaciones Específicas:**
  * No afecta las estadísticas oficiales de reprobación por faltas de los alumnos regulares.
- **Estado Resultante en la BD:** Asistencia de oyente registrada.

---

### [PR-136] - Bloqueo de Edición de Asistencia en Sesiones con Fecha Mayor a Límite Reglamentario
- **Historias de Usuario que satisface:** HU033.
- **Propósito de Negocio:** Impedir que un docente modifique planillas de asistencia de clases dictadas hace más de 8 o 15 días, exigiendo solicitud de desbloqueo al coordinador (`PR-137`).
- **Entidades del MER Involucradas:** `Sesion`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Evaluar la diferencia en días entre la fecha de la sesión y la fecha actual.
  2. Si `diferencia_dias > parametro_dias_limite`, bloquear la actualización y retornar mensaje de restricción.
- **Reglas de Negocio y Validaciones Específicas:**
  * Garantiza la estabilidad de las planillas de asistencia para evitar manipulaciones extemporáneas.
- **Estado Resultante en la BD:** Intento de edición bloqueado por vencimiento reglamentario.

---

### [PR-137] - Desbloqueo Excepcional de Sesión de Asistencia por Solicitud de Coordinador
- **Historias de Usuario que satisface:** HU033, HU066.
- **Propósito de Negocio:** Habilitar un permiso temporal de 24 horas para que un docente pueda editar la asistencia de una clase antigua previa justificación aprobada por la coordinación.
- **Entidades del MER Involucradas:** `Sesion`, `Coordinador`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la autorización del `Coordinador`.
  2. Marcar la tupla de `Sesion` con bandera de edición excepcional habilitada.
- **Reglas de Negocio y Validaciones Específicas:**
  * La habilitación expira automáticamente a las 24 horas de ser concedida.
- **Estado Resultante en la BD:** Sesión temporalmente editable.

---

### [PR-138] - Registro de Observación / Comentario Individual en Marcaje de Asistencia
- **Historias de Usuario que satisface:** HU027.
- **Propósito de Negocio:** Permitir al docente ingresar una nota explicativa al marcar la asistencia de un alumno (ej. "Llegó 20 min tarde por cita médica" o "Retirado con permiso previo").
- **Entidades del MER Involucradas:** `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Registrar el texto de la observación en la tupla de `Asistencia`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Visible para el estudiante al consultar sus detalles de asistencia (`uv_asistencia`).
- **Estado Resultante en la BD:** Campo de observación guardado en la asistencia.

---

### [PR-139] - Generación de Token Dinámico / Código QR Temporal para Sesión por el Docente
- **Historias de Usuario que satisface:** HU028.
- **Propósito de Negocio:** Generar la clave encriptada/QR que cambia cada 30 segundos y que se proyecta en el aula para que los estudiantes registren su presencia.
- **Entidades del MER Involucradas:** `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Sesion` esté activa.
  2. Generar el token temporal con algoritmo hash y timestamp.
  3. Actualizar la semilla del token en la entidad `Sesion`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Impide la captura remota del QR por estudiantes que no están físicamente en el aula.
- **Estado Resultante en la BD:** Token dinámico de sesión activo.

---

### [PR-140] - Validación de Token Dinámico de Asistencia y Expulsión por Token Vencido
- **Historias de Usuario que satisface:** HU027.
- **Propósito de Negocio:** Verificar la autenticidad del token enviado por el celular del estudiante al hacer marcaje autónomo (`PR-123`).
- **Entidades del MER Involucradas:** `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar el token recibido contra la semilla activa de la `Sesion`.
  2. Si el token expiró, retornar error de token inválido y denegar el registro.
- **Reglas de Negocio y Validaciones Específicas:**
  * Función de seguridad previa a la inserción en `Asistencia`.
- **Estado Resultante en la BD:** Diagnóstico de seguridad de token.

---

### [PR-141] - Registro de Asistencia en Modalidad Virtual / Remota con Enlace de Conexión
- **Historias de Usuario que satisface:** HU027.
- **Propósito de Negocio:** Registrar el ingreso y tiempo de permanencia de estudiantes en clases dictadas a través de plataformas virtuales (Teams, Zoom).
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir los logs de conexión virtual de la sesión.
  2. Mapear usuarios con `EstudianteGrupo` e insertar asistencias.
- **Reglas de Negocio y Validaciones Específicas:**
  * Exige un porcentaje mínimo de permanencia en la llamada (ej. 70% de la clase) para marcar `ASISTIO`.
- **Estado Resultante en la BD:** Asistencias virtuales registradas.

---

### [PR-142] - Sincronización Offline de Registros de Asistencia Tomados desde App Móvil Sin Conexión
- **Historias de Usuario que satisface:** HU027.
- **Propósito de Negocio:** Procesar en bloque el paquete de asistencias guardado localmente en el teléfono del docente cuando no había señal de internet en el aula.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Recibir el paquete firmado con los registros tomados offline y sus timestamps locales.
  2. Validar consistencia y volcar los datos en la tabla `Asistencia`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Verifica la integridad de la firma para evitar alteración de horas de toma de lista.
- **Estado Resultante en la BD:** Registros offline sincronizados en la base de datos.

---

### [PR-143] - Marcaje de Asistencia Grupal Total por Evento Institucional / Salida de Campo
- **Historias de Usuario que satisface:** HU027, HU028.
- **Propósito de Negocio:** Marcar atómicamente a TODO el grupo como "ASISTIO_EVENTO_INSTITUCIONAL" por actividades académicas autorizadas fuera del campus.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la autorización del evento para el `Grupo`.
  2. Registrar para la totalidad de la plantilla de `EstudianteGrupo` la asistencia institucional.
  3. Cerrar la `Sesion`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Exime individualmente el marcaje sin requerir llamada de lista uno a uno.
- **Estado Resultante en la BD:** Asistencia masiva de evento registrada.

---

### [PR-144] - Auditoría Fila a Fila de Modificaciones en la Tabla `Asistencia`
- **Historias de Usuario que satisface:** HU027, HU033.
- **Propósito de Negocio:** Registrar en la bitácora inmutable de auditoría cada cambio de estado efectuado sobre un registro de asistencia, capturando usuario, fecha, estado previo y nuevo.
- **Entidades del MER Involucradas:** `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Disparar atómicamente la inserción de la traza de auditoría ante cualquier `UPDATE` o `DELETE` en `Asistencia`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Estricta trazabilidad legal e institucional.
- **Estado Resultante en la BD:** Traza de auditoría de asistencia guardada.

---

### [PR-145] - Verificación de Integridad entre `Sesion`, `EstudianteGrupo` y `Asistencia`
- **Historias de Usuario que satisface:** Configuración Ecosistema.
- **Propósito de Negocio:** Procedimiento reactivo de mantenimiento que detecta asistencias registradas para estudiantes desvinculados o sesiones inconsistentes.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Escanear incoherencias en las llaves foráneas y fechas de `Asistencia`.
  2. Marcar registros anómalos para revisión técnica.
- **Reglas de Negocio y Validaciones Específicas:**
  * Diagnóstico sin pérdida de datos.
- **Estado Resultante en la BD:** Reporte de consistencia de asistencias.

---

### [PR-146] - Re-apertura de Sesión Cerrada para Inclusión de Estudiante Extemporáneo
- **Historias de Usuario que satisface:** HU028, HU053.
- **Propósito de Negocio:** Reabrir temporalmente una sesión concluida para agregar la asistencia de un alumno matriculado tardíamente.
- **Entidades del MER Involucradas:** `Sesion`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Cambiar el estado de la `Sesion` a "REABIERTA_TEMPORAL".
  2. Insertar el marcaje del estudiante tardío.
  3. Re-cerrar la `Sesion` (`PR-124`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Registra la causa justificada en la bitácora de auditoría.
- **Estado Resultante en la BD:** Asistencia de alumno extemporáneo incluida.

---

### [PR-147] - Marcaje de Permiso Institucional Previo en Asistencia por Representación Deportiva/Académica
- **Historias de Usuario que satisface:** HU027, HU014.
- **Propósito de Negocio:** Registrar en la sesión que el estudiante no asistirá por estar representando a la universidad en competencias o eventos oficiales.
- **Entidades del MER Involucradas:** `Asistencia`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la resolución de representación del estudiante.
  2. Registrar la tupla en `Asistencia` con `Estado = PERMISO_INSTITUCIONAL`.
- **Reglas de Negocio y Validaciones Específicas:**
  * No computa como inasistencia penalizable.
- **Estado Resultante en la BD:** Permiso institucional registrado en asistencia.

---

### [PR-148] - Reporte Reactivo de Faltas Consecutivas en el Transcurso de las Sesiones
- **Historias de Usuario que satisface:** HU013, HU066.
- **Propósito de Negocio:** Detectar cuando un estudiante acumula 3 o más faltas consecutivas en las últimas sesiones del grupo para alerta temprana de deserción.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Analizar la secuencia temporal de registros en `Asistencia` para el estudiante.
  2. Si se detectan N inasistencias seguidas sin justificar, emitir la alerta a bienestar universitario.
- **Reglas de Negocio y Validaciones Específicas:**
  * Diagnóstico automático en tiempo real.
- **Estado Resultante en la BD:** Alerta de faltas consecutivas generada.

---

### [PR-149] - Notificación Push / Correo Inmediata al Estudiante por Inasistencia Registrada
- **Historias de Usuario que satisface:** HU001, HU013.
- **Propósito de Negocio:** Notificar al instante al estudiante en su celular cada vez que un profesor le marca una falta o llegada tarde en clase.
- **Entidades del MER Involucradas:** `Asistencia`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Al insertar en `Asistencia` una tupla con estado "FALTA" o "TARDE", disparar el evento de mensajería.
  2. Construir y enviar la notificación con fecha, materia y profesor.
- **Reglas de Negocio y Validaciones Específicas:**
  * Permite al alumno reaccionar a tiempo y solicitar revisión si hubo un error (`PR-151`).
- **Estado Resultante en la BD:** Evento de notificación emitido.

---

---

### 📦 MÓDULO 6: Novedades, Justificaciones, Alertas de Ausentismo y Reportes Auditados (PR-151 a PR-180)

---

### [PR-151] - Radicar Solicitud de Revisión / Justificación de Inasistencia por el Estudiante con Soporte
- **Historias de Usuario que satisface:** HU010 (Registrar solicitud de revisión), HU014 (Adjuntar soportes/justificaciones médicos).
- **Propósito de Negocio:** Permite al alumno justificar una inasistencia o pedir corrección de error en la app. Asocia la `Asistencia`, selecciona la `RazonCausa`, adjunta observación/soporte y genera el registro en `SolicitudRevisionAsistencia` en estado "PENDIENTE".
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `Asistencia`, `RazonCausa`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `Asistencia` pertenezca al alumno autenticado y esté en estado "FALTA" o "TARDE".
  2. Validar existencia del `idRazonCausa` y que el motivo esté activo.
  3. Verificar que no exista ya una `SolicitudRevisionAsistencia` previa en estado "PENDIENTE" o "APROBADA" para esa misma asistencia.
  4. Obtener el `idEstado` correspondiente a "PENDIENTE_REVISION".
  5. Insertar tupla en `SolicitudRevisionAsistencia` (`asistencia`, `razonCausa`, `observacion`, `fechaSolicitud = NOW()`, `estado`).
  6. Emitir notificación al docente titular del grupo.
- **Reglas de Negocio y Validaciones Específicas:**
  * Debe radicarse dentro de los días hábiles permitidos tras el marcaje de la falta (ej. máximo 3 a 5 días hábiles).
- **Estado Resultante en la BD:** Solicitud radicada en `SolicitudRevisionAsistencia` con estado pendiente de evaluación.

---

### [PR-152] - Resolver Solicitud de Justificación por el Docente (Aprobación/Rechazo + Cambio Atómico en `Asistencia`)
- **Historias de Usuario que satisface:** HU035 (Ver solicitudes de revisión pendientes), HU037 (Aprobar/Rechazar justificaciones).
- **Propósito de Negocio:** Permite al profesor evaluar la solicitud del alumno. Si se aprueba, la transacción actualiza atómicamente la solicitud a "APROBADA" y modifica el campo `estado` en `Asistencia` a "JUSTIFICADA", recalculando el porcentaje de faltas acumuladas en un solo paso.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `Asistencia`, `Estado`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `SolicitudRevisionAsistencia` esté en estado "PENDIENTE_REVISION".
  2. Validar que el docente que resuelve sea el titular o suplente del `Grupo`.
  3. Recibir la decisión ("APROBADA" o "RECHAZADA") y comentario del docente.
  4. Actualizar el estado en `SolicitudRevisionAsistencia`.
  5. **Si la decisión es APROBADA:**
     * Actualizar la tupla en `Asistencia` asignando el estado "JUSTIFICADA".
     * Recalcular el porcentaje de ausentismo acumulado en `EstudianteGrupo`.
  6. Notificar la decisión al estudiante.
- **Reglas de Negocio y Validaciones Específicas:**
  * Si la justificación es aprobada, la falta justificada deja de sumar negativamente hacia el límite reglamentario de cancelación de materia.
- **Estado Resultante en la BD:** Solicitud resuelta y estado en `Asistencia` actualizado atómicamente.

---

### [PR-153] - Resolver Solicitud de Justificación por el Coordinador de Programa (Instancia Superior)
- **Historias de Usuario que satisface:** HU037, HU066.
- **Propósito de Negocio:** Permitir que la coordinación de carrera resuelva justificaciones en apelación o cuando el docente no respondió dentro del plazo reglamentario.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `Asistencia`, `Coordinador`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el usuario sea `Coordinador` del programa al que pertenece la asignatura.
  2. Ejecutar la resolución atómica de la justificación (`PR-152`).
  3. Dejar constancia de resolución por instancia superior en la auditoría.
- **Reglas de Negocio y Validaciones Específicas:**
  * La decisión del coordinador prevalece sobre cualquier estado previo de la solicitud.
- **Estado Resultante en la BD:** Solicitud resuelta por coordinación con actualización en asistencia.

---

### [PR-154] - Cancelación de Solicitud de Revisión por el Estudiante antes de ser Evaluada
- **Historias de Usuario que satisface:** HU010.
- **Propósito de Negocio:** Permitir que el estudiante retire voluntariamente su solicitud de revisión si la radicó por error o con datos incorrectos.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la `SolicitudRevisionAsistencia` esté en estado "PENDIENTE_REVISION" y pertenezca al estudiante.
  2. Actualizar el estado a "CANCELADA_POR_ESTUDIANTE".
- **Reglas de Negocio y Validaciones Específicas:**
  * No se puede cancelar una solicitud que ya ha sido APROBADA o RECHAZADA por el docente.
- **Estado Resultante en la BD:** Solicitud marcada como cancelada.

---

### [PR-155] - Generación de Alerta Temprana de Ausentismo Crítico al Superar Umbral
- **Historias de Usuario que satisface:** HU013 (Recibir alertas de ausentismo), HU066.
- **Propósito de Negocio:** Disparar de forma reactiva una alerta visual y por correo cuando el % de inasistencias de un alumno alcanza el 15% (Advertencia) o el 20% (Pérdida por inasistencias).
- **Entidades del MER Involucradas:** `Asistencia`, `EstudianteGrupo`, `Grupo`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Calcular la suma de faltas no justificadas del estudiante en la materia sobre el total de clases del periodo.
  2. Si `%_faltas >= 15%` y no existía alerta activa, generar el registro de alerta temprana.
  3. Enviar notificación push al estudiante y correo al docente/coordinador.
- **Reglas de Negocio y Validaciones Específicas:**
  * Función de evaluación automática ejecutada tras cada marcaje o resolución de justificación.
- **Estado Resultante en la BD:** Alerta temprana registrada y emitida.

---

### [PR-156] - Envío de Notificación Consolidada a Coordinación por Estudiantes en Riesgo
- **Historias de Usuario que satisface:** HU066, HU013.
- **Propósito de Negocio:** Generar un reporte periódico automático para la coordinación con la lista de alumnos que superaron el umbral crítico de faltas en cualquier asignatura de la facultad.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Grupo`, `Programa`, `Usuario`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar todos los `EstudianteGrupo` con alerta activa de ausentismo.
  2. Agrupar por programa académico.
  3. Enviar el paquete consolidado de alertas al correo del `Coordinador`.
- **Reglas de Negocio and Validaciones Específicas:**
  * Facilita la intervención temprana de bienestar universitario.
- **Estado Resultante en la BD:** Traza de reporte de alerta enviado.

---

### [PR-157] - Emisión de Certificado Oficial de Porcentaje de Asistencia por Asignatura
- **Historias de Usuario que satisface:** HU001, HU002.
- **Propósito de Negocio:** Generar el reporte oficial en PDF/XML de asistencias acumuladas de un estudiante para trámites de becas o patrocinios institucionales.
- **Entidades del MER Involucradas:** `Estudiante`, `EstudianteGrupo`, `Asistencia`, `Grupo`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar todas las `Sesion` ejecutadas del grupo y los registros correspondientes en `Asistencia`.
  2. Calcular: Total Clases Dictadas, Asistencias, Faltas Justificadas, Faltas No Justificadas, Retardos y % Definitivo.
  3. Retornar el certificado firmado digitalmente.
- **Reglas de Negocio y Validaciones Específicas:**
  * Certificado atómico inmutable para trámites externos.
- **Estado Resultante en la BD:** Documento de certificación generado.

---

### [PR-158] - Registro de Razón / Causa de Inasistencia Institucional (Mantenimiento de Catálogo)
- **Historias de Usuario que satisface:** HU005, HU016, HU042.
- **Propósito de Negocio:** Dar de alta o actualizar las opciones del catálogo `RazonCausa` (ej. "Incapacidad Médica EPS", "Calamidad Doméstica Comprobada", "Cita Judicial", "Representación Deportiva").
- **Entidades del MER Involucradas:** `RazonCausa`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que el `codigo` o `nombre` en `RazonCausa` no esté duplicado.
  2. Insertar/Actualizar la tupla (`id`, `codigo`, `nombre`, `estado = 1`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Catálogo global utilizado en las pantallas de justificación de estudiantes y docentes.
- **Estado Resultante en la BD:** Opción registrada en `RazonCausa`.

---

### [PR-159] - Consulta Consolidada de Histórico de Asistencias del Estudiante (`uv_asistencia`)
- **Historias de Usuario que satisface:** HU001 (Ver detalles de inasistencias), HU002 (Consultar histórico).
- **Propósito de Negocio:** Retornar en una vista/procedimiento de lectura ultra-rápida todo el expediente de asistencias del estudiante a lo largo de su carrera.
- **Entidades del MER Involucradas:** `Asistencia`, `EstudianteGrupo`, `Sesion`, `Grupo`, `Asignatura`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Ejecutar consulta sobre la vista optimizada `uv_asistencia` filtrando por `idEstudiante`.
  2. Formatear desglose por materia, periodo, fecha de clase y estado.
  3. Retornar la respuesta al cliente app.
- **Reglas de Negocio y Validaciones Específicas:**
  * Lectura optimizada mediante índices covering en `Asistencia`.
- **Estado Resultante en la BD:** Histórico retornado al cliente.

---

### [PR-160] - Consulta Consolidada de Estadísticas de Asistencia por Grupo (`uv_estadistica_grupo`)
- **Historias de Usuario que satisface:** HU060, HU066.
- **Propósito de Negocio:** Retornar a la coordinación el resumen estadístico de un grupo (% de asistencia promedio, número de estudiantes en riesgo, total de clases dictadas).
- **Entidades del MER Involucradas:** `Grupo`, `Sesion`, `Asistencia`, `EstudianteGrupo`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar la vista `uv_estadistica_grupo` filtrando por `idGrupo`.
  2. Retornar indicadores clave KPI del grupo.
- **Reglas de Negocio y Validaciones Específicas:**
  * Utilizado por docentes y coordinadores en su panel de mando.
- **Estado Resultante en la BD:** Indicadores KPI del grupo retornados.

---

### [PR-161] - Generación de Reporte Macro de Deserción y Ausentismo para Decanatura por Facultad
- **Historias de Usuario que satisface:** HU102 (Reportes macro decanatura).
- **Propósito de Negocio:** Consolidar métricas a nivel gerencial para el Decano, mostrando los programas académicos y materias con mayor índice de inasistencias en la Facultad.
- **Entidades del MER Involucradas:** `Facultad`, `Programa`, `Grupo`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Agrupar la totalidad de asistencias y faltas del periodo lectivo por `Programa` y `Facultad`.
  2. Generar ranking de ausentismo y proyección de pérdida de asignaturas.
- **Reglas de Negocio y Validaciones Específicas:**
  * Consulta atómica agregada de alto nivel.
- **Estado Resultante en la BD:** Reporte macro de decanatura generado.

---

### [PR-162] - Auditoría de Solicitudes de Revisión y Resoluciones de Docentes
- **Historias de Usuario que satisface:** HU037, HU010.
- **Propósito de Negocio:** Registrar en la bitácora inmutable las fechas de radicación, respuesta del docente y sustentos de cada solicitud de justificación procesada.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Disparar registro de auditoría con `idCorrelacion` al actualizar `SolicitudRevisionAsistencia`.
- **Reglas de Negocio y Validaciones Específicas:**
  * Garantiza la transparencia en la gestión de excusas médicas e institucionales.
- **Estado Resultante en la BD:** Traza de auditoría de justificación guardada.

---

### [PR-163] - Reabrir Solicitud de Revisión Rechazada por Presentación de Nuevo Soporte Oficial
- **Historias de Usuario que satisface:** HU010, HU037.
- **Propósito de Negocio:** Permitir que una solicitud que fue rechazada se reabra si el estudiante presenta una excusa oficial expedida posteriormente por bienestar o secretaría académica.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar que la solicitud anterior estuviera en estado "RECHAZADA".
  2. Actualizar el estado a "REABIERTA_PENDIENTE_EVALUACION".
  3. Anexar el nuevo soporte a la observación.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requiere aval del coordinador o decano.
- **Estado Resultante en la BD:** Solicitud reabierta para reconsideración.

---

### [PR-164] - Justificación Masiva de Inasistencias para un Grupo por Paro / Incapacidad Institucional
- **Historias de Usuario que satisface:** HU037.
- **Propósito de Negocio:** Marcar automáticamente como "JUSTIFICADA" la falta de TODOS los estudiantes de un grupo en una o varias fechas específicas por suspensión general de actividades.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `SolicitudRevisionAsistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Identificar las `Sesion` del grupo comprendidas en el rango de fechas de la suspensión.
  2. Actualizar en bloque las tuplas en `Asistencia` al estado "JUSTIFICADA_INSTITUCIONAL".
  3. Cerrar automáticamente cualquier solicitud de revisión individual pendiente sobre esas sesiones.
- **Reglas de Negocio y Validaciones Específicas:**
  * Transacción masiva de un solo paso ejecutada por orden de decanatura.
- **Estado Resultante en la BD:** Inasistencias del grupo justificadas masivamente.

---

### [PR-165] - Inactivación / Anulación de Solicitud de Revisión Fraudulenta con Notificación a Decanatura
- **Historias de Usuario que satisface:** HU037, HU102.
- **Propósito de Negocio:** Marcar como nula una solicitud de justificación tras comprobar que el certificado médico o soporte adjuntado por el estudiante era falso o adulterado.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `Asistencia`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Actualizar el estado de `SolicitudRevisionAsistencia` a "ANULADA_FRAUDE".
  2. Restablecer la asistencia a "FALTA_DISCIPLINARIA_UNILATERAL".
  3. Emitir reporte disciplinario a la Decanatura.
- **Reglas de Negocio y Validaciones Específicas:**
  * Bloquea al estudiante para radicar nuevas justificaciones durante el semestre.
- **Estado Resultante en la BD:** Solicitud anulada por fraude y falta disciplinaria registrada.

---

### [PR-166] - Configuración de Tipos de Causa Justificable por Programa Académico
- **Historias de Usuario que satisface:** HU005, HU066.
- **Propósito de Negocio:** Definir cuáles razones del catálogo `RazonCausa` son aceptables según la naturaleza del programa (ej. en internado médico aplican causas distintas a ingeniería).
- **Entidades del MER Involucradas:** `RazonCausa`, `Programa`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Configurar la matriz de razones justificables por programa.
- **Reglas de Negocio y Validaciones Específicas:**
  * Filtra las opciones visibles en la app del estudiante al radicar justificaciones.
- **Estado Resultante en la BD:** Matriz de causas por programa guardada.

---

### [PR-167] - Mapeo de Solicitudes de Revisión con Expediente Médico de Bienestar Universitario
- **Historias de Usuario que satisface:** HU014, HU035.
- **Propósito de Negocio:** Validar automáticamente que el soporte médico adjuntado coincida con la incapacidad registrada en la enfermería universitaria.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar el servicio de salud universitario con el documento del alumno.
  2. Si existe incapacidad validada para la fecha de la falta, marcar la solicitud con bandera "VERIFICADA_BIENESTAR".
- **Reglas de Negocio y Validaciones Específicas:**
  * Agiliza la aprobación del docente en la app.
- **Estado Resultante en la BD:** Solicitud verificada por bienestar.

---

### [PR-168] - Recálculo General de Porcentajes de Ausentismo por Modificación Retroactiva de Calendario
- **Historias de Usuario que satisface:** HU001, HU013.
- **Propósito de Negocio:** Recalcular todos los porcentajes de faltas acumuladas de los estudiantes cuando se agrega o elimina una sesión del calendario de clases.
- **Entidades del MER Involucradas:** `EstudianteGrupo`, `Asistencia`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Obtener el nuevo número total de sesiones válidas del grupo.
  2. Recalcular atómicamente el `%` de inasistencias para cada `EstudianteGrupo`.
  3. Actualizar o retirar banderas de alerta temprana (`PR-155`).
- **Reglas de Negocio y Validaciones Específicas:**
  * Mantiene la paridad exacta entre faltas reales y % de pérdida de materia.
- **Estado Resultante en la BD:** Ausentismo de los alumnos recalculado.

---

### [PR-169] - Generación de Indicador KPI de Cumplimiento de Toma de Lista por Docente
- **Historias de Usuario que satisface:** HU060 (Monitorear docentes que no siguen el proceso).
- **Propósito de Negocio:** Calcular el porcentaje de clases en las que cada profesor tomó asistencia a tiempo vs sesiones olvidadas o cerradas por el sistema.
- **Entidades del MER Involucradas:** `Docente`, `Grupo`, `Sesion`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Contar el total de sesiones dictadas por el docente.
  2. Contar cuántas sesiones fueron cerradas con tomadas de lista manual/autónoma a tiempo.
  3. Calcular el KPI de cumplimiento docente y retornar a coordinación.
- **Reglas de Negocio y Validaciones Específicas:**
  * Utilizado para evaluación de desempeño docente.
- **Estado Resultante en la BD:** Indicador KPI de cumplimiento docente calculado.

---

### [PR-170] - Exportación Registros de Asistencia a Formato Oficial de Acta de Notas y Faltas
- **Historias de Usuario que satisface:** HU027, HU029, HU040.
- **Propósito de Negocio:** Consolidar en un solo archivo plano u objeto de salida la lista de estudiantes de un grupo con sus calificaciones y faltas totales al cerrar el semestre.
- **Entidades del MER Involucradas:** `Grupo`, `EstudianteGrupo`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Extraer los matriculados finales del grupo.
  2. Consolidar el total de faltas justificadas, inasistencias y estado final (Aprobó / Reprobó por inasistencias).
  3. Firmar digitalmente la planilla de entrega.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requisito previo para el cierre definitivo de actas.
- **Estado Resultante en la BD:** Acta oficial de asistencia generada.

---

### [PR-171] - Consulta de Solicitudes de Justificación Vencidas Sin Respuesta del Docente
- **Historias de Usuario que satisface:** HU035, HU171.
- **Propósito de Negocio:** Listar aquellas solicitudes de revisión de asistencia que llevan más de 5 días hábiles en estado "PENDIENTE" sin que el docente las haya aprobado o rechazado.
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `Grupo`, `Docente`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar la entidad `SolicitudRevisionAsistencia` filtrando por estado "PENDIENTE" y `fechaSolicitud < NOW() - 5_DIAS`.
  2. Retornar el listado a la coordinación de programa.
- **Reglas de Negocio y Validaciones Específicas:**
  * Dispara alerta al docente recordándole responder la solicitud.
- **Estado Resultante en la BD:** Reporte de solicitudes vencidas retornado.

---

### [PR-172] - Aprobación Automática de Justificación por Silencio Administrativo del Docente
- **Historias de Usuario que satisface:** HU010, HU037.
- **Propósito de Negocio:** Aplicar el principio de silencio administrativo positivo. Si un docente no responde una justificación médica en más de 10 días, el sistema aprueba automáticamente la excusa y marca la asistencia como "JUSTIFICADA".
- **Entidades del MER Involucradas:** `SolicitudRevisionAsistencia`, `Asistencia`, `Estado`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Buscar solicitudes pendientes con más de 10 días de antigüedad.
  2. Ejecutar la aprobación automática (`PR-152`) registrando la causal "APROBADO_POR_SILENCIO_ADMINISTRATIVO".
  3. Actualizar la tupla en `Asistencia` a "JUSTIFICADA".
- **Reglas de Negocio y Validaciones Específicas:**
  * Protege al estudiante ante la inacción o negligencia del profesor.
- **Estado Resultante en la BD:** Justificación aprobada por silencio administrativo.

---

### [PR-173] - Notificación a Acudiente / Tutor Externo por Ausentismo Reiterado de Estudiante
- **Historias de Usuario que satisface:** HU013.
- **Propósito de Negocio:** Enviar una alerta formal por correo al acudiente o tutor legal registrado de un alumno menor de edad o becado que ha faltado a más de 3 clases consecutivas.
- **Entidades del MER Involucradas:** `Estudiante`, `Usuario`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la configuración de notificación a acudientes.
  2. Emitir el correo de alerta con el desglose de faltas.
- **Reglas de Negocio y Validaciones Específicas:**
  * Exige autorización previa de tratamiento de datos.
- **Estado Resultante en la BD:** Notificación a acudiente enviada.

---

### [PR-174] - Reporte de Inconsistencias entre Horarios de Grupo y Fechas de Sesiones Realizadas
- **Historias de Usuario que satisface:** HU028, HU034.
- **Propósito de Negocio:** Diagnosticar clases que fueron dictadas en días u horas totalmente fuera del horario configurado para el grupo.
- **Entidades del MER Involucradas:** `Grupo`, `Horario`, `Sesion`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Comparar la fecha y hora de las `Sesion` registradas vs las franjas de `Horario` del grupo.
  2. Listar las sesiones extemporáneas para revisión de auditoría académica.
- **Reglas de Negocio y Validaciones Específicas:**
  * Permite detectar clases dictadas en horarios no autorizados.
- **Estado Resultante en la BD:** Reporte de inconsistencias horarias retornado.

---

### [PR-175] - Consolidación de Histórico Académico de Asistencias para Proceso de Graduación
- **Historias de Usuario que satisface:** HU002.
- **Propósito de Negocio:** Certificar que un estudiante candidato a grado cumplió con el requisito institucional de porcentaje mínimo de asistencia en todas las asignaturas de su plan de estudio.
- **Entidades del MER Involucradas:** `Estudiante`, `EstudiantePrograma`, `EstudianteGrupo`, `Asistencia`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Verificar todas las asignaturas del plan de estudio cursadas por el alumno.
  2. Certificar que ninguna asignatura tenga estado de reprobación por inasistencia.
  3. Emitir el aval de asistencia para el expediente de graduación.
- **Reglas de Negocio y Validaciones Específicas:**
  * Requisito indispensable para el paz y salvo de graduación.
- **Estado Resultante en la BD:** Aval de asistencia para grado emitido.

---

### [PR-176] - Auditoría General de Trazabilidad de Transacciones (`idCorrelacion`)
- **Historias de Usuario que satisface:** Auditoría General del Ecosistema BD.
- **Propósito de Negocio:** Consultar toda la cadena de eventos y operaciones ejecutadas en la BD bajo un único identificador de correlación (`idCorrelacion`), permitiendo reconstruir exactamente un flujo completo de negocio de principio a fin.
- **Entidades del MER Involucradas:** Bitácoras de Auditoría de todas las entidades.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Filtrar las trazas de auditoría por el `idCorrelacion` ingresado.
  2. Ordenar cronológicamente las operaciones (`INSERT`, `UPDATE`, `DELETE`).
  3. Retornar el mapa completo de ejecución de la transacción.
- **Reglas de Negocio y Validaciones Específicas:**
  * Permite a los ingenieros de soporte auditar cualquier fallo de concurrencia o inconsistencia reportada por los usuarios.
- **Estado Resultante en la BD:** Trazabilidad completa de la transacción retornada.

---

### [PR-177] - Consulta de Log de Errores y Excepciones en Procedimientos Reactivos
- **Historias de Usuario que satisface:** Monitoreo y Mantenimiento Técnico.
- **Propósito de Negocio:** Retornar los mensajes de error técnico y excepciones capturadas durante la ejecución de los procedimientos reactivos para diagnóstico oportuno.
- **Entidades del MER Involucradas:** Bitácora de Excepciones del Sistema.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Consultar la tabla de logs de excepciones filtrando por fecha, procedimiento o usuario.
  2. Retornar el detalle del mensaje técnico y el stack de error.
- **Reglas de Negocio y Validaciones Específicas:**
  * Herramienta exclusiva para administradores de base de datos y desarrolladores.
- **Estado Resultante en la BD:** Consulta de logs de error ejecutada.

---

### [PR-178] - Mantenimiento de Parámetros Globales de Sistema (`Parametro`)
- **Historias de Usuario que satisface:** Configuración Ecosistema.
- **Propósito de Negocio:** Crear o actualizar variables de configuración global del ecosistema (ej. minutos de tolerancia de llegada tarde, plazo de justificación de faltas, habilitación de QR dinámico).
- **Entidades del MER Involucradas:** `Parametro`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la clave del parámetro en la tabla `Parametro`.
  2. Actualizar el valor y la descripción del parámetro.
- **Reglas de Negocio and Validaciones Específicas:**
  * Impacta de forma inmediata y centralizada el comportamiento de todos los procedimientos reactivos.
- **Estado Resultante en la BD:** Campo `Parametro` actualizado.

---

### [PR-179] - Respaldar y Archivar Registros de Asistencia de Periodos Académicos Históricos
- **Historias de Usuario que satisface:** Mantenimiento y Rendimiento BD.
- **Propósito de Negocio:** Mover registros de `Asistencia` y `Sesion` de hace más de 5 años a tablas de archivo histórico para optimizar la velocidad y el tamaño de las tablas operativas principales.
- **Entidades del MER Involucradas:** `Asistencia`, `Sesion`, `PeriodoAcademico`.
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Identificar periodos académicos concluidos hace más de 5 años.
  2. Transferir atómicamente sus tuplas a las tablas de archivo histórico (`Asistencia_Historico`).
  3. Purgar los registros de la tabla operativa principal sin perder la capacidad de consulta agregada.
- **Reglas de Negocio y Validaciones Específicas:**
  * Operación de mantenimiento nocturna que preserva el 100% de la integridad referencial.
- **Estado Resultante en la BD:** Tablas de producción optimizadas y registros antiguos archivados.

---

### [PR-180] - Cierre Anual Auditoría de Integridad del Ecosistema `gestionasistenciadb`
- **Historias de Usuario que satisface:** Auditoría General y Certificación de Integridad.
- **Propósito de Negocio:** Ejecutar una batería completa de pruebas de integridad referencial, consistencia de claves foráneas y ausencia de registros huérfanos en todas las entidades del MER al finalizar el año lectivo, emitiendo el certificado oficial de sanidad del ecosistema de base de datos.
- **Entidades del MER Involucradas:** Todas las entidades del MER (`Usuario`, `Docente`, `Estudiante`, `Grupo`, `Sesion`, `Asistencia`, `SolicitudRevisionAsistencia`, `Programa`, `Facultad`, `Institucion`).
- **Flujo Paso a Paso (Paso Reactivo Atómico):**
  1. Validar la inexistencia de claves foráneas nulas o rotas en las tablas del MER.
  2. Verificar la paridad entre sesiones abiertas, listas de clase y marcajes en `Asistencia`.
  3. Certificar la consistencia del ausentismo en `EstudianteGrupo`.
  4. Generar y firmar el acta técnica de auditoría anual de la BD.
- **Reglas de Negocio y Validaciones Específicas:**
  * Procedimiento de cierre anual obligatorio de la arquitectura del ecosistema.
- **Estado Resultante en la BD:** Certificado de integridad de la base de datos emitido exitosamente.

---






