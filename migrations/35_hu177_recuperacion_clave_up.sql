-- ============================================================================
-- MIGRACION UP 35: HU177 - recuperacion de contrasena con enlace de un solo uso
-- Crea dbo.TokenRecuperacionClave (solo guarda el SHA-256 del token; un enlace pendiente por usuario) con su FK a Usuario, y los SP
-- usp_consultar_solicitud_recuperacion_clave, usp_emitir_token_recuperacion_clave, usp_consultar_token_recuperacion_clave y
-- usp_consumir_token_recuperacion_clave. Siembra los mensajes RCL_001..RCL_003, los parametros RECUPERACION_CLAVE/TTL_MINUTOS y
-- RECUPERACION_CLAVE/REENVIO_ESPERA_MINUTOS y la plantilla de correo RECUPERACION_CLAVE (MERGE). Concede EXECUTE de los 4 SP al rol runtime.
-- No modifica objetos existentes. Idempotente. Down: 35_hu177_recuperacion_clave_down.sql.
-- ============================================================================
PRINT 'MIGRACION 35 UP: HU177 recuperacion de contrasena';
GO
-- ---- schema/tables/TokenRecuperacionClave.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU177: enlace de un solo uso para definir una contrasena nueva. Solo se guarda el SHA-256 del token del enlace; el
-- token en claro nunca se persiste. Un enlace sirve mientras no se haya usado, no se haya revocado y no haya vencido.
IF OBJECT_ID('dbo.TokenRecuperacionClave', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TokenRecuperacionClave (
        id                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_TokenRecuperacionClave_id DEFAULT NEWID(),
        usuario            UNIQUEIDENTIFIER NOT NULL,
        tokenHash          VARBINARY(32)    NOT NULL,
        fechaEmisionUtc    DATETIME2(0)     NOT NULL,
        fechaExpiracionUtc DATETIME2(0)     NOT NULL,
        fechaUsoUtc        DATETIME2(0)     NULL,
        fechaRevocacionUtc DATETIME2(0)     NULL,
        CONSTRAINT PK_TokenRecuperacionClave PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TokenRecuperacionClave_tokenHash UNIQUE (tokenHash),
        CONSTRAINT CK_TokenRecuperacionClave_vigencia CHECK (fechaExpiracionUtc > fechaEmisionUtc)
    );
END
GO

-- Un solo enlace pendiente por usuario: pedir otro revoca el anterior.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TokenRecuperacionClave_pendiente' AND object_id = OBJECT_ID('dbo.TokenRecuperacionClave'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenRecuperacionClave_pendiente
    ON dbo.TokenRecuperacionClave (usuario)
    WHERE fechaUsoUtc IS NULL AND fechaRevocacionUtc IS NULL;
END
GO
-- ---- schema/tables/zz_foreign_keys.sql (FK de HU177)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TokenRecuperacionClave_Usuario')
BEGIN
    ALTER TABLE [dbo].[TokenRecuperacionClave] ADD CONSTRAINT [FK_TokenRecuperacionClave_Usuario] FOREIGN KEY ([usuario]) REFERENCES [dbo].[Usuario] ([id]);
END
GO
-- ---- schema/stored-procedures/usp_consultar_solicitud_recuperacion_clave.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitud_recuperacion_clave (HU177)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (0..1 fila: idUsuario, primerNombre, correo).
-- Publico sin ejecutor: lo llama el backend cuando alguien pide el enlace para definir una contrasena nueva.
-- Devuelve la fila solo si el correo corresponde a UN usuario activo y ya paso la espera minima desde el ultimo enlace
-- emitido (RECUPERACION_CLAVE/REENVIO_ESPERA_MINUTOS). En cualquier otro caso devuelve 0 filas y no lanza: el llamador
-- responde siempre lo mismo, exista o no la cuenta, para no revelar quien esta registrado.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitud_recuperacion_clave]
(
    @correo        NVARCHAR(100),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @correoLimpio  NVARCHAR(100) = NULLIF(LTRIM(RTRIM(@correo)), N'');
    DECLARE @esperaMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'RECUPERACION_CLAVE', 'REENVIO_ESPERA_MINUTOS');
    DECLARE @ahoraUtc      DATETIME2(0) = SYSUTCDATETIME();

    SELECT idUsuario    = u.id,
           primerNombre = u.primerNombre,
           correo       = u.correo
    FROM dbo.Usuario u
    WHERE u.correo = @correoLimpio
      AND u.estado = 1
      AND (SELECT COUNT(*) FROM dbo.Usuario d WHERE d.correo = @correoLimpio AND d.estado = 1) = 1
      AND NOT EXISTS (SELECT 1
                      FROM dbo.TokenRecuperacionClave t
                      WHERE t.usuario = u.id
                        AND t.fechaEmisionUtc > DATEADD(MINUTE, -ISNULL(@esperaMinutos, 0), @ahoraUtc));
END;
GO
-- ---- schema/stored-procedures/usp_emitir_token_recuperacion_clave.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_emitir_token_recuperacion_clave (HU177)
--
-- Registra el enlace de un solo uso para definir una contrasena nueva (solo recibe y guarda su SHA-256). Lo invoca el
-- canal de correo al entregar el aviso. Revoca el enlace pendiente anterior del usuario; la vigencia es ahora +
-- RECUPERACION_CLAVE/TTL_MINUTOS. Tecnico (sin ejecutor): la credencial es la identidad del proceso de entrega.
-- Rechaza con VCE_007 si el usuario no existe o no esta activo. Resultset canonico de 4 columnas.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_emitir_token_recuperacion_clave]
(
    @idUsuario     UNIQUEIDENTIFIER,
    @tokenHash     VARBINARY(32),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoMensaje   VARCHAR(20) = NULL;
    DECLARE @parametroMensaje NVARCHAR(200) = NULL;
    DECLARE @abrioTransaccion BIT = 0;
    DECLARE @vigenciaMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'RECUPERACION_CLAVE', 'TTL_MINUTOS');
    DECLARE @emisionUtc      DATETIME2(0) = SYSUTCDATETIME();
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @idUsuario IS NULL OR @tokenHash IS NULL
                SELECT @codigoMensaje = 'GEN_002', @parametroMensaje = N'idUsuario/tokenHash';
            ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuario AND u.estado = 1)
                SET @codigoMensaje = 'VCE_007';
            ELSE IF @vigenciaMinutos IS NULL OR @vigenciaMinutos < 1
                SELECT @codigoMensaje = 'GEN_002', @parametroMensaje = N'RECUPERACION_CLAVE/TTL_MINUTOS';

            IF @codigoMensaje IS NULL
            BEGIN
                -- Revoca el enlace pendiente e inserta el nuevo como una sola unidad (un pendiente por usuario).
                IF @@TRANCOUNT = 0
                BEGIN
                    BEGIN TRANSACTION;
                    SET @abrioTransaccion = 1;
                END

                UPDATE p
                SET p.fechaRevocacionUtc = @emisionUtc
                FROM dbo.TokenRecuperacionClave p WITH (UPDLOCK, HOLDLOCK)
                WHERE p.usuario = @idUsuario AND p.fechaUsoUtc IS NULL AND p.fechaRevocacionUtc IS NULL;

                INSERT INTO dbo.TokenRecuperacionClave (usuario, tokenHash, fechaEmisionUtc, fechaExpiracionUtc)
                VALUES (@idUsuario, @tokenHash, @emisionUtc, DATEADD(MINUTE, @vigenciaMinutos, @emisionUtc));

                IF @abrioTransaccion = 1
                    COMMIT TRANSACTION;

                SELECT @codigoMensaje = 'GEN_004', @parametroMensaje = N'Enlace de recuperacion de contrasena';
            END
            ELSE
                SET @estadoResultado = 0;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoMensaje, @p_param1 = @parametroMensaje,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        IF @abrioTransaccion = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        IF @abrioTransaccion = 0 AND XACT_STATE() = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT idCorrelacion           = @idCorrelacionDefecto,
           mensajeUsuarioResultado = @mensajeUsuarioResultado,
           mensajeTecnicoResultado = @mensajeTecnicoResultado,
           estadoResultado         = @estadoResultado;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_token_recuperacion_clave.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_token_recuperacion_clave (HU177)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (0..1 fila: idUsuario). No consume el enlace.
-- Devuelve el usuario dueno de un enlace que todavia sirve (sin usar, sin revocar, sin vencer y de un usuario activo).
-- Para cualquier otro enlace devuelve 0 filas: el llamador no distingue inexistente, vencido, usado o revocado.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_token_recuperacion_clave]
(
    @tokenHash     VARBINARY(32),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT idUsuario = r.usuario
    FROM dbo.TokenRecuperacionClave r
    WHERE r.tokenHash = @tokenHash
      AND r.fechaUsoUtc IS NULL
      AND r.fechaRevocacionUtc IS NULL
      AND r.fechaExpiracionUtc > SYSUTCDATETIME()
      AND EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = r.usuario AND u.estado = 1);
END;
GO
-- ---- schema/stored-procedures/usp_consumir_token_recuperacion_clave.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consumir_token_recuperacion_clave (HU177)
--
-- Marca como usado el enlace para definir una contrasena nueva. Publico sin ejecutor: la credencial es el SHA-256 del
-- token. La marca es una sola sentencia UPDATE con UPDLOCK: de dos intentos simultaneos solo uno gana. Cualquier enlace
-- que ya no sirve (inexistente, vencido, usado, revocado o de usuario inactivo) responde igual: RCL_002.
-- La contrasena no vive en la base de datos: el backend la cambia en el proveedor de identidad antes de consumir.
-- Resultset canonico de 4 columnas.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consumir_token_recuperacion_clave]
(
    @tokenHash     VARBINARY(32),
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoMensaje   VARCHAR(20);
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        UPDATE r
        SET r.fechaUsoUtc = SYSUTCDATETIME()
        FROM dbo.TokenRecuperacionClave r WITH (UPDLOCK, HOLDLOCK)
        WHERE r.tokenHash = @tokenHash
          AND r.fechaUsoUtc IS NULL
          AND r.fechaRevocacionUtc IS NULL
          AND r.fechaExpiracionUtc > SYSUTCDATETIME()
          AND EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = r.usuario AND u.estado = 1);

        SELECT @codigoMensaje = IIF(@@ROWCOUNT = 1, 'RCL_003', 'RCL_002');
        SET @estadoResultado = IIF(@codigoMensaje = 'RCL_003', 1, 0);

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = @codigoMensaje,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
    END TRY
    BEGIN CATCH
        IF XACT_STATE() = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT idCorrelacion           = @idCorrelacionDefecto,
           mensajeUsuarioResultado = @mensajeUsuarioResultado,
           mensajeTecnicoResultado = @mensajeTecnicoResultado,
           estadoResultado         = @estadoResultado;
END;
GO
-- ---- schema/seed/61_hu177_recuperacion_clave.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU177: mensajes, parametros y plantilla de correo de la recuperacion de contrasena (idempotente).
-- RCL_001 se responde siempre al pedir el enlace, exista o no la cuenta, para no revelar quien esta registrado.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Destino
USING (VALUES
    ('RCL_001', 'SUCCESS',        'BAJO',  N'Si el correo está registrado, recibirá un enlace para definir una contraseña nueva.'),
    ('RCL_002', 'BUSINESS_ERROR', 'MEDIO', N'El enlace para definir la contraseña no es válido o ya venció. Solicite uno nuevo.'),
    ('RCL_003', 'SUCCESS',        'BAJO',  N'Su contraseña fue actualizada. Ya puede iniciar sesión.')
) AS Origen (codigo, tipoMensaje, severidad, contenido)
ON (Destino.codigo = Origen.codigo)
WHEN MATCHED THEN
    UPDATE SET Destino.tipoMensaje = Origen.tipoMensaje, Destino.severidad = Origen.severidad, Destino.contenido = Origen.contenido, Destino.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Origen.codigo, Origen.tipoMensaje, Origen.severidad, Origen.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Destino
USING (VALUES
    ('RCL_001', 'SUCCESS',        'BAJO',  N'Solicitud de recuperación recibida; la respuesta no indica si el correo existe.'),
    ('RCL_002', 'BUSINESS_ERROR', 'MEDIO', N'Enlace de recuperación inexistente, vencido, usado, revocado o de usuario inactivo.'),
    ('RCL_003', 'SUCCESS',        'BAJO',  N'Enlace de recuperación consumido (TokenRecuperacionClave.fechaUsoUtc).')
) AS Origen (codigo, tipoMensaje, severidad, contenido)
ON (Destino.codigo = Origen.codigo)
WHEN MATCHED THEN
    UPDATE SET Destino.tipoMensaje = Origen.tipoMensaje, Destino.severidad = Origen.severidad, Destino.contenido = Origen.contenido, Destino.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Origen.codigo, Origen.tipoMensaje, Origen.severidad, Origen.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- Vigencia del enlace y espera minima entre dos enlaces para el mismo usuario.
MERGE INTO [dbo].[CatalogoParametro] AS Destino
USING (VALUES
    ('RECUPERACION_CLAVE', 'TTL_MINUTOS', N'60', 'INT', N'60'),
    ('RECUPERACION_CLAVE', 'REENVIO_ESPERA_MINUTOS', N'5', 'INT', N'5')
) AS Origen (grupo, clave, valor, tipoDato, valorDefecto)
ON (Destino.grupo = Origen.grupo AND Destino.clave = Origen.clave)
WHEN MATCHED THEN
    UPDATE SET Destino.tipoDato = Origen.tipoDato, Destino.valorDefecto = Origen.valorDefecto, Destino.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Origen.grupo, Origen.clave, Origen.valor, Origen.tipoDato, Origen.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- Plantilla v1 del correo. El marcador {enlace} lo resuelve el canal de correo al entregar; nunca se guarda en el outbox.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Destino
USING (VALUES
    ('RECUPERACION_CLAVE', 'nombre', N'Primer nombre del usuario', N'Juan', 1),
    ('RECUPERACION_CLAVE', 'enlace', N'Enlace de un solo uso para definir la contraseña (lo genera el sistema al enviar)', N'https://plataforma/restablecer-clave#token=...', 1)
) AS Origen (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Destino.tipo = Origen.tipo AND Destino.marcador = Origen.marcador)
WHEN MATCHED THEN
    UPDATE SET Destino.descripcion = Origen.descripcion, Destino.ejemplo = Origen.ejemplo, Destino.obligatorio = Origen.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Origen.tipo, Origen.marcador, Origen.descripcion, Origen.ejemplo, Origen.obligatorio);
GO

MERGE INTO [dbo].[PlantillaNotificacion] AS Destino
USING (VALUES
    ('RECUPERACION_CLAVE', 'es', 1,
     N'Defina una contraseña nueva',
     N'Hola {nombre}, recibimos una solicitud para definir una contraseña nueva de su cuenta en la plataforma de asistencia. Abra el siguiente enlace para hacerlo: {enlace} . El enlace es de un solo uso y vence pronto. Si usted no hizo esta solicitud, ignore este mensaje: su contraseña actual sigue funcionando.',
     1)
) AS Origen (tipo, idioma, version, asunto, cuerpo, activa)
ON (Destino.tipo = Origen.tipo AND Destino.idioma = Origen.idioma AND Destino.version = Origen.version)
WHEN MATCHED THEN
    UPDATE SET Destino.asunto = Origen.asunto, Destino.cuerpo = Origen.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Origen.tipo, Origen.idioma, Origen.version, Origen.asunto, Origen.cuerpo, Origen.activa, NULL, SYSUTCDATETIME());
GO
-- ---- schema/security/rol_asistencias_runtime_hu177.sql
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU177: el rol runtime solo ejecuta los cuatro SP de la recuperacion de contrasena; no tiene DML sobre la tabla del enlace.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'GRANT EXECUTE ON [dbo].' + QUOTENAME(o.nombre) + N' TO [rol_asistencias_runtime];'
FROM (VALUES (N'usp_consultar_solicitud_recuperacion_clave'), (N'usp_emitir_token_recuperacion_clave'),
             (N'usp_consultar_token_recuperacion_clave'), (N'usp_consumir_token_recuperacion_clave')) o(nombre)
WHERE OBJECT_ID(N'dbo.' + o.nombre, N'P') IS NOT NULL;
EXEC sys.sp_executesql @sql;
GO
PRINT 'MIGRACION 35 UP OK';
GO
