USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: Catálogo de Mensajes del sistema
MERGE INTO [dbo].[Mensaje] AS Target
USING (VALUES
    ('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'USUARIO', 'No se encontro un programa academico asociado a este grupo.'),
    ('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'TECNICO', 'Error: Trazabilidad rota para {entidad}'),
    ('ERR_INESPERADO_REGISTRO_ESTUDIANTE', 'USUARIO', 'Hubo un error inesperado al procesar el registro completo del estudiante.'),
    ('ERR_INESPERADO_REGISTRO_ESTUDIANTE', 'TECNICO', 'Error critico en orquestador [usp_registrar_estudiante_en_grupo_usuario_no_existente]: {entidad}'),
    ('ERR_CORRELACION_REQUERIDA', 'USUARIO', 'El codigo de correlacion es requerido.'),
    ('ERR_CORRELACION_REQUERIDA', 'TECNICO', 'Error: idCorrelacion no esta presente o es invalido.'),
    ('ERR_USUARIO_NO_EXISTE', 'USUARIO', 'El usuario especificado no existe.'),
    ('ERR_USUARIO_NO_EXISTE', 'TECNICO', 'Error: No se encontro el ID de Usuario especificado: {entidad}'),
    ('ERR_ESTUDIANTE_NO_EXISTE', 'USUARIO', 'El estudiante especificado no existe.'),
    ('ERR_ESTUDIANTE_NO_EXISTE', 'TECNICO', 'Error: No se encontro el ID de Estudiante especificado: {entidad}')
) AS Source (codigo, tipo, contenido)
ON (Target.codigo = Source.codigo AND Target.tipo = Source.tipo)
WHEN MATCHED THEN
    UPDATE SET Target.contenido = Source.contenido
WHEN NOT MATCHED THEN
    INSERT (codigo, tipo, contenido)
    VALUES (Source.codigo, Source.tipo, Source.contenido);
GO
