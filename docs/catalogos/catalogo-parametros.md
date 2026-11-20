# Catálogo de parámetros

## Hoja: Valores

| A | B | C | D | E | F | G | I | J |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |


## Hoja: Parámetros

| A | B | C | D | E | F | G | H |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GLOBAL_FUN_GEN_Rol usuario |  |  |  |  |  |  | Corresponde al rol del usuario cuando se va a crear un usuario, es el valor por defecto de la lista desplegable la cual contiene dos valores: administrador y analista  |
| GLOBAL_FUN_GEN_Tipo de consulta |  |  |  |  |  |  |  |
| GLOBAL_FUN_GEN_Facultad |  |  |  |  |  |  |  |
| GLOBAL_FUN_GEN_Nivel de formación |  |  |  |  |  |  |  |
| GLOBAL_FUN_GEN_Programa |  |  |  |  |  |  |  |
| GLOBAL_FUN_GEN_Año base cálculo |  |  |  |  |  |  |  |
| GLOBAL_TEC_GEN_Año rango inicial |  |  |  |  |  | 2005 |  |
| GLOBAL_FUN_GEN_Fecha máxima |  |  |  |  |  |  |  |
| GLOBAL_TEC_GEN_Rango semestre |  |  |  |  |  | 14 | Corresponde al rango de semestres a calcular en algunos indicadores que se calculan en una línea de tiempo  |



## Parámetros sembrados por las migraciones (tabla `CatalogoParametro`)

El catálogo de arriba es el inventario funcional original. Los parámetros que siembran las migraciones y los archivos de `schema/seed/` no se repiten aquí uno a uno; el que agrega la oleada 2 de la validación es:

| Grupo | Clave | Valor | Tipo | Rango | Editable | Descripción | Migración / semilla |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AUDITORIA | RANGO_MAXIMO_DIAS | 90 | INT | 1..366 | No (el grupo AUDITORIA está en `PARAMETROS/GRUPOS_NO_EDITABLES`) | Días máximos entre la fecha inicial y la final de la consulta de auditoría. Lo lee el backend en lugar de tenerlo fijo (PAR-06). | `migrations/40_val_parametro_rango_auditoria_up.sql`, `schema/seed/57_val_parametro_rango_auditoria.sql` |

El rango 1..366 vive en `CatalogoParametroEdicion` (fila con `esEditable = 0`) y lo valida `ufn_validar_valor_parametro` (código `PRM_005` fuera de rango).

### SES-GEN-01: calendario de sesiones del semestre (`migrations/64_ses_gen_01_calendario_semestre_up.sql`)

| Grupo | Clave | Valor | Tipo | Descripción |
| --- | --- | --- | --- | --- |
| PERIODO | SEMANAS_DURACION | 16 | INT | El semestre dura siempre 16 semanas (112 días corridos): `fechaFin = fechaInicio + 7 x semanas - 1`. Lo imponen `usp_crear_periodo_academico` y `usp_actualizar_periodo_academico` al crear y al cambiar fechas (`PER_011`); los períodos históricos se conservan. |
| ASIGNATURA | HORAS_SEMANALES_MAXIMO | 40 | INT | Tope de `Asignatura.horasSemanales` (horas de 60 minutos de reloj, entero >= 1; `ASI_013`). |
| HORARIO | DURACION_MINIMA_MINUTOS | 60 | INT | Duración mínima de cada franja del horario de un grupo (`HOR_007`). Parámetro ausente: no se valida. |
| HORARIO | DURACION_MAXIMA_MINUTOS | 240 | INT | Duración máxima de cada franja (`HOR_007`). |
| HORARIO | VENTANA_INICIO | 06:00 | STRING | Hora local institucional más temprana en que puede empezar una franja (`HOR_008`). |
| HORARIO | VENTANA_FIN | 22:00 | STRING | Hora local institucional más tardía en que puede terminar una franja (`HOR_008`). |

Ninguno es editable desde la pantalla de parámetros (sin fila en `CatalogoParametroEdicion`).
