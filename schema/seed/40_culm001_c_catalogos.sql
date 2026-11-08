USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 C.1 (CONTRACT §2.1, DEC-028): catalogos de alertas y revisiones de cancelacion por inasistencia. MERGE idempotente por id.
MERGE INTO [dbo].[TipoAlertaInasistencia] AS Target
USING (VALUES
    ('7C1E0C10-5E51-4C0A-9A01-000000000001', N'ADVERTENCIA', N'Riesgo de pérdida por inasistencia', 1, 'ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA', 'ALERTA_RIESGO_INASISTENCIA',  'ALR_010', 0),
    ('7C1E0C10-5E51-4C0A-9A01-000000000002', N'PERDIDA',     N'Pérdida por inasistencia',           2, 'ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA',     'ALERTA_PERDIDA_INASISTENCIA', 'ALR_011', 1)
) AS Source (id, codigo, nombre, nivel, grupoParametroUmbral, claveParametroUmbral, tipoPlantillaEstudiante, codigoMensajeUsuario, creaRevisionCancelacion)
ON (Target.id = Source.id)
WHEN MATCHED THEN UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.nivel = Source.nivel,
    Target.grupoParametroUmbral = Source.grupoParametroUmbral, Target.claveParametroUmbral = Source.claveParametroUmbral,
    Target.tipoPlantillaEstudiante = Source.tipoPlantillaEstudiante, Target.codigoMensajeUsuario = Source.codigoMensajeUsuario,
    Target.creaRevisionCancelacion = Source.creaRevisionCancelacion
WHEN NOT MATCHED THEN INSERT (id, codigo, nombre, nivel, grupoParametroUmbral, claveParametroUmbral, tipoPlantillaEstudiante, codigoMensajeUsuario, creaRevisionCancelacion)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.nivel, Source.grupoParametroUmbral, Source.claveParametroUmbral, Source.tipoPlantillaEstudiante, Source.codigoMensajeUsuario, Source.creaRevisionCancelacion);
GO

MERGE INTO [dbo].[EstadoAlertaInasistencia] AS Target
USING (VALUES
    ('7C1E0C20-5E51-4C0A-9A01-000000000001', N'VIGENTE',  N'Vigente',  1),
    ('7C1E0C20-5E51-4C0A-9A01-000000000002', N'SUPERADA', N'Superada', 0)
) AS Source (id, codigo, nombre, estaVigente)
ON (Target.id = Source.id)
WHEN MATCHED THEN UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.estaVigente = Source.estaVigente
WHEN NOT MATCHED THEN INSERT (id, codigo, nombre, estaVigente) VALUES (Source.id, Source.codigo, Source.nombre, Source.estaVigente);
GO

MERGE INTO [dbo].[EstadoRevisionCancelacion] AS Target
USING (VALUES
    ('7C1E0C30-5E51-4C0A-9A01-000000000001', N'PENDIENTE_DOCENTE', N'Pendiente de decisión del docente',   1, 1, 1, 0, 0, 0, 0),
    ('7C1E0C30-5E51-4C0A-9A01-000000000002', N'MANTENIDA',         N'Estudiante mantenido por el docente', 2, 0, 0, 0, 1, 0, 0),
    ('7C1E0C30-5E51-4C0A-9A01-000000000003', N'PROPUESTA',         N'Cancelación propuesta',               3, 0, 0, 1, 0, 0, 0),
    ('7C1E0C30-5E51-4C0A-9A01-000000000004', N'APROBADA',          N'Cancelación aprobada',                4, 0, 0, 0, 0, 1, 1),
    ('7C1E0C30-5E51-4C0A-9A01-000000000005', N'RECHAZADA',         N'Cancelación rechazada',               5, 0, 0, 0, 1, 0, 0)
) AS Source (id, codigo, nombre, orden, esInicial, requiereAccionDocente, requiereAccionResolutor, conservaMatricula, cancelaMatricula, esFinal)
ON (Target.id = Source.id)
WHEN MATCHED THEN UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.orden = Source.orden, Target.esInicial = Source.esInicial,
    Target.requiereAccionDocente = Source.requiereAccionDocente, Target.requiereAccionResolutor = Source.requiereAccionResolutor,
    Target.conservaMatricula = Source.conservaMatricula, Target.cancelaMatricula = Source.cancelaMatricula, Target.esFinal = Source.esFinal
WHEN NOT MATCHED THEN INSERT (id, codigo, nombre, orden, esInicial, requiereAccionDocente, requiereAccionResolutor, conservaMatricula, cancelaMatricula, esFinal)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.orden, Source.esInicial, Source.requiereAccionDocente, Source.requiereAccionResolutor, Source.conservaMatricula, Source.cancelaMatricula, Source.esFinal);
GO

MERGE INTO [dbo].[TransicionRevisionCancelacion] AS Target
USING (VALUES
    ('7C1E0C40-5E51-4C0A-9A01-000000000001', '7C1E0C30-5E51-4C0A-9A01-000000000001', N'MANTENER', 0, '7C1E0C30-5E51-4C0A-9A01-000000000002', 0, 0, 'RCN_007', NULL),
    ('7C1E0C40-5E51-4C0A-9A01-000000000002', '7C1E0C30-5E51-4C0A-9A01-000000000001', N'PROPONER', 0, '7C1E0C30-5E51-4C0A-9A01-000000000003', 1, 1, 'RCN_008', 'PROPUESTA_CANCELACION'),
    ('7C1E0C40-5E51-4C0A-9A01-000000000003', '7C1E0C30-5E51-4C0A-9A01-000000000002', N'PROPONER', 0, '7C1E0C30-5E51-4C0A-9A01-000000000003', 1, 1, 'RCN_008', 'PROPUESTA_CANCELACION'),
    ('7C1E0C40-5E51-4C0A-9A01-000000000004', '7C1E0C30-5E51-4C0A-9A01-000000000005', N'PROPONER', 0, '7C1E0C30-5E51-4C0A-9A01-000000000003', 1, 1, 'RCN_008', 'PROPUESTA_CANCELACION'),
    ('7C1E0C40-5E51-4C0A-9A01-000000000005', '7C1E0C30-5E51-4C0A-9A01-000000000003', N'APROBAR',  1, '7C1E0C30-5E51-4C0A-9A01-000000000004', 1, 0, 'RCN_009', 'CANCELACION_APROBADA'),
    ('7C1E0C40-5E51-4C0A-9A01-000000000006', '7C1E0C30-5E51-4C0A-9A01-000000000003', N'RECHAZAR', 1, '7C1E0C30-5E51-4C0A-9A01-000000000005', 0, 0, 'RCN_010', 'CANCELACION_RECHAZADA')
) AS Source (id, estadoOrigen, codigoDecision, esDecisionResolutor, estadoDestino, exigeUmbralPerdida, exigeResolutorDisponible, codigoMensajeExito, tipoPlantillaNotificacion)
ON (Target.id = Source.id)
WHEN MATCHED THEN UPDATE SET Target.estadoOrigen = Source.estadoOrigen, Target.codigoDecision = Source.codigoDecision, Target.esDecisionResolutor = Source.esDecisionResolutor,
    Target.estadoDestino = Source.estadoDestino, Target.exigeUmbralPerdida = Source.exigeUmbralPerdida, Target.exigeResolutorDisponible = Source.exigeResolutorDisponible,
    Target.codigoMensajeExito = Source.codigoMensajeExito, Target.tipoPlantillaNotificacion = Source.tipoPlantillaNotificacion
WHEN NOT MATCHED THEN INSERT (id, estadoOrigen, codigoDecision, esDecisionResolutor, estadoDestino, exigeUmbralPerdida, exigeResolutorDisponible, codigoMensajeExito, tipoPlantillaNotificacion)
    VALUES (Source.id, Source.estadoOrigen, Source.codigoDecision, Source.esDecisionResolutor, Source.estadoDestino, Source.exigeUmbralPerdida, Source.exigeResolutorDisponible, Source.codigoMensajeExito, Source.tipoPlantillaNotificacion);
GO
