USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- Auditoria de BD (2026-11-22): A-2, A-1, M-1, M-3, M-6, M-7 y M-11 (fixture de asignatura compartida de B2NM; todo en una transaccion revertida).
--   AUDBD_A2_01_CUPO_INFERIOR_RECHAZADO      usp_actualizar_grupo rechaza un cupo menor que las matriculas activas y no cambia el grupo
--   AUDBD_A2_02_ACTUALIZA_Y_BLOQUEA_CUPO     un cupo valido se aplica; el SP es transaccional (XACT_ABORT ON, transaccion propia) y bloquea la fila del
--                                            grupo y sus matriculas activas con UPDLOCK, HOLDLOCK ANTES de contarlas y de actualizar. La prueba no puede
--                                            abrir una segunda sesion, asi que la garantia de no-carrera se comprueba en el orden de las sentencias
--                                            del SP (bloqueo -> conteo -> UPDATE -> COMMIT) y en el resultado funcional
--   AUDBD_A1_01_DECANO_SOLO_SU_FACULTAD      decano: cuenta de su facultad si; cuenta fuera de su ambito, SEC_002
--   AUDBD_A1_02_COORDINADOR_SOLO_SU_PROGRAMA coordinador: cuentas de su programa si; de otro programa o sin vinculo, SEC_002 (destino inexistente tambien)
--   AUDBD_A1_03_ADMINISTRADOR_TODA_CUENTA    administrador: cualquier cuenta; destino inexistente: VCE_007 (la validacion de existencia sigue en pie)
--   AUDBD_M1_01_INDICES_FK                   28 indices IX_<Tabla>_<columna> existen con la columna lider esperada
--   AUDBD_M3_01_SIN_GUID_VACIO_LITERAL       ufn_obtener_detalle_error y ufn_obtener_mensaje_desde_plantilla no llevan el GUID vacio literal y siguen resolviendo el defecto
--   AUDBD_M6_01_XACT_ABORT_ESCRITURA         7 SP de escritura declaran SET XACT_ABORT ON y conservan su manejo de XACT_STATE() = -1; usp_registrar_o_actualizar_plan_estudio queda sin el (su contrato de savepoint en la transaccion del llamador, PLAN_PUBLIC_ROLLBACK_SAVEPOINT, lo exige)
--   AUDBD_M7_01_FUNCION_RETIRADA             ufn_obtener_estado_estudiante_grupo ya no existe
--   AUDBD_M11_01_MENSAJES_CON_TILDES         14 mensajes de usuario con tilde y sin la forma anterior; VAL_APP_068 tecnico tambien
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_auditoria_bd_2026_11_22';
DROP TABLE IF EXISTS #r; DROP TABLE IF EXISTS #re; DROP TABLE IF EXISTS #idx; DROP TABLE IF EXISTS #cod;
BEGIN TRANSACTION;
BEGIN TRY
:r /tmp/test/fixtures/culm001_b2nm_asignatura_compartida.sql
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @msg NVARCHAR(4000);
    CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(4000) NULL, mensajeTecnicoResultado NVARCHAR(4000) NULL, estadoResultado BIT NOT NULL);
    CREATE TABLE #re (idUsuario UNIQUEIDENTIFIER NULL);

    -- ------------------------------------------------------------------ A-2
    DECLARE @codG INT = (SELECT codigo FROM dbo.Grupo WHERE id = @grupoG);
    UPDATE dbo.Grupo SET programaResponsable = @progA WHERE id = @grupoG;   -- responsable = A (coordinador CA)
    IF (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @grupoG AND estado = @estA) <> 3
        THROW 55501, 'TEST FAILED: AUDBD fixture: el grupo debe tener 3 matriculas activas.', 1;
    INSERT #r EXEC dbo.usp_actualizar_grupo @idGrupo = @grupoG, @codigo = @codG, @nombre = N'AUDBD-G', @idDocente = @docT, @cupoMaximo = 2, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=ERR[_]CUPO[_]INFERIOR[_]OCUPACION%')
       OR (SELECT cantidadEstudiantes FROM dbo.Grupo WHERE id = @grupoG) <> 30
       OR (SELECT nombre FROM dbo.Grupo WHERE id = @grupoG) <> N'B2NM-G'
        THROW 55502, 'TEST FAILED: AUDBD_A2_01 un cupo menor que las matriculas activas debe rechazarse (ERR_CUPO_INFERIOR_OCUPACION) sin cambiar el grupo.', 1;
    PRINT 'TEST_PASS:AUDBD_A2_01_CUPO_INFERIOR_RECHAZADO';

    TRUNCATE TABLE #r;
    INSERT #r EXEC dbo.usp_actualizar_grupo @idGrupo = @grupoG, @codigo = @codG, @nombre = N'AUDBD-G', @idDocente = @docT, @cupoMaximo = 3, @idCorrelacion = @c, @idUsuarioEjecutor = @uCA;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
       OR (SELECT cantidadEstudiantes FROM dbo.Grupo WHERE id = @grupoG) <> 3
       OR (SELECT nombre FROM dbo.Grupo WHERE id = @grupoG) <> N'AUDBD-G'
        THROW 55503, 'TEST FAILED: AUDBD_A2_02 un cupo igual a las matriculas activas debe aplicarse.', 1;
    DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_actualizar_grupo'));
    DECLARE @pLockGrupo INT = CHARINDEX(N'dbo.Grupo g WITH (UPDLOCK, HOLDLOCK)', @def);
    DECLARE @pLockMat INT = CHARINDEX(N'dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)', @def);
    DECLARE @pBegin INT = CHARINDEX(N'BEGIN TRANSACTION', @def);
    DECLARE @pUpdate INT = CHARINDEX(N'UPDATE dbo.Grupo', @def);
    DECLARE @pCommit INT = CHARINDEX(N'COMMIT TRANSACTION', @def);
    IF CHARINDEX(N'SET XACT_ABORT ON', @def) = 0
       OR @pBegin = 0 OR @pLockGrupo <= @pBegin OR @pLockMat <= @pLockGrupo OR @pUpdate <= @pLockMat OR @pCommit <= @pUpdate
       OR CHARINDEX(N'ROLLBACK TRANSACTION', @def, @pCommit) = 0
        THROW 55504, 'TEST FAILED: AUDBD_A2_02 usp_actualizar_grupo debe abrir transaccion, bloquear grupo y matriculas (UPDLOCK, HOLDLOCK) antes del UPDATE y confirmar/revertir al final.', 1;
    IF @@TRANCOUNT <> 1
        THROW 55505, 'TEST FAILED: AUDBD_A2_02 el SP no debe cerrar ni dejar abierta la transaccion externa.', 1;
    PRINT 'TEST_PASS:AUDBD_A2_02_ACTUALIZA_Y_BLOQUEA_CUPO';

    -- ------------------------------------------------------------------ A-1 (cuentas pendientes de activacion)
    UPDATE dbo.Usuario SET correoConfirmado = 0 WHERE id IN (@uT, @uEA, @uEB, @uE0);
    DECLARE @fantasma UNIQUEIDENTIFIER = NEWID();
    -- decano de la facultad: docente (A y B) y estudiante de A si; el estudiante sin programa no
    INSERT #re EXEC dbo.usp_consultar_reenvio_activacion_cuenta @idUsuario = @uT, @idUsuarioEjecutor = @uDec, @idCorrelacion = @c;
    INSERT #re EXEC dbo.usp_consultar_reenvio_activacion_cuenta @idUsuario = @uEA, @idUsuarioEjecutor = @uDec, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #re) <> 2
        THROW 55511, 'TEST FAILED: AUDBD_A1_01 el decano debe poder consultar cuentas de su facultad.', 1;
    SET @msg = NULL;
    BEGIN TRY
        INSERT #re EXEC dbo.usp_consultar_reenvio_activacion_cuenta @idUsuario = @uE0, @idUsuarioEjecutor = @uDec, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
    END CATCH
    IF XACT_STATE() = -1 THROW 55512, 'TEST FAILED: AUDBD_A1_01 la transaccion quedo condenada.', 1;
    IF @msg IS NULL OR @msg NOT LIKE N'DBCODE=SEC[_]002%' OR (SELECT COUNT(*) FROM #re) <> 2
        THROW 55513, 'TEST FAILED: AUDBD_A1_01 el decano no debe consultar una cuenta fuera de su facultad (SEC_002).', 1;
    PRINT 'TEST_PASS:AUDBD_A1_01_DECANO_SOLO_SU_FACULTAD';

    -- coordinador del programa A: docente y estudiante de A si; estudiante de B, sin vinculo e inexistente: SEC_002
    DELETE FROM #re;
    INSERT #re EXEC dbo.usp_consultar_reenvio_activacion_cuenta @idUsuario = @uT, @idUsuarioEjecutor = @uCA, @idCorrelacion = @c;
    INSERT #re EXEC dbo.usp_consultar_reenvio_activacion_cuenta @idUsuario = @uEA, @idUsuarioEjecutor = @uCA, @idCorrelacion = @c;
    INSERT #re EXEC dbo.usp_consultar_reenvio_activacion_cuenta @idUsuario = @uEB, @idUsuarioEjecutor = @uCB, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #re) <> 3
        THROW 55521, 'TEST FAILED: AUDBD_A1_02 cada coordinador debe poder consultar las cuentas de su programa.', 1;
    DECLARE @i INT = 1, @destino UNIQUEIDENTIFIER, @ejecutor UNIQUEIDENTIFIER;
    WHILE @i <= 4
    BEGIN
        SELECT @destino = CHOOSE(@i, @uEB, @uEA, @uE0, @fantasma), @ejecutor = CHOOSE(@i, @uCA, @uCB, @uCA, @uCA);
        SET @msg = NULL;
        BEGIN TRY
            INSERT #re EXEC dbo.usp_consultar_reenvio_activacion_cuenta @idUsuario = @destino, @idUsuarioEjecutor = @ejecutor, @idCorrelacion = @c;
        END TRY
        BEGIN CATCH
            SET @msg = ERROR_MESSAGE();
        END CATCH
        IF XACT_STATE() = -1 THROW 55522, 'TEST FAILED: AUDBD_A1_02 la transaccion quedo condenada.', 1;
        IF @msg IS NULL OR @msg NOT LIKE N'DBCODE=SEC[_]002%'
            THROW 55523, 'TEST FAILED: AUDBD_A1_02 un coordinador no debe consultar cuentas de otro programa, sin vinculo o inexistentes (SEC_002).', 1;
        SET @i += 1;
    END
    IF (SELECT COUNT(*) FROM #re) <> 3
        THROW 55524, 'TEST FAILED: AUDBD_A1_02 los rechazos no deben devolver filas.', 1;
    PRINT 'TEST_PASS:AUDBD_A1_02_COORDINADOR_SOLO_SU_PROGRAMA';

    -- administrador: cualquier cuenta; inexistente sigue siendo VCE_007
    DELETE FROM #re;
    INSERT #re EXEC dbo.usp_consultar_reenvio_activacion_cuenta @idUsuario = @uE0, @idUsuarioEjecutor = @uAdm, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #re WHERE idUsuario = @uE0) <> 1
        THROW 55531, 'TEST FAILED: AUDBD_A1_03 el administrador debe consultar cualquier cuenta pendiente.', 1;
    SET @msg = NULL;
    BEGIN TRY
        INSERT #re EXEC dbo.usp_consultar_reenvio_activacion_cuenta @idUsuario = @fantasma, @idUsuarioEjecutor = @uAdm, @idCorrelacion = @c;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
    END CATCH
    IF XACT_STATE() = -1 THROW 55532, 'TEST FAILED: AUDBD_A1_03 la transaccion quedo condenada.', 1;
    IF @msg IS NULL OR @msg NOT LIKE N'DBCODE=VCE[_]007%'
        THROW 55533, 'TEST FAILED: AUDBD_A1_03 un destino inexistente consultado por el administrador debe responder VCE_007.', 1;
    PRINT 'TEST_PASS:AUDBD_A1_03_ADMINISTRADOR_TODA_CUENTA';

    -- ------------------------------------------------------------------ M-1
    SELECT v.tabla, v.nombre, v.columna INTO #idx FROM (VALUES
        (N'Grupo', N'IX_Grupo_docente', N'docente'),
        (N'Grupo', N'IX_Grupo_periodoAcademico', N'periodoAcademico'),
        (N'Grupo', N'IX_Grupo_programaResponsable', N'programaResponsable'),
        (N'Horario', N'IX_Horario_grupo', N'grupo'),
        (N'Horario', N'IX_Horario_dia', N'dia'),
        (N'DocentePrograma', N'IX_DocentePrograma_programa', N'programa'),
        (N'EstudiantePrograma', N'IX_EstudiantePrograma_programa', N'programa'),
        (N'Programa', N'IX_Programa_facultad', N'facultad'),
        (N'Programa', N'IX_Programa_coordinador', N'coordinador'),
        (N'PlanEstudio', N'IX_PlanEstudio_programa', N'programa'),
        (N'SemestrePlanEstudio', N'IX_SemestrePlanEstudio_planEstudio', N'planEstudio'),
        (N'Coordinador', N'IX_Coordinador_facultad', N'facultad'),
        (N'Coordinador', N'IX_Coordinador_usuario', N'usuario'),
        (N'Docente', N'IX_Docente_usuario', N'usuario'),
        (N'Estudiante', N'IX_Estudiante_usuario', N'usuario'),
        (N'Administrador', N'IX_Administrador_usuario', N'usuario'),
        (N'Decano', N'IX_Decano_usuario', N'usuario'),
        (N'Facultad', N'IX_Facultad_decano', N'decano'),
        (N'EstudianteGrupo', N'IX_EstudianteGrupo_estado', N'estado'),
        (N'DetalleAsistencia', N'IX_DetalleAsistencia_razonCausa', N'razonCausa'),
        (N'SolicitudRevisionAsistencia', N'IX_SolicitudRevisionAsistencia_estado', N'estado'),
        (N'SolicitudRevisionAsistencia', N'IX_SolicitudRevisionAsistencia_toma', N'toma'),
        (N'TomaAsistencia', N'IX_TomaAsistencia_estado', N'estado'),
        (N'TomaAsistencia', N'IX_TomaAsistencia_docenteApertura', N'docenteApertura'),
        (N'RevisionCancelacion', N'IX_RevisionCancelacion_programaResolucion', N'programaResolucion'),
        (N'RevisionCancelacion', N'IX_RevisionCancelacion_usuarioResolucion', N'usuarioResolucion'),
        (N'SesionSolicitud', N'IX_SesionSolicitud_usuarioSolicitante', N'usuarioSolicitante'),
        (N'TokenMatriculaGrupo', N'IX_TokenMatriculaGrupo_docenteEmisor', N'docenteEmisor')
    ) v (tabla, nombre, columna);
    IF (SELECT COUNT(*) FROM #idx) <> 28
       OR EXISTS (
            SELECT 1 FROM #idx x
            WHERE NOT EXISTS (
                SELECT 1 FROM sys.indexes i
                INNER JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.key_ordinal = 1
                INNER JOIN sys.columns col ON col.object_id = ic.object_id AND col.column_id = ic.column_id
                WHERE i.object_id = OBJECT_ID(N'dbo.' + x.tabla) AND i.name = x.nombre AND col.name = x.columna AND i.is_hypothetical = 0))
        THROW 55541, 'TEST FAILED: AUDBD_M1_01 falta alguno de los 28 indices de apoyo de las FK de ambito (o su columna lider no es la FK).', 1;
    PRINT 'TEST_PASS:AUDBD_M1_01_INDICES_FK';

    -- ------------------------------------------------------------------ M-3
    DECLARE @cero NVARCHAR(40) = N'00000000-0000-0000-0000-000000000000';
    IF CHARINDEX(@cero, OBJECT_DEFINITION(OBJECT_ID(N'dbo.ufn_obtener_detalle_error'))) > 0
       OR CHARINDEX(@cero, OBJECT_DEFINITION(OBJECT_ID(N'dbo.ufn_obtener_mensaje_desde_plantilla'))) > 0
       OR CHARINDEX(N'GUID_DEFECTO_CORRELACION', OBJECT_DEFINITION(OBJECT_ID(N'dbo.ufn_obtener_detalle_error'))) = 0
       OR CHARINDEX(N'GUID_DEFECTO_CORRELACION', OBJECT_DEFINITION(OBJECT_ID(N'dbo.ufn_obtener_mensaje_desde_plantilla'))) = 0
        THROW 55551, 'TEST FAILED: AUDBD_M3_01 las funciones de error no deben llevar el GUID vacio literal.', 1;
    DECLARE @defecto NVARCHAR(50) = UPPER(CONVERT(NVARCHAR(50), dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION')));
    IF dbo.ufn_obtener_mensaje_desde_plantilla(NULL, N'ERROR', N'1', N'2', N'3', N'p', N'4', N'm') NOT LIKE CONCAT(N'[[]CORRELATION_ID=', @defecto, N']%')
       OR dbo.ufn_obtener_mensaje_desde_plantilla(@c, N'ERROR', N'1', N'2', N'3', N'p', N'4', N'm') NOT LIKE CONCAT(N'[[]CORRELATION_ID=', UPPER(CONVERT(NVARCHAR(50), @c)), N']%')
        THROW 55552, 'TEST FAILED: AUDBD_M3_01 la plantilla debe usar el defecto del parametro cuando no hay correlacion y la correlacion cuando si.', 1;
    PRINT 'TEST_PASS:AUDBD_M3_01_SIN_GUID_VACIO_LITERAL';

    -- ------------------------------------------------------------------ M-6
    IF EXISTS (
        SELECT 1 FROM (VALUES (N'usp_abrir_ventana_matricula_grupo'), (N'usp_clasificar_procedencia_sesion'), (N'usp_confirmar_verificacion_correo'), (N'usp_emitir_token_verificacion_correo'), (N'usp_registrar_asistencias_sesion'), (N'usp_matricular_por_token_interno'), (N'usp_rotar_token_matricula_interno')) s (nombre)
        WHERE CHARINDEX(N'SET XACT_ABORT ON', OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + s.nombre))) = 0
           OR CHARINDEX(N'XACT_STATE()', OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + s.nombre))) = 0
           OR CHARINDEX(N'THROW;', OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + s.nombre))) = 0)
        THROW 55561, 'TEST FAILED: AUDBD_M6_01 los SP de escritura deben declarar SET XACT_ABORT ON y conservar el manejo de XACT_STATE() = -1.', 1;
    IF CHARINDEX(N'SET XACT_ABORT ON', OBJECT_DEFINITION(OBJECT_ID(N'dbo.usp_registrar_o_actualizar_plan_estudio'))) > 0
        THROW 55562, 'TEST FAILED: AUDBD_M6_01 usp_registrar_o_actualizar_plan_estudio no debe declarar XACT_ABORT ON (rompe PLAN_PUBLIC_ROLLBACK_SAVEPOINT).', 1;
    PRINT 'TEST_PASS:AUDBD_M6_01_XACT_ABORT_ESCRITURA';

    -- ------------------------------------------------------------------ M-7
    IF OBJECT_ID(N'dbo.ufn_obtener_estado_estudiante_grupo') IS NOT NULL
        THROW 55571, 'TEST FAILED: AUDBD_M7_01 ufn_obtener_estado_estudiante_grupo debio retirarse.', 1;
    PRINT 'TEST_PASS:AUDBD_M7_01_FUNCION_RETIRADA';

    -- ------------------------------------------------------------------ M-11
    SELECT codigo INTO #cod FROM (VALUES (N'ERR_CORRELACION_REQUERIDA'), (N'ERR_UNICIDAD_DOCUMENTO'), (N'EST_004'), (N'ERR_ESTUDIANTE_NO_PERTENECE_SESION'), (N'ERR_DOCENTE_NO_EXISTE'), (N'ERR_GRUPO_NO_EXISTE'), (N'ERR_GRUPO_NO_HABILITADO'), (N'ERR_SESION_NO_EXISTE'), (N'ERR_TOKEN_VERIFICACION_INVALIDO'), (N'ARC_001'), (N'ARC_003'), (N'FES_006'), (N'FES_007'), (N'VAL_APP_068')) v (codigo);
    IF (SELECT COUNT(*) FROM #cod) <> 14
       OR EXISTS (SELECT 1 FROM #cod x LEFT JOIN dbo.CatalogoMensajeUsuario m ON m.codigo = x.codigo
                  WHERE m.codigo IS NULL OR NOT (m.contenido COLLATE Latin1_General_CI_AS LIKE N'%[áéíóúÁÉÍÓÚ]%'))
       OR EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario m INNER JOIN #cod x ON x.codigo = m.codigo
                  WHERE m.contenido COLLATE Latin1_General_CS_AS LIKE N'%codigo de%' OR m.contenido LIKE N'%correlacion%' OR m.contenido LIKE N'%sesion%'
                     OR m.contenido LIKE N'%esta registrado%' OR m.contenido LIKE N'%esta inactivo%' OR m.contenido LIKE N'%esta habilitado%' OR m.contenido LIKE N'%esta abierta%'
                     OR m.contenido LIKE N'%esta disponible%' OR m.contenido LIKE N'%matricula.%' OR m.contenido LIKE N'%validos%' OR m.contenido LIKE N'%dias%'
                     OR m.contenido LIKE N'%identificacion%' OR m.contenido LIKE N'%numero%' OR m.contenido LIKE N'%periodo%')
       OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'ERR_CORRELACION_REQUERIDA' AND contenido = N'El código de correlación es requerido.')
       OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = 'VAL_APP_068' AND contenido LIKE N'%días%envía%')
        THROW 55581, 'TEST FAILED: AUDBD_M11_01 los 14 mensajes corregidos deben llevar tildes y no conservar la forma anterior.', 1;
    PRINT 'TEST_PASS:AUDBD_M11_01_MENSAJES_CON_TILDES';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @fallo NVARCHAR(2000) = CONCAT(ERROR_MESSAGE(), N' [', ISNULL(ERROR_PROCEDURE(), N'lote'), N':', ERROR_LINE(), N']');
    THROW 55599, @fallo, 1;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
PRINT 'TEST_PASS:AUDBD_TRANCOUNT_ZERO';
PRINT 'TEST END: test_auditoria_bd_2026_11_22';
GO
