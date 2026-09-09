USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_ejecutar_cierre_masivo_periodo_interno]
(
    @idPeriodo               UNIQUEIDENTIFIER,
    @codigoPeriodo           NVARCHAR(50),
    @idActor                 NVARCHAR(100),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPeriodoDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPeriodo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoPeriodoDefecto NVARCHAR(50)     = TRIM(@codigoPeriodo);
    DECLARE @idActorDefecto       NVARCHAR(100)    = TRIM(@idActor);

    DECLARE @idEstadoFinalizado            UNIQUEIDENTIFIER;
    DECLARE @idEstadoCanceladoInasistencia UNIQUEIDENTIFIER;
    DECLARE @idPeriodoTarget               UNIQUEIDENTIFIER = @idPeriodoDefecto;
    DECLARE @totalEstudiantes              INT = 0;
    DECLARE @totalReprobados               INT = 0;

BEGIN
    SET NOCOUNT ON;
    SET @estadoResultado = 1;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');

    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Resolver período académico si no existe por ID
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @idPeriodoTarget)
        BEGIN
            IF @codigoPeriodoDefecto IS NOT NULL AND @codigoPeriodoDefecto <> ''
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM dbo.PeriodoAcademico
                WHERE nombre = @codigoPeriodoDefecto 
                   OR CAST(codigo AS NVARCHAR(50)) = @codigoPeriodoDefecto
                ORDER BY anio DESC;
            END

            IF @idPeriodoTarget IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @idPeriodoTarget)
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM dbo.PeriodoAcademico
                ORDER BY anio DESC, codigo DESC;
            END
        END

        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @idPeriodoTarget)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_002',
                @p_param1 = 'PeriodoAcademico',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Ejecución transaccional de Cierre Masivo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoFinalizado = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'F' ORDER BY id ASC;
            SELECT TOP 1 @idEstadoCanceladoInasistencia = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'CI' ORDER BY id ASC;

            BEGIN TRANSACTION;

            -- 1. Cerrar sesiones abiertas del período
            UPDATE s
            SET s.cerrada = 1
            FROM dbo.Sesion s
            INNER JOIN dbo.Grupo g ON s.grupo = g.id
            WHERE g.periodoAcademico = @idPeriodoTarget
              AND s.cerrada = 0;

            -- 2. Conteo de estudiantes procesados
            SELECT @totalEstudiantes = COUNT(eg.id)
            FROM dbo.EstudianteGrupo eg
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            WHERE g.periodoAcademico = @idPeriodoTarget;

            -- 3. Actualizar estudiantes con fallas críticas (>=3) a Cancelado por Inasistencia
            ;WITH InasistenciasPorEstudiante AS (
                SELECT 
                    a.estudiante,
                    s.grupo,
                    COUNT(a.id) AS totalFallas
                FROM dbo.Asistencia a
                INNER JOIN dbo.Sesion s ON a.sesion = s.id
                INNER JOIN dbo.Grupo g ON s.grupo = g.id
                INNER JOIN dbo.EstadoAsistencia ea ON a.estado = ea.id
                WHERE g.periodoAcademico = @idPeriodoTarget
                  AND ea.codigo IN ('IN', 'F')
                GROUP BY a.estudiante, s.grupo
                HAVING COUNT(a.id) >= 3
            )
            UPDATE eg
            SET eg.estado = @idEstadoCanceladoInasistencia
            FROM dbo.EstudianteGrupo eg
            INNER JOIN InasistenciasPorEstudiante ipe 
                ON eg.estudiante = ipe.estudiante AND eg.grupo = ipe.grupo
            WHERE eg.estado = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');

            SET @totalReprobados = @@ROWCOUNT;

            -- 4. Actualizar resto de estudiantes activos a Finalizado
            UPDATE eg
            SET eg.estado = @idEstadoFinalizado
            FROM dbo.EstudianteGrupo eg
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            WHERE g.periodoAcademico = @idPeriodoTarget
              AND eg.estado = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');

            -- 5. Actualizar contadores en tabla Grupo
            UPDATE g
            SET 
                cantidadEstudiantesFinalizaron = (
                    SELECT COUNT(1) FROM dbo.EstudianteGrupo eg 
                    WHERE eg.grupo = g.id AND eg.estado = @idEstadoFinalizado
                ),
                cantidadEstudiantesCancelaronAutomaticamente = (
                    SELECT COUNT(1) FROM dbo.EstudianteGrupo eg 
                    WHERE eg.grupo = g.id AND eg.estado = @idEstadoCanceladoInasistencia
                )
            FROM dbo.Grupo g
            WHERE g.periodoAcademico = @idPeriodoTarget;

            -- 6. Auditoría de evento
            INSERT INTO dbo.AuditoriaEvento (
                id, occurredAt, actorId, actorType, action,
                resourceType, resourceId, result, correlationId,
                httpMethod, path, httpStatus, metadata
            ) VALUES (
                NEWID(),
                SYSDATETIMEOFFSET(),
                CASE WHEN @idActorDefecto IS NOT NULL AND @idActorDefecto <> '' THEN @idActorDefecto ELSE 'ADMIN_SISTEMA' END,
                'ADMIN',
                'CIERRE_MASIVO_PERIODO',
                'PeriodoAcademico',
                CAST(@idPeriodoTarget AS NVARCHAR(50)),
                'EXITOSO',
                @idCorrelacionDefecto,
                'POST',
                '/api/v1/admin/cierre-masivo',
                200,
                CONCAT('Cierre masivo completado. Procesados: ', @totalEstudiantes, ', Reprobados por fallas: ', @totalReprobados)
            );

            COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'CierreMasivoPeriodo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
