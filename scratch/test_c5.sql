USE [gestionasistenciadb];
GO

DECLARE @tipoIdIdentificacion UNIQUEIDENTIFIER;
SELECT TOP 1 @tipoIdIdentificacion = id FROM dbo.TipoIdentificacion;

DECLARE @idGrupoValido UNIQUEIDENTIFIER;
SELECT TOP 1 @idGrupoValido = id FROM dbo.Grupo;

DECLARE @idAsignatura UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsignatura = id FROM dbo.Asignatura;

DECLARE @idDocenteValido UNIQUEIDENTIFIER;
SELECT TOP 1 @idDocenteValido = id FROM dbo.Docente;

DECLARE @idPeriodoValido UNIQUEIDENTIFIER;
SELECT TOP 1 @idPeriodoValido = id FROM dbo.PeriodoAcademico;

BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionC5 UNIQUEIDENTIFIER = NEWID();
    DECLARE @correoC5 NVARCHAR(255) = 'estudiante.cruce.c5@test.com';
    DECLARE @numeroIdC5 INT = 100000005;

    DECLARE @idGrupo2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@idGrupo2, @idAsignatura, @idPeriodoValido, 99992, 'Grupo Test Cruce Estudiante 2', 30, 0, 0, 0, @idDocenteValido);

    DECLARE @idDia UNIQUEIDENTIFIER;
    SELECT TOP 1 @idDia = id FROM dbo.Dia;

    -- Agregar horarios cruzados
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), @idGrupoValido, @idDia, '08:00:00', '10:00:00');

    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), @idGrupo2, @idDia, '09:00:00', '11:00:00');

    -- Primer registro
    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = @numeroIdC5,
        @primerApellido = 'Cruce',
        @segundoApellido = 'Estudiante',
        @primerNombre = 'Alumno',
        @segundoNombre = '',
        @correo = @correoC5,
        @password = 'Pass1234!',
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionC5;

    -- Debug: Ver si existe el estudiante en uv_estudiante_grupo
    PRINT '--- DEBUG EstudianteGrupo ---';
    SELECT eg.* FROM uv_estudiante_grupo eg;

    PRINT '--- DEBUG Horario ---';
    SELECT h.* FROM uv_horario h WHERE h.idGrupo IN (@idGrupoValido, @idGrupo2);

    -- Segundo registro
    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = @numeroIdC5,
        @primerApellido = 'Cruce',
        @segundoApellido = 'Estudiante',
        @primerNombre = 'Alumno',
        @segundoNombre = '',
        @correo = @correoC5,
        @password = 'Pass1234!',
        @idGrupo = @idGrupo2,
        @idCorrelacion = @idCorrelacionC5;
END;
ROLLBACK TRANSACTION;
GO
