USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: sesiones creadas manualmente por el docente (fuera de la precarga por horario). La procedencia temporal las
-- distingue: usp_crear_sesion_v2 / usp_actualizar_sesion_v2 marcan UTC_V2; la precarga y el generador marcan UTC_GENERADOR; la
-- clasificacion administrativa UTC_OWNER y la historica (NULL) no son manuales. Una sesion generada que el docente edita por la
-- via v2 pasa a UTC_V2 (limitacion conocida: se trata como manual desde ese momento).
CREATE OR ALTER VIEW [dbo].[uv_sesion_manual]
AS
SELECT  idSesion = s.id,
        idGrupo = s.grupo,
        numero = s.numero,
        nombre = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin
FROM    dbo.Sesion s
WHERE   s.procedenciaTemporal = N'UTC_V2';
GO
