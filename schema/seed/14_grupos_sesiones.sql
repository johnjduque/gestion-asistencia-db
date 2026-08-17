USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- 1. Sembrado Idempotente: Grupo (Asignado a la Dra. María Elena)
MERGE INTO [dbo].[Grupo] AS Target
USING (VALUES
    ('A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D', 'E2F3A4B5-0000-0000-0000-000000000001', 'F2A3B4C5-0000-0000-0000-000000000001', 1, 'Grupo 001 - Arq Software', 30, 0, 0, 0, 'F1A2B3C4-0000-0000-0000-000000000003')
) AS Source (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET 
        Target.nombre = Source.nombre, 
        Target.docente = TRY_CAST(Source.docente AS UNIQUEIDENTIFIER),
        Target.cantidadEstudiantes = Source.cantidadEstudiantes
WHEN NOT MATCHED THEN
    INSERT (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.asignatura AS UNIQUEIDENTIFIER), TRY_CAST(Source.periodoAcademico AS UNIQUEIDENTIFIER), Source.codigo, Source.nombre, Source.cantidadEstudiantes, Source.cantidadEstudiantesFinalizaron, Source.cantidadEstudiantesCancelaronVoluntadPropia, Source.cantidadEstudiantesCancelaronAutomaticamente, TRY_CAST(Source.docente AS UNIQUEIDENTIFIER));
GO

-- 2. Sembrado Idempotente: Sesiones de Clase para el Grupo
MERGE INTO [dbo].[Sesion] AS Target
USING (VALUES
    ('B2C3D4E5-F6A7-8B9C-0D1E-2F3A4B5C6D7E', 'Patrones Arquitectonicos Hexagonales', 1, 'SES-01', 1, 'A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D', '2026-08-17 08:00:00', '2026-08-17 10:00:00'),
    ('C3D4E5F6-A7B8-9C0D-1E2F-3A4B5C6D7E8F', 'Domain-Driven Design (DDD)', 2, 'SES-02', 2, 'A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D', '2026-08-24 08:00:00', '2026-08-24 10:00:00')
) AS Source (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.numero, Source.codigo, Source.numeroSemana, TRY_CAST(Source.grupo AS UNIQUEIDENTIFIER), CAST(Source.fechaHoraInicio AS DATETIME2), CAST(Source.fechaHoraFin AS DATETIME2));
GO

-- 3. Sembrado Idempotente: EstudianteGrupo (Inscripción de Estudiantes Base)
DECLARE @EstadoActivo UNIQUEIDENTIFIER;
SELECT TOP 1 @EstadoActivo = id FROM [dbo].[EstadoEstudianteGrupo] WHERE codigo = 'A';

MERGE INTO [dbo].[EstudianteGrupo] AS Target
USING (VALUES
    ('B1A2C3D4-0000-0000-0000-000000000001', @EstadoActivo, 'F1A2B3C4-0000-0000-0000-000000000004', 'A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D'),
    ('B1A2C3D4-0000-0000-0000-000000000002', @EstadoActivo, 'F1A2B3C4-0000-0000-0000-000000000005', 'A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D')
) AS Source (id, estado, estudiante, grupo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN NOT MATCHED THEN
    INSERT (id, estado, estudiante, grupo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.estado, TRY_CAST(Source.estudiante AS UNIQUEIDENTIFIER), TRY_CAST(Source.grupo AS UNIQUEIDENTIFIER));
GO
