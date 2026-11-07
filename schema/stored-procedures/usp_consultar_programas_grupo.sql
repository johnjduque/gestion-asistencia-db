USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- CULM-001 B2NM (S3 minimo): programas vigentes de un grupo, para el selector de la matricula manual y de la ventana QR.
-- Lo pueden usar el titular del grupo y el coordinador o decano con ambito sobre algun programa del grupo; si no, SEC_002 (403).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_programas_grupo]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idGrupo           UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @codigoRechazo NVARCHAR(10);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        SET @codigoRechazo = 'VAL_001';
    IF @codigoRechazo IS NULL AND @estadoResultado = 1
       AND NOT (EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor)
                OR EXISTS (SELECT 1 FROM dbo.ufn_programas_grupo(@idGrupo) pg
                           INNER JOIN dbo.ufn_programas_ambito_ejecutor(@idUsuarioEjecutor) amb ON amb.idPrograma = pg.idPrograma))
        SET @codigoRechazo = 'SEC_002';

    IF @estadoResultado = 0 OR @codigoRechazo IS NOT NULL
    BEGIN
        IF @codigoRechazo IS NOT NULL
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = N'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idPrograma     = p.id,
        nombrePrograma = p.nombrePrograma,
        idPlanEstudio  = pg.idPlanEstudio,
        inpPlanEstudio = pg.inpPlanEstudio
    FROM dbo.ufn_programas_grupo(@idGrupo) pg
    INNER JOIN dbo.uv_programa p ON p.id = pg.idPrograma
    ORDER BY p.nombrePrograma ASC, p.id ASC;
END;
GO
