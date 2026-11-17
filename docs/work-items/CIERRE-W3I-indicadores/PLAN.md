---
status: active
type: work-item
scope: database
last-reviewed: 2026-11-16
---

# CIERRE-W3I (BD): indicadores, aforo y nivel de permanencia resueltos en la base

Contrato completo en `docs/work-items/CIERRE-W3I-indicadores/CONTRACT.md` del repositorio de backend.

| Objeto | Cambio |
|---|---|
| `usp_consultar_kpis_coordinador` | Columnas nuevas al final: `totalDocentes` (vinculos activos del programa, sin repetir), `gruposActivos`, `cupoTotal`, `matriculadosActivos`, `tasaAforo` (grupos habilitados del programa en el periodo resuelto) y `estudiantesRegistrados` (padron del programa). |
| `usp_consultar_kpis_decano` | Columnas nuevas al final: `totalCoordinadores` (activos) y `totalDocentes` (docentes con vinculo activo en algun programa de la facultad, una sola vez). |
| `usp_consultar_kpis_institucion` | Columnas nuevas al final: `totalDecanos`, `decanosActivos` y `facultadesActivas`. |
| `usp_consultar_resumen_grupos_docente` (nuevo) | Una fila con los totales de los grupos habilitados del docente titular: grupos, estudiantes activos, cupo y tasa de ocupacion. |
| `usp_consultar_consolidado_asistencia_grupos_paginado` | Columna nueva al final `codigoPermanencia` (REGULAR/RIESGO/PERDIDA) del % de inasistencia del grupo con `ufn_clasificar_permanencia`. |
| `usp_consultar_revisiones_cancelacion_{coordinador,decano,docente}_paginado`, `usp_consultar_alertas_estudiante` | Columna nueva al final `codigoPermanenciaActual` (nivel vigente del estudiante en el grupo). |

Ambito: dentro de cada SP (coordinador su programa, decano su facultad, administrador su institucion, docente sus grupos).
Permisos: `schema/security/rol_asistencias_runtime_w3i_indicadores.sql` (solo el SP nuevo; los demas ya tenian permiso).
Pruebas: `test/test_w3i_indicadores.sql` (`W3I_*`), registrada en `test_suite.sql` y `test_summary.ps1`. Las plantillas temporales de las pruebas que
leen estos resultsets con `INSERT ... EXEC` ganaron las columnas nuevas al final (cambio formal de forma, sin tocar ninguna asercion): `test_usp_consultar_kpis_*`,
`test_culm001_b1_sesion_cancelada`, `test_culm001_b2_horas`, `test_culm001_c_alertas`, `test_culm001_c_revisiones`, `test_culm001_d8_kpis_horas` y
`test_consolidado_auditoria_catalogos`. El SP nuevo se agrego a las excepciones de `test/test_contract_closure.sql` y al chequeo de `test/test_public_objects.sql`.
Sin migracion: son objetos `CREATE OR ALTER` sin datos nuevos.
