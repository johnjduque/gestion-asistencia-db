# PLAN — SES-GEN-01

1. Registrar la extensión post-freeze y sus contratos en `CONTRACT.md` y en `DB_DEVELOP_FREEZE_ADDENDUM.md`.
2. Mantener la secuencia global de migraciones: 57 NOTOMA-001, 58 HU074, 64 SES-GEN-01 (renumerada desde 59).
3. Resolver colisiones de catálogo sin reutilizar ASI_009/ASI_010, que pertenecen a HU074.
4. Integrar las reglas de SES-GEN-01 en `usp_crear_grupo` preservando el bloqueo y la transacción de HU074.
5. Añadir `usp_previsualizar_horario_grupo`, la proyección mínima del período cerrado y el permiso de mínimo privilegio.
6. Mantener todas las lecturas de procedimientos públicos por vistas `uv_*` y documentar el contrato READ_QUERY_RESULTSET.
7. Ejecutar la validación segura de parser/estructura y la suite CI en una base desechable; no usar la instancia local compartida.
