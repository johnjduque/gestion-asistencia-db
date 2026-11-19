# TEST PLAN — SES-GEN-01

| Área | Escenario | Evidencia esperada |
|---|---|---|
| Período | Sin fecha final calcula 112 días; duración no válida se rechaza; cambio solo de nombre conserva históricos | `SES_GEN_01_PER_*`, `PER_011` |
| B1 | Coordinador con custodia completa crea grupo; sin vínculo activo no crea y devuelve `ASI_014`; inactiva devuelve `ASI_010` | `SES_GEN_01_B1_*`, `HU074_07/18` |
| B2 | Período vencido/cerrado/fuera de institución rechaza; NULL no busca un período reciente | `SES_GEN_01_B1_B2`, `PER_010`, `VAL_002` |
| Horario | Suma incorrecta, duración fuera de rango, ventana inválida y asignatura sin horas | `SES_GEN_01_B5/B7`, `HOR_006..008`, `ASI_013` |
| Preview | Las sesiones, semanas, festivos y conflictos coinciden con la precarga; un conflicto bloqueante no se lanza como excepción | `SES_GEN_01_PREVIEW`, `READ_QUERY_RESULTSET` |
| Seguridad | Runtime ejecuta preview y no tiene SELECT en la proyección interna | `SES_GEN_01_RUNTIME_GRANT` |
| Migración | Down retira solo SES-GEN-01; up repetido es idempotente; la transacción de prueba revierte | `SES_GEN_01_MIG_UP_DOWN_UP` |
