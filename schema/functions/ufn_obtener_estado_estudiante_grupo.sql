USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION [dbo].[ufn_obtener_estado_estudiante_grupo]
(
    @idEstudiante UNIQUEIDENTIFIER,
    @idGrupo      UNIQUEIDENTIFIER
)
RETURNS NVARCHAR(100)
AS
BEGIN
    DECLARE @nombreEstado NVARCHAR(100) = N'NO INSCRITO';

    SELECT TOP 1 
        @nombreEstado = eg.nombreEstadoEstudiante
    FROM dbo.uv_estudiante_grupo eg
    WHERE eg.idEstudiante = @idEstudiante
      AND eg.idGrupo = @idGrupo;

    RETURN ISNULL(@nombreEstado, N'NO INSCRITO');
END
GO
