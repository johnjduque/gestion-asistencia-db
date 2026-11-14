---
status: active
type: catalog
scope: database
owner: database-team
generated-by: scripts/generar-catalogo-mensajes.ps1
---

# Catálogo de mensajes

> Documento **generado** desde `schema/seed/*.sql` (MERGE sobre `CatalogoMensajeUsuario` y `CatalogoMensajeTecnico`). No editar a mano: agregue o cambie el seed y ejecute `./scripts/generar-catalogo-mensajes.ps1`. Verificación: `./scripts/generar-catalogo-mensajes.ps1 -Check`.

Uso en SP: `EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = '<CODIGO>', @p_param1 = ...`. Los marcadores `{}` / `{0}` se reemplazan con los parámetros. El mensaje técnico se entrega como `DBCODE=<CODIGO>|<texto>` (ver `docs/contracts/DB_BASELINE_CONTRACT.md`).

Total de códigos: **497**.

## ACC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ACC_APP_001` | SECURITY_ERROR | ALTO | El docente autenticado no tiene titularidad sobre el grupo consultado. | Backend (FORBIDDEN): El docente autenticado no tiene titularidad sobre el grupo consultado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_002` | SECURITY_ERROR | ALTO | El docente autenticado no tiene titularidad sobre el grupo solicitado. | Backend (FORBIDDEN): El docente autenticado no tiene titularidad sobre el grupo solicitado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_003` | SECURITY_ERROR | ALTO | No fue posible resolver el docente autenticado. | Backend (FORBIDDEN): No fue posible resolver el docente autenticado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_004` | SECURITY_ERROR | ALTO | No fue posible resolver el estudiante autenticado. | Backend (FORBIDDEN): No fue posible resolver el estudiante autenticado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_005` | SECURITY_ERROR | ALTO | No fue posible resolver el usuario autenticado. | Backend (FORBIDDEN): No fue posible resolver el usuario autenticado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_006` | SECURITY_ERROR | ALTO | No fue posible resolver el programa del coordinador autenticado. | Backend (FORBIDDEN): No fue posible resolver el programa del coordinador autenticado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_007` | SECURITY_ERROR | ALTO | No fue posible resolver el programa ni la facultad del usuario autenticado. | Backend (FORBIDDEN): No fue posible resolver el programa ni la facultad del usuario autenticado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_008` | SECURITY_ERROR | ALTO | El plan de estudio solicitado no pertenece al ámbito del usuario autenticado. | Backend (FORBIDDEN): El plan de estudio solicitado no pertenece al ambito del usuario autenticado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_009` | SECURITY_ERROR | ALTO | La asignatura no pertenece al programa del coordinador autenticado. | Backend (FORBIDDEN): La asignatura no pertenece al programa del coordinador autenticado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_010` | SECURITY_ERROR | ALTO | El plan de estudio no pertenece al programa del coordinador autenticado. | Backend (FORBIDDEN): El plan de estudio no pertenece al programa del coordinador autenticado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_011` | SECURITY_ERROR | ALTO | No fue posible resolver la facultad del decano autenticado. | Backend (FORBIDDEN): No fue posible resolver la facultad del decano autenticado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_012` | SECURITY_ERROR | ALTO | El usuario autenticado no puede gestionar cuentas de acceso. | Backend (FORBIDDEN): El usuario autenticado no puede gestionar cuentas de acceso. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_013` | SECURITY_ERROR | ALTO | La cuenta indicada está fuera del alcance del usuario autenticado. | Backend (FORBIDDEN): La cuenta indicada esta fuera del alcance del usuario autenticado. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_014` | SECURITY_ERROR | ALTO | El usuario autenticado no tiene autorización institucional para consultar el reporte del grupo. | Backend (FORBIDDEN): El usuario autenticado no tiene autorizacion institucional para consultar el reporte del grupo. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_015` | SECURITY_ERROR | ALTO | El usuario autenticado no tiene relación institucional con la sesión consultada. | Backend (FORBIDDEN): El usuario autenticado no tiene relacion institucional con la sesion consultada. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_016` | SECURITY_ERROR | ALTO | El docente autenticado no tiene titularidad sobre la sesión consultada. | Backend (FORBIDDEN): El docente autenticado no tiene titularidad sobre la sesion consultada. | `62_val_mensajes_aplicacion.sql` |
| `ACC_APP_017` | SECURITY_ERROR | ALTO | El usuario autenticado no tiene acceso al grupo solicitado. | Backend (FORBIDDEN): El usuario autenticado no tiene acceso al grupo solicitado. | `62_val_mensajes_aplicacion.sql` |

## ADS

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ADS_001` | SUCCESS | BAJO | Estudiante admitido. | HU156: estudiante admitido en el programa; Usuario, Estudiante y EstudiantePrograma confirmados. | `54_culm001_d4_mensajes.sql` |
| `ADS_002` | BUSINESS_ERROR | BAJO | El estudiante ya está admitido en este programa. | HU156: EstudiantePrograma ya existe para el estudiante y el programa; sin escrituras. | `54_culm001_d4_mensajes.sql` |
| `ADS_003` | BUSINESS_ERROR | MEDIO | El programa no existe o no pertenece a tu institución. | Ambito: el programa no existe, esta inactivo o no es de la institucion del administrador; sin escrituras. | `54_culm001_d4_mensajes.sql` |
| `ADS_004` | BUSINESS_ERROR | MEDIO | El documento y el correo corresponden a personas distintas. | Regla: el documento y el correo no pertenecen al mismo Usuario (SUPUESTO-D-11); sin escrituras. | `54_culm001_d4_mensajes.sql` |
| `ADS_005` | VALIDATION_ERROR | BAJO | El correo debe ser institucional ({}). | Regla: el correo de un alta nueva no cumple REGISTRO/DOMINIO_CORREO_ESTUDIANTE ({}); sin escrituras. | `54_culm001_d4_mensajes.sql` |
| `ADS_006` | VALIDATION_ERROR | BAJO | Indica una contraseña inicial para el estudiante nuevo. | Regla: un alta nueva exige el hash de la contrasena inicial; sin escrituras. | `54_culm001_d4_mensajes.sql` |

## ALR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ALR_001` | SUCCESS | BAJO | Las alertas de inasistencia están deshabilitadas. | ALERTA_INASISTENCIA/HABILITADA != true; grupo [{}] sin escrituras. | `40_culm001_c_mensajes.sql` |
| `ALR_002` | TECHNICAL_ERROR | CRITICO | No fue posible evaluar las alertas de inasistencia. | Umbral [{}] del tipo [{}] ausente o no numérico. | `40_culm001_c_mensajes.sql` |
| `ALR_003` | SUCCESS | BAJO | Evaluación de alertas completada. | Grupo [{}]: {} nuevas, {} superadas o reactivadas; revisiones creadas en novedadesJSON. | `40_culm001_c_mensajes.sql` |
| `ALR_004` | VALIDATION_ERROR | BAJO | La lista de alertas no es válida. | @alertasJSON vacío, inválido, con duplicados o con más de {}. | `40_culm001_c_mensajes.sql` |
| `ALR_005` | SUCCESS | BAJO | Se marcaron {} alertas como leídas. | Lectura de alertas del estudiante [{}]. | `40_culm001_c_mensajes.sql` |
| `ALR_006` | VALIDATION_ERROR | BAJO | La matrícula indicada no pertenece al grupo. | EstudianteGrupo [{}] no es del grupo [{}]. | `40_culm001_c_mensajes.sql` |
| `ALR_007` | SUCCESS | BAJO | Actualización de resolutores completada. | {} reasignadas, {} escaladas, {} sin resolutor. | `40_culm001_c_mensajes.sql` |
| `ALR_010` | INFO | BAJO | Llevas {}% de inasistencia en {}. Si llegas al {}% podrías perder la asignatura. | Texto ADVERTENCIA. | `40_culm001_c_mensajes.sql` |
| `ALR_011` | INFO | MEDIO | Alcanzaste {}% de inasistencia en {} (límite {}%). Tu docente revisará tu caso. | Texto PERDIDA. | `40_culm001_c_mensajes.sql` |

## AQR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `AQR_001` | BUSINESS_ERROR | BAJO | El código QR o el PIN no es válido o ya venció. Pide el PIN vigente al docente. | Token/PIN sin coincidencia vigente. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_002` | SECURITY_ERROR | MEDIO | Debes estar conectado a la red Wi-Fi del campus para registrar tu asistencia. | IP [{}] fuera de RED/CIDRS_CAMPUS. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_003` | BUSINESS_ERROR | BAJO | Esta toma es manual; no admite código QR. | Toma [{}] con usaCodigoQr = 0. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_004` | BUSINESS_ERROR | BAJO | No estás matriculado en el grupo de esta clase. | Estudiante [{}] sin matrícula A en grupo [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_005` | BUSINESS_ERROR | BAJO | La toma de asistencia ya se cerró. | Toma/token [{}] cerrado o expirado. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_006` | TECHNICAL_ERROR | BAJO | No fue posible generar el código. Intenta de nuevo. | PIN [{}] repetido entre activos/anteriores vigentes; reintentar. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_007` | VALIDATION_ERROR | BAJO | Escanea el código QR o digita el PIN. | Se requiere exactamente uno de @tokenHash o @pin. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_008` | SUCCESS | BAJO | Tu asistencia a esta toma ya estaba registrada. | Detalle existente para estudiante [{}] toma [{}]; sin cambios. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_009` | SUCCESS | BAJO | ¡Listo! Tu asistencia quedó registrada. | Asistencia AN por token: estudiante [{}] toma [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_010` | BUSINESS_ERROR | BAJO | El registro de asistencia por QR no está disponible. | ASISTENCIA_QR/HABILITADA != true. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_011` | SECURITY_ERROR | BAJO | Hiciste demasiados intentos. Espera un minuto e intenta de nuevo. | Límite [{}] superado para clave [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_012` | SUCCESS | BAJO | Código QR listo para proyectar. | Token de asistencia [{}] emitido para toma [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `AQR_013` | SUCCESS | BAJO | Se dejó de proyectar el código QR. | Token de la toma [{}] cerrado. | `35_mensajes_toma_asistencia_qr.sql` |

## ARC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ARC_001` | BUSINESS_ERROR | ALTO | El soporte indicado no esta disponible para esta solicitud. | Soporte no disponible para radicar: inexistente, de otro propietario, ya vinculado o no vigente. | `15_lb004d_archivo_soporte.sql` |
| `ARC_002` | BUSINESS_ERROR | ALTO | No fue posible registrar el soporte. | Registro de soporte rechazado: el identificador ya existe con otro propietario o con metadata distinta. | `15_lb004d_archivo_soporte.sql` |
| `ARC_003` | BUSINESS_ERROR | MEDIO | Los datos del soporte no son validos. | Metadata de soporte invalida: identificador, nombre, tipo de contenido, tamano o checksum fuera de contrato. | `15_lb004d_archivo_soporte.sql` |
| `ARC_005` | BUSINESS_ERROR | ALTO | El estudiante indicado no corresponde al usuario autenticado. | El idEstudiante no pertenece al idUsuarioEjecutor. | `15_lb004d_archivo_soporte.sql` |

## ARE

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ARE_001` | BUSINESS_ERROR | MEDIO | El área de conocimiento especificada no existe en el sistema. | Error de búsqueda: No se encontró el área de conocimiento en uv_area: {}. | `04_mensaje.sql` |
| `ARE_002` | BUSINESS_ERROR | ALTO | Ya existe un área de conocimiento con el mismo código o nombre. | Error de unicidad: código o nombre duplicado en área de conocimiento. | `04_mensaje.sql` |

## ASI

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ASI_001` | BUSINESS_ERROR | MEDIO | Los créditos de la asignatura son obligatorios y deben ser mayores que cero. | Validacion: @creditos nulo o menor o igual a cero; no se asigna un valor por defecto. | `29_mensajes_asignatura.sql` |
| `ASI_002` | BUSINESS_ERROR | MEDIO | Ya existe una asignatura con ese código. Usa "Asociar asignatura existente" para agregarla a este plan. | Regla: Asignatura.codigo es unico global (UX_Asignatura_codigo); use usp_asociar_asignatura_plan para vincular una existente. | `38_mensajes_asignatura_plan.sql` |
| `ASI_003` | BUSINESS_ERROR | MEDIO | La asignatura ya está asociada a este plan de estudios. | Regla: la asignatura ya tiene un vinculo activo en el plan (mismo u otro semestre). | `38_mensajes_asignatura_plan.sql` |
| `ASI_004` | BUSINESS_ERROR | MEDIO | La asignatura no está asociada a este plan de estudios. | Regla: la asignatura no tiene vinculo activo con el plan indicado. | `38_mensajes_asignatura_plan.sql` |
| `ASI_005` | BUSINESS_ERROR | ALTO | No puedes quitar la asignatura de este plan: tiene grupos o estudiantes del programa en el periodo vigente o en periodos futuros. | Regla: hay grupos vigentes o futuros, o matriculas activas, cuyo unico programa comun es el del plan. | `38_mensajes_asignatura_plan.sql` |
| `ASI_006` | BUSINESS_ERROR | MEDIO | La asignatura es compartida con programas que no coordinas; solo puedes cambiar su semestre y su carácter en tu plan. | Regla S2: el catalogo de una asignatura compartida solo lo cambia quien coordina todos sus programas con vinculo activo. | `38_mensajes_asignatura_plan.sql` |
| `ASI_007` | BUSINESS_ERROR | MEDIO | El carácter de la asignatura no es válido. | Validacion: codigoCaracter no existe en CaracterAsignaturaPlan o esta inactivo. | `38_mensajes_asignatura_plan.sql` |
| `ASI_008` | BUSINESS_ERROR | MEDIO | Los créditos de la asignatura no pueden superar {}. | Regla DEC-073: @creditos supera ASIGNATURA/CREDITOS_MAXIMO ({}) o el parametro no existe. | `64_dec073_validaciones.sql` |

## ATT

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ATT_001` | BUSINESS_ERROR | MEDIO | El payload JSON de asistencia no cumple el contrato requerido. | Payload JSON inválido: se requiere un arreglo no nulo de objetos con exactamente idEstudiante y estado. | `04_mensaje.sql` |
| `ATT_002` | BUSINESS_ERROR | MEDIO | El lote de asistencia no puede estar vacío. | Payload JSON válido pero vacío: no hay operación de negocio que ejecutar. | `04_mensaje.sql` |
| `ATT_003` | BUSINESS_ERROR | MEDIO | El estudiante {} aparece más de una vez en el lote de asistencia. | Duplicidad en payload JSON: idEstudiante [{}] aparece más de una vez. | `04_mensaje.sql` |

## AUD

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `AUD_001` | BUSINESS_ERROR | MEDIO | La consulta de auditoría requiere una sola institución activa. | SUPUESTO-D-16: hay {} instituciones activas; la auditoría no tiene ámbito por institución. | `56_culm001_d6_mensajes.sql` |
| `AUD_002` | VALIDATION_ERROR | BAJO | Los filtros de solo asistencia y solo administración no se pueden combinar. | @soloAsistencia = 1 y @soloAdministracion = 1 son excluyentes; el llamador debe enviar los dos parametros explicitos. | `56_culm001_d6_mensajes.sql` |

## CMA

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `CMA_001` | VALIDATION_ERROR | MEDIO | El archivo supera {} filas. | HU171: cantidad de filas {} supera CARGA_MASIVA/MAXIMO_FILAS ({}). | `55_culm001_d5_mensajes.sql` |
| `CMA_002` | VALIDATION_ERROR | MEDIO | El archivo supera el tamaño permitido. | HU171: tamano de archivo {} bytes supera CARGA_MASIVA/TAMANIO_MAXIMO_BYTES ({}). | `55_culm001_d5_mensajes.sql` |
| `CMA_003` | BUSINESS_ERROR | ALTO | El archivo cambió desde la validación. Valídalo de nuevo. | HU171: huella SHA-256 no coincide con la validada previamente. | `55_culm001_d5_mensajes.sql` |
| `CMA_004` | VALIDATION_ERROR | MEDIO | La cabecera no coincide con la plantilla: {}. | HU171: cabecera del CSV no valida o incompleta: {}. | `55_culm001_d5_mensajes.sql` |
| `CMA_005` | VALIDATION_ERROR | BAJO | Número de documento inválido. | HU171: numero de documento no es un entero positivo en rango INT. | `55_culm001_d5_mensajes.sql` |
| `CMA_006` | VALIDATION_ERROR | BAJO | Código de {} desconocido: {}. | HU171: codigo de {} '{}' no existe en catalogo. | `55_culm001_d5_mensajes.sql` |
| `CMA_007` | BUSINESS_ERROR | MEDIO | «{}» no está en tu ámbito. | HU171: entidad '{}' no pertenece al ambito de custodia del ejecutor. | `55_culm001_d5_mensajes.sql` |
| `CMA_008` | BUSINESS_ERROR | MEDIO | El documento y el correo corresponden a personas distintas. | HU171: documento y correo corresponden a diferentes personas existentes. | `55_culm001_d5_mensajes.sql` |
| `CMA_009` | BUSINESS_ERROR | ALTO | Tu rol no puede cargar este tipo de cuentas. | HU171: jerarquia no permitida en JerarquiaAltaUsuario para este perfil ejecutor y destino. | `55_culm001_d5_mensajes.sql` |
| `CMA_010` | VALIDATION_ERROR | BAJO | Fila repetida en el archivo (línea {}). | HU171: documento o correo repetido respecto a la linea {}. | `55_culm001_d5_mensajes.sql` |
| `CMA_011` | VALIDATION_ERROR | MEDIO | Valor no permitido en la columna {}. | HU171: intento de inyeccion de formulas o caracteres no permitidos en columna {}. | `55_culm001_d5_mensajes.sql` |
| `CMA_012` | VALIDATION_ERROR | BAJO | Falta la clave inicial para una persona nueva. | HU171: persona nueva requiere clave inicial valida segun PasswordRegistroRule. | `55_culm001_d5_mensajes.sql` |
| `CMA_013` | VALIDATION_ERROR | MEDIO | El archivo no es un CSV UTF-8 válido. | HU171: codificacion del archivo no es UTF-8 valida o archivo malformado. | `55_culm001_d5_mensajes.sql` |
| `CMA_014` | BUSINESS_ERROR | MEDIO | Has superado el número de cargas por minuto. | HU171: tasa de peticiones supera CARGA_MASIVA/LIMITE_POR_MINUTO. | `55_culm001_d5_mensajes.sql` |
| `CMA_015` | SUCCESS | BAJO | Carga procesada: {} creadas, {} ya existentes, {} con error. | HU171: resultado de ejecucion: creadas={}, yaExistentes={}, conError={}. | `55_culm001_d5_mensajes.sql` |

## COO

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `COO_001` | BUSINESS_ERROR | ALTO | No se puede desactivar al coordinador mientras tenga un programa activo a cargo. Reasigne o desactive el programa primero. | Regla de negocio: el coordinador {} coordina el programa activo {}. | `04_mensaje.sql` |
| `COO_002` | BUSINESS_ERROR | MEDIO | Coordinas varios programas: selecciona el programa que quieres consultar. | Regla S4: el coordinador tiene varios programas y no envio idPrograma. | `38_mensajes_asignatura_plan.sql` |
| `COO_003` | BUSINESS_ERROR | ALTO | El programa indicado no pertenece a tu coordinación. | Regla de ambito: idPrograma no esta entre los programas del coordinador. | `38_mensajes_asignatura_plan.sql` |

## CORR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `CORR_001` | BUSINESS_ERROR | ALTO | El identificador de correlación no está presente o está vacío. | Validación fallida: idCorrelacion no está presente o no es un UUID válido. Transacción no procesable. | `04_mensaje.sql` |

## DEC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `DEC_001` | BUSINESS_ERROR | MEDIO | El decano especificado no existe en el sistema. | Error de búsqueda: No se encontró el decano en uv_decano_identidad: {}. | `04_mensaje.sql` |
| `DEC_002` | BUSINESS_ERROR | ALTO | No se puede desactivar al decano de una facultad con programas activos. | Regla: el decano [{}] dirige una facultad con el programa activo [{}]; no se desactiva. | `33_culm001_a_mensajes.sql` |
| `DEC_003` | SUCCESS | BAJO | Se actualizó el estado del decano. | Actualizacion: Decano.estado del decano [{}] actualizado (regla D1 aplicada a Usuario.estado). | `33_culm001_a_mensajes.sql` |
| `DEC_020` | BUSINESS_ERROR | MEDIO | La persona ya está registrada como decano. | Regla: la persona ya tiene un registro de Decano activo (Decano.estado = 1); sin escrituras. | `59_culm001_d9_mensajes.sql` |

## DIS

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `DIS_APP_001` | BUSINESS_ERROR | MEDIO | La generación automática de sesiones al crear el grupo aún no está disponible (fase F2: precarga de sesiones). | Backend (FEATURE_UNAVAILABLE): La generacion automatica de sesiones al crear el grupo aun no esta disponible (fase F2: precarga de sesiones). | `62_val_mensajes_aplicacion.sql` |

## DOC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `DOC_001` | BUSINESS_ERROR | MEDIO | El docente especificado no existe o se encuentra inactivo. | Error de búsqueda: Docente no encontrado o deshabilitado en uv_docente: {}. | `04_mensaje.sql` |
| `DOC_002` | BUSINESS_ERROR | MEDIO | El usuario ya se encuentra registrado como docente. | Unicidad: el usuario ya tiene un registro en dbo.Docente. | `17_mensaje_docente_programa.sql` |
| `DOC_003` | BUSINESS_ERROR | ALTO | Ya existe una persona registrada con ese documento o correo. Use la opción "Vincular docente existente". | Conflicto de identidad: documento o correo ya existen en dbo.Usuario; el modo nuevo no hace find-or-create. | `17_mensaje_docente_programa.sql` |
| `DOC_004` | BUSINESS_ERROR | MEDIO | El tipo de vinculación indicado no existe o está inactivo. | Validación: TipoVinculacion inexistente o con estado = 0. | `17_mensaje_docente_programa.sql` |
| `DOC_005` | BUSINESS_ERROR | MEDIO | Debe indicar un docente existente o los datos de un docente nuevo, pero no ambos. | Validación de modo: exactamente uno entre @idDocente, @idUsuario o el bloque de datos de persona nueva. | `17_mensaje_docente_programa.sql` |
| `DOC_006` | BUSINESS_ERROR | MEDIO | El docente ya está vinculado a este programa. | Unicidad: ya existe dbo.DocentePrograma para el par (docente, programa). | `17_mensaje_docente_programa.sql` |
| `DOC_007` | BUSINESS_ERROR | BAJO | La búsqueda de candidatos requiere al menos 3 caracteres. | Validación: @busqueda de candidatos con menos caracteres que DOCENTE/BUSQUEDA_MIN_CARACTERES. | `17_mensaje_docente_programa.sql` |
| `DOC_008` | BUSINESS_ERROR | MEDIO | El docente no está vinculado a este programa. | Existencia: no hay dbo.DocentePrograma para el par (docente, programa) indicado. | `17_mensaje_docente_programa.sql` |
| `DOC_009` | BUSINESS_ERROR | MEDIO | El docente no tiene una vinculación activa con el programa. | Regla: el docente no tiene dbo.DocentePrograma con estado = 1 en el programa del grupo. | `17_mensaje_docente_programa.sql` |

## ERR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `ERR_ACCION_REVISION_INVALIDA` | VALIDATION_ERROR | BAJO | La acción sobre el reclamo debe ser APROBADA o RECHAZADA. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): La accion sobre el reclamo debe ser APROBADA o RECHAZADA. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_ACCION_REVISION_REQUERIDA` | VALIDATION_ERROR | BAJO | La acción sobre la solicitud es obligatoria. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): La accion sobre la solicitud es obligatoria. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_ANTIVIRUS_NO_DISPONIBLE` | TECHNICAL_ERROR | ALTO | El antivirus no está disponible; el archivo no se guardó. Intente de nuevo en unos minutos. | Backend (SERVICE_UNAVAILABLE, ArchivoErrorCode): ClamAV no respondio (caido, timeout, respuesta fuera del protocolo o circuit breaker malwareScan abierto); subida rechazada fail-closed con 503, sin almacenar bytes ni metadata. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_APROBACION_PRESENTE_SIN_TOMA` | BUSINESS_ERROR | MEDIO | La aprobación como presente solo aplica a reclamos de una toma. | Backend (CONFLICT, AsistenciaErrorCode): La aprobacion como presente solo aplica a reclamos de una toma. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_ASISTENCIA_REQUERIDA` | VALIDATION_ERROR | BAJO | La asistencia es obligatoria. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): La asistencia es obligatoria. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_BUSQUEDA_CANDIDATOS_CORTA` | VALIDATION_ERROR | BAJO | La búsqueda de candidatos requiere al menos 3 caracteres. | Backend (VALIDATION_ERROR, DocenteErrorCode): La busqueda de candidatos requiere al menos 3 caracteres. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_CAPACIDAD_GRUPO_INVALIDA` | SYSTEM_ERROR | CRITICO | No fue posible determinar una capacidad máxima válida para el grupo. | El parametro GRUPO/CAPACIDAD_MAXIMA_DEFECTO es nulo, cero o negativo: {}. | `04_mensaje.sql` |
| `ERR_CATEGORIA_JUSTIFICACION_INVALIDA` | VALIDATION_ERROR | BAJO | La categoría de justificación no es válida. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): La categoria de justificacion no es valida. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_CATEGORIA_REVISION_REQUERIDA` | VALIDATION_ERROR | BAJO | La categoría de la revisión es obligatoria. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): La categoria de la revision es obligatoria. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_CODIGO_GRUPO_INVALIDO` | BUSINESS_ERROR | MEDIO | El código del grupo debe ser un número entero mayor que cero. | Regla DEC-073: @codigo nulo, cero o negativo ({}). | `64_dec073_validaciones.sql` |
| `ERR_CODIGO_VERIFICACION_REQUERIDO` | VALIDATION_ERROR | BAJO | El código de verificación es obligatorio. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): El codigo de verificacion es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_CONFIGURACION_PLAZO_JUSTIFICACION` | TECHNICAL_ERROR | ALTO | No es posible validar el plazo de justificación en este momento. Intente más tarde. | Backend (TECHNICAL, AsistenciaErrorCode): Faltan ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER (REV_025). | `63_val_mensajes_err_pendientes.sql` |
| `ERR_CORRELACION_REQUERIDA` | BUSINESS_ERROR | ALTO | El codigo de correlacion es requerido. | Error: idCorrelacion no esta presente o es invalido. | `04_mensaje.sql` |
| `ERR_CORREO_FORMATO_INVALIDO` | VALIDATION_ERROR | BAJO | Ingrese un correo válido, por ejemplo nombre@dominio.com. | Backend (VALIDATION_ERROR, UsuarioErrorCode): Ingrese un correo valido, por ejemplo nombre@dominio.com. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_CORREO_LONGITUD_INVALIDA` | VALIDATION_ERROR | BAJO | El correo puede tener máximo 100 caracteres. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El correo puede tener maximo 100 caracteres. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_CORREO_REQUERIDO` | VALIDATION_ERROR | BAJO | El correo es obligatorio. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El correo es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_CORREO_REQUERIDO_MATRICULA` | VALIDATION_ERROR | BAJO | El correo es obligatorio: no hay un estudiante registrado que se pueda matricular con ese documento. | Backend (VALIDATION_ERROR, GrupoErrorCode): Codigo publico FIELD_REQUIRED (campo correo); el documento no resuelve a un estudiante matriculable. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_CRUCE_HORARIO_DOCENTE` | BUSINESS_ERROR | ALTO | Existe un cruce de horario para el docente en la misma franja horaria. | Cruce detectado en uv_horario para Docente con GrupoID: {}. | `04_mensaje.sql` |
| `ERR_CRUCE_HORARIO_ESTUDIANTE` | BUSINESS_ERROR | ALTO | No es posible realizar el registro. Existe un cruce de horario con otra asignatura. | Cruce detectado en uv_horario para Estudiante con GrupoID: {}. | `04_mensaje.sql` |
| `ERR_CUPO_INFERIOR_OCUPACION` | BUSINESS_ERROR | ALTO | La capacidad del grupo no puede ser menor al número actual de estudiantes activos. | Grupo {}: capacidad solicitada {} es menor a los estudiantes activos {}. | `04_mensaje.sql` |
| `ERR_CUPO_SUPERADO` | BUSINESS_ERROR | ALTO | El grupo ha superado la capacidad maxima de estudiantes permitida. | Cupo lleno. Maximo de estudiantes alcanzado para Grupo: {}. | `04_mensaje.sql` |
| `ERR_DESCRIPCION_SESION_LONGITUD_INVALIDA` | VALIDATION_ERROR | BAJO | Cuando se indique una descripción, debe tener entre 10 y 250 caracteres. | Backend (VALIDATION_ERROR, SesionErrorCode): Cuando se indique una descripcion, debe tener entre 10 y 250 caracteres. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_DOCENTE_INACTIVO` | BUSINESS_ERROR | MEDIO | El docente se encuentra inactivo. | Backend (CONFLICT, DocenteErrorCode): El docente se encuentra inactivo. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_DOCENTE_INVALIDO` | VALIDATION_ERROR | BAJO | El identificador del docente no es válido. | Backend (VALIDATION_ERROR, DocenteErrorCode): El identificador del docente no es valido. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_DOCENTE_NO_EXISTE` | BUSINESS_ERROR | MEDIO | El docente especificado no existe o esta inactivo. | Error: No se encontro el ID de Docente especificado: {}. | `04_mensaje.sql` |
| `ERR_DOCENTE_NO_TITULAR_GRUPO` | BUSINESS_ERROR | ALTO | El docente indicado no es el titular del grupo seleccionado. | Docente {} no es titular del Grupo {} (uv_grupo.idDocente). | `04_mensaje.sql` |
| `ERR_DOCENTE_NO_VINCULADO_PROGRAMA` | BUSINESS_ERROR | MEDIO | El docente no está vinculado a este programa. | Backend (RESOURCE_NOT_FOUND, DocenteErrorCode): El docente no esta vinculado a este programa. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_DOCENTE_REQUERIDO` | VALIDATION_ERROR | BAJO | El docente es obligatorio. | Backend (VALIDATION_ERROR, DocenteErrorCode): El docente es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_DOCENTE_SIN_TITULARIDAD_SESION` | SECURITY_ERROR | ALTO | El docente autenticado no tiene titularidad sobre la sesión indicada. | Backend (FORBIDDEN, AsistenciaErrorCode): El docente autenticado no tiene titularidad sobre la sesion indicada. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_DOCENTE_SIN_VINCULO_ACTIVO` | BUSINESS_ERROR | MEDIO | El docente no tiene una vinculación activa con el programa. | Backend (CONFLICT, DocenteErrorCode): El docente no tiene una vinculacion activa con el programa. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_DOCENTE_YA_REGISTRADO` | BUSINESS_ERROR | MEDIO | El usuario ya se encuentra registrado como docente. | Backend (CONFLICT, DocenteErrorCode): El usuario ya se encuentra registrado como docente. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_DOCENTE_YA_VINCULADO_PROGRAMA` | BUSINESS_ERROR | MEDIO | El docente ya está vinculado a este programa. | Backend (CONFLICT, DocenteErrorCode): El docente ya esta vinculado a este programa. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_ESTADO_ASISTENCIA_INVALIDO` | VALIDATION_ERROR | BAJO | El estado de asistencia debe ser AN, SJC o EX. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): El estado de asistencia debe ser AN, SJC o EX. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_ESTADO_ASISTENCIA_REQUERIDO` | VALIDATION_ERROR | BAJO | El estado de asistencia es obligatorio. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): El estado de asistencia es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_ESTUDIANTE_ID_INVALIDO` | VALIDATION_ERROR | BAJO | El identificador del estudiante no es válido. | Backend (VALIDATION_ERROR, EstudianteErrorCode): El identificador del estudiante no es valido. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_ESTUDIANTE_ID_REQUERIDO` | VALIDATION_ERROR | BAJO | El estudiante es obligatorio. | Backend (VALIDATION_ERROR, EstudianteErrorCode): El estudiante es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_ESTUDIANTE_INACTIVO` | BUSINESS_ERROR | MEDIO | El estudiante se encuentra inactivo. | Backend (CONFLICT, EstudianteErrorCode): El estudiante se encuentra inactivo. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_ESTUDIANTE_NO_EXISTE` | BUSINESS_ERROR | MEDIO | El estudiante especificado no existe. | Error: No se encontro el ID de Estudiante especificado: {}. | `04_mensaje.sql` |
| `ERR_ESTUDIANTE_NO_PERTENECE_SESION` | BUSINESS_ERROR | ALTO | El estudiante no pertenece al grupo de la sesion seleccionada. | Validacion fallida: Estudiante no pertenece al grupo de la sesion: {}. | `04_mensaje.sql` |
| `ERR_FACULTAD_INVALIDA` | VALIDATION_ERROR | BAJO | El identificador de la facultad no es válido. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El identificador de la facultad no es valido. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_GRUPO_INVALIDO` | VALIDATION_ERROR | BAJO | El identificador del grupo no es válido. | Backend (VALIDATION_ERROR, GrupoErrorCode): El identificador del grupo no es valido. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_GRUPO_NO_EXISTE` | BUSINESS_ERROR | MEDIO | El grupo seleccionado no existe o no esta habilitado. | Error: No existe un grupo habilitado con el identificador: {}. | `04_mensaje.sql` |
| `ERR_GRUPO_NO_HABILITADO` | BUSINESS_ERROR | MEDIO | El grupo seleccionado no se encuentra habilitado para matricula. | Grupo existente, pero fuera de ventana habilitada para matricula: {}. | `04_mensaje.sql` |
| `ERR_GRUPO_REQUERIDO` | VALIDATION_ERROR | BAJO | El grupo es obligatorio. | Backend (VALIDATION_ERROR, GrupoErrorCode): El grupo es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_IDENTIDAD_USUARIO_CONFLICTO` | BUSINESS_ERROR | MEDIO | El correo y el documento no corresponden al mismo usuario. | Backend (CONFLICT, UsuarioErrorCode): El correo y el documento no corresponden al mismo usuario. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_INESPERADO_REGISTRO_ASISTENCIA` | SYSTEM_ERROR | CRITICO | Hubo un error inesperado al registrar la asistencia del estudiante. | Error critico en orquestador [usp_registrar_asistencia_estudiante]: {}. | `04_mensaje.sql` |
| `ERR_INESPERADO_REGISTRO_DOCENTE` | SYSTEM_ERROR | CRITICO | Hubo un error inesperado al procesar el registro completo del docente. | Error critico en orquestador [usp_registrar_docente_en_grupo_usuario_no_existente]: {}. | `04_mensaje.sql` |
| `ERR_INESPERADO_REGISTRO_ESTUDIANTE` | SYSTEM_ERROR | CRITICO | Hubo un error inesperado al procesar el registro completo del estudiante. | Error critico en orquestador [usp_registrar_estudiante_en_grupo_usuario_no_existente]: {}. | `04_mensaje.sql` |
| `ERR_INSTITUCION_INVALIDA` | VALIDATION_ERROR | BAJO | El identificador de la institución no es válido. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El identificador de la institucion no es valido. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_JUSTIFICACION_REVISION_REQUERIDA` | VALIDATION_ERROR | BAJO | La justificación de la revisión es obligatoria. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): La justificacion de la revision es obligatoria. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_MATRICULA_DUPLICADA` | BUSINESS_ERROR | ALTO | Usted ya se encuentra registrado o matriculado en este grupo. | Registro duplicado detectado en uv_estudiante_grupo para Estudiante en Grupo: {}. | `04_mensaje.sql` |
| `ERR_MAXIMO_SOPORTES_RECLAMO` | VALIDATION_ERROR | BAJO | Se superó el máximo de soportes permitido por reclamo. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): Se supero el maximo de soportes permitido por reclamo. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_MODO_VINCULACION_INVALIDO` | VALIDATION_ERROR | BAJO | Indique un docente existente o los datos de un docente nuevo, pero no ambos. | Backend (VALIDATION_ERROR, DocenteErrorCode): Indique un docente existente o los datos de un docente nuevo, pero no ambos. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_MOTIVO_REVISION_LONGITUD_INVALIDA` | VALIDATION_ERROR | BAJO | El motivo de la revisión debe tener entre 10 y 300 caracteres. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): El motivo de la revision debe tener entre 10 y 300 caracteres. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_MOTIVO_REVISION_REQUERIDO` | VALIDATION_ERROR | BAJO | El motivo de la revisión es obligatorio. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): El motivo de la revision es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_NOMBRE_COMPLETO_DOCENTE_REQUERIDO` | VALIDATION_ERROR | BAJO | El nombre completo del docente es obligatorio. | Backend (VALIDATION_ERROR, DocenteErrorCode): El nombre completo del docente es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_NOMBRE_PERSONA_INVALIDO` | VALIDATION_ERROR | BAJO | Los nombres y apellidos solo pueden contener letras, espacios, apóstrofes y guiones. | Backend (VALIDATION_ERROR, UsuarioErrorCode): Los nombres y apellidos solo pueden contener letras, espacios, apostrofes y guiones. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_NOMBRE_PERSONA_LONGITUD_INVALIDA` | VALIDATION_ERROR | BAJO | Cada nombre o apellido puede tener máximo 50 caracteres. | Backend (VALIDATION_ERROR, UsuarioErrorCode): Cada nombre o apellido puede tener maximo 50 caracteres. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_NOMBRE_SESION_LONGITUD_INVALIDA` | VALIDATION_ERROR | BAJO | El nombre de la sesión debe tener entre 1 y 50 caracteres. | Backend (VALIDATION_ERROR, SesionErrorCode): El nombre de la sesion debe tener entre 1 y 50 caracteres. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_NOMBRE_SESION_REQUERIDO` | VALIDATION_ERROR | BAJO | El nombre de la sesión es obligatorio. | Backend (VALIDATION_ERROR, SesionErrorCode): El nombre de la sesion es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_NUMERO_IDENTIFICACION_DOCENTE_REQUERIDO` | VALIDATION_ERROR | BAJO | El número de identificación del docente es obligatorio. | Backend (VALIDATION_ERROR, DocenteErrorCode): El numero de identificacion del docente es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_NUMERO_IDENTIFICACION_INVALIDO` | VALIDATION_ERROR | BAJO | El número de identificación debe ser positivo y tener entre 6 y 10 dígitos. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El numero de identificacion debe ser positivo y tener entre 6 y 10 digitos. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_NUMERO_IDENTIFICACION_REQUERIDO` | VALIDATION_ERROR | BAJO | El número de identificación es obligatorio. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El numero de identificacion es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_OBSERVACION_ASISTENCIA_LONGITUD_INVALIDA` | VALIDATION_ERROR | BAJO | Cuando se indique una observación de asistencia, debe tener entre 5 y 250 caracteres. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): Cuando se indique una observacion de asistencia, debe tener entre 5 y 250 caracteres. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_OBSERVACION_ASISTENCIA_REQUERIDA` | VALIDATION_ERROR | BAJO | Debe indicar una observación cuando el estudiante no asiste. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): Debe indicar una observacion cuando el estudiante no asiste. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_OBSERVACION_CIERRE_LONGITUD_INVALIDA` | VALIDATION_ERROR | BAJO | La observación de cierre debe tener entre 10 y 250 caracteres. | Backend (VALIDATION_ERROR, SesionErrorCode): La observacion de cierre debe tener entre 10 y 250 caracteres. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_OBSERVACION_CIERRE_REQUERIDA` | VALIDATION_ERROR | BAJO | La observación de cierre es obligatoria. | Backend (VALIDATION_ERROR, SesionErrorCode): La observacion de cierre es obligatoria. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_PASSWORD_IGUAL_IDENTIFICACION` | VALIDATION_ERROR | BAJO | La clave no puede ser igual al número de identificación. | Backend (VALIDATION_ERROR, UsuarioErrorCode): La clave no puede ser igual al numero de identificacion. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_PASSWORD_LONGITUD_INVALIDA` | VALIDATION_ERROR | BAJO | La clave puede tener máximo 255 caracteres. | Backend (VALIDATION_ERROR, UsuarioErrorCode): La clave puede tener maximo 255 caracteres. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_PASSWORD_NUMERO_IDENTIFICACION_REQUERIDO` | VALIDATION_ERROR | BAJO | El número de identificación es obligatorio para validar la clave. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El numero de identificacion es obligatorio para validar la clave. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_PASSWORD_POLITICA_INVALIDA` | VALIDATION_ERROR | BAJO | La clave debe tener mínimo 8 caracteres, con mayúscula, minúscula, número y carácter especial. | Backend (VALIDATION_ERROR, UsuarioErrorCode): La clave debe tener minimo 8 caracteres, con mayuscula, minuscula, numero y caracter especial. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_PASSWORD_REQUERIDO` | VALIDATION_ERROR | BAJO | La clave es obligatoria. | Backend (VALIDATION_ERROR, UsuarioErrorCode): La clave es obligatoria. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_PERSONA_YA_REGISTRADA` | BUSINESS_ERROR | MEDIO | Ya existe una persona con ese documento o correo. Use "Vincular docente existente". | Backend (CONFLICT, DocenteErrorCode): Ya existe una persona con ese documento o correo. Use "Vincular docente existente". | `63_val_mensajes_err_pendientes.sql` |
| `ERR_PLAZO_JUSTIFICACION_VENCIDO` | BUSINESS_ERROR | MEDIO | El plazo para justificar esta inasistencia ya venció. | Backend (CONFLICT, AsistenciaErrorCode): El plazo para justificar esta inasistencia ya vencio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_PRESENTE_REQUERIDO` | VALIDATION_ERROR | BAJO | Debe indicar si el estudiante asistió. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): Debe indicar si el estudiante asistio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_PRIMER_APELLIDO_REQUERIDO` | VALIDATION_ERROR | BAJO | El primer apellido es obligatorio. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El primer apellido es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_PRIMER_NOMBRE_REQUERIDO` | VALIDATION_ERROR | BAJO | El primer nombre es obligatorio. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El primer nombre es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_PROGRAMA_FACULTAD_INCONSISTENTE` | BUSINESS_ERROR | CRITICO | El programa académico indicado no pertenece a la facultad especificada. | Programa {} no pertenece a la Facultad {} indicada en uv_programa.idFacultad. | `04_mensaje.sql` |
| `ERR_PROGRAMA_GRUPO_NO_ENCONTRADO` | BUSINESS_ERROR | ALTO | No se encontro un programa academico asociado a este grupo. | Error: Trazabilidad rota para Grupo ID {}. | `04_mensaje.sql` |
| `ERR_PROGRAMA_INVALIDO` | VALIDATION_ERROR | BAJO | El identificador del programa no es válido. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El identificador del programa no es valido. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_RANGO_FECHAS_SESION_INVALIDO` | VALIDATION_ERROR | BAJO | El rango de fechas de la sesión no es válido. | Backend (VALIDATION_ERROR, SesionErrorCode): El rango de fechas de la sesion no es valido. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_RECLAMO_ASISTENCIA_NO_JUSTIFICABLE` | BUSINESS_ERROR | MEDIO | La asistencia del reclamo no es una inasistencia justificable. | Backend (CONFLICT, AsistenciaErrorCode): La asistencia del reclamo no es una inasistencia justificable. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_RECLAMO_NO_EXISTE` | BUSINESS_ERROR | MEDIO | El reclamo indicado no existe. | Backend (RESOURCE_NOT_FOUND, AsistenciaErrorCode): El reclamo indicado no existe. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_RECLAMO_SIN_DETALLE_ASISTENCIA` | BUSINESS_ERROR | MEDIO | El reclamo no tiene un registro de asistencia que se pueda justificar. | Backend (CONFLICT, AsistenciaErrorCode): El reclamo no tiene un registro de asistencia que se pueda justificar. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_RECLAMO_TOMA_DUPLICADO` | BUSINESS_ERROR | MEDIO | Ya existe un reclamo para esta toma. | Backend (CONFLICT, AsistenciaErrorCode): Ya existe un reclamo para esta toma. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_RECLAMO_YA_RESUELTO` | BUSINESS_ERROR | MEDIO | El reclamo ya fue resuelto con una decisión distinta. | Backend (CONFLICT, AsistenciaErrorCode): El reclamo ya fue resuelto con una decision distinta. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_REGISTROS_ASISTENCIA_REQUERIDOS` | VALIDATION_ERROR | BAJO | Los registros de asistencia son obligatorios. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): Los registros de asistencia son obligatorios. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_RESPUESTA_RECLAMO_LONGITUD_INVALIDA` | BUSINESS_ERROR | MEDIO | Al rechazar, la respuesta es obligatoria ({} a {} caracteres); al aprobar es opcional (máx. {}). | Regla DEC-073: respuestaDocente fuera de RECLAMO/RESPUESTA_RECHAZO_LONGITUD_MINIMA ({}) .. RESPUESTA_LONGITUD_MAXIMA ({}). | `64_dec073_validaciones.sql` |
| `ERR_RESULTADO_APROBACION_INVALIDO` | VALIDATION_ERROR | BAJO | El resultado de la aprobación debe ser PRESENTE o JUSTIFICADA. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): El resultado de la aprobacion debe ser PRESENTE o JUSTIFICADA. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_SESION_ASISTENCIA_REQUERIDA` | VALIDATION_ERROR | BAJO | La sesión de asistencia es obligatoria. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): La sesion de asistencia es obligatoria. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_SESION_CANCELADA` | BUSINESS_ERROR | MEDIO | La sesión fue cancelada; no admite registro de asistencia. | Backend (CONFLICT, AsistenciaErrorCode): La sesion fue cancelada; no admite registro de asistencia. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_SESION_CERRADA` | BUSINESS_ERROR | MEDIO | La sesión ya finalizó; la asistencia solo puede modificarse mediante un reclamo. | Backend (CONFLICT, AsistenciaErrorCode): La sesion ya finalizo; la asistencia solo puede modificarse mediante un reclamo. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_SESION_HORARIO_INDETERMINADO` | BUSINESS_ERROR | MEDIO | El horario de la sesión no está confirmado; no es posible registrar asistencia. | Backend (CONFLICT, AsistenciaErrorCode): El horario de la sesion no esta confirmado; no es posible registrar asistencia. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_SESION_NO_EXISTE` | BUSINESS_ERROR | MEDIO | La sesion de clase no existe o no esta abierta. | Error: No se encontro una sesion activa para el ID especificado: {}. | `04_mensaje.sql` |
| `ERR_SESION_NO_INICIADA` | BUSINESS_ERROR | MEDIO | La sesión aún no ha iniciado; la asistencia solo se registra durante la sesión. | Backend (CONFLICT, AsistenciaErrorCode): La sesion aun no ha iniciado; la asistencia solo se registra durante la sesion. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_SESION_REQUERIDA` | VALIDATION_ERROR | BAJO | La sesión es obligatoria. | Backend (VALIDATION_ERROR, SesionErrorCode): La sesion es obligatoria. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_SOLICITUD_REVISION_REQUERIDA` | VALIDATION_ERROR | BAJO | La solicitud de revisión es obligatoria. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): La solicitud de revision es obligatoria. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_SOPORTE_OBLIGATORIO_CATEGORIA` | VALIDATION_ERROR | BAJO | La categoría seleccionada exige adjuntar al menos un soporte. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): La categoria seleccionada exige adjuntar al menos un soporte. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_SOPORTE_RECLAMO_DUPLICADO` | VALIDATION_ERROR | BAJO | Un mismo soporte no se puede adjuntar dos veces. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): Un mismo soporte no se puede adjuntar dos veces. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_SOPORTE_RECLAMO_INVALIDO` | VALIDATION_ERROR | BAJO | La lista de soportes contiene un identificador no válido. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): La lista de soportes contiene un identificador no valido. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_TIPO_IDENTIFICACION_CODIGO_LONGITUD_INVALIDA` | VALIDATION_ERROR | BAJO | El código del tipo de identificación puede tener máximo 5 caracteres. | Backend (VALIDATION_ERROR, TipoIdentificacionErrorCode): El codigo del tipo de identificacion puede tener maximo 5 caracteres. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_TIPO_IDENTIFICACION_CODIGO_REQUERIDO` | VALIDATION_ERROR | BAJO | El código del tipo de identificación es obligatorio. | Backend (VALIDATION_ERROR, TipoIdentificacionErrorCode): El codigo del tipo de identificacion es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_TIPO_IDENTIFICACION_INVALIDA` | VALIDATION_ERROR | BAJO | El tipo de identificación no es válido. | Backend (VALIDATION_ERROR, TipoIdentificacionErrorCode): El tipo de identificacion no es valido. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_TIPO_IDENTIFICACION_NO_EXISTE` | BUSINESS_ERROR | MEDIO | El tipo de identificación no existe. | Backend (RESOURCE_NOT_FOUND, TipoIdentificacionErrorCode): El tipo de identificacion no existe. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_TIPO_IDENTIFICACION_NOMBRE_LONGITUD_INVALIDA` | VALIDATION_ERROR | BAJO | El nombre del tipo de identificación puede tener máximo 50 caracteres. | Backend (VALIDATION_ERROR, TipoIdentificacionErrorCode): El nombre del tipo de identificacion puede tener maximo 50 caracteres. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_TIPO_IDENTIFICACION_NOMBRE_REQUERIDO` | VALIDATION_ERROR | BAJO | El nombre del tipo de identificación es obligatorio. | Backend (VALIDATION_ERROR, TipoIdentificacionErrorCode): El nombre del tipo de identificacion es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_TIPO_IDENTIFICACION_REQUERIDA` | VALIDATION_ERROR | BAJO | El tipo de identificación es obligatorio. | Backend (VALIDATION_ERROR, TipoIdentificacionErrorCode): El tipo de identificacion es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_TIPO_VINCULACION_INVALIDO` | VALIDATION_ERROR | BAJO | El tipo de vinculación indicado no existe o está inactivo. | Backend (VALIDATION_ERROR, DocenteErrorCode): El tipo de vinculacion indicado no existe o esta inactivo. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_TOKEN_VERIFICACION_INVALIDO` | BUSINESS_ERROR | MEDIO | El codigo de verificacion de asistencia es incorrecto o ha expirado. | Fallo: Codigo de verificacion incorrecto o expirado para Sesion: {}. | `04_mensaje.sql` |
| `ERR_TOMA_NO_RECLAMABLE` | BUSINESS_ERROR | MEDIO | Solo puedes reclamar una toma en la que quedaste ausente. | Backend (CONFLICT, AsistenciaErrorCode): Solo puedes reclamar una toma en la que quedaste ausente. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_UNICIDAD_CORREO` | BUSINESS_ERROR | ALTO | El correo electronico ya se encuentra registrado. | Fallo unicidad: El correo [{}] ya existe en uv_usuario. | `04_mensaje.sql` |
| `ERR_UNICIDAD_DOCUMENTO` | BUSINESS_ERROR | ALTO | El numero de documento ya esta registrado para este tipo de identificacion. | Fallo unicidad: Duplicado en idTipoIdentificacion y numeroIdentificacion [{}]. | `04_mensaje.sql` |
| `ERR_USUARIO_DOCENTE_INVALIDO` | VALIDATION_ERROR | BAJO | El identificador del usuario asociado al docente no es válido. | Backend (VALIDATION_ERROR, DocenteErrorCode): El identificador del usuario asociado al docente no es valido. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_USUARIO_DOCENTE_REQUERIDO` | VALIDATION_ERROR | BAJO | El usuario del docente es obligatorio. | Backend (VALIDATION_ERROR, DocenteErrorCode): El usuario del docente es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_USUARIO_EJECUTOR_ASISTENCIA_REQUERIDO` | VALIDATION_ERROR | BAJO | El usuario autenticado que registra las asistencias es obligatorio. | Backend (VALIDATION_ERROR, AsistenciaErrorCode): El usuario autenticado que registra las asistencias es obligatorio. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_USUARIO_INACTIVO` | BUSINESS_ERROR | MEDIO | El usuario se encuentra inactivo. | Backend (CONFLICT, UsuarioErrorCode): El usuario se encuentra inactivo. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_USUARIO_INVALIDO` | VALIDATION_ERROR | BAJO | El identificador del usuario no es válido. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El identificador del usuario no es valido. | `63_val_mensajes_err_pendientes.sql` |
| `ERR_USUARIO_NO_EXISTE` | BUSINESS_ERROR | MEDIO | El usuario especificado no existe. | Error: No se encontro el ID de Usuario especificado: {}. | `04_mensaje.sql` |
| `ERR_USUARIO_REQUERIDO` | VALIDATION_ERROR | BAJO | El usuario es obligatorio. | Backend (VALIDATION_ERROR, UsuarioErrorCode): El usuario es obligatorio. | `63_val_mensajes_err_pendientes.sql` |

## EST

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `EST_001` | BUSINESS_ERROR | MEDIO | El estudiante especificado no existe en el sistema. | Error de búsqueda: No se encontró el estudiante especificado en uv_estudiante: {}. | `04_mensaje.sql` |
| `EST_002` | BUSINESS_ERROR | ALTO | El estudiante ya se encuentra matriculado o registrado en este grupo. | Registro duplicado: El estudiante {} ya se encuentra asociado al grupo {} en uv_estudiante_grupo. | `04_mensaje.sql` |
| `EST_003` | BUSINESS_ERROR | ALTO | El estudiante ya pertenece a este programa académico. | Registro duplicado: El estudiante {} ya está asociado al programa en uv_estudiante_programa. | `04_mensaje.sql` |
| `EST_004` | BUSINESS_ERROR | ALTO | El estudiante no pertenece al grupo de la sesion seleccionada. | Validación de pertenencia fallida: El estudiante {} no está inscrito en el grupo de la sesión {}. | `04_mensaje.sql` |
| `EST_005` | BUSINESS_ERROR | MEDIO | El grupo pertenece a varios programas: indica el programa. | Regla R7/S3: el grupo tiene varios programas y no se envio idPrograma. | `38_mensajes_asignatura_plan.sql` |
| `EST_006` | BUSINESS_ERROR | MEDIO | El programa indicado no corresponde a los programas del grupo. | Regla R7/S3: idPrograma no esta entre los programas del grupo. | `38_mensajes_asignatura_plan.sql` |

## FAC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `FAC_001` | BUSINESS_ERROR | MEDIO | La facultad especificada no existe en el sistema. | Error de búsqueda: No se encontró la facultad en uv_facultad: {}. | `04_mensaje.sql` |
| `FAC_002` | BUSINESS_ERROR | ALTO | El decano seleccionado ya es titular de otra facultad activa. | Regla de unicidad de titularidad: el decano {} ya es titular de otra facultad activa. | `04_mensaje.sql` |

## FES

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `FES_001` | VALIDATION_ERROR | BAJO | El año de festivos no es válido. | @anio [{}] fuera de FESTIVOS/ANIO_MINIMO..ANIO_MAXIMO. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_002` | VALIDATION_ERROR | MEDIO | El listado de festivos recibido no es válido. | @festivosJSON inválido: {}. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_003` | VALIDATION_ERROR | MEDIO | El listado de festivos no tiene una cantidad válida de días. | Total [{}] fuera de FESTIVOS/MINIMO_POR_ANIO..MAXIMO_POR_ANIO. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_004` | VALIDATION_ERROR | MEDIO | La fuente de festivos no es válida. | @fuente [{}] no está en FESTIVOS/FUENTES_VALIDAS. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_005` | SUCCESS | BAJO | Se cargaron {} días festivos de {}. | Carga [{}]: insertados {}, actualizados {}, desactivados {}. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_006` | VALIDATION_ERROR | BAJO | Indica el periodo académico o el año, no ambos. | @idPeriodoAcademico y @anio: exactamente uno. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_007` | BUSINESS_ERROR | BAJO | El periodo académico no existe. | Periodo [{}] inexistente. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_008` | SUCCESS | BAJO | Se cancelaron {} sesiones por festivo; {} sesiones con asistencia quedaron sin cambios. | Aplicación de festivos grupo/periodo [{}]. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_009` | BUSINESS_ERROR | MEDIO | Algunos grupos no se pudieron actualizar con los festivos. | {} grupos con error; ver log con la correlación. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `FES_010` | TECHNICAL_ERROR | ALTO | No fue posible obtener los festivos del año; se usó el cálculo local. | Proveedores [{}] fallaron; respaldo CALCULO_LOCAL. | `34_mensajes_sesion_cancelada_festivos.sql` |

## GEN

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `GEN_001` | BUSINESS_ERROR | MEDIO | El {} especificado no existe en el sistema. | Error de existencia: No se encontró el registro para la entidad [{}] con el identificador proporcionado. | `04_mensaje.sql` |
| `GEN_002` | BUSINESS_ERROR | MEDIO | El {} no puede estar vacío o no está presente. | Error de validación: El parámetro o campo [{}] es requerido y no contiene un valor válido. | `04_mensaje.sql` |
| `GEN_003` | BUSINESS_ERROR | ALTO | Ya existe un {} registrado con este {}. | Error de unicidad: Se detectó un registro duplicado para la entidad [{}] con la propiedad [{}]. | `04_mensaje.sql` |
| `GEN_004` | SUCCESS | BAJO | {} registrado(a) exitosamente. | Operación exitosa: Se completó la creación/registro de la entidad [{}] de manera correcta. | `04_mensaje.sql` |
| `GEN_005` | SUCCESS | BAJO | {} actualizado(a) exitosamente. | Operación exitosa: Se completó la actualización de la entidad [{}] de manera correcta. | `04_mensaje.sql` |

## GRUP

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `GRUP_001` | BUSINESS_ERROR | MEDIO | El grupo seleccionado no existe o no se encuentra habilitado. | Error de búsqueda: Grupo inexistente o deshabilitado en uv_grupo: {}. | `04_mensaje.sql` |
| `GRUP_002` | BUSINESS_ERROR | ALTO | El grupo ha alcanzado o superado la capacidad máxima de estudiantes permitida. | Límite alcanzado: Capacidad máxima superada para el grupo seleccionado: {}. | `04_mensaje.sql` |
| `GRUP_003` | BUSINESS_ERROR | ALTO | No se encontró un programa académico asociado a este grupo. | Inconsistencia de trazabilidad: Grupo {} sin programa académico vinculado. | `04_mensaje.sql` |

## HOR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `HOR_001` | BUSINESS_ERROR | ALTO | No es posible realizar el registro. Existe un cruce de horario con otra asignatura. | Colisión horaria: Se detectó una superposición de horario para el estudiante en la misma franja: {}. | `04_mensaje.sql` |
| `HOR_002` | BUSINESS_ERROR | ALTO | Existe un cruce de horario para el docente: ya tiene el grupo {} en la misma franja ({}). | Colisión horaria del docente con el grupo {} en la franja {}. GrupoID evaluado: {}. | `04_mensaje.sql` |
| `HOR_003` | BUSINESS_ERROR | MEDIO | Las franjas del horario del grupo no pueden cruzarse: {} se cruza con {}. | Franjas traslapadas en el horario del grupo: {} y {}. | `04_mensaje.sql` |
| `HOR_004` | BUSINESS_ERROR | MEDIO | El horario del grupo no es válido: {}. | Horario de grupo invalido: {}. | `04_mensaje.sql` |
| `HOR_005` | BUSINESS_ERROR | MEDIO | El grupo ya tiene un horario definido. Para cambiarlo, solicita la aprobación del coordinador. | El docente ejecutor intento reemplazar un horario ya definido del grupo. | `04_mensaje.sql` |

## IAM

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `IAM_001` | SYSTEM_ERROR | ALTO | El registro se guardó, pero la cuenta de acceso no pudo crearse en este momento. Intente de nuevo. | Aprovisionamiento IAM falló después del commit en DB (TD-015): reintentar crearCuenta de forma idempotente. | `17_mensaje_docente_programa.sql` |

## IDE

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `IDE_001` | BUSINESS_ERROR | MEDIO | El motivo de la corrección es obligatorio y no puede superar 500 caracteres. | Validacion: @motivo nulo, vacio o de mas de 500 caracteres. | `31_mensajes_correccion_identidad.sql` |
| `IDE_002` | SUCCESS | BAJO | Los datos de identidad fueron corregidos. | Actualizacion: dbo.Usuario (documento, nombres y apellidos) y registro en dbo.AuditoriaEvento. | `31_mensajes_correccion_identidad.sql` |
| `IDE_003` | BUSINESS_ERROR | MEDIO | La corrección del tipo o número de documento no está habilitada. | Regla de negocio: IDENTIDAD.PERMITIR_CORREGIR_DOCUMENTO distinto de 1; el documento no se modifica. | `31_mensajes_correccion_identidad.sql` |

## INST

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `INST_001` | BUSINESS_ERROR | CRITICO | El estudiante, programa y facultad deben pertenecer a la misma institución. | Inconsistencia institucional: Los identificadores de institución no coinciden entre la facultad, programa y estudiante: {}. | `04_mensaje.sql` |

## KPI

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `KPI_001` | BUSINESS_ERROR | ALTO | No tiene un programa académico a su cargo para consultar estos indicadores. | Ámbito: el ejecutor {} no coordina ningún programa en uv_programa. | `18_mensajes_kpis_coordinador.sql` |
| `KPI_002` | BUSINESS_ERROR | CRITICO | No fue posible calcular los indicadores porque falta la configuración de umbrales de asistencia. | Falta el parámetro ASISTENCIA/UMBRAL_ALERTA_ADVERTENCIA o ASISTENCIA/UMBRAL_ALERTA_PERDIDA en CatalogoParametro. | `18_mensajes_kpis_coordinador.sql` |
| `KPI_003` | BUSINESS_ERROR | ALTO | No tiene una facultad a su cargo para consultar estos indicadores. | Ámbito: el ejecutor {} no es decano de ninguna facultad en uv_facultad. | `19_mensajes_kpis_decano.sql` |
| `KPI_004` | BUSINESS_ERROR | ALTO | No tiene una institución a su cargo para consultar estos indicadores. | Ámbito: el ejecutor {} no es administrador de ninguna institución en uv_administrador. | `20_mensajes_kpis_admin.sql` |

## MQR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `MQR_001` | BUSINESS_ERROR | MEDIO | El código de matrícula no es válido o ya no está disponible. Solicítale al docente uno nuevo. | Token o PIN de matrícula inexistente, cerrado, expirado o fuera de la tolerancia de rotación. | `29_mensajes_matricula_qr.sql` |
| `MQR_002` | BUSINESS_ERROR | MEDIO | La matrícula por código solo está disponible desde la red Wi-Fi del campus UCO. | Regla: la IP del cliente no pertenece a asistencias:red:cidrs-campus. | `29_mensajes_matricula_qr.sql` |
| `MQR_003` | BUSINESS_ERROR | BAJO | Demasiados intentos. Espera un momento antes de volver a intentarlo. | Límite de intentos por IP o por token superado en la ventana de tiempo. | `29_mensajes_matricula_qr.sql` |
| `MQR_004` | BUSINESS_ERROR | BAJO | Ya estás matriculado en este grupo. | Regla: el estudiante ya tiene matrícula en el grupo. | `29_mensajes_matricula_qr.sql` |
| `MQR_005` | BUSINESS_ERROR | MEDIO | Ya tienes una cuenta registrada. Inicia sesión para completar tu matrícula. | Existencia: el documento o el correo ya pertenecen a un usuario registrado. | `29_mensajes_matricula_qr.sql` |
| `MQR_006` | BUSINESS_ERROR | BAJO | No fue posible generar un código único. Inténtalo de nuevo. | Unicidad: el PIN ya está en uso por el token vigente o anterior de otra ventana activa. | `29_mensajes_matricula_qr.sql` |
| `MQR_007` | BUSINESS_ERROR | MEDIO | Debes indicar el código QR o el PIN, pero no ambos. | Validación: debe indicarse exactamente uno entre tokenHash y pin. | `29_mensajes_matricula_qr.sql` |
| `MQR_008` | BUSINESS_ERROR | MEDIO | No se pudo determinar tu programa en este grupo. Pide a tu docente que te matricule. | Regla S3: el token no tiene programaPorDefecto y el grupo tiene varios programas. | `38_mensajes_asignatura_plan.sql` |

## NOF

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `NOF_APP_001` | BUSINESS_ERROR | MEDIO | El decano especificado no existe en el sistema. | Backend (RESOURCE_NOT_FOUND): El decano especificado no existe en el sistema. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_002` | BUSINESS_ERROR | MEDIO | La facultad indicada para crear decano no existe. | Backend (RESOURCE_NOT_FOUND): La facultad indicada para crear decano no existe. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_003` | BUSINESS_ERROR | MEDIO | El estudiante no existe en su ámbito. | Backend (RESOURCE_NOT_FOUND): El estudiante no existe en su ambito. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_004` | BUSINESS_ERROR | MEDIO | El docente no existe o no está vinculado a su programa. | Backend (RESOURCE_NOT_FOUND): El docente no existe o no esta vinculado a su programa. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_005` | BUSINESS_ERROR | MEDIO | El plan de estudio indicado no existe en el programa del coordinador. | Backend (RESOURCE_NOT_FOUND): El plan de estudio indicado no existe en el programa del coordinador. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_006` | BUSINESS_ERROR | MEDIO | El programa académico especificado no existe en el sistema. | Backend (RESOURCE_NOT_FOUND): El programa academico especificado no existe en el sistema. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_007` | BUSINESS_ERROR | MEDIO | El estudiante no existe en la facultad del decano. | Backend (RESOURCE_NOT_FOUND): El estudiante no existe en la facultad del decano. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_008` | BUSINESS_ERROR | MEDIO | La solicitud de revisión no existe. | Backend (RESOURCE_NOT_FOUND): La solicitud de revision no existe. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_009` | BUSINESS_ERROR | MEDIO | El estudiante especificado no se encuentra registrado. | Backend (RESOURCE_NOT_FOUND): El estudiante especificado no se encuentra registrado. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_010` | BUSINESS_ERROR | MEDIO | La cuenta indicada no existe. | Backend (RESOURCE_NOT_FOUND): La cuenta indicada no existe. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_011` | BUSINESS_ERROR | MEDIO | La matrícula por código no está disponible en este momento. | Backend (RESOURCE_NOT_FOUND): La matrícula por código no está disponible en este momento. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_012` | BUSINESS_ERROR | MEDIO | No se encontró el perfil del usuario autenticado. | Backend (RESOURCE_NOT_FOUND): No se encontro el perfil del usuario autenticado. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_013` | BUSINESS_ERROR | MEDIO | La facultad especificada no existe en el sistema. | Backend (RESOURCE_NOT_FOUND): La facultad especificada no existe en el sistema. | `62_val_mensajes_aplicacion.sql` |
| `NOF_APP_014` | BUSINESS_ERROR | MEDIO | El archivo solicitado no existe. | Backend (RESOURCE_NOT_FOUND): El archivo solicitado no existe. | `62_val_mensajes_aplicacion.sql` |

## NTF

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `NTF_001` | BUSINESS_ERROR | MEDIO | Los datos de la notificación no son válidos. | Datos de la notificación o parámetros de invocación no cumplen el contrato. | `04_mensaje.sql` |
| `NTF_002` | BUSINESS_ERROR | MEDIO | La notificación especificada no existe en el sistema. | Notificación no encontrada por identificador. | `04_mensaje.sql` |
| `NTF_003` | BUSINESS_ERROR | MEDIO | La notificación ya no está reservada por este proceso. | La notificación no está reservada por la instancia o la reserva ya venció. | `04_mensaje.sql` |
| `NTF_004` | BUSINESS_ERROR | MEDIO | La plantilla de notificación no contiene todos los marcadores obligatorios o incluye marcadores no permitidos para este tipo. | Validación de plantilla fallida: marcadores obligatorios ausentes o marcadores no permitidos para el tipo. | `04_mensaje.sql` |
| `NTF_005` | BUSINESS_ERROR | MEDIO | No existe la versión de plantilla solicitada para el tipo e idioma indicados. | No existe la versión de plantilla solicitada para el tipo e idioma indicados. | `04_mensaje.sql` |
| `NTF_006` | SUCCESS | BAJO | La plantilla de correo se actualizó y activó correctamente en una nueva versión. | La plantilla de correo se actualizó y activó correctamente en una nueva versión. | `04_mensaje.sql` |
| `NTF_007` | SUCCESS | BAJO | La notificación fallida fue reencolada exitosamente para un nuevo intento de envío. | La notificación fallida fue reencolada exitosamente para un nuevo intento de envío. | `04_mensaje.sql` |
| `NTF_008` | BUSINESS_ERROR | MEDIO | Solo se pueden reencolar notificaciones en estado fallido definitivo o reintentable. | Solo se pueden reencolar notificaciones en estado fallido definitivo o reintentable. | `04_mensaje.sql` |
| `NTF_009` | SUCCESS | BAJO | Correo de prueba encolado correctamente. | Correo de prueba encolado correctamente. | `04_mensaje.sql` |
| `NTF_020` | BUSINESS_ERROR | MEDIO | La notificación no existe. | Ambito: NotificacionSaliente no tiene una fila con el identificador recibido; sin escrituras. | `59_culm001_d9_mensajes.sql` |
| `NTF_021` | BUSINESS_ERROR | MEDIO | El tipo de plantilla no existe. | Regla: PlantillaNotificacion no tiene el tipo recibido; sin escrituras. | `59_culm001_d9_mensajes.sql` |

## PAG

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `PAG_001` | BUSINESS_ERROR | MEDIO | Los parámetros de paginación no son válidos. | Paginación inválida: numeroPagina={} y tamanoPagina={} fuera de rango (máximo según PAGINACION/TAMANO_MAXIMO). | `17_mensajes_programa_academico.sql` |

## PER

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `PER_001` | BUSINESS_ERROR | MEDIO | El período académico indicado no existe. | Existencia: no hay dbo.PeriodoAcademico con el id indicado en la institucion del ejecutor. | `17_mensajes_periodo_academico.sql` |
| `PER_002` | BUSINESS_ERROR | MEDIO | La fecha de inicio del período debe ser anterior a la fecha de fin. | Validacion: fechaInicio y fechaFin obligatorias y fechaInicio < fechaFin. | `17_mensajes_periodo_academico.sql` |
| `PER_003` | BUSINESS_ERROR | MEDIO | Ya existe un período académico con ese nombre en la institución. | Unicidad: ya existe dbo.PeriodoAcademico con el mismo id o nombre en la institucion. | `17_mensajes_periodo_academico.sql` |
| `PER_004` | BUSINESS_ERROR | MEDIO | El período académico tiene grupos o sesiones asociados y no se puede eliminar. | Regla: existe dbo.Grupo que referencia el periodo a eliminar. | `17_mensajes_periodo_academico.sql` |
| `PER_005` | BUSINESS_ERROR | MEDIO | No tiene una institución activa asignada como administrador para gestionar períodos académicos. | Ambito: el ejecutor no tiene dbo.Administrador en una institucion activa. | `17_mensajes_periodo_academico.sql` |
| `PER_006` | SUCCESS | BAJO | Período académico eliminado exitosamente. | Eliminacion: dbo.PeriodoAcademico eliminado. | `17_mensajes_periodo_academico.sql` |

## PLA

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `PLA_002` | BUSINESS_ERROR | MEDIO | El plan de estudios indicado no existe. | Existencia: no hay dbo.PlanEstudio con el id indicado. | `17_mensajes_plan_estudio.sql` |
| `PLA_003` | BUSINESS_ERROR | MEDIO | El plan de estudios ya tiene el número máximo de semestres. | Regla: no existe dbo.Semestre con numero MAX(numero del plan) + 1. | `17_mensajes_plan_estudio.sql` |
| `PLA_004` | BUSINESS_ERROR | MEDIO | El semestre indicado no pertenece al plan de estudios. | Existencia: no hay dbo.SemestrePlanEstudio del plan con el numero de semestre indicado. | `17_mensajes_plan_estudio.sql` |
| `PLA_005` | BUSINESS_ERROR | MEDIO | Solo se puede quitar el último semestre del plan de estudios. | Regla: el numero de semestre indicado no es el mayor del plan; la malla debe seguir consecutiva. | `17_mensajes_plan_estudio.sql` |
| `PLA_006` | BUSINESS_ERROR | MEDIO | El semestre tiene asignaturas asociadas. Reubíquelas o elimínelas primero. | Regla: existe dbo.Asignatura que referencia el dbo.SemestrePlanEstudio a quitar. | `17_mensajes_plan_estudio.sql` |

## PRM

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `PRM_001` | SUCCESS | BAJO | Parámetro actualizado. | CatalogoParametro actualizado y CambioParametro registrado. | `53_culm001_d3_mensajes.sql` |
| `PRM_002` | BUSINESS_ERROR | MEDIO | El parámetro no existe. | CatalogoParametro no tiene un parametro activo con ese id. | `53_culm001_d3_mensajes.sql` |
| `PRM_003` | BUSINESS_ERROR | MEDIO | Este parámetro no se puede editar. | Parametro en un grupo de PARAMETROS/GRUPOS_NO_EDITABLES o sin fila editable en CatalogoParametroEdicion. | `53_culm001_d3_mensajes.sql` |
| `PRM_004` | VALIDATION_ERROR | BAJO | El valor debe ser de tipo {}. | Valor invalido para tipoDato [{}] (no numerico, con decimales en un tipo entero, vacio o de mas de 4000 caracteres). | `53_culm001_d3_mensajes.sql` |
| `PRM_005` | VALIDATION_ERROR | BAJO | El valor debe estar entre {} y {}. | Valor fuera del rango [{}, {}] de CatalogoParametroEdicion. | `53_culm001_d3_mensajes.sql` |
| `PRM_006` | VALIDATION_ERROR | BAJO | El valor debe ser uno de: {}. | Valor fuera de valoresPermitidos [{}] (pertenencia exacta). | `53_culm001_d3_mensajes.sql` |
| `PRM_007` | VALIDATION_ERROR | BAJO | «{}» debe ser menor que «{}». | Regla cruzada estricta violada: [{}] debe ser menor que [{}]. | `53_culm001_d3_mensajes.sql` |
| `PRM_008` | BUSINESS_ERROR | MEDIO | Otro usuario modificó el parámetro. Recarga y vuelve a intentarlo. | fechaModificacionEsperada distinta de CatalogoParametro.fechaModificacion (concurrencia optimista). | `53_culm001_d3_mensajes.sql` |
| `PRM_009` | VALIDATION_ERROR | BAJO | Indica un motivo de al menos {} caracteres. | Motivo vacio o menor que PARAMETROS/LONGITUD_MINIMA_MOTIVO ({}) tras recortar. | `53_culm001_d3_mensajes.sql` |
| `PRM_010` | BUSINESS_ERROR | MEDIO | La edición de parámetros no está disponible con el catálogo de configuración activo. | El catalogo de parametros activo del backend no es sqlserver: la edicion en BD no es la fuente de verdad. | `53_culm001_d3_mensajes.sql` |
| `PRM_011` | SUCCESS | BAJO | El valor no cambió. | El valor propuesto es igual al almacenado; no se escribio nada. | `53_culm001_d3_mensajes.sql` |
| `PRM_012` | BUSINESS_ERROR | MEDIO | La edición de parámetros requiere una sola institución activa. | [SUPUESTO-D-16] La instalacion no tiene exactamente una Institucion activa; los parametros no tienen ambito por institucion. | `53_culm001_d3_mensajes.sql` |

## PROG

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `PROG_001` | BUSINESS_ERROR | ALTO | El programa académico especificado no existe en el sistema. | Error de búsqueda: No se encontró el programa en uv_programa: {}. | `04_mensaje.sql` |
| `PROG_002` | BUSINESS_ERROR | ALTO | Ya existe un programa académico con el identificador indicado. | Registro duplicado: ya existe un programa con el id {} en uv_programa. | `17_mensajes_programa_academico.sql` |
| `PROG_003` | BUSINESS_ERROR | ALTO | Ya existe un programa académico con ese nombre en la facultad. | Regla de unicidad: el nombre [{}] ya existe en la facultad (comparación sin distinguir mayúsculas). | `17_mensajes_programa_academico.sql` |
| `PROG_004` | BUSINESS_ERROR | MEDIO | El tipo de programa indicado no existe o está inactivo. | Error de búsqueda: tipo de programa {} inexistente o inactivo en uv_tipo_programa. | `17_mensajes_programa_academico.sql` |
| `PROG_005` | BUSINESS_ERROR | ALTO | El coordinador seleccionado no está disponible: no existe, está inactivo o ya tiene un programa asignado. | Regla 1 a 1: el coordinador {} no existe, está inactivo o ya figura en otro programa. | `17_mensajes_programa_academico.sql` |
| `PROG_006` | BUSINESS_ERROR | MEDIO | La modalidad o la jornada indicada no existe o está inactiva. | Error de búsqueda: modalidad/jornada {} inexistente o inactiva. | `17_mensajes_programa_academico.sql` |
| `PROG_007` | BUSINESS_ERROR | ALTO | No se puede desactivar el programa porque tiene grupos activos en el período vigente. | Regla D4: el programa {} tiene grupos habilitados en uv_grupo_programa. | `17_mensajes_programa_academico.sql` |
| `PROG_008` | BUSINESS_ERROR | ALTO | No se puede activar el programa porque su facultad está inactiva. | Regla de jerarquía: la facultad del programa {} está inactiva. | `17_mensajes_programa_academico.sql` |

## RC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `RC_001` | BUSINESS_ERROR | MEDIO | El estado de asistencia {} no corresponde a una razón de causa válida. | RazonCausa.codigo = [{}] no existe o no es válido para el contrato de asistencia. | `04_mensaje.sql` |

## RCN

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `RCN_001` | BUSINESS_ERROR | BAJO | La revisión de cancelación no existe. | Revisión [{}] inexistente o fuera del ámbito de [{}]. | `40_culm001_c_mensajes.sql` |
| `RCN_002` | VALIDATION_ERROR | BAJO | La decisión no es válida. | @codigoDecision/@codigoEstado [{}] no existe para este actor. | `40_culm001_c_mensajes.sql` |
| `RCN_003` | VALIDATION_ERROR | BAJO | El motivo debe tener entre {} y {} caracteres. | @motivo fuera de REVISION_CANCELACION/MOTIVO_LONGITUD_*. | `40_culm001_c_mensajes.sql` |
| `RCN_004` | BUSINESS_ERROR | MEDIO | La revisión está en estado «{}» y no admite esa decisión. | Sin transición para ({}, {}). | `40_culm001_c_mensajes.sql` |
| `RCN_005` | BUSINESS_ERROR | MEDIO | La matrícula del estudiante ya no está activa en el grupo. | EstudianteGrupo [{}] con estado [{}]. | `40_culm001_c_mensajes.sql` |
| `RCN_006` | BUSINESS_ERROR | MEDIO | El estudiante ya no supera el límite de inasistencia ({}% de {}%); no se puede proponer ni aprobar la cancelación. | Porcentaje [{}] < umbral [{}]. | `40_culm001_c_mensajes.sql` |
| `RCN_007` | SUCCESS | BAJO | Decisión registrada: el estudiante se mantiene en el grupo. | Revisión [{}] → MANTENIDA. | `40_culm001_c_mensajes.sql` |
| `RCN_008` | SUCCESS | BAJO | Se envió la propuesta de cancelación a la coordinación del programa. | Revisión [{}] → PROPUESTA (COORDINADOR). | `40_culm001_c_mensajes.sql` |
| `RCN_009` | SUCCESS | BAJO | Cancelación aprobada: el estudiante quedó cancelado por inasistencia. | Revisión [{}] → APROBADA; matrícula [{}] → CI. | `40_culm001_c_mensajes.sql` |
| `RCN_010` | SUCCESS | BAJO | Cancelación rechazada: el estudiante sigue activo en el grupo. | Revisión [{}] → RECHAZADA. | `40_culm001_c_mensajes.sql` |
| `RCN_011` | SUCCESS | BAJO | La decisión ya estaba registrada. | Revisión [{}] ya en [{}]; sin escrituras. | `40_culm001_c_mensajes.sql` |
| `RCN_012` | BUSINESS_ERROR | ALTO | Hay {} casos de pérdida por inasistencia pendientes de decisión del docente o de resolución en el periodo; resuélvelos antes del cierre. | Cierre de [{}] bloqueado: {} revisiones pendientes (incluye las de pérdida ya superada que esperan decisión), {} pérdidas sin revisión. | `40_culm001_c_mensajes.sql` |
| `RCN_013` | BUSINESS_ERROR | MEDIO | El programa no tiene coordinador activo para resolver la revisión; solicite su asignación al decano. | ufn_revision_cancelacion_resolutores vacío para [{}] (sin coordinador activo; DEC-065: no se escala al decano). | `40_culm001_c_mensajes.sql` |
| `RCN_014` | BUSINESS_ERROR | MEDIO | No puedes resolver una propuesta de cancelación que hiciste como docente. | Ejecutor [{}] = proponente de [{}]. | `40_culm001_c_mensajes.sql` |
| `RCN_015` | SUCCESS | BAJO | Mensaje en desuso (DEC-065): la propuesta ya no se envía a la decanatura; la decisión final es del coordinador. | En desuso (DEC-065): ya no se escala la revisión [{}] a DECANO. | `40_culm001_c_mensajes.sql` |
| `RCN_016` | BUSINESS_ERROR | MEDIO | La resolución de la revisión corresponde al coordinador del programa. | Regla DEC-065: el ejecutor [{}] es decano y no resuelve la revisión [{}]; solo el coordinador del programa; sin escrituras. | `40_culm001_c_mensajes.sql` |

## RET

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `RET_001` | BUSINESS_ERROR | MEDIO | El grupo indicado no existe o no es un grupo a su cargo. | Ambito: no existe dbo.Grupo con el id indicado cuyo Docente.usuario sea el ejecutor. | `21_mensajes_retiro_estudiante_grupo.sql` |
| `RET_002` | BUSINESS_ERROR | MEDIO | El estudiante no tiene una matrícula activa en este grupo. | Existencia: no hay dbo.EstudianteGrupo activo (estado A) para el estudiante en el grupo. | `21_mensajes_retiro_estudiante_grupo.sql` |
| `RET_003` | BUSINESS_ERROR | MEDIO | El período académico del grupo ya terminó; no se puede retirar al estudiante. | Regla: PeriodoAcademico.fechaFin es anterior a la fecha local (TIEMPO.ZONA_HORARIA_SQLSERVER). | `21_mensajes_retiro_estudiante_grupo.sql` |
| `RET_004` | BUSINESS_ERROR | MEDIO | El motivo del retiro es obligatorio y no puede superar 500 caracteres. | Validacion: @motivo nulo, vacio o de mas de 500 caracteres. | `21_mensajes_retiro_estudiante_grupo.sql` |
| `RET_005` | SUCCESS | BAJO | El estudiante fue retirado del grupo. | Actualizacion: dbo.EstudianteGrupo pasa a estado I (inactivo) y se registra dbo.AuditoriaEvento. | `21_mensajes_retiro_estudiante_grupo.sql` |

## REV

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `REV_001` | BUSINESS_ERROR | MEDIO | La acción sobre el reclamo no es válida; use APROBADA o RECHAZADA. | SES-04 resolución de reclamo: acción [{}] fuera del contrato (APROBADA \| RECHAZADA); sin escrituras. | `04_mensaje.sql` |
| `REV_002` | BUSINESS_ERROR | MEDIO | El reclamo ya fue resuelto con una decisión distinta. | SES-04 resolución de reclamo: la solicitud [{}] ya está resuelta con otra decisión; sin escrituras. | `04_mensaje.sql` |
| `REV_003` | BUSINESS_ERROR | MEDIO | La asistencia del reclamo no es una inasistencia justificable. | SES-04 resolución de reclamo: la solicitud [{}] apunta a una asistencia presente (AN / asistio = 1); sin escrituras. | `04_mensaje.sql` |
| `REV_004` | BUSINESS_ERROR | MEDIO | El reclamo no tiene un registro de asistencia que se pueda justificar. | SES-04 resolución de reclamo: la solicitud [{}] no tiene DetalleAsistencia; no se simula la justificación. | `04_mensaje.sql` |
| `REV_005` | BUSINESS_ERROR | MEDIO | El reclamo indicado no existe. | SES-04 resolución de reclamo: la solicitud [{}] no existe o no tiene asistencia, sesión y grupo válidos. | `04_mensaje.sql` |
| `REV_006` | BUSINESS_ERROR | MEDIO | La solicitud de revisión no existe. | Ambito: la solicitud de revision [{}] no existe o no es del estudiante ejecutor; sin escrituras. | `33_culm001_a_mensajes.sql` |
| `REV_007` | BUSINESS_ERROR | MEDIO | Solo se puede retirar una solicitud de revisión pendiente. | Regla: la solicitud de revision [{}] no esta en el estado de RECLAMO/ESTADO_PENDIENTE; sin escrituras. | `33_culm001_a_mensajes.sql` |
| `REV_008` | SUCCESS | BAJO | La solicitud de revisión fue retirada. | Actualizacion: la solicitud de revision [{}] paso al estado de RECLAMO/ESTADO_RETIRADO. | `33_culm001_a_mensajes.sql` |
| `REV_020` | BUSINESS_ERROR | MEDIO | El plazo para justificar esta inasistencia venció el {}. | HU026B: instante {} >= límite {} (ASISTENCIA/DIAS_LIMITE_JUSTIFICACION={}). | `51_culm001_d1_mensajes.sql` |
| `REV_021` | BUSINESS_ERROR | MEDIO | La categoría de justificación no es válida. | HU015: la categoría [{}] no existe en CategoriaJustificacion (ni por código ni por nombre). | `52_culm001_d2_parametros_mensajes.sql` |
| `REV_022` | BUSINESS_ERROR | MEDIO | La categoría «{}» exige adjuntar al menos un soporte. | HU014: la categoría [{}] tiene requiereSoporte = 1 y la solicitud llegó sin soportes. | `52_culm001_d2_parametros_mensajes.sql` |
| `REV_023` | BUSINESS_ERROR | MEDIO | Puedes adjuntar como máximo {} soportes. | HU015: [{}] soportes superan ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO = [{}]. | `52_culm001_d2_parametros_mensajes.sql` |
| `REV_024` | BUSINESS_ERROR | MEDIO | Un mismo soporte no se puede adjuntar dos veces. | HU015: la lista de soportes repite al menos un idArchivoSoporte. | `52_culm001_d2_parametros_mensajes.sql` |
| `REV_025` | TECHNICAL_ERROR | ALTO | No es posible validar el plazo de justificación en este momento. | HU026B: falta ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER. | `51_culm001_d1_mensajes.sql` |
| `REV_026` | BUSINESS_ERROR | MEDIO | Solo puedes reclamar una toma en la que quedaste ausente. | Regla: el estudiante no tiene SJC en la toma [{}] de la sesion [{}]; sin escrituras. | `61_puntos_control_mensajes.sql` |
| `REV_027` | BUSINESS_ERROR | MEDIO | Ya existe un reclamo para esta toma. | Regla: la toma [{}] ya tiene la solicitud de revision no retirada [{}]; sin escrituras. | `61_puntos_control_mensajes.sql` |
| `REV_028` | VALIDATION_ERROR | BAJO | El resultado de la aprobación debe ser PRESENTE o JUSTIFICADA. | Validacion: codigoResultadoAprobacion [{}] fuera de ASISTENCIA/CODIGO_RAZON_PRESENTE y ASISTENCIA/CODIGO_RAZON_EXCUSA; sin escrituras. | `61_puntos_control_mensajes.sql` |
| `REV_029` | BUSINESS_ERROR | MEDIO | La aprobación como presente solo aplica a reclamos de una toma. | Regla: la solicitud de revision [{}] es de la sesion completa (sin toma) y solo admite el resultado EX; sin escrituras. | `61_puntos_control_mensajes.sql` |

## SEC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `SEC_001` | BUSINESS_ERROR | ALTO | No tiene permisos suficientes para realizar esta operación. | RBAC denegado: el usuario no posee perfil activo requerido o no existe/está inactivo. | `04_mensaje.sql` |
| `SEC_002` | BUSINESS_ERROR | ALTO | No tiene autorización sobre el recurso solicitado. | Titularidad denegada: el usuario no está autorizado sobre el recurso solicitado. | `04_mensaje.sql` |

## SES

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `SES_001` | BUSINESS_ERROR | MEDIO | La sesión de clase especificada no existe o no se encuentra activa. | Error de búsqueda: Sesión no encontrada o cerrada en uv_sesion: {}. | `04_mensaje.sql` |
| `SES_002` | BUSINESS_ERROR | MEDIO | El código de verificación de asistencia es incorrecto o ha expirado. | Validación fallida: Token QR o código de verificación no coincide o venció para Sesión: {}. | `04_mensaje.sql` |
| `SES_003` | BUSINESS_ERROR | MEDIO | El cierre de sesión no está soportado por el contrato vigente de base de datos. | LEGACY_NOT_SUPPORTED: dbo.Sesion no posee columna de cierre/estado; usp_cerrar_sesion no persiste cierre real. | `04_mensaje.sql` |
| `SES_004` | BUSINESS_ERROR | MEDIO | La fecha y hora de fin de sesión debe ser posterior a la fecha y hora de inicio. | Validación temporal fallida: fechaHoraFin [{}] debe ser posterior a fechaHoraInicio [{}]. | `04_mensaje.sql` |
| `SES_005` | BUSINESS_ERROR | MEDIO | El horario institucional incluye una hora local inexistente por cambio de horario; no se generaron sesiones. | Validación temporal fallida: la zona [{}] no contiene la hora local [{}] (salto DST); generación abortada sin escrituras. | `04_mensaje.sql` |
| `SES_006` | BUSINESS_ERROR | ALTO | La sesión no coincide con el manifiesto de clasificación aprobado; no se modificó. | Clasificación UTC_OWNER rechazada: la sesión [{}] no coincide con el manifiesto [{}] (procedencia no NULL u horas distintas). | `04_mensaje.sql` |
| `SES_007` | BUSINESS_ERROR | MEDIO | La sesión de clase aún no ha iniciado; la asistencia solo se registra durante la sesión. | SES-01 ventana de registro: la sesión [{}] no ha iniciado (SYSUTCDATETIME() < fechaHoraInicio); lote rechazado sin escrituras. | `04_mensaje.sql` |
| `SES_008` | BUSINESS_ERROR | MEDIO | La sesión de clase ya finalizó; la asistencia solo puede modificarse mediante un reclamo. | SES-01 ventana de registro: la sesión [{}] está cerrada (SYSUTCDATETIME() >= fechaHoraFin); lote rechazado sin escrituras. | `04_mensaje.sql` |
| `SES_009` | BUSINESS_ERROR | MEDIO | El horario de la sesión no está confirmado; no es posible registrar asistencia. | SES-01 ventana de registro: la sesión [{}] tiene procedencia temporal INDETERMINADA (procedenciaTemporal NULL); lote rechazado sin escrituras. | `04_mensaje.sql` |
| `SES_010` | BUSINESS_ERROR | MEDIO | La sesión fue cancelada; no admite registro de asistencia. | Sesión [{}] cancelada (SesionCancelacion existe); operación rechazada sin escrituras. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_011` | BUSINESS_ERROR | BAJO | La sesión ya estaba cancelada. | Sesión [{}] con SesionCancelacion previa; se conserva el motivo original. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_012` | BUSINESS_ERROR | MEDIO | No es posible cancelar una sesión que ya tiene asistencia registrada. | Sesión [{}] con Asistencia o TomaAsistencia; cancelación rechazada. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_013` | VALIDATION_ERROR | BAJO | El motivo de cancelación debe tener entre {} y {} caracteres. | Longitud de @motivo fuera de SESION/MOTIVO_CANCELACION_LONGITUD_*. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_014` | SUCCESS | BAJO | La sesión fue cancelada y se avisó a los estudiantes. | SesionCancelacion creada para [{}] tipo [{}]. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_016` | BUSINESS_ERROR | MEDIO | La sesión ya terminó y tiene asistencia registrada; no se puede cancelar. Las correcciones se hacen por reclamo. | Sesión [{}] con Asistencia o TomaAsistencia y SYSUTCDATETIME() >= fin + MARGEN_RETARDO_MINUTOS; cancelación rechazada. | `34_mensajes_sesion_cancelada_festivos.sql` |
| `SES_017` | BUSINESS_ERROR | MEDIO | La sesión se cruza con otra sesión del grupo o del docente en ese horario. | Regla: la sesion se cruza con la sesion [{}] del mismo grupo o de otro grupo del mismo docente (inicio < fin y fin > inicio); sin escrituras. | `33_culm001_a_mensajes.sql` |
| `SES_018` | BUSINESS_ERROR | MEDIO | Solo las sesiones creadas manualmente por el docente pueden ser canceladas por el coordinador. | Regla: la sesión [{}] no es manual (procedencia UTC_GENERADOR o UTC_OWNER); el coordinador no puede cancelarla; sin escrituras. | `60_sesiones_manuales_mensajes.sql` |
| `SES_019` | VALIDATION_ERROR | BAJO | El motivo de cancelación no es válido. | Validación: codigoMotivo [{}] ausente o fuera de MotivoCancelacionSesion activo; sin escrituras. | `60_sesiones_manuales_mensajes.sql` |
| `SES_020` | SUCCESS | BAJO | La sesión fue cancelada por la coordinación del programa. | Sesión [{}] cancelada por el coordinador; tipo [{}]. | `60_sesiones_manuales_mensajes.sql` |
| `SES_021` | VALIDATION_ERROR | BAJO | La observación no puede superar {} caracteres. | Validación: la observación recortada supera SESION/OBSERVACION_CANCELACION_COORDINADOR_MAXIMA ({}); sin escrituras. | `60_sesiones_manuales_mensajes.sql` |
| `SES_022` | SUCCESS | BAJO | La sesión extraordinaria quedó registrada como solicitud pendiente de aprobación del coordinador del programa. | Sesión [{}] creada por el docente con solicitud PENDIENTE de aprobación del coordinador. | `60_sesiones_manuales_mensajes.sql` |
| `SES_023` | BUSINESS_ERROR | MEDIO | La sesión está pendiente de aprobación del coordinador. | Regla: la sesión [{}] tiene una solicitud en espera (EstadoSolicitudSesion.esFinal = 0); no admite tomas ni asistencia; sin escrituras. | `60_sesiones_manuales_mensajes.sql` |
| `SES_024` | BUSINESS_ERROR | MEDIO | La solicitud ya fue resuelta. | Regla: la solicitud de la sesión [{}] ya está en un estado final (aprobada o rechazada); sin escrituras. | `60_sesiones_manuales_mensajes.sql` |
| `SES_025` | BUSINESS_ERROR | MEDIO | La sesión no tiene una solicitud de aprobación. | Regla: la sesión [{}] no tiene fila en SesionSolicitud (generada o anterior a DEC-065); sin escrituras. | `60_sesiones_manuales_mensajes.sql` |
| `SES_026` | SUCCESS | BAJO | La solicitud de sesión extraordinaria fue aprobada. | Solicitud de la sesión [{}] aprobada por el coordinador. | `60_sesiones_manuales_mensajes.sql` |
| `SES_027` | SUCCESS | BAJO | La solicitud de sesión extraordinaria fue rechazada y la sesión quedó cancelada. | Solicitud de la sesión [{}] rechazada por el coordinador; la sesión quedó cancelada (tipo manual). | `60_sesiones_manuales_mensajes.sql` |
| `SES_028` | BUSINESS_ERROR | MEDIO | La sesión debe terminar el mismo día en que empieza; no puede pasar de la medianoche. | Regla DEC-072: fechaHoraInicio y fechaHoraFin caen en dias distintos en la zona {}. | `64_dec073_validaciones.sql` |

## SUC

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `SUC_REGISTRO_ASISTENCIA` | SUCCESS | BAJO | Asistencia registrada de forma satisfactoria. | Sincronizacion de asistencia completa. Registrada para: {}. | `04_mensaje.sql` |
| `SUC_REGISTRO_DOCENTE_GRUPO` | SUCCESS | BAJO | Se ha registrado el docente en el grupo de forma satisfactoria. | Operacion exitosa completa. Orquestador finalizado para Docente en Grupo: {}. | `04_mensaje.sql` |
| `SUC_REGISTRO_ESTUDIANTE_GRUPO` | SUCCESS | BAJO | Se ha registrado el estudiante en el grupo de forma satisfactoria. | Operacion exitosa completa. Orquestador finalizado para Estudiante en Grupo: {}. | `04_mensaje.sql` |

## SYS

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `SYS_001` | SYSTEM_ERROR | CRITICO | Ocurrió un error inesperado al procesar la solicitud. | Excepción de sistema no controlada capturada en bloque CATCH: {}. | `04_mensaje.sql` |

## TOM

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `TOM_001` | BUSINESS_ERROR | BAJO | La toma de asistencia no existe. | Toma [{}] inexistente o de otra sesión. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_002` | VALIDATION_ERROR | BAJO | El modo de la toma no es válido. | @codigoModo [{}] no existe en ModoTomaAsistencia. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_003` | BUSINESS_ERROR | BAJO | Ya hay una toma abierta en esta sesión; ciérrala antes de abrir otra. | Sesión [{}] con toma abierta [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_004` | BUSINESS_ERROR | BAJO | La sesión ya tiene el máximo de {} tomas. | TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION alcanzado en [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_008` | SUCCESS | BAJO | Toma {} abierta. | TomaAsistencia [{}] abierta modo [{}]. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_009` | SUCCESS | BAJO | Toma cerrada. {} estudiantes quedaron como ausentes. | TomaAsistencia [{}] cerrada; ausentes marcados {}. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_010` | SUCCESS | BAJO | Asistencia de la toma guardada. | Lote de toma [{}] con {} registros. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_011` | SUCCESS | BAJO | La toma ya estaba cerrada. | TomaAsistencia [{}] ya cerrada; sin escrituras. | `35_mensajes_toma_asistencia_qr.sql` |
| `TOM_012` | BUSINESS_ERROR | MEDIO | La toma {} ya no se puede corregir porque se abrió la toma {}. Las correcciones se hacen por reclamo del estudiante. | Regla: la toma numero [{}] esta cerrada y ya se abrio la toma numero [{}]; solo se corrige por reclamo; sin escrituras. | `61_puntos_control_mensajes.sql` |

## TPR

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `TPR_001` | BUSINESS_ERROR | MEDIO | El tipo de programa especificado no existe en el sistema. | Error de búsqueda: No se encontró el tipo de programa en uv_tipo_programa: {}. | `04_mensaje.sql` |
| `TPR_002` | BUSINESS_ERROR | ALTO | Ya existe un tipo de programa con el mismo código o nombre. | Error de unicidad: código o nombre duplicado en tipo de programa. | `04_mensaje.sql` |

## USU

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `USU_001` | BUSINESS_ERROR | MEDIO | El usuario especificado no existe en el sistema. | Error de búsqueda: No se encontró el usuario con el ID especificado: {}. | `04_mensaje.sql` |
| `USU_002` | BUSINESS_ERROR | ALTO | El usuario especificado se encuentra inactivo en la plataforma. | Restricción de acceso: El usuario [{}] tiene estaActivo = 0. | `04_mensaje.sql` |

## VAL

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `VAL_001` | BUSINESS_ERROR | MEDIO | El número de identificación es obligatorio. | Validación de campo: numeroIdentificacion no está presente o es nulo. | `04_mensaje.sql` |
| `VAL_002` | BUSINESS_ERROR | MEDIO | El número de identificación debe tener entre {} y {} dígitos. | Validación de rango: numeroIdentificacion debe tener una longitud de entre {} y {} dígitos. | `04_mensaje.sql` |
| `VAL_003` | BUSINESS_ERROR | MEDIO | Los nombres y apellidos son obligatorios. | Validación de campo: nombres o apellidos vacíos o no proporcionados. | `04_mensaje.sql` |
| `VAL_004` | BUSINESS_ERROR | MEDIO | El campo {} contiene caracteres no permitidos. | Validación de formato: El valor enviado para [{}] contiene caracteres especiales no válidos. | `04_mensaje.sql` |
| `VAL_005` | BUSINESS_ERROR | MEDIO | El correo electrónico es obligatorio y debe tener un formato válido. | Validación de formato: La dirección de correo electrónico no cumple con la estructura estándar. | `04_mensaje.sql` |
| `VAL_006` | BUSINESS_ERROR | ALTO | La dirección de correo electrónico ya se encuentra registrada. | Fallo de unicidad: El correo electrónico ya existe en la vista uv_usuario. | `04_mensaje.sql` |
| `VAL_007` | BUSINESS_ERROR | ALTO | La contraseña no cumple con los requisitos mínimos de seguridad. | Validación de seguridad: La contraseña no satisface las políticas de complejidad establecidas. | `04_mensaje.sql` |
| `VAL_APP_001` | VALIDATION_ERROR | BAJO | Los datos de la facultad son obligatorios. | Backend (VALIDATION_ERROR): Los datos de la facultad son obligatorios. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_002` | VALIDATION_ERROR | BAJO | El identificador de la facultad es obligatorio. | Backend (VALIDATION_ERROR): El identificador de la facultad es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_003` | VALIDATION_ERROR | BAJO | Debe indicar al menos el nombre o el decano de la facultad. | Backend (VALIDATION_ERROR): Debe indicar al menos el nombre o el decano de la facultad. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_004` | VALIDATION_ERROR | BAJO | El nombre de la facultad debe tener entre 3 y 50 caracteres. | Backend (VALIDATION_ERROR): El nombre de la facultad debe tener entre 3 y 50 caracteres. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_005` | VALIDATION_ERROR | BAJO | Los datos para actualizar el parámetro no son válidos. | Backend (VALIDATION_ERROR): Los datos para actualizar el parametro no son validos. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_006` | VALIDATION_ERROR | BAJO | Los datos del cambio de estado del decano son obligatorios. | Backend (VALIDATION_ERROR): Los datos del cambio de estado del decano son obligatorios. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_007` | VALIDATION_ERROR | BAJO | El decano es obligatorio. | Backend (VALIDATION_ERROR): El decano es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_008` | VALIDATION_ERROR | BAJO | El usuario autenticado es obligatorio. | Backend (VALIDATION_ERROR): El usuario autenticado es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_009` | VALIDATION_ERROR | BAJO | El estado deseado de la facultad es obligatorio. | Backend (VALIDATION_ERROR): El estado deseado de la facultad es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_010` | VALIDATION_ERROR | BAJO | El parámetro es obligatorio. | Backend (VALIDATION_ERROR): El parametro es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_011` | VALIDATION_ERROR | BAJO | Los datos de la consulta son obligatorios. | Backend (VALIDATION_ERROR): Los datos de la consulta son obligatorios. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_012` | VALIDATION_ERROR | BAJO | La granularidad debe ser SEMANA o MES. | Backend (VALIDATION_ERROR): La granularidad debe ser SEMANA o MES. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_013` | VALIDATION_ERROR | BAJO | Indique una facultad existente o una facultad nueva, no ambas. | Backend (VALIDATION_ERROR): Indique una facultad existente o una facultad nueva, no ambas. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_014` | VALIDATION_ERROR | BAJO | El nombre de la facultad es obligatorio y debe tener entre 3 y 50 caracteres. | Backend (VALIDATION_ERROR): El nombre de la facultad es obligatorio y debe tener entre 3 y 50 caracteres. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_015` | VALIDATION_ERROR | BAJO | El decano titular de la facultad es obligatorio. | Backend (VALIDATION_ERROR): El decano titular de la facultad es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_016` | VALIDATION_ERROR | BAJO | El usuario ejecutor es obligatorio. | Backend (VALIDATION_ERROR): El usuario ejecutor es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_017` | VALIDATION_ERROR | BAJO | El período académico a modificar es obligatorio. | Backend (VALIDATION_ERROR): El periodo academico a modificar es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_018` | VALIDATION_ERROR | BAJO | El período académico a eliminar es obligatorio. | Backend (VALIDATION_ERROR): El periodo academico a eliminar es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_019` | VALIDATION_ERROR | BAJO | El nombre del período académico es obligatorio. | Backend (VALIDATION_ERROR): El nombre del periodo academico es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_020` | VALIDATION_ERROR | BAJO | La fecha de inicio del período debe ser anterior a la fecha de fin. | Backend (VALIDATION_ERROR): La fecha de inicio del periodo debe ser anterior a la fecha de fin. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_021` | VALIDATION_ERROR | BAJO | El archivo adjunto no puede estar vacío. | Backend (VALIDATION_ERROR): El archivo adjunto no puede estar vacio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_022` | VALIDATION_ERROR | BAJO | El archivo excede el tamaño máximo permitido ({}). | Backend (VALIDATION_ERROR): El archivo excede el tamano maximo permitido ({}). | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_023` | VALIDATION_ERROR | BAJO | Formato de archivo no permitido. Solo se aceptan archivos PDF, PNG o JPG. | Backend (VALIDATION_ERROR): Formato de archivo no permitido. Solo se aceptan archivos PDF, PNG o JPG. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_024` | VALIDATION_ERROR | BAJO | El Content-Type declarado no coincide con la extensión del archivo. | Backend (VALIDATION_ERROR): El Content-Type declarado no coincide con la extension del archivo. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_025` | VALIDATION_ERROR | BAJO | El contenido del archivo no coincide con su extensión declarada. | Backend (VALIDATION_ERROR): El contenido del archivo no coincide con su extension declarada. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_026` | VALIDATION_ERROR | BAJO | Nombre de archivo no válido. | Backend (VALIDATION_ERROR): Nombre de archivo no valido. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_027` | VALIDATION_ERROR | BAJO | El nombre del archivo excede la longitud máxima permitida (250 caracteres). | Backend (VALIDATION_ERROR): El nombre del archivo excede la longitud maxima permitida (250 caracteres). | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_028` | VALIDATION_ERROR | BAJO | El archivo fue rechazado: se detectó una firma de malware conocida. | Backend (VALIDATION_ERROR): El archivo fue rechazado: se detecto una firma de malware conocida. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_029` | VALIDATION_ERROR | BAJO | El estado de vínculo debe ser ACTIVO, SIN_Vínculo o TODOS. | Backend (VALIDATION_ERROR): El estado de vinculo debe ser ACTIVO, SIN_VINCULO o TODOS. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_030` | VALIDATION_ERROR | BAJO | El estudiante es obligatorio. | Backend (VALIDATION_ERROR): El estudiante es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_031` | VALIDATION_ERROR | BAJO | La fecha inicial debe ser anterior a la fecha final. | Backend (VALIDATION_ERROR): La fecha inicial debe ser anterior a la fecha final. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_032` | VALIDATION_ERROR | BAJO | El rango de fechas no puede superar {} días. | Backend (VALIDATION_ERROR): El rango de fechas no puede superar {} dias. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_033` | VALIDATION_ERROR | BAJO | El resultado debe ser SUCCESS o FAILURE. | Backend (VALIDATION_ERROR): El resultado debe ser SUCCESS o FAILURE. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_034` | VALIDATION_ERROR | BAJO | El filtro {} excede la longitud permitida. | Backend (VALIDATION_ERROR): El filtro {} excede la longitud permitida. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_035` | VALIDATION_ERROR | BAJO | Los filtros de consulta son obligatorios. | Backend (VALIDATION_ERROR): Los filtros de consulta son obligatorios. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_036` | VALIDATION_ERROR | BAJO | El semáforo debe ser VERDE, AMBAR o ROJO. | Backend (VALIDATION_ERROR): El semaforo debe ser VERDE, AMBAR o ROJO. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_037` | VALIDATION_ERROR | BAJO | La fecha desde no puede ser posterior a la fecha hasta. | Backend (VALIDATION_ERROR): La fecha desde no puede ser posterior a la fecha hasta. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_038` | VALIDATION_ERROR | BAJO | La página debe ser mayor o igual a 1. | Backend (VALIDATION_ERROR): La pagina debe ser mayor o igual a 1. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_039` | VALIDATION_ERROR | BAJO | El tamaño de página debe estar entre 1 y {}. | Backend (VALIDATION_ERROR): El tamano de pagina debe estar entre 1 y {}. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_040` | VALIDATION_ERROR | BAJO | El número de semestre debe ser un entero positivo. | Backend (VALIDATION_ERROR): El numero de semestre debe ser un entero positivo. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_041` | VALIDATION_ERROR | BAJO | El número de página debe ser mayor o igual a 1. | Backend (VALIDATION_ERROR): El numero de pagina debe ser mayor o igual a 1. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_042` | VALIDATION_ERROR | BAJO | El tamaño de página debe ser mayor o igual a 1. | Backend (VALIDATION_ERROR): El tamano de pagina debe ser mayor o igual a 1. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_043` | VALIDATION_ERROR | BAJO | Los datos del programa son obligatorios. | Backend (VALIDATION_ERROR): Los datos del programa son obligatorios. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_044` | VALIDATION_ERROR | BAJO | La búsqueda excede la longitud permitida. | Backend (VALIDATION_ERROR): La busqueda excede la longitud permitida. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_045` | VALIDATION_ERROR | BAJO | El nombre del programa académico es obligatorio. | Backend (VALIDATION_ERROR): El nombre del programa academico es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_046` | VALIDATION_ERROR | BAJO | El nombre del programa académico no puede superar {} caracteres. | Backend (VALIDATION_ERROR): El nombre del programa academico no puede superar {} caracteres. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_047` | VALIDATION_ERROR | BAJO | Los parámetros de paginación deben ser mayores o iguales a 1. | Backend (VALIDATION_ERROR): Los parametros de paginacion deben ser mayores o iguales a 1. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_048` | VALIDATION_ERROR | BAJO | Indique un programa existente o un programa nuevo, no ambos. | Backend (VALIDATION_ERROR): Indique un programa existente o un programa nuevo, no ambos. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_049` | VALIDATION_ERROR | BAJO | El tipo del programa nuevo es obligatorio. | Backend (VALIDATION_ERROR): El tipo del programa nuevo es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_050` | VALIDATION_ERROR | BAJO | La contraseña inicial del coordinador es obligatoria. | Backend (VALIDATION_ERROR): La contrasena inicial del coordinador es obligatoria. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_051` | VALIDATION_ERROR | BAJO | La solicitud de revisión es obligatoria. | Backend (VALIDATION_ERROR): La solicitud de revision es obligatoria. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_052` | VALIDATION_ERROR | BAJO | El estado de la solicitud no es válido. | Backend (VALIDATION_ERROR): El estado de la solicitud no es valido. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_053` | VALIDATION_ERROR | BAJO | El grupo y el estudiante son obligatorios. | Backend (VALIDATION_ERROR): El grupo y el estudiante son obligatorios. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_054` | VALIDATION_ERROR | BAJO | El motivo del retiro es obligatorio y no puede superar 500 caracteres. | Backend (VALIDATION_ERROR): El motivo del retiro es obligatorio y no puede superar 500 caracteres. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_055` | VALIDATION_ERROR | BAJO | Los datos del retiro del reclamo son obligatorios. | Backend (VALIDATION_ERROR): Los datos del retiro del reclamo son obligatorios. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_056` | VALIDATION_ERROR | BAJO | El reclamo a retirar es obligatorio. | Backend (VALIDATION_ERROR): El reclamo a retirar es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_057` | VALIDATION_ERROR | BAJO | Los datos de la búsqueda son obligatorios. | Backend (VALIDATION_ERROR): Los datos de la busqueda son obligatorios. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_058` | VALIDATION_ERROR | BAJO | El grupo es obligatorio. | Backend (VALIDATION_ERROR): El grupo es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_059` | VALIDATION_ERROR | BAJO | El tipo de identificación es obligatorio. | Backend (VALIDATION_ERROR): El tipo de identificacion es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_060` | VALIDATION_ERROR | BAJO | El número de documento debe ser un entero positivo. | Backend (VALIDATION_ERROR): El numero de documento debe ser un entero positivo. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_061` | VALIDATION_ERROR | BAJO | El tipo de usuario a corregir no es válido. | Backend (VALIDATION_ERROR): El tipo de usuario a corregir no es valido. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_062` | VALIDATION_ERROR | BAJO | Los datos del registro son obligatorios. | Backend (VALIDATION_ERROR): Los datos del registro son obligatorios. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_063` | VALIDATION_ERROR | BAJO | El cuerpo de la petición es obligatorio. | Backend (VALIDATION_ERROR): El cuerpo de la peticion es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_064` | VALIDATION_ERROR | BAJO | El tipo de programa es obligatorio. | Backend (VALIDATION_ERROR): El tipo de programa es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_065` | VALIDATION_ERROR | BAJO | El coordinador del programa es obligatorio. | Backend (VALIDATION_ERROR): El coordinador del programa es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_066` | VALIDATION_ERROR | BAJO | El estado deseado del programa es obligatorio. | Backend (VALIDATION_ERROR): El estado deseado del programa es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_067` | VALIDATION_ERROR | BAJO | Cada franja del horario es obligatoria. | Backend (respuesta ERR_CAMPO_OBLIGATORIO): Cada franja del horario es obligatoria. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_068` | VALIDATION_ERROR | BAJO | El campo dias es obligatorio cuando se envía el horario. | Backend (respuesta ERR_CAMPO_OBLIGATORIO): El campo dias es obligatorio cuando se envia el horario. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_069` | VALIDATION_ERROR | BAJO | El campo {} es obligatorio. | Backend (respuesta ERR_CAMPO_OBLIGATORIO): El campo {} es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_070` | VALIDATION_ERROR | BAJO | El campo {} debe usar formato ISO local {}. | Backend (respuesta ERR_FECHA_HORA_INVALIDA): El campo {} debe usar formato ISO local {}. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_071` | VALIDATION_ERROR | BAJO | Los datos de la consulta no son válidos. | Backend (VALIDATION_ERROR): Los datos de la consulta no son validos. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_072` | VALIDATION_ERROR | BAJO | La sesión es obligatoria. | Backend (VALIDATION_ERROR): La sesion es obligatoria. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_073` | VALIDATION_ERROR | BAJO | El identificador del estudiante es obligatorio. | Backend (VALIDATION_ERROR): El identificador del estudiante es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_074` | VALIDATION_ERROR | BAJO | El identificador del docente es obligatorio. | Backend (VALIDATION_ERROR): El identificador del docente es obligatorio. | `62_val_mensajes_aplicacion.sql` |
| `VAL_APP_075` | VALIDATION_ERROR | BAJO | El identificador del programa es obligatorio. | Backend (VALIDATION_ERROR): El identificador del programa es obligatorio. | `62_val_mensajes_aplicacion.sql` |

## VCE

| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |
|---|---|---|---|---|---|
| `VCE_001` | BUSINESS_ERROR | MEDIO | El correo del estudiante debe ser institucional y terminar en {}. | Regla: el correo de un alta nueva no cumple REGISTRO/DOMINIO_CORREO_ESTUDIANTE ({}). | `27_mensajes_ident001.sql` |
| `VCE_002` | BUSINESS_ERROR | MEDIO | El enlace de verificación no es válido o ya venció. | Token de verificación inexistente, vencido, usado, revocado o de usuario inactivo. | `27_mensajes_ident001.sql` |
| `VCE_003` | BUSINESS_ERROR | BAJO | Debe esperar unos minutos antes de volver a enviar el enlace de verificación. | Regla: aún no transcurre VERIFICACION_CORREO/REENVIO_ESPERA_MINUTOS desde la última emisión. | `27_mensajes_ident001.sql` |
| `VCE_004` | BUSINESS_ERROR | MEDIO | El estudiante no pertenece a un grupo a su cargo. | Ámbito: el ejecutor no es titular del grupo ni coordinador de su programa, o el estudiante no pertenece al grupo. | `27_mensajes_ident001.sql` |
| `VCE_005` | BUSINESS_ERROR | BAJO | El correo de este estudiante ya fue verificado. | Estado: Usuario.correoConfirmado ya es 1. | `27_mensajes_ident001.sql` |
| `VCE_006` | SUCCESS | BAJO | Su correo fue verificado. Ya puede iniciar sesión. | Token consumido y Usuario.correoConfirmado = 1. | `27_mensajes_ident001.sql` |
| `VCE_007` | BUSINESS_ERROR | MEDIO | El usuario no existe o no está activo. | Existencia: no hay dbo.Usuario activo con el id indicado. | `27_mensajes_ident001.sql` |
| `VCE_008` | BUSINESS_ERROR | MEDIO | El correo debe ser institucional y terminar en {}. | Regla DEC-073: el correo de personal nuevo no cumple REGISTRO/DOMINIO_CORREO_ESTUDIANTE ({}). | `64_dec073_validaciones.sql` |

