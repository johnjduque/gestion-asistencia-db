---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-13
---

# VAL-oleada3-mensajes (BD) - VALIDATION

Fecha: 2026-11-13. Contenedor local `sql_server_asistencias`, base `gestionasistenciadb` (solo se aplicó la migración 41, que
agrega filas de catálogo; la ruta de los archivos fue `/tmp/val41` dentro del contenedor, `sqlcmd -f 65001`).

| Prueba | Resultado |
| :--- | :--- |
| `test_val_oleada3_mensajes_aplicacion.sql` antes de la migración 41 | Falla en `VAL_MSG05_01` (rojo esperado) |
| Migración 41 UP dos veces seguidas | OK, idempotente (107 filas por catálogo cada vez) |
| Misma prueba después | 3 de 3 `TEST_PASS` (MSG05_01, MSG05_02, TRANCOUNT) |
| Migración 41 DOWN + prueba | Falla en `VAL_MSG05_01` (rojo esperado) |
| Semilla `62_val_mensajes_aplicacion.sql` + prueba | 3 de 3 `TEST_PASS` |
| Texto con tildes en la BD | `VAL_APP_039` = "El tamaño de página debe estar entre 1 y {}.", `NOF_APP_011` y `DIS_APP_001` con tildes correctas |
| `scripts/generar-catalogo-mensajes.ps1 -Check` | `CATALOGO_MENSAJES_OK codigos=398` |
| `freeze-manifest.ps1 -Mode Verify` | `FREEZE_MANIFEST_OK entries=10 post_freeze_superseded=4 post_freeze_work_item=11 culm001_d=80` |
| `lb004d-manifest.ps1 -Mode Verify` | `LB004D_MANIFEST_OK entries=9` |
| `build-message-catalog.py --check` (Infra) contra el fixture del backend | `OK ... coincide con los seeds (398 mensajes)` |
| Compuerta de BD completa (`test_summary.ps1`) | No corrida por el agente (la corre John) |
