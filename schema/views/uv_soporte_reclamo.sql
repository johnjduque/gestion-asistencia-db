USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.2 (CONTRACT §3.2, HU015): soportes vinculados (ATTACHED) a un reclamo, en orden de adjuncion. Un reclamo puede tener
-- de 0 a ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO. El estado "adjunto" sale de ARCHIVO/ESTADO_ADJUNTO (sin literal quemado).
-- orden = posicion del soporte dentro del reclamo (1 = el primero adjuntado; desempate por id).
CREATE OR ALTER VIEW [dbo].[uv_soporte_reclamo]
AS
SELECT  idSolicitud       = a.solicitudRevisionAsistencia,
        idArchivo         = a.id,
        nombreOriginal    = a.nombreOriginal,
        tipoContenido     = a.tipoContenido,
        tamanioBytes      = a.tamanioBytes,
        fechaAdjuncionUtc = a.fechaAdjuncionUtc,
        orden             = ROW_NUMBER() OVER (PARTITION BY a.solicitudRevisionAsistencia ORDER BY a.fechaAdjuncionUtc, a.id)
FROM    dbo.ArchivoSoporte a
WHERE   a.solicitudRevisionAsistencia IS NOT NULL
  AND   a.estado = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10))
GO
