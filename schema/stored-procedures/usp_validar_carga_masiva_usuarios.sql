USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

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
