USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente Completo: Catálogo de Parámetros del Sistema
MERGE INTO [dbo].[Parametro] AS Target
USING (VALUES
    -- Parámetros Generales y de Sistema
    ('GENERAL', 'UUID_DEFECTO', '00000000-0000-0000-0000-000000000000', 'STRING', 'UUID comodín por defecto para representar valores nulos o no especificados', '00000000-0000-0000-0000-000000000000'),
    ('GENERAL', 'CADENA_VACIA', '', 'STRING', 'Valor de cadena vacia para inicializar buffers de texto', ''),
    ('GLOBAL_FUN_GEN', 'Rol_Usuario', 'analista', 'STRING', 'Corresponde al rol del usuario por defecto (administrador o analista)', 'analista'),
    ('GLOBAL_TEC_GEN', 'Año_Rango_Inicial', '2005', 'INT', 'Año inicial para rango de cálculo de métricas históricas', '2005'),
    ('GLOBAL_TEC_GEN', 'Rango_Semestre', '14', 'INT', 'Rango máximo de semestres a calcular en la línea de tiempo', '14'),

    -- Parámetros de Perfiles y Roles Institucionales
    ('PERFIL', 'CODIGO_ESTUDIANTE', 'ESTUDIANTE', 'STRING', 'Código único del perfil de Estudiante en la tabla Perfil', 'ESTUDIANTE'),
    ('PERFIL', 'CODIGO_DOCENTE', 'DOCENTE', 'STRING', 'Código único del perfil de Docente en la tabla Perfil', 'DOCENTE'),
    ('PERFIL', 'CODIGO_COORDINADOR', 'COORDINADOR', 'STRING', 'Código único del perfil de Coordinador de Programa', 'COORDINADOR'),
    ('PERFIL', 'CODIGO_DECANO', 'DECANO', 'STRING', 'Código único del perfil de Decano de Facultad', 'DECANO'),

    -- Parámetros de Grupos y Cupos
    ('GRUPO', 'CAPACIDAD_MAXIMA_DEFECTO', '40', 'INT', 'Capacidad máxima predeterminada de estudiantes inscritos por grupo', '40'),

    -- Parámetros de Control de Asistencia y Tolerancia
    ('ASISTENCIA', 'TOLERANCIA_MINUTOS', '15', 'INT', 'Minutos de tolerancia desde el inicio de clase para marcar asistencia A Tiempo', '15'),
    ('ASISTENCIA', 'MARGEN_RETARDO_MINUTOS', '30', 'INT', 'Minutos máximos permitidos para marcar llegada Tarde antes de inasistencia', '30'),
    ('ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION', '5', 'INT', 'Días hábiles máximos reglamentarios para radicar justificaciones de inasistencia', '5'),
    ('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA', '15', 'DECIMAL', 'Porcentaje de ausentismo acumulado para disparar alerta preventiva (15%)', '15'),
    ('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA', '20', 'DECIMAL', 'Porcentaje de ausentismo acumulado para pérdida automática por faltas (20%)', '20')
) AS Source (grupo, clave, valor, tipoDato, descripcion, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET 
        Target.valor = Source.valor, 
        Target.tipoDato = Source.tipoDato,
        Target.descripcion = Source.descripcion,
        Target.valorDefecto = Source.valorDefecto
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, descripcion, valorDefecto)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.descripcion, Source.valorDefecto);
GO
