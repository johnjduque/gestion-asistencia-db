-- ============================================================================
-- Exporta las versiones de plantilla de notificacion PERSONALIZADAS de Asistencias como JSON compatible con el Servicio de Notificaciones
-- (Complementos/Notificaciones/contrato/openapi-notificaciones.yaml, POST /api/v1/plantillas/{tipo}/versiones, esquema NuevaVersion).
--
-- USO UNICO: ejecutelo UNA vez, ANTES de aplicar la migracion 71 (migrations/71_p3_f5_notificaciones_servicio_up.sql), en cada entorno con
-- datos reales. La migracion elimina PlantillaNotificacion y PlantillaNotificacionMarcador y con ellas el historial de versiones.
--   sqlcmd -S <servidor> -d gestionasistenciadb -U <usuario> -P <clave> -C -f 65001 -y 0 -i scripts/exportar-plantillas-notificaciones.sql -o plantillas-personalizadas.txt
-- (-y 0 evita que sqlcmd parta el JSON en lineas; -f 65001 conserva las tildes; -y 0 no se combina con -h -1 ni con -W, asi que el archivo trae dos lineas
-- de encabezado, el nombre de la columna y los guiones: la tercera linea es el JSON.) Solo lee: no modifica nada. El script no ejecuta USE: la base la fija -d.
-- Para dejar solo el JSON: (Get-Content plantillas-personalizadas.txt -Encoding UTF8 | Select-Object -Skip 2 | Select-Object -First 1) | Set-Content plantillas-personalizadas.json -Encoding UTF8
--
-- Que exporta: toda version con version > 1 o creada por una persona (creadoPor no nulo). La version 1 de fabrica no se exporta: el servicio
-- ya la trae sembrada. Cada elemento del arreglo es una llamada:
--   ruta                      ruta relativa de POST (el tipo ya esta sustituido).
--   solicitud                 cuerpo NuevaVersion: { idioma, asunto, cuerpo, creadoPor } (creadoPor = id de usuario de Asistencias, en texto).
--   versionOrigen             numero de version que tenia en Asistencias.
--   activaEnOrigen            true si era la version vigente del tipo e idioma en Asistencias.
--   creadoEnOrigen            instante UTC de creacion en Asistencias (informativo; el servicio pone el suyo).
-- Orden de importacion: tal como salen (tipo, idioma, version ascendente). Cada POST crea la version siguiente del servicio y la deja activa;
-- si la version activa en origen no es la ultima del tipo e idioma, active despues
-- POST /api/v1/plantillas/{tipo}/versiones/{n}/activacion?idioma=<idioma> con la numeracion que devolvio el servicio. La numeracion del servicio
-- solo coincide con versionOrigen si el origen no tiene huecos; use versionOrigen para identificar cual es cual, no como numero de destino.
-- ============================================================================
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'dbo.PlantillaNotificacion', N'U') IS NULL
    THROW 71001, 'exportar-plantillas-notificaciones: dbo.PlantillaNotificacion ya no existe (la migracion 71 ya se aplico); no hay nada que exportar.', 1;
GO
SELECT (
    SELECT
        p.tipo                                                    AS tipo,
        p.idioma                                                  AS idioma,
        CONCAT(N'/api/v1/plantillas/', p.tipo, N'/versiones')     AS ruta,
        p.version                                                 AS versionOrigen,
        p.activa                                                  AS activaEnOrigen,
        CONVERT(VARCHAR(33), p.creadoEn, 126) + 'Z'               AS creadoEnOrigen,
        p.idioma                                                  AS [solicitud.idioma],
        p.asunto                                                  AS [solicitud.asunto],
        p.cuerpo                                                  AS [solicitud.cuerpo],
        CONVERT(VARCHAR(36), p.creadoPor)                         AS [solicitud.creadoPor]
    FROM dbo.PlantillaNotificacion AS p
    WHERE p.version > 1 OR p.creadoPor IS NOT NULL
    ORDER BY p.tipo, p.idioma, p.version
    FOR JSON PATH, INCLUDE_NULL_VALUES
) AS plantillasPersonalizadas;
GO
