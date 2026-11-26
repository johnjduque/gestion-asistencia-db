USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
-- SKILLS-BD lote 3 (plan por lotes 2026-11-25): parametros, usuarios e identidad.
-- Fija el comportamiento de los SP del lote que no tenian prueba directa (nucleos de usuario, validadores, mensajes y contexto)
-- antes de refactorizarlos. Los SP publicos del lote (perfil, reenvio de activacion, correccion de identidad, identidad externa,
-- sincronizacion de mensajes, titularidad) siguen cubiertos por sus pruebas de dominio; aqui se agrega el perfil por rol.
-- Todo lo que escribe corre dentro de una transaccion revertida.
--   SKL3_N01_ESTRUCTURA            vista uv_token_verificacion_correo sin columnas sensibles; usp_obtener_mensaje_catalogo con
--                                  @estadoResultado OUTPUT opcional al final; firmas de contexto y mensajes sin cambio de nombre
--   SKL3_R01_MENSAJE_CATALOGO      codigo conocido (plantilla y DBCODE), desconocido y vacio (textos de reserva, tipo y severidad)
--   SKL3_R02_CONTEXTO_EJECUTOR     fija y limpia SESSION_CONTEXT(idUsuarioEjecutor)
--   SKL3_R03_VALIDAR_CORRELACION   NULL => CORR_001 estado 0; GUID valido => estado 1 y mensajes vacios
--   SKL3_R04_VALIDADORES_USUARIO   perfil por codigo, tipo de identificacion, unicidad y existencia del usuario (exito y rechazos)
--   SKL3_R05_ACTUALIZAR_DATOS      GEN_001, VAL_003, VAL_005, VAL_006 y exito (nombres y correo normalizados)
--   SKL3_R06_CAMBIAR_ESTADO        GEN_002, GEN_001, inactivar y reactivar (idempotente)
--   SKL3_R07_CORREGIR_DOCUMENTO    sin cambio (no-op), IDE_001, ERR_UNICIDAD_DOCUMENTO, @soloValidar sin escribir y escritura
--   SKL3_R08_CORREGIR_IDENTIDAD    nucleo: IDE_001 sin escribir; exito IDE_002 con nombres, documento y auditoria
--   SKL3_R09_PERFIL_POR_ROL        usp_consultar_perfil_usuario: ESTUDIANTE, DOCENTE, COORDINADOR, DECANO y ADMINISTRADOR
SET NOCOUNT ON;
SET XACT_ABORT OFF;
PRINT 'TEST START: test_skills_lote3_caracterizacion';

-- ===================================================================== N01 (estructura; no escribe)
DECLARE @msgN01 NVARCHAR(4000) = NULL;
IF OBJECT_ID(N'dbo.uv_token_verificacion_correo', N'V') IS NULL
    SET @msgN01 = N'falta la vista uv_token_verificacion_correo';
ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.uv_token_verificacion_correo')
                AND name NOT IN (N'id', N'idUsuario', N'fechaEmisionUtc'))
    SET @msgN01 = N'uv_token_verificacion_correo expone columnas de mas';
ELSE IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_obtener_mensaje_catalogo')
                    AND name = N'@estadoResultado' AND is_output = 1
                    AND parameter_id = (SELECT MAX(parameter_id) FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_obtener_mensaje_catalogo')))
    SET @msgN01 = N'usp_obtener_mensaje_catalogo sin @estadoResultado OUTPUT opcional al final';
ELSE IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_establecer_contexto_usuario_ejecutor') AND name = N'@p_idUsuario')
     OR NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_obtener_mensaje_catalogo') AND name = N'@p_codigo')
    SET @msgN01 = N'cambio la firma de usp_establecer_contexto_usuario_ejecutor o usp_obtener_mensaje_catalogo';
IF @msgN01 IS NOT NULL
BEGIN
    SET @msgN01 = CONCAT(N'TEST FAILED: SKL3_N01_ESTRUCTURA ', @msgN01);
    THROW 54800, @msgN01, 1;
END
PRINT 'TEST_PASS:SKL3_N01_ESTRUCTURA';
GO

-- ===================================================================== R01 (solo lectura)
DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @tipo VARCHAR(50), @sev VARCHAR(20);
DECLARE @plantilla NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'GEN_001');
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = ' GEN_001 ', @p_param1 = N'Usuario',
     @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @tipoMensajeResultado = @tipo OUTPUT, @severidadResultado = @sev OUTPUT;
IF @plantilla IS NULL OR @mu <> dbo.ufn_reemplazar_plantilla_mensaje(@plantilla, N'Usuario', NULL, NULL)
   OR @mt NOT LIKE N'DBCODE=GEN[_]001|%' OR @tipo IS NULL OR @sev IS NULL
    THROW 54810, 'TEST FAILED: SKL3_R01_MENSAJE_CATALOGO (codigo conocido)', 1;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ZZ_SKL3_NO_EXISTE',
     @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @tipoMensajeResultado = @tipo OUTPUT, @severidadResultado = @sev OUTPUT;
IF @mu <> N'Mensaje de usuario no configurado para el código: ZZ_SKL3_NO_EXISTE'
   OR @mt <> N'DBCODE=ZZ_SKL3_NO_EXISTE|Mensaje técnico no configurado para el código: ZZ_SKL3_NO_EXISTE'
   OR @tipo <> 'SYSTEM_ERROR' OR @sev <> 'ALTO'
    THROW 54811, 'TEST FAILED: SKL3_R01_MENSAJE_CATALOGO (codigo desconocido)', 1;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = NULL,
     @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @tipoMensajeResultado = @tipo OUTPUT, @severidadResultado = @sev OUTPUT;
IF @mu <> N'Mensaje de usuario no configurado para el código: '
   OR @mt <> N'DBCODE=DESCONOCIDO|Mensaje técnico no configurado para el código: DESCONOCIDO'
   OR @tipo <> 'SYSTEM_ERROR' OR @sev <> 'ALTO'
    THROW 54812, 'TEST FAILED: SKL3_R01_MENSAJE_CATALOGO (codigo nulo)', 1;
-- Sin los OUTPUT opcionales (como lo llaman casi todos los SP)
SET @mu = NULL; SET @mt = NULL;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001', @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT;
IF @mu IS NULL OR @mt NOT LIKE N'DBCODE=SYS[_]001|%'
    THROW 54813, 'TEST FAILED: SKL3_R01_MENSAJE_CATALOGO (sin opcionales)', 1;
PRINT 'TEST_PASS:SKL3_R01_MENSAJE_CATALOGO';
GO

-- ===================================================================== R02 (solo SESSION_CONTEXT)
DECLARE @previo UNIQUEIDENTIFIER = TRY_CAST(SESSION_CONTEXT(N'idUsuarioEjecutor') AS UNIQUEIDENTIFIER);
DECLARE @u UNIQUEIDENTIFIER = '5C3A0000-0000-0000-0000-0000000000C1';
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @u;
IF TRY_CAST(SESSION_CONTEXT(N'idUsuarioEjecutor') AS UNIQUEIDENTIFIER) IS NULL
   OR TRY_CAST(SESSION_CONTEXT(N'idUsuarioEjecutor') AS UNIQUEIDENTIFIER) <> @u
    THROW 54820, 'TEST FAILED: SKL3_R02_CONTEXTO_EJECUTOR (fijar)', 1;
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
IF SESSION_CONTEXT(N'idUsuarioEjecutor') IS NOT NULL
    THROW 54821, 'TEST FAILED: SKL3_R02_CONTEXTO_EJECUTOR (limpiar)', 1;
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @previo;
PRINT 'TEST_PASS:SKL3_R02_CONTEXTO_EJECUTOR';
GO

-- ===================================================================== R03 (solo lectura)
DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT;
EXEC dbo.usp_validar_id_correlacion_esta_presente_interno @idCorrelacion = NULL,
     @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=CORR[_]001|%'
    THROW 54830, 'TEST FAILED: SKL3_R03_VALIDAR_CORRELACION (nula)', 1;
EXEC dbo.usp_validar_id_correlacion_esta_presente_interno @idCorrelacion = '5C3A0000-0000-0000-0000-0000000000C2',
     @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
IF @ok <> 1 OR @mu <> N'' OR @mt <> N''
    THROW 54831, 'TEST FAILED: SKL3_R03_VALIDAR_CORRELACION (valida)', 1;
PRINT 'TEST_PASS:SKL3_R03_VALIDAR_CORRELACION';
GO

-- ===================================================================== R04..R09 (dentro de una transaccion revertida)
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @tipoOtro UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE id <> @tipoCC ORDER BY tipoIdentificacion);
DECLARE @idPrograma UNIQUEIDENTIFIER, @uCoord UNIQUEIDENTIFIER, @idFacultad UNIQUEIDENTIFIER;
SELECT TOP 1 @idPrograma = p.id, @uCoord = ci.idUsuario, @idFacultad = p.idFacultad
FROM dbo.uv_programa p
INNER JOIN dbo.uv_coordinador_identidad ci ON ci.id = p.idCoordinador
WHERE ci.estaActivoUsuario = 1
ORDER BY p.id;
DECLARE @uDecano UNIQUEIDENTIFIER, @idInstitucion UNIQUEIDENTIFIER;
SELECT @uDecano = d.idUsuario, @idInstitucion = f.idInstitucion
FROM dbo.uv_facultad f INNER JOIN dbo.uv_decano d ON d.id = f.idDecano
WHERE f.id = @idFacultad;
DECLARE @uAdmin UNIQUEIDENTIFIER = (SELECT TOP 1 a.idUsuario FROM dbo.uv_administrador a WHERE a.idInstitucion = @idInstitucion ORDER BY a.id);
IF @tipoCC IS NULL OR @tipoOtro IS NULL OR @idPrograma IS NULL OR @uCoord IS NULL OR @uDecano IS NULL OR @uAdmin IS NULL
    THROW 54840, 'TEST FAILED: SKL3 faltan fixtures del seed (tipos de documento, programa con coordinador, decano y administrador).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER = NEWID(), @idPerfil UNIQUEIDENTIFIER, @cambio BIT;
    DECLARE @msg NVARCHAR(4000);

    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 954830001,
        @primerApellido = N'Lote', @segundoApellido = N'Tres', @primerNombre = N'Ana', @segundoNombre = N'',
        @correo = N'skl3.a@uco.edu.co', @password = N'HashBackend_QaSkl31234567890', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 54841, 'TEST FAILED: SKL3 no se pudo crear el usuario A.', 1;
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 954830002,
        @primerApellido = N'Lote', @segundoApellido = N'Tres', @primerNombre = N'Beto', @segundoNombre = N'',
        @correo = N'skl3.b@uco.edu.co', @password = N'HashBackend_QaSkl31234567890', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 54842, 'TEST FAILED: SKL3 no se pudo crear el usuario B.', 1;
    DECLARE @uA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_usuario WHERE correo = N'skl3.a@uco.edu.co');
    DECLARE @uB UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_usuario WHERE correo = N'skl3.b@uco.edu.co');
    DECLARE @eA UNIQUEIDENTIFIER = NEWID(), @dB UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Estudiante (id, usuario) VALUES (@eA, @uA);
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES (NEWID(), @eA, @idPrograma);
    INSERT INTO dbo.Docente (id, usuario) VALUES (@dB, @uB);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, estado, fechaVinculacionUtc) VALUES (NEWID(), @dB, @idPrograma, 1, SYSUTCDATETIME());

    -- ================================================================= R04
    EXEC dbo.usp_validar_perfil_existe_por_codigo_interno @codigoPerfil = N' AD ', @idCorrelacion = @corr, @idPerfilEncontrado = @idPerfil OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @idPerfil IS NULL OR @idPerfil <> (SELECT id FROM dbo.uv_perfil WHERE codigo = 'AD')
        THROW 54850, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (perfil existente)', 1;
    EXEC dbo.usp_validar_perfil_existe_por_codigo_interno @codigoPerfil = N'', @idCorrelacion = @corr, @idPerfilEncontrado = @idPerfil OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VAL[_]003|%'
        THROW 54851, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (perfil vacio)', 1;
    EXEC dbo.usp_validar_perfil_existe_por_codigo_interno @codigoPerfil = N'ZZ', @idCorrelacion = @corr, @idPerfilEncontrado = @idPerfil OUTPUT,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]001|%'
        THROW 54852, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (perfil inexistente)', 1;
    EXEC dbo.usp_validar_tipo_identificacion_exista_por_id_interno @idTipoId = @tipoCC, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 54853, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (tipo existente)', 1;
    EXEC dbo.usp_validar_tipo_identificacion_exista_por_id_interno @idTipoId = NULL, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VAL[_]001|%' THROW 54854, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (tipo nulo)', 1;
    EXEC dbo.usp_validar_tipo_identificacion_exista_por_id_interno @idTipoId = '5C3A0000-0000-0000-0000-0000000000C3', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]001|%' THROW 54855, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (tipo inexistente)', 1;
    EXEC dbo.usp_validar_unicidad_usuario_interno @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 954830001, @correo = N'otro.skl3@uco.edu.co',
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=ERR[_]UNICIDAD[_]DOCUMENTO|%' THROW 54856, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (documento repetido)', 1;
    EXEC dbo.usp_validar_unicidad_usuario_interno @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 954830009, @correo = N' SKL3.A@uco.edu.co ',
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VAL[_]006|%' THROW 54857, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (correo repetido)', 1;
    EXEC dbo.usp_validar_unicidad_usuario_interno @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 954830009, @correo = N'nuevo.skl3@uco.edu.co',
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 54858, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (unico)', 1;
    EXEC dbo.usp_validar_usuario_existe_por_id_interno @idUsuario = @uA, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 54859, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (usuario activo)', 1;
    EXEC dbo.usp_validar_usuario_existe_por_id_interno @idUsuario = NULL, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VAL[_]001|%' THROW 54860, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (usuario nulo)', 1;
    EXEC dbo.usp_validar_usuario_existe_por_id_interno @idUsuario = '5C3A0000-0000-0000-0000-0000000000C4', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=USU[_]001|%' THROW 54861, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (usuario inexistente)', 1;
    UPDATE dbo.Usuario SET estado = 0 WHERE id = @uB;
    EXEC dbo.usp_validar_usuario_existe_por_id_interno @idUsuario = @uB, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=USU[_]002|%' THROW 54862, 'TEST FAILED: SKL3_R04_VALIDADORES_USUARIO (usuario inactivo)', 1;
    UPDATE dbo.Usuario SET estado = 1 WHERE id = @uB;
    PRINT 'TEST_PASS:SKL3_R04_VALIDADORES_USUARIO';

    -- ================================================================= R05
    EXEC dbo.usp_actualizar_datos_usuario_interno @idUsuario = '5C3A0000-0000-0000-0000-0000000000C5', @primerNombre = N'X', @segundoNombre = NULL,
         @primerApellido = N'Y', @segundoApellido = NULL, @correo = N'x.skl3@uco.edu.co', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]001|%' THROW 54870, 'TEST FAILED: SKL3_R05_ACTUALIZAR_DATOS (inexistente)', 1;
    EXEC dbo.usp_actualizar_datos_usuario_interno @idUsuario = @uA, @primerNombre = N'', @segundoNombre = NULL,
         @primerApellido = N'Y', @segundoApellido = NULL, @correo = N'skl3.a@uco.edu.co', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VAL[_]003|%' THROW 54871, 'TEST FAILED: SKL3_R05_ACTUALIZAR_DATOS (nombre vacio)', 1;
    EXEC dbo.usp_actualizar_datos_usuario_interno @idUsuario = @uA, @primerNombre = N'Ana', @segundoNombre = NULL,
         @primerApellido = N'Lote', @segundoApellido = NULL, @correo = N'no-es-correo', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VAL[_]005|%' THROW 54872, 'TEST FAILED: SKL3_R05_ACTUALIZAR_DATOS (correo invalido)', 1;
    EXEC dbo.usp_actualizar_datos_usuario_interno @idUsuario = @uA, @primerNombre = N'Ana', @segundoNombre = NULL,
         @primerApellido = N'Lote', @segundoApellido = NULL, @correo = N'skl3.b@uco.edu.co', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=VAL[_]006|%' THROW 54873, 'TEST FAILED: SKL3_R05_ACTUALIZAR_DATOS (correo de otro)', 1;
    EXEC dbo.usp_actualizar_datos_usuario_interno @idUsuario = @uA, @primerNombre = N'  Anita ', @segundoNombre = N'Maria',
         @primerApellido = N'Lote', @segundoApellido = N'Tres', @correo = N' SKL3.A2@uco.edu.co ', @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE id = @uA AND primerNombre = N'Anita' AND segundoNombre = N'Maria'
                                                              AND correo = N'skl3.a2@uco.edu.co')
    BEGIN
        SET @msg = CONCAT(N'TEST FAILED: SKL3_R05_ACTUALIZAR_DATOS (exito) ', @mt, N' | ',
                          (SELECT CONCAT(primerNombre, N'/', segundoNombre, N'/', correo) FROM dbo.uv_usuario WHERE id = @uA));
        THROW 54874, @msg, 1;
    END
    PRINT 'TEST_PASS:SKL3_R05_ACTUALIZAR_DATOS';

    -- ================================================================= R06
    EXEC dbo.usp_cambiar_estado_usuario_interno @idUsuario = NULL, @estaActivo = 0, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]002|%' THROW 54880, 'TEST FAILED: SKL3_R06_CAMBIAR_ESTADO (nulo)', 1;
    EXEC dbo.usp_cambiar_estado_usuario_interno @idUsuario = '5C3A0000-0000-0000-0000-0000000000C6', @estaActivo = 0, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]001|%' THROW 54881, 'TEST FAILED: SKL3_R06_CAMBIAR_ESTADO (inexistente)', 1;
    EXEC dbo.usp_cambiar_estado_usuario_interno @idUsuario = @uB, @estaActivo = 0, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE id = @uB AND estaActivoUsuario = 0)
        THROW 54882, 'TEST FAILED: SKL3_R06_CAMBIAR_ESTADO (inactivar)', 1;
    EXEC dbo.usp_cambiar_estado_usuario_interno @idUsuario = @uB, @estaActivo = 0, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 54883, 'TEST FAILED: SKL3_R06_CAMBIAR_ESTADO (idempotente)', 1;
    EXEC dbo.usp_cambiar_estado_usuario_interno @idUsuario = @uB, @estaActivo = 1, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE id = @uB AND estaActivoUsuario = 1)
        THROW 54884, 'TEST FAILED: SKL3_R06_CAMBIAR_ESTADO (reactivar)', 1;
    PRINT 'TEST_PASS:SKL3_R06_CAMBIAR_ESTADO';

    -- ================================================================= R07
    EXEC dbo.usp_corregir_documento_usuario_interno @idUsuario = @uA, @idTipoIdIdentificacion = NULL, @numeroIdentificacion = NULL, @motivo = NULL,
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT,
         @documentoCambiado = @cambio OUTPUT;
    IF @ok <> 1 OR @cambio <> 0 THROW 54890, 'TEST FAILED: SKL3_R07_CORREGIR_DOCUMENTO (sin cambio)', 1;
    EXEC dbo.usp_corregir_documento_usuario_interno @idUsuario = '5C3A0000-0000-0000-0000-0000000000C7', @idTipoIdIdentificacion = NULL,
         @numeroIdentificacion = 954830007, @motivo = N'x', @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT,
         @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT, @documentoCambiado = @cambio OUTPUT;
    IF @ok <> 0 OR @cambio <> 0 OR @mt NOT LIKE N'DBCODE=GEN[_]001|%' THROW 54891, 'TEST FAILED: SKL3_R07_CORREGIR_DOCUMENTO (inexistente)', 1;
    EXEC dbo.usp_corregir_documento_usuario_interno @idUsuario = @uA, @idTipoIdIdentificacion = NULL, @numeroIdentificacion = 954830003, @motivo = N'  ',
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT,
         @documentoCambiado = @cambio OUTPUT;
    IF @ok <> 0 OR @cambio <> 0 OR @mt NOT LIKE N'DBCODE=IDE[_]001|%' THROW 54892, 'TEST FAILED: SKL3_R07_CORREGIR_DOCUMENTO (sin motivo)', 1;
    EXEC dbo.usp_corregir_documento_usuario_interno @idUsuario = @uA, @idTipoIdIdentificacion = NULL, @numeroIdentificacion = 954830002, @motivo = N'Error',
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT,
         @documentoCambiado = @cambio OUTPUT;
    IF @ok <> 0 OR @cambio <> 0 OR @mt NOT LIKE N'DBCODE=ERR[_]UNICIDAD[_]DOCUMENTO|%' THROW 54893, 'TEST FAILED: SKL3_R07_CORREGIR_DOCUMENTO (repetido)', 1;
    EXEC dbo.usp_corregir_documento_usuario_interno @idUsuario = @uA, @idTipoIdIdentificacion = @tipoOtro, @numeroIdentificacion = 954830003, @motivo = N'Error',
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT,
         @documentoCambiado = @cambio OUTPUT, @soloValidar = 1;
    IF @ok <> 1 OR @cambio <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE id = @uA AND numeroIdentificacion = 954830001 AND idTipoIdentificacion = @tipoCC)
        THROW 54894, 'TEST FAILED: SKL3_R07_CORREGIR_DOCUMENTO (solo validar)', 1;
    EXEC dbo.usp_corregir_documento_usuario_interno @idUsuario = @uA, @idTipoIdIdentificacion = @tipoOtro, @numeroIdentificacion = 954830003, @motivo = N'Error',
         @idCorrelacion = @corr, @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT,
         @documentoCambiado = @cambio OUTPUT;
    IF @ok <> 1 OR @cambio <> 1 OR NOT EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE id = @uA AND numeroIdentificacion = 954830003 AND idTipoIdentificacion = @tipoOtro)
        THROW 54895, 'TEST FAILED: SKL3_R07_CORREGIR_DOCUMENTO (escritura)', 1;
    PRINT 'TEST_PASS:SKL3_R07_CORREGIR_DOCUMENTO';

    -- ================================================================= R08
    EXEC dbo.usp_corregir_identidad_usuario_interno @idUsuario = @uA, @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 954830004,
         @primerNombre = N'Otra', @segundoNombre = NULL, @primerApellido = N'Persona', @segundoApellido = NULL, @motivo = NULL,
         @accionAuditoria = 'CORREGIR_IDENTIDAD_ESTUDIANTE', @tipoRecurso = 'Estudiante', @idRecurso = @eA,
         @rutaAuditoria = N'/api/v1/coordinador/estudiantes/{idEstudiante}/identidad', @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=IDE[_]001|%'
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE id = @uA AND primerNombre = N'Anita' AND numeroIdentificacion = 954830003)
        THROW 54900, 'TEST FAILED: SKL3_R08_CORREGIR_IDENTIDAD (sin motivo no escribe)', 1;
    EXEC dbo.usp_corregir_identidad_usuario_interno @idUsuario = @uA, @idTipoIdIdentificacion = @tipoCC, @numeroIdentificacion = 954830004,
         @primerNombre = N'Otra', @segundoNombre = NULL, @primerApellido = N'Persona', @segundoApellido = NULL, @motivo = N'Correccion SKL3',
         @accionAuditoria = 'CORREGIR_IDENTIDAD_ESTUDIANTE', @tipoRecurso = 'Estudiante', @idRecurso = @eA,
         @rutaAuditoria = N'/api/v1/coordinador/estudiantes/{idEstudiante}/identidad', @idUsuarioEjecutor = @uCoord, @idCorrelacion = @corr,
         @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 OR @mt NOT LIKE N'DBCODE=IDE[_]002|%'
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE id = @uA AND primerNombre = N'Otra' AND primerApellido = N'Persona'
                                                     AND numeroIdentificacion = 954830004 AND idTipoIdentificacion = @tipoCC AND correo = N'skl3.a2@uco.edu.co')
       OR NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corr AND action = 'CORREGIR_IDENTIDAD_ESTUDIANTE'
                                                         AND resourceId = CAST(@eA AS NVARCHAR(120)) AND metadata LIKE N'%Correccion SKL3%')
    BEGIN
        SET @msg = CONCAT(N'TEST FAILED: SKL3_R08_CORREGIR_IDENTIDAD (exito) ', @mt);
        THROW 54901, @msg, 1;
    END
    PRINT 'TEST_PASS:SKL3_R08_CORREGIR_IDENTIDAD';

    -- ================================================================= R09
    CREATE TABLE #skl3Perfil (idUsuario UNIQUEIDENTIFIER, codigoTipoIdentificacion VARCHAR(50), nombreTipoIdentificacion NVARCHAR(200),
        numeroIdentificacion INT, primerNombre NVARCHAR(100), segundoNombre NVARCHAR(100), primerApellido NVARCHAR(100), segundoApellido NVARCHAR(100),
        nombreCompleto NVARCHAR(400), correo NVARCHAR(255), correoConfirmado BIT, estaActivoUsuario BIT, rolVinculo VARCHAR(20),
        idEntidadVinculo UNIQUEIDENTIFIER, nombreEntidadVinculo NVARCHAR(400), detalleVinculo NVARCHAR(400), estaActivoVinculo BIT);
    INSERT INTO #skl3Perfil EXEC dbo.usp_consultar_perfil_usuario @idCorrelacion = @corr, @idUsuarioEjecutor = @uA;
    INSERT INTO #skl3Perfil EXEC dbo.usp_consultar_perfil_usuario @idCorrelacion = @corr, @idUsuarioEjecutor = @uB;
    INSERT INTO #skl3Perfil EXEC dbo.usp_consultar_perfil_usuario @idCorrelacion = @corr, @idUsuarioEjecutor = @uCoord;
    INSERT INTO #skl3Perfil EXEC dbo.usp_consultar_perfil_usuario @idCorrelacion = @corr, @idUsuarioEjecutor = @uDecano;
    INSERT INTO #skl3Perfil EXEC dbo.usp_consultar_perfil_usuario @idCorrelacion = @corr, @idUsuarioEjecutor = @uAdmin;
    INSERT INTO #skl3Perfil EXEC dbo.usp_consultar_perfil_usuario @idCorrelacion = @corr, @idUsuarioEjecutor = '5C3A0000-0000-0000-0000-0000000000C8';
    DECLARE @nombreFacultad NVARCHAR(400) = (SELECT nombreFacultad FROM dbo.uv_facultad WHERE id = @idFacultad);
    IF NOT EXISTS (SELECT 1 FROM #skl3Perfil WHERE idUsuario = @uA AND rolVinculo = 'ESTUDIANTE' AND idEntidadVinculo = @idPrograma
                   AND detalleVinculo = @nombreFacultad AND nombreCompleto = N'Otra Persona' AND correo = N'skl3.a2@uco.edu.co')
       OR (SELECT COUNT(*) FROM #skl3Perfil WHERE idUsuario = @uA) <> 1
       OR NOT EXISTS (SELECT 1 FROM #skl3Perfil WHERE idUsuario = @uB AND rolVinculo = 'DOCENTE' AND idEntidadVinculo = @idPrograma
                      AND detalleVinculo = @nombreFacultad AND estaActivoVinculo = 1)
       OR NOT EXISTS (SELECT 1 FROM #skl3Perfil WHERE idUsuario = @uCoord AND rolVinculo = 'COORDINADOR' AND idEntidadVinculo = @idPrograma
                      AND detalleVinculo = @nombreFacultad)
       OR NOT EXISTS (SELECT 1 FROM #skl3Perfil p INNER JOIN dbo.uv_institucion i ON i.id = @idInstitucion
                      WHERE p.idUsuario = @uDecano AND p.rolVinculo = 'DECANO' AND p.idEntidadVinculo = @idFacultad AND p.detalleVinculo = i.nombre)
       OR NOT EXISTS (SELECT 1 FROM #skl3Perfil WHERE idUsuario = @uAdmin AND rolVinculo = 'ADMINISTRADOR' AND idEntidadVinculo = @idInstitucion
                      AND detalleVinculo IS NULL)
       OR EXISTS (SELECT 1 FROM #skl3Perfil WHERE idUsuario = '5C3A0000-0000-0000-0000-0000000000C8')
       OR EXISTS (SELECT 1 FROM #skl3Perfil p1 INNER JOIN #skl3Perfil p2 ON p2.idUsuario = p1.idUsuario
                  WHERE p1.rolVinculo IS NULL AND p2.rolVinculo IS NOT NULL)
        THROW 54910, 'TEST FAILED: SKL3_R09_PERFIL_POR_ROL', 1;
    DROP TABLE #skl3Perfil;
    PRINT 'TEST_PASS:SKL3_R09_PERFIL_POR_ROL';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
