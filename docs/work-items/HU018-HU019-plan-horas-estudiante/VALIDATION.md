---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-10
---

# VALIDATION — HU018-HU019: plan de estudios y horas programadas del estudiante

| Comando | Resultado |
|---|---|
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre un contenedor SQL Server 2022 limpio (mismo orden que el job `DB Quality Gate CI/CD`), 2026-11-10 | `TOTAL_EXPECTED=530`, `TOTAL_EXECUTED=708`, `PASSED=707`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `SQL_ERROR_COUNT=0`, `DB GATE PASS`. Pasan los 9 casos nuevos: `HU018_PLAN_ESTRUCTURA_ORDEN`, `HU018_PLAN_EXCLUSIONES`, `HU018_PLAN_CURSANDO`, `HU018_PLAN_PRIVACIDAD`, `HU018_PLAN_COLUMNAS`, `HU019_HORAS_PROGRAMADAS`, `HU019_HORAS_VALIDACIONES`, `HU018_HU019_SEG_01` y `HU018_HU019_MIG_UP_DOWN_UP` |
| La misma compuerta en un contenedor limpio, después de unir `develop` (migraciones 30, 31 y 32 de DEC-065) y renumerar esta migración de la 30 a la 33, 2026-11-10 | `TOTAL_EXPECTED=562`, `TOTAL_EXECUTED=740`, `PASSED=739`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `SQL_ERROR_COUNT=0`, `DB GATE PASS` |
| `scripts/freeze-manifest.ps1 -Mode Verify` (dentro del gate) | `GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED`: ningún objeto congelado cambia |
| `PUBLIC_CANONICAL_RESULTSET` y `PUBLIC_SP_INVENTORY` (dentro del gate) | Pasan; 195 SP públicos en el repositorio |
| Migración `33_hu018_hu019_plan_horas_estudiante_up.sql` en la BD local de John | Aplicada el 2026-11-10: los dos SP existen con `EXECUTE` para `rol_asistencias_runtime` |
| `test/test_hu018_hu019_plan_horas_estudiante.sql` y `test/test_hu018_hu019.ps1` en la BD local | Los 7 casos funcionales y la migración up → down → up pasan; la transacción se revierte y no quedan residuos |
| GitHub Actions `DB Quality Gate CI/CD` | Pendiente: la rama está en el árbol de trabajo local, sin commit ni push |

## Comprobación con los datos locales

Para el estudiante de prueba (Carlos Zapata), antes de crear la sesión de la recertificación:

- `usp_consultar_plan_estudio_estudiante`: 1 fila. Ingenieria de Sistemas, plan 2024, semestre 8, ARQ-402 Arquitectura de Software, 3 créditos, obligatoria, `cursando = 1` en "Grupo 001 - Arq Software".
- `usp_consultar_horas_programadas_estudiante`: 5 sesiones y 8.97 horas programadas (las dos sesiones canceladas no cuentan). El resumen por horas daba 4.97 horas dictadas en 3 sesiones: las dictadas son un subconjunto de las programadas.

## Incidencias corregidas durante la validación

1. **`SET XACT_ABORT ON` en un SP de lectura.** La primera versión lo traía, como otros SP de consulta de CULM-001. El rechazo por ejecutor nulo (THROW 51000) dejaba sin poder confirmar la transacción de quien llama, y la prueba fallaba al escribir después (Msg 3930). Se quitó: los dos SP son de solo lectura.
2. **`QUOTED_IDENTIFIER`.** La prueba inserta en `SesionCancelacion`, que tiene un índice filtrado. Sin `SET QUOTED_IDENTIFIER ON` en su propio lote, `sqlcmd` rechaza el `INSERT` (Msg 1934). Se agregó la cabecera que usan las pruebas de CULM-001 B.2.
3. **Intercalación en la prueba de migración.** En la BD local, la intercalación de la base no es la de `tempdb`, y el cruce de la tabla temporal con `sys.objects` fallaba (Msg 468). Se agregó `COLLATE DATABASE_DEFAULT`. En el contenedor limpio no se nota.

## Desviación

Las pruebas se escribieron junto con el código, sin un commit RED separado.

## Limitación

La revisión en pantalla está en el `VALIDATION.md` del work item homónimo del backend.
