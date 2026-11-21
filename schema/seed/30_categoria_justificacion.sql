USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado idempotente: CategoriaJustificacion (HU005/HU016). Los nombres son los que el formulario de reclamo ya
-- envia en @categoria al SP de radicacion, para no romper el contrato actual.
-- Migracion 65: el catalogo lo administra el ADMINISTRADOR (usp_crear/actualizar/cambiar_estado_categoria_justificacion); por eso el
-- sembrado solo INSERTA las filas ausentes y no pisa nombre, descripcion, requiereSoporte ni estaActivo ya administrados. requiereSoporte
-- (HU014: MED, ACA y LAB exigen al menos un soporte) nace aqui con la fila.
MERGE INTO [dbo].[CategoriaJustificacion] AS Target
USING (VALUES
    ('CA7E0000-0000-0000-0000-000000000001', N'MED', N'Médico / Salud',
     N'Enfermedad, cita o urgencia médica, incapacidad u hospitalización.', 1),
    ('CA7E0000-0000-0000-0000-000000000002', N'CAL', N'Calamidad Doméstica',
     N'Situación grave e imprevista del núcleo familiar: fallecimiento, accidente o enfermedad grave de un familiar.', 0),
    ('CA7E0000-0000-0000-0000-000000000003', N'ACA', N'Académico / Representación',
     N'Actividad académica, deportiva o cultural en representación de la universidad, o participación en un evento institucional.', 1),
    ('CA7E0000-0000-0000-0000-000000000004', N'FMA', N'Fuerza Mayor',
     N'Hecho imprevisible e irresistible ajeno al estudiante: desastre natural, orden público o cierre de vías.', 0),
    ('CA7E0000-0000-0000-0000-000000000005', N'LAB', N'Laboral',
     N'Obligación laboral comprobable que coincidió con la sesión.', 1),
    ('CA7E0000-0000-0000-0000-000000000006', N'OTR', N'Otro',
     N'Motivo distinto a los anteriores; explícalo en la justificación del reclamo.', 0)
) AS Source (id, codigo, nombre, descripcion, requiereSoporte)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, descripcion, requiereSoporte)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.codigo, Source.nombre, Source.descripcion, Source.requiereSoporte);
GO
