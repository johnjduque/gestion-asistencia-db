USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (CONTRACT §2.6, R8): programas que coordina un usuario (reemplaza los TOP 1 de programa).
CREATE OR ALTER FUNCTION [dbo].[ufn_programas_coordinador] (@idUsuario UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT  idPrograma = p.id
    FROM    dbo.Programa p
    INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
    WHERE   c.usuario = @idUsuario
);
GO
