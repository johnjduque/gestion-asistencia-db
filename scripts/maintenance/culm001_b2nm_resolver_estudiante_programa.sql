USE [gestionasistenciadb];
GO
-- CULM-001 B2NM (CONTRACT §2.4 punto 4): resuelve una fila AMBIGUO / SIN_INTERSECCION del reporte
-- zz_reporte_culm001_b2nm_estudiante_programa con una de dos opciones explicitas y registra RESUELTO.
--   @opcion = 'VINCULAR': crea EstudiantePrograma(estudiante, @idPrograma); @idPrograma debe ser un programa del grupo.
--   @opcion = 'ASOCIAR' : asocia la asignatura del grupo al plan @idPlanEstudio (semestre @semestreNumero, caracter @codigoCaracter)
--                         ejecutando usp_asociar_asignatura_plan con el coordinador @idUsuarioCoordinador (flujo §4.3.1).
-- Rellene las variables y ejecute; no toca nada si la fila no existe o ya esta resuelta.
SET NOCOUNT ON; SET XACT_ABORT ON;
DECLARE @idEstudiante UNIQUEIDENTIFIER = NULL, @idGrupo UNIQUEIDENTIFIER = NULL, @opcion NVARCHAR(10) = N'VINCULAR';
DECLARE @idPrograma UNIQUEIDENTIFIER = NULL;
DECLARE @idPlanEstudio UNIQUEIDENTIFIER = NULL, @semestreNumero INT = NULL, @codigoCaracter NVARCHAR(3) = NULL, @idUsuarioCoordinador UNIQUEIDENTIFIER = NULL;
IF @idEstudiante IS NULL OR @idGrupo IS NULL THROW 52940, 'Indique @idEstudiante y @idGrupo.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.zz_reporte_culm001_b2nm_estudiante_programa
               WHERE estudiante = @idEstudiante AND (grupo = @idGrupo OR tipo = N'AMBIGUO') AND tipo IN (N'AMBIGUO', N'SIN_INTERSECCION'))
    THROW 52941, 'No hay una fila pendiente del reporte para ese estudiante y grupo.', 1;
BEGIN TRANSACTION;
IF @opcion = N'VINCULAR'
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) WHERE idPrograma = @idPrograma) THROW 52942, '@idPrograma no es un programa del grupo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @idEstudiante AND programa = @idPrograma)
        INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @idEstudiante, @idPrograma);
END
ELSE IF @opcion = N'ASOCIAR'
BEGIN
    DECLARE @idAsignatura UNIQUEIDENTIFIER = (SELECT asignatura FROM dbo.Grupo WHERE id = @idGrupo), @c UNIQUEIDENTIFIER = NEWID();
    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mu NVARCHAR(4000), mt NVARCHAR(4000), estado BIT);
    INSERT INTO #r EXEC dbo.usp_asociar_asignatura_plan @idAsignatura = @idAsignatura, @idPlanEstudio = @idPlanEstudio, @semestreNumero = @semestreNumero,
        @codigoCaracter = @codigoCaracter, @idCorrelacion = @c, @idUsuarioEjecutor = @idUsuarioCoordinador;
    IF EXISTS (SELECT 1 FROM #r WHERE estado = 0) THROW 52943, 'usp_asociar_asignatura_plan rechazo la asociacion.', 1;
END
ELSE THROW 52944, '@opcion debe ser VINCULAR o ASOCIAR.', 1;
INSERT INTO dbo.zz_reporte_culm001_b2nm_estudiante_programa (id, estudiante, grupo, programa, tipo, detalle)
VALUES (NEWID(), @idEstudiante, @idGrupo, @idPrograma, N'RESUELTO', CONCAT(N'Resuelto con la opcion ', @opcion));
COMMIT TRANSACTION;
GO
