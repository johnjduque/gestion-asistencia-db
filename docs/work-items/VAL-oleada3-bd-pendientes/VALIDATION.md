---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-13
---

# VAL-oleada3-bd-pendientes (BD) - VALIDATION

Fecha: 2026-11-13. Rama `fix/VAL-oleada3-bd-pendientes` sobre `origin/develop` 86dc810. Sin build de Maven en paralelo.

## PRU-05: resumen de la compuerta de BD

Corrida sobre una instancia SQL Server 2022 Developer limpia y temporal (contenedor desechable, sin puerto publicado, clave
generada en la corrida y nunca impresa), en el mismo orden que la CI: `freeze-manifest.ps1 -Mode Verify`,
`deploy_schema.ps1`, `migrar.ps1 -Modo Baseline` y `-Modo Estado`, `prepare_lb004d_fixture.ps1`, `test_summary.ps1`,
`cleanup_lb004d_fixture.ps1`. El contenedor se borró al terminar.

| Dato | Valor |
| :--- | :--- |
| Inicio / fin | 2026-11-13 10:25:55 / 11:21:56 (UTC-5) |
| Commit base | `origin/develop` 86dc810 más los cambios de esta rama (el commit que los registra es el de este documento) |
| `deploy_schema.ps1` | rc 0 |
| `migrar.ps1 -Modo Baseline` / `-Modo Estado` | rc 0 / rc 0: `total=40 registradas=40 pendientes=0 deriva=0` |
| `TOTAL_EXPECTED` (ids críticos) | 616 |
| `TOTAL_EXECUTED` | 794 |
| `PASSED` | 793 |
| `FAILED` | 0 |
| `SKIPPED` / `ALLOWED_SKIPPED` | 1 / 1 (`XACT_STATE_MINUS_ONE_RUNTIME`, el único permitido) |
| `CRITICAL_MISSING` | 0 |
| `SQLCMD_EXIT_CODE` / `SQL_ERROR_COUNT` / `UNAUTHORIZED_SKIPS` | 0 / 0 / 0 |
| `@@TRANCOUNT` | 0 |
| Resultado | `DB GATE PASS`, rc 0 |
| Ids nuevos de esta rama | 18 de 18 `TEST_PASS` (6 PRU-14, 5 OBS-03, 7 F12-12) |
| `NO_HARDCODED_DB_PASSWORD` | pasa (incluye los archivos nuevos) |

Antes se corrió la compuerta contra la BD compartida de desarrollo (`sql_server_asistencias`) y no sirve como evidencia:
falla por estado ajeno a esta rama. Tiene un procedimiento viejo que ya no está en el repo y no compila
(`usp_consultar_asignaturas_paginado`; 221 SP públicos en la instancia frente a 203 en el repo), reclamos por toma reales
que hacen que el down de la migración 37 se niegue con 50037 (lo usan varias pruebas up/down/up) y una alerta que choca con
el fixture de la migración 19. No se tocó nada de eso; queda para que John decida si limpia o recrea esa base.

## Pruebas por ítem

| Prueba | Resultado |
| :--- | :--- |
| `test/test_val_umbral_horas_bordes.sql` contra la BD de desarrollo y en la compuerta limpia | 6 de 6 `TEST_PASS` |
| `test/test_val_obs03_id_correlacion.sql` contra la BD de desarrollo y en la compuerta limpia | 5 de 5 `TEST_PASS` |
| OBS-03 en rojo: un procedimiento `dbo` nuevo sin `@idCorrelacion`, creado dentro de una transacción revertida | aparece en la consulta de `VAL_OBS03_01` (la compuerta fallaría) |
| OBS-03: detección de escritura con `sys.dm_sql_referenced_entities` sobre dos núcleos mutantes conocidos | 2 y 5 tablas con `is_updated = 1` |
| `test/test_val_migrar.ps1` directo y en la compuerta limpia (BD temporal `qa_migrar_<tag>`, borrada al final) | 7 de 7 `TEST_PASS` |
| Primera versión de `test_val_migrar.ps1` | 6 fallos por leer `Changed database context` en las consultas; se corrigió la prueba (`-d` en vez de `USE`), no la tarea |
| `migrar.ps1 -Modo Baseline -HastaVersion 40` y `-Modo Estado` sobre la BD de desarrollo | 40 registradas como BASELINE; `pendientes=0 deriva=0` (la tabla la creó `deploy_schema.ps1`) |
| `freeze-manifest.ps1 -Mode Verify` / `lb004d-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK ... culm001_d=79` / `LB004D_MANIFEST_OK entries=9` |
| `rhysd/actionlint:1.7.12` sobre `.github/workflows/ci.yml` (paso nuevo de línea base) | 0 hallazgos |
| Workflow en GitHub | No ejecutado (sin push) |

## Cambios en la BD de desarrollo

- `deploy_schema.ps1` de esta rama: crea `dbo.MigracionAplicada` y vuelve a aplicar los objetos (idempotente).
- `migrar.ps1 -Modo Baseline -HastaVersion 40`: 40 filas `BASELINE` en `dbo.MigracionAplicada`. Si en esa base ya se aplicó
  la migración 41 de `fix/VAL-oleada3-mensajes-catalogo`, al unir esa rama la 41 aparecerá como `PENDIENTE`; se registra con
  `-Modo Baseline -HastaVersion 41` o se reaplica con `-Modo Aplicar` (es idempotente).
- Ninguna migración ejecutada contra la BD de desarrollo.
