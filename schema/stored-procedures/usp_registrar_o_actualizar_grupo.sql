USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_o_actualizar_grupo]
(
    @idGrupo            UNIQUEIDENTIFIER,
    @idAsignatura       UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER,
    @idDocente          UNIQUEIDENTIFIER,
    @nombre             NVARCHAR(50),
    @codigo             NVARCHAR(50),
    @cupo               INT,
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
DECLARE @idCorrelacionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idGrupoDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idAsignaturaDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idPeriodoAcademicoDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPeriodoAcademico, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @idDocenteDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @nombreDefecto             NVARCHAR(50)     = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@nombre, 'GENERAL', 'CADENA_VACIA')));
DECLARE @codigoDefecto             NVARCHAR(50)     = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@codigo, 'GENERAL', 'CADENA_VACIA')));
DECLARE @cupoDefecto               INT              = dbo.ufn_obtener_parametro_int(@cupo, 'GENERAL', 'ENTERO_CERO');

DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- 1. Validar presencia obligatoria de idCorrelacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- 2. Validar que la Asignatura exista vía Vista uv_asignatura
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura a WHERE a.id = @idAsignaturaDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Asignatura no encontrada. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 3. Validar que el Período Académico exista vía Vista uv_periodo_academico
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_periodo_academico pa WHERE pa.id = @idPeriodoAcademicoDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Periodo academico no encontrado. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- 4. Validar el Docente asignado si fue provisto
        IF @estadoResultado = 1 AND @idDocenteDefecto IS NOT NULL AND @idDocenteDefecto <> CAST('00000000-0000-0000-0000-000000000000' AS UNIQUEIDENTIFIER)
        BEGIN
            EXEC dbo.usp_validar_docente_exista_por_id_interno
                @idDocente = @idDocenteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- 5. FLUJO REACTIVO (UPSERT): Consultar existencia en uv_grupo
        IF @estadoResultado = 1
        BEGIN
            DECLARE @codigoInt INT = TRY_CAST(@codigoDefecto AS INT);
            IF @codigoInt IS NULL SET @codigoInt = 1;

            IF EXISTS (SELECT 1 FROM dbo.uv_grupo g WHERE g.id = @idGrupoDefecto OR (g.codigo = CAST(@codigoInt AS VARCHAR(20)) AND g.idPeriodoAcademico = @idPeriodoAcademicoDefecto))
            BEGIN
                UPDATE [dbo].[Grupo]
                SET [asignatura]          = @idAsignaturaDefecto,
                    [periodoAcademico]    = @idPeriodoAcademicoDefecto,
                    [docente]             = CASE WHEN @idDocenteDefecto = CAST('00000000-0000-0000-0000-000000000000' AS UNIQUEIDENTIFIER) THEN [docente] ELSE @idDocenteDefecto END,
                    [nombre]              = @nombreDefecto,
                    [codigo]              = @codigoInt,
                    [cantidadEstudiantes] = @cupoDefecto
                WHERE [id] = @idGrupoDefecto OR ([codigo] = @codigoInt AND [periodoAcademico] = @idPeriodoAcademicoDefecto);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SUC_ACTUALIZACION_GRUPO',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END
            ELSE
            BEGIN
                DECLARE @nuevoId UNIQUEIDENTIFIER = NEWID();

                INSERT INTO [dbo].[Grupo] (
                    [id], [asignatura], [periodoAcademico], [codigo], [nombre],
                    [cantidadEstudiantes], [cantidadEstudiantesFinalizaron],
                    [cantidadEstudiantesCancelaronVoluntadPropia], [cantidadEstudiantesCancelaronAutomaticamente],
                    [docente]
                )
                VALUES (
                    @nuevoId, @idAsignaturaDefecto, @idPeriodoAcademicoDefecto, @codigoInt, @nombreDefecto,
                    @cupoDefecto, 0, 0, 0, @idDocenteDefecto
                );

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SUC_REGISTRO_GRUPO',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'ERR_INESPERADO_REGISTRO_GRUPO',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL MANDATORIO: Retorno unificado de 4 columnas
    SELECT
        idCorrelacion = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END;
GO
