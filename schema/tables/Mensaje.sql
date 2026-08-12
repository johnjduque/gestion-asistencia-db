USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Mensaje]', 'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.[Mensaje];
END
GO

CREATE TABLE [dbo].[Mensaje] (
    [codigo]            VARCHAR(100)    NOT NULL,
    [tipo]              VARCHAR(20)     NOT NULL, -- 'USUARIO', 'TECNICO', 'EXITO', 'ERROR', 'ADVERTENCIA', 'INFORMACION'
    [numero]            VARCHAR(10)     NULL,     -- Código numérico de correlación/seguimiento (ej: '00001')
    [severidad]         INT             NOT NULL DEFAULT 0,  -- Nivel de severidad SQL / Log (0 = Info, 16 = User, 18 = Error Sistema)
    [estado]            INT             NOT NULL DEFAULT 200, -- Mapeo a código de estado (ej: HTTP 200, 400, 404, 500)
    [contenidoUsuario]  NVARCHAR(4000)  NOT NULL, -- Mensaje amigable para UI / Frontend
    [contenidoTecnico]  NVARCHAR(4000)  NOT NULL, -- Mensaje técnico parametrizado para logs / auditoría
    [descripcion]       NVARCHAR(500)   NULL,     -- Documentación contextual del propósito del mensaje
    [estaActivo]        BIT             NOT NULL DEFAULT 1,
    [fechaCreacion]     DATETIME        NOT NULL DEFAULT GETDATE()
);
GO

ALTER TABLE [dbo].[Mensaje] ADD CONSTRAINT [PK_Mensaje] PRIMARY KEY CLUSTERED ([codigo], [tipo]);
GO

-- Índice no agrupado para acelerar búsquedas por tipo y estado activo
CREATE NONCLUSTERED INDEX [IX_Mensaje_Tipo_Activo] ON [dbo].[Mensaje] ([tipo], [estaActivo]) INCLUDE ([codigo], [contenidoUsuario], [contenidoTecnico]);
GO
