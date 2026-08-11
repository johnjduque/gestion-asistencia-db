USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_generar_sesiones_grupo]
(
    @idGrupo UNIQUEIDENTIFIER,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
    DECLARE @idGrupoDefecto UNIQUEIDENTIFIER = ISNULL(@idGrupo, '00000000-0000-0000-0000-000000000000');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = '';
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = '';
    DECLARE @estadoResultado BIT = 1;

    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Validar ID de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar existencia del grupo
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 3. Validar horarios asignados al grupo
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_horarios_grupo_interno
                @idGrupo = @idGrupoDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 4. Validar fechas del periodo academico del grupo
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_fechas_periodo_academico_interno
                @idGrupo = @idGrupoDefecto, @idCorrelacion = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 5. Generar sesiones de clase recurrentes
        IF @estadoResultado = 1
        BEGIN
            DECLARE @idPeriodo UNIQUEIDENTIFIER;
            DECLARE @fechaInicio DATE;
            DECLARE @fechaFin DATE;

            SELECT TOP 1 @idPeriodo = periodoAcademico FROM [dbo].[Grupo] WHERE id = @idGrupoDefecto;
            SELECT TOP 1 @fechaInicio = fechaInicio, @fechaFin = fechaFin FROM [dbo].[PeriodoAcademico] WHERE id = @idPeriodo;

            DECLARE @currentDate DATE = @fechaInicio;
            DECLARE @sesionesCreadas INT = 0;
            DECLARE @numeroSesion INT = ISNULL((SELECT MAX(numero) FROM [dbo].[Sesion] WHERE grupo = @idGrupoDefecto), 0) + 1;

            DECLARE @fechaHoraInicio DATETIME2;
            DECLARE @fechaHoraFin DATETIME2;
            DECLARE @numSemana INT;
            DECLARE @codigoVerif NVARCHAR(50);
            DECLARE @nombreSesion NVARCHAR(50);

            BEGIN TRANSACTION;

            WHILE @currentDate <= @fechaFin
            BEGIN
                -- Resolver codigo del dia de la semana (LU, MA, MI, JU, VI, SA, DO)
                DECLARE @codigoDia NVARCHAR(2) = 
                    CASE LTRIM(RTRIM(LOWER(DATENAME(dw, @currentDate))))
                        WHEN 'monday' THEN 'LU' WHEN 'lunes' THEN 'LU'
                        WHEN 'tuesday' THEN 'MA' WHEN 'martes' THEN 'MA'
                        WHEN 'wednesday' THEN 'MI' WHEN 'miércoles' THEN 'MI' WHEN 'miercoles' THEN 'MI'
                        WHEN 'thursday' THEN 'JU' WHEN 'jueves' THEN 'JU'
                        WHEN 'friday' THEN 'VI' WHEN 'viernes' THEN 'VI'
                        WHEN 'saturday' THEN 'SA' WHEN 'sábado' THEN 'SA' WHEN 'sabado' THEN 'SA'
                        WHEN 'sunday' THEN 'DO' WHEN 'domingo' THEN 'DO'
                    END;

                -- Buscar si hay horarios para este grupo en este dia de la semana
                DECLARE @HorariosDelDia TABLE (
                    idHorario UNIQUEIDENTIFIER,
                    horaInicio TIME,
                    horaFin TIME
                );

                DELETE FROM @HorariosDelDia;

                INSERT INTO @HorariosDelDia (idHorario, horaInicio, horaFin)
                SELECT h.id, h.horaInicio, h.horaFin
                FROM [dbo].[Horario] h
                INNER JOIN [dbo].[Dia] d ON h.dia = d.id
                WHERE h.grupo = @idGrupoDefecto AND d.codigo = @codigoDia;

                IF EXISTS (SELECT 1 FROM @HorariosDelDia)
                BEGIN
                    DECLARE @idHorario UNIQUEIDENTIFIER;
                    DECLARE @horaInicio TIME;
                    DECLARE @horaFin TIME;

                    DECLARE @hTotal INT = (SELECT COUNT(1) FROM @HorariosDelDia);
                    DECLARE @hIterador INT = 1;

                    -- Tabla ordenada para iterar sobre los horarios del mismo día (ej. si tiene clase en la mañana y tarde)
                    DECLARE @HorariosOrdenados TABLE (
                        Secuencia INT IDENTITY(1,1),
                        horaInicio TIME,
                        horaFin TIME
                    );
                    DELETE FROM @HorariosOrdenados;
                    INSERT INTO @HorariosOrdenados (horaInicio, horaFin)
                    SELECT horaInicio, horaFin FROM @HorariosDelDia ORDER BY horaInicio;

                    WHILE @hIterador <= @hTotal
                    BEGIN
                        SELECT 
                            @horaInicio = horaInicio,
                            @horaFin = horaFin
                        FROM @HorariosOrdenados
                        WHERE Secuencia = @hIterador;

                        SET @fechaHoraInicio = CAST(CAST(@currentDate AS DATETIME) + CAST(@horaInicio AS DATETIME) AS DATETIME2);
                        SET @fechaHoraFin = CAST(CAST(@currentDate AS DATETIME) + CAST(@horaFin AS DATETIME) AS DATETIME2);

                        -- Evitar duplicados exactos
                        IF NOT EXISTS (
                            SELECT 1 FROM [dbo].[Sesion] 
                            WHERE grupo = @idGrupoDefecto 
                              AND fechaHoraInicio = @fechaHoraInicio 
                              AND fechaHoraFin = @fechaHoraFin
                        )
                        BEGIN
                            -- Calcular número de semana transcurrida
                            SET @numSemana = DATEDIFF(week, @fechaInicio, @currentDate) + 1;
                            -- Generar código de verificación aleatorio de 6 caracteres
                            SET @codigoVerif = UPPER(LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(50)), '-', ''), 6));
                            -- Generar nombre de la sesión
                            SET @nombreSesion = CONCAT('Sesión ', @numeroSesion);

                            INSERT INTO [dbo].[Sesion] (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
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

            SELECT 
                @mensajeUsuarioResultado = CONCAT('Se generaron ', @sesionesCreadas, ' sesiones de clase exitosamente.'),
                @mensajeTecnicoResultado = [dbo].[ufn_obtener_mensaje_exito](@idCorrelacionDefecto, OBJECT_NAME(@@PROCID), CONCAT('Generación de sesiones completada. Total creadas: ', @sesionesCreadas, ' para Grupo: ', @idGrupoDefecto)),
                @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SELECT 
            @mensajeUsuarioResultado = 'Hubo un error inesperado al generar las sesiones del grupo.',
            @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto),
            @estadoResultado = 0;
    END CATCH

    -- 6. Retornar resultado de la transaccion
    SELECT 
        id = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END
GO
