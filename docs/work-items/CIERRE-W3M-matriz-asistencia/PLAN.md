---
status: active
type: work-item
scope: database
last-reviewed: 2026-11-16
---

# CIERRE-W3M (BD): matriz de asistencia del grupo y resumen de sesiones resueltos en la base

Contrato completo en `docs/work-items/CIERRE-W3M-matriz-asistencia/CONTRACT.md` del repositorio de backend.

| Objeto | Cambio |
|---|---|
| `usp_consultar_matriz_asistencia_grupo_docente_paginado` (nuevo) | Pagina de matriculas del grupo (por nombre; `@busqueda` por nombre o documento) con una fila por sesion y el estado de la celda tal como lo define `uv_asistencia_sesion_horas` (DEC-066): `PRESENTE`, `PARCIAL`, `JUSTIFICADA`, `AUSENTE`, `SIN_REGISTRO`, `NO_DISPONIBLE`, mas `minutosAsistidos` y `minutosSesion`. `totalRegistros` cuenta estudiantes. |
| `usp_consultar_resumen_sesiones_grupo_docente` (nuevo) | Una fila por sesion con su estado temporal (`PROGRAMADA`, `EN_CURSO`, `EJECUTADA`, `CANCELADA`) y conteos (presentes, parciales, justificadas, ausentes, sin registro) sobre las matriculas activas, mas columnas del grupo: sesiones programadas, ejecutadas, canceladas, en curso, sesion en curso y proxima, estudiantes activos, en riesgo, promedio y umbrales de catalogo. |
| `usp_consultar_resumen_asistencia_grupo_docente_paginado` | Suma al final `@busqueda NVARCHAR(100) = NULL` (nombre o documento, `CHARINDEX`); el resultset no cambia y `totalRegistros` cuenta con el filtro. |

Ambito: los tres validan perfil DOCENTE y titularidad del grupo antes de leer filas (`SEC_001` / `SEC_002` / `ERR_GRUPO_NO_EXISTE`;
la matriz tambien `PAG_001`).
Permisos: `schema/security/rol_asistencias_runtime_w3m_matriz_asistencia.sql` (los dos SP nuevos).
Pruebas: `test/test_w3m_matriz_asistencia.sql` (`W3M_*`), registrada en `test_suite.sql` y `test_summary.ps1`. Los SP nuevos se agregaron a las
excepciones de `READ_QUERY_RESULTSET` de `test/test_contract_closure.sql` y al chequeo de permisos de `test/test_public_objects.sql`.
Sin migracion: son objetos `CREATE OR ALTER` sin datos nuevos.
