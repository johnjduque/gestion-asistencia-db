USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

PRINT '======================================================================';
PRINT '  SUITE DE PRUEBAS COMPLETAS: usp_registrar_estudiante_en_grupo_usuario_no_existente';
PRINT '======================================================================';

-- 1. Declarar variables para los ID validos del sistema
DECLARE @tipoIdIdentificacion UNIQUEIDENTIFIER;
DECLARE @idGrupoValido UNIQUEIDENTIFIER;
DECLARE @idPeriodoValido UNIQUEIDENTIFIER;

-- 2. Obtener datos reales de la base de datos para la prueba
SELECT TOP 1 @tipoIdIdentificacion = id FROM dbo.TipoIdentificacion;
SELECT TOP 1 @idGrupoValido = id, @idPeriodoValido = periodoAcademico FROM dbo.Grupo;

-- Control para asegurar que existan datos base
IF @tipoIdIdentificacion IS NULL OR @idGrupoValido IS NULL OR @idPeriodoValido IS NULL
BEGIN
    PRINT 'ERROR CRITICO: No se encontraron registros base en TipoIdentificacion, Grupo o PeriodoAcademico. Deteniendo pruebas.';
    SET NOEXEC ON;
END

----------------------------------------------------------------------
-- CAMINO 1: IdCorrelacion Ausente / Vacio
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 1]: IdCorrelacion Ausente / Vacio (00000000-0000-0000-0000-000000000000) ---';
BEGIN TRANSACTION;
BEGIN
    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = 100000001,
        @primerApellido = 'Perez',
        @segundoApellido = 'Gomez',
        @primerNombre = 'Juan',
        @segundoNombre = 'Carlos',
        @correo = 'juan.perez.c1@test.com',
        @password = 'Pass1234!',
        @idGrupo = @idGrupoValido,
        @idCorrelacion = '00000000-0000-0000-0000-000000000000';
END;
ROLLBACK TRANSACTION;

----------------------------------------------------------------------
-- CAMINO 2: Happy Path (Usuario Nuevo + Estudiante Nuevo + Registro Exitoso)
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 2]: Happy Path (Usuario Nuevo -> Estudiante Nuevo -> Registro Exitoso) ---';
BEGIN TRANSACTION;
BEGIN
    -- Forzar vigencia del periodo academico para pasar la validacion
    UPDATE dbo.PeriodoAcademico 
    SET fechaInicio = DATEADD(month, -1, GETDATE()), 
        fechaFin = DATEADD(month, 3, GETDATE()) 
    WHERE id = @idPeriodoValido;

    DECLARE @idCorrelacionC2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @correoC2 NVARCHAR(255) = 'estudiante.nuevo.c2@test.com';
    DECLARE @numeroIdC2 INT = 100000002;

    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = @numeroIdC2,
        @primerApellido = 'Lopez',
        @segundoApellido = 'Diaz',
        @primerNombre = 'Maria',
        @segundoNombre = 'Fernanda',
        @correo = @correoC2,
        @password = 'Pass1234!',
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionC2;

    -- Verificacion
    IF EXISTS (
        SELECT 1 FROM dbo.Usuario u
        INNER JOIN dbo.Estudiante e ON u.id = e.usuario
        INNER JOIN dbo.EstudianteGrupo eg ON e.id = eg.estudiante
        WHERE u.correo = @correoC2 AND eg.grupo = @idGrupoValido
    )
        PRINT '>> RESULTADO: PASO (Estudiante creado e inscrito en el grupo exitosamente)';
    ELSE
        PRINT '>> RESULTADO: FALLO (La inscripcion no se realizo correctamente)';
END;
ROLLBACK TRANSACTION;

----------------------------------------------------------------------
-- CAMINO 3: Usuario Preexistente -> Actualiza Nombres, Crea Perfil y Asigna
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 3]: Usuario Preexistente -> Actualiza Nombres, Crea Perfil y Asigna ---';
BEGIN TRANSACTION;
BEGIN
    -- Forzar vigencia del periodo academico para pasar la validacion
    UPDATE dbo.PeriodoAcademico 
    SET fechaInicio = DATEADD(month, -1, GETDATE()), 
        fechaFin = DATEADD(month, 3, GETDATE()) 
    WHERE id = @idPeriodoValido;

    DECLARE @idCorrelacionC3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @correoC3 NVARCHAR(255) = 'usuario.preexistente.c3@test.com';
    DECLARE @numeroIdC3 INT = 100000003;
    DECLARE @idUsuarioC3 UNIQUEIDENTIFIER = NEWID();

    -- Crear usuario base sin perfil de estudiante
    INSERT INTO [dbo].[Usuario] (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@idUsuarioC3, @tipoIdIdentificacion, @numeroIdC3, 'ViejoAp', '', 'ViejoNom', '', @correoC3, 0, 1, 'ClaveVieja123*');

    -- Ejecutar orquestador con datos actualizados
    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = @numeroIdC3,
        @primerApellido = 'NuevoAp',
        @segundoApellido = 'Actualizado',
        @primerNombre = 'NuevoNom',
        @segundoNombre = '',
        @correo = @correoC3,
        @password = 'Pass1234!',
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionC3;

    -- Verificacion
    IF EXISTS (
        SELECT 1 FROM dbo.Usuario u
        INNER JOIN dbo.Estudiante e ON u.id = e.usuario
        INNER JOIN dbo.EstudianteGrupo eg ON e.id = eg.estudiante
        WHERE u.correo = @correoC3 
          AND u.primerNombre = 'NUEVONOM' 
          AND u.primerApellido = 'NUEVOAP'
          AND eg.grupo = @idGrupoValido
    )
        PRINT '>> RESULTADO: PASO (Usuario preexistente actualizado, perfil estudiante creado e inscrito)';
    ELSE
        PRINT '>> RESULTADO: FALLO (La actualizacion o inscripcion no se realizo correctamente)';
END;
ROLLBACK TRANSACTION;

----------------------------------------------------------------------
-- CAMINO 4: Fallo en Sincronizar Usuario (Campos Nulos / Invalidos)
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 4]: Fallo en Sincronizar Usuario (Campos Nulos / Invalidos) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionC4 UNIQUEIDENTIFIER = NEWID();

    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = NULL, -- Causara error de formato / ufn_validar_numero
        @primerApellido = NULL,
        @segundoApellido = NULL,
        @primerNombre = NULL,
        @segundoNombre = NULL,
        @correo = NULL,
        @password = NULL,
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionC4;
END;
ROLLBACK TRANSACTION;

----------------------------------------------------------------------
-- CAMINO 5: Fallo por Cruce de Horario del Estudiante
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 5]: Fallo por Cruce de Horario (Estudiante con clases coincidentes) ---';
BEGIN TRANSACTION;
BEGIN
    -- Forzar vigencia del periodo academico para pasar la validacion
    UPDATE dbo.PeriodoAcademico 
    SET fechaInicio = DATEADD(month, -1, GETDATE()), 
        fechaFin = DATEADD(month, 3, GETDATE()) 
    WHERE id = @idPeriodoValido;

    DECLARE @idCorrelacionC5 UNIQUEIDENTIFIER = NEWID();
    DECLARE @correoC5 NVARCHAR(255) = 'estudiante.cruce.c5@test.com';
    DECLARE @numeroIdC5 INT = 100000005;

    -- Obtener periodo academico del grupo valido
    DECLARE @idPeriodo UNIQUEIDENTIFIER;
    SELECT @idPeriodo = periodoAcademico FROM dbo.Grupo WHERE id = @idGrupoValido;

    -- Crear un segundo grupo de prueba en el mismo periodo
    DECLARE @idGrupo2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idAsignatura UNIQUEIDENTIFIER;
    SELECT TOP 1 @idAsignatura = id FROM dbo.Asignatura;
    DECLARE @idDocenteValido UNIQUEIDENTIFIER;
    SELECT TOP 1 @idDocenteValido = id FROM dbo.Docente;
    IF @idDocenteValido IS NULL SET @idDocenteValido = '00000000-0000-0000-0000-000000000000';

    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@idGrupo2, @idAsignatura, @idPeriodo, 99992, 'Grupo Test Cruce Estudiante 2', 30, 0, 0, 0, @idDocenteValido);

    -- Crear un dia comun para los horarios
    DECLARE @idDia UNIQUEIDENTIFIER;
    SELECT TOP 1 @idDia = id FROM dbo.Dia;

    -- Agregar horarios cruzados
    -- Grupo 1 (Grupo Valido): 08:00 a 10:00
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), @idGrupoValido, @idDia, '08:00:00', '10:00:00');

    -- Grupo 2: 09:00 a 11:00 (Traslape de 9:00 a 10:00)
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), @idGrupo2, @idDia, '09:00:00', '11:00:00');

    -- Enrolar estudiante al Grupo 1 exitosamente
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

    -- Intentar enrolar al mismo estudiante al Grupo 2 (Deberia fallar por cruce)
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

----------------------------------------------------------------------
-- CAMINO 6: Fallo por Grupo Inexistente
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 6]: Fallo por Grupo Inexistente (Grupo ID no registrado) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionC6 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idGrupoInexistente UNIQUEIDENTIFIER = '8B8B3878-E6D5-4664-A40E-F768A95A0115';

    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = 100000006,
        @primerApellido = 'Inexistente',
        @segundoApellido = 'Grupo',
        @primerNombre = 'Estudiante',
        @segundoNombre = '',
        @correo = 'estudiante.inexistente.c6@test.com',
        @password = 'Pass1234!',
        @idGrupo = @idGrupoInexistente,
        @idCorrelacion = @idCorrelacionC6;
END;
ROLLBACK TRANSACTION;

----------------------------------------------------------------------
-- CAMINO 7: Captura de error en CATCH (idGrupo = NULL / All Zeros)
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 7]: Captura de error en CATCH (idGrupo = NULL) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionC7 UNIQUEIDENTIFIER = NEWID();

    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = 100000007,
        @primerApellido = 'Error',
        @segundoApellido = 'Catch',
        @primerNombre = 'Estudiante',
        @segundoNombre = '',
        @correo = 'estudiante.catch.c7@test.com',
        @password = 'Pass1234!',
        @idGrupo = '00000000-0000-0000-0000-000000000000',
        @idCorrelacion = @idCorrelacionC7;
END;
ROLLBACK TRANSACTION;
GO
