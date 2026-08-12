USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

PRINT '======================================================================';
PRINT '  DESHABILITANDO CONSTRICCIONES DE CLAVE FORANEA PARA SEMBRADO';
PRINT '======================================================================';

ALTER TABLE dbo.PeriodoAcademico NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Facultad NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Docente NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Estudiante NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Programa NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.PlanEstudio NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Semestre NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.SemestrePlanEstudio NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Asignatura NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Grupo NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Horario NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.EstudianteGrupo NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Sesion NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.Asistencia NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.DetalleAsistencia NOCHECK CONSTRAINT ALL;
ALTER TABLE dbo.TipoPrograma NOCHECK CONSTRAINT ALL;

PRINT '======================================================================';
PRINT '  SEMBRADO DE DATOS SEMILLA BASE PARA LA SUITE DE PRUEBAS';
PRINT '======================================================================';

-- 1. Asegurar catálogo de TipoIdentificacion
IF NOT EXISTS (SELECT 1 FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC')
    INSERT INTO dbo.TipoIdentificacion (id, tipoIdentificacion, nombre) VALUES (NEWID(), 'CC', 'Cedula de ciudadania');
IF NOT EXISTS (SELECT 1 FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'TI')
    INSERT INTO dbo.TipoIdentificacion (id, tipoIdentificacion, nombre) VALUES (NEWID(), 'TI', 'Tarjeta de identidad');
IF NOT EXISTS (SELECT 1 FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'PA')
    INSERT INTO dbo.TipoIdentificacion (id, tipoIdentificacion, nombre) VALUES (NEWID(), 'PA', 'Pasaporte');

-- 2. Asegurar catálogo de Dia
IF NOT EXISTS (SELECT 1 FROM dbo.Dia WHERE codigo = 'LU')
    INSERT INTO dbo.Dia (id, nombre, codigo) VALUES (NEWID(), 'Lunes', 'LU');
IF NOT EXISTS (SELECT 1 FROM dbo.Dia WHERE codigo = 'MA')
    INSERT INTO dbo.Dia (id, nombre, codigo) VALUES (NEWID(), 'Martes', 'MA');
IF NOT EXISTS (SELECT 1 FROM dbo.Dia WHERE codigo = 'MI')
    INSERT INTO dbo.Dia (id, nombre, codigo) VALUES (NEWID(), 'Miercoles', 'MI');
IF NOT EXISTS (SELECT 1 FROM dbo.Dia WHERE codigo = 'JU')
    INSERT INTO dbo.Dia (id, nombre, codigo) VALUES (NEWID(), 'Jueves', 'JU');
IF NOT EXISTS (SELECT 1 FROM dbo.Dia WHERE codigo = 'VI')
    INSERT INTO dbo.Dia (id, nombre, codigo) VALUES (NEWID(), 'Viernes', 'VI');
IF NOT EXISTS (SELECT 1 FROM dbo.Dia WHERE codigo = 'SA')
    INSERT INTO dbo.Dia (id, nombre, codigo) VALUES (NEWID(), 'Sabado', 'SA');
IF NOT EXISTS (SELECT 1 FROM dbo.Dia WHERE codigo = 'DO')
    INSERT INTO dbo.Dia (id, nombre, codigo) VALUES (NEWID(), 'Domingo', 'DO');

-- 3. Asegurar catálogo de EstadoEstudianteGrupo
IF NOT EXISTS (SELECT 1 FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A')
    INSERT INTO dbo.EstadoEstudianteGrupo (id, nombre, codigo) VALUES (NEWID(), 'activo', 'A');
IF NOT EXISTS (SELECT 1 FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'CVP')
    INSERT INTO dbo.EstadoEstudianteGrupo (id, nombre, codigo) VALUES (NEWID(), 'cancelado por voluntad propia', 'CVP');
IF NOT EXISTS (SELECT 1 FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'CI')
    INSERT INTO dbo.EstadoEstudianteGrupo (id, nombre, codigo) VALUES (NEWID(), 'cancelado por inasistencia', 'CI');
IF NOT EXISTS (SELECT 1 FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'F')
    INSERT INTO dbo.EstadoEstudianteGrupo (id, nombre, codigo) VALUES (NEWID(), 'finalizado', 'F');

-- 4. Asegurar catálogo de RazonCausa
IF NOT EXISTS (SELECT 1 FROM dbo.RazonCausa WHERE codigo = 'A')
    INSERT INTO dbo.RazonCausa (id, nombre, codigo) VALUES (NEWID(), 'Asistio', 'A');
IF NOT EXISTS (SELECT 1 FROM dbo.RazonCausa WHERE codigo = 'F')
    INSERT INTO dbo.RazonCausa (id, nombre, codigo) VALUES (NEWID(), 'Falto', 'F');
IF NOT EXISTS (SELECT 1 FROM dbo.RazonCausa WHERE codigo = 'T')
    INSERT INTO dbo.RazonCausa (id, nombre, codigo) VALUES (NEWID(), 'Tarde', 'T');
IF NOT EXISTS (SELECT 1 FROM dbo.RazonCausa WHERE codigo = 'J')
    INSERT INTO dbo.RazonCausa (id, nombre, codigo) VALUES (NEWID(), 'Justificado', 'J');

-- 4.1. Asegurar catálogo de Mensaje
IF NOT EXISTS (SELECT 1 FROM dbo.Mensaje WHERE codigo = 'ERR_PROGRAMA_GRUPO_NO_ENCONTRADO' AND tipo = 'USUARIO')
    INSERT INTO dbo.Mensaje (codigo, tipo, contenidoUsuario, contenidoTecnico) VALUES ('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'USUARIO', 'No se encontró un programa académico asociado a este grupo.', 'No se encontró un programa académico asociado a este grupo.');
IF NOT EXISTS (SELECT 1 FROM dbo.Mensaje WHERE codigo = 'ERR_PROGRAMA_GRUPO_NO_ENCONTRADO' AND tipo = 'TECNICO')
    INSERT INTO dbo.Mensaje (codigo, tipo, contenidoUsuario, contenidoTecnico) VALUES ('ERR_PROGRAMA_GRUPO_NO_ENCONTRADO', 'TECNICO', 'Error: Trazabilidad rota para {entidad}', 'Error: Trazabilidad rota para {entidad}');
IF NOT EXISTS (SELECT 1 FROM dbo.Mensaje WHERE codigo = 'ERR_INESPERADO_REGISTRO_ESTUDIANTE' AND tipo = 'USUARIO')
    INSERT INTO dbo.Mensaje (codigo, tipo, contenidoUsuario, contenidoTecnico) VALUES ('ERR_INESPERADO_REGISTRO_ESTUDIANTE', 'USUARIO', 'Hubo un error inesperado al procesar el registro completo del estudiante.', 'Hubo un error inesperado al procesar el registro completo del estudiante.');

-- 4.2. Asegurar catálogo de Parametro
IF OBJECT_ID('dbo.Parametro', 'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.Parametro WHERE grupo = 'GENERAL' AND clave = 'UUID_DEFECTO')
        INSERT INTO dbo.Parametro (grupo, clave, valor, descripcion) VALUES ('GENERAL', 'UUID_DEFECTO', '00000000-0000-0000-0000-000000000000', 'UUID comodin por defecto para valores nulos');
END


-- 5. Crear una Institución semilla
DECLARE @idInstitucion UNIQUEIDENTIFIER;
SELECT TOP 1 @idInstitucion = id FROM dbo.Institucion;
IF @idInstitucion IS NULL
BEGIN
    SET @idInstitucion = NEWID();
    INSERT INTO dbo.Institucion (id, nombre, estado) VALUES (@idInstitucion, 'Institucion de Prueba', 1);
END

-- 6. Crear un PeriodoAcademico semilla
DECLARE @idPeriodoValido UNIQUEIDENTIFIER;
SELECT TOP 1 @idPeriodoValido = id FROM dbo.PeriodoAcademico;
IF @idPeriodoValido IS NULL
BEGIN
    SET @idPeriodoValido = NEWID();
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@idPeriodoValido, @idInstitucion, 'Periodo de Prueba 2026', 202601, DATEADD(month, -1, GETDATE()), DATEADD(month, 3, GETDATE()), 2026);
END
ELSE
BEGIN
    UPDATE dbo.PeriodoAcademico 
    SET fechaInicio = DATEADD(month, -1, GETDATE()), 
        fechaFin = DATEADD(month, 3, GETDATE()) 
    WHERE id = @idPeriodoValido;
END

-- 7. Asegurar Perfil con codigo ES (Estudiante) - requerido por usp_registrar_estudiante_en_grupo
IF NOT EXISTS (SELECT 1 FROM dbo.Perfil WHERE codigo = 'ES')
    INSERT INTO dbo.Perfil (id, nombre, nivel_acceso, codigo) VALUES (NEWID(), 'Estudiante', 1, 'ES');
IF NOT EXISTS (SELECT 1 FROM dbo.Perfil WHERE codigo = 'DO')
    INSERT INTO dbo.Perfil (id, nombre, nivel_acceso, codigo) VALUES (NEWID(), 'Docente', 2, 'DO');

-- 8. Asegurar Area y Componente semilla (requeridos por uv_asignatura INNER JOINs)
DECLARE @idArea UNIQUEIDENTIFIER;
SELECT TOP 1 @idArea = id FROM dbo.Area;
IF @idArea IS NULL
BEGIN
    SET @idArea = NEWID();
    INSERT INTO dbo.Area (id, nombre, codigo) VALUES (@idArea, 'Area Test', 'AT1');
END

DECLARE @idComponente UNIQUEIDENTIFIER;
SELECT TOP 1 @idComponente = id FROM dbo.Componente;
IF @idComponente IS NULL
BEGIN
    SET @idComponente = NEWID();
    INSERT INTO dbo.Componente (id, nombre, codigo) VALUES (@idComponente, 'Componente Test', 'CT1');
END

-- 9. Crear jerarquia Facultad -> Programa -> PlanEstudio -> Semestre -> SemestrePlanEstudio
-- (requerida por uv_asignatura y uv_grupo INNER JOINs)
DECLARE @idFacultad UNIQUEIDENTIFIER;
SELECT TOP 1 @idFacultad = id FROM dbo.Facultad;
IF @idFacultad IS NULL
BEGIN
    SET @idFacultad = NEWID();
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@idFacultad, 'Facultad Test', @idInstitucion, '00000000-0000-0000-0000-000000000000', 1);
END

DECLARE @idTipoPrograma UNIQUEIDENTIFIER;
SELECT TOP 1 @idTipoPrograma = id FROM dbo.TipoPrograma;
IF @idTipoPrograma IS NULL
BEGIN
    SET @idTipoPrograma = NEWID();
    INSERT INTO dbo.TipoPrograma (id, nombre, estado, codigo) VALUES (@idTipoPrograma, 'Pregrado', 1, 'PRE');
END

DECLARE @idPrograma UNIQUEIDENTIFIER;
SELECT TOP 1 @idPrograma = id FROM dbo.Programa;
IF @idPrograma IS NULL
BEGIN
    SET @idPrograma = NEWID();
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES (@idPrograma, @idFacultad, @idTipoPrograma, 'Ingenieria de Sistemas Test', '00000000-0000-0000-0000-000000000000', 1);
END

DECLARE @idPlanEstudio UNIQUEIDENTIFIER;
SELECT TOP 1 @idPlanEstudio = id FROM dbo.PlanEstudio;
IF @idPlanEstudio IS NULL
BEGIN
    SET @idPlanEstudio = NEWID();
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES (@idPlanEstudio, @idPrograma, 1, 1);
END

DECLARE @idSemestre UNIQUEIDENTIFIER;
SELECT TOP 1 @idSemestre = id FROM dbo.Semestre;
IF @idSemestre IS NULL
BEGIN
    SET @idSemestre = NEWID();
    INSERT INTO dbo.Semestre (id, nombre, numero, codigo) VALUES (@idSemestre, 'Semestre 1', 1, 'S1');
END

DECLARE @idSemestrePlanEstudio UNIQUEIDENTIFIER;
SELECT TOP 1 @idSemestrePlanEstudio = id FROM dbo.SemestrePlanEstudio;
IF @idSemestrePlanEstudio IS NULL
BEGIN
    SET @idSemestrePlanEstudio = NEWID();
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES (@idSemestrePlanEstudio, @idPlanEstudio, @idSemestre);
END

-- 10. LIMPIEZA DE DATOS DE PRUEBAS ANTERIORES
-- Eliminar datos de test anteriores para que se recreen limpiamente
DELETE FROM dbo.Horario WHERE grupo IN (SELECT id FROM dbo.Grupo WHERE codigo = 9001);
DELETE FROM dbo.EstudianteGrupo WHERE grupo IN (SELECT id FROM dbo.Grupo WHERE codigo = 9001);
DELETE FROM dbo.Sesion WHERE grupo IN (SELECT id FROM dbo.Grupo WHERE codigo = 9001);
DELETE FROM dbo.Grupo WHERE codigo = 9001;
DELETE FROM dbo.Asignatura WHERE codigo = 'PRG01';
DELETE FROM dbo.Docente WHERE usuario IN (SELECT id FROM dbo.Usuario WHERE numeroIdentificacion = 9999901);
DELETE FROM dbo.Usuario WHERE numeroIdentificacion = 9999901;

-- 11. Resolver o crear Asignatura semilla visible en uv_asignatura
DECLARE @idAsignatura UNIQUEIDENTIFIER;
SELECT TOP 1 @idAsignatura = id FROM uv_asignatura;
IF @idAsignatura IS NULL
BEGIN
    -- La BD esta vacia, crear asignatura con registros reales creados arriba
    SET @idAsignatura = NEWID();
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado) 
    VALUES (@idAsignatura, 'PRG01', 'Programacion Avanzada', 4, @idArea, @idComponente, @idSemestrePlanEstudio, 1);
END

-- 12. Resolver o crear Docente semilla
DECLARE @idDocenteValido UNIQUEIDENTIFIER;
SELECT TOP 1 @idDocenteValido = id FROM dbo.Docente;
IF @idDocenteValido IS NULL
BEGIN
    DECLARE @idUsuarioDocente UNIQUEIDENTIFIER = NEWID();
    DECLARE @tipoIdCC UNIQUEIDENTIFIER;
    SELECT TOP 1 @tipoIdCC = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC';
    
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, password, estado)
    VALUES (@idUsuarioDocente, @tipoIdCC, 9999901, 'Docente', 'Prueba', 'Juan', '', 'docente.test@test.com', 1, 'Pass1234!', 1);
    
    SET @idDocenteValido = NEWID();
    INSERT INTO dbo.Docente (id, usuario) VALUES (@idDocenteValido, @idUsuarioDocente);
END

-- 13. Crear Grupo semilla (siempre se crea fresco)
DECLARE @idGrupoValido UNIQUEIDENTIFIER = NEWID();
INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
VALUES (@idGrupoValido, @idAsignatura, @idPeriodoValido, 9001, 'Grupo 1 Test', 30, 0, 0, 0, @idDocenteValido);

-- 15. Asignar un Horario al grupo test
DECLARE @idDiaLunes UNIQUEIDENTIFIER;
SELECT TOP 1 @idDiaLunes = id FROM dbo.Dia WHERE codigo = 'LU';
INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
VALUES (NEWID(), @idGrupoValido, @idDiaLunes, '08:00:00', '10:00:00');

PRINT '>> Sembrado completado de forma satisfactoria.';

DECLARE @tipoIdIdentificacion UNIQUEIDENTIFIER;
SELECT TOP 1 @tipoIdIdentificacion = id FROM dbo.TipoIdentificacion;

------------------------------------------------------------------------------------------------------------------------
-- METODO: usp_registrar_estudiante_en_grupo_usuario_no_existente
------------------------------------------------------------------------------------------------------------------------
PRINT '----------------------------------------------------------------------';
PRINT '  PRUEBAS DE: usp_registrar_estudiante_en_grupo_usuario_no_existente';
PRINT '----------------------------------------------------------------------';

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
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

PRINT '--- [CAMINO 2]: Happy Path (Usuario Nuevo -> Estudiante Nuevo -> Registro Exitoso) ---';
BEGIN TRANSACTION;
BEGIN
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
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

PRINT '--- [CAMINO 3]: Usuario Preexistente -> Actualiza Nombres, Crea Perfil y Asigna ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionC3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @correoC3 NVARCHAR(255) = 'usuario.preexistente.c3@test.com';
    DECLARE @numeroIdC3 INT = 100000003;
    DECLARE @idUsuarioC3 UNIQUEIDENTIFIER = NEWID();

    INSERT INTO [dbo].[Usuario] (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@idUsuarioC3, @tipoIdIdentificacion, @numeroIdC3, 'ViejoAp', '', 'ViejoNom', '', @correoC3, 0, 1, 'ClaveVieja123*');

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
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

PRINT '--- [CAMINO 4]: Fallo en Sincronizar Usuario (Campos Nulos / Invalidos) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionC4 UNIQUEIDENTIFIER = NEWID();

    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = NULL,
        @primerApellido = NULL,
        @segundoApellido = NULL,
        @primerNombre = NULL,
        @segundoNombre = NULL,
        @correo = NULL,
        @password = NULL,
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionC4;
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

PRINT '--- [CAMINO 5]: Fallo por Cruce de Horario (Estudiante con clases coincidentes) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionC5 UNIQUEIDENTIFIER = NEWID();
    DECLARE @correoC5 NVARCHAR(255) = 'estudiante.cruce.c5@test.com';
    DECLARE @numeroIdC5 INT = 100000005;

    DECLARE @idGrupo2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idPeriodo UNIQUEIDENTIFIER;
    SELECT @idPeriodo = periodoAcademico FROM dbo.Grupo WHERE id = @idGrupoValido;
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@idGrupo2, @idAsignatura, @idPeriodo, 99992, 'Grupo Test Cruce Estudiante 2', 30, 0, 0, 0, @idDocenteValido);

    DECLARE @idDia UNIQUEIDENTIFIER;
    SELECT TOP 1 @idDia = id FROM dbo.Dia;

    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), @idGrupoValido, @idDia, '08:00:00', '10:00:00');

    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    VALUES (NEWID(), @idGrupo2, @idDia, '09:00:00', '11:00:00');

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
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

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
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

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
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;


------------------------------------------------------------------------------------------------------------------------
-- METODO: usp_generar_sesiones_grupo
------------------------------------------------------------------------------------------------------------------------
PRINT '';
PRINT '----------------------------------------------------------------------';
PRINT '  PRUEBAS DE: usp_generar_sesiones_grupo';
PRINT '----------------------------------------------------------------------';

PRINT '--- [CAMINO 1]: Happy Path (Generación Exitosa de Sesiones) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionGS1 UNIQUEIDENTIFIER = NEWID();

    EXEC [dbo].[usp_generar_sesiones_grupo]
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionGS1;

    IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @idGrupoValido)
        PRINT '>> RESULTADO: PASO (Sesiones generadas con exito)';
    ELSE
        PRINT '>> RESULTADO: FALLO (No se generaron sesiones)';
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

PRINT '--- [CAMINO 2]: Fallo por Grupo Inexistente ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionGS2 UNIQUEIDENTIFIER = NEWID();
    EXEC [dbo].[usp_generar_sesiones_grupo]
        @idGrupo = 'E71A5A90-5712-421F-B5C0-0192A0284F1E',
        @idCorrelacion = @idCorrelacionGS2;
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

PRINT '--- [CAMINO 3]: Fallo por Grupo sin Horarios ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionGS3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idGrupoSinHorarios UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@idGrupoSinHorarios, @idAsignatura, @idPeriodoValido, 9002, 'Grupo Sin Horarios', 30, 0, 0, 0, @idDocenteValido);

    EXEC [dbo].[usp_generar_sesiones_grupo]
        @idGrupo = @idGrupoSinHorarios,
        @idCorrelacion = @idCorrelacionGS3;
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;


------------------------------------------------------------------------------------------------------------------------
-- METODO: usp_registrar_asistencia_estudiante
------------------------------------------------------------------------------------------------------------------------
PRINT '';
PRINT '----------------------------------------------------------------------';
PRINT '  PRUEBAS DE: usp_registrar_asistencia_estudiante';
PRINT '----------------------------------------------------------------------';

PRINT '--- [CAMINO 1]: Happy Path (Registro Unitario Exitoso) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionRA1 UNIQUEIDENTIFIER = NEWID();
    
    -- Crear Estudiante de prueba
    DECLARE @idUsuarioEst UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, password, estado)
    VALUES (@idUsuarioEst, @tipoIdIdentificacion, 8881001, 'Estudiante', 'Test', 'Pedro', '', 'pedro.est@test.com', 1, 'Pass1234!', 1);
    DECLARE @idEstudiante UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@idEstudiante, @idUsuarioEst);

    -- Enrolar al grupo
    DECLARE @idEstudianteGrupo UNIQUEIDENTIFIER = NEWID();
    DECLARE @idEstadoActivo UNIQUEIDENTIFIER;
    SELECT TOP 1 @idEstadoActivo = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A';
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@idEstudianteGrupo, @idEstadoActivo, @idEstudiante, @idGrupoValido);

    -- Crear sesion de clase
    DECLARE @idSesion UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@idSesion, 'Clase 01', 1, 'COD123', 1, @idGrupoValido, GETDATE(), DATEADD(hour, 2, GETDATE()));

    DECLARE @idEstadoAsistencia UNIQUEIDENTIFIER;
    SELECT TOP 1 @idEstadoAsistencia = id FROM dbo.RazonCausa WHERE codigo = 'A';

    EXEC [dbo].[usp_registrar_asistencia_estudiante]
        @idEstudianteGrupo = @idEstudianteGrupo,
        @idGrupoSesion = @idSesion,
        @idEstadoAsistencia = @idEstadoAsistencia,
        @idCorrelacion = @idCorrelacionRA1;

    -- Verificar
    IF EXISTS (
        SELECT 1 FROM dbo.Asistencia a
        INNER JOIN dbo.DetalleAsistencia da ON a.id = da.asistencia
        WHERE a.estudianteGrupo = @idEstudianteGrupo AND a.sesion = @idSesion AND da.asistio = 1
    )
        PRINT '>> RESULTADO: PASO (Asistencia registrada unitaria)';
    ELSE
        PRINT '>> RESULTADO: FALLO (No se inserto la asistencia)';
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

PRINT '--- [CAMINO 2]: Happy Path (Actualización de Asistencia Preexistente) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionRA2 UNIQUEIDENTIFIER = NEWID();
    
    DECLARE @idUsuarioEst2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, password, estado)
    VALUES (@idUsuarioEst2, @tipoIdIdentificacion, 8881002, 'Estudiante', 'Test2', 'Ana', '', 'ana.est@test.com', 1, 'Pass1234!', 1);
    DECLARE @idEstudiante2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@idEstudiante2, @idUsuarioEst2);

    DECLARE @idEstudianteGrupo2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idEstadoActivo2 UNIQUEIDENTIFIER;
    SELECT TOP 1 @idEstadoActivo2 = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A';
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@idEstudianteGrupo2, @idEstadoActivo2, @idEstudiante2, @idGrupoValido);

    DECLARE @idSesion2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@idSesion2, 'Clase 02', 1, 'COD456', 1, @idGrupoValido, GETDATE(), DATEADD(hour, 2, GETDATE()));

    DECLARE @idEstadoA UNIQUEIDENTIFIER;
    DECLARE @idEstadoF UNIQUEIDENTIFIER;
    SELECT TOP 1 @idEstadoA = id FROM dbo.RazonCausa WHERE codigo = 'A';
    SELECT TOP 1 @idEstadoF = id FROM dbo.RazonCausa WHERE codigo = 'F';

    -- Registrar asistencia como Falto primero
    EXEC [dbo].[usp_registrar_asistencia_estudiante]
        @idEstudianteGrupo = @idEstudianteGrupo2,
        @idGrupoSesion = @idSesion2,
        @idEstadoAsistencia = @idEstadoF,
        @idCorrelacion = @idCorrelacionRA2;

    -- Actualizar a Asistió
    EXEC [dbo].[usp_registrar_asistencia_estudiante]
        @idEstudianteGrupo = @idEstudianteGrupo2,
        @idGrupoSesion = @idSesion2,
        @idEstadoAsistencia = @idEstadoA,
        @idCorrelacion = @idCorrelacionRA2;

    -- Verificar cambio a Asistio = 1
    IF EXISTS (
        SELECT 1 FROM dbo.Asistencia a
        INNER JOIN dbo.DetalleAsistencia da ON a.id = da.asistencia
        WHERE a.estudianteGrupo = @idEstudianteGrupo2 AND a.sesion = @idSesion2 AND da.asistio = 1
    )
        PRINT '>> RESULTADO: PASO (Asistencia actualizada unitaria)';
    ELSE
        PRINT '>> RESULTADO: FALLO (No se actualizo la asistencia)';
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

PRINT '--- [CAMINO 3]: Fallo por Matrícula Inexistente ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionRA3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idEstadoA3 UNIQUEIDENTIFIER;
    SELECT TOP 1 @idEstadoA3 = id FROM dbo.RazonCausa WHERE codigo = 'A';
    DECLARE @idSesion3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@idSesion3, 'Clase 03', 1, 'COD789', 1, @idGrupoValido, GETDATE(), DATEADD(hour, 2, GETDATE()));

    EXEC [dbo].[usp_registrar_asistencia_estudiante]
        @idEstudianteGrupo = 'A354AA62-581F-431A-BDC9-2917AB328EEA',
        @idGrupoSesion = @idSesion3,
        @idEstadoAsistencia = @idEstadoA3,
        @idCorrelacion = @idCorrelacionRA3;
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;


------------------------------------------------------------------------------------------------------------------------
-- METODO: usp_registrar_asistencia_estudiante_autonomo
------------------------------------------------------------------------------------------------------------------------
PRINT '';
PRINT '----------------------------------------------------------------------';
PRINT '  PRUEBAS DE: usp_registrar_asistencia_estudiante_autonomo';
PRINT '----------------------------------------------------------------------';

PRINT '--- [CAMINO 1]: Happy Path (Auto-registro exitoso con código correcto) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionAUT1 UNIQUEIDENTIFIER = NEWID();

    -- Crear Estudiante de prueba
    DECLARE @idUsuarioEst4 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, password, estado)
    VALUES (@idUsuarioEst4, @tipoIdIdentificacion, 8881004, 'Estudiante', 'Auto', 'Luis', '', 'luis.est@test.com', 1, 'Pass1234!', 1);
    DECLARE @idEstudiante4 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@idEstudiante4, @idUsuarioEst4);

    -- Enrolar al grupo
    DECLARE @idEstudianteGrupo4 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idEstadoActivo4 UNIQUEIDENTIFIER;
    SELECT TOP 1 @idEstadoActivo4 = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A';
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@idEstudianteGrupo4, @idEstadoActivo4, @idEstudiante4, @idGrupoValido);

    -- Crear sesion de clase con código
    DECLARE @idSesion4 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@idSesion4, 'Clase Auto 1', 1, 'SEC999', 1, @idGrupoValido, GETDATE(), DATEADD(hour, 2, GETDATE()));

    EXEC [dbo].[usp_registrar_asistencia_estudiante_autonomo]
        @idEstudiante = @idEstudiante4,
        @idSesion = @idSesion4,
        @codigoVerificacion = 'SEC999',
        @idCorrelacion = @idCorrelacionAUT1;

    -- Verificar
    IF EXISTS (
        SELECT 1 FROM dbo.Asistencia a
        INNER JOIN dbo.DetalleAsistencia da ON a.id = da.asistencia
        WHERE a.estudianteGrupo = @idEstudianteGrupo4 AND a.sesion = @idSesion4 AND da.asistio = 1
    )
        PRINT '>> RESULTADO: PASO (Auto-registro exitoso)';
    ELSE
        PRINT '>> RESULTADO: FALLO (No se auto-registro la asistencia)';
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

PRINT '--- [CAMINO 2]: Fallo por Código de Verificación Incorrecto ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionAUT2 UNIQUEIDENTIFIER = NEWID();

    -- Crear Estudiante de prueba
    DECLARE @idUsuarioEst5 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, password, estado)
    VALUES (@idUsuarioEst5, @tipoIdIdentificacion, 8881005, 'Estudiante', 'Auto2', 'Carlos', '', 'carlos.est@test.com', 1, 'Pass1234!', 1);
    DECLARE @idEstudiante5 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@idEstudiante5, @idUsuarioEst5);

    -- Enrolar al grupo
    DECLARE @idEstudianteGrupo5 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idEstadoActivo5 UNIQUEIDENTIFIER;
    SELECT TOP 1 @idEstadoActivo5 = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A';
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@idEstudianteGrupo5, @idEstadoActivo5, @idEstudiante5, @idGrupoValido);

    -- Crear sesion de clase con código
    DECLARE @idSesion5 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@idSesion5, 'Clase Auto 2', 1, 'SEC888', 1, @idGrupoValido, GETDATE(), DATEADD(hour, 2, GETDATE()));

    EXEC [dbo].[usp_registrar_asistencia_estudiante_autonomo]
        @idEstudiante = @idEstudiante5,
        @idSesion = @idSesion5,
        @codigoVerificacion = 'SECWRONG',
        @idCorrelacion = @idCorrelacionAUT2;
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

PRINT '--- [CAMINO 3]: Fallo por Estudiante No Matriculado en el Grupo de la Sesión ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionAUT3 UNIQUEIDENTIFIER = NEWID();

    -- Crear Estudiante de prueba (NO enrolado)
    DECLARE @idUsuarioEst6 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, password, estado)
    VALUES (@idUsuarioEst6, @tipoIdIdentificacion, 8881006, 'Estudiante', 'Auto3', 'Diana', '', 'diana.est@test.com', 1, 'Pass1234!', 1);
    DECLARE @idEstudiante6 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@idEstudiante6, @idUsuarioEst6);

    -- Crear sesion
    DECLARE @idSesion6 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@idSesion6, 'Clase Auto 3', 1, 'SEC777', 1, @idGrupoValido, GETDATE(), DATEADD(hour, 2, GETDATE()));

    EXEC [dbo].[usp_registrar_asistencia_estudiante_autonomo]
        @idEstudiante = @idEstudiante6,
        @idSesion = @idSesion6,
        @codigoVerificacion = 'SEC777',
        @idCorrelacion = @idCorrelacionAUT3;
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;


------------------------------------------------------------------------------------------------------------------------
-- METODO: usp_registrar_asistencias_sesion
------------------------------------------------------------------------------------------------------------------------
PRINT '';
PRINT '----------------------------------------------------------------------';
PRINT '  PRUEBAS DE: usp_registrar_asistencias_sesion';
PRINT '----------------------------------------------------------------------';

PRINT '--- [CAMINO 1]: Happy Path (Carga Masiva Exitosa con JSON) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionMAS1 UNIQUEIDENTIFIER = NEWID();

    -- Crear Estudiantes
    DECLARE @idUsuarioM1 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, password, estado)
    VALUES (@idUsuarioM1, @tipoIdIdentificacion, 8882001, 'EstM1', 'Test', 'Juan', '', 'juan.m1@test.com', 1, 'Pass1234!', 1);
    DECLARE @idEstudianteM1 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@idEstudianteM1, @idUsuarioM1);

    DECLARE @idUsuarioM2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, password, estado)
    VALUES (@idUsuarioM2, @tipoIdIdentificacion, 8882002, 'EstM2', 'Test', 'Sara', '', 'sara.m2@test.com', 1, 'Pass1234!', 1);
    DECLARE @idEstudianteM2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@idEstudianteM2, @idUsuarioM2);

    -- Enrolar a ambos al grupo
    DECLARE @idEstadoActivoM UNIQUEIDENTIFIER;
    SELECT TOP 1 @idEstadoActivoM = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A';
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (NEWID(), @idEstadoActivoM, @idEstudianteM1, @idGrupoValido);
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (NEWID(), @idEstadoActivoM, @idEstudianteM2, @idGrupoValido);

    -- Crear sesion
    DECLARE @idSesionM1 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@idSesionM1, 'Clase Masiva 1', 1, 'MAS001', 1, @idGrupoValido, GETDATE(), DATEADD(hour, 2, GETDATE()));

    -- Preparar JSON
    DECLARE @json NVARCHAR(MAX) = CONCAT('[',
        '{"idEstudiante":"', CAST(@idEstudianteM1 AS NVARCHAR(50)), '", "estado":"A"},',
        '{"idEstudiante":"', CAST(@idEstudianteM2 AS NVARCHAR(50)), '", "estado":"F"}',
        ']');

    EXEC [dbo].[usp_registrar_asistencias_sesion]
        @idSesion = @idSesionM1,
        @asistenciaJSON = @json,
        @idCorrelacion = @idCorrelacionMAS1;

    -- Verificar que ambos registros de asistencia existan
    IF EXISTS (
        SELECT 1 FROM dbo.Asistencia a
        INNER JOIN dbo.DetalleAsistencia da ON a.id = da.asistencia
        INNER JOIN dbo.EstudianteGrupo eg ON a.estudianteGrupo = eg.id
        WHERE a.sesion = @idSesionM1 AND eg.estudiante = @idEstudianteM1 AND da.asistio = 1
    ) AND EXISTS (
        SELECT 1 FROM dbo.Asistencia a
        INNER JOIN dbo.DetalleAsistencia da ON a.id = da.asistencia
        INNER JOIN dbo.EstudianteGrupo eg ON a.estudianteGrupo = eg.id
        WHERE a.sesion = @idSesionM1 AND eg.estudiante = @idEstudianteM2 AND da.asistio = 0
    )
        PRINT '>> RESULTADO: PASO (Carga masiva JSON exitosa)';
    ELSE
        PRINT '>> RESULTADO: FALLO (No se completo la carga masiva JSON)';
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

PRINT '--- [CAMINO 2]: Fallo por Estudiante No Matriculado en el Grupo de la Sesión ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionMAS2 UNIQUEIDENTIFIER = NEWID();

    -- Crear un estudiante (NO enrolado)
    DECLARE @idUsuarioM3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, password, estado)
    VALUES (@idUsuarioM3, @tipoIdIdentificacion, 8882003, 'EstM3', 'Test', 'Jose', '', 'jose.m3@test.com', 1, 'Pass1234!', 1);
    DECLARE @idEstudianteM3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@idEstudianteM3, @idUsuarioM3);

    -- Crear sesion
    DECLARE @idSesionM2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@idSesionM2, 'Clase Masiva 2', 1, 'MAS002', 1, @idGrupoValido, GETDATE(), DATEADD(hour, 2, GETDATE()));

    -- Preparar JSON con el estudiante no enrolado
    DECLARE @json2 NVARCHAR(MAX) = CONCAT('[',
        '{"idEstudiante":"', CAST(@idEstudianteM3 AS NVARCHAR(50)), '", "estado":"A"}',
        ']');

    EXEC [dbo].[usp_registrar_asistencias_sesion]
        @idSesion = @idSesionM2,
        @asistenciaJSON = @json2,
        @idCorrelacion = @idCorrelacionMAS2;
END;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

GO
PRINT '======================================================================';
PRINT '  SUITE DE PRUEBAS COMPLETAS: usp_registrar_docente_en_grupo_usuario_no_existente';
PRINT '======================================================================';

-- Obtener datos validos preexistentes para pruebas
DECLARE @tipoIdIdentificacion UNIQUEIDENTIFIER;
SELECT TOP 1 @tipoIdIdentificacion = id FROM [dbo].[TipoIdentificacion];

DECLARE @idGrupoValido UNIQUEIDENTIFIER;
SELECT TOP 1 @idGrupoValido = id FROM [dbo].[Grupo];

DECLARE @idPeriodoValido UNIQUEIDENTIFIER;
SELECT @idPeriodoValido = periodoAcademico FROM [dbo].[Grupo] WHERE id = @idGrupoValido;

IF @tipoIdIdentificacion IS NULL OR @idGrupoValido IS NULL OR @idPeriodoValido IS NULL
BEGIN
    PRINT 'ERROR CRITICO: No se encontraron registros base en TipoIdentificacion, Grupo o PeriodoAcademico. Deteniendo pruebas.';
    RETURN;
END

----------------------------------------------------------------------
-- CAMINO 1: Validacion de ID Correlacion Ausente/Vacio
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 1]: IdCorrelacion Ausente / Vacio (00000000-0000-0000-0000-000000000000) ---';
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
        @idCorrelacion = '00000000-0000-0000-0000-000000000000'; -- Invalido

    -- Nota: Al llamarse desde SSMS o script de prueba, el orquestador retorna un Result Set.
END;

----------------------------------------------------------------------
-- CAMINO 2: Happy Path (Usuario Nuevo + Docente Nuevo + Registro Exitoso)
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 2]: Happy Path (Usuario Nuevo -> Docente Nuevo -> Asignacion Exitosa) ---';
BEGIN TRANSACTION;
BEGIN
    -- Forzar vigencia del periodo academico para pasar la validacion
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

    -- Verificacion de Insercion
    IF EXISTS (
        SELECT 1 FROM dbo.Usuario u
        INNER JOIN dbo.Docente d ON u.id = d.usuario
        INNER JOIN dbo.Grupo g ON d.id = g.docente
        WHERE u.correo = @correoC2 AND g.id = @idGrupoValido
    )
        PRINT '>> RESULTADO: PASO (Docente creado y asignado al grupo exitosamente)';
    ELSE
        PRINT '>> RESULTADO: FALLO (No se encontro la asociacion completa)';
END;
ROLLBACK TRANSACTION;

----------------------------------------------------------------------
-- CAMINO 3: Usuario Preexistente (Sin Perfil Docente) -> Actualiza y Asigna
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

    -- Verificacion
    IF EXISTS (
        SELECT 1 FROM dbo.Usuario u
        INNER JOIN dbo.Docente d ON u.id = d.usuario
        INNER JOIN dbo.Grupo g ON d.id = g.docente
        WHERE u.correo = @correoC3 
          AND u.primerNombre = 'NUEVONOM' 
          AND u.primerApellido = 'NUEVOAP'
          AND g.id = @idGrupoValido
    )
        PRINT '>> RESULTADO: PASO (Usuario preexistente actualizado, perfil docente creado y asignado)';
    ELSE
        PRINT '>> RESULTADO: FALLO (La actualizacion o asignacion no se realizo correctamente)';
END;
ROLLBACK TRANSACTION;

----------------------------------------------------------------------
-- CAMINO 4: Fallo por Sincronizacion de Usuario (Campos Obligatorios NULL)
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 4]: Fallo en Sincronizar Usuario (Campos Nulos / Invalidos) ---';
BEGIN TRANSACTION;
BEGIN
    DECLARE @idCorrelacionC4 UNIQUEIDENTIFIER = NEWID();

    EXEC [dbo].[usp_registrar_docente_en_grupo_usuario_no_existente]
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
-- CAMINO 5: Fallo por Cruce de Horario del Docente
----------------------------------------------------------------------
PRINT '';
PRINT '--- [CAMINO 5]: Fallo por Cruce de Horario (Docente con clases coincidentes) ---';
BEGIN TRANSACTION;
BEGIN
    -- Forzar vigencia del periodo academico para pasar la validacion
    UPDATE dbo.PeriodoAcademico 
    SET fechaInicio = DATEADD(month, -1, GETDATE()), 
        fechaFin = DATEADD(month, 3, GETDATE()) 
    WHERE id = @idPeriodoValido;

    DECLARE @idCorrelacionC5 UNIQUEIDENTIFIER = NEWID();
    DECLARE @correoC5 NVARCHAR(255) = 'docente.cruce.c5@test.com';
    DECLARE @numeroIdC5 INT = 200000005;

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
    VALUES (@idGrupo2, @idAsignatura, @idPeriodo, 99991, 'Grupo Test Cruce 2', 30, 0, 0, 0, @idDocenteValido);

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

    -- Intentar asignar el mismo docente al Grupo 2 (Deberia fallar por cruce)
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
-- CAMINO 7: Captura de Excepcion en Bloque CATCH (Error Critico)
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
        @idGrupo = NULL, -- Causara error en la insercion/validacion interna al no admitir nulo
        @idCorrelacion = @idCorrelacionC7;
END;

GO
PRINT '======================================================================';
PRINT '  HABILITANDO CONSTRICCIONES DE CLAVE FORANEA POST-SEMBRADO';
PRINT '======================================================================';

ALTER TABLE dbo.PeriodoAcademico CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Facultad CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Docente CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Estudiante CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Programa CHECK CONSTRAINT ALL;
ALTER TABLE dbo.PlanEstudio CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Semestre CHECK CONSTRAINT ALL;
ALTER TABLE dbo.SemestrePlanEstudio CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Asignatura CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Grupo CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Horario CHECK CONSTRAINT ALL;
ALTER TABLE dbo.EstudianteGrupo CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Sesion CHECK CONSTRAINT ALL;
ALTER TABLE dbo.Asistencia CHECK CONSTRAINT ALL;
ALTER TABLE dbo.DetalleAsistencia CHECK CONSTRAINT ALL;
ALTER TABLE dbo.TipoPrograma CHECK CONSTRAINT ALL;
GO
