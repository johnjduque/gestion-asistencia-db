---
status: active
type: work-item
scope: database
last-reviewed: 2026-11-16
---

# CIERRE-W1B (BD): directorios de personas con ámbito y paginación

Contrato completo en `docs/work-items/CIERRE-W1B-directorios-ambito/CONTRACT.md` del repositorio de backend.

| Objeto | Cambio |
|---|---|
| `usp_validar_permiso_rbac_usuario_interno` | El perfil se compara por código exacto o nombre completo exacto (sin `LIKE`, sin distinguir mayúsculas) y se ignoran los elementos vacíos de la lista. Todos los llamadores pasan el nombre del rol (`'DOCENTE'`, …) salvo `usp_resolver_revision_cancelacion` (código); ninguno cambia. |
| `usp_consultar_coordinadores_facultad_paginado` (nuevo) | Coordinadores de la facultad del decano con `busqueda`, `estaActivo`, `sinPrograma` y `OFFSET/FETCH`. Permiso en `rol_asistencias_runtime_w1b_directorios.sql`. |
| `usp_consultar_docentes_facultad_paginado` | Suma al final `primerNombre`, `segundoNombre`, `primerApellido`, `segundoApellido`, `idTipoIdentificacion`, `codigoTipoIdentificacion`. |
| `usp_buscar_estudiantes_institucion_paginado` | Suma al final `primerNombre`, `segundoNombre`, `primerApellido`, `segundoApellido`. |
| `uv_decano_identidad`, `uv_decano` | Suman al final los cuatro campos de nombre. |

Pruebas: `test/test_w1b_directorios.sql` (`W1B_*`), registrada en `test_suite.sql` y `test_summary.ps1`. Se actualizaron las
tablas temporales `#docentes` y `#estudiantes` de `test/test_consultas_transversales_hu112_hu157.sql` a las columnas nuevas.
Sin migración: son objetos `CREATE OR ALTER` sin datos nuevos (como los cambios de SP recientes).
