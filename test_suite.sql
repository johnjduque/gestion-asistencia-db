USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

PRINT '======================================================================';
PRINT '  SUITE DE PRUEBAS COMPLETA: usp_registrar_estudiante_en_grupo_usuario_no_existente';
PRINT '======================================================================';

----------------------------------------------------------------------
-- CONFIGURACIÓN PREVIA Y VARIABLES GENERALES
----------------------------------------------------------------------
DECLARE @tipoIdIdentificacion UNIQUEIDENTIFIER;
SELECT TOP 1 @tipoIdIdentificacion = id FROM [dbo].[tipoIdentificacion];

DECLARE @idGrupoValido UNIQUEIDENTIFIER;
SELECT TOP 1 @idGrupoValido = id FROM [dbo].[grupo];

DECLARE @idGrupoSinPrograma UNIQUEIDENTIFIER = NEWID();  -- Grupo existente pero sin trazabilidad a Programa

----------------------------------------------------------------------
-- CAMINO 1: Validación de ID Correlación Ausente/inválido (@estadoResultado = 0)
----------------------------------------------------------------------
PRINT '--- [CAMINO 1]: IdCorrelacion Ausente / Inválido ---';
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
        @idCorrelacion = '00000000-0000-0000-0000-000000000000'; -- Inválido/Vacío
END;

----------------------------------------------------------------------
-- CAMINO 2: Usuario Nuevo + Estudiante Nuevo + Registro Exitoso (HAPPY PATH PRINCIPAL)
----------------------------------------------------------------------
PRINT '--- [CAMINO 2]: Usuario Nuevo -> Registro Completo Exitoso ---';
BEGIN
    DECLARE @idCorrelacionC2 UNIQUEIDENTIFIER = NEWID();

    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = 100000002,
        @primerApellido = 'Lopez',
        @segundoApellido = 'Diaz',
        @primerNombre = 'Maria',
        @segundoNombre = 'Fernanda',
        @correo = 'maria.lopez.c2@test.com',
        @password = 'Pass1234!',
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionC2;
END;

----------------------------------------------------------------------
-- CAMINO 3: Usuario Preexistente (Actualización de Datos) + Estudiante Nuevo
----------------------------------------------------------------------
PRINT '--- [CAMINO 3]: Usuario Ya Existente -> Actualiza Datos y Enrola ---';
BEGIN
    DECLARE @idCorrelacionC3 UNIQUEIDENTIFIER = NEWID();

    -- Invocación 1 (Crea el usuario):
    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = 100000003,
        @primerApellido = 'Ramirez',
        @segundoApellido = 'Torres',
        @primerNombre = 'Carlos',
        @segundoNombre = 'Andres',
        @correo = 'carlos.ramirez.c3@test.com',
        @password = 'Pass1234!',
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionC3;

    -- Invocación 2 (Mismo Correo / Identificación - Reutiliza y Actualiza):
    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = 100000003,
        @primerApellido = 'Ramirez Modificado',
        @segundoApellido = 'Torres',
        @primerNombre = 'Carlos',
        @segundoNombre = 'Andres',
        @correo = 'carlos.ramirez.c3@test.com',
        @password = 'Pass1234!',
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionC3;
END;

----------------------------------------------------------------------
-- CAMINO 4: Error en Creación/Sincronización de Usuario (Datos Inválidos)
----------------------------------------------------------------------
PRINT '--- [CAMINO 4]: Fallo en Sincronizar Usuario (Ej: Correo/Campos nulos) ---';
BEGIN
    DECLARE @idCorrelacionC4 UNIQUEIDENTIFIER = NEWID();

    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = NULL, -- Provoca fallo en sincronización
        @primerApellido = NULL,
        @segundoApellido = NULL,
        @primerNombre = NULL,
        @segundoNombre = NULL,
        @correo = NULL,               -- Correo Nulo
        @password = NULL,
        @idGrupo = @idGrupoValido,
        @idCorrelacion = @idCorrelacionC4;
END;

----------------------------------------------------------------------
-- CAMINO 5: Grupo Sin Programa Asociado (Fallo Trazabilidad de Grupo)
----------------------------------------------------------------------
PRINT '--- [CAMINO 5]: Grupo Válido pero sin Programa Asociado ---';
BEGIN
    DECLARE @idCorrelacionC5 UNIQUEIDENTIFIER = NEWID();

    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = @tipoIdIdentificacion,
        @numeroIdentificacion = 100000005,
        @primerApellido = 'Soto',
        @segundoApellido = 'Mendoza',
        @primerNombre = 'Ana',
        @segundoNombre = 'Sofia',
        @correo = 'ana.soto.c5@test.com',
        @password = 'Pass1234!',
        @idGrupo = @idGrupoSinPrograma, -- Grupo sin jerarquía de Programa
        @idCorrelacion = @idCorrelacionC5;
END;

----------------------------------------------------------------------
-- CAMINO 6: Captura de Excepción en Bloque CATCH (Error Crítico / Parámetros no válidos)
----------------------------------------------------------------------
PRINT '--- [CAMINO 6]: Captura por CATCH (Error Crítico Inesperado) ---';
BEGIN
    DECLARE @idCorrelacionC6 UNIQUEIDENTIFIER = NEWID();

    -- Forzando un error sintáctico o de datos incompatible si aplica
    EXEC [dbo].[usp_registrar_estudiante_en_grupo_usuario_no_existente]
        @tipoIdIdentificacion = '00000000-0000-0000-0000-000000000000',
        @numeroIdentificacion = 999999999,
        @primerApellido = 'TestCatch',
        @segundoApellido = 'TestCatch',
        @primerNombre = 'TestCatch',
        @segundoNombre = 'TestCatch',
        @correo = 'test.catch@test.com',
        @password = 'Pass1234!',
        @idGrupo = NULL, -- Provoca fallo crítico
        @idCorrelacion = @idCorrelacionC6;
END;
GO
