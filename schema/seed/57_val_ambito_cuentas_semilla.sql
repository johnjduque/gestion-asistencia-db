USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- VAL ROL-12 (hallazgo H-03): las cuentas semilla de decano (decano.ingenieria@uco.edu.co) y coordinador (coordinador.sistemas@uco.edu.co)
-- deben tener ambito: el decano es titular de la Facultad de Ingenieria (Facultad.decano, lo mismo que deja usp_crear_decano_interno) y el
-- coordinador coordina Ingenieria de Sistemas (Programa.coordinador) y conserva su facultad (Coordinador.facultad, lo mismo que deja
-- usp_crear_coordinador_interno). Idempotente: solo actua si las filas semilla existen y la cuenta aun no tiene ese ambito.
DECLARE @idDecanoSemilla      UNIQUEIDENTIFIER = 'F1A2B3C4-0000-0000-0000-000000000001';
DECLARE @idCoordinadorSemilla UNIQUEIDENTIFIER = 'F1A2B3C4-0000-0000-0000-000000000002';
DECLARE @idFacultadSemilla    UNIQUEIDENTIFIER = 'A2B3C4D5-0000-0000-0000-000000000001';
DECLARE @idProgramaSemilla    UNIQUEIDENTIFIER = 'B2C3D4E5-0000-0000-0000-000000000001';

IF EXISTS (SELECT 1 FROM dbo.Decano WHERE id = @idDecanoSemilla)
   AND EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @idFacultadSemilla)
   AND NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE decano = @idDecanoSemilla)
    UPDATE dbo.Facultad SET decano = @idDecanoSemilla WHERE id = @idFacultadSemilla;

IF EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @idCoordinadorSemilla)
   AND EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @idFacultadSemilla)
    UPDATE dbo.Coordinador SET facultad = @idFacultadSemilla WHERE id = @idCoordinadorSemilla AND facultad IS NULL;

IF EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @idCoordinadorSemilla)
   AND EXISTS (SELECT 1 FROM dbo.Programa WHERE id = @idProgramaSemilla AND facultad = @idFacultadSemilla)
   AND NOT EXISTS (SELECT 1 FROM dbo.Programa WHERE coordinador = @idCoordinadorSemilla)
    UPDATE dbo.Programa SET coordinador = @idCoordinadorSemilla WHERE id = @idProgramaSemilla;
GO
