USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_generar_sesiones_grupo]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    -- 1. Estandarización e inicialización de variables locales utilizando catálogo de parámetros (Sin ISNULL)
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @idPeriodo            UNIQUEIDENTIFIER;
    DECLARE @fechaInicio          DATE;
    DECLARE @fechaFin             DATE;
    DECLARE @currentDate          DATE;
    DECLARE @sesionesCreadas      INT = 0;
    DECLARE @numeroSesion         INT = 1;
    DECLARE @maxNumeroSesion      INT;

    DECLARE @fechaHoraInicio      DATETIME2;
    DECLARE @fechaHoraFin         DATETIME2;
    DECLARE @numSemana            INT;
    DECLARE @codigoVerif          NVARCHAR(50);
    DECLARE @nombreSesion         NVARCHAR(50);
    DECLARE @codigoDia            NVARCHAR(2);

    DECLARE @idHorario            UNIQUEIDENTIFIER;
    DECLARE @horaInicio           TIME;
    DECLARE @horaFin              TIME;
    DECLARE @hTotal               INT;
    DECLARE @hIterador            INT;

    -- Tablas temporales locales para resolver franjas horarias por día
    DECLARE @HorariosDelDia TABLE (
        idHorario  UNIQUEIDENTIFIER,
        horaInicio TIME,
        horaFin    TIME
    );

    DECLARE @HorariosOrdenados TABLE (
        secuencia  INT IDENTITY(1,1),
        horaInicio TIME,
        horaFin    TIME
    );

    -- Inicialización interna de variables de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación de presencia del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación del usuario ejecutor si es suministrado
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NOT NULL
        BEGIN
            EXEC dbo.usp_validar_usuario_existe_por_id_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validación de existencia del grupo académico
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validación de existencia de franjas horarias asociadas al grupo
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_horarios_grupo_interno
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validación de coherencia y vigencia de fechas del periodo académico
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_fechas_periodo_academico_interno
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Generación recurrente de sesiones de clase según el periodo académico y franjas horarias
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idPeriodo = periodoAcademico FROM dbo.Grupo WHERE id = @idGrupoDefecto;
            SELECT TOP 1 @fechaInicio = fechaInicio, @fechaFin = fechaFin FROM dbo.PeriodoAcademico WHERE id = @idPeriodo;

            SELECT @maxNumeroSesion = MAX(numero) FROM dbo.Sesion WHERE grupo = @idGrupoDefecto;
            IF @maxNumeroSesion IS NULL
            BEGIN
                SET @numeroSesion = 1;
            END
            ELSE
            BEGIN
                SET @numeroSesion = @maxNumeroSesion + 1;
            END

            SET @currentDate = @fechaInicio;
            SET @sesionesCreadas = 0;

            BEGIN TRANSACTION;

            WHILE @currentDate <= @fechaFin
            BEGIN
                -- Mapeo estandarizado del día de la semana (LU, MA, MI, JU, VI, SA, DO)
                SET @codigoDia = 
                    CASE LTRIM(RTRIM(LOWER(DATENAME(dw, @currentDate))))
                        WHEN 'monday' THEN 'LU' WHEN 'lunes' THEN 'LU'
                        WHEN 'tuesday' THEN 'MA' WHEN 'martes' THEN 'MA'
                        WHEN 'wednesday' THEN 'MI' WHEN 'miércoles' THEN 'MI' WHEN 'miercoles' THEN 'MI'
                        WHEN 'thursday' THEN 'JU' WHEN 'jueves' THEN 'JU'
                        WHEN 'friday' THEN 'VI' WHEN 'viernes' THEN 'VI'
                        WHEN 'saturday' THEN 'SA' WHEN 'sábado' THEN 'SA' WHEN 'sabado' THEN 'SA'
                        WHEN 'sunday' THEN 'DO' WHEN 'domingo' THEN 'DO'
                    END;

                DELETE FROM @HorariosDelDia;
                DELETE FROM @HorariosOrdenados;

                INSERT INTO @HorariosDelDia (idHorario, horaInicio, horaFin)
                SELECT h.id, h.horaInicio, h.horaFin
                FROM dbo.Horario h
                INNER JOIN dbo.Dia d ON h.dia = d.id
                WHERE h.grupo = @idGrupoDefecto AND d.codigo = @codigoDia;

                IF EXISTS (SELECT 1 FROM @HorariosDelDia)
                BEGIN
                    INSERT INTO @HorariosOrdenados (horaInicio, horaFin)
                    SELECT horaInicio, horaFin FROM @HorariosDelDia ORDER BY horaInicio;

                    SELECT @hTotal = COUNT(1) FROM @HorariosOrdenados;
                    SET @hIterador = 1;

                    WHILE @hIterador <= @hTotal
                    BEGIN
                        SELECT 
                            @horaInicio = horaInicio,
                            @horaFin = horaFin
                        FROM @HorariosOrdenados
                        WHERE secuencia = @hIterador;

                        SET @fechaHoraInicio = CAST(CAST(@currentDate AS DATETIME) + CAST(@horaInicio AS DATETIME) AS DATETIME2);
                        SET @fechaHoraFin = CAST(CAST(@currentDate AS DATETIME) + CAST(@horaFin AS DATETIME) AS DATETIME2);

                        -- Inserción controlada evitando duplicación de fechas/horas
                        IF NOT EXISTS (
                            SELECT 1 FROM dbo.Sesion 
                            WHERE grupo = @idGrupoDefecto 
                              AND fechaHoraInicio = @fechaHoraInicio 
                              AND fechaHoraFin = @fechaHoraFin
                        )
                        BEGIN
                            SET @numSemana = DATEDIFF(week, @fechaInicio, @currentDate) + 1;
                            SET @codigoVerif = UPPER(LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(50)), '-', ''), 6));
                            SET @nombreSesion = CONCAT('Sesión ', @numeroSesion);

                            INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
                            VALUES (NEWID(), @nombreSesion, @numeroSesion, @codigoVerif, @numSemana, @idGrupoDefecto, @fechaHoraInicio, @fechaHoraFin);

                            SET @sesionesCreadas = @sesionesCreadas + 1;
                            SET @numeroSesion = @numeroSesion + 1;
                        END

                        SET @hIterador = @hIterador + 1;
                    END
                END

                SET @currentDate = DATEADD(day, 1, @currentDate);
            END

            COMMIT TRANSACTION;
        END

        -- PASO 6: Evaluación de resultado final y generación de mensaje de éxito desde el Catálogo de Mensajes
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'GeneracionSesionesGrupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones e inicio de reversión transaccional
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados garantizando el nombre de columna idCorrelacion
    SELECT 
        idCorrelacion = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END;
GO
