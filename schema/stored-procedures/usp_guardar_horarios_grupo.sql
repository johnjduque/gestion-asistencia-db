USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- F1 (2026-10-30): el COORDINADOR del programa define el horario semanal del grupo (reemplaza todas sus franjas).
-- @horariosJSON: arreglo no vacio de {"codigoDia":"LU","horaInicio":"08:00","horaFin":"10:00"} (codigos de dbo.Dia).
-- Reglas: formato, dia existente y horaFin > horaInicio (HOR_004); las franjas del grupo no se traslapan entre si,
-- las contiguas si se permiten (HOR_003); el docente titular no tiene otro grupo a la misma hora en el periodo (HOR_002,
-- usp_validar_cruce_horario_docente_interno). Grupo de otro programa: SEC_002. Ninguna regla deja escrituras parciales.
-- SES-GEN-01: ademas, cada franja dura entre HORARIO/DURACION_MINIMA_MINUTOS y DURACION_MAXIMA_MINUTOS y cae dentro de la ventana
-- HORARIO/VENTANA_INICIO..VENTANA_FIN (HOR_007/HOR_008); la suma semanal de las franjas es igual, exacta, a asignatura.horasSemanales * 60
-- minutos (HOR_006; con horasSemanales NULL no se valida); y el horario nuevo no cruza con otros grupos de los estudiantes ya inscritos
-- (HOR_009). Un parametro de horario ausente omite su regla (B7); B9 se valida dentro de la transaccion y deshace el reemplazo si falla.
CREATE OR ALTER PROCEDURE [dbo].[usp_guardar_horarios_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @horariosJSON            NVARCHAR(MAX),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocente                UNIQUEIDENTIFIER;
    DECLARE @ejecutorEsCoordinador    BIT = 0;
    DECLARE @motivoInvalido           NVARCHAR(200);
    DECLARE @franjaA                  NVARCHAR(100);
    DECLARE @franjaB                  NVARCHAR(100);
    DECLARE @duracionMinima           INT          = dbo.ufn_obtener_parametro_int(NULL, 'HORARIO', 'DURACION_MINIMA_MINUTOS');
    DECLARE @duracionMaxima           INT          = dbo.ufn_obtener_parametro_int(NULL, 'HORARIO', 'DURACION_MAXIMA_MINUTOS');
    DECLARE @ventanaInicio            TIME(0)      = TRY_CAST(dbo.ufn_obtener_parametro('HORARIO', 'VENTANA_INICIO') AS TIME(0));
    DECLARE @ventanaFin               TIME(0)      = TRY_CAST(dbo.ufn_obtener_parametro('HORARIO', 'VENTANA_FIN') AS TIME(0));
    DECLARE @codigoRechazoHorario     VARCHAR(10);
    DECLARE @franjaRechazo            NVARCHAR(100);
    DECLARE @horasSemanalesMateria    INT;
    DECLARE @minutosFranjas           INT;
    DECLARE @estudiantesCruzados      INT;
    DECLARE @textoParametro1          NVARCHAR(500);
    DECLARE @textoParametro2          NVARCHAR(500);
    DECLARE @franjaCruce              NVARCHAR(100);
    DECLARE @codigoMatriculaActiva    NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;

    DECLARE @franjas TABLE (
        secuencia  INT IDENTITY(1, 1) PRIMARY KEY,
        idDia      UNIQUEIDENTIFIER NULL,
        codigoDia  NVARCHAR(10)     NULL,
        nombreDia  NVARCHAR(50)     NULL,
        horaInicio TIME(0)          NULL,
        horaFin    TIME(0)          NULL
    );

BEGIN
    -- Sin XACT_ABORT ON: con savepoint condenaria la transaccion del llamador (Msg 3930); ver skill procedimientos-externos-condiciones.
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor, grupo y ambito (coordinador del programa o docente titular), validacion compartida
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_gestion_grupo_coordinador_o_titular_interno
                @idGrupo = @idGrupoDefecto,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @idCorrelacion = @idCorrelacionDefecto,
                @ejecutorEsCoordinador = @ejecutorEsCoordinador OUTPUT,
                @idDocenteTitular = @idDocente OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3 (F3): el DOCENTE titular solo define el horario inicial (HOR_005); los cambios van por el coordinador
        IF @estadoResultado = 1 AND @ejecutorEsCoordinador = 0
           AND EXISTS (SELECT 1 FROM dbo.uv_horario h WHERE h.idGrupo = @idGrupoDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'HOR_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Formato del horario (HOR_004): arreglo no vacio, solo las 3 claves, dia existente y horaFin > horaInicio
        IF @estadoResultado = 1
        BEGIN
            IF @horariosJSON IS NULL OR ISJSON(@horariosJSON, ARRAY) <> 1 OR NOT EXISTS (SELECT 1 FROM OPENJSON(@horariosJSON))
            BEGIN
                SET @motivoInvalido = N'debe enviar al menos una franja';
            END
            ELSE IF EXISTS (
                SELECT 1
                FROM OPENJSON(@horariosJSON) item
                WHERE item.[type] <> 5
                   OR EXISTS (SELECT 1 FROM OPENJSON(item.value) campo WHERE campo.[key] NOT IN ('codigoDia', 'horaInicio', 'horaFin'))
            )
            BEGIN
                SET @motivoInvalido = N'cada franja lleva solo codigoDia, horaInicio y horaFin';
            END
            ELSE
            BEGIN
                INSERT INTO @franjas (idDia, codigoDia, nombreDia, horaInicio, horaFin)
                SELECT d.id, f.codigoDia, d.nombre, TRY_CAST(f.horaInicio AS TIME(0)), TRY_CAST(f.horaFin AS TIME(0))
                FROM OPENJSON(@horariosJSON)
                    WITH (codigoDia NVARCHAR(10) '$.codigoDia', horaInicio NVARCHAR(20) '$.horaInicio', horaFin NVARCHAR(20) '$.horaFin') f
                LEFT JOIN dbo.uv_dia d ON d.codigo = UPPER(TRIM(f.codigoDia));

                SELECT TOP 1 @motivoInvalido =
                    CASE
                        WHEN idDia IS NULL THEN CONCAT(N'el dia "', codigoDia, N'" no existe')
                        WHEN horaInicio IS NULL OR horaFin IS NULL THEN N'las horas deben tener formato HH:mm'
                        ELSE CONCAT(N'en ', nombreDia, N' la hora de fin debe ser mayor que la de inicio')
                    END
                FROM @franjas
                WHERE idDia IS NULL OR horaInicio IS NULL OR horaFin IS NULL OR horaFin <= horaInicio
                ORDER BY secuencia;
            END

            IF @motivoInvalido IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'HOR_004', @p_param1 = @motivoInvalido,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: Las franjas del grupo no se traslapan entre si (HOR_003); las contiguas se permiten
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @franjaA = CONCAT(a.nombreDia, ' ', CONVERT(CHAR(5), a.horaInicio, 108), '-', CONVERT(CHAR(5), a.horaFin, 108)),
                @franjaB = CONCAT(b.nombreDia, ' ', CONVERT(CHAR(5), b.horaInicio, 108), '-', CONVERT(CHAR(5), b.horaFin, 108))
            FROM @franjas a
            INNER JOIN @franjas b ON b.idDia = a.idDia AND b.secuencia > a.secuencia
            WHERE a.horaInicio < b.horaFin AND a.horaFin > b.horaInicio
            ORDER BY a.secuencia, b.secuencia;

            IF @franjaA IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'HOR_003', @p_param1 = @franjaA, @p_param2 = @franjaB,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5.1 (SES-GEN-01 B7): duracion minima/maxima de cada franja (HOR_007) y ventana horaria institucional (HOR_008)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @franjaRechazo = CONCAT(nombreDia, ' ', CONVERT(CHAR(5), horaInicio, 108), '-', CONVERT(CHAR(5), horaFin, 108)),
                @codigoRechazoHorario = CASE
                    WHEN @duracionMinima IS NOT NULL AND DATEDIFF(MINUTE, horaInicio, horaFin) < @duracionMinima THEN 'HOR_007'
                    WHEN @duracionMaxima IS NOT NULL AND DATEDIFF(MINUTE, horaInicio, horaFin) > @duracionMaxima THEN 'HOR_007'
                    WHEN @ventanaInicio IS NOT NULL AND @ventanaFin IS NOT NULL AND (horaInicio < @ventanaInicio OR horaFin > @ventanaFin) THEN 'HOR_008'
                END
            FROM @franjas
            WHERE (@duracionMinima IS NOT NULL AND DATEDIFF(MINUTE, horaInicio, horaFin) < @duracionMinima)
               OR (@duracionMaxima IS NOT NULL AND DATEDIFF(MINUTE, horaInicio, horaFin) > @duracionMaxima)
               OR (@ventanaInicio IS NOT NULL AND @ventanaFin IS NOT NULL AND (horaInicio < @ventanaInicio OR horaFin > @ventanaFin))
            ORDER BY secuencia;

            IF @codigoRechazoHorario = 'HOR_007'
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'HOR_007', @p_param1 = @franjaRechazo, @p_param2 = @duracionMinima, @p_param3 = @duracionMaxima,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            ELSE IF @codigoRechazoHorario = 'HOR_008'
            BEGIN
                SET @textoParametro2 = CONCAT(CONVERT(CHAR(5), @ventanaInicio, 108), '-', CONVERT(CHAR(5), @ventanaFin, 108));
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'HOR_008', @p_param1 = @franjaRechazo, @p_param2 = @textoParametro2,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END

            IF @codigoRechazoHorario IS NOT NULL
            BEGIN
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5.2 (SES-GEN-01 B5): las horas semanales de las franjas (suma de duraciones) igualan, exacto, las de la materia (HOR_006).
        --          Materia sin horas cargadas (NULL): no se valida.
        IF @estadoResultado = 1
        BEGIN
            SELECT @horasSemanalesMateria = a.horasSemanales
            FROM dbo.Grupo g
            INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
            WHERE g.id = @idGrupoDefecto;

            SELECT @minutosFranjas = SUM(DATEDIFF(MINUTE, horaInicio, horaFin)) FROM @franjas;

            IF @horasSemanalesMateria IS NOT NULL AND @minutosFranjas <> @horasSemanalesMateria * 60
            BEGIN
                SET @textoParametro1 = IIF(@minutosFranjas % 60 = 0, CAST(@minutosFranjas / 60 AS NVARCHAR(20)), CAST(CAST(@minutosFranjas / 60.0 AS DECIMAL(6, 2)) AS NVARCHAR(20)));
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'HOR_006',
                    @p_param1 = @textoParametro1,
                    @p_param2 = @horasSemanalesMateria,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 6: Reemplazo atomico de las franjas y cruce del docente titular (HOR_002) sobre el horario nuevo
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_guardar_horarios_grupo;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_guardar_horarios_grupo_interno
                @idGrupo = @idGrupoDefecto,
                @horariosJSON = @horariosJSON,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_validar_cruce_horario_docente_interno
                    @idDocente = @idDocente,
                    @idGrupo = @idGrupoDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            -- PASO 6.1 (SES-GEN-01 B9): el horario nuevo no cruza con otros grupos de los estudiantes ya inscritos (HOR_009)
            IF @estadoResultado = 1
            BEGIN
                SELECT @estudiantesCruzados = COUNT(DISTINCT egNuevo.idEstudiante),
                       @franjaCruce = MIN(CONCAT(hNuevo.nombreDia, ' ', CONVERT(CHAR(5), hNuevo.horaInicio, 108), '-', CONVERT(CHAR(5), hNuevo.horaFin, 108)))
                FROM dbo.uv_horario hNuevo
                INNER JOIN dbo.uv_horario hExistente
                    ON hExistente.idDia = hNuevo.idDia AND hExistente.idPeriodoAcademico = hNuevo.idPeriodoAcademico AND hExistente.idGrupo <> hNuevo.idGrupo
                INNER JOIN dbo.uv_estudiante_grupo egNuevo
                    ON egNuevo.idGrupo = hNuevo.idGrupo AND egNuevo.codigoEstadoEstudiante = @codigoMatriculaActiva
                INNER JOIN dbo.uv_estudiante_grupo egOtro
                    ON egOtro.idGrupo = hExistente.idGrupo AND egOtro.codigoEstadoEstudiante = @codigoMatriculaActiva AND egOtro.idEstudiante = egNuevo.idEstudiante
                WHERE hNuevo.idGrupo = @idGrupoDefecto
                  AND hNuevo.horaInicio < hExistente.horaFin AND hNuevo.horaFin > hExistente.horaInicio;

                IF @estudiantesCruzados > 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'HOR_009', @p_param1 = @estudiantesCruzados, @p_param2 = @franjaCruce,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_005', @p_param1 = 'Horario del grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- Rechazo de negocio despues de escribir: se deshace todo lo escrito en este SP
            IF @estadoResultado = 0
            BEGIN
                IF @transaccionPropia = 1
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @transaccionPropia = 0;
                END
                ELSE
                BEGIN
                    ROLLBACK TRANSACTION sp_guardar_horarios_grupo;
                    SET @savepointCreado = 0;
                END
            END
            ELSE IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
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
            ROLLBACK TRANSACTION sp_guardar_horarios_grupo;
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
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
