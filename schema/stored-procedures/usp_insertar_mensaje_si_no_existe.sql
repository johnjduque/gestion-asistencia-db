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
    IF NOT EXISTS (
        SELECT 1
        FROM Utilitario.Mensajes
        WHERE codigo = @p_codigo AND tipo = @p_tipo
    )
    BEGIN
        INSERT INTO Utilitario.Mensajes (codigo, tipo, contenido)
        VALUES (@p_codigo, @p_tipo, @p_contenido);
    END
END;
GO
