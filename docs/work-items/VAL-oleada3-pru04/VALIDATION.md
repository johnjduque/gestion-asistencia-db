---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-13
---

# VAL-oleada3-pru04 (BD) - VALIDATION

Fecha: 2026-11-12/13. Réplica local del `Backend Integration Gate` sobre el contenedor local `sql_server_asistencias`
(Developer Edition), en una base APARTE `gestionasistenciadb_ci` (la base de desarrollo `gestionasistenciadb` no se tocó):
copia del repo con el nombre de la base reescrito a `gestionasistenciadb_ci`, `deploy_schema.ps1` completo y
`test/prepare_java_integration_fixture.ps1`. La base aparte se borró al final.

| Corrida | Resultado |
|---|---|
| `prepare_java_integration_fixture.ps1` (esquema de `develop` + rama) | `TEST_PASS:MAINT_003G_JAVA_ATTENDANCE_FIXTURE`, `TEST_PASS:MAINT_003H_JAVA_DATA_FIXTURE`, `TEST_PASS:VAL_PRU04_JAVA_DIRECTORY_FIXTURE`. |
| Idempotencia | Después de la corrida completa de las IT, el script completo se corrió dos veces más seguidas sobre la misma base: las tres evidencias `TEST_PASS` en ambas (cada fixture borra y recrea sus filas). |
| Perfil `integration` completo del backend sobre esta base | 347 IT: 321 en verde, 17 omitidas y 26 fallas solo de ambiente local (MinIO y ClamAV no levantados). Ver la VALIDATION del backend. |
| Primer intento del fixture nuevo | Falló con `Msg 102` (expresiones como argumento de `EXEC`); se pasaron a variables. Una transacción con `XACT_ABORT` no dejó filas. |
| IT de Java que lo usan | `CoreViewQueriesJpaParityIT` 7/7 (antes 6/7: "encontrados: 2"); `EstudianteAcademicFilterJpaParityIT` 3/3 con los 12 estudiantes nuevos (no tienen grupo, no entran en los filtros académicos). |

No se corrió la compuerta completa de BD (`test_summary.ps1`, ~20 min): el cambio es solo un fixture de prueba de Java que
no se despliega con el esquema ni con la semilla, y `test_summary.ps1` no lo ejecuta.
