USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 / DEC-064: sesiones creadas manualmente por el docente (fuera de la precarga por horario). Los dos endpoints de creacion
-- (usp_crear_sesion v1 -> procedenciaTemporal NULL; usp_crear_sesion_v2 -> UTC_V2) son manuales; la precarga y el generador marcan
-- UTC_GENERADOR y la clasificacion administrativa de historicos UTC_OWNER: esas NO son manuales. Limitaciones conocidas: NULL tambien
-- es una fila historica anterior a UTC-D06 (se trata como manual; una sesion con asistencia no se puede cancelar de todos modos) y una
-- sesion generada que el docente edita por la via v2 pasa a UTC_V2.
CREATE OR ALTER VIEW [dbo].[uv_sesion_manual]
AS
SELECT  idSesion = s.id,
        idGrupo = s.grupo,
        numero = s.numero,
        nombre = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin
FROM    dbo.Sesion s
WHERE   s.procedenciaTemporal IS NULL OR s.procedenciaTemporal = N'UTC_V2';
GO
