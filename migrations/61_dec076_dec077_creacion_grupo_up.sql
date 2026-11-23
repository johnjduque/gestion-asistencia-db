-- ============================================================================
-- MIGRACION UP 61: DEC-076 y DEC-077 (2026-11-20) - creacion de grupos por el coordinador
--   DEC-076: usp_crear_grupo sin periodo toma el ACTIVO (inicio mas reciente) o el proximo en PLANEACION, en vez del de mayor anio, y
--            rechaza un periodo CERRADO con PER_010 (la precarga solo genera sesiones desde hoy: el grupo quedaba sin sesiones).
--   DEC-077: programa responsable del grupo. Nueva columna Grupo.programaResponsable (FK a Programa, NULL) y funcion
--            ufn_programas_grupo_responsable: en un grupo compartido por varios programas solo el coordinador del programa
--            responsable gestiona el grupo, aprueba o rechaza sus solicitudes de sesion, cancela sesiones y recibe los avisos del
--            grupo (sesion manual, sesion sin toma). Los asuntos de cada estudiante siguen yendo al coordinador de su programa.
--   1. Mensaje PER_010 (seed 17_mensajes_periodo_academico.sql).
--   2. Columna Grupo.programaResponsable y FK_Grupo_ProgramaResponsable.
--   3. Funcion ufn_programas_grupo_responsable.
--   4. Rellena programaResponsable de los grupos existentes con la regla de la funcion (mas estudiantes del grupo, luego nombre).
--   Los cuerpos de usp_crear_grupo (parametro aditivo @idProgramaResponsable), usp_validar_gestion_grupo_coordinador_o_titular_interno,
--   usp_validar_coordinador_sesion_interno, usp_consultar_destinatarios_sesion_manual, usp_consultar_destinatarios_aviso_sin_toma,
--   usp_cancelar_sesion_coordinador (solo comentario) y la vista uv_solicitud_sesion se despliegan con deploy_schema.ps1
--   (CREATE OR ALTER), como en la 48, la 49 y la 56.
-- Idempotente. Down: 61_dec076_dec077_creacion_grupo_down.sql.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
PRINT 'MIGRACION 61 UP: DEC-076/DEC-077 creacion de grupos';
GO

MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PER_010', 'BUSINESS_ERROR', 'MEDIO', N'El período académico {} ya terminó; no se pueden crear grupos en él porque no tendrían sesiones por programar.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('PER_010', 'BUSINESS_ERROR', 'MEDIO', N'Regla: uv_periodo_academico.estado del periodo {} es CERRADO (fecha local institucional > fechaFin); usp_crear_grupo no crea grupos en un periodo terminado (la precarga no generaria sesiones).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- ---- schema/tables/Grupo.sql y zz_foreign_keys.sql
IF COL_LENGTH('dbo.Grupo', 'programaResponsable') IS NULL
BEGIN
    ALTER TABLE [dbo].[Grupo] ADD [programaResponsable] uniqueidentifier NULL;
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Grupo_ProgramaResponsable')
BEGIN
    ALTER TABLE [dbo].[Grupo] ADD CONSTRAINT [FK_Grupo_ProgramaResponsable] FOREIGN KEY ([programaResponsable]) REFERENCES [dbo].[Programa] ([id]);
END
GO

-- ---- schema/functions/ufn_programas_grupo_responsable.sql
CREATE OR ALTER FUNCTION [dbo].[ufn_programas_grupo_responsable] (@idGrupo UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT  TOP (1) pg.idPrograma, pg.idPlanEstudio, pg.inpPlanEstudio
    FROM    dbo.ufn_programas_grupo(@idGrupo) pg
    INNER JOIN dbo.Programa p ON p.id = pg.idPrograma
    OUTER APPLY (SELECT g.programaResponsable FROM dbo.Grupo g WHERE g.id = @idGrupo) r
    OUTER APPLY (SELECT inscritos = COUNT(*)
                 FROM dbo.EstudianteGrupo eg
                 INNER JOIN dbo.EstudiantePrograma ep ON ep.estudiante = eg.estudiante AND ep.programa = pg.idPrograma
                 WHERE eg.grupo = @idGrupo) c
    ORDER BY IIF(pg.idPrograma = r.programaResponsable, 0, 1), c.inscritos DESC, p.nombre, p.id
);
GO

-- Relleno: los grupos anteriores quedan con el programa que la regla ya les asignaba (mas estudiantes del grupo, luego nombre).
UPDATE g
SET    g.programaResponsable = r.idPrograma
FROM   dbo.Grupo g
CROSS APPLY dbo.ufn_programas_grupo_responsable(g.id) r
WHERE  g.programaResponsable IS NULL;
GO

PRINT 'MIGRACION 61 UP OK (ejecute deploy_schema.ps1 para los cuerpos de los SP y de uv_solicitud_sesion)';
GO
