USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B2NM (CONTRACT §2.6): programas del ambito de un ejecutor. Coordinador -> sus programas; decano -> programas de su facultad.
CREATE OR ALTER FUNCTION [dbo].[ufn_programas_ambito_ejecutor] (@idUsuario UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT  idPrograma = p.id, rol = CAST(N'COORDINADOR' AS NVARCHAR(20))
    FROM    dbo.Programa p
    INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
    WHERE   c.usuario = @idUsuario
    UNION
    SELECT  idPrograma = p.id, rol = CAST(N'DECANO' AS NVARCHAR(20))
    FROM    dbo.Programa p
    INNER JOIN dbo.Facultad f ON f.id = p.facultad
    INNER JOIN dbo.Decano d ON d.id = f.decano
    WHERE   d.usuario = @idUsuario
);
GO
