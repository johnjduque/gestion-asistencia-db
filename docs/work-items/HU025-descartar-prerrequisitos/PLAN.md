---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-29
---

# PLAN — HU025: descartar prerrequisitos y correquisitos

## Decisión

John (2026-10-29): **los prerrequisitos y correquisitos no existen y no están incorporados en la aplicación.**
- La HU025 (en `HU-CATALOG` de Infra, "Consultar prerrequisitos y correquisitos") se **descarta**.
- Se elimina todo lo referente en BD, backend y frontend. No se crea ninguna tabla.

## Cambio en BD (rama `chore/HU025-descartar-prerrequisitos`)

1. **Se elimina `schema/stored-procedures/usp_validar_prerrequisitos_asignatura_estudiante_interno.sql`.**
   - Era un stub que siempre aprobaba.
   - No tenía llamadores, pruebas ni permisos, y no estaba en ningún manifiesto de congelamiento.
2. **`migrations/07_hu025_descartar_prerrequisitos_up.sql`:** borra el SP en las bases ya desplegadas, porque `deploy_schema.ps1` crea objetos pero no elimina los que salen de `schema/`. Es idempotente.
   - El `_down` restaura el stub, solo para revertir el commit.
3. **Documentación sin menciones a prerrequisitos:**
   - `backend_specification.md`: agregar asignatura a semestre e inscripción de estudiante;
   - `transaccion-procedimiento.md`: registro de estudiante, lista de internos e inventario (162 SP: 102 públicos y 60 internos);
   - `work-items/INT-HU-01…/PLAN.md`;
   - `reportes/reporte_analisis_arquitectura_rbac.html`.
   - El `README.md` conserva "Prerrequisitos" porque se refiere a lo que hay que instalar (Docker), no a asignaturas.

No cambian las tablas, los SP públicos, las pruebas, los permisos ni los manifiestos.

## Cambios relacionados en los otros repos

- **Backend:** se elimina el endpoint `GET /api/v1/estudiante/materias/{materiaId}/prerrequisitos` (respondía 501), su prueba, su entrada en `access-catalog.json` y las filas de las matrices.
- **Frontend:**
  - se elimina el modal de prerrequisitos del estudiante y el botón que lo abría;
  - se elimina la sección de prerrequisitos del formulario de asignatura del coordinador (el backend nunca la guardaba) y su visualización en la malla y el listado;
  - se eliminan también el campo `prerrequisitos` del modelo, los mocks y las pruebas.

## Pendiente para el equipo (no se toca desde aquí)

- **Infra (`docs/user-stories/HU-CATALOG.md`):** marcar la HU025 como descartada.
- **José Alejandro (PDP):** retirar del aprovisionamiento la ruta `GET /api/v1/estudiante/materias/{materiaId}/prerrequisitos`.

## Validación

Réplica del job `DB Quality Gate CI/CD` sobre SQL Server 2022 limpio (2026-10-29): `TOTAL_EXECUTED=386`, `FAILED=0`, `CRITICAL_MISSING=0`, `DB GATE PASS`; `freeze-manifest -Mode Verify` OK. El esquema despliega sin el stub. La migración 07 solo hace `DROP PROCEDURE IF EXISTS` (idempotente).
