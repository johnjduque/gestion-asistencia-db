USE [gestionasistenciadb]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_id_correlacion_esta_presente]    Script Date: 24/07/2026 11:03:55 p. m. ******/
DROP PROCEDURE [dbo].[usp_validar_id_correlacion_esta_presente]
GO

/****** Object:  StoredProcedure [dbo].[usp_validar_id_correlacion_esta_presente]    Script Date: 24/07/2026 11:03:55 p. m. ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE  OR  ALTER   PROCEDURE [dbo].[usp_validar_id_correlacion_esta_presente_interno]
(
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
        -- Inicialización
    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1

BEGIN
    
    EXEC usp_validar_id_interno	@id = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado= @estadoResultado OUTPUT
    
    -- Validación real del parámetro
    IF @estadoResultado = 0 BEGIN
        SELECT  @mensajeUsuarioResultado = 'El identificador de correlación no está presente y es vital para llevar a cabo la transacción deseada.',
                @mensajeTecnicoResultado = 'No se tiene el id de correlación necesario para llevar a cabo la transacción deseada.',
                @estadoResultado = 0
    END
END
GO


