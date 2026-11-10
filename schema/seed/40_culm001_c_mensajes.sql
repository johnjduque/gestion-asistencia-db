USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.7): mensajes de alertas de inasistencia (ALR_) y revision de cancelacion (RCN_). Idempotente (MERGE por codigo).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('ALR_001', 'SUCCESS',          'BAJO',  N'Las alertas de inasistencia están deshabilitadas.'),
    ('ALR_002', 'TECHNICAL_ERROR',  'CRITICO', N'No fue posible evaluar las alertas de inasistencia.'),
    ('ALR_003', 'SUCCESS',          'BAJO',  N'Evaluación de alertas completada.'),
    ('ALR_004', 'VALIDATION_ERROR', 'BAJO',  N'La lista de alertas no es válida.'),
    ('ALR_005', 'SUCCESS',          'BAJO',  N'Se marcaron {} alertas como leídas.'),
    ('ALR_006', 'VALIDATION_ERROR', 'BAJO',  N'La matrícula indicada no pertenece al grupo.'),
    ('ALR_007', 'SUCCESS',          'BAJO',  N'Actualización de resolutores completada.'),
    ('ALR_010', 'INFO',             'BAJO',  N'Llevas {}% de inasistencia en {}. Si llegas al {}% podrías perder la asignatura.'),
    ('ALR_011', 'INFO',             'MEDIO', N'Alcanzaste {}% de inasistencia en {} (límite {}%). Tu docente revisará tu caso.'),
    ('RCN_001', 'BUSINESS_ERROR',   'BAJO',  N'La revisión de cancelación no existe.'),
    ('RCN_002', 'VALIDATION_ERROR', 'BAJO',  N'La decisión no es válida.'),
    ('RCN_003', 'VALIDATION_ERROR', 'BAJO',  N'El motivo debe tener entre {} y {} caracteres.'),
    ('RCN_004', 'BUSINESS_ERROR',   'MEDIO', N'La revisión está en estado «{}» y no admite esa decisión.'),
    ('RCN_005', 'BUSINESS_ERROR',   'MEDIO', N'La matrícula del estudiante ya no está activa en el grupo.'),
    ('RCN_006', 'BUSINESS_ERROR',   'MEDIO', N'El estudiante ya no supera el límite de inasistencia ({}% de {}%); no se puede proponer ni aprobar la cancelación.'),
    ('RCN_007', 'SUCCESS',          'BAJO',  N'Decisión registrada: el estudiante se mantiene en el grupo.'),
    ('RCN_008', 'SUCCESS',          'BAJO',  N'Se envió la propuesta de cancelación a la coordinación del programa.'),
    ('RCN_009', 'SUCCESS',          'BAJO',  N'Cancelación aprobada: el estudiante quedó cancelado por inasistencia.'),
    ('RCN_010', 'SUCCESS',          'BAJO',  N'Cancelación rechazada: el estudiante sigue activo en el grupo.'),
    ('RCN_011', 'SUCCESS',          'BAJO',  N'La decisión ya estaba registrada.'),
    ('RCN_012', 'BUSINESS_ERROR',   'ALTO',  N'Hay {} casos de pérdida por inasistencia pendientes de decisión del docente o de resolución en el periodo; resuélvelos antes del cierre.'),
    ('RCN_013', 'BUSINESS_ERROR',   'MEDIO', N'El programa no tiene coordinador activo para resolver la revisión; solicite su asignación al decano.'),
    ('RCN_014', 'BUSINESS_ERROR',   'MEDIO', N'No puedes resolver una propuesta de cancelación que hiciste como docente.'),
    ('RCN_015', 'SUCCESS',          'BAJO',  N'Mensaje en desuso (DEC-065): la propuesta ya no se envía a la decanatura; la decisión final es del coordinador.'),
    ('RCN_016', 'BUSINESS_ERROR',   'MEDIO', N'La resolución de la revisión corresponde al coordinador del programa.')
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
    ('ALR_001', 'SUCCESS',          'BAJO',  N'ALERTA_INASISTENCIA/HABILITADA != true; grupo [{}] sin escrituras.'),
    ('ALR_002', 'TECHNICAL_ERROR',  'CRITICO', N'Umbral [{}] del tipo [{}] ausente o no numérico.'),
    ('ALR_003', 'SUCCESS',          'BAJO',  N'Grupo [{}]: {} nuevas, {} superadas o reactivadas; revisiones creadas en novedadesJSON.'),
    ('ALR_004', 'VALIDATION_ERROR', 'BAJO',  N'@alertasJSON vacío, inválido, con duplicados o con más de {}.'),
    ('ALR_005', 'SUCCESS',          'BAJO',  N'Lectura de alertas del estudiante [{}].'),
    ('ALR_006', 'VALIDATION_ERROR', 'BAJO',  N'EstudianteGrupo [{}] no es del grupo [{}].'),
    ('ALR_007', 'SUCCESS',          'BAJO',  N'{} reasignadas, {} escaladas, {} sin resolutor.'),
    ('ALR_010', 'INFO',             'BAJO',  N'Texto ADVERTENCIA.'),
    ('ALR_011', 'INFO',             'MEDIO', N'Texto PERDIDA.'),
    ('RCN_001', 'BUSINESS_ERROR',   'BAJO',  N'Revisión [{}] inexistente o fuera del ámbito de [{}].'),
    ('RCN_002', 'VALIDATION_ERROR', 'BAJO',  N'@codigoDecision/@codigoEstado [{}] no existe para este actor.'),
    ('RCN_003', 'VALIDATION_ERROR', 'BAJO',  N'@motivo fuera de REVISION_CANCELACION/MOTIVO_LONGITUD_*.'),
    ('RCN_004', 'BUSINESS_ERROR',   'MEDIO', N'Sin transición para ({}, {}).'),
    ('RCN_005', 'BUSINESS_ERROR',   'MEDIO', N'EstudianteGrupo [{}] con estado [{}].'),
    ('RCN_006', 'BUSINESS_ERROR',   'MEDIO', N'Porcentaje [{}] < umbral [{}].'),
    ('RCN_007', 'SUCCESS',          'BAJO',  N'Revisión [{}] → MANTENIDA.'),
    ('RCN_008', 'SUCCESS',          'BAJO',  N'Revisión [{}] → PROPUESTA (COORDINADOR).'),
    ('RCN_009', 'SUCCESS',          'BAJO',  N'Revisión [{}] → APROBADA; matrícula [{}] → CI.'),
    ('RCN_010', 'SUCCESS',          'BAJO',  N'Revisión [{}] → RECHAZADA.'),
    ('RCN_011', 'SUCCESS',          'BAJO',  N'Revisión [{}] ya en [{}]; sin escrituras.'),
    ('RCN_012', 'BUSINESS_ERROR',   'ALTO',  N'Cierre de [{}] bloqueado: {} revisiones pendientes (incluye las de pérdida ya superada que esperan decisión), {} pérdidas sin revisión.'),
    ('RCN_013', 'BUSINESS_ERROR',   'MEDIO', N'ufn_revision_cancelacion_resolutores vacío para [{}] (sin coordinador activo; DEC-065: no se escala al decano).'),
    ('RCN_014', 'BUSINESS_ERROR',   'MEDIO', N'Ejecutor [{}] = proponente de [{}].'),
    ('RCN_015', 'SUCCESS',          'BAJO',  N'En desuso (DEC-065): ya no se escala la revisión [{}] a DECANO.'),
    ('RCN_016', 'BUSINESS_ERROR',   'MEDIO', N'Regla DEC-065: el ejecutor [{}] es decano y no resuelve la revisión [{}]; solo el coordinador del programa; sin escrituras.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
