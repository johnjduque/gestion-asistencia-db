USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION UP: IDENT-001 - Token de verificacion de correo y parametros del correo institucional
-- ============================================================================
-- La funcion ufn_correo_cumple_dominio_institucional, los SP usp_emitir_/usp_consultar_/usp_confirmar_ del token,
-- usp_consultar_reenvio_verificacion_correo, el SP usp_registrar_estudiante_en_grupo, los mensajes VCE_*, la plantilla
-- VERIFICACION_CORREO y los permisos se despliegan con deploy_schema.ps1 (CREATE OR ALTER / MERGE idempotentes).

-- 1. Tabla
IF OBJECT_ID('dbo.TokenVerificacionCorreo', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TokenVerificacionCorreo (
        id                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_TokenVerificacionCorreo_id DEFAULT NEWID(),
        usuario            UNIQUEIDENTIFIER NOT NULL,
        tokenHash          VARBINARY(32)    NOT NULL,
        fechaEmisionUtc    DATETIME2(0)     NOT NULL,
        fechaExpiracionUtc DATETIME2(0)     NOT NULL,
        fechaUsoUtc        DATETIME2(0)     NULL,
        fechaRevocacionUtc DATETIME2(0)     NULL,
        CONSTRAINT PK_TokenVerificacionCorreo PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TokenVerificacionCorreo_tokenHash UNIQUE (tokenHash),
        CONSTRAINT CK_TokenVerificacionCorreo_vigencia CHECK (fechaExpiracionUtc > fechaEmisionUtc)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TokenVerificacionCorreo_activo' AND object_id = OBJECT_ID('dbo.TokenVerificacionCorreo'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenVerificacionCorreo_activo
    ON dbo.TokenVerificacionCorreo (usuario)
    WHERE fechaUsoUtc IS NULL AND fechaRevocacionUtc IS NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TokenVerificacionCorreo_Usuario')
BEGIN
    ALTER TABLE dbo.TokenVerificacionCorreo ADD CONSTRAINT FK_TokenVerificacionCorreo_Usuario FOREIGN KEY (usuario) REFERENCES dbo.Usuario (id);
END
GO

-- 2. Parametros
MERGE INTO dbo.CatalogoParametro AS Target
USING (VALUES
    ('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE', N'@uco.edu.co', 'STRING', N'@uco.edu.co'),
    ('VERIFICACION_CORREO', 'TTL_HORAS', N'24', 'INT', N'24'),
    ('VERIFICACION_CORREO', 'REENVIO_ESPERA_MINUTOS', N'5', 'INT', N'5')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
