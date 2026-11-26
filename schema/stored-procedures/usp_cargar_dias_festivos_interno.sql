USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cargar_dias_festivos_interno (CULM-001 B.1; CONTRACT §2.7.4) — nucleo, sin EXECUTE para el rol runtime.
-- SKILLS-BD lote 2 (2026-11-25): antes usp_internal_cargar_dias_festivos (renombrado, D3); el cuerpo se corrige en su lote de dominio.
--
-- Carga (o recarga) los festivos de un anio recibidos del backend: la BD nunca llama a internet.
--   @festivosJSON = [{"fecha":"YYYY-MM-DD","nombre":"..."}] con exactamente esas 2 claves por elemento.
-- Validaciones sin escrituras:
--   FES_001 anio fuera de FESTIVOS/ANIO_MINIMO..ANIO_MAXIMO; FES_004 fuente fuera de FESTIVOS/FUENTES_VALIDAS;
--   FES_002 JSON invalido, elemento que no es objeto, clave distinta de fecha/nombre (o ausente), fecha invalida o de
--   otro anio, fecha repetida, nombre vacio o > 120, @diferenciasCalculoLocal NULL o < 0;
--   FES_003 total fuera de FESTIVOS/MINIMO_POR_ANIO..MAXIMO_POR_ANIO.
-- Escritura (transaccion propia o SAVE TRANSACTION): el rango del anio en dbo.DiaFestivo se bloquea con UPDLOCK +
-- HOLDLOCK (serializa job y administrador sobre el mismo anio) y un MERGE limitado al anio inserta las fechas nuevas,
-- actualiza las existentes (nombre, fuente, estaActivo = 1, fecha y correlacion de carga) y desactiva las que ya no
-- vienen (estaActivo = 0; nunca DELETE: SesionCancelacion puede referenciarlas). Registra dbo.CargaDiaFestivo.
-- Idempotente: dos cargas con el mismo JSON dejan el mismo conjunto activo (segunda: 0 insertados, N actualizados).
-- fechaCargaUtc es estrictamente creciente por anio (si coincide con la ultima carga se toma el segundo siguiente)
-- para que uv_carga_dia_festivo.esUltimaCargaAnio sea determinista.
-- ============================================================================
-- SKILLS-BD lote 9 (2026-11-26): PASO n, IF con BEGIN/END y sin ISNULL sobre variables (IIF equivalentes; quedan los ISNULL sobre agregaciones, permitidos). Los bloqueos y el MERGE siguen en las tablas. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_cargar_dias_festivos_interno]
(
    @anio                     INT,
    @festivosJSON             NVARCHAR(MAX),
    @fuente                   NVARCHAR(40),
    @diferenciasCalculoLocal  INT,
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER,
    @festivosInsertados       INT OUTPUT,
    @festivosActualizados     INT OUTPUT,
    @festivosDesactivados     INT OUTPUT,
    @mensajeUsuarioResultado  NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000) OUTPUT,
    @estadoResultado          BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @anioMinimo   INT = dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'ANIO_MINIMO');
    DECLARE @anioMaximo   INT = dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'ANIO_MAXIMO');
    DECLARE @minimoPorAnio INT = dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'MINIMO_POR_ANIO');
    DECLARE @maximoPorAnio INT = dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'MAXIMO_POR_ANIO');
    DECLARE @fuentesValidas NVARCHAR(MAX) = dbo.ufn_obtener_parametro('FESTIVOS', 'FUENTES_VALIDAS');
    DECLARE @fuenteLimpia NVARCHAR(40) = LTRIM(RTRIM(@fuente));

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @codigoRechazo  VARCHAR(20) = NULL;
    DECLARE @detalleRechazo NVARCHAR(500) = NULL;
    DECLARE @totalFestivos  INT = 0;
    DECLARE @fechaCarga     DATETIME2(0);
    DECLARE @ultimaCarga    DATETIME2(0);
    DECLARE @bloqueo        INT;
    DECLARE @anioTexto      NVARCHAR(20) = CONVERT(NVARCHAR(20), @anio);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500), @p3 NVARCHAR(500);
    DECLARE @mensajeUsuarioExito NVARCHAR(4000);

    DECLARE @items TABLE (
        idx          INT           NOT NULL,
        tipoElemento INT           NOT NULL,
        claves       INT           NOT NULL,
        clavesExtra  INT           NOT NULL,
        fechaTexto   NVARCHAR(4000) NULL,
        tipoFecha    INT           NULL,
        nombre       NVARCHAR(4000) NULL,
        tipoNombre   INT           NULL,
        fecha        DATE          NULL
    );
    DECLARE @acciones TABLE (accion NVARCHAR(10) NOT NULL, activo BIT NULL);

    SELECT
        @festivosInsertados = 0,
        @festivosActualizados = 0,
        @festivosDesactivados = 0,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: validaciones sin escrituras (FES_001, FES_004, FES_002, FES_003)
        IF @estadoResultado = 1
        BEGIN
            IF @anio IS NULL OR @anioMinimo IS NULL OR @anioMaximo IS NULL OR @anio < @anioMinimo OR @anio > @anioMaximo
            BEGIN
                SELECT @codigoRechazo = 'FES_001', @detalleRechazo = IIF(@anioTexto IS NULL, N'NULL', @anioTexto);
            END
            ELSE IF @fuenteLimpia IS NULL OR @fuenteLimpia = N''
                 OR NOT EXISTS (SELECT 1 FROM STRING_SPLIT(@fuentesValidas, N',') f
                                WHERE LTRIM(RTRIM(f.value)) COLLATE Latin1_General_BIN2 = @fuenteLimpia COLLATE Latin1_General_BIN2)
            BEGIN
                SELECT @codigoRechazo = 'FES_004', @detalleRechazo = IIF(@fuenteLimpia IS NULL, N'NULL', @fuenteLimpia);
            END
            ELSE IF @diferenciasCalculoLocal IS NULL OR @diferenciasCalculoLocal < 0
            BEGIN
                SELECT @codigoRechazo = 'FES_002', @detalleRechazo = N'diferenciasCalculoLocal NULL o negativo';
            END
            ELSE IF @festivosJSON IS NULL OR ISJSON(@festivosJSON) <> 1 OR LEFT(LTRIM(@festivosJSON), 1) <> N'['
            BEGIN
                SELECT @codigoRechazo = 'FES_002', @detalleRechazo = N'no es un arreglo JSON';
            END
        END

        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            -- PASO 2.1: elementos del JSON (ISNULL sobre agregacion (permitido): COUNT/SUM del OUTER APPLY)
            INSERT INTO @items (idx, tipoElemento, claves, clavesExtra, fechaTexto, tipoFecha, nombre, tipoNombre)
            SELECT  TRY_CAST(e.[key] AS INT),
                    e.[type],
                    ISNULL(k.claves, 0),
                    ISNULL(k.clavesExtra, 0),
                    k.fechaTexto,
                    k.tipoFecha,
                    k.nombre,
                    k.tipoNombre
            FROM OPENJSON(@festivosJSON) e
            OUTER APPLY (
                SELECT  claves = COUNT(1),
                        clavesExtra = SUM(IIF(c.[key] COLLATE Latin1_General_BIN2 IN (N'fecha', N'nombre'), 0, 1)),
                        fechaTexto = MAX(IIF(c.[key] COLLATE Latin1_General_BIN2 = N'fecha', c.[value], NULL)),
                        tipoFecha = MAX(IIF(c.[key] COLLATE Latin1_General_BIN2 = N'fecha', c.[type], NULL)),
                        nombre = MAX(IIF(c.[key] COLLATE Latin1_General_BIN2 = N'nombre', c.[value], NULL)),
                        tipoNombre = MAX(IIF(c.[key] COLLATE Latin1_General_BIN2 = N'nombre', c.[type], NULL))
                FROM OPENJSON(IIF(e.[type] = 5, e.[value], N'{}')) c
            ) k;

            UPDATE @items
            SET fecha = IIF(tipoFecha = 1 AND LEN(fechaTexto) = 10 AND fechaTexto LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]',
                            TRY_CONVERT(DATE, fechaTexto, 23), NULL),
                nombre = LTRIM(RTRIM(nombre));

            SET @totalFestivos = (SELECT COUNT(1) FROM @items);

            IF EXISTS (SELECT 1 FROM @items WHERE tipoElemento <> 5)
            BEGIN
                SELECT @codigoRechazo = 'FES_002', @detalleRechazo = N'un elemento no es un objeto';
            END
            ELSE IF EXISTS (SELECT 1 FROM @items WHERE claves <> 2 OR clavesExtra <> 0 OR tipoFecha IS NULL OR tipoNombre IS NULL)
            BEGIN
                SELECT @codigoRechazo = 'FES_002', @detalleRechazo = N'cada elemento debe tener exactamente las claves fecha y nombre';
            END
            ELSE IF EXISTS (SELECT 1 FROM @items WHERE fecha IS NULL OR YEAR(fecha) <> @anio)
            BEGIN
                SELECT @codigoRechazo = 'FES_002', @detalleRechazo = CONCAT(N'fecha invalida o fuera del anio ', @anioTexto);
            END
            ELSE IF EXISTS (SELECT 1 FROM @items GROUP BY fecha HAVING COUNT(1) > 1)
            BEGIN
                SELECT @codigoRechazo = 'FES_002', @detalleRechazo = N'fecha repetida';
            END
            ELSE IF EXISTS (SELECT 1 FROM @items WHERE tipoNombre <> 1 OR nombre IS NULL OR LEN(nombre) = 0 OR LEN(nombre) > 120)
            BEGIN
                SELECT @codigoRechazo = 'FES_002', @detalleRechazo = N'nombre vacio o de mas de 120 caracteres';
            END
            ELSE IF @minimoPorAnio IS NULL OR @maximoPorAnio IS NULL OR @totalFestivos < @minimoPorAnio OR @totalFestivos > @maximoPorAnio
            BEGIN
                SELECT @codigoRechazo = 'FES_003', @detalleRechazo = CONVERT(NVARCHAR(20), @totalFestivos);
            END
        END

        -- PASO 2.2: rechazo de validacion por codigo del catalogo
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @detalleRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: escritura atomica del anio
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cargar_dias_festivos;
                SET @savepointCreado = 1;
            END

            -- Serializa las cargas del mismo anio (job y administrador)
            SELECT @bloqueo = COUNT(1) FROM dbo.DiaFestivo WITH (UPDLOCK, HOLDLOCK, INDEX(IX_DiaFestivo_anio)) WHERE anio = @anio;
            SELECT @ultimaCarga = MAX(c.fechaCargaUtc) FROM dbo.CargaDiaFestivo c WITH (UPDLOCK, HOLDLOCK) WHERE c.anio = @anio;

            SET @fechaCarga = CAST(SYSUTCDATETIME() AS DATETIME2(0));
            IF @ultimaCarga IS NOT NULL AND @ultimaCarga >= @fechaCarga
            BEGIN
                SET @fechaCarga = DATEADD(SECOND, 1, @ultimaCarga);
            END

            MERGE dbo.DiaFestivo WITH (HOLDLOCK) AS destino
            USING (SELECT fecha, nombre FROM @items) AS origen
            ON destino.fecha = origen.fecha
            WHEN MATCHED THEN
                UPDATE SET destino.nombre = origen.nombre,
                           destino.fuente = @fuenteLimpia,
                           destino.estaActivo = 1,
                           destino.fechaCargaUtc = @fechaCarga,
                           destino.idCorrelacionCarga = @idCorrelacionDefecto
            WHEN NOT MATCHED BY TARGET THEN
                INSERT (fecha, nombre, fuente, estaActivo, fechaCargaUtc, idCorrelacionCarga)
                VALUES (origen.fecha, origen.nombre, @fuenteLimpia, 1, @fechaCarga, @idCorrelacionDefecto)
            WHEN NOT MATCHED BY SOURCE AND destino.anio = @anio AND destino.estaActivo = 1 THEN
                UPDATE SET destino.estaActivo = 0
            OUTPUT $action, inserted.estaActivo INTO @acciones (accion, activo);

            -- ISNULL sobre agregacion (permitido): SUM sin filas devuelve NULL
            SELECT
                @festivosInsertados = ISNULL(SUM(IIF(accion = N'INSERT', 1, 0)), 0),
                @festivosActualizados = ISNULL(SUM(IIF(accion = N'UPDATE' AND activo = 1, 1, 0)), 0),
                @festivosDesactivados = ISNULL(SUM(IIF(accion = N'UPDATE' AND activo = 0, 1, 0)), 0)
            FROM @acciones;

            INSERT INTO dbo.CargaDiaFestivo (anio, fuente, totalFestivos, festivosInsertados, festivosActualizados, festivosDesactivados,
                                             diferenciasCalculoLocal, usuarioEjecutor, fechaCargaUtc, idCorrelacion)
            VALUES (@anio, @fuenteLimpia, @totalFestivos, @festivosInsertados, @festivosActualizados, @festivosDesactivados,
                    @diferenciasCalculoLocal, @idUsuarioEjecutor, @fechaCarga, @idCorrelacionDefecto);

            -- FES_005: usuario (total, anio); tecnico (anio, insertados, actualizados, desactivados)
            SET @p1 = CONVERT(NVARCHAR(20), @totalFestivos);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FES_005', @p_param1 = @p1, @p_param2 = @anioTexto,
                @mensajeUsuarioResultado = @mensajeUsuarioExito OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SELECT @p1 = @anioTexto, @p2 = CONVERT(NVARCHAR(20), @festivosInsertados), @p3 = CONVERT(NVARCHAR(20), @festivosActualizados);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FES_005', @p_param1 = @p1, @p_param2 = @p2, @p_param3 = @p3,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            IF CHARINDEX(N'{}', @mensajeTecnicoResultado) > 0
            BEGIN
                SET @mensajeTecnicoResultado = STUFF(@mensajeTecnicoResultado, CHARINDEX(N'{}', @mensajeTecnicoResultado), 2, CONVERT(NVARCHAR(20), @festivosDesactivados));
            END
            SET @mensajeUsuarioResultado = @mensajeUsuarioExito;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, N' Fuente: ', @fuenteLimpia, N'. Correlacion: ', @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        -- PASO 4: Revertir lo propio; con transaccion del llamador no confirmable relanza, si no responde SYS_001
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_cargar_dias_festivos;
        END

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SELECT @estadoResultado = 0, @festivosInsertados = 0, @festivosActualizados = 0, @festivosDesactivados = 0;
    END CATCH
END;
GO
