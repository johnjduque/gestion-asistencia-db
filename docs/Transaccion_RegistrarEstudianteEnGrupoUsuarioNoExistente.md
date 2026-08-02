# Transacción: Registrar Estudiante en Grupo (Usuario No Existente)

Documentación de la transacción orquestadora para dar de alta o actualizar a un usuario, asegurar su rol de estudiante y enrolarlo tanto en un grupo como en su programa académico correspondiente.

## 📥 Parámetros de Entrada

| Parámetro | Tipo | Requerido | Descripción |
| :--- | :--- | :---: | :--- |
| `tipoIdIdentificacion` | `UUID` | Sí | ID del tipo de documento de identidad |
| `numeroIdentificacion` | `INT` | Sí | Número del documento de identidad |
| `primerApellido` | `NVARCHAR` | Sí | Primer apellido |
| `segundoApellido` | `NVARCHAR` | No | Segundo apellido |
| `primerNombre` | `NVARCHAR` | Sí | Primer nombre |
| `segundoNombre` | `NVARCHAR` | No | Segundo nombre |
| `correo` | `NVARCHAR` | Sí | Dirección de correo electrónico |
| `password` | `NVARCHAR` | No | Contraseña del usuario |
| `idGrupo` | `UUID` | Sí | ID del grupo en el que se inscribirá |
| `idCorrelacion` | `UUID` | Sí | ID de trazabilidad de la transacción |

---

## 📤 Parámetros de Salida

| Parámetro | Tipo | Descripción |
| :--- | :--- | :--- |
| `idCorrelacion` | `UUID` | Identificador de trazabilidad retornado |
| `mensajeUsuario` | `NVARCHAR` | Mensaje descriptivo para la interfaz de usuario |
| `mensajeTecnico` | `NVARCHAR` | Mensaje técnico de auditoría o error detallado |
| `estado` | `BIT` | Estado final de la transacción (`1` = Éxito, `0` = Fallo) |

---

## 📋 Responsabilidades de la Transacción

La transacción es responsable de los siguientes flujos:
*   Validar id correlacion esta presente
*   Validar si el usuario esta creado
*   Si existe actualizarlo de lo contrario crearlo
*   Registrar estudiante en el grupo
*   Registrar estudiante en programa

---

## 🔍 Reglas de Negocio y Validaciones

### 1. Validaciones Propias de `usp_registrar_estudiante_en_grupo_usuario_no_existente`
*   Validación de Trazabilidad del Programa Académico

### 2. Procedimientos Utilizados y sus Validaciones

*   **`usp_validar_id_correlacion_esta_presente_interno`**
    *   Validación de Correlación

*   **`usp_validar_usuario_existe_por_id_interno`**
    *   Validación de Existencia y Actividad del Usuario

*   **`usp_sincronizar_usuario_interno`**
    *   Validación del Tipo de Documento
    *   Validación de Unicidad
    *   Validación de Formatos

*   **`usp_sincronizar_estudiante_interno`**
    *   Validación del Perfil de Estudiante

*   **`usp_registrar_estudiante_en_grupo_interno`**
    *   Validación de Existencia del Estudiante
    *   Validación de Existencia del Grupo
    *   Validación de Habilitación y Periodo Académico
    *   Validación de Cupos del Grupo
    *   Validación de Cruces de Horario
    *   Validación de Matrícula Duplicada

*   **`usp_registrar_estudiante_en_programa_interno`**
    *   Validación de Consistencia Institucional
