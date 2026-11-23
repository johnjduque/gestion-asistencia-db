USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- DEC-078 (2026-11-20): en un grupo compartido el estudiante elige su programa al matricularse por QR (antes lo elegia el docente
-- para todos al abrir la ventana). Usa el fixture de B2NM: grupo G de la optativa en los programas A y B, docente titular T.
--   Q1  el titular abre la ventana SIN programa en el grupo compartido (antes EST_005);
--   Q2  la validacion publica devuelve los dos programas elegibles (JSON) y nada si la ventana fija programa;
--   Q3  registro publico con un programa ajeno al grupo: EST_006 sin crear usuario;
--   Q4  registro publico sin programa en el grupo compartido: MQR_008 sin crear usuario;
--   Q5  registro publico con el programa B: crea usuario, matricula y el vinculo EstudiantePrograma con B.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_dec078_matricula_programa_estudiante';
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @estadoActiva  NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA');
    DECLARE @estadoCerrada NVARCHAR(10) = dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_CERRADA');
    DECLARE @dominio NVARCHAR(255) = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
    DECLARE @periodoEnCurso UNIQUEIDENTIFIER = (SELECT TOP (1) id FROM dbo.uv_periodo_academico WHERE estado = 'ACTIVO' ORDER BY fechaInicio DESC, id);
    IF @periodoEnCurso IS NULL OR @dominio IS NULL OR @dominio = N''
        THROW 54201, 'TEST FAILED: DEC-078 fixture: falta un periodo en curso o el dominio de correo (semilla).', 1;
    -- La ventana de matricula exige un grupo vigente: G pasa al periodo en curso.
    UPDATE dbo.Grupo SET periodoAcademico = @periodoEnCurso WHERE id = @grupoG;
    UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoCerrada WHERE grupo = @grupoG AND estado = @estadoActiva;

    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX) NULL, mensajeTecnicoResultado NVARCHAR(MAX) NULL,
        estadoResultado BIT NOT NULL, idVentana UNIQUEIDENTIFIER NULL, fechaExpiracionUtc DATETIME2(0) NULL);
    CREATE TABLE #val (idGrupo UNIQUEIDENTIFIER NULL, nombreAsignatura NVARCHAR(200) NULL, nombreGrupo NVARCHAR(200) NULL,
        nombreDocente NVARCHAR(300) NULL, fechaExpiracionUtc DATETIME2(0) NULL, cupoDisponible INT NULL, programasElegibles NVARCHAR(MAX) NULL);
    CREATE TABLE #m (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX) NULL, mensajeTecnicoResultado NVARCHAR(MAX) NULL,
        estadoResultado BIT NOT NULL, idEstudiante UNIQUEIDENTIFIER NULL, idUsuario UNIQUEIDENTIFIER NULL, idGrupo UNIQUEIDENTIFIER NULL);

    -- Q1
    DECLARE @tok NVARCHAR(100) = CONCAT(N'dec078-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @hash VARBINARY(32) = HASHBYTES('SHA2_256', @tok);
    DECLARE @pin NCHAR(6) = RIGHT(CONCAT('000000', CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6))), 6);
    INSERT INTO #r EXEC dbo.usp_abrir_ventana_matricula_grupo @idGrupo = @grupoG, @tokenHash = @hash, @pin = @pin,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @uT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idVentana IS NOT NULL)
        THROW 54202, 'TEST FAILED: DEC-078 Q1 el titular debe abrir la ventana del grupo compartido sin elegir programa.', 1;

    -- Q2
    INSERT INTO #val EXEC dbo.usp_validar_token_matricula_publico @tokenHash = @hash, @pin = NULL, @idCorrelacion = @corr;
    DECLARE @json NVARCHAR(MAX) = (SELECT programasElegibles FROM #val);
    IF ISJSON(@json) <> 1
       OR (SELECT COUNT(*) FROM OPENJSON(@json) WITH (idPrograma UNIQUEIDENTIFIER '$.idPrograma', nombre NVARCHAR(100) '$.nombre')
           WHERE idPrograma IN (@progA, @progB) AND nombre IS NOT NULL) <> 2
        THROW 54203, 'TEST FAILED: DEC-078 Q2 la validacion debe devolver los dos programas del grupo como JSON.', 1;

    DECLARE @sufijo NVARCHAR(40) = REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '');
    DECLARE @numero INT = 1100000000 + ABS(CHECKSUM(NEWID()) % 400000000);
    DECLARE @pass NVARCHAR(500) = N'HashBackend_Dec078_1234567890';
    DECLARE @tipoCC2 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
    DECLARE @correo3 NVARCHAR(255) = CONCAT(N'dec078.q3.', @sufijo, @dominio);
    DECLARE @correo4 NVARCHAR(255) = CONCAT(N'dec078.q4.', @sufijo, @dominio);
    DECLARE @correo5 NVARCHAR(255) = CONCAT(N'dec078.q5.', @sufijo, @dominio);

    -- Q3
    DELETE FROM #m;
    DECLARE @ajeno UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #m EXEC dbo.usp_registrar_estudiante_por_token_publico @tokenHash = @hash, @pin = NULL,
        @idTipoIdentificacion = @tipoCC2, @numeroIdentificacion = @numero, @primerNombre = N'Ana', @segundoNombre = NULL,
        @primerApellido = N'Gomez', @segundoApellido = NULL, @correo = @correo3, @password = @pass, @idCorrelacion = @corr, @idPrograma = @ajeno;
    IF NOT EXISTS (SELECT 1 FROM #m WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'%EST_006%')
       OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = LOWER(@correo3))
        THROW 54204, 'TEST FAILED: DEC-078 Q3 un programa ajeno al grupo debe dar EST_006 sin crear el usuario.', 1;

    -- Q4
    DELETE FROM #m;
    INSERT INTO #m EXEC dbo.usp_registrar_estudiante_por_token_publico @tokenHash = @hash, @pin = NULL,
        @idTipoIdentificacion = @tipoCC2, @numeroIdentificacion = @numero, @primerNombre = N'Ana', @segundoNombre = NULL,
        @primerApellido = N'Gomez', @segundoApellido = NULL, @correo = @correo4, @password = @pass, @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #m WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'%MQR_008%')
       OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = LOWER(@correo4))
        THROW 54205, 'TEST FAILED: DEC-078 Q4 sin programa en el grupo compartido debe dar MQR_008 sin crear el usuario.', 1;

    -- Q5
    DELETE FROM #m;
    INSERT INTO #m EXEC dbo.usp_registrar_estudiante_por_token_publico @tokenHash = @hash, @pin = NULL,
        @idTipoIdentificacion = @tipoCC2, @numeroIdentificacion = @numero, @primerNombre = N'Ana', @segundoNombre = NULL,
        @primerApellido = N'Gomez', @segundoApellido = NULL, @correo = @correo5, @password = @pass, @idCorrelacion = @corr, @idPrograma = @progB;
    DECLARE @est UNIQUEIDENTIFIER = (SELECT idEstudiante FROM #m WHERE estadoResultado = 1);
    IF @est IS NULL
       OR NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @est AND programa = @progB)
       OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @est AND programa = @progA)
       OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE estudiante = @est AND grupo = @grupoG)
        THROW 54206, 'TEST FAILED: DEC-078 Q5 con el programa B debe matricular y vincular al estudiante solo con B.', 1;

    PRINT 'TEST_PASS:DEC078_MATRICULA_PROGRAMA_ESTUDIANTE';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @msg NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 54299, @msg, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
