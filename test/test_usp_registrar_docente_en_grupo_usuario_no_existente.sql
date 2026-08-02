USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

PRINT '======================================================================';
PRINT '  SUITE DE PRUEBAS COMPLETAS: usp_registrar_docente_en_grupo_usuario_no_existente';
PRINT '======================================================================';

-- Obtener datos válidos preexistentes para pruebas
DECLARE @tipoIdIdentificacion UNIQUEIDENTIFIER;
SELECT TOP 1 @tipoIdIdentificacion = id FROM [dbo].[TipoIdentificacion];

DECLARE @idGrupoValido UNIQUEIDENTIFIER;
SELECT TOP 1 @idGrupoValido = id FROM [dbo].[Grupo];

DECLARE @idPeriodoValido UNIQUEIDENTIFIER;
SELECT @idPeriodoValido = periodoAcademico FROM [dbo].[Grupo] WHERE id = @idGrupoValido;

IF @tipoIdIdentificacion IS NULL OR @idGrupoValido IS NULL OR @idPeriodoValido IS NULL
BEGIN
    PRINT 'ERROR CRÍTICO: No se encontraron registros base en TipoIdentificacion, Grupo o PeriodoAcademico. Deteniendo pruebas.';
    RETURN;
END

----------------------------------------------------------------------
-- CAMINO 1: Validación de ID Correlación Ausente/Vacío
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 1]: IdCorrelacion Ausente / Vacío (00000000-0000-0000-0000-000000000000) ---';
BEGIN
    DECLARE @mensajeUsuarioC1 NVARCHAR(4000);
    DECLARE @mensajeTecnicoC1 NVARCHAR(4000);
    DECLARE @estadoC1 BIT;

    EXEC [dbo].[usp_registrar_docente_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = 200000001,
        @primerApellido = 'Perez',
        @segundoApellido = 'Gomez',
        @primerNombre = 'Juan',
        @segundoNombre = 'Carlos',
        @correo = 'juan.docente.c1@test.com',
        @password = 'Pass1234!',
        @idGrupo = @idGrupoValido,
        @idCorrelacion = '00000000-0000-0000-0000-000000000000'; -- Inválido

    -- Nota: Al llamarse desde SSMS o script de prueba, el orquestador retorna un Result Set.
END;

----------------------------------------------------------------------
-- CAMINO 2: Happy Path (Usuario Nuevo + Docente Nuevo + Registro Exitoso)
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 2]: Happy Path (Usuario Nuevo -> Docente Nuevo -> Asignación Exitosa) ---';
BEGIN TRANSACTION;
BEGIN
    -- Forzar vigencia del periodo académico para pasar la validación
    UPDATE dbo.PeriodoAcademico 
    SET fechaInicio = DATEADD(month, -1, GETDATE()), 
        fechaFin = DATEADD(month, 3, GETDATE()) 
    WHERE id = @idPeriodoValido;

    DECLARE @idCorrelacionC2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @correoC2 NVARCHAR(255) = 'docente.happy.c2@test.com';
    DECLARE @numeroIdC2 INT = 200000002;

    -- Ejecutar
    EXEC [dbo].[usp_registrar_docente_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = @numeroIdC2,
        @primerApellido = 'Sanchez',
        @segundoApellido = 'Mendoza',
        @primerNombre = 'Luis',
        @segundoNombre = 'Alberto',
        @correo = @correoC2,
        @password = 'Pass1234!',
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionC2;

    -- Verificación de Inserción
    IF EXISTS (
        SELECT 1 FROM dbo.Usuario u
        INNER JOIN dbo.Docente d ON u.id = d.usuario
        INNER JOIN dbo.Grupo g ON d.id = g.docente
        WHERE u.correo = @correoC2 AND g.id = @idGrupoValido
    )
        PRINT '>> RESULTADO: PASÓ (Docente creado y asignado al grupo exitosamente)';
    ELSE
        PRINT '>> RESULTADO: FALLÓ (No se encontró la asociación completa)';
END;
ROLLBACK TRANSACTION;

----------------------------------------------------------------------
-- CAMINO 3: Usuario Preexistente (Sin Perfil Docente) -> Actualiza y Asigna
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 3]: Usuario Preexistente -> Actualiza Nombres, Crea Perfil y Asigna ---';
BEGIN TRANSACTION;
BEGIN
    -- Forzar vigencia del periodo académico para pasar la validación
    UPDATE dbo.PeriodoAcademico 
    SET fechaInicio = DATEADD(month, -1, GETDATE()), 
        fechaFin = DATEADD(month, 3, GETDATE()) 
    WHERE id = @idPeriodoValido;

    DECLARE @idCorrelacionC3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @correoC3 NVARCHAR(255) = 'usuario.preexistente.c3@test.com';
    DECLARE @numeroIdC3 INT = 200000003;
    DECLARE @idUsuarioC3 UNIQUEIDENTIFIER = NEWID();

    -- Crear usuario base sin perfil de docente
    INSERT INTO [dbo].[Usuario] (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@idUsuarioC3, @tipoIdIdentificacion, @numeroIdC3, 'AntiguoAp', '', 'AntiguoNom', '', @correoC3, 0, 1, 'ClaveVieja123*');

    -- Ejecutar orquestador con datos actualizados
    EXEC [dbo].[usp_registrar_docente_en_grupo_usuario_no_existente]
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

    -- Verificación
    IF EXISTS (
        SELECT 1 FROM dbo.Usuario u
        INNER JOIN dbo.Docente d ON u.id = d.usuario
        INNER JOIN dbo.Grupo g ON d.id = g.docente
        WHERE u.correo = @correoC3 
          AND u.primerNombre = 'NUEVONOM' 
          AND u.primerApellido = 'NUEVOAP'
          AND g.id = @idGrupoValido
    )
        PRINT '>> RESULTADO: PASÓ (Usuario preexistente actualizado, perfil docente creado y asignado)';
    ELSE
        PRINT '>> RESULTADO: FALLÓ (La actualización o asignación no se realizó correctamente)';
END;
ROLLBACK TRANSACTION;

----------------------------------------------------------------------
-- CAMINO 4: Fallo por Sincronización de Usuario (Campos Obligatorios NULL)
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 4]: Fallo en Sincronizar Usuario (Campos Nulos / Inválidos) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionC4 UNIQUEIDENTIFIER = NEWID();

    EXEC [dbo].[usp_registrar_docente_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = NULL, -- Causará error de formato / ufn_validar_numero
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
-- CAMINO 5: Fallo por Cruce de Horario del Docente
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 5]: Fallo por Cruce de Horario (Docente con clases coincidentes) ---';
BEGIN TRANSACTION;
BEGIN
    -- Forzar vigencia del periodo académico para pasar la validación
    UPDATE dbo.PeriodoAcademico 
    SET fechaInicio = DATEADD(month, -1, GETDATE()), 
        fechaFin = DATEADD(month, 3, GETDATE()) 
    WHERE id = @idPeriodoValido;

    DECLARE @idCorrelacionC5 UNIQUEIDENTIFIER = NEWID();
    DECLARE @correoC5 NVARCHAR(255) = 'docente.cruce.c5@test.com';
    DECLARE @numeroIdC5 INT = 200000005;

    -- Obtener periodo académico del grupo válido
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
    VALUES (@idGrupo2, @idAsignatura, @idPeriodo, 99991, 'Grupo Test Cruce 2', 30, 0, 0, 0, @idDocenteValido);

    -- Crear un día común para los horarios
    DECLARE @idDia UNIQUEIDENTIFIER;
    SELECT TOP 1 @idDia = id FROM dbo.Dia;

    -- Agregar horarios cruzados
    -- Grupo 1 (Grupo Válido): 08:00 a 10:00
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), @idGrupoValido, @idDia, '08:00:00', '10:00:00');

    -- Grupo 2: 09:00 a 11:00 (Traslape de 9:00 a 10:00)
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), @idGrupo2, @idDia, '09:00:00', '11:00:00');

    -- Asignar docente al Grupo 1 exitosamente
    EXEC [dbo].[usp_registrar_docente_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = @numeroIdC5,
        @primerApellido = 'Cruce',
        @segundoApellido = 'Docente',
        @primerNombre = 'Profesor',
        @segundoNombre = '',
        @correo = @correoC5,
        @password = 'Pass1234!',
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionC5;

    -- Intentar asignar el mismo docente al Grupo 2 (Debería fallar por cruce)
    EXEC [dbo].[usp_registrar_docente_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = @numeroIdC5,
        @primerApellido = 'Cruce',
        @segundoApellido = 'Docente',
        @primerNombre = 'Profesor',
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
    DECLARE @idGrupoInexistente UNIQUEIDENTIFIER = NEWID();

    EXEC [dbo].[usp_registrar_docente_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = 200000006,
        @primerApellido = 'Rojas',
        @segundoApellido = '',
        @primerNombre = 'Laura',
        @segundoNombre = '',
        @correo = 'laura.rojas.c6@test.com',
        @password = 'Pass1234!',
        @idGrupo = @idGrupoInexistente,
        @idCorrelacion = @idCorrelacionC6;
END;
ROLLBACK TRANSACTION;

----------------------------------------------------------------------
-- CAMINO 7: Captura de Excepción en Bloque CATCH (Error Crítico)
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 7]: Captura de error en CATCH (idGrupo = NULL) ---';
BEGIN
    DECLARE @idCorrelacionC7 UNIQUEIDENTIFIER = NEWID();

    EXEC [dbo].[usp_registrar_docente_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = 200000007,
        @primerApellido = 'Excepcion',
        @segundoApellido = '',
        @primerNombre = 'Test',
        @segundoNombre = '',
        @correo = 'test.catch.c7@test.com',
        @password = 'Pass1234!',
        @idGrupo = NULL, -- Causará error en la inserción/validación interna al no admitir nulo
        @idCorrelacion = @idCorrelacionC7;
END;
GO
