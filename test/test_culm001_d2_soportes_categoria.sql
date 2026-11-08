USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- CULM-001 D.2 (CONTRACT §3.2, HU014/HU015, TD-059/TD-060/TD-061): varios soportes por reclamo, categoria persistida con FK y
-- soporte obligatorio segun la categoria. Casos D2-01 .. D2-10, D2-12, D2-14, D2-15, D2-16 y permisos. D2-11 (concurrencia)
-- esta en test_lb004d_concurrency.ps1 y D2-13 / D-RB (up -> down -> up, orden de rollback) en test_culm001_d2.ps1.
-- Cada caso corre dentro de UNA transaccion con ROLLBACK final: no deja datos. Los soportes DRAFT se insertan directamente
-- (la subida real la hace el backend con usp_registrar_archivo_soporte; aqui solo importa su estado).
-- ============================================================================
IF OBJECT_ID('tempdb..#d2_expect') IS NOT NULL DROP PROCEDURE #d2_expect;
GO
CREATE PROCEDURE #d2_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: CULM001_D2_', @label);
        THROW 52400, @mensaje, 1;
    END
END;
GO
IF OBJECT_ID('tempdb..#d2_draft') IS NOT NULL DROP PROCEDURE #d2_draft;
GO
CREATE PROCEDURE #d2_draft @id UNIQUEIDENTIFIER, @usuario UNIQUEIDENTIFIER, @nombre NVARCHAR(250) = N'evidencia.pdf'
AS
BEGIN
    INSERT dbo.ArchivoSoporte (id, usuarioPropietario, nombreOriginal, tipoContenido, tamanioBytes, checksumSha256, estado,
                               fechaRegistroUtc, fechaCambioEstadoUtc, idCorrelacionRegistro)
    VALUES (@id, @usuario, @nombre, 'application/pdf', 1234, LOWER(CONVERT(CHAR(64), HASHBYTES('SHA2_256', CONVERT(VARCHAR(36), @id)), 2)),
            'DRAFT', SYSUTCDATETIME(), SYSUTCDATETIME(), NEWID());
END;
GO

DECLARE @codInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
DECLARE @group UNIQUEIDENTIFIER, @group2 UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER;
DECLARE @studentA UNIQUEIDENTIFIER, @studentC UNIQUEIDENTIFIER, @userA UNIQUEIDENTIFIER, @userC UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER, @userT2 UNIQUEIDENTIFIER;

SELECT TOP 1 @group = g.id, @teacher = g.docente, @studentA = eg.idEstudiante
FROM dbo.Grupo g
INNER JOIN dbo.uv_estudiante_grupo eg ON eg.idGrupo = g.id AND eg.codigoEstadoEstudiante = @codInscrita
ORDER BY g.id, eg.idEstudiante;
SELECT TOP 1 @group2 = eg.idGrupo, @studentC = eg.idEstudiante
FROM dbo.uv_estudiante_grupo eg
WHERE eg.idGrupo <> @group AND eg.codigoEstadoEstudiante = @codInscrita
  AND NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo y WHERE y.idGrupo = @group AND y.idEstudiante = eg.idEstudiante)
ORDER BY eg.idGrupo, eg.idEstudiante;
SELECT @userA = usuario FROM dbo.Estudiante WHERE id = @studentA;
SELECT @userC = usuario FROM dbo.Estudiante WHERE id = @studentC;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT TOP 1 @userT2 = d.usuario FROM dbo.Docente d WHERE d.id <> @teacher AND d.usuario <> @userT ORDER BY d.id;

IF @group IS NULL OR @group2 IS NULL OR @studentA IS NULL OR @studentC IS NULL OR @userA IS NULL OR @userC IS NULL OR @userT IS NULL OR @userT2 IS NULL
    THROW 52401, 'TEST FAILED: CULM001_D2 fixture faltante (semilla local).', 1;

DECLARE @finReciente DATETIME2(7) = DATEADD(DAY, -2, SYSUTCDATETIME());
DECLARE @finVencida DATETIME2(7) = DATEADD(DAY, -90, SYSUTCDATETIME());
DECLARE @s1 UNIQUEIDENTIFIER = NEWID(), @s2 UNIQUEIDENTIFIER = NEWID(), @s3 UNIQUEIDENTIFIER = NEWID(), @s4 UNIQUEIDENTIFIER = NEWID(),
        @s5 UNIQUEIDENTIFIER = NEWID(), @s6 UNIQUEIDENTIFIER = NEWID(), @sVenc UNIQUEIDENTIFIER = NEWID(), @sIdem UNIQUEIDENTIFIER = NEWID();
DECLARE @num INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);

DECLARE @corr UNIQUEIDENTIFIER, @ok BIT, @filasAntes INT, @filasDespues INT, @sol UNIQUEIDENTIFIER, @max INT, @json NVARCHAR(MAX);
DECLARE @f1 UNIQUEIDENTIFIER = NEWID(), @f2 UNIQUEIDENTIFIER = NEWID(), @f3 UNIQUEIDENTIFIER = NEWID(), @f4 UNIQUEIDENTIFIER = NEWID(),
        @fAjeno UNIQUEIDENTIFIER = NEWID(), @fOrf UNIQUEIDENTIFIER = NEWID(), @fInex UNIQUEIDENTIFIER = NEWID();
DECLARE @idCal UNIQUEIDENTIFIER = (SELECT id FROM dbo.CategoriaJustificacion WHERE codigo = N'CAL');
DECLARE @idMed UNIQUEIDENTIFIER = (SELECT id FROM dbo.CategoriaJustificacion WHERE codigo = N'MED');
DECLARE @nomMed NVARCHAR(50) = (SELECT nombre FROM dbo.CategoriaJustificacion WHERE codigo = N'MED');

CREATE TABLE #w3 (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX), mensajeTecnicoResultado NVARCHAR(MAX),
    estadoResultado INT NOT NULL, idSolicitudRevision UNIQUEIDENTIFIER NULL, totalSoportes INT NULL);
CREATE TABLE #w2 (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX), mensajeTecnicoResultado NVARCHAR(MAX),
    estadoResultado INT NOT NULL);
CREATE TABLE #r1 (idArchivoSoporte UNIQUEIDENTIFIER, estado VARCHAR(10), nombreOriginal NVARCHAR(250), tipoContenido VARCHAR(50),
    tamanioBytes BIGINT, checksumSha256 CHAR(64), fechaRegistroUtc DATETIME2(7), fechaAdjuncionUtc DATETIME2(7),
    idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, relacionAcceso VARCHAR(20));
CREATE TABLE #rd (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado NVARCHAR(5), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    asistio BIT, codigoRazonCausa NVARCHAR(5), nombreRazonCausa NVARCHAR(50),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7),
    codigoCategoria NVARCHAR(5), nombreCategoria NVARCHAR(50), soportesJson NVARCHAR(MAX));
CREATE TABLE #rl (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado NVARCHAR(5), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7), totalRegistros INT,
    codigoCategoria NVARCHAR(5), nombreCategoria NVARCHAR(50), soportesJson NVARCHAR(MAX));
CREATE TABLE #rr (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado NVARCHAR(5), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7), totalRegistros INT,
    codigoCategoria NVARCHAR(5), nombreCategoria NVARCHAR(50), totalSoportes INT);
CREATE TABLE #cfg (maximoSoportes INT, tamanioMaximoBytes BIGINT, tiposPermitidos NVARCHAR(500), limiteSubidasPorMinuto INT, diasLimiteJustificacion INT);

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin) VALUES
        (@s1,    N'QA D2 1',     @num,     LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finReciente), @finReciente),
        (@s2,    N'QA D2 2',     @num + 1, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finReciente), @finReciente),
        (@s3,    N'QA D2 3',     @num + 2, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finReciente), @finReciente),
        (@s4,    N'QA D2 4',     @num + 3, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finReciente), @finReciente),
        (@s5,    N'QA D2 5',     @num + 4, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finReciente), @finReciente),
        (@s6,    N'QA D2 6',     @num + 5, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finReciente), @finReciente),
        (@sVenc, N'QA D2 venc',  @num + 6, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finVencida),  @finVencida),
        (@sIdem, N'QA D2 idem',  @num + 7, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group, DATEADD(HOUR, -1, @finReciente), @finReciente);

    SET @max = dbo.ufn_obtener_parametro_int(NULL, 'ARCHIVOS', 'MAXIMO_SOPORTES_POR_RECLAMO');
    SET @ok = IIF(@max = 3 AND EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'ARCHIVO' AND clave = 'ESTADO_BORRADOR' AND valor = N'DRAFT'), 1, 0);
    EXEC #d2_expect 'SEMILLA_PARAMETROS', @ok;
    -- D.3: fila de edicion de ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO con rango [1, 10]
    SET @ok = IIF(EXISTS (SELECT 1 FROM dbo.CatalogoParametroEdicion e INNER JOIN dbo.CatalogoParametro p ON p.id = e.parametro
                          WHERE p.grupo = 'ARCHIVOS' AND p.clave = 'MAXIMO_SOPORTES_POR_RECLAMO' AND e.esEditable = 1
                            AND e.valorMinimo = 1 AND e.valorMaximo = 10), 1, 0);
    EXEC #d2_expect 'SEMILLA_EDICION_MAXIMO_SOPORTES_1_10', @ok;

    -- ---------------------------------------------------------------- D2-01 tres soportes propios, categoria CAL
    EXEC #d2_draft @f1, @userA, N'uno.pdf'; EXEC #d2_draft @f2, @userA, N'dos.pdf'; EXEC #d2_draft @f3, @userA, N'tres.pdf';
    SET @corr = NEWID();
    SET @json = CONCAT('["', CAST(@f1 AS CHAR(36)), '","', CAST(@f2 AS CHAR(36)), '","', CAST(@f3 AS CHAR(36)), '"]');
    INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @s1,
        @categoria = N'CAL', @justificacion = N'QA D2-01', @idsArchivoSoporte = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SELECT @sol = idSolicitudRevision FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 1 AND totalSoportes = 3;
    SET @ok = IIF(@sol IS NOT NULL
                  AND (SELECT COUNT(*) FROM dbo.ArchivoSoporte WHERE solicitudRevisionAsistencia = @sol AND estado = 'ATTACHED') = 3
                  AND EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @sol AND categoriaJustificacion = @idCal)
                  AND @@TRANCOUNT = 1, 1, 0);
    EXEC #d2_expect 'D2_01_TRES_SOPORTES', @ok;
    PRINT 'TEST_PASS:CULM001_D2_01_TRES_SOPORTES';

    -- ---------------------------------------------------------------- D2-02 cuatro soportes con maximo 3: REV_023 sin escrituras
    TRUNCATE TABLE #w3;
    EXEC #d2_draft @f4, @userA, N'cuatro.pdf';
    DECLARE @fx1 UNIQUEIDENTIFIER = NEWID(), @fx2 UNIQUEIDENTIFIER = NEWID(), @fx3 UNIQUEIDENTIFIER = NEWID();
    EXEC #d2_draft @fx1, @userA; EXEC #d2_draft @fx2, @userA; EXEC #d2_draft @fx3, @userA;
    SELECT @filasAntes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    SET @corr = NEWID();
    SET @json = CONCAT('["', CAST(@fx1 AS CHAR(36)), '","', CAST(@fx2 AS CHAR(36)), '","', CAST(@fx3 AS CHAR(36)), '","', CAST(@f4 AS CHAR(36)), '"]');
    INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @s2,
        @categoria = N'CAL', @justificacion = N'QA D2-02', @idsArchivoSoporte = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SELECT @filasDespues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 0 AND idSolicitudRevision IS NULL
                          AND mensajeUsuarioResultado LIKE N'Puedes adjuntar como m%ximo 3 soportes.')
                  AND @filasAntes = @filasDespues
                  AND (SELECT COUNT(*) FROM dbo.ArchivoSoporte WHERE id IN (@fx1, @fx2, @fx3, @f4) AND estado = 'DRAFT') = 4
                  AND @@TRANCOUNT = 1, 1, 0);
    EXEC #d2_expect 'D2_02_MAXIMO_REV_023', @ok;
    PRINT 'TEST_PASS:CULM001_D2_02_MAXIMO';

    -- ---------------------------------------------------------------- D2-03 GUID repetido: REV_024
    TRUNCATE TABLE #w3;
    SET @corr = NEWID();
    SET @json = CONCAT('["', CAST(@f4 AS CHAR(36)), '","', CAST(@f4 AS CHAR(36)), '"]');
    INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @s2,
        @categoria = N'CAL', @justificacion = N'QA D2-03', @idsArchivoSoporte = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 0
                          AND mensajeUsuarioResultado = N'Un mismo soporte no se puede adjuntar dos veces.')
                  AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @f4 AND estado = 'DRAFT'), 1, 0);
    EXEC #d2_expect 'D2_03_DUPLICADO_REV_024', @ok;
    PRINT 'TEST_PASS:CULM001_D2_03_DUPLICADO';

    -- ---------------------------------------------------------------- D2-04 soporte ajeno / ya ATTACHED / ORPHAN / inexistente: ARC_001, 0 escrituras
    EXEC #d2_draft @fAjeno, @userC;
    EXEC #d2_draft @fOrf, @userA;
    UPDATE dbo.ArchivoSoporte SET estado = 'ORPHAN' WHERE id = @fOrf;
    SELECT @filasAntes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    DECLARE @msgArc001 NVARCHAR(4000) = (SELECT TOP 1 contenido FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ARC_001');
    DECLARE @caso INT = 1, @malo UNIQUEIDENTIFIER;
    WHILE @caso <= 4
    BEGIN
        SET @malo = CASE @caso WHEN 1 THEN @fAjeno WHEN 2 THEN @f1 WHEN 3 THEN @fOrf ELSE @fInex END;
        TRUNCATE TABLE #w3;
        SET @corr = NEWID();
        SET @json = CONCAT('["', CAST(@f4 AS CHAR(36)), '","', CAST(@malo AS CHAR(36)), '"]');
        INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @s2,
            @categoria = N'CAL', @justificacion = N'QA D2-04', @idsArchivoSoporte = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
        SELECT @filasDespues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
        SET @ok = IIF(EXISTS (SELECT 1 FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 0 AND mensajeUsuarioResultado = @msgArc001)
                      AND @filasAntes = @filasDespues
                      AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @f4 AND estado = 'DRAFT' AND solicitudRevisionAsistencia IS NULL)
                      AND (@malo <> @f1 OR EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @f1 AND estado = 'ATTACHED' AND solicitudRevisionAsistencia = @sol)), 1, 0);
        EXEC #d2_expect 'D2_04_SOPORTE_NO_UTILIZABLE_ARC_001', @ok;
        SET @caso += 1;
    END
    PRINT 'TEST_PASS:CULM001_D2_04_SOPORTE_NO_UTILIZABLE';

    -- ---------------------------------------------------------------- D2-05 soporte obligatorio por categoria
    DECLARE @cod NVARCHAR(5), @oblig BIT;
    DECLARE @cats TABLE (n INT IDENTITY, cod NVARCHAR(5), oblig BIT);
    INSERT @cats (cod, oblig) VALUES (N'MED', 1), (N'ACA', 1), (N'LAB', 1), (N'CAL', 0), (N'FMA', 0), (N'OTR', 0);
    DECLARE @nCat INT = 1, @nomCat NVARCHAR(50), @sesCat UNIQUEIDENTIFIER;
    WHILE @nCat <= 6
    BEGIN
        SELECT @cod = cod, @oblig = oblig FROM @cats WHERE n = @nCat;
        SELECT @nomCat = nombre FROM dbo.CategoriaJustificacion WHERE codigo = @cod;
        SET @sesCat = CASE @nCat WHEN 1 THEN @s3 WHEN 2 THEN @s4 WHEN 3 THEN @s5 WHEN 4 THEN @s3 WHEN 5 THEN @s4 ELSE @s5 END;
        TRUNCATE TABLE #w3;
        SET @corr = NEWID();
        SELECT @filasAntes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
        INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA,
            @idSesion = @sesCat, @categoria = @cod, @justificacion = N'QA D2-05',
            @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
        SELECT @filasDespues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
        IF @oblig = 1
            SET @ok = IIF(EXISTS (SELECT 1 FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 0
                                  AND mensajeUsuarioResultado = CONCAT(N'La categoría «', @nomCat, N'» exige adjuntar al menos un soporte.'))
                          AND @filasAntes = @filasDespues
                          AND EXISTS (SELECT 1 FROM dbo.CategoriaJustificacion WHERE codigo = @cod AND requiereSoporte = 1), 1, 0);
        ELSE
            SET @ok = IIF(EXISTS (SELECT 1 FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 1 AND totalSoportes = 0)
                          AND @filasDespues = @filasAntes + 1
                          AND EXISTS (SELECT 1 FROM dbo.CategoriaJustificacion WHERE codigo = @cod AND requiereSoporte = 0), 1, 0);
        EXEC #d2_expect 'D2_05_SOPORTE_OBLIGATORIO_POR_CATEGORIA', @ok;
        SET @nCat += 1;
    END
    PRINT 'TEST_PASS:CULM001_D2_05_SOPORTE_OBLIGATORIO';

    -- ---------------------------------------------------------------- D2-06 categoria por codigo y por nombre: misma FK
    TRUNCATE TABLE #w3;
    DECLARE @fn1 UNIQUEIDENTIFIER = NEWID(), @fn2 UNIQUEIDENTIFIER = NEWID();
    EXEC #d2_draft @fn1, @userA; EXEC #d2_draft @fn2, @userA;
    SET @corr = NEWID();
    SET @json = CONCAT('["', CAST(@fn1 AS CHAR(36)), '"]');
    INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @s1,
        @categoria = @nomMed, @justificacion = N'QA D2-06 nombre', @idsArchivoSoporte = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    DECLARE @solNombre UNIQUEIDENTIFIER = (SELECT idSolicitudRevision FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 1);
    TRUNCATE TABLE #w3;
    SET @corr = NEWID();
    SET @json = CONCAT('["', CAST(@fn2 AS CHAR(36)), '"]');
    INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @s1,
        @categoria = N'MED', @justificacion = N'QA D2-06 codigo', @idsArchivoSoporte = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    DECLARE @solCodigo UNIQUEIDENTIFIER = (SELECT idSolicitudRevision FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 1);
    SET @ok = IIF(@solNombre IS NOT NULL AND @solCodigo IS NOT NULL
                  AND (SELECT categoriaJustificacion FROM dbo.SolicitudRevisionAsistencia WHERE id = @solNombre) = @idMed
                  AND (SELECT categoriaJustificacion FROM dbo.SolicitudRevisionAsistencia WHERE id = @solCodigo) = @idMed, 1, 0);
    EXEC #d2_expect 'D2_06_CATEGORIA_POR_CODIGO_Y_NOMBRE', @ok;
    PRINT 'TEST_PASS:CULM001_D2_06_CODIGO_Y_NOMBRE';

    -- ---------------------------------------------------------------- D2-07 categoria inexistente: REV_021
    TRUNCATE TABLE #w3;
    SET @corr = NEWID();
    SELECT @filasAntes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @s1,
        @categoria = N'ASISTENCIA', @justificacion = N'QA D2-07', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SELECT @filasDespues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 0
                          AND mensajeUsuarioResultado LIKE N'La categor%a de justificaci%n no es v%lida.')
                  AND @filasAntes = @filasDespues, 1, 0);
    EXEC #d2_expect 'D2_07_CATEGORIA_INEXISTENTE_REV_021', @ok;
    PRINT 'TEST_PASS:CULM001_D2_07_CATEGORIA_INEXISTENTE';

    -- ---------------------------------------------------------------- D2-08 v2: igual que v3 con un soporte; resultset de 4 columnas
    DECLARE @fv2 UNIQUEIDENTIFIER = NEWID();
    EXEC #d2_draft @fv2, @userA;
    SET @corr = NEWID();
    INSERT INTO #w2 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @s2,
        @categoria = N'MED', @justificacion = N'QA D2-08 sin', @idArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w2 WHERE idCorrelacion = @corr AND estadoResultado = 0 AND mensajeUsuarioResultado LIKE N'%exige adjuntar al menos un soporte.'), 1, 0);
    EXEC #d2_expect 'D2_08_V2_MED_SIN_SOPORTE', @ok;
    TRUNCATE TABLE #w2;
    SET @corr = NEWID();
    INSERT INTO #w2 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @s2,
        @categoria = N'MED', @justificacion = N'QA D2-08 con', @idArchivoSoporte = @fv2, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w2 WHERE idCorrelacion = @corr AND estadoResultado = 1)
                  AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte a INNER JOIN dbo.SolicitudRevisionAsistencia r ON r.id = a.solicitudRevisionAsistencia
                              WHERE a.id = @fv2 AND a.estado = 'ATTACHED' AND r.categoriaJustificacion = @idMed AND r.justificacionSolicitud = N'QA D2-08 con'), 1, 0);
    EXEC #d2_expect 'D2_08_V2_MED_CON_SOPORTE', @ok;
    PRINT 'TEST_PASS:CULM001_D2_08_V2';

    -- ---------------------------------------------------------------- D2-09 descarga de cada uno de los N soportes de D2-01
    DECLARE @dl TABLE (n INT IDENTITY, archivo UNIQUEIDENTIFIER);
    INSERT @dl (archivo) VALUES (@f1), (@f2), (@f3);
    DECLARE @k INT = 1, @af UNIQUEIDENTIFIER;
    WHILE @k <= 3
    BEGIN
        SELECT @af = archivo FROM @dl WHERE n = @k;
        TRUNCATE TABLE #r1; SET @corr = NEWID();
        INSERT INTO #r1 EXEC dbo.usp_consultar_archivo_soporte_autorizado @idArchivoSoporte = @af, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
        SET @ok = IIF(EXISTS (SELECT 1 FROM #r1 WHERE relacionAcceso = 'PROPIETARIO'), 1, 0);
        EXEC #d2_expect 'D2_09_DUENO_DESCARGA', @ok;
        TRUNCATE TABLE #r1; SET @corr = NEWID();
        INSERT INTO #r1 EXEC dbo.usp_consultar_archivo_soporte_autorizado @idArchivoSoporte = @af, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
        SET @ok = IIF(EXISTS (SELECT 1 FROM #r1 WHERE relacionAcceso = 'DOCENTE_TITULAR'), 1, 0);
        EXEC #d2_expect 'D2_09_DOCENTE_TITULAR_DESCARGA', @ok;
        TRUNCATE TABLE #r1; SET @corr = NEWID();
        INSERT INTO #r1 EXEC dbo.usp_consultar_archivo_soporte_autorizado @idArchivoSoporte = @af, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT2;
        INSERT INTO #r1 EXEC dbo.usp_consultar_archivo_soporte_autorizado @idArchivoSoporte = @af, @idCorrelacion = @corr, @idUsuarioEjecutor = @userC;
        SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #r1), 1, 0);
        EXEC #d2_expect 'D2_09_OTROS_NO_DESCARGAN', @ok;
        SET @k += 1;
    END
    PRINT 'TEST_PASS:CULM001_D2_09_DESCARGA_DE_CADA_SOPORTE';

    -- ---------------------------------------------------------------- D2-10 consultas: categoria, totalSoportes y soportesJson; sin literales (TD-061)
    SET @corr = NEWID();
    INSERT INTO #rr EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rr WHERE idSolicitudRevisionAsistencia = @sol AND codigoCategoria = N'CAL' AND totalSoportes = 3
                                              AND idArchivoSoporte IN (@f1, @f2, @f3))
                  AND (SELECT COUNT(*) FROM #rr WHERE idSolicitudRevisionAsistencia = @sol) = 1, 1, 0);
    EXEC #d2_expect 'D2_10_R2_CATEGORIA_Y_TOTAL', @ok;
    INSERT INTO #rd EXEC dbo.usp_consultar_detalle_solicitud_revision_docente @idSolicitud = @sol, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #rd) = 1
                  AND EXISTS (SELECT 1 FROM #rd WHERE codigoCategoria = N'CAL' AND ISJSON(soportesJson) = 1)
                  AND (SELECT COUNT(*) FROM #rd CROSS APPLY OPENJSON(soportesJson)) = 3
                  AND EXISTS (SELECT 1 FROM #rd CROSS APPLY OPENJSON(soportesJson) WITH (idArchivo UNIQUEIDENTIFIER '$.idArchivo', nombreOriginal NVARCHAR(250) '$.nombreOriginal',
                              tipoContenido VARCHAR(50) '$.tipoContenido', tamanioBytes BIGINT '$.tamanioBytes') j
                              WHERE j.idArchivo = @f1 AND j.nombreOriginal = N'uno.pdf' AND j.tipoContenido = 'application/pdf' AND j.tamanioBytes = 1234), 1, 0);
    EXEC #d2_expect 'D2_10_DETALLE_SOPORTES_JSON', @ok;
    INSERT INTO #rl EXEC dbo.usp_consultar_solicitudes_revision_estudiante @idUsuarioEjecutor = @userA, @idCorrelacion = @corr, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #rl WHERE idSolicitudRevisionAsistencia = @sol AND codigoCategoria = N'CAL' AND ISJSON(soportesJson) = 1)
                  AND (SELECT COUNT(*) FROM #rl WHERE idSolicitudRevisionAsistencia = @sol) = 1
                  AND (SELECT COUNT(*) FROM #rl CROSS APPLY OPENJSON(soportesJson) WHERE idSolicitudRevisionAsistencia = @sol) = 3, 1, 0);
    EXEC #d2_expect 'D2_10_LISTA_ESTUDIANTE_SOPORTES_JSON', @ok;
    -- Las columnas nuevas van AL FINAL (contrato posicional)
    SET @ok = IIF((SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_consultar_solicitudes_revision_docente'), NULL) d
                   WHERE (d.name = 'codigoCategoria' AND d.column_ordinal = 26) OR (d.name = 'nombreCategoria' AND d.column_ordinal = 27)
                      OR (d.name = 'totalSoportes' AND d.column_ordinal = 28) OR (d.name = 'totalRegistros' AND d.column_ordinal = 25)) = 4, 1, 0);
    EXEC #d2_expect 'D2_10_R2_COLUMNAS_AL_FINAL', @ok;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM sys.sql_modules m
                              WHERE m.object_id IN (OBJECT_ID(N'dbo.usp_consultar_solicitudes_revision_docente'), OBJECT_ID(N'dbo.usp_consultar_archivo_soporte_autorizado'),
                                                    OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision'), OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v2'),
                                                    OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v3'))
                                AND (m.definition LIKE N'%''ATTACHED''%' OR m.definition LIKE N'%''DRAFT''%' OR m.definition LIKE N'%''ORPHAN''%'))
                  AND OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision', N'P') IS NOT NULL
                  AND OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v3', N'P') IS NOT NULL, 1, 0);
    EXEC #d2_expect 'D2_10_SIN_LITERALES_DE_ESTADO_TD_061', @ok;
    PRINT 'TEST_PASS:CULM001_D2_10_CONSULTAS';

    -- ---------------------------------------------------------------- D2-12 plazo vencido con soportes: REV_020; siguen DRAFT
    TRUNCATE TABLE #w3;
    DECLARE @fp1 UNIQUEIDENTIFIER = NEWID(), @fp2 UNIQUEIDENTIFIER = NEWID();
    EXEC #d2_draft @fp1, @userA; EXEC #d2_draft @fp2, @userA;
    SET @corr = NEWID();
    SELECT @filasAntes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    SET @json = CONCAT('["', CAST(@fp1 AS CHAR(36)), '","', CAST(@fp2 AS CHAR(36)), '"]');
    INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @sVenc,
        @categoria = N'MED', @justificacion = N'QA D2-12', @idsArchivoSoporte = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SELECT @filasDespues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 0
                          AND mensajeUsuarioResultado LIKE N'El plazo para justificar esta inasistencia venci%')
                  AND @filasAntes = @filasDespues
                  AND (SELECT COUNT(*) FROM dbo.ArchivoSoporte WHERE id IN (@fp1, @fp2) AND estado = 'DRAFT') = 2, 1, 0);
    EXEC #d2_expect 'D2_12_PLAZO_VENCIDO_CON_SOPORTES', @ok;
    PRINT 'TEST_PASS:CULM001_D2_12_PLAZO_VENCIDO';

    -- ---------------------------------------------------------------- D2-15 v3: exito con 2 soportes, vence el plazo, reintento con la misma correlacion
    TRUNCATE TABLE #w3;
    DECLARE @fi1 UNIQUEIDENTIFIER = NEWID(), @fi2 UNIQUEIDENTIFIER = NEWID();
    EXEC #d2_draft @fi1, @userA; EXEC #d2_draft @fi2, @userA;
    SET @corr = NEWID();
    SET @json = CONCAT('["', CAST(@fi1 AS CHAR(36)), '","', CAST(@fi2 AS CHAR(36)), '"]');
    INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @sIdem,
        @categoria = N'MED', @justificacion = N'QA D2-15', @idsArchivoSoporte = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    DECLARE @solIdem UNIQUEIDENTIFIER = (SELECT idSolicitudRevision FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 1 AND totalSoportes = 2);
    SET @ok = IIF(@solIdem IS NOT NULL, 1, 0);
    EXEC #d2_expect 'D2_15_PRIMER_ENVIO', @ok;
    SELECT @filasAntes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    UPDATE dbo.Sesion SET fechaHoraInicio = DATEADD(DAY, -90, fechaHoraInicio), fechaHoraFin = DATEADD(DAY, -90, fechaHoraFin), procedenciaTemporal = procedenciaTemporal WHERE id = @sIdem;
    TRUNCATE TABLE #w3;
    INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @sIdem,
        @categoria = N'MED', @justificacion = N'QA D2-15', @idsArchivoSoporte = @json, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SELECT @filasDespues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 1 AND totalSoportes = 2 AND idSolicitudRevision = @solIdem)
                  AND @filasAntes = @filasDespues
                  AND (SELECT COUNT(*) FROM dbo.ArchivoSoporte WHERE solicitudRevisionAsistencia = @solIdem AND estado = 'ATTACHED') = 2, 1, 0);
    EXEC #d2_expect 'D2_15_REINTENTO_IDEMPOTENTE', @ok;
    PRINT 'TEST_PASS:CULM001_D2_15_REINTENTO_IDEMPOTENTE';

    -- ---------------------------------------------------------------- configuracion de reclamos
    SET @corr = NEWID();
    INSERT INTO #cfg EXEC dbo.usp_consultar_configuracion_reclamos @idUsuarioEjecutor = @userA, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #cfg) = 1
                  AND EXISTS (SELECT 1 FROM #cfg WHERE maximoSoportes = 3 AND tamanioMaximoBytes = dbo.ufn_obtener_parametro_int(NULL, 'ARCHIVO', 'TAMANIO_MAXIMO_BYTES')
                              AND limiteSubidasPorMinuto = dbo.ufn_obtener_parametro_int(NULL, 'ARCHIVOS', 'LIMITE_SUBIDAS_POR_MINUTO')
                              AND diasLimiteJustificacion = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION')
                              AND tiposPermitidos LIKE N'%application/pdf%' AND tiposPermitidos LIKE N'%image/png%' AND tiposPermitidos LIKE N'%image/jpeg%'), 1, 0);
    EXEC #d2_expect 'D2_CFG_CONFIGURACION_RECLAMOS', @ok;
    TRUNCATE TABLE #cfg;
    INSERT INTO #cfg EXEC dbo.usp_consultar_configuracion_reclamos @idUsuarioEjecutor = @userT, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #cfg) = 1, 1, 0);
    EXEC #d2_expect 'D2_CFG_DOCENTE_TAMBIEN', @ok;
    PRINT 'TEST_PASS:CULM001_D2_CFG_CONFIGURACION';

    -- ---------------------------------------------------------------- D2-16 ningun SP de D.2 usa INSERT ... EXEC
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM sys.sql_modules m
                              WHERE m.object_id IN (OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision'), OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v2'),
                                                    OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v3'))
                                AND (m.definition LIKE N'%INSERT INTO #%' OR m.definition LIKE N'%INSERT #%'
                                     OR m.definition LIKE N'%INSERT%EXEC dbo.usp_internal_radicar_solicitud_revision%'
                                     OR m.definition LIKE N'%INSERT%EXEC dbo.usp_radicar_solicitud_revision_asistencia_v%'))
                  AND OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision', N'P') IS NOT NULL, 1, 0);
    EXEC #d2_expect 'D2_16_SIN_INSERT_EXEC', @ok;
    PRINT 'TEST_PASS:CULM001_D2_16_SIN_INSERT_EXEC';

    -- ---------------------------------------------------------------- D2-14 (TD-059) borrar una solicitud con la FK habilitada
    -- Con el indice unico filtrado UX_ArchivoSoporte_Solicitud y la FK habilitada, cualquier DELETE sobre SolicitudRevisionAsistencia
    -- fallaba con Msg 8624 (8622 con pistas de join) del procesador de consultas. Se prueba con QUOTED_IDENTIFIER ON y OFF.
    DECLARE @solLimpia UNIQUEIDENTIFIER, @solLimpia2 UNIQUEIDENTIFIER, @errTd059 INT = 0, @errTd059b INT = 0;
    TRUNCATE TABLE #w3;
    SET @corr = NEWID();
    INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @s6,
        @categoria = N'OTR', @justificacion = N'QA D2-14', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SELECT @solLimpia = idSolicitudRevision FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 1;
    BEGIN TRY
        DECLARE @sqlTd059 NVARCHAR(400) = CONCAT(N'SET QUOTED_IDENTIFIER OFF; DELETE FROM dbo.SolicitudRevisionAsistencia WHERE id = ''', CONVERT(NVARCHAR(36), @solLimpia), N''';');
        EXEC (@sqlTd059);
    END TRY
    BEGIN CATCH
        SET @errTd059 = ERROR_NUMBER();
    END CATCH
    TRUNCATE TABLE #w3;
    SET @corr = NEWID();
    INSERT INTO #w3 EXEC dbo.usp_radicar_solicitud_revision_asistencia_v3 @idEstudiante = @studentA, @idSesion = @s6,
        @categoria = N'OTR', @justificacion = N'QA D2-14 b', @idsArchivoSoporte = NULL, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SELECT @solLimpia2 = idSolicitudRevision FROM #w3 WHERE idCorrelacion = @corr AND estadoResultado = 1;
    BEGIN TRY
        DELETE FROM dbo.SolicitudRevisionAsistencia WHERE id = @solLimpia2;
    END TRY
    BEGIN CATCH
        SET @errTd059b = ERROR_NUMBER();
    END CATCH
    SET @ok = IIF(@solLimpia IS NOT NULL AND @errTd059 = 0 AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @solLimpia)
                  AND @solLimpia2 IS NOT NULL AND @errTd059b = 0 AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @solLimpia2), 1, 0);
    EXEC #d2_expect 'D2_14_TD_059_DELETE_SIN_INDICE_FILTRADO', @ok;
    PRINT 'TEST_PASS:CULM001_D2_14_TD_059';

    -- ---------------------------------------------------------------- forma de las tablas, vista y permisos de minimo privilegio
    SET @ok = IIF(EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.ArchivoSoporte') AND name = 'IX_ArchivoSoporte_Solicitud' AND is_unique = 0 AND has_filter = 0)
                  AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.ArchivoSoporte') AND name = 'UX_ArchivoSoporte_Solicitud')
                  AND EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SolicitudRevisionAsistencia_CategoriaJustificacion'
                              AND parent_object_id = OBJECT_ID('dbo.SolicitudRevisionAsistencia') AND referenced_object_id = OBJECT_ID('dbo.CategoriaJustificacion'))
                  AND EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SolicitudRevisionAsistencia') AND name = 'IX_SolicitudRevisionAsistencia_Categoria')
                  AND COL_LENGTH('dbo.SolicitudRevisionAsistencia', 'categoriaJustificacion') IS NOT NULL
                  AND COL_LENGTH('dbo.CategoriaJustificacion', 'requiereSoporte') IS NOT NULL
                  AND (SELECT COUNT(*) FROM dbo.CategoriaJustificacion WHERE requiereSoporte = 1 AND codigo IN (N'MED', N'ACA', N'LAB')) = 3
                  AND (SELECT COUNT(*) FROM dbo.CategoriaJustificacion WHERE requiereSoporte = 1) = 3
                  AND OBJECT_ID(N'dbo.uv_soporte_reclamo', N'V') IS NOT NULL, 1, 0);
    EXEC #d2_expect 'D2_FORMA_TABLAS_INDICES_FK', @ok;
    SET @ok = IIF((SELECT COUNT(*) FROM dbo.uv_soporte_reclamo WHERE idSolicitud = @sol) = 3 AND (SELECT MAX(orden) FROM dbo.uv_soporte_reclamo WHERE idSolicitud = @sol) = 3
                  AND NOT EXISTS (SELECT 1 FROM dbo.uv_soporte_reclamo WHERE idArchivo = @fOrf), 1, 0);
    EXEC #d2_expect 'D2_VISTA_SOPORTE_RECLAMO', @ok;
    SET @ok = IIF(EXISTS (SELECT 1 FROM sys.database_permissions dp WHERE dp.major_id = OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v3') AND dp.permission_name = N'EXECUTE'
                            AND dp.state IN ('G', 'W') AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
                  AND EXISTS (SELECT 1 FROM sys.database_permissions dp WHERE dp.major_id = OBJECT_ID(N'dbo.usp_consultar_configuracion_reclamos') AND dp.permission_name = N'EXECUTE'
                            AND dp.state IN ('G', 'W') AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
                  AND NOT EXISTS (SELECT 1 FROM sys.database_permissions dp WHERE dp.major_id = OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision')
                            AND dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime'))
                  AND OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision', N'P') IS NOT NULL, 1, 0);
    EXEC #d2_expect 'D2_SEG_PERMISOS', @ok;
    PRINT 'TEST_PASS:CULM001_D2_SEG_PERMISOS';
END TRY
BEGIN CATCH
    DECLARE @msgFallo NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), ' (linea ', ERROR_LINE(), ')');
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT @msgFallo;
    THROW;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO
DROP PROCEDURE #d2_draft;
DROP PROCEDURE #d2_expect;
GO
