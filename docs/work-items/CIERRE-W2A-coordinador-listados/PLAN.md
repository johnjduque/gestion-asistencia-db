---
status: active
type: work-item
scope: database
last-reviewed: 2026-11-16
---

# CIERRE-W2A (BD): listados del coordinador resueltos en la base

Contrato completo en `docs/work-items/CIERRE-W2A-coordinador-listados/CONTRACT.md` del repositorio de backend.

| Objeto | Cambio |
|---|---|
| `usp_consultar_asignaturas_coordinador_paginado` | Suma al final `@codigoCaracter NVARCHAR(50) = NULL`: filtra por el codigo del caracter de la asignatura en el plan (`OBL`, `OPT`). Vacio o NULL = sin filtro; `totalRegistros` cuenta con el filtro. |
| `usp_consultar_asignaturas_ambito_consolidado` (nuevo) | Asignaturas (`id`, `nombre`) con grupos en el ambito del ejecutor (`uv_auth_grupo`: coordinador, decano o administrador) y, opcionalmente, de un periodo. |
| `usp_consultar_docentes_ambito_consolidado` (nuevo) | Docentes titulares (`id`, `nombre`) con grupos en el ambito del ejecutor y, opcionalmente, de un periodo. |
| `uv_periodo_academico` | Suma al final `estado` (`PLANEACION`, `ACTIVO`, `CERRADO`) con la fecha local institucional (`TIEMPO/ZONA_HORARIA_SQLSERVER`), igual que `uv_grupo.grupoEstaHablitado`. |

Permisos: `schema/security/rol_asistencias_runtime_w2a_coordinador_listados.sql` (los dos SP nuevos).
Pruebas: `test/test_w2a_coordinador_listados.sql` (`W2A_*`), registrada en `test_suite.sql` y `test_summary.ps1`. Los dos SP nuevos
se agregaron a las excepciones de `READ_QUERY_RESULTSET` de `test/test_contract_closure.sql`.
Sin migracion: son objetos `CREATE OR ALTER` sin datos nuevos (como los cambios de SP recientes).
