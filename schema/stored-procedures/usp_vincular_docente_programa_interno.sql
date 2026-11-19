USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU091: operacion atomica de vinculo (docente, programa). La fachada publica aporta RBAC, titularidad,
-- resolucion de modo y transaccion; aqui solo se valida la unicidad y se inserta (MEJORAS-SERGIO-2026-11-18: sin tipo de vinculacion).
CREATE OR ALTER PROCEDURE [dbo].[usp_vincular_docente_programa_interno]
(
    @idDocente               UNIQUEIDENTIFIER,
    @idPrograma              UNIQUEIDENTIFIER,
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

    INSERT INTO dbo.DocentePrograma (id, docente, programa, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @idDocente, @idPrograma, 1, SYSUTCDATETIME());

    EXEC dbo.usp_obtener_mensaje_catalogo
        @p_codigo = 'GEN_004',
        @p_param1 = 'Vinculacion docente',
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
END;
GO
