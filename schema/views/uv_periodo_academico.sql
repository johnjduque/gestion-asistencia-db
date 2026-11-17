USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CIERRE-W2A (punto 4): `estado` resuelto en la base con la fecha local institucional (TIEMPO/ZONA_HORARIA_SQLSERVER), igual que
-- uv_grupo: PLANEACION (aun no inicia), ACTIVO (vigente hoy) o CERRADO (ya termino). El cliente no deduce el estado con su reloj.
CREATE OR ALTER  VIEW [dbo].[uv_periodo_academico]
AS
SELECT		id = pa.id,
			idInstitucion = i.id,
			nombreInstitucion = i.nombre,
			nombre = pa.nombre,
			codigo = pa.codigo,
			fechaInicio = pa.fechaInicio,
			fechaFin = pa.fechaFin,
			anio = pa.anio,
			estado = CASE WHEN t.fechaLocalInstitucional < pa.fechaInicio THEN 'PLANEACION'
			              WHEN t.fechaLocalInstitucional > pa.fechaFin THEN 'CERRADO'
			              ELSE 'ACTIVO' END

FROM		PeriodoAcademico pa
INNER JOIN	uv_institucion i
ON			pa.institucion = i.id
CROSS APPLY (
    SELECT fechaLocalInstitucional = CAST(
        SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE COALESCE(
            (SELECT TOP 1 valor
             FROM dbo.CatalogoParametro
             WHERE grupo = 'TIEMPO'
               AND clave = 'ZONA_HORARIA_SQLSERVER'
               AND estaActivo = 1),
            'SA Pacific Standard Time'
        ) AS DATE
    )
) t
GO
