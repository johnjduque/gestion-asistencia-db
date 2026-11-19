-- ============================================================================
-- MIGRACION UP 57: HU074 activar o inactivar asignaturas (reglas nuevas)
--   1. Mensajes ASI_009 (inactivar con grupos en el periodo vigente o futuro), ASI_010 (asignatura inactiva), ASI_011 y ASI_012 (exito:
--      quedo activa / inactiva). Seed: schema/seed/69_hu074_mensajes_estado_asignatura.sql.
--   2. Crea usp_validar_asignatura_activa_interno (ASI_010; interno, sin EXECUTE para el runtime).
--   3. Recompila usp_toggle_estado_asignatura (ASI_009 al inactivar; ASI_011/ASI_012 en lugar de GEN_004), usp_crear_grupo (ASI_010) y
--      usp_asociar_asignatura_plan (ASI_010 en lugar de GEN_001 para una asignatura inactiva). Resultsets sin cambio; los
--      permisos de los SP publicos se conservan (CREATE OR ALTER). Unico cambio de firma, aditivo: el toggle recibe
--      @estaActivaDeseada BIT = NULL (NULL alterna; 1/0 fija el estado y es idempotente).
--   4. Concurrencia: el toggle (regla de grupos + UPDATE) y usp_crear_grupo (ASI_010 + INSERT) leen la fila de dbo.Asignatura con
--      UPDLOCK, HOLDLOCK dentro de una transaccion (SET XACT_ABORT ON): inactivar y crear grupo a la vez se serializan.
-- Sin cambios de tablas. Los grupos existentes no cambian. Idempotente. Down: 57_hu074_estado_asignatura_reglas_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 57 UP: HU074 estado de la asignatura';
GO
-- ---- schema/seed/69_hu074_mensajes_estado_asignatura.sql
-- HU074: mensajes del estado de la asignatura (activar / inactivar y su efecto). Idempotente (MERGE por codigo).
--   ASI_009  inactivar con grupos en el periodo vigente o en periodos futuros (usp_toggle_estado_asignatura)
--   ASI_010  asignatura inactiva usada para crear un grupo o asociarla a un plan (usp_validar_asignatura_activa_interno)
--   ASI_011  exito: la asignatura quedo activa
--   ASI_012  exito: la asignatura quedo inactiva
-- Migracion: 57_hu074_estado_asignatura_reglas_up.sql.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('ASI_009', 'BUSINESS_ERROR', 'ALTO',  N'No puedes inactivar la asignatura: tiene grupos en el período vigente o en períodos futuros.'),
    ('ASI_010', 'BUSINESS_ERROR', 'MEDIO', N'La asignatura está inactiva; actívala para usarla.'),
    ('ASI_011', 'SUCCESS',        'BAJO',  N'La asignatura quedó activa.'),
    ('ASI_012', 'SUCCESS',        'BAJO',  N'La asignatura quedó inactiva.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('ASI_009', 'BUSINESS_ERROR', 'ALTO',  N'Regla HU074: la asignatura tiene grupos en un periodo academico vigente o futuro (uv_periodo_academico.estado distinto de CERRADO); no se inactiva.'),
    ('ASI_010', 'BUSINESS_ERROR', 'MEDIO', N'Regla HU074: Asignatura.estado = 0; no se crean grupos ni se asocia a planes hasta reactivarla.'),
    ('ASI_011', 'SUCCESS',        'BAJO',  N'HU074: Asignatura.estado pasa de 0 a 1.'),
    ('ASI_012', 'SUCCESS',        'BAJO',  N'HU074: Asignatura.estado pasa de 1 a 0.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- ---- schema/stored-procedures/usp_validar_asignatura_activa_interno.sql
-- =============================================================================
-- Procedimiento: [dbo].[usp_validar_asignatura_activa_interno]   (INTERNO: sin EXECUTE para el runtime)
-- HU074 (migracion 57): una asignatura inactiva (Asignatura.estado = 0) no se usa para crear grupos ni para asociarla a un
-- plan: ASI_010. La existencia la valida el llamador (VAL_002 / GEN_001); una asignatura inexistente pasa esta validacion.
-- Llamadores: usp_crear_grupo y usp_asociar_asignatura_plan. Los grupos existentes no cambian.
-- @bloquearFila = 1: lee dbo.Asignatura con UPDLOCK, HOLDLOCK; el llamador debe tener una transaccion abierta (el bloqueo dura
-- hasta su COMMIT). usp_crear_grupo lo usa para serializarse con usp_toggle_estado_asignatura, que toma el mismo bloqueo.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_asignatura_activa_interno]
(
    @idAsignatura            UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @bloquearFila            BIT = 0
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @estaActiva           BIT;

BEGIN
    SET NOCOUNT ON;
    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    -- PASO 1: estado de la asignatura (con bloqueo de fila si el llamador lo pide)
    IF @bloquearFila = 1
        SELECT @estaActiva = a.estado FROM dbo.Asignatura a WITH (UPDLOCK, HOLDLOCK) WHERE a.id = @idAsignatura;
    ELSE
        SELECT @estaActiva = a.estaActivaAsignatura FROM dbo.uv_asignatura a WHERE a.id = @idAsignatura;

    -- PASO 2: ASI_010 si la asignatura existe y esta inactiva
    IF @estaActiva = 0
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'ASI_010',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
END;
GO
-- ---- schema/stored-procedures/usp_toggle_estado_asignatura.sql
-- =============================================================================
-- Procedimiento: [dbo].[usp_toggle_estado_asignatura]
-- Alterna Asignatura.estado (activa <-> inactiva). RBAC COORDINADOR que coordine TODOS los programas con vinculo activo de la
-- asignatura (usp_validar_gestion_asignatura_coordinador_interno con @exigirTodosLosProgramas = 1; si no, SEC_002 / ASI_006).
-- HU074 (migracion 57):
--   * Inactivar (1 -> 0) se rechaza con ASI_009 si la asignatura tiene grupos en un periodo academico vigente o futuro, en
--     cualquier programa: uv_periodo_academico.estado distinto de CERRADO (fecha local institucional, TIEMPO/ZONA_HORARIA_SQLSERVER;
--     misma regla que ASI_005 en usp_desvincular_asignatura_plan: fechaFin >= hoy). Grupo no tiene baja logica: cuentan todos.
--   * Reactivar (0 -> 1) siempre se permite tras las validaciones anteriores.
--   * Exito: ASI_011 (quedo activa) o ASI_012 (quedo inactiva). Resultset canonico sin cambios.
--   * @estaActivaDeseada (aditivo, opcional): NULL alterna el estado leido; 1 / 0 fija ese estado. Si la asignatura ya esta en el
--     estado pedido responde exito sin cambios (ASI_011 / ASI_012) y no evalua la regla de grupos (idempotente ante reintentos).
--   * Concurrencia: la fila de dbo.Asignatura se lee con UPDLOCK, HOLDLOCK dentro de la transaccion, antes de buscar grupos, y el
--     UPDATE ocurre en la misma transaccion. usp_crear_grupo toma el mismo bloqueo antes de validar ASI_010 e insertar: una
--     inactivacion y una creacion de grupo simultaneas sobre la misma asignatura se serializan.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_toggle_estado_asignatura]
(
    @idAsignatura   UNIQUEIDENTIFIER,
    @idCorrelacion  UNIQUEIDENTIFIER,
    -- REC2 (auditoria BD 2026-10-28): ejecutor obligatorio (GEN_002 si llega NULL). El DEFAULT solo conserva la
    -- compatibilidad de firma; RBAC COORDINADOR + titularidad del PROGRAMA se validan en usp_validar_gestion_asignatura_coordinador_interno.
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL,
    -- HU074: estado deseado (1 activa, 0 inactiva). NULL conserva el comportamiento de alternar.
    @estaActivaDeseada BIT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @estaActivaActual     BIT;
    DECLARE @estaActivaNueva      BIT;
    DECLARE @codigoResultado      NVARCHAR(10);
    DECLARE @transaccionPropia    BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación del identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio, perfil COORDINADOR, existencia de la asignatura y titularidad del
        --         programa (REC2: logica comun en usp_validar_gestion_asignatura_coordinador_interno)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_gestion_asignatura_coordinador_interno
                @idAsignatura = @idAsignaturaDefecto,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @exigirTodosLosProgramas = 1,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3 (HU074): con la fila bloqueada, ASI_009 si se pide inactivar y hay grupos en un periodo vigente o futuro; si no,
        --         fija el estado pedido (o el contrario al leido). Sin cambio cuando ya esta en el estado pedido.
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            SELECT @estaActivaActual = a.estado
            FROM dbo.Asignatura a WITH (UPDLOCK, HOLDLOCK)
            WHERE a.id = @idAsignaturaDefecto;

            SET @estaActivaNueva = COALESCE(@estaActivaDeseada, IIF(@estaActivaActual = 1, 0, 1));

            IF @estaActivaActual = 1 AND @estaActivaNueva = 0
               AND EXISTS (SELECT 1
                           FROM dbo.uv_grupo g
                           INNER JOIN dbo.uv_periodo_academico pa ON pa.id = g.idPeriodoAcademico
                           WHERE g.idAsignatura = @idAsignaturaDefecto AND pa.estado <> 'CERRADO')
            BEGIN
                SET @codigoResultado = 'ASI_009';
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                IF @estaActivaNueva <> @estaActivaActual
                    UPDATE dbo.Asignatura
                    SET estado = @estaActivaNueva
                    WHERE id = @idAsignaturaDefecto;

                SET @codigoResultado = IIF(@estaActivaNueva = 1, 'ASI_011', 'ASI_012');
            END

            IF @transaccionPropia = 1 COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoResultado,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;

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
-- ---- schema/stored-procedures/usp_crear_grupo.sql
-- CULM-001 / DEC-065 (4): solo el COORDINADOR crea grupos; el DOCENTE recibe SEC_001 (perfil requerido COORDINADOR).
-- HU074 (migracion 57): una asignatura inactiva se rechaza con ASI_010 (usp_validar_asignatura_activa_interno). Desde el PASO 2B
-- hasta el INSERT todo ocurre en una transaccion con la fila de dbo.Asignatura bloqueada (UPDLOCK, HOLDLOCK): una inactivacion
-- simultanea (usp_toggle_estado_asignatura toma el mismo bloqueo) espera o se ve. Si el llamador ya tiene transaccion, se usa la suya.
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
    DECLARE @transaccionPropia         BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
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

        -- PASO 2B (HU074): una asignatura inactiva no se usa para crear grupos (ASI_010). Abre la transaccion (si el llamador no
        --          tiene una) y bloquea la fila de la asignatura hasta el INSERT del PASO 7.
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            EXEC dbo.usp_validar_asignatura_activa_interno
                @idAsignatura = @idAsignaturaDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @bloquearFila = 1;
        END

        -- PASO 3: Resolver período académico si viene nulo/guid defecto
        IF @estadoResultado = 1
        BEGIN
            IF @idPeriodoResolved IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[uv_periodo_academico] WHERE id = @idPeriodoResolved)
            BEGIN
                SELECT TOP 1 @idPeriodoResolved = id 
                FROM [dbo].[uv_periodo_academico] 
                ORDER BY anio DESC;
            END

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

        -- Cierre de la transaccion propia: confirma el INSERT; las ramas de rechazo no escriben y solo liberan el bloqueo
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoResultado = 1 COMMIT TRANSACTION;
            ELSE ROLLBACK TRANSACTION;
        END

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;

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
-- ---- schema/stored-procedures/usp_asociar_asignatura_plan.sql
-- =============================================================================
-- Procedimiento: [dbo].[usp_asociar_asignatura_plan]
-- CULM-001 B2NM (DEC-019, R3): asocia una asignatura existente (catalogo) a un plan de estudios, con semestre y caracter.
-- RBAC COORDINADOR; el plan existe (PLA_002) y es de un programa suyo (SEC_002); la asignatura existe y tiene algun vinculo en
-- un programa de la misma institucion (si no, GEN_001) y esta activa (HU074, migracion 57: si no, ASI_010). Reglas de vinculo en usp_internal_asociar_asignatura_plan
-- (PLA_004, ASI_003, ASI_007). Salida canonica (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_asociar_asignatura_plan]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @semestreNumero     INT,
    @codigoCaracter     NVARCHAR(3) = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaPlan UNIQUEIDENTIFIER, @idInstitucionPlan UNIQUEIDENTIFIER;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @transaccionPropia BIT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'COORDINADOR', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- Plan existente (PLA_002) y titularidad del programa del plan (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idProgramaPlan = pe.programa, @idInstitucionPlan = f.institucion
            FROM dbo.PlanEstudio pe
            INNER JOIN dbo.Programa p ON p.id = pe.programa
            INNER JOIN dbo.Facultad f ON f.id = p.facultad
            WHERE pe.id = @idPlanEstudio;

            IF @idProgramaPlan IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PLA_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
                EXEC dbo.usp_validar_titularidad_jerarquica_interno
                    @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idProgramaPlan, @tipoEntidadPadre = 'PROGRAMA',
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
        END

        -- La asignatura existe y pertenece a la institucion del plan (tiene algun vinculo en ella)
        IF @estadoResultado = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura_plan_estudio v
                           WHERE v.idAsignatura = @idAsignatura AND v.idInstitucion = @idInstitucionPlan)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_001', @p_param1 = 'Asignatura',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- HU074: una asignatura inactiva no se asocia a un plan (ASI_010)
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_asignatura_activa_interno
                @idAsignatura = @idAsignatura, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END

            EXEC dbo.usp_internal_asociar_asignatura_plan
                @idAsignatura = @idAsignatura, @idPlanEstudio = @idPlanEstudio, @semestreNumero = @semestreNumero,
                @codigoCaracter = @codigoCaracter, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Vinculo de asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                IF @transaccionPropia = 1 COMMIT TRANSACTION;
            END
            ELSE IF @transaccionPropia = 1
                ROLLBACK TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 AND @transaccionPropia = 1 ROLLBACK TRANSACTION;
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT idCorrelacion = @idCorrelacionDefecto, mensajeUsuarioResultado = @mensajeUsuarioResultado,
           mensajeTecnicoResultado = @mensajeTecnicoResultado, estadoResultado = @estadoResultado;
END;
GO
