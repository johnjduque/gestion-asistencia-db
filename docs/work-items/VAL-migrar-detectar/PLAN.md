---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-13
---

# VAL-migrar-detectar (BD) - PLAN

Fecha: 2026-11-13. Rama `fix/VAL-migrar-detectar`, creada desde `origin/develop` (5c4f30c). Rama del mismo nombre en Infra.

## Problema

Una base local con datos de prueba (la de José Alejandro, contenedor `sql_server_asistencias`) quedó a medias: tiene parte de los
cambios, le faltan los objetos de la migración 17 en adelante (entre ellos HU018/HU019 en la 33 y las tomas por puntos de control en
la 37 y 38) y no tiene `dbo.MigracionAplicada`, así que `migrar.ps1 -Modo Estado` muestra 05..42 como pendientes.

- `-Modo Baseline` marcaría todo como aplicado (se perderían las que faltan).
- `-Modo Aplicar` desde cero re-ejecutaría 05..16; varias tienen `THROW` de precondición.
- No hay acceso a esa instancia: el procedimiento lo ejecuta él.

## Cambios

| Cambio | Archivo |
| :--- | :--- |
| `-Modo Detectar` (solo lectura): clasifica cada migración `APLICADA_DETECTADA` / `AUSENTE` / `PARCIAL` por marcadores; resumen con `contigua_hasta` | `scripts/migrar.ps1` |
| `-Modo Baseline -SoloDetectadas`: si no hay `PARCIAL`, crea el registro si falta y registra como `BASELINE` solo el tramo contiguo detectado; `-IncluirFueraDeOrden` y `-ReaplicarParciales` para decisiones humanas | `scripts/migrar.ps1` |
| `-HastaVersion` también limita `-Modo Aplicar`; con `-Database` distinta de la compartida, `Aplicar` ejecuta una copia de `migrations/` y `schema/` con el nombre de la base cambiado (pruebas) | `scripts/migrar.ps1` |
| Marcadores: 42 migraciones, 253 marcadores | `scripts/migrar-marcadores.json` |
| Prueba (8 casos, BD temporales) e ids en la compuerta | `test/test_val_migrar_detectar.ps1`, `test_summary.ps1` |
| CI: tras `deploy_schema.ps1`, `Detectar` debe dar `ausentes=0 parciales=0 sin_marcadores=0` | `.github/workflows/ci.yml` |
| Procedimiento para el compañero | `docs/runbooks/ACTUALIZAR_BD_LOCAL_EXISTENTE.md` |
| Manifiesto | `docs/contracts/DB_CULM001_D_POST_FREEZE_MANIFEST.sha256` (`migrar.ps1`, `migrar-marcadores.json`) |
| Infra: `reset-datos-prueba.ps1 -Mode Base` usa `migrar.ps1` en vez del rango fijo 13..28 | Repositorio Infra, `scripts/database/reset-datos-prueba.ps1` |

Sin migración nueva ni cambios en `schema/`.

## Cómo se eligieron los marcadores

1. Se leyó cada migración `up` (05..42) por lotes: DDL (tablas, columnas, índices, restricciones), módulos creados o alterados,
   `DROP` y semillas (`MERGE`/`INSERT`/`DELETE` en catálogos).
2. Para 17..42 se midió el efecto real: base con el `schema/` del commit `8f18b76` (develop justo antes de la 17), luego
   `migrar.ps1 -Modo Aplicar -HastaVersion N` una a una, con una foto del catálogo después de cada paso (tablas, columnas, índices,
   restricciones, hash de cada módulo, permisos y filas de los catálogos con `codigo`, parámetros y plantillas). El diff entre fotos
   consecutivas da exactamente lo que agrega o quita cada migración.
3. Se tomaron solo efectos que **siguen** en develop (presentes en un despliegue limpio): por ejemplo no se usan las tablas
   `zz_archivo_*` ni `zz_reporte_*`, que solo crean las migraciones.
4. Se evaluaron los marcadores contra todas las fotos (estado 16, cada paso 17..42 y despliegue limpio): cada migración pasa de
   `AUSENTE` a `APLICADA_DETECTADA` exactamente en su paso y nunca sale `PARCIAL` (tabla en `VALIDATION.md`).

Tipos: `tabla`, `columna`, `indice`, `restriccion`, `objeto` (existe o no), `objeto` + `contiene` (texto de una línea de la
definición) y `tabla` + `donde` (fila de catálogo, predicado SQL). `existe: false` para retiros (07 hu025, 08 eliminar, 09, 11
catálogos, 13 solicitudes de ingreso, 18 columna `semestrePlanEstudio`, 26, 36 recuperación de clave, 39). Cada marcador se
evalúa con un `SELECT` propio; una fila cuya tabla o columna no existe cuenta como ausente (`TRY/CATCH` del lote dinámico). No usa
tablas temporales (no choca con una intercalación distinta en `tempdb`).

### Migraciones difíciles de detectar

- **Solo cambian módulos existentes**: 27 (cuatro SP de KPI por horas) y 38 (bandeja de reclamos con la toma). Se detectan por una
  línea que la migración agrega a la definición (`contiene`). 25 y 34 combinan objeto nuevo o semilla con una línea de definición.
  Si una migración futura reescribe esas líneas, la prueba `VAL_MDET_02` (despliegue limpio) y el paso de CI lo detectan y hay que
  ajustar el marcador.
- **20**: entró a develop (PR #97) antes que la 17 (PR #113); una base de esa época la tiene completa con 17..19 ausentes. Sale
  detectada `fuera_de_orden=1`.
- **36**: solo retira la 35, que casi ninguna base tuvo; en una base vieja sale detectada (`solo_retiro=1`) aunque nunca se aplicó.
- **Bases mantenidas con `deploy_schema.ps1`** (sin migraciones): `deploy_schema.ps1` crea tablas nuevas y módulos, pero no borra lo
  que una migración retira ni agrega columnas a tablas que ya existen. Un respaldo real de desarrollo del 2026-11-09 dio `PARCIAL` en
  05 (SP autónomo sin retirar), 13 y 14. De ahí `-ReaplicarParciales`.
- **40 (ROL-12)** y la parte de datos de otras migraciones (ámbito de cuentas semilla, backfills) no se usan como marcador: dependen
  de que existan filas semilla.

## Decisiones

- **Solo el tramo contiguo** se registra con `-SoloDetectadas`. Una detectada después de una ausente queda pendiente y `Aplicar` la
  re-ejecuta en su orden: así una migración posterior nunca queda registrada antes de una anterior que la pisaría (caso real: 17
  reescribe módulos de la 20). Las migraciones son idempotentes (en el ensayo se re-ejecutaron la 20 y la 36 sin error; en el
  respaldo del 2026-11-09 se ejecutaron las 42). `-IncluirFueraDeOrden` existe para quien decida lo contrario.
- **`PARCIAL` detiene** `-SoloDetectadas` sin crear ni escribir el registro. `-ReaplicarParciales` es la salida explícita.
- **`deploy_schema.ps1` después de `Aplicar` es necesario**, no opcional: las migraciones dejan a `deploy_schema.ps1` parte de los SP,
  semillas y permisos (lo dicen sus encabezados). En el ensayo faltaban 6 SP, mensajes `ALR_*`/`RCN_*`, parámetros, plantillas y
  permisos, y 2 SP tenían texto viejo; tras `deploy_schema.ps1` la base quedó igual a un despliegue limpio. Riesgo sobre datos:
  `schema/seed/03_parametro.sql` repone el valor de fábrica de los parámetros base y las semillas 11..14 reponen las filas de
  demostración con id fijo; el runbook guarda y repone los parámetros propios.
- **Orden de `Aplicar`**: ya era por versión y nombre sobre la lista de pendientes; una pendiente anterior a una registrada se aplica
  igual en su orden (`VAL_MDET_06`). No hubo que cambiarlo.
