USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- 1. Sembrado Idempotente: Usuarios (Decano, Coordinador, Docente, Estudiantes)
DECLARE @TipoCC UNIQUEIDENTIFIER;
SELECT TOP 1 @TipoCC = id FROM [dbo].[TipoIdentificacion] WHERE tipoIdentificacion = 'CC';

MERGE INTO [dbo].[Usuario] AS Target
USING (VALUES
    ('E1F2A3B4-0000-0000-0000-000000000001', @TipoCC, 1017000001, 'Gomez', 'Perez', 'Juan', 'Carlos', 'decano.ingenieria@uco.edu.co', 1, 1, '123456'),
    ('E1F2A3B4-0000-0000-0000-000000000002', @TipoCC, 1017000002, 'Lopez', 'Martinez', 'Andres', 'Felipe', 'coordinador.sistemas@uco.edu.co', 1, 1, '123456'),
    ('E1F2A3B4-0000-0000-0000-000000000003', @TipoCC, 1017112233, 'Rostagno', 'Valencia', 'Maria', 'Elena', 'maria.rostagno@aurora.edu.pe', 1, 1, '123456'),
    ('E1F2A3B4-0000-0000-0000-000000000004', @TipoCC, 1017223344, 'Zapata', 'Gomez', 'Carlos', 'Andres', 'carlos.zapata@uco.edu.co', 1, 1, '123456'),
    ('E1F2A3B4-0000-0000-0000-000000000005', @TipoCC, 1017334455, 'Gomez', 'Rios', 'Ana', 'Sofia', 'ana.gomez@uco.edu.co', 1, 1, '123456')
) AS Source (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
ON (Target.correo = Source.correo)
WHEN MATCHED THEN
    UPDATE SET 
        Target.primerNombre = Source.primerNombre,
        Target.primerApellido = Source.primerApellido,
        Target.password = Source.password
WHEN NOT MATCHED THEN
    INSERT (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.tipoIdIdentificacion, Source.numeroIdentificacion, Source.primerApellido, Source.segundoApellido, Source.primerNombre, Source.segundoNombre, Source.correo, Source.correoConfirmado, Source.estado, Source.password);
GO

-- 2. Sembrado Idempotente: Decano
MERGE INTO [dbo].[Decano] AS Target
USING (VALUES
    ('F1A2B3C4-0000-0000-0000-000000000001', 'E1F2A3B4-0000-0000-0000-000000000001')
) AS Source (id, usuario)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN NOT MATCHED THEN
    INSERT (id, usuario)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER));
GO

-- 3. Sembrado Idempotente: Coordinador
MERGE INTO [dbo].[Coordinador] AS Target
USING (VALUES
    ('F1A2B3C4-0000-0000-0000-000000000002', 'E1F2A3B4-0000-0000-0000-000000000002')
) AS Source (id, usuario)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN NOT MATCHED THEN
    INSERT (id, usuario)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER));
GO

-- 4. Sembrado Idempotente: Docente
MERGE INTO [dbo].[Docente] AS Target
USING (VALUES
    ('F1A2B3C4-0000-0000-0000-000000000003', 'E1F2A3B4-0000-0000-0000-000000000003')
) AS Source (id, usuario)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN NOT MATCHED THEN
    INSERT (id, usuario)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER));
GO

-- 5. Sembrado Idempotente: Estudiantes
MERGE INTO [dbo].[Estudiante] AS Target
USING (VALUES
    ('F1A2B3C4-0000-0000-0000-000000000004', 'E1F2A3B4-0000-0000-0000-000000000004'),
    ('F1A2B3C4-0000-0000-0000-000000000005', 'E1F2A3B4-0000-0000-0000-000000000005')
) AS Source (id, usuario)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER))
WHEN NOT MATCHED THEN
    INSERT (id, usuario)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), TRY_CAST(Source.usuario AS UNIQUEIDENTIFIER));
GO
