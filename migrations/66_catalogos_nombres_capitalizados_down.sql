-- ============================================================================
-- MIGRACION DOWN 66: restaura los nombres de catalogo en minuscula previos a la migracion 66. Idempotente.
-- Si se despliega el esquema actual (seeds con mayuscula inicial) despues del down, los seeds vuelven a capitalizarlos.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 66 DOWN: nombres de catalogo con mayuscula inicial';
GO
UPDATE t SET t.nombre = v.nombre
FROM [dbo].[TipoPrograma] t
JOIN (VALUES
    (N'PRE', N'pregrado'),
    (N'POS', N'postgrado')
) AS v (codigo, nombre) ON t.codigo = v.codigo
WHERE t.nombre COLLATE Latin1_General_CS_AS <> v.nombre COLLATE Latin1_General_CS_AS;
GO
UPDATE t SET t.nombre = v.nombre
FROM [dbo].[Estado] t
JOIN (VALUES
    (N'A', N'aceptada'),
    (N'P', N'pendiente'),
    (N'R', N'rechazada'),
    (N'X', N'retirada')
) AS v (codigo, nombre) ON t.codigo = v.codigo
WHERE t.nombre COLLATE Latin1_General_CS_AS <> v.nombre COLLATE Latin1_General_CS_AS;
GO
UPDATE t SET t.nombre = v.nombre
FROM [dbo].[EstadoEstudianteGrupo] t
JOIN (VALUES
    (N'CVP', N'cancelado por voluntad propia'),
    (N'A', N'activo'),
    (N'I', N'inactivo'),
    (N'CI', N'cancelado por inasistencia'),
    (N'F', N'finalizado')
) AS v (codigo, nombre) ON t.codigo = v.codigo
WHERE t.nombre COLLATE Latin1_General_CS_AS <> v.nombre COLLATE Latin1_General_CS_AS;
GO
UPDATE t SET t.nombre = v.nombre
FROM [dbo].[RazonCausa] t
JOIN (VALUES
    (N'AN', N'asistencia normal'),
    (N'SJC', N'sin justa causa'),
    (N'EX', N'excusa'),
    (N'CPVP', N'cancelado por voluntad propia'),
    (N'CPI', N'cancelado por inasistencia')
) AS v (codigo, nombre) ON t.codigo = v.codigo
WHERE t.nombre COLLATE Latin1_General_CS_AS <> v.nombre COLLATE Latin1_General_CS_AS;
GO
UPDATE t SET t.nombre = v.nombre
FROM [dbo].[TipoIdentificacion] t
JOIN (VALUES
    (N'CC', N'Cedula de ciudadania'),
    (N'CE', N'Cedula de extranjeria')
) AS v (codigo, nombre) ON t.tipoIdentificacion = v.codigo
WHERE t.nombre COLLATE Latin1_General_CS_AS <> v.nombre COLLATE Latin1_General_CS_AS;
GO
PRINT 'MIGRACION 66 DOWN OK';
GO
