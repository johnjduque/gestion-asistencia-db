USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER        PROCEDURE [dbo].[usp_validar_id_correlacion_esta_presente_interno]
(
    @idCorrelacion UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = ISNULL(@idCorrelacion, '00000000-0000-0000-0000-000000000000');
        -- Inicializaci??n
    SELECT @mensajeUsuarioResultado = '', @mensajeTecnicoResultado = '', @estadoResultado = 1

BEGIN
    
    EXEC usp_validar_id_interno	@id = @idCorrelacionDefecto, @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, @estadoResultado= @estadoResultado OUTPUT
    
    -- Validaci??n real del par??metro
    IF @estadoResultado = 0 BEGIN
        SELECT  @mensajeUsuarioResultado = 'El identificador de correlaci??n no est?? presente y es vital para llevar a cabo la transacci??n deseada.',
                @mensajeTecnicoResultado = 'No se tiene el id de correlaci??n necesario para llevar a cabo la transacci??n deseada.',
                @estadoResultado = 0
    END
END
GO
