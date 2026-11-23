USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_recesos_periodo (DEC-081) — READ_QUERY_RESULTSET: dias de receso activos de un periodo, ordenados por fecha.
-- Lectura permitida a ADMINISTRADOR, DECANO, COORDINADOR y DOCENTE cuya institucion sea la del periodo (administrador: Administrador.institucion;
-- decano: su facultad; coordinador: un programa que coordina; docente: vinculo activo a un programa o grupo titular en el periodo).
-- Sin perfil => SEC_001; periodo inexistente o fuera del ambito => PER_001. Las fallas se propagan con THROW 51000.
-- Columnas: id, idPeriodoAcademico, fecha, motivo, sesionesCanceladas (INT), estaAplicado (BIT), puedeRetirarse (BIT: no aplicado y periodo
-- sin cerrar), fechaCreacionUtc, totalRegistros.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_recesos_periodo]
(
    @idPeriodo         UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPeriodoDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPeriodo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idInstitucion        UNIQUEIDENTIFIER;
    DECLARE @fechaCierreUtc       DATETIME2(7);
    DECLARE @enAmbito             BIT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ADMINISTRADOR,DECANO,COORDINADOR,DOCENTE',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1
    BEGIN
        SELECT @idInstitucion = pa.institucion, @fechaCierreUtc = pa.fechaCierreUtc
        FROM dbo.PeriodoAcademico pa WHERE pa.id = @idPeriodoDefecto;

        IF @idInstitucion IS NOT NULL
           AND (EXISTS (SELECT 1 FROM dbo.Administrador a WHERE a.usuario = @idUsuarioDefecto AND a.institucion = @idInstitucion)
             OR EXISTS (SELECT 1 FROM dbo.Decano d INNER JOIN dbo.Facultad f ON f.decano = d.id
                        WHERE d.usuario = @idUsuarioDefecto AND f.institucion = @idInstitucion)
             OR EXISTS (SELECT 1 FROM dbo.Coordinador c INNER JOIN dbo.Programa p ON p.coordinador = c.id
                        INNER JOIN dbo.Facultad f ON f.id = p.facultad
                        WHERE c.usuario = @idUsuarioDefecto AND f.institucion = @idInstitucion)
             OR EXISTS (SELECT 1 FROM dbo.Docente dc INNER JOIN dbo.DocentePrograma dp ON dp.docente = dc.id AND dp.estado = 1
                        INNER JOIN dbo.Programa p ON p.id = dp.programa INNER JOIN dbo.Facultad f ON f.id = p.facultad
                        WHERE dc.usuario = @idUsuarioDefecto AND f.institucion = @idInstitucion)
             OR EXISTS (SELECT 1 FROM dbo.Docente dc INNER JOIN dbo.Grupo g ON g.docente = dc.id AND g.periodoAcademico = @idPeriodoDefecto
                        WHERE dc.usuario = @idUsuarioDefecto))
            SET @enAmbito = 1;

        IF @enAmbito = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PER_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @estadoResultado = 0;
        END
    END

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT
        id                 = r.id,
        idPeriodoAcademico = r.idPeriodoAcademico,
        fecha              = r.fecha,
        motivo             = r.motivo,
        sesionesCanceladas = r.sesionesCanceladas,
        estaAplicado       = r.estaAplicado,
        puedeRetirarse     = CAST(IIF(r.estaAplicado = 0 AND @fechaCierreUtc IS NULL, 1, 0) AS BIT),
        fechaCreacionUtc   = r.fechaCreacionUtc,
        totalRegistros     = COUNT(1) OVER()
    FROM dbo.uv_periodo_receso_academico r
    WHERE r.idPeriodoAcademico = @idPeriodoDefecto
    ORDER BY r.fecha, r.id;
END;
GO
