USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- Dias IDs:
-- Lunes:    b1b2c3d4-0000-0000-0000-000000000001
-- Martes:   b1b2c3d4-0000-0000-0000-000000000002
-- Miercoles:b1b2c3d4-0000-0000-0000-000000000003
-- Jueves:   b1b2c3d4-0000-0000-0000-000000000004
-- Viernes:  b1b2c3d4-0000-0000-0000-000000000005

-- Grupo 01 (c1a2b3c4-0000-0000-0000-000000000001) - Lunes y Miércoles 08:00 - 10:00
IF NOT EXISTS (SELECT 1 FROM dbo.Horario WHERE grupo = 'c1a2b3c4-0000-0000-0000-000000000001' AND dia = 'b1b2c3d4-0000-0000-0000-000000000001')
BEGIN
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), 'c1a2b3c4-0000-0000-0000-000000000001', 'b1b2c3d4-0000-0000-0000-000000000001', '08:00:00', '10:00:00');
END

IF NOT EXISTS (SELECT 1 FROM dbo.Horario WHERE grupo = 'c1a2b3c4-0000-0000-0000-000000000001' AND dia = 'b1b2c3d4-0000-0000-0000-000000000003')
BEGIN
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), 'c1a2b3c4-0000-0000-0000-000000000001', 'b1b2c3d4-0000-0000-0000-000000000003', '08:00:00', '10:00:00');
END

-- Grupo 02 (de8a9d2d-65fc-4415-8b9e-47fab30a9091) - Martes y Jueves 10:00 - 12:00
IF NOT EXISTS (SELECT 1 FROM dbo.Horario WHERE grupo = 'de8a9d2d-65fc-4415-8b9e-47fab30a9091' AND dia = 'b1b2c3d4-0000-0000-0000-000000000002')
BEGIN
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), 'de8a9d2d-65fc-4415-8b9e-47fab30a9091', 'b1b2c3d4-0000-0000-0000-000000000002', '10:00:00', '12:00:00');
END

IF NOT EXISTS (SELECT 1 FROM dbo.Horario WHERE grupo = 'de8a9d2d-65fc-4415-8b9e-47fab30a9091' AND dia = 'b1b2c3d4-0000-0000-0000-000000000004')
BEGIN
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), 'de8a9d2d-65fc-4415-8b9e-47fab30a9091', 'b1b2c3d4-0000-0000-0000-000000000004', '10:00:00', '12:00:00');
END

-- Grupo 03 (5c44a7f7-050d-4807-a36b-5fbc08858ce9) - Viernes 14:00 - 16:00
IF NOT EXISTS (SELECT 1 FROM dbo.Horario WHERE grupo = '5c44a7f7-050d-4807-a36b-5fbc08858ce9' AND dia = 'b1b2c3d4-0000-0000-0000-000000000005')
BEGIN
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), '5c44a7f7-050d-4807-a36b-5fbc08858ce9', 'b1b2c3d4-0000-0000-0000-000000000005', '14:00:00', '16:00:00');
END

PRINT 'Datos semilla de Horarios de grupos insertados exitosamente.';
GO
