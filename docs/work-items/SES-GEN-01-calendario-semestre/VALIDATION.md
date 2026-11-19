# VALIDATION — SES-GEN-01

- `scripts/freeze-manifest.ps1 -Mode Verify`: `FREEZE_MANIFEST_OK`; actualizados los hashes `WORK_ITEM` existentes de `schema/seed/62_val_mensajes_aplicacion.sql` y `scripts/migrar-marcadores.json`.
- `scripts/generar-catalogo-mensajes.ps1 -Check`: `CATALOGO_MENSAJES_OK codigos=506`.
- `test_summary.ps1 -ParserSelfTestOnly`: diez casos del parser pasaron.
- `git diff --cached --check`: sin errores de whitespace antes del commit inicial.
- CI de PR #155 en `8e952b74`: bloqueado antes del despliegue porque esos dos hashes estaban desactualizados; el manifiesto fue corregido. Falta volver a ejecutar CI para validar SQL y pruebas de integración.
- CI de PR #155 en `59a83a6`: pasó el manifiesto, pero el despliegue detectó que `uv_asignatura` expone `idArea` e `idComponente`; la comparación en `usp_actualizar_asignatura` se ajustó y falta repetir CI.
- CI de PR #155 en `07f1475`: el manifiesto, despliegue, registro de migración y `SES_GEN_01_MIG_UP_DOWN_UP` pasaron. La suite mostró que el grant genérico de vistas corría después de la revocación específica; el script de SES-GEN-01 se renombró con prefijo `zz_` para aplicarse al final. `VAL_MDET_07` también reveló que la vista y el SP preview se despliegan desde `schema/` (como fija este contrato), no desde la migración 59; se retiraron esos dos marcadores para que el detector mida los efectos realmente propiedad del `up`.
- CI de PR #155 en `abb8c44`: pasaron manifiesto, despliegue, registro, permisos runtime, `SES_GEN_01_MIG_UP_DOWN_UP` y los ocho casos de `VAL_MDET`. La suite expuso que `test_hu074_estado_asignatura.sql` no contemplaba la nueva columna `horasSemanales` del resultset de la malla; se agregó a la tabla receptora en el orden de salida del SP.

Las pruebas SQL de integración se ejecutan en el SQL Server desechable del flujo CI; no deben dirigirse a la instancia compartida `sql_server_asistencias`.
