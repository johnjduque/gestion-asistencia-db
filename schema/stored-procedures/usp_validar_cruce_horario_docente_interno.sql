USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_validar_cruce_horario_docente_interno]
(
    @idDocente               UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @nombreGrupoConflicto NVARCHAR(200);
    DECLARE @franjaConflicto      NVARCHAR(100);

    -- Inicialización de respuesta desde parámetros del catálogo
    SELECT 
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validación previa de existencia del docente. La existencia del grupo la valida el caller
        -- (usp_actualizar_grupo): no se exige que el grupo esté en el período vigente, para poder cambiar el
        -- titular de grupos de períodos futuros o pasados.
        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_docente_exista_por_id_interno 
                @idDocente = @idDocenteDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Detección de colisión / cruce de horario del docente: mismo día y período, franjas que se
        -- traslapan (las horas contiguas, p. ej. 08-10 y 10-12, no son cruce). El mensaje nombra el grupo y la franja.
        IF @estadoResultado = 1 
        BEGIN
            SELECT TOP 1 
                @estadoResultado = 0,
                @nombreGrupoConflicto = gExistente.nombre,
                @franjaConflicto = CONCAT(hExistente.nombreDia, ' ', CONVERT(CHAR(5), hExistente.horaInicio, 108), '-', CONVERT(CHAR(5), hExistente.horaFin, 108))
            FROM dbo.uv_horario hNuevo
            INNER JOIN dbo.uv_horario hExistente ON hNuevo.idDia = hExistente.idDia 
                AND hNuevo.idPeriodoAcademico = hExistente.idPeriodoAcademico
            INNER JOIN dbo.uv_grupo gExistente ON hExistente.idGrupo = gExistente.id
            WHERE hNuevo.idGrupo = @idGrupoDefecto
                AND gExistente.idDocente = @idDocenteDefecto
                AND hNuevo.idGrupo <> hExistente.idGrupo
                AND hNuevo.horaInicio < hExistente.horaFin
                AND hNuevo.horaFin > hExistente.horaInicio
            ORDER BY gExistente.nombre, hExistente.horaInicio;

            IF @estadoResultado = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'HOR_002',
                    @p_param1 = @nombreGrupoConflicto,
                    @p_param2 = @franjaConflicto,
                    @p_param3 = @idGrupoDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
