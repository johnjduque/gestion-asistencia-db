USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- PC BD-1 (docs/work-items/PC-puntos-control-tomas/CONTRACT.md §A.7): calculo de minutos por tramos entre puntos de control.
--   PC_CAL_01..14: tabla de casos del contrato (sesion de 08:00 a 10:00, tomas en los minutos 0, 40 y 100 salvo indicacion),
--   verificada en uv_asistencia_tramo (tramos y clasificacion), uv_asistencia_sesion_horas (minutos, horas, consolidado,
--   esParcial, codigoEstadoSesionEstudiante) y uv_resumen_asistencia_estudiante_grupo (horas del estudiante).
--   PC_INV_01: para toda cabecera con tomas, suma de minutos de tramos = minutosSesion y las cuatro horas suman horasSesion.
-- Un estudiante y una sesion por caso, por insercion directa (sesiones vencidas en minutos enteros) dentro de una transaccion
-- revertida. PC_CAL_13 y PC_CAL_14 simulan el efecto de un reclamo aprobado (el reclamo por toma es BD-3) cambiando la marca.
PRINT 'TEST START: test_pc_calculo_tramos (PC BD-1)';

IF OBJECT_ID(N'dbo.uv_toma_punto_control', N'V') IS NULL OR OBJECT_ID(N'dbo.uv_asistencia_tramo', N'V') IS NULL
   OR (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_asistencia_sesion_horas') AND name IN (
        'minutosSesion', 'minutosAsistidos', 'minutosFalta', 'minutosExcusa', 'minutosSinRegistro', 'tomasAusentes', 'tomasSinRegistro',
        'codigoEstadoSesionEstudiante')) <> 8
   OR (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_toma_asistencia') AND name IN (
        'fechaPuntoControlUtc', 'ordenPuntoControl', 'minutosTramoAnterior', 'minutosTramoSiguiente', 'fechaAperturaSiguienteUtc', 'horasToma')) <> 6
    THROW 58000, 'TEST FAILED PC_CAL: faltan las vistas de puntos de control o sus columnas.', 1;
GO

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @estadoA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @tipoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoCancelacionSesion WHERE esAutomatica = 0);
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @estCerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @idAsig UNIQUEIDENTIFIER, @idInst UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsig = a.id, @idInst = pr.idInstitucion
FROM dbo.uv_asignatura a
INNER JOIN dbo.uv_asignatura_plan_estudio apx ON apx.idAsignatura = a.id
INNER JOIN dbo.uv_semestre_plan_estudio spe ON spe.id = apx.idSemestrePlanEstudio
INNER JOIN dbo.uv_plan_estudio pe ON pe.id = spe.idPlanEstudio
INNER JOIN dbo.uv_programa pr ON pr.id = pe.idPrograma
ORDER BY a.id;
IF @tipoCC IS NULL OR @estadoA IS NULL OR @tipoManual IS NULL OR @modoManual IS NULL OR @estCerrada IS NULL OR @idAsig IS NULL OR @idInst IS NULL
    THROW 58001, 'TEST FAILED PC_CAL: faltan fixtures del seed (tipo CC, estado A, modo MANUAL, estado CERRADA, asignatura con programa).', 1;

-- Casos: id, orden, sesion cancelada; resultado esperado (tramos "min+clase" en orden, minutos, consolidado, parcial, estado)
CREATE TABLE #pcC (caso NVARCHAR(12) PRIMARY KEY, orden INT, cancelada BIT, tramos NVARCHAR(60), mAsis INT, mFalta INT, mExcusa INT, mSinReg INT,
    consolidado NVARCHAR(10), esParcial BIT, estado NVARCHAR(20), idUsuario UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idEG UNIQUEIDENTIFIER,
    idSesion UNIQUEIDENTIFIER, idAsistencia UNIQUEIDENTIFIER);
-- Tomas de cada caso: numero, minuto de apertura relativo al inicio, marca (NULL = sin detalle)
CREATE TABLE #pcT (caso NVARCHAR(12), numero INT, minuto INT, codigo NVARCHAR(5), idToma UNIQUEIDENTIFIER);

INSERT INTO #pcC (caso, orden, cancelada, tramos, mAsis, mFalta, mExcusa, mSinReg, consolidado, esParcial, estado) VALUES
    (N'PC_CAL_01', 1, 0, N'0P,40P,60P,20P', 120, 0, 0, 0, N'AN', 0, N'PRESENTE'),
    (N'PC_CAL_02', 2, 0, N'0P,40P,60A,20A', 40, 80, 0, 0, N'SJC', 1, N'PARCIAL'),
    (N'PC_CAL_03', 3, 0, N'0P,40A,60A,20P', 20, 100, 0, 0, N'SJC', 1, N'PARCIAL'),
    (N'PC_CAL_04', 4, 0, N'0A,40A,60P,20P', 80, 40, 0, 0, N'SJC', 1, N'PARCIAL'),
    (N'PC_CAL_05', 5, 0, N'0A,40A,60A,20A', 0, 120, 0, 0, N'SJC', 0, N'AUSENTE'),
    (N'PC_CAL_06A', 6, 0, N'30P,90P', 120, 0, 0, 0, N'AN', 0, N'PRESENTE'),
    (N'PC_CAL_06B', 7, 0, N'30A,90A', 0, 120, 0, 0, N'SJC', 0, N'AUSENTE'),
    (N'PC_CAL_07', 8, 0, N'0P,60A,60A,0P', 0, 120, 0, 0, N'SJC', 0, N'AUSENTE'),
    (N'PC_CAL_08', 9, 0, N'0A,0A,60P,60P', 120, 0, 0, 0, N'AN', 0, N'PRESENTE'),
    (N'PC_CAL_09', 10, 0, N'0P,40E,60E,20P', 20, 0, 100, 0, N'EX', 0, N'PARCIAL'),
    (N'PC_CAL_10', 11, 0, N'0P,40N,60N,20P', 20, 0, 0, 100, N'AN', 0, N'PARCIAL'),
    (N'PC_CAL_11', 12, 0, N'0P,40E,60A,20A', 0, 80, 40, 0, N'SJC', 0, N'AUSENTE'),
    -- cancelada: todo sin registro; el consolidado sigue por marcas (SJC) como antes
    (N'PC_CAL_12', 13, 1, N'0N,40N,60N,20N', 0, 0, 0, 120, N'SJC', 0, N'NO_DISPONIBLE'),
    -- 13 y 14 parten de PC_CAL_03; el esperado es el resultado tras cambiar la marca de la toma 2
    (N'PC_CAL_13', 14, 0, N'0P,40P,60P,20P', 120, 0, 0, 0, N'AN', 0, N'PRESENTE'),
    (N'PC_CAL_14', 15, 0, N'0P,40E,60E,20P', 20, 0, 100, 0, N'EX', 0, N'PARCIAL');
UPDATE #pcC SET idUsuario = NEWID(), idEstudiante = NEWID(), idEG = NEWID(), idSesion = NEWID(), idAsistencia = NEWID();

INSERT INTO #pcT (caso, numero, minuto, codigo) VALUES
    (N'PC_CAL_01', 1, 0, N'AN'), (N'PC_CAL_01', 2, 40, N'AN'), (N'PC_CAL_01', 3, 100, N'AN'),
    (N'PC_CAL_02', 1, 0, N'AN'), (N'PC_CAL_02', 2, 40, N'AN'), (N'PC_CAL_02', 3, 100, N'SJC'),
    (N'PC_CAL_03', 1, 0, N'AN'), (N'PC_CAL_03', 2, 40, N'SJC'), (N'PC_CAL_03', 3, 100, N'AN'),
    (N'PC_CAL_04', 1, 0, N'SJC'), (N'PC_CAL_04', 2, 40, N'AN'), (N'PC_CAL_04', 3, 100, N'AN'),
    (N'PC_CAL_05', 1, 0, N'SJC'), (N'PC_CAL_05', 2, 40, N'SJC'), (N'PC_CAL_05', 3, 100, N'SJC'),
    (N'PC_CAL_06A', 1, 30, N'AN'),
    (N'PC_CAL_06B', 1, 30, N'SJC'),
    (N'PC_CAL_07', 1, -10, N'AN'), (N'PC_CAL_07', 2, 60, N'SJC'), (N'PC_CAL_07', 3, 130, N'AN'),
    (N'PC_CAL_08', 1, -10, N'SJC'), (N'PC_CAL_08', 2, -5, N'AN'), (N'PC_CAL_08', 3, 60, N'AN'),
    (N'PC_CAL_09', 1, 0, N'AN'), (N'PC_CAL_09', 2, 40, N'EX'), (N'PC_CAL_09', 3, 100, N'AN'),
    (N'PC_CAL_10', 1, 0, N'AN'), (N'PC_CAL_10', 2, 40, NULL), (N'PC_CAL_10', 3, 100, N'AN'),
    (N'PC_CAL_11', 1, 0, N'AN'), (N'PC_CAL_11', 2, 40, N'EX'), (N'PC_CAL_11', 3, 100, N'SJC'),
    (N'PC_CAL_12', 1, 0, N'AN'), (N'PC_CAL_12', 2, 40, N'AN'), (N'PC_CAL_12', 3, 100, N'SJC'),
    (N'PC_CAL_13', 1, 0, N'AN'), (N'PC_CAL_13', 2, 40, N'SJC'), (N'PC_CAL_13', 3, 100, N'AN'),
    (N'PC_CAL_14', 1, 0, N'AN'), (N'PC_CAL_14', 2, 40, N'SJC'), (N'PC_CAL_14', 3, 100, N'AN');
UPDATE #pcT SET idToma = NEWID();

CREATE TABLE #pcO (caso NVARCHAR(12) PRIMARY KEY, tramos NVARCHAR(60), nTramos INT, sumaTramos INT, minutosSesion INT, mAsis INT, mFalta INT, mExcusa INT, mSinReg INT,
    hAsis DECIMAL(12,6), hFalta DECIMAL(12,6), hExcusa DECIMAL(12,6), hSinReg DECIMAL(12,6), hSesion DECIMAL(12,6),
    consolidado NVARCHAR(10), esParcial BIT, estado NVARCHAR(20), rAsis DECIMAL(12,6), rFalta DECIMAL(12,6), rExcusa DECIMAL(12,6));

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @uD UNIQUEIDENTIFIER = NEWID(), @d UNIQUEIDENTIFIER = NEWID(), @g UNIQUEIDENTIFIER = NEWID(), @per UNIQUEIDENTIFIER = NEWID();
    DECLARE @tag NVARCHAR(12) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 12);
    -- Sesiones de 08:00 a 10:00 UTC en dias pasados (minutos enteros): base = hace 40 dias
    DECLARE @base DATETIME2(7) = DATEADD(HOUR, 8, CAST(DATEADD(DAY, -40, CAST(SYSUTCDATETIME() AS DATE)) AS DATETIME2(7)));

    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uD, @tipoCC, 975000000 + ABS(CHECKSUM(NEWID()) % 999999), N'Puntos', N'Control', N'Doc', N'PC', CONCAT(N'pccal.d.', @tag, N'@test.local'), 1, 1, N'HashBackend_PC');
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT c.idUsuario, @tipoCC, 976000000 + c.orden * 10000 + ABS(CHECKSUM(NEWID()) % 9999), CONCAT(N'Puntos', c.orden), N'Control', N'Est', N'PC',
           CONCAT(N'pccal.e', c.orden, N'.', @tag, N'@test.local'), 1, 1, N'HashBackend_PC'
    FROM #pcC c;
    INSERT INTO dbo.Docente (id, usuario) VALUES (@d, @uD);
    INSERT INTO dbo.Estudiante (id, usuario) SELECT idEstudiante, idUsuario FROM #pcC;
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@per, @idInst, N'PC periodo tramos', 3900000 + ABS(CHECKSUM(NEWID()) % 90000), CAST(DATEADD(DAY, -60, @base) AS DATE), CAST(DATEADD(DAY, 60, @base) AS DATE), YEAR(@base));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@g, @idAsig, @per, 939000 + ABS(CHECKSUM(NEWID()) % 9999), N'PC Grupo tramos', 30, 0, 0, 0, @d);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) SELECT idEG, @estadoA, idEstudiante, @g FROM #pcC;
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
    SELECT c.idSesion, CONCAT(N'PC ', c.caso), c.orden, CONCAT(N'PC', c.orden, N'-', @tag), 1, @g,
           DATEADD(DAY, c.orden, @base), DATEADD(MINUTE, 120, DATEADD(DAY, c.orden, @base)), N'UTC_V2'
    FROM #pcC c;
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT t.idToma, c.idSesion, t.numero, @modoManual, @estCerrada, 0, @d, DATEADD(MINUTE, t.minuto, DATEADD(DAY, c.orden, @base)),
           DATEADD(MINUTE, 130, DATEADD(DAY, c.orden, @base)), NEWID()
    FROM #pcT t INNER JOIN #pcC c ON c.caso = t.caso;
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) SELECT idAsistencia, idEG, idSesion FROM #pcC;
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, c.idAsistencia, IIF(t.codigo = N'AN', 1, 0), rc.id,
           DATEADD(DAY, c.orden, @base), DATEADD(MINUTE, 120, DATEADD(DAY, c.orden, @base)), t.idToma, 0, SYSUTCDATETIME()
    FROM #pcT t INNER JOIN #pcC c ON c.caso = t.caso INNER JOIN dbo.RazonCausa rc ON rc.codigo = t.codigo COLLATE DATABASE_DEFAULT
    WHERE t.codigo IS NOT NULL;
    INSERT dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, idCorrelacion)
    SELECT c.idSesion, @tipoManual, N'PC cancelada con marcas', NULL, @uD, NEWID() FROM #pcC c WHERE c.cancelada = 1;

    -- PC_CAL_13 / PC_CAL_14: antes del cambio de marca dan lo mismo que PC_CAL_03
    IF EXISTS (SELECT 1 FROM dbo.uv_asistencia_sesion_horas h INNER JOIN #pcC c ON c.idAsistencia = h.idAsistencia
               WHERE c.caso IN (N'PC_CAL_13', N'PC_CAL_14') AND (h.minutosAsistidos <> 20 OR h.minutosFalta <> 100 OR h.codigoEstadoSesionEstudiante <> N'PARCIAL'))
        THROW 58002, 'TEST FAILED PC_CAL_13: antes del reclamo, la sesion con SJC en la toma 2 debe dar 20 / 100 como PC_CAL_03.', 1;
    -- Efecto de un reclamo de la toma 2 aprobado como PRESENTE (13) o como JUSTIFICADA (14)
    UPDATE da SET da.razonCausa = rc.id, da.asistio = IIF(c.caso = N'PC_CAL_13', 1, 0)
    FROM dbo.DetalleAsistencia da INNER JOIN #pcT t ON t.idToma = da.toma INNER JOIN #pcC c ON c.caso = t.caso
    INNER JOIN dbo.RazonCausa rc ON rc.codigo = IIF(c.caso = N'PC_CAL_13', N'AN', N'EX')
    WHERE c.caso IN (N'PC_CAL_13', N'PC_CAL_14') AND t.numero = 2;

    -- Resultado obtenido por caso
    INSERT INTO #pcO (caso, tramos, nTramos, sumaTramos, minutosSesion, mAsis, mFalta, mExcusa, mSinReg, hAsis, hFalta, hExcusa, hSinReg, hSesion,
        consolidado, esParcial, estado, rAsis, rFalta, rExcusa)
    SELECT c.caso, tr.tramos, tr.nTramos, tr.sumaTramos, h.minutosSesion, h.minutosAsistidos, h.minutosFalta, h.minutosExcusa, h.minutosSinRegistro,
           h.horasAsistidas, h.horasFalta, h.horasExcusa, h.horasSinRegistro, h.horasSesion, h.codigoRazonCausaConsolidado, h.esParcial,
           h.codigoEstadoSesionEstudiante, r.horasAsistidas, r.horasFalta, r.horasExcusa
    FROM #pcC c
    INNER JOIN dbo.uv_asistencia_sesion_horas h ON h.idAsistencia = c.idAsistencia
    INNER JOIN dbo.uv_resumen_asistencia_estudiante_grupo r ON r.idEstudianteGrupo = c.idEG
    CROSS APPLY (SELECT tramos = STRING_AGG(CONCAT(t.minutosTramo, CASE t.codigoClasificacionTramo WHEN N'PRESENTE' THEN N'P' WHEN N'AUSENTE' THEN N'A'
                                                                  WHEN N'EXCUSADO' THEN N'E' WHEN N'SIN_REGISTRO' THEN N'N' ELSE N'?' END), N',')
                                        WITHIN GROUP (ORDER BY t.ordenTramo),
                        nTramos = COUNT(*), sumaTramos = SUM(t.minutosTramo)
                 FROM dbo.uv_asistencia_tramo t WHERE t.idAsistencia = c.idAsistencia) tr;

    -- Una verificacion por caso: tramos, minutos, horas (minutos / 60 con 6 decimales), consolidado, parcial, estado y resumen
    DECLARE @caso NVARCHAR(12), @id NVARCHAR(12), @msg NVARCHAR(2048), @ultimo NVARCHAR(12) = N'';
    WHILE 1 = 1
    BEGIN
        SELECT TOP 1 @caso = caso FROM #pcC WHERE caso > @ultimo ORDER BY caso;
        IF @caso = @ultimo BREAK;
        SET @ultimo = @caso;
        IF NOT EXISTS (SELECT 1 FROM #pcC c INNER JOIN #pcO o ON o.caso = c.caso
                       WHERE c.caso = @caso AND o.tramos = c.tramos COLLATE DATABASE_DEFAULT AND o.nTramos = (SELECT COUNT(*) FROM #pcT t WHERE t.caso = c.caso) + 1
                         AND o.sumaTramos = 120 AND o.minutosSesion = 120 AND o.hSesion = 2.000000
                         AND o.mAsis = c.mAsis AND o.mFalta = c.mFalta AND o.mExcusa = c.mExcusa AND o.mSinReg = c.mSinReg
                         AND o.hAsis = CAST(CAST(c.mAsis AS DECIMAL(12,6)) / 60 AS DECIMAL(12,6)) AND o.hFalta = CAST(CAST(c.mFalta AS DECIMAL(12,6)) / 60 AS DECIMAL(12,6))
                         AND o.hExcusa = CAST(CAST(c.mExcusa AS DECIMAL(12,6)) / 60 AS DECIMAL(12,6)) AND o.hAsis + o.hFalta + o.hExcusa + o.hSinReg = o.hSesion
                         AND o.consolidado = c.consolidado COLLATE DATABASE_DEFAULT AND o.esParcial = c.esParcial AND o.estado = c.estado COLLATE DATABASE_DEFAULT
                         AND o.rAsis = o.hAsis AND o.rFalta = o.hFalta AND o.rExcusa = o.hExcusa)
        BEGIN
            SELECT @msg = CONCAT(N'TEST FAILED ', @caso, N': esperado ', c.tramos, N' ', c.mAsis, N'/', c.mFalta, N'/', c.mExcusa, N'/', c.mSinReg, N' ', c.consolidado,
                                 N' ', c.estado, N'; obtenido ', o.tramos, N' ', o.mAsis, N'/', o.mFalta, N'/', o.mExcusa, N'/', o.mSinReg, N' ', o.consolidado,
                                 N' parcial=', o.esParcial, N' ', o.estado, N' resumen=', o.rAsis, N'/', o.rFalta, N'/', o.rExcusa, N'.')
            FROM #pcC c LEFT JOIN #pcO o ON o.caso = c.caso WHERE c.caso = @caso;
            THROW 58010, @msg, 1;
        END;
        -- PC_CAL_06A y PC_CAL_06B son las dos variantes de PC_CAL_06
        SET @id = IIF(@caso LIKE N'PC_CAL_06_', N'PC_CAL_06', @caso);
        IF @caso <> N'PC_CAL_06A' PRINT CONCAT('TEST_PASS:', @id);
    END;

    -- Valores literales del contrato (6 decimales) y efectos que no son minutos
    IF NOT EXISTS (SELECT 1 FROM #pcO WHERE caso = N'PC_CAL_02' AND hAsis = 0.666667 AND hFalta = 1.333333 AND hSinReg = 0)
       OR NOT EXISTS (SELECT 1 FROM #pcO WHERE caso = N'PC_CAL_09' AND hAsis = 0.333333 AND hExcusa = 1.666667 AND hFalta = 0)
       OR NOT EXISTS (SELECT 1 FROM #pcO WHERE caso = N'PC_CAL_04' AND hAsis = 1.333333 AND hFalta = 0.666667)
       -- PC_CAL_08: la marca SJC de 0 minutos sigue existiendo y cuenta como toma ausente y en faltasSinJustaCausa
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_sesion_horas h INNER JOIN #pcC c ON c.idAsistencia = h.idAsistencia
                      WHERE c.caso = N'PC_CAL_08' AND h.tomasAusentes = 1 AND h.tomasSinRegistro = 0 AND h.tieneFaltaSinJustaCausa = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_resumen_asistencia_estudiante_grupo r INNER JOIN #pcC c ON c.idEG = r.idEstudianteGrupo
                      WHERE c.caso = N'PC_CAL_08' AND r.faltasSinJustaCausa = 1 AND r.asistencias = 2)
       -- PC_CAL_10: la toma sin detalle cuenta como toma sin registro
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_sesion_horas h INNER JOIN #pcC c ON c.idAsistencia = h.idAsistencia
                      WHERE c.caso = N'PC_CAL_10' AND h.tomasSinRegistro = 1 AND h.tomasConRegistro = 2 AND h.tomasAusentes = 0)
       -- PC_CAL_12: cancelada; la falta se sigue leyendo por marcas como antes
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_sesion_horas h INNER JOIN #pcC c ON c.idAsistencia = h.idAsistencia
                      WHERE c.caso = N'PC_CAL_12' AND h.tieneFaltaSinJustaCausa = 1 AND h.horasSinRegistro = 2.000000)
       -- PC_CAL_07: puntos recortados a inicio y fin, ordenados por punto
       OR (SELECT STRING_AGG(CONCAT(DATEDIFF(MINUTE, pc.fechaHoraInicioSesion, pc.fechaPuntoControlUtc), N'#', pc.ordenPuntoControl), N',') WITHIN GROUP (ORDER BY pc.numero)
           FROM dbo.uv_toma_asistencia pc INNER JOIN #pcC c ON c.idSesion = pc.idSesion WHERE c.caso = N'PC_CAL_07') <> N'0#1,60#2,120#3'
       -- uv_toma_asistencia: minutos de los tramos vecinos; horasToma (obsoleto) conserva 1/n
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_toma_asistencia ta INNER JOIN #pcT t ON t.idToma = ta.idToma
                      WHERE t.caso = N'PC_CAL_01' AND t.numero = 2 AND ta.minutosTramoAnterior = 40 AND ta.minutosTramoSiguiente = 60
                        AND ta.horasToma = 0.666667 AND ta.fechaAperturaSiguienteUtc = DATEADD(MINUTE, 100, ta.fechaHoraInicioSesion))
        THROW 58020, 'TEST FAILED PC_CAL: valores literales del contrato, marcas de 0 minutos, cancelada o columnas de uv_toma_asistencia no coinciden.', 1;

    -- --------------------------------------------------------------------------------------------------------
    -- PC_INV_01: toda cabecera con tomas (fixture y datos existentes): n + 1 tramos, suma de tramos = minutosSesion y
    -- horasAsistidas + horasFalta + horasExcusa + horasSinRegistro = horasSesion (minutos y horas)
    -- --------------------------------------------------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM dbo.uv_asistencia_sesion_horas h
               OUTER APPLY (SELECT n = COUNT(*), m = SUM(t.minutosTramo) FROM dbo.uv_asistencia_tramo t WHERE t.idAsistencia = h.idAsistencia) tr
               WHERE h.totalTomasSesion > 0
                 AND (tr.n <> h.totalTomasSesion + 1 OR tr.m <> h.minutosSesion
                      OR h.minutosAsistidos + h.minutosFalta + h.minutosExcusa + h.minutosSinRegistro <> h.minutosSesion
                      OR h.horasAsistidas + h.horasFalta + h.horasExcusa + h.horasSinRegistro <> h.horasSesion
                      OR h.minutosSinRegistro < 0 OR h.horasSinRegistro < 0))
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_asistencia_sesion_horas h INNER JOIN #pcC c ON c.idAsistencia = h.idAsistencia)
        THROW 58030, 'TEST FAILED PC_INV_01: la suma de los tramos o de las cuatro horas no coincide con la duracion de la sesion.', 1;
    PRINT 'TEST_PASS:PC_INV_01';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    PRINT CONCAT('TEST FAILED: ', @err);
    THROW;
END CATCH;
GO

IF @@TRANCOUNT <> 0
    THROW 58099, 'TEST FAILED PC_CAL: @@TRANCOUNT distinto de 0 al terminar.', 1;
PRINT 'TEST_PASS:PC_CAL_TRANCOUNT_ZERO';
PRINT 'TEST END: test_pc_calculo_tramos';
GO
