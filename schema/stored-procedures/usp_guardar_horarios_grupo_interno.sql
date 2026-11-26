USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- F1 (2026-11-01): nucleo atomico de usp_guardar_horarios_grupo. Reemplaza todas las franjas del grupo.
-- @horariosJSON ya viene validado por el SP publico (formato, dias existentes, horas validas y sin traslapes);
-- este nucleo no abre transaccion: la controla el SP publico (propia o savepoint).
-- SKILLS-BD lote 13 (2026-11-26): la inicializacion de las salidas pasa de la cabecera al cuerpo (PASO 0); el reemplazo de franjas sigue en la tabla. Mismo resultado.
CREATE OR ALTER PROCEDURE [dbo].[usp_guardar_horarios_grupo_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @horariosJSON            NVARCHAR(MAX),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
BEGIN
    SET NOCOUNT ON;
    -- PASO 0: inicializacion de las salidas desde el catalogo (antes, entre AS y BEGIN)
    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
    BEGIN TRY
        -- PASO 1: Validacion del identificador de correlacion obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            -- PASO 2: Reemplazo de las franjas del grupo
            DELETE FROM dbo.Horario WHERE grupo = @idGrupoDefecto;

            INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin)
            SELECT NEWID(), @idGrupoDefecto, d.id, TRY_CAST(f.horaInicio AS TIME(0)), TRY_CAST(f.horaFin AS TIME(0))
            FROM OPENJSON(@horariosJSON)
                WITH (codigoDia NVARCHAR(10) '$.codigoDia', horaInicio NVARCHAR(20) '$.horaInicio', horaFin NVARCHAR(20) '$.horaFin') f
            INNER JOIN dbo.uv_dia d ON d.codigo = UPPER(TRIM(f.codigoDia));
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
