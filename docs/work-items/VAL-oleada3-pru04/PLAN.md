---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-12
---

# VAL-oleada3-pru04 (BD) - PLAN

Fecha: 2026-11-12. Ítem PRU-04 de `informes/LISTA_CHEQUEO_VALIDACION_2026-11-12.md`: sacar de cuarentena las 12 IT del
backend (`@Tag("cuarentena-oleada3")`). El detalle completo de causas y arreglos vive en el backend:
`Repositorio_GestionAsistenciaBackend/docs/work-items/VAL-oleada3-pru04/PLAN.md`.

Rama local `fix/VAL-oleada3-pru04-cuarentena` (mismo nombre que la del backend, así el `Backend Integration Gate` la
despliega en lugar de `develop`).

## Cambio en este repo

Solo datos de prueba para las IT de Java; no hay migraciones, ni cambios de esquema, ni de semilla de despliegue.

| Archivo | Qué |
|---|---|
| `test/fixtures/val_pru04_directorio_estudiantes_fixture.sql` (nuevo) | 12 estudiantes (`it.valpru04.estudiante.NN@test.local`) creados por `usp_sincronizar_usuario_interno` y vinculados por `EstudiantePrograma` a un programa de la institución del primer administrador. Los necesita `CoreViewQueriesJpaParityIT` (paginación de 3 páginas de 5, mínimo 11 estudiantes en el ámbito; la semilla trae 2). No se matriculan en grupos, para no cambiar conteos de grupos, sesiones, asistencias, alertas ni KPIs que comparan otras IT. Idempotente (borra y recrea por correo) y con las mismas guardas que MAINT-003G/003H (solo `gestionasistenciadb` en Developer Edition, nunca un ambiente declarado producción). |
| `test/prepare_java_integration_fixture.ps1` | Ejecuta el fixture nuevo después de MAINT-003G/003H y exige la evidencia `TEST_FIXTURE_READY|valpru04|estudiantesDirectorio=12` (`TEST_PASS:VAL_PRU04_JAVA_DIRECTORY_FIXTURE`). |

## Por qué no se agregó una matrícula con pérdida al fixture

`AvisoDocenteUmbralCancelacionIT` necesita una matrícula activa sobre el umbral de pérdida. Ponerla en el fixture compartido
la dejaría visible para todas las IT: bloquearía cierres masivos (`RCN_012`, pérdida sin revisión) y cambiaría alertas y
KPIs. Por eso la prueba la crea dentro de su propia transacción, que se revierte.
