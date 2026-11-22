USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente Completo: Catálogo de Mensajes de Usuario (CatalogoMensajeUsuario)
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    -- Correlación y Transacción
    ('CORR_001', 'BUSINESS_ERROR', 'ALTO', N'El identificador de correlación no está presente o está vacío.'),
    ('ERR_CORRELACION_REQUERIDA', 'BUSINESS_ERROR', 'ALTO', N'El código de correlación es requerido.'),

    -- Plantillas Generales Dinámicas ({})
    ('GEN_001', 'BUSINESS_ERROR', 'MEDIO', N'El {} especificado no existe en el sistema.'),
    ('GEN_002', 'BUSINESS_ERROR', 'MEDIO', N'El {} no puede estar vacío o no está presente.'),
    ('GEN_003', 'BUSINESS_ERROR', 'ALTO', N'Ya existe un {} registrado con este {}.'),
    ('GEN_004', 'SUCCESS', 'BAJO', N'{} registrado(a) exitosamente.'),
    ('GEN_005', 'SUCCESS', 'BAJO', N'{} actualizado(a) exitosamente.'),

    -- Validaciones Biográficas y Formato
    ('VAL_001', 'BUSINESS_ERROR', 'MEDIO', N'El número de identificación es obligatorio.'),
    ('VAL_002', 'BUSINESS_ERROR', 'MEDIO', N'El número de identificación debe tener entre {} y {} dígitos.'),
    ('VAL_003', 'BUSINESS_ERROR', 'MEDIO', N'Los nombres y apellidos son obligatorios.'),
    ('VAL_004', 'BUSINESS_ERROR', 'MEDIO', N'El campo {} contiene caracteres no permitidos.'),
    ('VAL_005', 'BUSINESS_ERROR', 'MEDIO', N'El correo electrónico es obligatorio y debe tener un formato válido.'),
    ('VAL_006', 'BUSINESS_ERROR', 'ALTO', N'La dirección de correo electrónico ya se encuentra registrada.'),
    ('VAL_007', 'BUSINESS_ERROR', 'ALTO', N'La contraseña no cumple con los requisitos mínimos de seguridad.'),

    -- Entidades del Sistema
    ('USU_001', 'BUSINESS_ERROR', 'MEDIO', N'El usuario especificado no existe en el sistema.'),
    ('ERR_USUARIO_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', N'El usuario especificado no existe.'),
    ('USU_002', 'BUSINESS_ERROR', 'ALTO', N'El usuario especificado se encuentra inactivo en la plataforma.'),
    ('ERR_UNICIDAD_CORREO', 'BUSINESS_ERROR', 'ALTO', N'El correo electronico ya se encuentra registrado.'),
    ('ERR_UNICIDAD_DOCUMENTO', 'BUSINESS_ERROR', 'ALTO', N'El número de documento ya está registrado para este tipo de identificación.'),

    ('EST_001', 'BUSINESS_ERROR', 'MEDIO', N'El estudiante especificado no existe en el sistema.'),
    ('ERR_ESTUDIANTE_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', N'El estudiante especificado no existe.'),
    ('EST_002', 'BUSINESS_ERROR', 'ALTO', N'El estudiante ya se encuentra matriculado o registrado en este grupo.'),
    ('ERR_MATRICULA_DUPLICADA', 'BUSINESS_ERROR', 'ALTO', N'Usted ya se encuentra registrado o matriculado en este grupo.'),
    ('EST_003', 'BUSINESS_ERROR', 'ALTO', N'El estudiante ya pertenece a este programa académico.'),
    ('EST_004', 'BUSINESS_ERROR', 'ALTO', N'El estudiante no pertenece al grupo de la sesión seleccionada.'),
    ('ERR_ESTUDIANTE_NO_PERTENECE_SESION', 'BUSINESS_ERROR', 'ALTO', N'El estudiante no pertenece al grupo de la sesión seleccionada.'),

    ('DOC_001', 'BUSINESS_ERROR', 'MEDIO', N'El docente especificado no existe o se encuentra inactivo.'),
    ('ERR_DOCENTE_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', N'El docente especificado no existe o está inactivo.'),
    ('ERR_DOCENTE_NO_TITULAR_GRUPO', 'BUSINESS_ERROR', 'ALTO', N'El docente indicado no es el titular del grupo seleccionado.'),

    ('PROG_001', 'BUSINESS_ERROR', 'ALTO', N'El programa académico especificado no existe en el sistema.'),
    ('FAC_001', 'BUSINESS_ERROR', 'MEDIO', N'La facultad especificada no existe en el sistema.'),
    ('TPR_001', 'BUSINESS_ERROR', 'MEDIO', N'El tipo de programa especificado no existe en el sistema.'),
    ('ARE_001', 'BUSINESS_ERROR', 'MEDIO', N'El área de conocimiento especificada no existe en el sistema.'),
    ('TPR_002', 'BUSINESS_ERROR', 'ALTO', N'Ya existe un tipo de programa con el mismo código o nombre.'),
    ('ARE_002', 'BUSINESS_ERROR', 'ALTO', N'Ya existe un área de conocimiento con el mismo código o nombre.'),
    ('DEC_001', 'BUSINESS_ERROR', 'MEDIO', N'El decano especificado no existe en el sistema.'),
    ('FAC_002', 'BUSINESS_ERROR', 'ALTO', N'El decano seleccionado ya es titular de otra facultad activa.'),
    ('COO_001', 'BUSINESS_ERROR', 'ALTO', N'No se puede desactivar al coordinador mientras tenga un programa activo a cargo. Reasigne o desactive el programa primero.'),
    ('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'BUSINESS_ERROR', 'ALTO', N'No se encontro un programa academico asociado a este grupo.'),

    ('GRUP_001', 'BUSINESS_ERROR', 'MEDIO', N'El grupo seleccionado no existe o no se encuentra habilitado.'),
    ('ERR_GRUPO_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', N'El grupo seleccionado no existe o no está habilitado.'),
    ('ERR_GRUPO_NO_HABILITADO', 'BUSINESS_ERROR', 'MEDIO', N'El grupo seleccionado no se encuentra habilitado para matrícula.'),
    ('GRUP_002', 'BUSINESS_ERROR', 'ALTO', N'El grupo ha alcanzado o superado la capacidad máxima de estudiantes permitida.'),
    ('ERR_CUPO_SUPERADO', 'BUSINESS_ERROR', 'ALTO', N'El grupo ha superado la capacidad maxima de estudiantes permitida.'),
    ('ERR_CAPACIDAD_GRUPO_INVALIDA', 'SYSTEM_ERROR', 'CRITICO', N'No fue posible determinar una capacidad máxima válida para el grupo.'),
    ('ERR_CUPO_INFERIOR_OCUPACION', 'BUSINESS_ERROR', 'ALTO', N'La capacidad del grupo no puede ser menor al número actual de estudiantes activos.'),
    ('GRUP_003', 'BUSINESS_ERROR', 'ALTO', N'No se encontró un programa académico asociado a este grupo.'),

    ('HOR_001', 'BUSINESS_ERROR', 'ALTO', N'No es posible realizar el registro. Existe un cruce de horario con otra asignatura.'),
    ('ERR_CRUCE_HORARIO_ESTUDIANTE', 'BUSINESS_ERROR', 'ALTO', N'No es posible realizar el registro. Existe un cruce de horario con otra asignatura.'),
    ('HOR_002', 'BUSINESS_ERROR', 'ALTO', N'Existe un cruce de horario para el docente: ya tiene el grupo {} en la misma franja ({}).'),
    ('ERR_CRUCE_HORARIO_DOCENTE', 'BUSINESS_ERROR', 'ALTO', N'Existe un cruce de horario para el docente en la misma franja horaria.'),
    ('HOR_003', 'BUSINESS_ERROR', 'MEDIO', N'Las franjas del horario del grupo no pueden cruzarse: {} se cruza con {}.'),
    ('HOR_004', 'BUSINESS_ERROR', 'MEDIO', N'El horario del grupo no es válido: {}.'),
    ('HOR_005', 'BUSINESS_ERROR', 'MEDIO', N'El grupo ya tiene un horario definido. Para cambiarlo, solicita la aprobación del coordinador.'),
    -- SES-GEN-01 (migracion 59)
    ('HOR_006', 'BUSINESS_ERROR', 'ALTO', N'Las horas semanales del horario ({} h) no coinciden con las de la materia ({} h). Ajusta las franjas para que sumen exactamente las horas de la materia.'),
    ('HOR_007', 'BUSINESS_ERROR', 'MEDIO', N'La franja {} debe durar entre {} y {} minutos.'),
    ('HOR_008', 'BUSINESS_ERROR', 'MEDIO', N'La franja {} debe estar dentro del horario permitido ({}).'),
    ('HOR_009', 'BUSINESS_ERROR', 'ALTO', N'El nuevo horario se cruza con otros grupos de {} estudiante(s) inscrito(s) en la franja {}.'),
    ('HOR_010', 'INFORMATIVO', 'BAJO', N'El horario programa {} h en el período y la materia espera {} h.'),
    ('HOR_011', 'INFORMATIVO', 'BAJO', N'{} h caen en días festivos ({} sesión(es)); esas sesiones quedan canceladas.'),
    ('HOR_012', 'INFORMATIVO', 'BAJO', N'{} h ya no se pueden programar porque el período ya inició; las sesiones se programan desde {}.'),
    ('HOR_013', 'INFORMATIVO', 'MEDIO', N'La materia aún no tiene horas semanales cargadas: no se valida el total del horario.'),
    ('HOR_014', 'INFORMATIVO', 'BAJO', N'Se conservan {} sesión(es) ya dictadas o con asistencia ({} h).'),
    ('ASI_013', 'BUSINESS_ERROR', 'MEDIO', N'Las horas semanales de la materia deben ser un entero entre 1 y {}.'),
    ('ASI_014', 'BUSINESS_ERROR', 'ALTO', N'La asignatura no tiene un vínculo activo con un plan activo de los programas que coordinas.'),
    ('PER_010', 'BUSINESS_ERROR', 'ALTO', N'El período académico {} no está vigente: ya terminó, está cerrado o no es de tu institución.'),
    ('PER_011', 'BUSINESS_ERROR', 'MEDIO', N'El período debe durar {} semanas: la fecha de fin debe ser {}.'),

    ('SES_001', 'BUSINESS_ERROR', 'MEDIO', N'La sesión de clase especificada no existe o no se encuentra activa.'),
    ('ERR_SESION_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', N'La sesión de clase no existe o no está abierta.'),
    ('SES_002', 'BUSINESS_ERROR', 'MEDIO', N'El código de verificación de asistencia es incorrecto o ha expirado.'),
    ('SES_003', 'BUSINESS_ERROR', 'MEDIO', N'El cierre de sesión no está soportado por el contrato vigente de base de datos.'),
    ('SES_004', 'BUSINESS_ERROR', 'MEDIO', N'La fecha y hora de fin de sesión debe ser posterior a la fecha y hora de inicio.'),
    ('SES_005', 'BUSINESS_ERROR', 'MEDIO', N'El horario institucional incluye una hora local inexistente por cambio de horario; no se generaron sesiones.'),
    ('SES_006', 'BUSINESS_ERROR', 'ALTO', N'La sesión no coincide con el manifiesto de clasificación aprobado; no se modificó.'),
    ('SES_007', 'BUSINESS_ERROR', 'MEDIO', N'La sesión de clase aún no ha iniciado; la asistencia solo se registra durante la sesión.'),
    ('SES_008', 'BUSINESS_ERROR', 'MEDIO', N'La sesión de clase ya finalizó; la asistencia solo puede modificarse mediante un reclamo.'),
    ('SES_009', 'BUSINESS_ERROR', 'MEDIO', N'El horario de la sesión no está confirmado; no es posible registrar asistencia.'),
    ('ERR_TOKEN_VERIFICACION_INVALIDO', 'BUSINESS_ERROR', 'MEDIO', N'El código de verificación de asistencia es incorrecto o ha expirado.'),

    ('INST_001', 'BUSINESS_ERROR', 'CRITICO', N'El estudiante, programa y facultad deben pertenecer a la misma institución.'),
    ('ERR_PROGRAMA_FACULTAD_INCONSISTENTE', 'BUSINESS_ERROR', 'CRITICO', N'El programa académico indicado no pertenece a la facultad especificada.'),

    -- Razón de causa / estado de asistencia (contrato AN, SJC, EX)
    ('RC_001', 'BUSINESS_ERROR', 'MEDIO', N'El estado de asistencia {} no corresponde a una razón de causa válida.'),
    ('ATT_001', 'BUSINESS_ERROR', 'MEDIO', N'El payload JSON de asistencia no cumple el contrato requerido.'),
    ('ATT_002', 'BUSINESS_ERROR', 'MEDIO', N'El lote de asistencia no puede estar vacío.'),
    ('ATT_003', 'BUSINESS_ERROR', 'MEDIO', N'El estudiante {} aparece más de una vez en el lote de asistencia.'),
    ('REV_001', 'BUSINESS_ERROR', 'MEDIO', N'La acción sobre el reclamo no es válida; use APROBADA o RECHAZADA.'),
    ('REV_002', 'BUSINESS_ERROR', 'MEDIO', N'El reclamo ya fue resuelto con una decisión distinta.'),
    ('REV_003', 'BUSINESS_ERROR', 'MEDIO', N'La asistencia del reclamo no es una inasistencia justificable.'),
    ('REV_004', 'BUSINESS_ERROR', 'MEDIO', N'El reclamo no tiene un registro de asistencia que se pueda justificar.'),
    ('REV_005', 'BUSINESS_ERROR', 'MEDIO', N'El reclamo indicado no existe.'),
    ('SEC_001', 'BUSINESS_ERROR', 'ALTO', N'No tiene permisos suficientes para realizar esta operación.'),
    ('SEC_002', 'BUSINESS_ERROR', 'ALTO', N'No tiene autorización sobre el recurso solicitado.'),

    -- Notificaciones (NOTIF-001 / NOTIF-002B)
    ('NTF_001', 'BUSINESS_ERROR', 'MEDIO', N'Los datos de la notificación no son válidos.'),
    ('NTF_002', 'BUSINESS_ERROR', 'MEDIO', N'La notificación especificada no existe en el sistema.'),
    ('NTF_003', 'BUSINESS_ERROR', 'MEDIO', N'La notificación ya no está reservada por este proceso.'),
    ('NTF_004', 'BUSINESS_ERROR', 'MEDIO', N'La plantilla de notificación no contiene todos los marcadores obligatorios o incluye marcadores no permitidos para este tipo.'),
    ('NTF_005', 'BUSINESS_ERROR', 'MEDIO', N'No existe la versión de plantilla solicitada para el tipo e idioma indicados.'),
    ('NTF_006', 'SUCCESS', 'BAJO', N'La plantilla de correo se actualizó y activó correctamente en una nueva versión.'),
    ('NTF_007', 'SUCCESS', 'BAJO', N'La notificación fallida fue reencolada exitosamente para un nuevo intento de envío.'),
    ('NTF_008', 'BUSINESS_ERROR', 'MEDIO', N'Solo se pueden reencolar notificaciones en estado fallido definitivo o reintentable.'),
    ('NTF_009', 'SUCCESS', 'BAJO', N'Correo de prueba encolado correctamente.'),

    -- Errores de Sistema
    ('SYS_001', 'SYSTEM_ERROR', 'CRITICO', N'Ocurrió un error inesperado al procesar la solicitud.'),
    ('ERR_INESPERADO_REGISTRO_ESTUDIANTE', 'SYSTEM_ERROR', 'CRITICO', N'Hubo un error inesperado al procesar el registro completo del estudiante.'),
    ('ERR_INESPERADO_REGISTRO_DOCENTE', 'SYSTEM_ERROR', 'CRITICO', N'Hubo un error inesperado al procesar el registro completo del docente.'),
    ('ERR_INESPERADO_REGISTRO_ASISTENCIA', 'SYSTEM_ERROR', 'CRITICO', N'Hubo un error inesperado al registrar la asistencia del estudiante.'),

    -- Éxitos
    ('SUC_REGISTRO_ESTUDIANTE_GRUPO', 'SUCCESS', 'BAJO', N'Se ha registrado el estudiante en el grupo de forma satisfactoria.'),
    ('SUC_REGISTRO_DOCENTE_GRUPO', 'SUCCESS', 'BAJO', N'Se ha registrado el docente en el grupo de forma satisfactoria.'),
    ('SUC_REGISTRO_ASISTENCIA', 'SUCCESS', 'BAJO', N'Asistencia registrada de forma satisfactoria.')

) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET 
        Target.tipoMensaje = Source.tipoMensaje,
        Target.severidad = Source.severidad,
        Target.contenido = Source.contenido,
        Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- Sembrado Idempotente Completo: Catálogo de Mensajes Técnicos (CatalogoMensajeTecnico)
MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    -- Correlación y Transacción
    ('CORR_001', 'BUSINESS_ERROR', 'CRITICO', N'Validación fallida: idCorrelacion no está presente o no es un UUID válido. Transacción no procesable.'),
    ('ERR_CORRELACION_REQUERIDA', 'BUSINESS_ERROR', 'CRITICO', N'Error: idCorrelacion no esta presente o es invalido.'),

    -- Plantillas Generales Dinámicas ({})
    ('GEN_001', 'BUSINESS_ERROR', 'MEDIO', N'Error de existencia: No se encontró el registro para la entidad [{}] con el identificador proporcionado.'),
    ('GEN_002', 'BUSINESS_ERROR', 'MEDIO', N'Error de validación: El parámetro o campo [{}] es requerido y no contiene un valor válido.'),
    ('GEN_003', 'BUSINESS_ERROR', 'ALTO', N'Error de unicidad: Se detectó un registro duplicado para la entidad [{}] con la propiedad [{}].'),
    ('GEN_004', 'SUCCESS', 'BAJO', N'Operación exitosa: Se completó la creación/registro de la entidad [{}] de manera correcta.'),
    ('GEN_005', 'SUCCESS', 'BAJO', N'Operación exitosa: Se completó la actualización de la entidad [{}] de manera correcta.'),

    -- Validaciones Biográficas y Formato
    ('VAL_001', 'BUSINESS_ERROR', 'MEDIO', N'Validación de campo: numeroIdentificacion no está presente o es nulo.'),
    ('VAL_002', 'BUSINESS_ERROR', 'MEDIO', N'Validación de rango: numeroIdentificacion debe tener una longitud de entre {} y {} dígitos.'),
    ('VAL_003', 'BUSINESS_ERROR', 'MEDIO', N'Validación de campo: nombres o apellidos vacíos o no proporcionados.'),
    ('VAL_004', 'BUSINESS_ERROR', 'MEDIO', N'Validación de formato: El valor enviado para [{}] contiene caracteres especiales no válidos.'),
    ('VAL_005', 'BUSINESS_ERROR', 'MEDIO', N'Validación de formato: La dirección de correo electrónico no cumple con la estructura estándar.'),
    ('VAL_006', 'BUSINESS_ERROR', 'ALTO', N'Fallo de unicidad: El correo electrónico ya existe en la vista uv_usuario.'),
    ('VAL_007', 'BUSINESS_ERROR', 'ALTO', N'Validación de seguridad: La contraseña no satisface las políticas de complejidad establecidas.'),

    -- Entidades del Sistema
    ('USU_001', 'BUSINESS_ERROR', 'MEDIO', N'Error de búsqueda: No se encontró el usuario con el ID especificado: {}.'),
    ('ERR_USUARIO_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', N'Error: No se encontro el ID de Usuario especificado: {}.'),
    ('USU_002', 'BUSINESS_ERROR', 'ALTO', N'Restricción de acceso: El usuario [{}] tiene estaActivo = 0.'),
    ('ERR_UNICIDAD_CORREO', 'BUSINESS_ERROR', 'ALTO', N'Fallo unicidad: El correo [{}] ya existe en uv_usuario.'),
    ('ERR_UNICIDAD_DOCUMENTO', 'BUSINESS_ERROR', 'ALTO', N'Fallo unicidad: Duplicado en idTipoIdentificacion y numeroIdentificacion [{}].'),

    ('EST_001', 'BUSINESS_ERROR', 'MEDIO', N'Error de búsqueda: No se encontró el estudiante especificado en uv_estudiante: {}.'),
    ('ERR_ESTUDIANTE_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', N'Error: No se encontro el ID de Estudiante especificado: {}.'),
    ('EST_002', 'BUSINESS_ERROR', 'ALTO', N'Registro duplicado: El estudiante {} ya se encuentra asociado al grupo {} en uv_estudiante_grupo.'),
    ('ERR_MATRICULA_DUPLICADA', 'BUSINESS_ERROR', 'ALTO', N'Registro duplicado detectado en uv_estudiante_grupo para Estudiante en Grupo: {}.'),
    ('EST_003', 'BUSINESS_ERROR', 'ALTO', N'Registro duplicado: El estudiante {} ya está asociado al programa en uv_estudiante_programa.'),
    ('EST_004', 'BUSINESS_ERROR', 'ALTO', N'Validación de pertenencia fallida: El estudiante {} no está inscrito en el grupo de la sesión {}.'),
    ('ERR_ESTUDIANTE_NO_PERTENECE_SESION', 'BUSINESS_ERROR', 'ALTO', N'Validacion fallida: Estudiante no pertenece al grupo de la sesion: {}.'),

    ('DOC_001', 'BUSINESS_ERROR', 'MEDIO', N'Error de búsqueda: Docente no encontrado o deshabilitado en uv_docente: {}.'),
    ('ERR_DOCENTE_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', N'Error: No se encontro el ID de Docente especificado: {}.'),
    ('ERR_DOCENTE_NO_TITULAR_GRUPO', 'BUSINESS_ERROR', 'ALTO', N'Docente {} no es titular del Grupo {} (uv_grupo.idDocente).'),

    ('PROG_001', 'BUSINESS_ERROR', 'ALTO', N'Error de búsqueda: No se encontró el programa en uv_programa: {}.'),
    ('FAC_001', 'BUSINESS_ERROR', 'MEDIO', N'Error de búsqueda: No se encontró la facultad en uv_facultad: {}.'),
    ('TPR_001', 'BUSINESS_ERROR', 'MEDIO', N'Error de búsqueda: No se encontró el tipo de programa en uv_tipo_programa: {}.'),
    ('ARE_001', 'BUSINESS_ERROR', 'MEDIO', N'Error de búsqueda: No se encontró el área de conocimiento en uv_area: {}.'),
    ('TPR_002', 'BUSINESS_ERROR', 'ALTO', N'Error de unicidad: código o nombre duplicado en tipo de programa.'),
    ('ARE_002', 'BUSINESS_ERROR', 'ALTO', N'Error de unicidad: código o nombre duplicado en área de conocimiento.'),
    ('DEC_001', 'BUSINESS_ERROR', 'MEDIO', N'Error de búsqueda: No se encontró el decano en uv_decano_identidad: {}.'),
    ('FAC_002', 'BUSINESS_ERROR', 'ALTO', N'Regla de unicidad de titularidad: el decano {} ya es titular de otra facultad activa.'),
    ('COO_001', 'BUSINESS_ERROR', 'ALTO', N'Regla de negocio: el coordinador {} coordina el programa activo {}.'),
    ('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'BUSINESS_ERROR', 'ALTO', N'Error: Trazabilidad rota para Grupo ID {}.'),

    ('GRUP_001', 'BUSINESS_ERROR', 'MEDIO', N'Error de búsqueda: Grupo inexistente o deshabilitado en uv_grupo: {}.'),
    ('ERR_GRUPO_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', N'Error: No existe un grupo habilitado con el identificador: {}.'),
    ('ERR_GRUPO_NO_HABILITADO', 'BUSINESS_ERROR', 'MEDIO', N'Grupo existente, pero fuera de ventana habilitada para matricula: {}.'),
    ('GRUP_002', 'BUSINESS_ERROR', 'ALTO', N'Límite alcanzado: Capacidad máxima superada para el grupo seleccionado: {}.'),
    ('ERR_CUPO_SUPERADO', 'BUSINESS_ERROR', 'ALTO', N'Cupo lleno. Maximo de estudiantes alcanzado para Grupo: {}.'),
    ('ERR_CAPACIDAD_GRUPO_INVALIDA', 'SYSTEM_ERROR', 'CRITICO', N'El parametro GRUPO/CAPACIDAD_MAXIMA_DEFECTO es nulo, cero o negativo: {}.'),
    ('ERR_CUPO_INFERIOR_OCUPACION', 'BUSINESS_ERROR', 'ALTO', N'Grupo {}: capacidad solicitada {} es menor a los estudiantes activos {}.'),
    ('GRUP_003', 'BUSINESS_ERROR', 'ALTO', N'Inconsistencia de trazabilidad: Grupo {} sin programa académico vinculado.'),

    ('HOR_001', 'BUSINESS_ERROR', 'ALTO', N'Colisión horaria: Se detectó una superposición de horario para el estudiante en la misma franja: {}.'),
    ('ERR_CRUCE_HORARIO_ESTUDIANTE', 'BUSINESS_ERROR', 'ALTO', N'Cruce detectado en uv_horario para Estudiante con GrupoID: {}.'),
    ('HOR_002', 'BUSINESS_ERROR', 'ALTO', N'Colisión horaria del docente con el grupo {} en la franja {}. GrupoID evaluado: {}.'),
    ('ERR_CRUCE_HORARIO_DOCENTE', 'BUSINESS_ERROR', 'ALTO', N'Cruce detectado en uv_horario para Docente con GrupoID: {}.'),
    ('HOR_003', 'BUSINESS_ERROR', 'MEDIO', N'Franjas traslapadas en el horario del grupo: {} y {}.'),
    ('HOR_004', 'BUSINESS_ERROR', 'MEDIO', N'Horario de grupo invalido: {}.'),
    ('HOR_005', 'BUSINESS_ERROR', 'MEDIO', N'El docente ejecutor intento reemplazar un horario ya definido del grupo.'),
    -- SES-GEN-01 (migracion 59)
    ('HOR_006', 'BUSINESS_ERROR', 'ALTO', N'Suma de minutos de las franjas distinta de horasSemanales*60 de la asignatura. Franjas: {} h; materia: {} h.'),
    ('HOR_007', 'BUSINESS_ERROR', 'MEDIO', N'Duracion de franja fuera de HORARIO/DURACION_MINIMA_MINUTOS..DURACION_MAXIMA_MINUTOS. Franja {}; minimo {}; maximo {}.'),
    ('HOR_008', 'BUSINESS_ERROR', 'MEDIO', N'Franja fuera de la ventana HORARIO/VENTANA_INICIO..VENTANA_FIN. Franja {}; ventana {}.'),
    ('HOR_009', 'BUSINESS_ERROR', 'ALTO', N'El horario nuevo cruza con otros grupos de estudiantes inscritos. Estudiantes: {}; franja {}.'),
    ('HOR_010', 'INFORMATIVO', 'BAJO', N'Total programado {} h frente a {} h esperadas de la materia.'),
    ('HOR_011', 'INFORMATIVO', 'BAJO', N'Horas perdidas por festivo: {} h en {} sesion(es).'),
    ('HOR_012', 'INFORMATIVO', 'BAJO', N'Horas no programables por inicio tardio: {} h; se programa desde {}.'),
    ('HOR_013', 'INFORMATIVO', 'MEDIO', N'Asignatura sin horasSemanales: B5 y B8 no se evaluan.'),
    ('HOR_014', 'INFORMATIVO', 'BAJO', N'Sesiones conservadas por estar dictadas o con asistencia: {}; horas: {}.'),
    ('ASI_013', 'BUSINESS_ERROR', 'MEDIO', N'horasSemanales invalida: debe ser entero entre 1 y {}.'),
    ('ASI_014', 'BUSINESS_ERROR', 'ALTO', N'Regla SES-GEN-01: sin vinculo activo a plan activo de los programas del coordinador (DEC-077 sustituye la exigencia de custodiar todos los programas).'),
    ('PER_010', 'BUSINESS_ERROR', 'ALTO', N'Periodo {} inexistente, de otra institucion, cerrado o terminado.'),
    ('PER_011', 'BUSINESS_ERROR', 'MEDIO', N'Duracion de periodo invalida: se exigen {} semanas; fecha de fin calculada {}.'),

    ('SES_001', 'BUSINESS_ERROR', 'MEDIO', N'Error de búsqueda: Sesión no encontrada o cerrada en uv_sesion: {}.'),
    ('ERR_SESION_NO_EXISTE', 'BUSINESS_ERROR', 'MEDIO', N'Error: No se encontro una sesion activa para el ID especificado: {}.'),
    ('SES_002', 'BUSINESS_ERROR', 'MEDIO', N'Validación fallida: Token QR o código de verificación no coincide o venció para Sesión: {}.'),
    ('SES_003', 'BUSINESS_ERROR', 'MEDIO', N'LEGACY_NOT_SUPPORTED: dbo.Sesion no posee columna de cierre/estado; usp_cerrar_sesion no persiste cierre real.'),
    ('SES_004', 'BUSINESS_ERROR', 'MEDIO', N'Validación temporal fallida: fechaHoraFin [{}] debe ser posterior a fechaHoraInicio [{}].'),
    ('SES_005', 'BUSINESS_ERROR', 'MEDIO', N'Validación temporal fallida: la zona [{}] no contiene la hora local [{}] (salto DST); generación abortada sin escrituras.'),
    ('SES_006', 'BUSINESS_ERROR', 'ALTO', N'Clasificación UTC_OWNER rechazada: la sesión [{}] no coincide con el manifiesto [{}] (procedencia no NULL u horas distintas).'),
    ('SES_007', 'BUSINESS_ERROR', 'MEDIO', N'SES-01 ventana de registro: la sesión [{}] no ha iniciado (SYSUTCDATETIME() < fechaHoraInicio); lote rechazado sin escrituras.'),
    ('SES_008', 'BUSINESS_ERROR', 'MEDIO', N'SES-01 ventana de registro: la sesión [{}] está cerrada (SYSUTCDATETIME() >= fechaHoraFin); lote rechazado sin escrituras.'),
    ('SES_009', 'BUSINESS_ERROR', 'MEDIO', N'SES-01 ventana de registro: la sesión [{}] tiene procedencia temporal INDETERMINADA (procedenciaTemporal NULL); lote rechazado sin escrituras.'),
    ('ERR_TOKEN_VERIFICACION_INVALIDO', 'BUSINESS_ERROR', 'MEDIO', N'Fallo: Codigo de verificacion incorrecto o expirado para Sesion: {}.'),

    ('INST_001', 'BUSINESS_ERROR', 'CRITICO', N'Inconsistencia institucional: Los identificadores de institución no coinciden entre la facultad, programa y estudiante: {}.'),
    ('ERR_PROGRAMA_FACULTAD_INCONSISTENTE', 'BUSINESS_ERROR', 'CRITICO', N'Programa {} no pertenece a la Facultad {} indicada en uv_programa.idFacultad.'),

    -- Razón de causa / estado de asistencia (contrato AN, SJC, EX)
    ('RC_001', 'BUSINESS_ERROR', 'MEDIO', N'RazonCausa.codigo = [{}] no existe o no es válido para el contrato de asistencia.'),
    ('ATT_001', 'BUSINESS_ERROR', 'MEDIO', N'Payload JSON inválido: se requiere un arreglo no nulo de objetos con exactamente idEstudiante y estado.'),
    ('ATT_002', 'BUSINESS_ERROR', 'MEDIO', N'Payload JSON válido pero vacío: no hay operación de negocio que ejecutar.'),
    ('ATT_003', 'BUSINESS_ERROR', 'MEDIO', N'Duplicidad en payload JSON: idEstudiante [{}] aparece más de una vez.'),
    ('REV_001', 'BUSINESS_ERROR', 'MEDIO', N'SES-04 resolución de reclamo: acción [{}] fuera del contrato (APROBADA | RECHAZADA); sin escrituras.'),
    ('REV_002', 'BUSINESS_ERROR', 'MEDIO', N'SES-04 resolución de reclamo: la solicitud [{}] ya está resuelta con otra decisión; sin escrituras.'),
    ('REV_003', 'BUSINESS_ERROR', 'MEDIO', N'SES-04 resolución de reclamo: la solicitud [{}] apunta a una asistencia presente (AN / asistio = 1); sin escrituras.'),
    ('REV_004', 'BUSINESS_ERROR', 'MEDIO', N'SES-04 resolución de reclamo: la solicitud [{}] no tiene DetalleAsistencia; no se simula la justificación.'),
    ('REV_005', 'BUSINESS_ERROR', 'MEDIO', N'SES-04 resolución de reclamo: la solicitud [{}] no existe o no tiene asistencia, sesión y grupo válidos.'),
    ('SEC_001', 'BUSINESS_ERROR', 'ALTO', N'RBAC denegado: el usuario no posee perfil activo requerido o no existe/está inactivo.'),
    ('SEC_002', 'BUSINESS_ERROR', 'ALTO', N'Titularidad denegada: el usuario no está autorizado sobre el recurso solicitado.'),

    -- Notificaciones (NOTIF-001 / NOTIF-002B)
    ('NTF_001', 'BUSINESS_ERROR', 'MEDIO', N'Datos de la notificación o parámetros de invocación no cumplen el contrato.'),
    ('NTF_002', 'BUSINESS_ERROR', 'MEDIO', N'Notificación no encontrada por identificador.'),
    ('NTF_003', 'BUSINESS_ERROR', 'MEDIO', N'La notificación no está reservada por la instancia o la reserva ya venció.'),
    ('NTF_004', 'BUSINESS_ERROR', 'MEDIO', N'Validación de plantilla fallida: marcadores obligatorios ausentes o marcadores no permitidos para el tipo.'),
    ('NTF_005', 'BUSINESS_ERROR', 'MEDIO', N'No existe la versión de plantilla solicitada para el tipo e idioma indicados.'),
    ('NTF_006', 'SUCCESS', 'BAJO', N'La plantilla de correo se actualizó y activó correctamente en una nueva versión.'),
    ('NTF_007', 'SUCCESS', 'BAJO', N'La notificación fallida fue reencolada exitosamente para un nuevo intento de envío.'),
    ('NTF_008', 'BUSINESS_ERROR', 'MEDIO', N'Solo se pueden reencolar notificaciones en estado fallido definitivo o reintentable.'),
    ('NTF_009', 'SUCCESS', 'BAJO', N'Correo de prueba encolado correctamente.'),

    -- Errores de Sistema
    ('SYS_001', 'SYSTEM_ERROR', 'CRITICO', N'Excepción de sistema no controlada capturada en bloque CATCH: {}.'),
    ('ERR_INESPERADO_REGISTRO_ESTUDIANTE', 'SYSTEM_ERROR', 'CRITICO', N'Error critico en orquestador [usp_registrar_estudiante_en_grupo_usuario_no_existente]: {}.'),
    ('ERR_INESPERADO_REGISTRO_DOCENTE', 'SYSTEM_ERROR', 'CRITICO', N'Error critico en orquestador [usp_registrar_docente_en_grupo_usuario_no_existente]: {}.'),
    ('ERR_INESPERADO_REGISTRO_ASISTENCIA', 'SYSTEM_ERROR', 'CRITICO', N'Error critico en orquestador [usp_registrar_asistencia_estudiante]: {}.'),

    -- Éxitos
    ('SUC_REGISTRO_ESTUDIANTE_GRUPO', 'SUCCESS', 'BAJO', N'Operacion exitosa completa. Orquestador finalizado para Estudiante en Grupo: {}.'),
    ('SUC_REGISTRO_DOCENTE_GRUPO', 'SUCCESS', 'BAJO', N'Operacion exitosa completa. Orquestador finalizado para Docente en Grupo: {}.'),
    ('SUC_REGISTRO_ASISTENCIA', 'SUCCESS', 'BAJO', N'Sincronizacion de asistencia completa. Registrada para: {}.')

) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET 
        Target.tipoMensaje = Source.tipoMensaje,
        Target.severidad = Source.severidad,
        Target.contenido = Source.contenido,
        Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
