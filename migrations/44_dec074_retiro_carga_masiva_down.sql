-- ============================================================================
-- MIGRACION DOWN 44: restaura la carga masiva de usuarios por CSV tal como estaba antes de DEC-074 (tabla, FK, filas de
-- jerarquia, vista, SP, parametros con su metadato de edicion, mensajes CMA_* y permisos del rol runtime). El historial de
-- cambios de los parametros CARGA_MASIVA/* que borro el up no se recupera. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 44 DOWN: restaura la carga masiva';
GO

-- ---- tabla JerarquiaAltaUsuario ----
-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, [SUPUESTO-D-15], HU171): jerarquia de alta masiva de usuarios.
-- Tabla de catalogo que define los pares permitidos de (perfilEjecutor -> perfilDestino)
-- para la carga masiva CSV.
-- Filas sembradas (55_culm001_d5_jerarquia.sql):
--   COORDINADOR -> DOCENTE
--   DECANO      -> COORDINADOR
--   ADMINISTRADOR -> DECANO
-- ============================================================================
IF OBJECT_ID('dbo.[JerarquiaAltaUsuario]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.JerarquiaAltaUsuario (
        id             UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_JerarquiaAltaUsuario PRIMARY KEY CLUSTERED,
        perfilEjecutor UNIQUEIDENTIFIER NOT NULL,
        perfilDestino  UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT UQ_JerarquiaAltaUsuario_Pares UNIQUE (perfilEjecutor, perfilDestino)
    );
END
GO

-- ---- FK ----
-- CULM-001 D.5 (CONTRACT §6.3, HU171): JerarquiaAltaUsuario -> Perfil
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_JerarquiaAltaUsuario_PerfilEjecutor')
BEGIN
    ALTER TABLE [dbo].[JerarquiaAltaUsuario] ADD CONSTRAINT [FK_JerarquiaAltaUsuario_PerfilEjecutor] FOREIGN KEY ([perfilEjecutor]) REFERENCES [dbo].[Perfil] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_JerarquiaAltaUsuario_PerfilDestino')
BEGIN
    ALTER TABLE [dbo].[JerarquiaAltaUsuario] ADD CONSTRAINT [FK_JerarquiaAltaUsuario_PerfilDestino] FOREIGN KEY ([perfilDestino]) REFERENCES [dbo].[Perfil] ([id]);
END
GO

-- ---- vista ----
-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, HU171): vista de jerarquia de alta masiva de usuarios.
-- ============================================================================
CREATE OR ALTER VIEW dbo.uv_jerarquia_alta_usuario
AS
SELECT 
    j.id,
    j.perfilEjecutor,
    pe.codigo AS codigoPerfilEjecutor,
    pe.nombre AS nombrePerfilEjecutor,
    j.perfilDestino,
    pd.codigo AS codigoPerfilDestino,
    pd.nombre AS nombrePerfilDestino
FROM dbo.JerarquiaAltaUsuario j
INNER JOIN dbo.Perfil pe ON pe.id = j.perfilEjecutor
INNER JOIN dbo.Perfil pd ON pd.id = j.perfilDestino;
GO

-- ---- SP ----
-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, [SUPUESTO-D-11], [SUPUESTO-D-15], HU171)
-- usp_validar_carga_masiva_usuarios (READ_QUERY_RESULTSET, sin escrituras).
--
-- Valida jerarquia de autorizacion (JerarquiaAltaUsuario), limite maximo de filas
-- (CARGA_MASIVA/MAXIMO_FILAS) y devuelve un resultset con una fila por cada fila
-- de entrada analizando duplicados, catalogos, ambito, consistencia de identidad y yaExiste.
-- DEC-058: codigoPrograma/codigoFacultad se resuelven por nombre (el modelo no tiene codigo).
-- Comparacion UPPER(LTRIM(RTRIM(nombre))) dentro del ambito del ejecutor; estaActivo -> estado = 1.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_carga_masiva_usuarios]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @codigoPerfilDestino     VARCHAR(20),
    @filasJson               NVARCHAR(MAX)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioVal NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoVal NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    -- PASO 1: Validar idCorrelacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioVal OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoVal OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 0
    BEGIN
        THROW 52000, @mensajeTecnicoVal, 1;
    END

    -- PASO 2: Validar presencia de ejecutor
    IF @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioVal OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoVal OUTPUT;
        SET @mensajeTecnicoVal = CONCAT(@mensajeTecnicoVal, ' Correlacion: ', @idCorrelacionDefecto);
        THROW 50002, @mensajeTecnicoVal, 1;
    END

    -- PASO 3: Resolver perfil destino
    DECLARE @idPerfilDestino UNIQUEIDENTIFIER = (
        SELECT TOP 1 id FROM dbo.Perfil 
        WHERE UPPER(codigo) = UPPER(@codigoPerfilDestino) 
           OR UPPER(nombre) = UPPER(@codigoPerfilDestino)
    );

    IF @idPerfilDestino IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_009',
            @mensajeUsuarioResultado = @mensajeUsuarioVal OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoVal OUTPUT;
        SET @mensajeTecnicoVal = CONCAT(@mensajeTecnicoVal, ' Correlacion: ', @idCorrelacionDefecto);
        THROW 52009, @mensajeTecnicoVal, 1;
    END

    -- PASO 4: Validar jerarquia de alta segun JerarquiaAltaUsuario
    DECLARE @idPerfilEjecutorValido UNIQUEIDENTIFIER = (
        SELECT TOP 1 j.perfilEjecutor
        FROM dbo.JerarquiaAltaUsuario j
        INNER JOIN dbo.uv_usuario_perfil up ON up.idPerfil = j.perfilEjecutor
        WHERE up.idUsuario = @idUsuarioEjecutor
          AND j.perfilDestino = @idPerfilDestino
    );

    IF @idPerfilEjecutorValido IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_009',
            @mensajeUsuarioResultado = @mensajeUsuarioVal OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoVal OUTPUT;
        SET @mensajeTecnicoVal = CONCAT(@mensajeTecnicoVal, ' Correlacion: ', @idCorrelacionDefecto);
        THROW 52009, @mensajeTecnicoVal, 1;
    END

    -- PASO 5: Parsear JSON de entrada
    IF OBJECT_ID('tempdb..#filasEntrada') IS NOT NULL DROP TABLE #filasEntrada;
    CREATE TABLE #filasEntrada (
        numeroFila            INT,
        tipoDocumento         NVARCHAR(50),
        numeroDocumento       INT,
        correo                NVARCHAR(255),
        codigoTipoVinculacion NVARCHAR(50),
        codigoPrograma        NVARCHAR(50),
        codigoFacultad        NVARCHAR(50)
    );

    IF @filasJson IS NOT NULL AND ISJSON(@filasJson) = 1
    BEGIN
        INSERT INTO #filasEntrada (numeroFila, tipoDocumento, numeroDocumento, correo, codigoTipoVinculacion, codigoPrograma, codigoFacultad)
        SELECT 
            numeroFila,
            TRIM(tipoDocumento),
            numeroDocumento,
            LOWER(TRIM(correo)),
            TRIM(codigoTipoVinculacion),
            TRIM(codigoPrograma),
            TRIM(codigoFacultad)
        FROM OPENJSON(@filasJson)
        WITH (
            numeroFila            INT           '$.numeroFila',
            tipoDocumento         NVARCHAR(50)  '$.tipoDocumento',
            numeroDocumento       INT           '$.numeroDocumento',
            correo                NVARCHAR(255) '$.correo',
            codigoTipoVinculacion NVARCHAR(50)  '$.codigoTipoVinculacion',
            codigoPrograma        NVARCHAR(50)  '$.codigoPrograma',
            codigoFacultad        NVARCHAR(50)  '$.codigoFacultad'
        );
    END

    -- PASO 6: Validar maximo de filas
    DECLARE @maxFilas INT = dbo.ufn_obtener_parametro_int(NULL, 'CARGA_MASIVA', 'MAXIMO_FILAS');
    IF @maxFilas IS NULL OR @maxFilas <= 0 SET @maxFilas = 100;

    DECLARE @totalFilas INT = (SELECT COUNT(*) FROM #filasEntrada);
    IF @totalFilas > @maxFilas
    BEGIN
        DECLARE @maxFilasStr VARCHAR(20) = CAST(@maxFilas AS VARCHAR(20));
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_001', @p_param1 = @maxFilasStr,
            @mensajeUsuarioResultado = @mensajeUsuarioVal OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoVal OUTPUT;
        SET @mensajeTecnicoVal = CONCAT(@mensajeTecnicoVal, ' Correlacion: ', @idCorrelacionDefecto);
        THROW 52001, @mensajeTecnicoVal, 1;
    END

    -- PASO 7: Ambitos segun perfil
    DECLARE @codPerfilEjecutor VARCHAR(20) = (SELECT UPPER(codigo) FROM dbo.Perfil WHERE id = @idPerfilEjecutorValido);
    DECLARE @codPerfilDestino VARCHAR(20) = (SELECT UPPER(codigo) FROM dbo.Perfil WHERE id = @idPerfilDestino);

    IF OBJECT_ID('tempdb..#programasCoordinador') IS NOT NULL DROP TABLE #programasCoordinador;
    CREATE TABLE #programasCoordinador (id UNIQUEIDENTIFIER, nombre NVARCHAR(50));

    IF OBJECT_ID('tempdb..#programasDecano') IS NOT NULL DROP TABLE #programasDecano;
    CREATE TABLE #programasDecano (idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(50), idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(50));

    IF OBJECT_ID('tempdb..#facultadesAdmin') IS NOT NULL DROP TABLE #facultadesAdmin;
    CREATE TABLE #facultadesAdmin (idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(50));

    DECLARE @totalProgsCoord INT = 0;
    DECLARE @idProgUnico UNIQUEIDENTIFIER = NULL;

    IF @codPerfilEjecutor = 'CD'
    BEGIN
        INSERT INTO #programasCoordinador (id, nombre)
        SELECT p.id, UPPER(LTRIM(RTRIM(p.nombre)))
        FROM dbo.Programa p
        INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
        WHERE c.usuario = @idUsuarioEjecutor AND p.estado = 1;

        SELECT @totalProgsCoord = COUNT(*) FROM #programasCoordinador;
        IF @totalProgsCoord = 1
            SELECT @idProgUnico = id FROM #programasCoordinador;
    END
    ELSE IF @codPerfilEjecutor = 'DE'
    BEGIN
        INSERT INTO #programasDecano (idFacultad, nombreFacultad, idPrograma, nombrePrograma)
        SELECT f.id, UPPER(LTRIM(RTRIM(f.nombre))), p.id, UPPER(LTRIM(RTRIM(p.nombre)))
        FROM dbo.Facultad f
        INNER JOIN dbo.Decano d ON d.id = f.decano
        LEFT JOIN dbo.Programa p ON p.facultad = f.id AND p.estado = 1
        WHERE d.usuario = @idUsuarioEjecutor AND f.estado = 1;
    END
    ELSE IF @codPerfilEjecutor = 'AD'
    BEGIN
        INSERT INTO #facultadesAdmin (idFacultad, nombreFacultad)
        SELECT f.id, UPPER(LTRIM(RTRIM(f.nombre)))
        FROM dbo.Facultad f
        INNER JOIN dbo.Administrador a ON a.institucion = f.institucion
        WHERE a.usuario = @idUsuarioEjecutor AND f.estado = 1;
    END

    -- PASO 8: Evaluacion fila por fila
    IF OBJECT_ID('tempdb..#salida') IS NOT NULL DROP TABLE #salida;
    CREATE TABLE #salida (
        numeroFila            INT,
        esValida              BIT,
        yaExiste              BIT,
        codigoMensaje         VARCHAR(20),
        mensajeUsuario        NVARCHAR(4000),
        idTipoIdentificacion  UNIQUEIDENTIFIER,
        idTipoVinculacion     UNIQUEIDENTIFIER,
        idPrograma            UNIQUEIDENTIFIER,
        idFacultad            UNIQUEIDENTIFIER,
        idUsuarioExistente    UNIQUEIDENTIFIER
    );

    DECLARE curFilas CURSOR LOCAL FAST_FORWARD FOR
        SELECT numeroFila, tipoDocumento, numeroDocumento, correo, codigoTipoVinculacion, codigoPrograma, codigoFacultad
        FROM #filasEntrada
        ORDER BY numeroFila ASC;

    OPEN curFilas;

    DECLARE @curFila INT, @curTipoDoc NVARCHAR(50), @curNumDoc INT, @curCorreo NVARCHAR(255);
    DECLARE @curTipoVinc NVARCHAR(50), @curCodProg NVARCHAR(50), @curCodFac NVARCHAR(50);

    FETCH NEXT FROM curFilas INTO @curFila, @curTipoDoc, @curNumDoc, @curCorreo, @curTipoVinc, @curCodProg, @curCodFac;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @esValida BIT = 1;
        DECLARE @yaExiste BIT = 0;
        DECLARE @codigoMensaje VARCHAR(20) = NULL;
        DECLARE @mensajeUsuario NVARCHAR(4000) = NULL;
        DECLARE @mensajeTecnico NVARCHAR(4000) = NULL;

        DECLARE @idTipoDoc UNIQUEIDENTIFIER = NULL;
        DECLARE @idTipoVinc UNIQUEIDENTIFIER = NULL;
        DECLARE @idProg UNIQUEIDENTIFIER = NULL;
        DECLARE @idFac UNIQUEIDENTIFIER = NULL;
        DECLARE @idUsuarioExistente UNIQUEIDENTIFIER = NULL;

        -- 1. Duplicado en el mismo archivo (CMA_010)
        DECLARE @lineaPrevia INT = (
            SELECT TOP 1 numeroFila
            FROM #filasEntrada
            WHERE numeroFila < @curFila
              AND ((numeroDocumento = @curNumDoc AND tipoDocumento = @curTipoDoc) OR correo = @curCorreo)
            ORDER BY numeroFila ASC
        );

        IF @lineaPrevia IS NOT NULL
        BEGIN
            SET @esValida = 0;
            SET @codigoMensaje = 'CMA_010';
            DECLARE @lineaPreviaStr VARCHAR(20) = CAST(@lineaPrevia AS VARCHAR(20));
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_010', @p_param1 = @lineaPreviaStr,
                @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnico OUTPUT;
        END

        -- 2. Catalogo tipo de documento (CMA_006)
        IF @esValida = 1
        BEGIN
            SELECT TOP 1 @idTipoDoc = id 
            FROM dbo.TipoIdentificacion 
            WHERE tipoIdentificacion = @curTipoDoc;

            IF @idTipoDoc IS NULL
            BEGIN
                SET @esValida = 0;
                SET @codigoMensaje = 'CMA_006';
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_006', @p_param1 = 'tipo de documento', @p_param2 = @curTipoDoc,
                    @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnico OUTPUT;
            END
        END

        -- 3. Catalogo tipo de vinculacion para DOCENTE (CMA_006)
        IF @esValida = 1 AND @codPerfilDestino = 'DO'
        BEGIN
            IF @curTipoVinc IS NULL OR @curTipoVinc = N''
            BEGIN
                SET @esValida = 0;
                SET @codigoMensaje = 'CMA_006';
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_006', @p_param1 = 'tipo de vinculación', @p_param2 = '(vacío)',
                    @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnico OUTPUT;
            END
            ELSE
            BEGIN
                SELECT TOP 1 @idTipoVinc = id 
                FROM dbo.TipoVinculacion 
                WHERE codigo = @curTipoVinc;

                IF @idTipoVinc IS NULL
                BEGIN
                    SET @esValida = 0;
                    SET @codigoMensaje = 'CMA_006';
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_006', @p_param1 = 'tipo de vinculación', @p_param2 = @curTipoVinc,
                        @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnico OUTPUT;
                END
            END
        END

        -- 4. Ambito segun rol (CMA_007)
        IF @esValida = 1
        BEGIN
            IF @codPerfilDestino = 'DO'
            BEGIN
                IF @curCodProg IS NOT NULL AND @curCodProg <> N''
                BEGIN
                    SELECT @idProg = id FROM #programasCoordinador WHERE nombre = UPPER(LTRIM(RTRIM(@curCodProg)));
                    IF @idProg IS NULL
                    BEGIN
                        SET @esValida = 0;
                        SET @codigoMensaje = 'CMA_007';
                        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_007', @p_param1 = @curCodProg,
                            @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnico OUTPUT;
                    END
                END
                ELSE
                BEGIN
                    IF @totalProgsCoord = 1
                    BEGIN
                        SET @idProg = @idProgUnico;
                    END
                    ELSE
                    BEGIN
                        SET @esValida = 0;
                        SET @codigoMensaje = 'CMA_007';
                        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_007', @p_param1 = 'programa',
                            @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnico OUTPUT;
                    END
                END
            END
            ELSE IF @codPerfilDestino = 'CD'
            BEGIN
                IF @curCodProg IS NULL OR @curCodProg = N''
                BEGIN
                    SET @esValida = 0;
                    SET @codigoMensaje = 'CMA_007';
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_007', @p_param1 = 'programa',
                        @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnico OUTPUT;
                END
                ELSE
                BEGIN
                    SELECT @idProg = idPrograma, @idFac = idFacultad FROM #programasDecano WHERE nombrePrograma = UPPER(LTRIM(RTRIM(@curCodProg)));
                    IF @idProg IS NULL
                    BEGIN
                        SET @esValida = 0;
                        SET @codigoMensaje = 'CMA_007';
                        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_007', @p_param1 = @curCodProg,
                            @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnico OUTPUT;
                    END
                END
            END
            ELSE IF @codPerfilDestino = 'DE'
            BEGIN
                IF @curCodFac IS NOT NULL AND @curCodFac <> N''
                BEGIN
                    SELECT @idFac = idFacultad FROM #facultadesAdmin WHERE nombreFacultad = UPPER(LTRIM(RTRIM(@curCodFac)));
                    IF @idFac IS NULL
                    BEGIN
                        SET @esValida = 0;
                        SET @codigoMensaje = 'CMA_007';
                        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_007', @p_param1 = @curCodFac,
                            @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnico OUTPUT;
                    END
                END
            END
        END

        -- 5. Consistencia de identidad (CMA_008)
        IF @esValida = 1
        BEGIN
            DECLARE @uDoc UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Usuario WHERE numeroIdentificacion = @curNumDoc);
            DECLARE @uCorreo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Usuario WHERE correo = @curCorreo);

            IF @uDoc IS NOT NULL AND @uCorreo IS NOT NULL AND @uDoc <> @uCorreo
            BEGIN
                SET @esValida = 0;
                SET @codigoMensaje = 'CMA_008';
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'CMA_008',
                    @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnico OUTPUT;
            END
            ELSE
            BEGIN
                SET @idUsuarioExistente = COALESCE(@uDoc, @uCorreo);
            END
        END

        -- 6. Verificar si yaExiste en el rol/ambito (SUPUESTO-D-11)
        IF @esValida = 1 AND @idUsuarioExistente IS NOT NULL
        BEGIN
            IF @codPerfilDestino = 'DO'
            BEGIN
                IF EXISTS (
                    SELECT 1 
                    FROM dbo.Docente d 
                    INNER JOIN dbo.DocentePrograma dp ON dp.docente = d.id 
                    WHERE d.usuario = @idUsuarioExistente AND dp.programa = @idProg
                )
                BEGIN
                    SET @yaExiste = 1;
                END
            END
            ELSE IF @codPerfilDestino = 'CD'
            BEGIN
                IF EXISTS (
                    SELECT 1 
                    FROM dbo.Coordinador c 
                    INNER JOIN dbo.Programa p ON p.coordinador = c.id 
                    WHERE c.usuario = @idUsuarioExistente AND p.id = @idProg
                )
                BEGIN
                    SET @yaExiste = 1;
                END
            END
            ELSE IF @codPerfilDestino = 'DE'
            BEGIN
                IF EXISTS (
                    SELECT 1 
                    FROM dbo.Decano d 
                    INNER JOIN dbo.Facultad f ON f.decano = d.id 
                    WHERE d.usuario = @idUsuarioExistente AND (@idFac IS NULL OR f.id = @idFac)
                )
                BEGIN
                    SET @yaExiste = 1;
                END
            END
        END

        INSERT INTO #salida (
            numeroFila, esValida, yaExiste, codigoMensaje, mensajeUsuario,
            idTipoIdentificacion, idTipoVinculacion, idPrograma, idFacultad, idUsuarioExistente
        )
        VALUES (
            @curFila, @esValida, @yaExiste, @codigoMensaje, @mensajeUsuario,
            @idTipoDoc, @idTipoVinc, @idProg, @idFac, @idUsuarioExistente
        );

        FETCH NEXT FROM curFilas INTO @curFila, @curTipoDoc, @curNumDoc, @curCorreo, @curTipoVinc, @curCodProg, @curCodFac;
    END

    CLOSE curFilas;
    DEALLOCATE curFilas;

    -- PASO 9: Emitir resultset
    SELECT 
        numeroFila,
        esValida,
        yaExiste,
        codigoMensaje,
        mensajeUsuario,
        idTipoIdentificacion,
        idTipoVinculacion,
        idPrograma,
        idFacultad,
        idUsuarioExistente
    FROM #salida
    ORDER BY numeroFila ASC;
END
GO

-- ---- parametros y metadato de edicion ----
-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, HU171): parametros de carga masiva por CSV y tipo doc defecto.
-- ============================================================================
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('CARGA_MASIVA', 'MAXIMO_FILAS',                  N'100',     'INT',    N'100'),
    ('CARGA_MASIVA', 'TAMANIO_MAXIMO_BYTES',          N'1048576', 'INT',    N'1048576'),
    ('CARGA_MASIVA', 'LIMITE_POR_MINUTO',             N'3',       'INT',    N'3'),
    ('IDENTIDAD',    'TIPO_IDENTIFICACION_DEFECTO',   N'CC',      'STRING', N'CC')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

IF OBJECT_ID('dbo.CatalogoParametroEdicion', 'U') IS NOT NULL
BEGIN
    MERGE INTO [dbo].[CatalogoParametroEdicion] AS Target
    USING (
        SELECT  p.id AS parametro, v.esEditable, v.valorMinimo, v.valorMaximo, v.valoresPermitidos, NULL AS parametroDebeSerMenorQue,
                v.etiqueta, v.descripcion, v.unidad, v.categoriaVisual, v.orden
        FROM (VALUES
            ('CARGA_MASIVA', 'MAXIMO_FILAS',         CONVERT(BIT, 1), CONVERT(DECIMAL(19,4), 1),     CONVERT(DECIMAL(19,4), 500),     NULL, N'Máximo de filas por carga',          N'Filas máximas de un archivo de carga masiva de cuentas.', N'filas',      N'Carga masiva', CONVERT(SMALLINT, 10)),
            ('CARGA_MASIVA', 'LIMITE_POR_MINUTO',    1,               1,                             20,                              NULL, N'Límite de cargas por minuto',         N'Cargas masivas por minuto permitidas a un mismo usuario.', N'por minuto', N'Carga masiva', 20),
            ('CARGA_MASIVA', 'TAMANIO_MAXIMO_BYTES', 1,               10240,                         2097152,                         NULL, N'Tamaño máximo del archivo de carga',  N'Bytes máximos del archivo CSV de una carga masiva.',       N'bytes',      N'Carga masiva', 30)
        ) AS v (grupo, clave, esEditable, valorMinimo, valorMaximo, valoresPermitidos, etiqueta, descripcion, unidad, categoriaVisual, orden)
        INNER JOIN [dbo].[CatalogoParametro] p ON p.grupo = v.grupo AND p.clave = v.clave
    ) AS Source
    ON (Target.parametro = Source.parametro)
    WHEN MATCHED THEN
        UPDATE SET Target.esEditable = Source.esEditable, Target.valorMinimo = Source.valorMinimo, Target.valorMaximo = Source.valorMaximo,
                   Target.valoresPermitidos = Source.valoresPermitidos, Target.etiqueta = Source.etiqueta,
                   Target.descripcion = Source.descripcion, Target.unidad = Source.unidad,
                   Target.categoriaVisual = Source.categoriaVisual, Target.orden = Source.orden
    WHEN NOT MATCHED THEN
        INSERT (parametro, esEditable, valorMinimo, valorMaximo, valoresPermitidos, parametroDebeSerMenorQue, etiqueta, descripcion, unidad, categoriaVisual, orden)
        VALUES (Source.parametro, Source.esEditable, Source.valorMinimo, Source.valorMaximo, Source.valoresPermitidos, Source.parametroDebeSerMenorQue,
                Source.etiqueta, Source.descripcion, Source.unidad, Source.categoriaVisual, Source.orden);
END
GO

-- ---- mensajes ----
-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, HU171): mensajes de carga masiva de usuarios por CSV.
-- Idempotente (MERGE por codigo).
-- ============================================================================
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('CMA_001', 'VALIDATION_ERROR', 'MEDIO', N'El archivo supera {} filas.'),
    ('CMA_002', 'VALIDATION_ERROR', 'MEDIO', N'El archivo supera el tamaño permitido.'),
    ('CMA_003', 'BUSINESS_ERROR',   'ALTO',  N'El archivo cambió desde la validación. Valídalo de nuevo.'),
    ('CMA_004', 'VALIDATION_ERROR', 'MEDIO', N'La cabecera no coincide con la plantilla: {}.'),
    ('CMA_005', 'VALIDATION_ERROR', 'BAJO',  N'Número de documento inválido.'),
    ('CMA_006', 'VALIDATION_ERROR', 'BAJO',  N'Código de {} desconocido: {}.'),
    ('CMA_007', 'BUSINESS_ERROR',   'MEDIO', N'«{}» no está en tu ámbito.'),
    ('CMA_008', 'BUSINESS_ERROR',   'MEDIO', N'El documento y el correo corresponden a personas distintas.'),
    ('CMA_009', 'BUSINESS_ERROR',   'ALTO',  N'Tu rol no puede cargar este tipo de cuentas.'),
    ('CMA_010', 'VALIDATION_ERROR', 'BAJO',  N'Fila repetida en el archivo (línea {}).'),
    ('CMA_011', 'VALIDATION_ERROR', 'MEDIO', N'Valor no permitido en la columna {}.'),
    ('CMA_012', 'VALIDATION_ERROR', 'BAJO',  N'Falta la clave inicial para una persona nueva.'),
    ('CMA_013', 'VALIDATION_ERROR', 'MEDIO', N'El archivo no es un CSV UTF-8 válido.'),
    ('CMA_014', 'BUSINESS_ERROR',   'MEDIO', N'Has superado el número de cargas por minuto.'),
    ('CMA_015', 'SUCCESS',          'BAJO',  N'Carga procesada: {} creadas, {} ya existentes, {} con error.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('CMA_001', 'VALIDATION_ERROR', 'MEDIO', N'HU171: cantidad de filas {} supera CARGA_MASIVA/MAXIMO_FILAS ({}).'),
    ('CMA_002', 'VALIDATION_ERROR', 'MEDIO', N'HU171: tamano de archivo {} bytes supera CARGA_MASIVA/TAMANIO_MAXIMO_BYTES ({}).'),
    ('CMA_003', 'BUSINESS_ERROR',   'ALTO',  N'HU171: huella SHA-256 no coincide con la validada previamente.'),
    ('CMA_004', 'VALIDATION_ERROR', 'MEDIO', N'HU171: cabecera del CSV no valida o incompleta: {}.'),
    ('CMA_005', 'VALIDATION_ERROR', 'BAJO',  N'HU171: numero de documento no es un entero positivo en rango INT.'),
    ('CMA_006', 'VALIDATION_ERROR', 'BAJO',  N'HU171: codigo de {} ''{}'' no existe en catalogo.'),
    ('CMA_007', 'BUSINESS_ERROR',   'MEDIO', N'HU171: entidad ''{}'' no pertenece al ambito de custodia del ejecutor.'),
    ('CMA_008', 'BUSINESS_ERROR',   'MEDIO', N'HU171: documento y correo corresponden a diferentes personas existentes.'),
    ('CMA_009', 'BUSINESS_ERROR',   'ALTO',  N'HU171: jerarquia no permitida en JerarquiaAltaUsuario para este perfil ejecutor y destino.'),
    ('CMA_010', 'VALIDATION_ERROR', 'BAJO',  N'HU171: documento o correo repetido respecto a la linea {}.'),
    ('CMA_011', 'VALIDATION_ERROR', 'MEDIO', N'HU171: intento de inyeccion de formulas o caracteres no permitidos en columna {}.'),
    ('CMA_012', 'VALIDATION_ERROR', 'BAJO',  N'HU171: persona nueva requiere clave inicial valida segun PasswordRegistroRule.'),
    ('CMA_013', 'VALIDATION_ERROR', 'MEDIO', N'HU171: codificacion del archivo no es UTF-8 valida o archivo malformado.'),
    ('CMA_014', 'BUSINESS_ERROR',   'MEDIO', N'HU171: tasa de peticiones supera CARGA_MASIVA/LIMITE_POR_MINUTO.'),
    ('CMA_015', 'SUCCESS',          'BAJO',  N'HU171: resultado de ejecucion: creadas={}, yaExistentes={}, conError={}.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- ---- jerarquia ----
-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, [SUPUESTO-D-15], HU171): jerarquia de alta masiva.
-- Pares:
--   COORDINADOR (CD)   -> DOCENTE (DO)
--   DECANO (DE)        -> COORDINADOR (CD)
--   ADMINISTRADOR (AD) -> DECANO (DE)
-- ============================================================================
MERGE INTO dbo.JerarquiaAltaUsuario AS Target
USING (
    SELECT 
        NEWID() AS id,
        pe.id AS perfilEjecutor,
        pd.id AS perfilDestino
    FROM (VALUES
        ('CD', 'DO'),
        ('DE', 'CD'),
        ('AD', 'DE')
    ) AS v(codEjecutor, codDestino)
    INNER JOIN dbo.Perfil pe ON (pe.codigo = v.codEjecutor OR UPPER(pe.nombre) = CASE v.codEjecutor WHEN 'CD' THEN 'COORDINADOR' WHEN 'DE' THEN 'DECANO' WHEN 'AD' THEN 'ADMINISTRADOR' END)
    INNER JOIN dbo.Perfil pd ON (pd.codigo = v.codDestino OR UPPER(pd.nombre) = CASE v.codDestino WHEN 'DO' THEN 'DOCENTE' WHEN 'CD' THEN 'COORDINADOR' WHEN 'DE' THEN 'DECANO' END)
) AS Source
ON (Target.perfilEjecutor = Source.perfilEjecutor AND Target.perfilDestino = Source.perfilDestino)
WHEN NOT MATCHED THEN
    INSERT (id, perfilEjecutor, perfilDestino)
    VALUES (Source.id, Source.perfilEjecutor, Source.perfilDestino);
GO

-- ---- permisos ----
-- ============================================================================
-- CULM-001 D.5 (CONTRACT §6.3, HU171): permisos para validacion de carga masiva.
-- ============================================================================
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_validar_carga_masiva_usuarios] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.uv_jerarquia_alta_usuario', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_jerarquia_alta_usuario] TO [rol_asistencias_runtime];
GO
PRINT 'MIGRACION 44 DOWN OK';
GO
