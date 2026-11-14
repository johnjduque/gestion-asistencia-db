USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEC-073: los validadores internos nuevos solo se alcanzan por encadenamiento de propiedad desde los SP publicos
-- (crear/actualizar sesion, altas de personal y actualizacion del coordinador); el rol runtime no los ejecuta directo.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO
IF OBJECT_ID(N'dbo.usp_validar_sesion_mismo_dia_interno', N'P') IS NULL
    THROW 52731, 'DEC073_RUNTIME: usp_validar_sesion_mismo_dia_interno requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_validar_correo_institucional_personal_interno', N'P') IS NULL
    THROW 52732, 'DEC073_RUNTIME: usp_validar_correo_institucional_personal_interno requerido ausente.', 1;
GO
DENY EXECUTE ON [dbo].[usp_validar_sesion_mismo_dia_interno] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_validar_correo_institucional_personal_interno] TO [rol_asistencias_runtime];
GO
