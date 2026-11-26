USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 13 (plan por lotes 2026-11-25): sesiones y horarios.
-- Fija el comportamiento de los internos del lote que no tenian prueba directa, antes de refactorizarlos. Los SP publicos del lote
-- siguen cubiertos por sus pruebas de dominio. Todo lo que escribe corre dentro de una transaccion revertida.
--   SKL13_R01_SESION_EXISTE        usp_validar_sesion_exista_por_id_interno: existe, inexistente (SES_001), nula (VAL_001) y
--                                  correlacion nula (CORR_001)
--   SKL13_R02_DOCENTE_TITULAR      usp_validar_docente_titular_sesion_interno: titular, otro docente (SEC_002), ejecutor nulo
--                                  (GEN_002), id que no es usuario (USU_001) y correlacion nula (CORR_001)
--   SKL13_R03_ESTUDIANTE_EN_SESION usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno: activo, ajeno (EST_004) y sesion
--                                  inexistente (SES_001)
--   SKL13_R04_HORARIOS_GRUPO       usp_validar_horarios_grupo_interno (con franjas, sin franjas GRUP_001, CORR_001) y
--                                  usp_guardar_horarios_grupo_interno (reemplaza las franjas; un dia desconocido se ignora)
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote13_caracterizacion';

DECLARE @s UNIQUEIDENTIFIER, @g UNIQUEIDENTIFIER, @docU UNIQUEIDENTIFIER, @est UNIQUEIDENTIFIER, @otroDoc UNIQUEIDENTIFIER;
SELECT TOP 1 @s = s.id, @g = s.grupo, @docU = d.usuario
FROM dbo.Sesion s INNER JOIN dbo.Grupo g ON g.id = s.grupo INNER JOIN dbo.Docente d ON d.id = g.docente
WHERE EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo e ON e.id = eg.estado AND e.codigo = 'A'
              WHERE eg.grupo = g.id)
  AND EXISTS (SELECT 1 FROM dbo.Horario h WHERE h.grupo = g.id)
ORDER BY s.id;
SELECT TOP 1 @est = eg.estudiante FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo e ON e.id = eg.estado AND e.codigo = 'A'
WHERE eg.grupo = @g ORDER BY eg.estudiante;
SELECT TOP 1 @otroDoc = d.usuario FROM dbo.Docente d
WHERE d.usuario <> @docU
  AND NOT EXISTS (SELECT 1 FROM dbo.Administrador a WHERE a.usuario = d.usuario)
  AND NOT EXISTS (SELECT 1 FROM dbo.Grupo g2 INNER JOIN dbo.Sesion s2 ON s2.grupo = g2.id WHERE s2.id = @s AND g2.docente = d.id)
ORDER BY d.usuario;
IF @s IS NULL OR @est IS NULL OR @otroDoc IS NULL
    THROW 56300, 'TEST FAILED: SKL13 faltan fixtures del seed (sesion con horario y estudiante activo, y otro docente).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER = NEWID();
    DECLARE @inexistente UNIQUEIDENTIFIER = '5C6A0000-0000-0000-0000-0000000000E9';
    DECLARE @sufijo NVARCHAR(60) = N'%Correlacion: ' + CONVERT(NVARCHAR(36), @corr);

    -- ================================================================= R01
    EXEC dbo.usp_validar_sesion_exista_por_id_interno @idSesion = @s, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mu <> N'' OR @mt <> N'' THROW 56310, 'TEST FAILED: SKL13_R01_SESION_EXISTE (existe)', 1;
    EXEC dbo.usp_validar_sesion_exista_por_id_interno @idSesion = @inexistente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=SES[_]001|%' OR @mt NOT LIKE @sufijo THROW 56311, 'TEST FAILED: SKL13_R01_SESION_EXISTE (SES_001)', 1;
    EXEC dbo.usp_validar_sesion_exista_por_id_interno @idSesion = NULL, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VAL[_]001|%' OR @mt NOT LIKE @sufijo THROW 56312, 'TEST FAILED: SKL13_R01_SESION_EXISTE (VAL_001)', 1;
    EXEC dbo.usp_validar_sesion_exista_por_id_interno @idSesion = @s, @idCorrelacion = NULL,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=CORR[_]001|%' THROW 56313, 'TEST FAILED: SKL13_R01_SESION_EXISTE (CORR_001)', 1;
    PRINT 'TEST_PASS:SKL13_R01_SESION_EXISTE';

    -- ================================================================= R02
    EXEC dbo.usp_validar_docente_titular_sesion_interno @idSesion = @s, @idUsuarioEjecutor = @docU, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 56320, 'TEST FAILED: SKL13_R02_DOCENTE_TITULAR (titular)', 1;
    EXEC dbo.usp_validar_docente_titular_sesion_interno @idSesion = @s, @idUsuarioEjecutor = @otroDoc, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=SEC[_]002|%' OR @mt NOT LIKE @sufijo THROW 56321, 'TEST FAILED: SKL13_R02_DOCENTE_TITULAR (SEC_002)', 1;
    EXEC dbo.usp_validar_docente_titular_sesion_interno @idSesion = @s, @idUsuarioEjecutor = NULL, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]002|%' OR @mt NOT LIKE @sufijo THROW 56322, 'TEST FAILED: SKL13_R02_DOCENTE_TITULAR (GEN_002)', 1;
    EXEC dbo.usp_validar_docente_titular_sesion_interno @idSesion = @s, @idUsuarioEjecutor = @inexistente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=USU[_]001|%' THROW 56323, 'TEST FAILED: SKL13_R02_DOCENTE_TITULAR (USU_001)', 1;
    EXEC dbo.usp_validar_docente_titular_sesion_interno @idSesion = @s, @idUsuarioEjecutor = @docU, @idCorrelacion = NULL,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=CORR[_]001|%' THROW 56324, 'TEST FAILED: SKL13_R02_DOCENTE_TITULAR (CORR_001)', 1;
    PRINT 'TEST_PASS:SKL13_R02_DOCENTE_TITULAR';

    -- ================================================================= R03
    EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno @idEstudiante = @est, @idSesion = @s, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 56330, 'TEST FAILED: SKL13_R03_ESTUDIANTE_EN_SESION (activo)', 1;
    EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno @idEstudiante = @inexistente, @idSesion = @s, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=EST[_]004|%' OR @mt NOT LIKE @sufijo THROW 56331, 'TEST FAILED: SKL13_R03_ESTUDIANTE_EN_SESION (EST_004)', 1;
    EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno @idEstudiante = @est, @idSesion = @inexistente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=SES[_]001|%' OR @mt NOT LIKE @sufijo THROW 56332, 'TEST FAILED: SKL13_R03_ESTUDIANTE_EN_SESION (SES_001)', 1;
    PRINT 'TEST_PASS:SKL13_R03_ESTUDIANTE_EN_SESION';

    -- ================================================================= R04
    EXEC dbo.usp_validar_horarios_grupo_interno @idGrupo = @g, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 56340, 'TEST FAILED: SKL13_R04_HORARIOS_GRUPO (con franjas)', 1;
    EXEC dbo.usp_validar_horarios_grupo_interno @idGrupo = @inexistente, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GRUP[_]001|%' OR @mt NOT LIKE @sufijo THROW 56341, 'TEST FAILED: SKL13_R04_HORARIOS_GRUPO (GRUP_001)', 1;
    EXEC dbo.usp_validar_horarios_grupo_interno @idGrupo = @g, @idCorrelacion = NULL,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=CORR[_]001|%' THROW 56342, 'TEST FAILED: SKL13_R04_HORARIOS_GRUPO (CORR_001)', 1;

    EXEC dbo.usp_guardar_horarios_grupo_interno @idGrupo = @g, @idCorrelacion = @corr,
         @horariosJSON = N'[{"codigoDia":" lu ","horaInicio":"07:00","horaFin":"09:00"},{"codigoDia":"MI","horaInicio":"10:00:00","horaFin":"12:00"},{"codigoDia":"ZZ","horaInicio":"07:00","horaFin":"08:00"}]',
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt <> N'' THROW 56343, 'TEST FAILED: SKL13_R04_HORARIOS_GRUPO (guardar)', 1;
    IF (SELECT COUNT(*) FROM dbo.Horario WHERE grupo = @g) <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.Horario h INNER JOIN dbo.Dia d ON d.id = h.dia
                      WHERE h.grupo = @g AND d.codigo = 'LU' AND h.horaInicio = '07:00' AND h.horaFin = '09:00')
       OR NOT EXISTS (SELECT 1 FROM dbo.Horario h INNER JOIN dbo.Dia d ON d.id = h.dia
                      WHERE h.grupo = @g AND d.codigo = 'MI' AND h.horaInicio = '10:00' AND h.horaFin = '12:00')
        THROW 56344, 'TEST FAILED: SKL13_R04_HORARIOS_GRUPO (franjas reemplazadas)', 1;
    EXEC dbo.usp_guardar_horarios_grupo_interno @idGrupo = @g, @idCorrelacion = NULL, @horariosJSON = N'[]',
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=CORR[_]001|%' OR (SELECT COUNT(*) FROM dbo.Horario WHERE grupo = @g) <> 2
        THROW 56345, 'TEST FAILED: SKL13_R04_HORARIOS_GRUPO (CORR_001 no borra)', 1;
    PRINT 'TEST_PASS:SKL13_R04_HORARIOS_GRUPO';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
PRINT 'TEST END: test_skills_lote13_caracterizacion';
GO
