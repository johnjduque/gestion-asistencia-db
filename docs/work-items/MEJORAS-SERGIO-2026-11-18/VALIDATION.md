# MEJORAS-SERGIO-2026-11-18 — Validación de la base de datos

Fecha: 2026-11-18. Equipo local (Windows 10, 8 GB de RAM, Docker Desktop). Rama `feat/mejoras-sergio-2026-11-18`.
Contenedor desechable SQL Server 2022 (`SQL_Latin1_General_CP1_CI_AS`), con una contraseña aleatoria que no se imprimió. No se tocó
`sql_server_asistencias`.

## Compuerta completa (despliegue limpio)

| Paso | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | OK |
| `scripts/lb004d-manifest.ps1 -Mode Verify` | OK |
| `scripts/generar-catalogo-mensajes.ps1 -Check` | OK (487 códigos) |
| `deploy_schema.ps1` | OK |
| `migrar.ps1 -Modo Detectar` / `-Modo Baseline` / `-Modo Estado` | OK (la 56 sale detectada) |
| `test_summary.ps1` | **955 PASSED / 8 FAILED / 7 CRITICAL_MISSING**: todos los fallos son del entorno (ver abajo) |

Los fallos y faltantes del `test_summary` fueron:

- `CULM001_B2_TOM_08_CIERRE_CONCURRENTE` y `CULM001_C_RUNNER`: Docker Desktop respondió `500 Internal Server Error` a `docker exec`.
- `VAL_MDET_RUNNER` (y por eso faltan `VAL_MDET_03..08`): el `tar` de Git interpretó `C:` como host remoto.

## Re-ejecución de esos casos

| Caso | Resultado |
|---|---|
| `CULM001_B2_TOM_08_CIERRE_CONCURRENTE` | **PASA** |
| `CULM001_B2_TOM_10_CIERRE_AUTOMATICO_CONCURRENTE`, `MIG_01..05`, `MIG_03_COLAPSO_*` | PASAN |
| `CULM001_C` (`CULM001_C_MIG_19_UP_DOWN_UP`) | **PASA** (el runner ya no recibió el 500) |
| `test_val_migrar.ps1` (`VAL_F1212_01..07`) | 7/7 PASAN en la primera re-ejecución. En la segunda, Docker Desktop volvió a responder 500, esta vez a `docker cp`. |
| Migración 56 en la base desplegada: `up` (sin cambios), `down`, `down` (idempotente), `up`, `up` (idempotente) | exit 0 en los 5 pasos |
| `VAL_MDET_01_MARCADORES_COMPLETOS`, `VAL_MDET_02_DESPLIEGUE_LIMPIO_TODAS` | PASAN |
| `VAL_MDET_03..08` | **No se ejecutaron en el equipo local; quedan para el CI.** Cada caso hace un despliegue completo de unos 45 min en este equipo. El CI de GitHub corre la compuerta completa de BD en el PR antes de unir. |

`CULM001_B2_SEG_02_FIXTURES_REPETIBLES` pasó en la compuerta completa. En la re-ejecución falló con
`Invalid object name 'uv_tipo_vinculacion'` en `uv_docente_programa`. La causa: se reutilizó el contenedor de una re-ejecución
anterior que se interrumpió después de aplicar `down` y luego `up` de la 56 sin volver a correr `deploy_schema.ps1`. Así se
comporta la 56, y lo dice su cabecera (igual que la 48 y la 49): entre el `up` y el despliegue, las vistas y los SP viejos quedan
inválidos, por eso el despliegue es obligatorio (`docs/runbooks/ACTUALIZAR_BD_LOCAL_EXISTENTE.md`). No es una regresión del
esquema.

## Correcciones de la revisión independiente (2026-11-18)

- `generar_datos_prueba.py` vuelve a CRLF (como en develop): el diff contra `origin/develop` queda en las 6 líneas reales.
- Migración 56: regla cruzada `parametroDebeSerMenorQue` que apunte al parámetro retirado. Verificado en un contenedor SQL Server
  2022 desechable (`SQL_Latin1_General_CP1_CI_AS`), dentro de una transacción revertida: `down`, fila de edición del parámetro
  retirado + 2 filas de otros parámetros con la regla cruzada hacia él, `up` (las 2 filas se conservan con la regla en `NULL`),
  `up` repetido (idempotente) y `ROLLBACK`. Con el `up` anterior el mismo caso fallaba con el error 547 de
  `FK_CatalogoParametroEdicion_MenorQue`. `test_migracion_docente_programa.sql`: PASA.

## Pendiente

- `VAL_MDET_03..08` en el CI del PR.
