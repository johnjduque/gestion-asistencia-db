USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEC-081 (2026-11-21): mensajes del receso academico del periodo. Idempotente (MERGE por codigo). Migracion 68.
--   REC_001 exito al crear (fecha, clases canceladas)      REC_002 exito al retirar (fecha)
--   REC_003 fecha fuera del periodo (inicio, fin)          REC_004 fecha de hoy o pasada (fecha, hoy)
--   REC_005 la fecha es festivo (nombre)                   REC_006 fecha repetida en el periodo
--   REC_007 periodo cerrado (nombre)                       REC_008 motivo vacio o largo (maximo)
--   REC_009 receso inexistente o ya retirado               REC_010 ya cancelo sesiones: no se retira (n)
--   REC_011 informativo de la previsualizacion del horario (horas, sesiones)
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('REC_001', 'SUCCESS', 'BAJO', N'Se registró el receso académico del {}; se cancelaron {} clases.'),
    ('REC_002', 'SUCCESS', 'BAJO', N'Se retiró el receso académico del {}.'),
    ('REC_003', 'VALIDATION_ERROR', 'BAJO', N'La fecha del receso debe estar dentro del período académico, del {} al {}.'),
    ('REC_004', 'VALIDATION_ERROR', 'BAJO', N'La fecha del receso debe ser posterior a hoy; elige una fecha desde mañana.'),
    ('REC_005', 'BUSINESS_ERROR', 'MEDIO', N'Ese día ya es festivo ({}); no necesita receso académico.'),
    ('REC_006', 'BUSINESS_ERROR', 'MEDIO', N'Ya hay un receso académico registrado para esa fecha en este período.'),
    ('REC_007', 'BUSINESS_ERROR', 'MEDIO', N'El período académico {} está cerrado; no se pueden registrar ni retirar días de receso.'),
    ('REC_008', 'VALIDATION_ERROR', 'BAJO', N'El motivo del receso es obligatorio y puede tener hasta {} caracteres.'),
    ('REC_009', 'BUSINESS_ERROR', 'MEDIO', N'El día de receso académico no existe o ya fue retirado.'),
    ('REC_010', 'BUSINESS_ERROR', 'MEDIO', N'Este día de receso ya canceló {} clases y no se puede retirar ni cambiar.'),
    ('REC_011', 'INFORMATIVO', 'BAJO', N'{} h caen en días de receso académico ({} sesión(es)); esas sesiones quedan canceladas.')
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
    ('REC_001', 'SUCCESS', 'BAJO', N'Receso academico [{}] creado. Sesiones canceladas: {}. Sesiones con asistencia que no se tocaron: {}.'),
    ('REC_002', 'SUCCESS', 'BAJO', N'Receso academico [{}] retirado (estaActivo = 0); no habia cancelado ninguna sesion.'),
    ('REC_003', 'VALIDATION_ERROR', 'BAJO', N'Fecha del receso fuera de PeriodoAcademico.fechaInicio..fechaFin ({}..{}).'),
    ('REC_004', 'VALIDATION_ERROR', 'BAJO', N'Fecha del receso [{}] no es posterior a la fecha local institucional de hoy [{}] (TIEMPO/ZONA_HORARIA_SQLSERVER).'),
    ('REC_005', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la fecha coincide con un DiaFestivo activo ({}); un receso en un festivo es redundante.'),
    ('REC_006', 'BUSINESS_ERROR', 'MEDIO', N'Unicidad: ya existe un PeriodoRecesoAcademico activo para el periodo y la fecha [{}].'),
    ('REC_007', 'BUSINESS_ERROR', 'MEDIO', N'Regla: PeriodoAcademico.fechaCierreUtc no es nula (periodo [{}] cerrado).'),
    ('REC_008', 'VALIDATION_ERROR', 'BAJO', N'Validacion: motivo vacio o mayor que RECESO/MOTIVO_LONGITUD_MAXIMA ({}).'),
    ('REC_009', 'BUSINESS_ERROR', 'MEDIO', N'Existencia: no hay PeriodoRecesoAcademico activo con el id [{}] en la institucion del ejecutor.'),
    ('REC_010', 'BUSINESS_ERROR', 'MEDIO', N'Regla: el receso tiene {} SesionCancelacion enlazadas; el retiro se rechaza sin escrituras.'),
    ('REC_011', 'INFORMATIVO', 'BAJO', N'Horas perdidas por receso academico: {} h en {} sesion(es).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
