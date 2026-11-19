USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-065 (4): solo el COORDINADOR crea grupos; el DOCENTE recibe SEC_001 (perfil requerido COORDINADOR).
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idAsignatura            UNIQUEIDENTIFIER,
    @idPeriodoAcademico      UNIQUEIDENTIFIER,
    @codigo                  INT,
    @nombre                  NVARCHAR(50),
    @idDocente               UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPeriodoAcademicoDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPeriodoAcademico, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto             NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idPeriodoResolved         UNIQUEIDENTIFIER = @idPeriodoAcademicoDefecto;
    DECLARE @capacidadMaximaDefecto    INT;
    DECLARE @nombrePeriodoRechazo      NVARCHAR(500);

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.6 (DEC-065 (4)): solo el COORDINADOR crea grupos (el docente ya no los crea; el PASO 1.5 lo rechaza con SEC_001)

        -- PASO 2: Validar asignatura en uv_asignatura
        IF @estadoResultado = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[uv_asignatura] WHERE id = @idAsignaturaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'Asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 2B (SES-GEN-01 B1, DR-14): la asignatura esta activa, tiene vinculo activo con un plan activo, y el coordinador coordina
        --          TODOS los programas donde esta activa (mismo criterio que la edicion de asignaturas compartidas). Antes solo se
        --          comprobaba que existiera (el ambito solo lo validaba usp_guardar_horarios_grupo, y solo con franjas).
        IF @estadoResultado = 1
           AND (NOT EXISTS (SELECT 1 FROM [dbo].[uv_asignatura] a WHERE a.id = @idAsignaturaDefecto AND a.estaActivaAsignatura = 1)
                OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_asignatura_plan_estudio] v
                               WHERE v.idAsignatura = @idAsignaturaDefecto AND v.estaActivoVinculo = 1 AND v.estaActivoPlan = 1)
                OR EXISTS (SELECT 1 FROM [dbo].[uv_asignatura_plan_estudio] v
                           WHERE v.idAsignatura = @idAsignaturaDefecto AND v.estaActivoVinculo = 1 AND v.estaActivoPlan = 1
                             AND NOT EXISTS (SELECT 1 FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto) cp WHERE cp.idPrograma = v.idPrograma)))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ASI_010',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: El periodo academico es obligatorio y debe existir (SES-GEN-01 DR-06: ya no se sustituye en silencio por el mas reciente)
        IF @estadoResultado = 1
        BEGIN
            IF @idPeriodoResolved IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_periodo_academico] WHERE id = @idPeriodoResolved)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'PeriodoAcademico',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3B (SES-GEN-01 B2): el periodo es de la institucion del coordinador y no esta terminado ni cerrado (PER_010)
        IF @estadoResultado = 1
           AND NOT EXISTS (SELECT 1
                           FROM [dbo].[uv_periodo_academico] pa
                           INNER JOIN dbo.PeriodoAcademico p ON p.id = pa.id
                           WHERE pa.id = @idPeriodoResolved
                             AND pa.estado <> 'CERRADO'
                             AND p.fechaCierreUtc IS NULL
                             AND pa.idInstitucion IN (SELECT pr.idInstitucion FROM [dbo].[uv_programa] pr
                                                      WHERE pr.id IN (SELECT cp.idPrograma FROM dbo.ufn_programas_coordinador(@idUsuarioEjecutorDefecto) cp)))
        BEGIN
            SELECT TOP 1 @nombrePeriodoRechazo = pa.nombre FROM [dbo].[uv_periodo_academico] pa WHERE pa.id = @idPeriodoResolved;
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PER_010',
                @p_param1 = @nombrePeriodoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Validar docente mediante procedimiento interno estandarizado
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_docente_exista_por_id_interno
                @idDocente = @idDocenteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4B (HU093/D12): el titular no puede tener su vinculo con el programa inactivado
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_docente_vinculo_activo_programa_interno
                @idDocente = @idDocenteDefecto,
                @idAsignatura = @idAsignaturaDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4C (DEC-073): el codigo del grupo es un entero mayor que cero (ERR_CODIGO_GRUPO_INVALIDO); 0 o negativo no se
        --          ignora en silencio.
        IF @estadoResultado = 1 AND (@codigo IS NULL OR @codigo <= 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ERR_CODIGO_GRUPO_INVALIDO',
                @p_param1 = @codigo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Validar unicidad de código de grupo en el período consultando uv_grupo
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (
                SELECT 1 FROM [dbo].[uv_grupo]
                WHERE idAsignatura = @idAsignaturaDefecto AND idPeriodoAcademico = @idPeriodoResolved AND codigo = @codigo
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_006',
                    @p_param1 = 'Grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 6: Resolver capacidad máxima por defecto desde el catálogo de parámetros (GRUPO/CAPACIDAD_MAXIMA_DEFECTO)
        IF @estadoResultado = 1
        BEGIN
            SET @capacidadMaximaDefecto = dbo.ufn_obtener_parametro_int(NULL, 'GRUPO', 'CAPACIDAD_MAXIMA_DEFECTO');

            IF @capacidadMaximaDefecto IS NULL OR @capacidadMaximaDefecto <= 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ERR_CAPACIDAD_GRUPO_INVALIDA',
                    @p_param1 = @capacidadMaximaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: Inserción directa de Grupo con capacidad máxima proveniente del catálogo
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.Grupo (
                id, asignatura, periodoAcademico, codigo, nombre,
                cantidadEstudiantes, cantidadEstudiantesFinalizaron,
                cantidadEstudiantesCancelaronVoluntadPropia,
                cantidadEstudiantesCancelaronAutomaticamente,
                docente
            )
            VALUES (
                @idGrupoDefecto,
                @idAsignaturaDefecto,
                @idPeriodoResolved,
                @codigo,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Grupo ', @codigo) END,
                @capacidadMaximaDefecto, 0, 0, 0,
                @idDocenteDefecto
            );

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
