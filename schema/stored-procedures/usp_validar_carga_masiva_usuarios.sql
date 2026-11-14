USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- DEC-074 (2026-11-13): RETIRADO. La carga masiva de usuarios por CSV (HU171, CULM-001 D.5) se elimino del sistema:
-- decanos, coordinadores y docentes se registran uno por uno. Este archivo ya no crea el SP; solo lo borra si existe.
-- Se conserva en esta ruta porque la migracion 24 (ya aplicada en todas las bases) lo incluye con :r; al reaplicarla
-- en orden, la 24 deja de crearlo y la 44 retira el resto (tabla, vista, parametros y mensajes). test_summary.ps1 lo
-- excluye del inventario de SP publicos. El SP original esta en el down de la migracion 44.
-- ============================================================================
IF OBJECT_ID(N'dbo.usp_validar_carga_masiva_usuarios', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_validar_carga_masiva_usuarios];
GO
