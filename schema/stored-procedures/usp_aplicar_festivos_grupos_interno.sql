USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_aplicar_festivos_grupos_interno (CULM-001 B.1; CONTRACT §2.7.5) — nucleo, sin EXECUTE para el rol runtime.
-- SKILLS-BD lote 2 (2026-11-25): antes usp_internal_aplicar_festivos_grupos (renombrado, D3); sin cursor (WHILE sobre la tabla
-- variable), triplete OUTPUT, PASO n, IF con BEGIN/END, seleccion por vistas (uv_grupo, uv_sesion) y SYS_001 en el CATCH.
--
-- Selecciona los grupos y aplica usp_aplicar_festivos_grupo_interno (@soloFuturas = 1) a cada uno en su PROPIA
-- transaccion (o savepoint si el llamador ya tiene una): un grupo con error no deshace los anteriores y se cuenta en
-- @gruposConError (su detalle queda en @mensajeTecnicoResultado). Una transaccion externa condenada se propaga (THROW).
-- Seleccion de grupos (tabla variable, sin tablas temporales, para que los SP publicos sigan siendo describibles por
-- sp_describe_first_result_set):
--   * @idPeriodoAcademico NOT NULL: los grupos del periodo (usp_aplicar_festivos_periodo con periodo);
--   * si no, @idUsuarioAdministrador NOT NULL: los grupos de los periodos de la institucion del administrador que se
--     cruzan con @anio (usp_aplicar_festivos_periodo con anio);
--   * si no: todos los grupos con sesiones cuya fecha local cae en @anio (usp_aplicar_festivos_automatico).
-- @estadoResultado = 1 aunque haya grupos con error (los cuenta @gruposConError, como antes); 0 solo ante un error fuera del
-- procesamiento por grupo.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_aplicar_festivos_grupos_interno]
(
    @idPeriodoAcademico       UNIQUEIDENTIFIER,
    @anio                     INT,
    @idUsuarioAdministrador   UNIQUEIDENTIFIER,
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER,
    @gruposProcesados         INT OUTPUT,
    @sesionesCanceladas       INT OUTPUT,
    @sesionesConAsistencia    INT OUTPUT,
    @gruposConError           INT OUTPUT,
    @mensajeUsuarioResultado  NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000) OUTPUT,
    @estadoResultado          BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoActual    UNIQUEIDENTIFIER;
    DECLARE @canceladas       INT;
    DECLARE @conAsistencia    INT;
    DECLARE @mensajeUsuario   NVARCHAR(4000);
    DECLARE @mensajeTecnico   NVARCHAR(4000);
    DECLARE @estado           BIT;
    DECLARE @transaccionPropia BIT;
    DECLARE @estadoTransaccion INT;
    DECLARE @zonaHorariaSqlServer SYSNAME = CONVERT(SYSNAME, dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER'));
    DECLARE @grupos TABLE (idGrupo UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: respuesta inicial y contadores
    SELECT @gruposProcesados = 0, @sesionesCanceladas = 0, @sesionesConAsistencia = 0, @gruposConError = 0;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        -- PASO 2: seleccion de grupos
        IF @idPeriodoAcademico IS NOT NULL
        BEGIN
            INSERT INTO @grupos (idGrupo)
            SELECT g.id FROM dbo.uv_grupo g WHERE g.idPeriodoAcademico = @idPeriodoAcademico;
        END
        ELSE IF @idUsuarioAdministrador IS NOT NULL
        BEGIN
            INSERT INTO @grupos (idGrupo)
            SELECT g.id
            FROM dbo.uv_grupo g
            INNER JOIN dbo.uv_periodo_academico pa ON pa.id = g.idPeriodoAcademico
            WHERE pa.fechaInicio <= DATEFROMPARTS(@anio, 12, 31) AND pa.fechaFin >= DATEFROMPARTS(@anio, 1, 1)
              AND pa.idInstitucion IN (SELECT a.idInstitucion FROM dbo.uv_administrador a WHERE a.idUsuario = @idUsuarioAdministrador);
        END
        ELSE IF @anio IS NOT NULL AND @zonaHorariaSqlServer IS NOT NULL
        BEGIN
            INSERT INTO @grupos (idGrupo)
            SELECT DISTINCT s.idGrupo
            FROM dbo.uv_sesion s
            WHERE YEAR(CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zonaHorariaSqlServer AS DATE)) = @anio;
        END

        -- PASO 3: cada grupo en su propia transaccion (o savepoint), en orden de id
        SELECT @idGrupoActual = MIN(idGrupo) FROM @grupos;
        WHILE @idGrupoActual IS NOT NULL
        BEGIN
            SELECT @canceladas = 0, @conAsistencia = 0, @estado = 1, @transaccionPropia = 0;
            BEGIN TRY
                IF @@TRANCOUNT = 0
                BEGIN
                    BEGIN TRANSACTION;
                    SET @transaccionPropia = 1;
                END
                ELSE
                BEGIN
                    SAVE TRANSACTION sp_aplicar_festivos_grupos;
                END

                EXEC dbo.usp_aplicar_festivos_grupo_interno
                    @idGrupo = @idGrupoActual,
                    @soloFuturas = 1,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @idUsuarioEjecutor = @idUsuarioEjecutor,
                    @sesionesCanceladas = @canceladas OUTPUT,
                    @sesionesConAsistencia = @conAsistencia OUTPUT,
                    @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnico OUTPUT,
                    @estadoResultado = @estado OUTPUT;

                SET @estadoTransaccion = XACT_STATE();
                IF @estadoTransaccion = -1
                BEGIN
                    -- El nucleo atrapo un error que condeno la transaccion
                    IF @transaccionPropia = 1
                    BEGIN
                        ROLLBACK TRANSACTION;
                    END
                    ELSE
                    BEGIN
                        THROW 51000, @mensajeTecnico, 1;
                    END
                    SET @estado = 0;
                END
                ELSE IF @transaccionPropia = 1
                BEGIN
                    -- Las ramas de rechazo del nucleo no escriben: se confirma igual
                    COMMIT TRANSACTION;
                END

                IF @estado = 1
                BEGIN
                    SELECT @gruposProcesados += 1, @sesionesCanceladas += @canceladas, @sesionesConAsistencia += @conAsistencia;
                END
                ELSE
                BEGIN
                    SET @gruposConError += 1;
                    SET @mensajeTecnicoResultado = @mensajeTecnico;
                END
            END TRY
            BEGIN CATCH
                -- PASO 3.1: error en este grupo: se revierte solo el grupo; una transaccion externa condenada se relanza
                SET @estadoTransaccion = XACT_STATE();
                IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
                BEGIN
                    ROLLBACK TRANSACTION;
                END
                ELSE IF @transaccionPropia = 0 AND @estadoTransaccion = -1
                BEGIN
                    THROW;
                END
                ELSE IF @transaccionPropia = 0 AND @estadoTransaccion = 1
                BEGIN
                    ROLLBACK TRANSACTION sp_aplicar_festivos_grupos;
                END
                SET @gruposConError += 1;
                SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
            END CATCH

            SELECT @idGrupoActual = MIN(idGrupo) FROM @grupos WHERE idGrupo > @idGrupoActual;
        END
    END TRY
    BEGIN CATCH
        -- PASO 4: error fuera del procesamiento por grupo (SYS_001); una transaccion externa condenada se relanza
        IF XACT_STATE() = -1 AND @@TRANCOUNT > 0
        BEGIN
            THROW;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
