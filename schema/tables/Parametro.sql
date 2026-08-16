USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Parametro]', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.[Parametro];
END
GO

CREATE TABLE [dbo].[Parametro] (
    [grupo]             VARCHAR(100)    NOT NULL, -- Ámbito/Subsistema (ej: 'GLOBAL_FUN_GEN', 'GLOBAL_TEC_GEN', 'SISTEMA')
    [clave]             VARCHAR(100)    NOT NULL, -- Identificador único de la variable (ej: 'Rol_Usuario', 'Rango_Semestre')
    [valor]             NVARCHAR(MAX)   NOT NULL, -- Valor actual de configuración (String, Number, JSON, Bool)
    [tipoDato]          VARCHAR(20)     NOT NULL DEFAULT 'STRING', -- 'STRING', 'INT', 'DECIMAL', 'BOOLEAN', 'JSON', 'DATE'
    [descripcion]       NVARCHAR(500)   NULL,     -- Explicación funcional o técnica del parámetro
    [valorDefecto]      NVARCHAR(MAX)   NULL,     -- Valor de respaldo en caso de reinicio de fábrica
    [estaActivo]        BIT             NOT NULL DEFAULT 1, -- 1: Activo, 0: Inactivo/Deshabilitado
    [fechaCreacion]     DATETIME        NOT NULL DEFAULT GETDATE(),
    [fechaModificacion] DATETIME        NULL
);
GO

ALTER TABLE [dbo].[Parametro] ADD CONSTRAINT [PK_Parametro] PRIMARY KEY CLUSTERED ([grupo], [clave]);
GO

-- Índice optimizado para lecturas frecuentes por grupo y estado
CREATE NONCLUSTERED INDEX [IX_Parametro_Grupo_Clave_Activo] ON [dbo].[Parametro] ([grupo], [clave], [estaActivo]) INCLUDE ([valor], [tipoDato]);
GO
