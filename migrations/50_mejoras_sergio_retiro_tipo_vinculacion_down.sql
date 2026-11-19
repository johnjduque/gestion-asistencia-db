-- ============================================================================
-- MIGRACION DOWN 50: restaura el tipo de vinculacion del docente (MEJORAS-SERGIO-2026-11-18, items 1 y 12)
--   1. Tabla TipoVinculacion (PK, UQ por codigo) con PLA, MTI, CAT y OCA, y la vista uv_tipo_vinculacion.
--   2. Columna DocentePrograma.tipoVinculacion: se agrega NULL, los vinculos existentes toman el tipo por defecto (CAT), queda NOT
--      NULL con DF_DocentePrograma_tipoVinculacion (= CAT, para que las altas sin tipo de pruebas y SP sigan funcionando) y la FK.
--      El tipo real que tenian los vinculos antes del up NO se recupera (el up lo borra).
--   3. Parametro DOCENTE/TIPO_VINCULACION_DEFECTO y mensajes DOC_004 y ERR_TIPO_VINCULACION_INVALIDO. No se recrean filas de
--      CatalogoParametroEdicion: las semillas nunca hicieron editable este parametro ni lo usaron como regla cruzada
--      (parametroDebeSerMenorQue); si en una base alguien lo hizo a mano, el up anulo esa regla y el down no la recupera.
--   4. El texto de develop (antes de la 50) de uv_docente_programa, uv_auth_docente_programa, usp_vincular_docente_programa(_interno),
--      usp_actualizar_docente_programa, usp_consultar_docentes_programa, usp_consultar_resumen_docentes_programa,
--      usp_consultar_perfil_usuario y usp_consultar_estudiantes_facultad_paginado (sin codigoTipoIdentificacion).
-- Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 50 DOWN: restaura el tipo de vinculacion del docente';
GO
-- ---- schema/tables/TipoVinculacion.sql
IF OBJECT_ID(N'dbo.TipoVinculacion', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[TipoVinculacion] (
        [id] uniqueidentifier NOT NULL,
        [codigo] nvarchar(3) NOT NULL,
        [nombre] nvarchar(50) NOT NULL,
        [estado] bit NOT NULL
    );
    ALTER TABLE [dbo].[TipoVinculacion] ADD CONSTRAINT [PK_TipoVinculacion] PRIMARY KEY CLUSTERED ([id]);
    ALTER TABLE [dbo].[TipoVinculacion] ADD CONSTRAINT [UQ_TipoVinculacion_codigo] UNIQUE ([codigo]);
END
GO
MERGE INTO [dbo].[TipoVinculacion] AS Target
USING (VALUES
    ('PLA', N'Planta', 1),
    ('MTI', N'Medio tiempo', 1),
    ('CAT', N'Cátedra', 1),
    ('OCA', N'Ocasional', 1)
) AS Source (codigo, nombre, estado)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.estado = Source.estado
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, estado)
    VALUES (NEWID(), Source.codigo, Source.nombre, Source.estado);
GO
-- ---- schema/views/uv_tipo_vinculacion.sql
CREATE OR ALTER VIEW [dbo].[uv_tipo_vinculacion]
AS
SELECT		tv.id,
			tv.codigo,
			tv.nombre,
			estaActivoTipoVinculacion = tv.estado,
			estaActivoTextoTipoVinculacion = IIF(tv.estado = 1, 'SI', 'NO')
FROM		TipoVinculacion tv
GO
-- ---- schema/tables/DocentePrograma.sql (columna tipoVinculacion) y zz_foreign_keys.sql (FK 40)
IF COL_LENGTH(N'dbo.DocentePrograma', N'tipoVinculacion') IS NULL
    ALTER TABLE [dbo].[DocentePrograma] ADD [tipoVinculacion] uniqueidentifier NULL;
GO
DECLARE @idCat UNIQUEIDENTIFIER = (SELECT id FROM dbo.TipoVinculacion WHERE codigo = N'CAT');
UPDATE dbo.DocentePrograma SET tipoVinculacion = @idCat WHERE tipoVinculacion IS NULL;
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints dc
               INNER JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
               WHERE dc.parent_object_id = OBJECT_ID(N'dbo.DocentePrograma') AND c.name = N'tipoVinculacion')
BEGIN
    DECLARE @sqlDf NVARCHAR(400) = N'ALTER TABLE [dbo].[DocentePrograma] ADD CONSTRAINT [DF_DocentePrograma_tipoVinculacion] DEFAULT ('''
        + CONVERT(NVARCHAR(36), @idCat) + N''') FOR [tipoVinculacion];';
    EXEC sys.sp_executesql @sqlDf;
END
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.DocentePrograma') AND name = N'tipoVinculacion' AND is_nullable = 1)
    ALTER TABLE [dbo].[DocentePrograma] ALTER COLUMN [tipoVinculacion] uniqueidentifier NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DocentePrograma_TipoVinculacion')
    ALTER TABLE [dbo].[DocentePrograma] ADD CONSTRAINT [FK_DocentePrograma_TipoVinculacion] FOREIGN KEY ([tipoVinculacion]) REFERENCES [dbo].[TipoVinculacion] ([id]);
GO
-- ---- schema/seed/16_tipo_vinculacion.sql (parametro)
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES ('DOCENTE', 'TIPO_VINCULACION_DEFECTO', 'CAT', 'STRING', 'CAT')) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- ---- mensajes (17_mensaje_docente_programa.sql y 63_val_mensajes_err_pendientes.sql)
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('DOC_004', 'BUSINESS_ERROR', 'MEDIO', N'El tipo de vinculación indicado no existe o está inactivo.'),
    ('ERR_TIPO_VINCULACION_INVALIDO', 'VALIDATION_ERROR', 'BAJO', N'El tipo de vinculación indicado no existe o está inactivo.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('DOC_004', 'BUSINESS_ERROR', 'MEDIO', N'Validación: TipoVinculacion inexistente o con estado = 0.'),
    ('ERR_TIPO_VINCULACION_INVALIDO', 'VALIDATION_ERROR', 'BAJO', N'Backend (VALIDATION_ERROR, DocenteErrorCode): El tipo de vinculacion indicado no existe o esta inactivo.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
-- ---- schema/views/uv_docente_programa.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU062/HU089: una fila por vinculo (docente, programa). No depende de los grupos (un docente recien
-- vinculado aparece con totalGruposPrograma = 0). uv_docente y uv_auth_docente no cambian.
CREATE OR ALTER VIEW [dbo].[uv_docente_programa]
AS
SELECT		idDocentePrograma = dp.id,
			idDocente = di.id,
			di.idUsuario,

			idTipoIdentificacion = u.idTipoIdentificacion,
			codigoTipoIdentificacion = u.TipoIdentificacion,
			u.numeroIdentificacion,
			u.primerNombre,
			u.segundoNombre,
			u.primerApellido,
			u.segundoApellido,
			u.nombreCompleto,
			u.correo,

			idPrograma = pr.id,
			pr.nombrePrograma,
			pr.idFacultad,
			pr.nombreFacultad,
			pr.idInstitucion,

			idTipoVinculacion = tv.id,
			codigoTipoVinculacion = tv.codigo,
			nombreTipoVinculacion = tv.nombre,

			dp.fechaVinculacionUtc,
			estaActivoVinculacion = dp.estado,
			estaActivoUsuario = u.estaActivoUsuario,
			estaActivoDocentePrograma = IIF(dp.estado = 1 AND u.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 1, 0),

			totalGruposPrograma = (
				SELECT	COUNT(DISTINCT x.idGrupo)
				FROM	uv_docente x
				WHERE	x.id = di.id AND x.idPrograma = pr.id
			)
FROM		DocentePrograma dp
INNER JOIN	uv_docente_identidad di
ON			dp.docente = di.id
INNER JOIN	uv_usuario u
ON			di.idUsuario = u.id
INNER JOIN	uv_programa pr
ON			dp.programa = pr.id
INNER JOIN	uv_tipo_vinculacion tv
ON			dp.tipoVinculacion = tv.id
GO
-- ---- schema/views/uv_auth_docente_programa.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Vista con ambito (fail-closed): sin contexto de ejecutor => 0 filas. Admin de la institucion, decano de
-- la facultad, coordinador del programa de la fila, o el propio docente.
CREATE OR ALTER VIEW [dbo].[uv_auth_docente_programa]
AS
SELECT  d.idDocentePrograma,
        d.idDocente,
        d.idUsuario,
        d.idTipoIdentificacion,
        d.codigoTipoIdentificacion,
        d.numeroIdentificacion,
        d.primerNombre,
        d.segundoNombre,
        d.primerApellido,
        d.segundoApellido,
        d.nombreCompleto,
        d.correo,
        d.idPrograma,
        d.nombrePrograma,
        d.idFacultad,
        d.nombreFacultad,
        d.idInstitucion,
        d.idTipoVinculacion,
        d.codigoTipoVinculacion,
        d.nombreTipoVinculacion,
        d.fechaVinculacionUtc,
        d.estaActivoVinculacion,
        d.estaActivoUsuario,
        d.estaActivoDocentePrograma,
        d.totalGruposPrograma
FROM    dbo.uv_docente_programa d
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL
   AND  (
            EXISTS (
                SELECT 1 FROM dbo.Administrador a
                WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = d.idInstitucion
            )
        OR  EXISTS (
                SELECT 1 FROM dbo.Decano dec INNER JOIN dbo.Facultad f ON dec.id = f.decano
                WHERE dec.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.id = d.idFacultad
            )
        OR  EXISTS (
                SELECT 1 FROM dbo.Coordinador c INNER JOIN dbo.Programa pr ON c.id = pr.coordinador
                WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.id = d.idPrograma
            )
        OR  d.idUsuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        );
GO
-- ---- schema/stored-procedures/usp_vincular_docente_programa_interno.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU091: operacion atomica de vinculo (docente, programa). La fachada publica aporta RBAC, titularidad,
-- resolucion de modo y transaccion; aqui solo se valida el tipo, la unicidad y se inserta.
CREATE OR ALTER PROCEDURE [dbo].[usp_vincular_docente_programa_interno]
(
    @idDocente               UNIQUEIDENTIFIER,
    @idPrograma              UNIQUEIDENTIFIER,
    @idTipoVinculacion       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;

    -- Tipo de vinculacion existente y activo
    IF @idTipoVinculacion IS NULL
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_vinculacion WHERE id = @idTipoVinculacion AND estaActivoTipoVinculacion = 1)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'DOC_004',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
        RETURN;
    END

    -- Unicidad (docente, programa) bajo bloqueo para serializar vinculos concurrentes
    IF EXISTS (SELECT 1 FROM dbo.DocentePrograma WITH (UPDLOCK, HOLDLOCK) WHERE docente = @idDocente AND programa = @idPrograma)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'DOC_006',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
        RETURN;
    END

    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @idDocente, @idPrograma, @idTipoVinculacion, 1, SYSUTCDATETIME());

    EXEC dbo.usp_obtener_mensaje_catalogo
        @p_codigo = 'GEN_004',
        @p_param1 = 'Vinculacion docente',
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
END;
GO
-- ---- schema/stored-procedures/usp_vincular_docente_programa.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU091: vincula un docente al programa del coordinador. Tres modos excluyentes:
--   (a) @idDocente        docente existente (p. ej. de otro programa de la misma institucion)
--   (b) @idUsuario        usuario existente que aun no es docente
--   (c) datos de persona  alta nueva (usuario + docente + vinculo); documento/correo existentes => DOC_003
-- RBAC COORDINADOR + titularidad PROGRAMA se validan DENTRO del SP. @password es el HASH (nunca texto plano).
-- Una sola transaccion con ownership (transaccion propia o savepoint si el llamador ya tiene una).
CREATE OR ALTER PROCEDURE [dbo].[usp_vincular_docente_programa]
(
    @idDocente              UNIQUEIDENTIFIER = NULL,
    @idUsuario              UNIQUEIDENTIFIER = NULL,
    @idTipoIdentificacion   UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion   INT              = NULL,
    @primerNombre           NVARCHAR(50)     = NULL,
    @segundoNombre          NVARCHAR(50)     = NULL,
    @primerApellido         NVARCHAR(50)     = NULL,
    @segundoApellido        NVARCHAR(50)     = NULL,
    @correo                 NVARCHAR(100)    = NULL,
    @password               NVARCHAR(500)    = NULL,
    @idTipoVinculacion      UNIQUEIDENTIFIER,
    @idPrograma             UNIQUEIDENTIFIER,
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor      UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @modoDocente BIT = IIF(@idDocente IS NULL, 0, 1);
    DECLARE @modoUsuario BIT = IIF(@idUsuario IS NULL, 0, 1);
    DECLARE @modoNuevo   BIT = IIF(@numeroIdentificacion IS NULL AND @correo IS NULL AND @idTipoIdentificacion IS NULL
                                   AND @primerNombre IS NULL AND @primerApellido IS NULL AND @password IS NULL, 0, 1);
    DECLARE @idUsuarioResuelto  UNIQUEIDENTIFIER;
    DECLARE @idDocenteResuelto  UNIQUEIDENTIFIER;
    DECLARE @idInstitucion      UNIQUEIDENTIFIER;
    DECLARE @correoNormalizado  NVARCHAR(100) = LOWER(TRIM(@correo));

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: RBAC COORDINADOR
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

        -- PASO 4: titularidad sobre el programa
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idProgramaDefecto,
                @tipoEntidadPadre = 'PROGRAMA',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4B: programa activo
        IF @estadoResultado = 1
        BEGIN
            SELECT @idInstitucion = idInstitucion FROM dbo.uv_programa WHERE id = @idProgramaDefecto AND estaActivoPrograma = 1;
            IF @idInstitucion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PROG_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: exactamente un modo (DOC_005)
        IF @estadoResultado = 1 AND (CAST(@modoDocente AS INT) + CAST(@modoUsuario AS INT) + CAST(@modoNuevo AS INT)) <> 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'DOC_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: tipo de vinculacion antes de tocar datos (DOC_004)
        IF @estadoResultado = 1
           AND (@idTipoVinculacion IS NULL
                OR NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_vinculacion WHERE id = @idTipoVinculacion AND estaActivoTipoVinculacion = 1))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'DOC_004',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 7: validaciones de solo lectura ANTES de abrir la transaccion (sin escrituras no hay rollback que hacer)
        IF @estadoResultado = 1
        BEGIN
            IF @modoNuevo = 1
            BEGIN
                IF EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE numeroIdentificacion = @numeroIdentificacion OR correo = @correoNormalizado)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_003',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
                -- DEC-073: el docente nuevo usa el correo institucional (VCE_008)
                IF @estadoResultado = 1
                EXEC dbo.usp_validar_correo_institucional_personal_interno
                    @correo = @correo,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
            ELSE IF @modoUsuario = 1
            BEGIN
                SELECT TOP 1 @idUsuarioResuelto = id FROM dbo.uv_usuario WHERE id = @idUsuario AND estaActivoUsuario = 1;
                IF @idUsuarioResuelto IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
                ELSE
                    SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE idUsuario = @idUsuarioResuelto;
            END
            ELSE
            BEGIN
                SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE id = @idDocente AND estaActivoUsuario = 1;
                IF @idDocenteResuelto IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
            END

            -- El docente no puede pertenecer solo a otra institucion
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.uv_docente_programa WHERE idDocente = @idDocenteResuelto AND idInstitucion <> @idInstitucion)
               AND NOT EXISTS (SELECT 1 FROM dbo.uv_docente_programa WHERE idDocente = @idDocenteResuelto AND idInstitucion = @idInstitucion)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DOC_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END

            -- Vinculo duplicado
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @idDocenteResuelto AND programa = @idProgramaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DOC_006',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 0
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 8: escrituras en una sola transaccion con ownership
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
                SAVE TRANSACTION usp_vincular_docente_programa;
                SET @savepointCreado = 1;
            END

            -- 8A: persona nueva
            IF @modoNuevo = 1
            BEGIN
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correo,
                    @password = @password,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                    SELECT TOP 1 @idUsuarioResuelto = id FROM dbo.uv_usuario WHERE correo = @correoNormalizado;
            END

            -- 8B: rol Docente para la persona (modos nuevo y usuario sin rol)
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NULL
            BEGIN
                EXEC dbo.usp_sincronizar_docente_interno
                    @idUsuario = @idUsuarioResuelto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
                IF @estadoResultado = 1
                    SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE idUsuario = @idUsuarioResuelto;
            END

            -- 8C: vinculo (revalida tipo y unicidad bajo UPDLOCK, HOLDLOCK)
            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_vincular_docente_programa_interno
                    @idDocente = @idDocenteResuelto,
                    @idPrograma = @idProgramaDefecto,
                    @idTipoVinculacion = @idTipoVinculacion,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            -- PASO 9: cierre respetando ownership
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    IF @estadoResultado = 1 COMMIT TRANSACTION; ELSE ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
            ELSE IF @savepointCreado = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 0
                    ROLLBACK TRANSACTION usp_vincular_docente_programa;
            END
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0 ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_vincular_docente_programa;
        END

        -- Transaccion externa doomed: no nos pertenece, se propaga al propietario.
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
-- ---- schema/stored-procedures/usp_actualizar_docente_programa.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU092: edita (a) el tipo de vinculacion del vinculo docente-programa y (b) los nombres/apellidos de la persona.
-- Solo se actualizan los parametros no nulos (''/vacio en un segundo nombre o apellido lo limpia). El correo NO se
-- edita aqui (exige sincronizar Keycloak: IAM-001). HU159 (decision de John 2026-11-05): (c) el tipo y el numero de
-- documento, opcionales, con usp_corregir_documento_usuario_interno; si cambia, el motivo es obligatorio y se audita
-- CORREGIR_DOCUMENTO_DOCENTE con los valores anteriores y nuevos. Los nombres afectan a la persona en todos sus
-- programas. RBAC COORDINADOR + titularidad PROGRAMA + existencia del vinculo se validan DENTRO del SP, y las
-- validaciones de lectura ocurren antes de abrir la transaccion.
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_docente_programa]
(
    @idDocente          UNIQUEIDENTIFIER,
    @idPrograma         UNIQUEIDENTIFIER,
    @idTipoVinculacion  UNIQUEIDENTIFIER = NULL,
    @primerNombre       NVARCHAR(50)     = NULL,
    @segundoNombre      NVARCHAR(50)     = NULL,
    @primerApellido     NVARCHAR(50)     = NULL,
    @segundoApellido    NVARCHAR(50)     = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion   INT = NULL,
    @motivo                 NVARCHAR(500) = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto         UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @pn  NVARCHAR(50) = TRIM(@primerNombre);
    DECLARE @sn  NVARCHAR(50) = TRIM(@segundoNombre);
    DECLARE @pa  NVARCHAR(50) = TRIM(@primerApellido);
    DECLARE @sa  NVARCHAR(50) = TRIM(@segundoApellido);
    DECLARE @idUsuarioDocente UNIQUEIDENTIFIER;
    DECLARE @identidadAnterior NVARCHAR(MAX);
    DECLARE @documentoCambiado BIT = 0;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar perfil del ejecutor (RBAC COORDINADOR)
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 4: Validar titularidad del ejecutor sobre PROGRAMA
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idProgramaDefecto,
                @tipoEntidadPadre = 'PROGRAMA', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 5: Al menos un campo a actualizar
        IF @estadoResultado = 1 AND @idTipoVinculacion IS NULL AND @pn IS NULL AND @sn IS NULL AND @pa IS NULL AND @sa IS NULL
           AND @idTipoIdIdentificacion IS NULL AND @numeroIdentificacion IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'campo a actualizar',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Existencia del vinculo (docente, programa)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idUsuarioDocente = idUsuario FROM dbo.uv_docente_programa WHERE idDocente = @idDocenteDefecto AND idPrograma = @idProgramaDefecto;
            IF @idUsuarioDocente IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DOC_008',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: Tipo de vinculacion (cuando viene)
        IF @estadoResultado = 1 AND @idTipoVinculacion IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_vinculacion WHERE id = @idTipoVinculacion AND estaActivoTipoVinculacion = 1)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'DOC_004',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 8: Nombres: obligatorios no vacios si vienen; opcionales pueden limpiarse con ''
        IF @estadoResultado = 1
           AND ((@pn IS NOT NULL AND dbo.ufn_validar_texto(@pn) = 0) OR (@pa IS NOT NULL AND dbo.ufn_validar_texto(@pa) = 0))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_003',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        -- PASO 9: Validacion de negocio (VAL_004)
        IF @estadoResultado = 1
           AND ((@sn IS NOT NULL AND @sn <> '' AND dbo.ufn_validar_texto(@sn) = 0) OR (@sa IS NOT NULL AND @sa <> '' AND dbo.ufn_validar_texto(@sa) = 0))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 9b: Documento (HU159): se valida antes de abrir la transaccion
        IF @estadoResultado = 1
        BEGIN
            SET @identidadAnterior = dbo.ufn_obtener_identidad_usuario_json(@idUsuarioDocente);
            EXEC dbo.usp_corregir_documento_usuario_interno
                @idUsuario = @idUsuarioDocente,
                @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                @numeroIdentificacion = @numeroIdentificacion,
                @motivo = @motivo,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @documentoCambiado = @documentoCambiado OUTPUT,
                @soloValidar = 1;
        END

        -- PASO 10: Escrituras en una sola transaccion con ownership
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
                SAVE TRANSACTION usp_actualizar_docente_programa;
                SET @savepointCreado = 1;
            END

            IF @idTipoVinculacion IS NOT NULL
                UPDATE dbo.DocentePrograma SET tipoVinculacion = @idTipoVinculacion
                WHERE docente = @idDocenteDefecto AND programa = @idProgramaDefecto;

            IF @pn IS NOT NULL OR @sn IS NOT NULL OR @pa IS NOT NULL OR @sa IS NOT NULL
                EXEC dbo.usp_actualizar_nombres_usuario_interno
                    @idUsuario = @idUsuarioDocente, @primerNombre = @pn, @segundoNombre = @sn,
                    @primerApellido = @pa, @segundoApellido = @sa;

            IF @documentoCambiado = 1
            BEGIN
                EXEC dbo.usp_corregir_documento_usuario_interno
                    @idUsuario = @idUsuarioDocente,
                    @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @motivo = @motivo,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT,
                    @documentoCambiado = @documentoCambiado OUTPUT;

                EXEC dbo.usp_registrar_auditoria_identidad_interno
                    @idUsuario = @idUsuarioDocente,
                    @identidadAnterior = @identidadAnterior,
                    @motivo = @motivo,
                    @accion = 'CORREGIR_DOCUMENTO_DOCENTE',
                    @tipoRecurso = 'Docente',
                    @idRecurso = @idDocenteDefecto,
                    @ruta = N'/api/v1/coordinador/docentes/{idDocente}',
                    @idUsuarioEjecutor = @idUsuarioEjecutorDefecto,
                    @idCorrelacion = @idCorrelacionDefecto;
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_005', @p_param1 = 'Docente',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1 COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1 ROLLBACK TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0 ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_actualizar_docente_programa;
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
-- ---- schema/stored-procedures/usp_consultar_docentes_programa.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_docentes_programa (HU062 / HU089 / HU063)
--
-- Resultset: READ_QUERY_RESULTSET (filas de uv_auth_docente_programa + totalRegistros). NO es un
-- MUTATION_COMMAND_RESULTSET. Las fallas de RBAC/titularidad se propagan con THROW (mensaje tecnico
-- de catalogo, que lleva el codigo para el clasificador del backend).
-- Solo lectura: sin XACT_ABORT (las fallas se propagan con THROW sin condenar la transaccion del llamador).
-- Paginacion normalizada (pagina >= 1, tamano 1..100) igual que usp_consultar_grupos_paginado.
-- Busqueda: solo digitos => prefijo de numeroIdentificacion; en otro caso => contiene en nombreCompleto.
-- SESSION_CONTEXT se aplica solo durante la consulta y SIEMPRE se restaura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_docentes_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPrograma         UNIQUEIDENTIFIER,
    @numeroPagina       INT              = 1,
    @tamanoPagina       INT              = 10,
    @busqueda           NVARCHAR(50)     = NULL,
    @estaActivo         BIT              = NULL,
    @idTipoVinculacion  UNIQUEIDENTIFIER = NULL,
    @idDocente          UNIQUEIDENTIFIER = NULL,
    @idUsuario          UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    DECLARE @texto NVARCHAR(50) = NULLIF(TRIM(@busqueda), '');
    DECLARE @textoEscapado NVARCHAR(110) = REPLACE(REPLACE(REPLACE(@texto, '\', '\\'), '%', '\%'), '_', '\_');
    DECLARE @soloDigitos BIT = IIF(@texto IS NOT NULL AND @texto NOT LIKE '%[^0-9]%', 1, 0);
    DECLARE @patron NVARCHAR(120) = IIF(@texto IS NULL, NULL, IIF(@soloDigitos = 1, CONCAT(@textoEscapado, '%'), CONCAT('%', @textoEscapado, '%')));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Validar perfil del ejecutor (RBAC COORDINADOR)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto,
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validar titularidad del ejecutor sobre PROGRAMA
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioDefecto,
                @idEntidadPadre = @idProgramaDefecto,
                @tipoEntidadPadre = 'PROGRAMA',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validacion de entrada
        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 5: Fijar el contexto del ejecutor para las vistas uv_auth_*
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @idUsuarioDefecto;

        -- PASO 6: Consulta y retorno de resultados
        SELECT
            d.idDocentePrograma, d.idDocente, d.idUsuario,
            d.idTipoIdentificacion, d.codigoTipoIdentificacion, d.numeroIdentificacion,
            d.primerNombre, d.segundoNombre, d.primerApellido, d.segundoApellido,
            d.nombreCompleto, d.correo,
            d.idPrograma, d.nombrePrograma, d.idFacultad, d.nombreFacultad, d.idInstitucion,
            d.idTipoVinculacion, d.codigoTipoVinculacion, d.nombreTipoVinculacion,
            d.fechaVinculacionUtc, d.estaActivoVinculacion, d.estaActivoUsuario, d.estaActivoDocentePrograma,
            d.totalGruposPrograma,
            COUNT(*) OVER() AS totalRegistros
        FROM dbo.uv_auth_docente_programa d
        WHERE d.idPrograma = @idProgramaDefecto
          AND (@estaActivo IS NULL OR d.estaActivoDocentePrograma = @estaActivo)
          AND (@idTipoVinculacion IS NULL OR d.idTipoVinculacion = @idTipoVinculacion)
          AND (@idDocente IS NULL OR d.idDocente = @idDocente)
          AND (@idUsuario IS NULL OR d.idUsuario = @idUsuario)
          AND (
                @patron IS NULL
                OR (@soloDigitos = 1 AND CAST(d.numeroIdentificacion AS NVARCHAR(12)) LIKE @patron ESCAPE '\')
                OR (@soloDigitos = 0 AND d.nombreCompleto LIKE @patron ESCAPE '\')
              )
        ORDER BY d.nombreCompleto ASC, d.idDocente ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

        -- PASO 7: Restaurar el contexto de sesion previo
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_resumen_docentes_programa.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_docentes_programa (HU095)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Consolidado del directorio docente del programa del COORDINADOR: una fila por tipo de vinculacion con los
-- vinculos activos e inactivos (mismo criterio estaActivoDocentePrograma del directorio HU062/HU089).
--   - el programa se resuelve del ejecutor (usp_resolver_programa_coordinador_interno; KPI_001 si no coordina);
--   - incluye los tipos de vinculacion activos aunque no tengan docentes (contadores en cero) y los inactivos
--     que aun tengan vinculos en el programa.
-- Solo lectura: sin XACT_ABORT.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_docentes_programa]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
,
    @idPrograma UNIQUEIDENTIFIER = NULL)
AS

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.

BEGIN
    SET NOCOUNT ON;

-- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @validarUmbrales = 0,
        @idPrograma = @idPrograma OUTPUT, @idProgramaSolicitado = @idPrograma;

    -- PASO 2: Consulta y retorno de resultados
    SELECT
        idTipoVinculacion     = tv.id,
        codigoTipoVinculacion = tv.codigo,
        nombreTipoVinculacion = tv.nombre,
        totalActivos          = SUM(CASE WHEN d.idDocentePrograma IS NOT NULL AND d.estaActivoDocentePrograma = 1 THEN 1 ELSE 0 END),
        totalInactivos        = SUM(CASE WHEN d.idDocentePrograma IS NOT NULL AND d.estaActivoDocentePrograma = 0 THEN 1 ELSE 0 END)
    FROM dbo.TipoVinculacion tv
    LEFT JOIN dbo.uv_docente_programa d
           ON d.idTipoVinculacion = tv.id
          AND d.idPrograma = @idPrograma
    GROUP BY tv.id, tv.codigo, tv.nombre, tv.estado
    HAVING tv.estado = 1 OR COUNT(d.idDocentePrograma) > 0
    ORDER BY tv.nombre ASC, tv.id ASC;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_perfil_usuario.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_perfil_usuario (HU006)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Perfil del USUARIO EJECUTOR (solo el propio; no recibe otro id): datos personales de dbo.Usuario y una fila por
-- cada vinculo institucional:
--   ESTUDIANTE     -> programa (EstudiantePrograma; detalle = facultad)
--   DOCENTE        -> programa (DocentePrograma; detalle = tipo de vinculacion; activo = estado del vinculo)
--   COORDINADOR    -> programa que coordina (Programa.coordinador; detalle = facultad)
--   DECANO         -> facultad (Facultad.decano; detalle = institucion)
--   ADMINISTRADOR  -> institucion (Administrador.institucion)
-- Sin vinculos devuelve UNA fila con las columnas del vinculo en NULL. Usuario inexistente => 0 filas.
-- No expone la contrasena ni datos de otros usuarios. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_perfil_usuario]
(
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;

-- PASO 1: Validar el identificador de correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: Ejecutor obligatorio (GEN_002)
    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    -- PASO 3: Validacion de entrada
    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: Consulta y retorno de resultados
    ;WITH vinculos AS (
        SELECT rol = 'ESTUDIANTE', orden = 1, idEntidad = p.id, nombreEntidad = p.nombre, detalle = f.nombre, activo = p.estado
        FROM dbo.Estudiante e
        INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = e.id
        INNER JOIN dbo.Programa p ON p.id = ep.programa
        INNER JOIN dbo.Facultad f ON f.id = p.facultad
        WHERE e.usuario = @idUsuarioDefecto
        UNION ALL
        SELECT 'DOCENTE', 2, p.id, p.nombre, tv.nombre, dp.estado
        FROM dbo.Docente d
        INNER JOIN dbo.DocentePrograma dp ON dp.docente = d.id
        INNER JOIN dbo.Programa p ON p.id = dp.programa
        INNER JOIN dbo.TipoVinculacion tv ON tv.id = dp.tipoVinculacion
        WHERE d.usuario = @idUsuarioDefecto
        UNION ALL
        SELECT 'COORDINADOR', 3, p.id, p.nombre, f.nombre, p.estado
        FROM dbo.Coordinador c
        INNER JOIN dbo.Programa p ON p.coordinador = c.id
        INNER JOIN dbo.Facultad f ON f.id = p.facultad
        WHERE c.usuario = @idUsuarioDefecto
        UNION ALL
        SELECT 'DECANO', 4, f.id, f.nombre, i.nombre, f.estado
        FROM dbo.Decano dc
        INNER JOIN dbo.Facultad f ON f.decano = dc.id
        INNER JOIN dbo.Institucion i ON i.id = f.institucion
        WHERE dc.usuario = @idUsuarioDefecto
        UNION ALL
        SELECT 'ADMINISTRADOR', 5, i.id, i.nombre, NULL, i.estado
        FROM dbo.Administrador a
        INNER JOIN dbo.Institucion i ON i.id = a.institucion
        WHERE a.usuario = @idUsuarioDefecto
    )
    -- PASO 5: Consulta y retorno de resultados
    SELECT
        idUsuario                = u.id,
        codigoTipoIdentificacion = u.TipoIdentificacion,
        nombreTipoIdentificacion = u.nombreTipoIdentificacion,
        numeroIdentificacion     = u.numeroIdentificacion,
        primerNombre             = u.primerNombre,
        segundoNombre            = u.segundoNombre,
        primerApellido           = u.primerApellido,
        segundoApellido          = u.segundoApellido,
        nombreCompleto           = CAST(CONCAT_WS(N' ',
                                       NULLIF(TRIM(u.primerNombre), N''),
                                       NULLIF(TRIM(u.segundoNombre), N''),
                                       NULLIF(TRIM(u.primerApellido), N''),
                                       NULLIF(TRIM(u.segundoApellido), N'')) AS NVARCHAR(400)),
        correo                   = u.correo,
        correoConfirmado         = u.correoConfirmado,
        estaActivoUsuario        = u.estaActivoUsuario,
        rolVinculo               = CAST(v.rol AS VARCHAR(20)),
        idEntidadVinculo         = v.idEntidad,
        nombreEntidadVinculo     = v.nombreEntidad,
        detalleVinculo           = v.detalle,
        estaActivoVinculo        = v.activo
    FROM dbo.uv_usuario u
    LEFT JOIN vinculos v ON 1 = 1
    WHERE u.id = @idUsuarioDefecto
    ORDER BY v.orden ASC, v.nombreEntidad ASC, v.idEntidad ASC;
END;
GO
-- ---- schema/stored-procedures/usp_consultar_estudiantes_facultad_paginado.sql (texto de develop antes de la 50)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_estudiantes_facultad_paginado (HU104 directorio, HU105 busqueda)
--
-- Directorio consolidado de los estudiantes de la facultad del decano ejecutor: una fila por estudiante con
-- los programas en que esta matriculado y su numero de grupos. @busqueda compara contra nombre y documento.
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de paginacion se propagan con THROW (DBCODE=PAG_001).
-- Ambito: filas de uv_auth_estudiante (fail-closed sin contexto) restringidas a las facultades cuyo decano es
-- el ejecutor; cualquier otro usuario recibe 0 filas.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_estudiantes_facultad_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @busqueda           NVARCHAR(100)    = NULL,
    @idPrograma         UNIQUEIDENTIFIER = NULL,
    @estaActivo         BIT              = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = TRY_CAST(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO') AS INT);
    DECLARE @busquedaFiltro       NVARCHAR(100) = NULLIF(TRIM(@busqueda), '');
    DECLARE @offset               INT;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
           AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
                OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PAG_001',
                @p_param1 = @numeroPagina,
                @p_param2 = @tamanoPagina,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        SET @offset = (@numeroPagina - 1) * @tamanoPagina;

        EXEC dbo.usp_establecer_contexto_usuario_ejecutor
            @p_idUsuario = @idUsuarioDefecto;

        WITH matriculas AS (
            SELECT  e.id, e.idUsuario, e.numeroIdentificacion, e.nombreCompleto, e.estaActivoUsuario,
                    e.idPrograma, e.nombrePrograma, e.idGrupo
            FROM    dbo.uv_auth_estudiante e
            WHERE   e.idFacultad IN (
                        SELECT f.id FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano
                        WHERE d.usuario = @idUsuarioDefecto
                    )
               AND  (@idPrograma IS NULL OR e.idPrograma = @idPrograma)
        ),
        estudiantes AS (
            SELECT  id, idUsuario, numeroIdentificacion, nombreCompleto, estaActivoUsuario,
                    COUNT(DISTINCT idGrupo) AS totalGrupos
            FROM    matriculas
            GROUP BY id, idUsuario, numeroIdentificacion, nombreCompleto, estaActivoUsuario
        ),
        programas AS (
            SELECT  id, STRING_AGG(CONVERT(NVARCHAR(MAX), nombrePrograma), N', ') WITHIN GROUP (ORDER BY nombrePrograma) AS programas
            FROM    (SELECT DISTINCT id, nombrePrograma FROM matriculas) mp
            GROUP BY id
        )
        SELECT
            es.id                   AS idEstudiante,
            es.idUsuario,
            es.numeroIdentificacion,
            es.nombreCompleto,
            u.correo,
            es.estaActivoUsuario,
            pr.programas,
            es.totalGrupos,
            COUNT(*) OVER()         AS totalRegistros
        FROM estudiantes es
        INNER JOIN programas pr ON pr.id = es.id
        LEFT JOIN dbo.uv_usuario u ON u.id = es.idUsuario
        WHERE
            (@estaActivo IS NULL OR es.estaActivoUsuario = @estaActivo)
            AND (
                @busquedaFiltro IS NULL
                OR CHARINDEX(@busquedaFiltro, es.nombreCompleto) > 0
                OR CHARINDEX(@busquedaFiltro, CONVERT(NVARCHAR(20), es.numeroIdentificacion)) > 0
            )
        ORDER BY es.nombreCompleto ASC, es.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
        THROW;
    END CATCH;
END;
GO
IF OBJECT_ID(N'dbo.TipoVinculacion', N'U') IS NULL OR COL_LENGTH(N'dbo.DocentePrograma', N'tipoVinculacion') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DocentePrograma_TipoVinculacion')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = 'DOC_004')
    THROW 55097, 'MIGRACION 50 DOWN: el tipo de vinculacion no quedo restaurado.', 1;
GO
PRINT 'MIGRACION 50 DOWN OK';
GO
