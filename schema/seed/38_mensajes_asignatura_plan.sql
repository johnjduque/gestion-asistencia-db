USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (CONTRACT §2.8.1): mensajes de asignaturas por plan, matricula con programa y ambito de coordinacion.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('ASI_002', 'BUSINESS_ERROR', 'MEDIO', N'Ya existe una asignatura con ese código. Usa "Asociar asignatura existente" para agregarla a este plan.'),
    ('ASI_003', 'BUSINESS_ERROR', 'MEDIO', N'La asignatura ya está asociada a este plan de estudios.'),
    ('ASI_004', 'BUSINESS_ERROR', 'MEDIO', N'La asignatura no está asociada a este plan de estudios.'),
    ('ASI_005', 'BUSINESS_ERROR', 'ALTO',  N'No puedes quitar la asignatura de este plan: tiene grupos o estudiantes del programa en el periodo vigente o en periodos futuros.'),
    ('ASI_006', 'BUSINESS_ERROR', 'MEDIO', N'La asignatura es compartida con programas que no coordinas; solo puedes cambiar su semestre y su carácter en tu plan.'),
    ('ASI_007', 'BUSINESS_ERROR', 'MEDIO', N'El carácter de la asignatura no es válido.'),
    ('EST_005', 'BUSINESS_ERROR', 'MEDIO', N'El grupo pertenece a varios programas: indica el programa.'),
    ('EST_006', 'BUSINESS_ERROR', 'MEDIO', N'El programa indicado no corresponde a los programas del grupo.'),
    ('MQR_008', 'BUSINESS_ERROR', 'MEDIO', N'No se pudo determinar tu programa en este grupo. Pide a tu docente que te matricule.'),
    ('COO_002', 'BUSINESS_ERROR', 'MEDIO', N'Coordinas varios programas: selecciona el programa que quieres consultar.'),
    ('COO_003', 'BUSINESS_ERROR', 'ALTO',  N'El programa indicado no pertenece a tu coordinación.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('ASI_002', 'BUSINESS_ERROR', 'MEDIO', N'Regla: Asignatura.codigo es unico global (UX_Asignatura_codigo); use usp_asociar_asignatura_plan para vincular una existente.'),
    ('ASI_003', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la asignatura ya tiene un vinculo activo en el plan (mismo u otro semestre).'),
    ('ASI_004', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la asignatura no tiene vinculo activo con el plan indicado.'),
    ('ASI_005', 'BUSINESS_ERROR', 'ALTO',  N'Regla: hay grupos vigentes o futuros, o matriculas activas, cuyo unico programa comun es el del plan.'),
    ('ASI_006', 'BUSINESS_ERROR', 'MEDIO', N'Regla S2: el catalogo de una asignatura compartida solo lo cambia quien coordina todos sus programas con vinculo activo.'),
    ('ASI_007', 'BUSINESS_ERROR', 'MEDIO', N'Validacion: codigoCaracter no existe en CaracterAsignaturaPlan o esta inactivo.'),
    ('EST_005', 'BUSINESS_ERROR', 'MEDIO', N'Regla R7/S3: el grupo tiene varios programas y no se envio idPrograma.'),
    ('EST_006', 'BUSINESS_ERROR', 'MEDIO', N'Regla R7/S3: idPrograma no esta entre los programas del grupo.'),
    ('MQR_008', 'BUSINESS_ERROR', 'MEDIO', N'Regla S3: el token no tiene programaPorDefecto y el grupo tiene varios programas.'),
    ('COO_002', 'BUSINESS_ERROR', 'MEDIO', N'Regla S4: el coordinador tiene varios programas y no envio idPrograma.'),
    ('COO_003', 'BUSINESS_ERROR', 'ALTO',  N'Regla de ambito: idPrograma no esta entre los programas del coordinador.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
