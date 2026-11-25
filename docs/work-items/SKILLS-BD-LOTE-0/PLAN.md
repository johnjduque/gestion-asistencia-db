---
status: active
type: work-item
scope: db-docs
owner: db-team
last-reviewed: 2026-11-25
---

# PLAN — SKILLS-BD lote 0: documentar las excepciones justificadas a los skills

## Contexto

Los skills de BD recogen las reglas de organización del código acordadas con el asesor. Su cumplimiento cuenta para la aceptación de la app.

La auditoría del 2026-11-25 y su plan por lotes (`informes/AUDITORIA_BD_SKILLS_2026-11-25` y `informes/PLAN_LOTES_SKILLS_BD_2026-11-25`, fuera del repo) dejan este reparto:
- lo que el código puede cumplir se corrige en los lotes 1 a 14;
- lo que no puede cumplir sin romper la app o sin cambiar el backend se documenta como excepción, sin modificar los skills.

## Cambios

- Nuevo `docs/arquitectura/excepciones-skills-bd.md`, con las excepciones E1 a E6, el motivo técnico de cada una y la condición que la acota.
- **Sin cambios** en `.agents/skills/`, `schema/`, `test/`, contratos ni AGENTS.md.

## Decisiones de John (2026-11-25)

| # | Decisión |
|---|---|
| D1 | Se conserva `XACT_ABORT ON` en el patrón de savepoint (excepción E5). |
| D2 | El backend puede leer las vistas base; la validación de rol y ámbito sigue en `uv_auth_*`, en los SP o en el PDP (E3). |
| D3 | `usp_internal_*` se renombra a `usp_..._interno` en el lote 2. **No** es excepción. |
| D4 | Se dejan como excepciones los SP de sistema, el ejecutor `@idUsuario`, el administrador en lecturas transversales y HU156 (E1, E2 y E4). |
| D5 | Los congelados se corrigen en el lote 14, sin cambiar firma ni resultset (E6). |
| D6 | `uv_auth_decano`: se mantiene la visibilidad de los decanos sin facultad, con la condición escrita de forma explícita (lote 4). |
| D7 | Al final se avisa a Sergio y a José Alejandro para que actualicen sus BD. |

## Validación

- Los SP citados existen en `schema/stored-procedures/`.
- El lote no cambia código, así que el gate de BD es el mismo que en `develop`.
