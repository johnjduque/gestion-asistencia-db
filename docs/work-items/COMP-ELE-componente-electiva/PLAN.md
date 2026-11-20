---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-19
---

# PLAN — COMP-ELE: componente de formación "electivas" (ELE)

## Identidad y objetivo

- **Decisión de John (2026-11-19):** las asignaturas pueden ser de tipo **Electiva**, además de básicas (BAS), institucionales (INS) y específicas (ESP).
- **Cambio:** fila nueva en `dbo.Componente`: `id = 9A0EFAA3-9840-4FE3-BC04-048FD0E83C4E`, `nombre = 'electivas'`, `codigo = 'ELE'` (mismo formato en minúscula y plural que las otras tres).

## Objetos

| Objeto | Cambio |
|---|---|
| `schema/seed/11_institucion_infraestructura.sql` | Fila ELE en el `MERGE` de `Componente` |
| `migrations/60_componente_electiva_up.sql` / `_down.sql` | Up: `MERGE` de la fila. Down: la elimina solo si ninguna asignatura la usa (si no, `THROW 59601`) |
| `scripts/migrar-marcadores.json` | Marcador de la 60 (`dbo.Componente` con `codigo = 'ELE'`) y su hash en el manifiesto CULM-001 D |
| `test/test_componente_electiva.sql` | Nueva, registrada en `test_suite.sql` |

Sin cambios de procedimientos ni vistas:

- `usp_resolver_area_componente_asignatura_interno` resuelve el componente por código o nombre exactos.
- `uv_componente` y `usp_consultar_componentes_formacion` listan todas las filas.
- No hay `CHECK` ni procedimiento con los códigos BAS/INS/ESP fijos.

## Decisión sobre la inscripción en el programa (cerrada 2026-11-19)

**Decidido por John (2026-11-19, opción 1):** la Electiva se comporta exactamente igual que Básica. No se cambia la regla de inscripción: al matricular en una asignatura ELE también se crea el vínculo `EstudiantePrograma`, como con BAS, INS y ESP. No hay cambios de procedimientos por esta decisión.

La regla de inscripción en el programa al matricular **no cambia** con esta migración. La regla de HU008 ("solo ESP crea `EstudiantePrograma`") fue reemplazada por R7 (CULM-001 B2NM, DEC-020): hoy toda matrícula, incluidas BAS e INS, crea el vínculo (PASO 3.7 de `usp_registrar_estudiante_en_grupo_interno`). Que ELE no inscriba en el programa exige una decisión de John (ver el informe del 2026-11-19).

## Validación (base local, 2026-11-19)

- `scripts/migrar.ps1 -Modo Aplicar`: `MIGRAR_APLICADA_AHORA 60_componente_electiva`.
- `test/test_componente_electiva.sql`: `COMP_ELE_01` y `COMP_ELE_02` en TEST_PASS.
- `scripts/freeze-manifest.ps1 -Mode Verify`: `FREEZE_MANIFEST_OK`.
