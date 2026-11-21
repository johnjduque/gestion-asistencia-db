USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU005/HU016: categorias de justificacion (catalogo de solo consulta). El runtime recibe SELECT con el resto de
-- vistas uv_* (rol_asistencias_runtime.sql). Migracion 65: solo las categorias ACTIVAS (las que se ofrecen al estudiante);
-- el administrador ve todas en uv_categoria_justificacion_admin. CULM-001 D.2: + requiereSoporte (HU014: la categoria exige al menos un soporte).
CREATE OR ALTER VIEW [dbo].[uv_categoria_justificacion]
AS
SELECT  id,
        codigo,
        nombre,
        descripcion,
        requiereSoporte
FROM    dbo.CategoriaJustificacion
WHERE   estaActivo = 1
GO
