-- ============================================================================
-- MIGRACION UP 65: nombres de catalogo con mayuscula inicial (C4)
--   Solo cambia el texto mostrado: dbo.TipoPrograma ('pregrado'/'postgrado' pasan a 'Pregrado'/'Posgrado'), dbo.Estado (estados de
--   reclamo), dbo.EstadoEstudianteGrupo y dbo.RazonCausa y dbo.TipoIdentificacion (CC y CE con tildes). Se actualiza por codigo; ninguna logica compara estos nombres (SP, vistas,
--   backend y frontend usan codigos; el frontend normaliza el estado de solicitud con toLowerCase). dbo.Perfil NO se toca: algunos SP
--   comparan UPPER(nombrePerfil). Los seeds (schema/seed/05..08, 33_culm001_a_catalogos) quedan con los mismos valores.
-- Idempotente. Down: 65_catalogos_nombres_capitalizados_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 65 UP: nombres de catalogo con mayuscula inicial';
GO
UPDATE t SET t.nombre = v.nombre
FROM [dbo].[TipoPrograma] t
JOIN (VALUES
    (N'PRE', N'Pregrado'),
    (N'POS', N'Posgrado')
) AS v (codigo, nombre) ON t.codigo = v.codigo
WHERE t.nombre COLLATE Latin1_General_CS_AS <> v.nombre COLLATE Latin1_General_CS_AS;
GO
UPDATE t SET t.nombre = v.nombre
FROM [dbo].[Estado] t
JOIN (VALUES
    (N'A', N'Aceptada'),
    (N'P', N'Pendiente'),
    (N'R', N'Rechazada'),
    (N'X', N'Retirada')
) AS v (codigo, nombre) ON t.codigo = v.codigo
WHERE t.nombre COLLATE Latin1_General_CS_AS <> v.nombre COLLATE Latin1_General_CS_AS;
GO
UPDATE t SET t.nombre = v.nombre
FROM [dbo].[EstadoEstudianteGrupo] t
JOIN (VALUES
    (N'CVP', N'Cancelado por voluntad propia'),
    (N'A', N'Activo'),
    (N'I', N'Inactivo'),
    (N'CI', N'Cancelado por inasistencia'),
    (N'F', N'Finalizado')
) AS v (codigo, nombre) ON t.codigo = v.codigo
WHERE t.nombre COLLATE Latin1_General_CS_AS <> v.nombre COLLATE Latin1_General_CS_AS;
GO
UPDATE t SET t.nombre = v.nombre
FROM [dbo].[RazonCausa] t
JOIN (VALUES
    (N'AN', N'Asistencia normal'),
    (N'SJC', N'Sin justa causa'),
    (N'EX', N'Excusa'),
    (N'CPVP', N'Cancelado por voluntad propia'),
    (N'CPI', N'Cancelado por inasistencia')
) AS v (codigo, nombre) ON t.codigo = v.codigo
WHERE t.nombre COLLATE Latin1_General_CS_AS <> v.nombre COLLATE Latin1_General_CS_AS;
GO
UPDATE t SET t.nombre = v.nombre
FROM [dbo].[TipoIdentificacion] t
JOIN (VALUES
    (N'CC', N'C' + NCHAR(233) + N'dula de ciudadan' + NCHAR(237) + N'a'),
    (N'CE', N'C' + NCHAR(233) + N'dula de extranjer' + NCHAR(237) + N'a')
) AS v (codigo, nombre) ON t.tipoIdentificacion = v.codigo
WHERE t.nombre COLLATE Latin1_General_CS_AS <> v.nombre COLLATE Latin1_General_CS_AS;
GO
PRINT 'MIGRACION 65 UP OK';
GO
