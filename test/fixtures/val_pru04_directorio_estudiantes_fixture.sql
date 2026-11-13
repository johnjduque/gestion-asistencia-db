USE [gestionasistenciadb];
GO

/*
  VAL-PRU-04 (oleada 3): fixture de datos para las *IT de Java. NO es semilla de despliegue: solo la ejecuta
  test/prepare_java_integration_fixture.ps1 contra el contenedor Developer controlado (CI efimero o base aparte).
  CoreViewQueriesJpaParityIT.estudiantes_paginados_desde_vistas_sql_server_conservan_conteo_y_orden_en_tres_paginas
  recorre TRES paginas de 5 del directorio de estudiantes del primer ADMINISTRADOR y exige al menos 11 estudiantes
  distintos en su ambito (institucion). La semilla trae 2; este fixture agrega 12 estudiantes vinculados por
  EstudiantePrograma a un programa de esa institucion. No se matriculan en grupos: no cambian conteos de grupos,
  sesiones, asistencias, alertas ni KPIs que otras IT comparan.
  Idempotente: las filas llevan el correo it.valpru04.estudiante.NN@test.local y se borran antes de recrearse.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'gestionasistenciadb'
   OR CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) NOT LIKE N'%Developer Edition%'
    THROW 52212, 'BLOCKED - VAL-PRU-04 fixtures require gestionasistenciadb on SQL Server Developer Edition.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_parametro WHERE grupo = N'OPERACION' AND clave = N'AMBIENTE' AND UPPER(valor) IN (N'PRODUCCION', N'PROD', N'PRODUCTION'))
    THROW 52213, 'BLOCKED - OPERACION/AMBIENTE declares a production database.', 1;

DECLARE @emailPrefix NVARCHAR(40) = N'it.valpru04.estudiante.';
DECLARE @emailDomain NVARCHAR(20) = N'@test.local';
DECLARE @programa UNIQUEIDENTIFIER;
DECLARE @tipo UNIQUEIDENTIFIER;
DECLARE @correlation UNIQUEIDENTIFIER;
DECLARE @mensajeUsuario NVARCHAR(4000);
DECLARE @mensajeTecnico NVARCHAR(4000);
DECLARE @estado BIT;
DECLARE @correo NVARCHAR(100);
DECLARE @usuario UNIQUEIDENTIFIER;
DECLARE @numero INT;
DECLARE @segundoNombre NVARCHAR(50);
DECLARE @n INT = 1;

BEGIN TRANSACTION;

-- Limpieza idempotente de una preparacion anterior
DELETE ep FROM dbo.EstudiantePrograma ep
INNER JOIN dbo.Estudiante e ON e.id = ep.estudiante
INNER JOIN dbo.Usuario u ON u.id = e.usuario
WHERE u.correo LIKE @emailPrefix + N'%' + @emailDomain;
DELETE e FROM dbo.Estudiante e
INNER JOIN dbo.Usuario u ON u.id = e.usuario
WHERE u.correo LIKE @emailPrefix + N'%' + @emailDomain;
DELETE FROM dbo.Usuario WHERE correo LIKE @emailPrefix + N'%' + @emailDomain;

-- Programa de la institucion del primer administrador (el mismo actor que usan las IT de directorio)
SELECT TOP (1) @programa = p.id
FROM dbo.Programa p
INNER JOIN dbo.Facultad f ON f.id = p.facultad
WHERE f.institucion = (SELECT TOP (1) a.institucion FROM dbo.Administrador a ORDER BY a.usuario)
ORDER BY p.id;
SELECT TOP (1) @tipo = id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC';
IF @programa IS NULL OR @tipo IS NULL
    THROW 52306, 'VAL-PRU-04 fixture requires an administrator institution with a program and the CC identification type.', 1;

WHILE @n <= 12
BEGIN
    SET @correo = CONCAT(@emailPrefix, RIGHT(CONCAT(N'0', @n), 2), @emailDomain);
    SET @correlation = NEWID();
    SET @estado = NULL;
    SET @numero = 1810000000 + @n;
    SET @segundoNombre = CONCAT(N'Directorio', @n);
    -- Usuario por el nucleo interno de usuarios (el proveedor publico se retiro en VAL ROL-05, migracion 39)
    EXEC dbo.usp_sincronizar_usuario_interno
        @idTipoIdIdentificacion = @tipo, @numeroIdentificacion = @numero,
        @primerApellido = N'Fixture', @segundoApellido = N'ValPru04', @primerNombre = N'Estudiante',
        @segundoNombre = @segundoNombre,
        @correo = @correo, @password = N'HashBackend_ValPru04Fixture_NotASecret', @idCorrelacion = @correlation,
        @mensajeUsuarioResultado = @mensajeUsuario OUTPUT, @mensajeTecnicoResultado = @mensajeTecnico OUTPUT,
        @estadoResultado = @estado OUTPUT;
    IF ISNULL(@estado, 0) <> 1
        THROW 52307, 'VAL-PRU-04 fixture user creation was rejected by usp_sincronizar_usuario_interno.', 1;
    SELECT @usuario = id FROM dbo.Usuario WHERE correo = @correo;
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (NEWID(), @usuario);
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
    SELECT NEWID(), e.id, @programa FROM dbo.Estudiante e WHERE e.usuario = @usuario;
    SET @n = @n + 1;
END

IF (SELECT COUNT(*) FROM dbo.EstudiantePrograma ep
    INNER JOIN dbo.Estudiante e ON e.id = ep.estudiante
    INNER JOIN dbo.Usuario u ON u.id = e.usuario
    WHERE u.correo LIKE @emailPrefix + N'%' + @emailDomain) <> 12
    THROW 52308, 'VAL-PRU-04 fixture did not produce the 12 directory students.', 1;

COMMIT TRANSACTION;

SELECT CONCAT('TEST_FIXTURE_READY|valpru04|estudiantesDirectorio=',
    (SELECT COUNT(*) FROM dbo.Usuario WHERE correo LIKE @emailPrefix + N'%' + @emailDomain));
GO
