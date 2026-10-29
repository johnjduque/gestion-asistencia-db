---
status: active
type: work-item
scope: db-docs
owner: db-team
last-reviewed: 2026-10-29
---

# PLAN — REC5: catálogo de mensajes y documentación de SP

## Hallazgo (auditoría BD 2026-10-28, severidad media)

- `docs/catalogos/catalogo-mensajes.md` era una exportación antigua de Excel con códigos de otro formato (`GEN_USU_EXI_00001`). No contenía ninguno de los códigos reales sembrados en `schema/seed`, aunque AGENTS.md y CLAUDE.md lo señalan como la fuente para consultar mensajes.
- `especificacion_sp_endpoints.md` cubría 49 de 102 SP públicos.
- 48 públicos y 30 internos no tenían ficha en los documentos de arquitectura.
- `transaccion-procedimiento.md` declaraba 57 SP, 55 vistas y 15 funciones.

## Cambio (solo documentación y un script; no toca `schema/` ni las pruebas)

1. **`scripts/generar-catalogo-mensajes.ps1`**
   - Regenera `docs/catalogos/catalogo-mensajes.md` a partir de los `MERGE` sobre `CatalogoMensajeUsuario` y `CatalogoMensajeTecnico` de `schema/seed/*.sql`.
   - Para cada código muestra el tipo, la severidad, el mensaje de usuario, el mensaje técnico y el seed de origen, agrupados por prefijo.
   - `-Check` termina con exit 1 si el documento no coincide con los seeds; está listo para agregarse como paso del CI si el equipo lo aprueba.
   - Resultado: **131 códigos**.
2. **`especificacion_sp_endpoints.md`** (Addendum REC5)
   - Agrega los 53 públicos que faltaban, con módulo, endpoint, rol, parámetros y propósito.
   - Endpoints trazados sobre el backend `develop`: `*JpaRepository` → puerto → caso de uso → controller.
   - Los 11 SP legacy sin consumidor ni grant se listan aparte.
3. **`DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md` y `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md`** (Addendum REC5)
   - Índice de los 48 públicos y los 30 internos sin ficha, con parámetros y propósito tomado del comentario de cabecera del SP.
4. **`transaccion-procedimiento.md`**
   - Inventario vigente: 162 SP, 65 vistas, 17 funciones.
   - Referencias a los addendums y al generador del catálogo.
5. **`CLAUDE.md`**
   - Comando del generador y su modo `-Check`.

## Resultado

La auditoría automática se volvió a ejecutar sobre esta rama. Cobertura documental de SP:

| Regla | Antes | Después |
|---|---|---|
| D1 Internos en la documentación de arquitectura | 30/60 | 61/61 (con el interno de REC2) |
| D2 Públicos en PUBLICOS/ORQUESTADORES/transaccion-procedimiento | 54/102 | 102/102 |
| D3 Públicos en `especificacion_sp_endpoints.md` | 49/102 | 102/102 |
| D4 Públicos en algún documento o work item | 62/102 | 102/102 |

## Pendientes fuera de alcance

- 6 vistas siguen sin documentación (D5: 59/65).
- Agregar `generar-catalogo-mensajes.ps1 -Check` al workflow `DB Quality Gate`. Requiere aprobación porque cambia el CI compartido.
- Se integró `origin/develop` con REC2 (#61). El inventario quedó en 163 SP (61 internos) y `transaccion-procedimiento.md` ya está actualizado. La ficha del interno nuevo está en el addendum REC2 de `DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md`; al integrar se conservaron las dos secciones.

## Validación

- `./scripts/generar-catalogo-mensajes.ps1 -Check`: `CATALOGO_MENSAJES_OK codigos=131`.
- No hay cambios en `schema/` ni en `test/`.
- CI de BD de control sobre la rama antes de integrar develop: `TOTAL_EXECUTED=378`, `FAILED=0`, `DB GATE PASS`.
- Después de integrar `origin/develop` (#61) solo se resolvió un conflicto de documentación. `schema/` y `test/` quedan idénticos a `develop`, que ya pasó su DB Quality Gate en GitHub.
