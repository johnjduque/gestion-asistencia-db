USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEC-081: dias de receso academico ACTIVOS de cada periodo, con el numero de sesiones que cada uno ya cancelo
-- (dbo.SesionCancelacion.recesoAcademico). estaAplicado = 1 cuando cancelo al menos una sesion: un dia aplicado no se retira
-- (usp_retirar_receso_academico). La visibilidad por perfil la imponen usp_consultar_recesos_periodo y los SP de escritura;
-- la vista no filtra por usuario. Los dias retirados (estaActivo = 0) no aparecen.
CREATE OR ALTER VIEW [dbo].[uv_periodo_receso_academico]
AS
SELECT  id = r.id,
        idPeriodoAcademico = pa.id,
        nombrePeriodo = pa.nombre,
        idInstitucion = pa.institucion,
        fecha = r.fecha,
        motivo = r.motivo,
        fechaCreacionUtc = r.fechaCreacionUtc,
        idUsuarioCreador = r.usuarioCreador,
        sesionesCanceladas = c.total,
        estaAplicado = CAST(IIF(c.total > 0, 1, 0) AS BIT)
FROM    dbo.PeriodoRecesoAcademico r
INNER JOIN dbo.PeriodoAcademico pa
ON      pa.id = r.periodoAcademico
CROSS APPLY (
        SELECT total = COUNT(1)
        FROM   dbo.SesionCancelacion sc
        WHERE  sc.recesoAcademico = r.id
) c
WHERE   r.estaActivo = 1;
GO
