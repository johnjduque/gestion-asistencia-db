USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente Completo: Catálogo de Mensajes y Códigos del Sistema
MERGE INTO [dbo].[Mensaje] AS Target
USING (VALUES
    -- 1. Errores de Validación de Identidad y Seguridad
    ('ERR_CORRELACION_REQUERIDA', 'USUARIO', '00001', 16, 400, 'El codigo de correlacion es requerido.', 'Error: idCorrelacion no esta presente o es invalido.', 'Validación de UUID de correlación obligatorio'),
    ('ERR_CORRELACION_REQUERIDA', 'TECNICO', '00001', 16, 400, 'El codigo de correlacion es requerido.', 'Error: idCorrelacion no esta presente o es invalido.', 'Validación de UUID de correlación obligatorio'),
    
    ('ERR_USUARIO_NO_EXISTE', 'USUARIO', '00002', 16, 404, 'El usuario especificado no existe.', 'Error: No se encontro el ID de Usuario especificado: {entidad}', 'Usuario no registrado en la BD'),
    ('ERR_USUARIO_NO_EXISTE', 'TECNICO', '00002', 16, 404, 'El usuario especificado no existe.', 'Error: No se encontro el ID de Usuario especificado: {entidad}', 'Usuario no registrado en la BD'),

    ('ERR_UNICIDAD_CORREO', 'USUARIO', '00003', 16, 409, 'El correo electronico ya se encuentra registrado.', 'Fallo unicidad: El correo [{entidad}] ya existe en uv_usuario.', 'Duplicidad de correo electrónico'),
    ('ERR_UNICIDAD_CORREO', 'TECNICO', '00003', 16, 409, 'El correo electronico ya se encuentra registrado.', 'Fallo unicidad: El correo [{entidad}] ya existe en uv_usuario.', 'Duplicidad de correo electrónico'),

    ('ERR_UNICIDAD_DOCUMENTO', 'USUARIO', '00004', 16, 409, 'El numero de documento ya esta registrado para este tipo de identificacion.', 'Fallo unicidad: Duplicado en idTipoIdentificacion y numeroIdentificacion [{entidad}].', 'Duplicidad de documento de identidad'),
    ('ERR_UNICIDAD_DOCUMENTO', 'TECNICO', '00004', 16, 409, 'El numero de documento ya esta registrado para este tipo de identificacion.', 'Fallo unicidad: Duplicado en idTipoIdentificacion y numeroIdentificacion [{entidad}].', 'Duplicidad de documento de identidad'),

    -- 2. Errores de Roles y Entidades Académicas
    ('ERR_ESTUDIANTE_NO_EXISTE', 'USUARIO', '00010', 16, 404, 'El estudiante especificado no existe.', 'Error: No se encontro el ID de Estudiante especificado: {entidad}', 'Estudiante no encontrado'),
    ('ERR_ESTUDIANTE_NO_EXISTE', 'TECNICO', '00010', 16, 404, 'El estudiante especificado no existe.', 'Error: No se encontro el ID de Estudiante especificado: {entidad}', 'Estudiante no encontrado'),

    ('ERR_DOCENTE_NO_EXISTE', 'USUARIO', '00011', 16, 404, 'El docente especificado no existe o esta inactivo.', 'Error: No se encontro el ID de Docente especificado: {entidad}', 'Docente no encontrado'),
    ('ERR_DOCENTE_NO_EXISTE', 'TECNICO', '00011', 16, 404, 'El docente especificado no existe o esta inactivo.', 'Error: No se encontro el ID de Docente especificado: {entidad}', 'Docente no encontrado'),

    ('ERR_GRUPO_NO_EXISTE', 'USUARIO', '00012', 16, 404, 'El grupo seleccionado no existe o no esta habilitado.', 'Error: No existe un grupo habilitado con el identificador: {entidad}', 'Grupo no existe o inactivo'),
    ('ERR_GRUPO_NO_EXISTE', 'TECNICO', '00012', 16, 404, 'El grupo seleccionado no existe o no esta habilitado.', 'Error: No existe un grupo habilitado con el identificador: {entidad}', 'Grupo no existe o inactivo'),

    ('ERR_SESION_NO_EXISTE', 'USUARIO', '00013', 16, 404, 'La sesion de clase no existe o no esta abierta.', 'Error: No se encontro una sesion activa para el ID especificado: {entidad}', 'Sesión de clase no válida'),
    ('ERR_SESION_NO_EXISTE', 'TECNICO', '00013', 16, 404, 'La sesion de clase no existe o no esta abierta.', 'Error: No se encontro una sesion activa para el ID especificado: {entidad}', 'Sesión de clase no válida'),

    -- 3. Errores de Negocio, Cupos y Horarios
    ('ERR_CUPO_SUPERADO', 'USUARIO', '00020', 16, 409, 'El grupo ha superado la capacidad maxima de estudiantes permitida.', 'Cupo lleno. Maximo de estudiantes alcanzado para Grupo: {entidad}', 'Cupo máximo de grupo superado'),
    ('ERR_CUPO_SUPERADO', 'TECNICO', '00020', 16, 409, 'El grupo ha superado la capacidad maxima de estudiantes permitida.', 'Cupo lleno. Maximo de estudiantes alcanzado para Grupo: {entidad}', 'Cupo máximo de grupo superado'),

    ('ERR_CRUCE_HORARIO_ESTUDIANTE', 'USUARIO', '00021', 16, 409, 'No es posible realizar el registro. Existe un cruce de horario con otra asignatura.', 'Cruce detectado en uv_horario para Estudiante con GrupoID: {entidad}', 'Colisión horaria del estudiante'),
    ('ERR_CRUCE_HORARIO_ESTUDIANTE', 'TECNICO', '00021', 16, 409, 'No es posible realizar el registro. Existe un cruce de horario con otra asignatura.', 'Cruce detectado en uv_horario para Estudiante con GrupoID: {entidad}', 'Colisión horaria del estudiante'),

    ('ERR_CRUCE_HORARIO_DOCENTE', 'USUARIO', '00022', 16, 409, 'Existe un cruce de horario para el docente en la misma franja horaria.', 'Cruce detectado en uv_horario para Docente con GrupoID: {entidad}', 'Colisión horaria del docente'),
    ('ERR_CRUCE_HORARIO_DOCENTE', 'TECNICO', '00022', 16, 409, 'Existe un cruce de horario para el docente en la misma franja horaria.', 'Cruce detectado en uv_horario para Docente con GrupoID: {entidad}', 'Colisión horaria del docente'),

    ('ERR_MATRICULA_DUPLICADA', 'USUARIO', '00023', 16, 409, 'Usted ya se encuentra registrado o matriculado en este grupo.', 'Registro duplicado detectado en uv_estudiante_grupo para Estudiante en Grupo: {entidad}', 'Estudiante ya inscrito en grupo'),
    ('ERR_MATRICULA_DUPLICADA', 'TECNICO', '00023', 16, 409, 'Usted ya se encuentra registrado o matriculado en este grupo.', 'Registro duplicado detectado en uv_estudiante_grupo para Estudiante en Grupo: {entidad}', 'Estudiante ya inscrito en grupo'),

    ('ERR_ESTUDIANTE_NO_PERTENECE_SESION', 'USUARIO', '00024', 16, 403, 'El estudiante no pertenece al grupo de la sesion seleccionada.', 'Validacion fallida: Estudiante no pertenece al grupo de la sesion: {entidad}', 'Marcaje no autorizado'),
    ('ERR_ESTUDIANTE_NO_PERTENECE_SESION', 'TECNICO', '00024', 16, 403, 'El estudiante no pertenece al grupo de la sesion seleccionada.', 'Validacion fallida: Estudiante no pertenece al grupo de la sesion: {entidad}', 'Marcaje no autorizado'),

    ('ERR_TOKEN_VERIFICACION_INVALIDO', 'USUARIO', '00025', 16, 400, 'El codigo de verificacion de asistencia es incorrecto o ha expirado.', 'Fallo: Codigo de verificacion incorrecto o expirado para Sesion: {entidad}', 'Token QR expirado o no coincide'),
    ('ERR_TOKEN_VERIFICACION_INVALIDO', 'TECNICO', '00025', 16, 400, 'El codigo de verificacion de asistencia es incorrecto o ha expirado.', 'Fallo: Codigo de verificacion incorrecto o expirado para Sesion: {entidad}', 'Token QR expirado o no coincide'),

    ('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'USUARIO', '00030', 16, 404, 'No se encontro un programa academico asociado a este grupo.', 'Error: Trazabilidad rota para Grupo ID {entidad}', 'Grupo sin programa académico asociado'),
    ('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'TECNICO', '00030', 16, 404, 'No se encontro un programa academico asociado a este grupo.', 'Error: Trazabilidad rota para Grupo ID {entidad}', 'Grupo sin programa académico asociado'),

    -- 4. Excepciones Inesperadas (CATCH / HTTP 500)
    ('ERR_INESPERADO_REGISTRO_ESTUDIANTE', 'USUARIO', '00090', 18, 500, 'Hubo un error inesperado al procesar el registro completo del estudiante.', 'Error critico en orquestador [usp_registrar_estudiante_en_grupo_usuario_no_existente]: {entidad}', 'Excepción general en registro de estudiante'),
    ('ERR_INESPERADO_REGISTRO_ESTUDIANTE', 'TECNICO', '00090', 18, 500, 'Hubo un error inesperado al procesar el registro completo del estudiante.', 'Error critico en orquestador [usp_registrar_estudiante_en_grupo_usuario_no_existente]: {entidad}', 'Excepción general en registro de estudiante'),

    ('ERR_INESPERADO_REGISTRO_DOCENTE', 'USUARIO', '00091', 18, 500, 'Hubo un error inesperado al procesar el registro completo del docente.', 'Error critico en orquestador [usp_registrar_docente_en_grupo_usuario_no_existente]: {entidad}', 'Excepción general en registro de docente'),
    ('ERR_INESPERADO_REGISTRO_DOCENTE', 'TECNICO', '00091', 18, 500, 'Hubo un error inesperado al procesar el registro completo del docente.', 'Error critico en orquestador [usp_registrar_docente_en_grupo_usuario_no_existente]: {entidad}', 'Excepción general en registro de docente'),

    ('ERR_INESPERADO_REGISTRO_ASISTENCIA', 'USUARIO', '00092', 18, 500, 'Hubo un error inesperado al registrar la asistencia del estudiante.', 'Error critico en orquestador [usp_registrar_asistencia_estudiante]: {entidad}', 'Excepción general en registro de asistencia'),
    ('ERR_INESPERADO_REGISTRO_ASISTENCIA', 'TECNICO', '00092', 18, 500, 'Hubo un error inesperado al registrar la asistencia del estudiante.', 'Error critico en orquestador [usp_registrar_asistencia_estudiante]: {entidad}', 'Excepción general en registro de asistencia'),

    -- 5. Mensajes de Éxito
    ('SUC_REGISTRO_ESTUDIANTE_GRUPO', 'USUARIO', '00100', 0, 200, 'Se ha registrado el estudiante en el grupo de forma satisfactoria.', 'Operacion exitosa completa. Orquestador finalizado para Estudiante en Grupo: {entidad}', 'Registro de estudiante en grupo exitoso'),
    ('SUC_REGISTRO_ESTUDIANTE_GRUPO', 'TECNICO', '00100', 0, 200, 'Se ha registrado el estudiante en el grupo de forma satisfactoria.', 'Operacion exitosa completa. Orquestador finalizado para Estudiante en Grupo: {entidad}', 'Registro de estudiante en grupo exitoso'),

    ('SUC_REGISTRO_DOCENTE_GRUPO', 'USUARIO', '00101', 0, 200, 'Se ha registrado el docente en el grupo de forma satisfactoria.', 'Operacion exitosa completa. Orquestador finalizado para Docente en Grupo: {entidad}', 'Registro de docente en grupo exitoso'),
    ('SUC_REGISTRO_DOCENTE_GRUPO', 'TECNICO', '00101', 0, 200, 'Se ha registrado el docente en el grupo de forma satisfactoria.', 'Operacion exitosa completa. Orquestador finalizado para Docente en Grupo: {entidad}', 'Registro de docente en grupo exitoso'),

    ('SUC_REGISTRO_ASISTENCIA', 'USUARIO', '00102', 0, 200, 'Asistencia registrada de forma satisfactoria.', 'Sincronizacion de asistencia completa. Registrada para: {entidad}', 'Toma de asistencia exitosa'),
    ('SUC_REGISTRO_ASISTENCIA', 'TECNICO', '00102', 0, 200, 'Asistencia registrada de forma satisfactoria.', 'Sincronizacion de asistencia completa. Registrada para: {entidad}', 'Toma de asistencia exitosa')

) AS Source (codigo, tipo, numero, severidad, estado, contenidoUsuario, contenidoTecnico, descripcion)
ON (Target.codigo = Source.codigo AND Target.tipo = Source.tipo)
WHEN MATCHED THEN
    UPDATE SET 
        Target.numero = Source.numero,
        Target.severidad = Source.severidad,
        Target.estado = Source.estado,
        Target.contenidoUsuario = Source.contenidoUsuario,
        Target.contenidoTecnico = Source.contenidoTecnico,
        Target.descripcion = Source.descripcion
WHEN NOT MATCHED THEN
    INSERT (codigo, tipo, numero, severidad, estado, contenidoUsuario, contenidoTecnico, descripcion)
    VALUES (Source.codigo, Source.tipo, Source.numero, Source.severidad, Source.estado, Source.contenidoUsuario, Source.contenidoTecnico, Source.descripcion);
GO
