USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- BD-4 (decision del responsable 2026-11-22): la matricula manual del docente solo procede con un programa COMUN entre el estudiante y el
-- grupo (igual criterio que la matricula por QR, DEC-078). Validador interno de solo lectura, sin transaccion propia; lo llama
-- usp_registrar_estudiante_en_grupo antes de escribir nada. Reglas, en este orden (un estudiante que aun no existe, o que existe sin ningun
-- vinculo en dbo.EstudiantePrograma, no se restringe: queda vinculado al programa del grupo en usp_asegurar_estudiante_programa_grupo_interno):
--   (1) @idProgramaElegido informado y ajeno al grupo (ufn_programas_grupo): EST_006.
--   (2) el estudiante tiene vinculos pero ninguno es programa del grupo: EST_010.
--   (3) @idProgramaElegido informado y que no es uno de los programas del estudiante: EST_011.
-- SKILLS-BD lote 7 (2026-11-26): vinculos del estudiante por uv_estudiante_programa (antes, la tabla), PASO n e IF con
-- BEGIN/END; mismos codigos.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_programa_comun_estudiante_grupo_interno]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idProgramaElegido       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoRechazo        VARCHAR(20);

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Reglas de programa comun, en orden (EST_006, EST_010, EST_011)
        IF @idProgramaElegido IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) pg WHERE pg.idPrograma = @idProgramaElegido)
        BEGIN
            SET @codigoRechazo = 'EST_006';
        END
        ELSE IF @idEstudiante IS NOT NULL
                AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa ep WHERE ep.idEstudiante = @idEstudiante)
                AND NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa ep
                                INNER JOIN dbo.ufn_programas_grupo(@idGrupo) pg ON pg.idPrograma = ep.idPrograma
                                WHERE ep.idEstudiante = @idEstudiante)
        BEGIN
            SET @codigoRechazo = 'EST_010';
        END
        ELSE IF @idEstudiante IS NOT NULL AND @idProgramaElegido IS NOT NULL
                AND EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa ep WHERE ep.idEstudiante = @idEstudiante)
                AND NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa ep
                                WHERE ep.idEstudiante = @idEstudiante AND ep.idPrograma = @idProgramaElegido)
        BEGIN
            SET @codigoRechazo = 'EST_011';
        END

        -- PASO 2: Rechazo con el mensaje del catalogo

        IF @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        -- PASO 3: Error inesperado: triplete SYS_001
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
