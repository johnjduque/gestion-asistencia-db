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
