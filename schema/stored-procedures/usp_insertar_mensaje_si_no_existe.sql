USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  PROCEDURE [dbo].[usp_insertar_mensaje_si_no_existe]
    @p_codigo NVARCHAR(50),
    @p_tipo NVARCHAR(20),
    @p_contenido NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @codigo VARCHAR(100) = CONVERT(VARCHAR(100), TRIM(@p_codigo));
    DECLARE @tipoMensaje VARCHAR(50) = CONVERT(VARCHAR(50), TRIM(@p_tipo));
    DECLARE @contenido NVARCHAR(4000) = LEFT(TRIM(@p_contenido), 4000);

    MERGE INTO dbo.CatalogoMensajeUsuario AS Target
    USING (VALUES (@codigo, @tipoMensaje, @contenido)) AS Source (codigo, tipoMensaje, contenido)
    ON Target.codigo = Source.codigo
    WHEN NOT MATCHED THEN
        INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
        VALUES (Source.codigo, Source.tipoMensaje, 'MEDIO', Source.contenido, 1, GETDATE(), GETDATE());

    MERGE INTO dbo.CatalogoMensajeTecnico AS Target
    USING (VALUES (@codigo, @tipoMensaje, @contenido)) AS Source (codigo, tipoMensaje, contenido)
    ON Target.codigo = Source.codigo
    WHEN NOT MATCHED THEN
        INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
        VALUES (Source.codigo, Source.tipoMensaje, 'CRITICO', Source.contenido, 1, GETDATE(), GETDATE());
END;
GO
