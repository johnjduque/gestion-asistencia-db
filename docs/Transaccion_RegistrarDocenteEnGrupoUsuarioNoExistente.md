# Transacción: Registrar Docente en Grupo (Usuario No Existente)

Documentación de la transacción orquestadora para dar de alta o actualizar a un usuario, asegurar su rol de docente y asignarlo como el docente a cargo de un grupo académico.

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
| `idGrupo` | `UUID` | Sí | ID del grupo al cual se le asignará el docente |
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
*   Validar que el id de correlación esté presente.
*   Validar si el usuario ya está registrado en el sistema (por correo o por tipo/número de documento).
*   Si el usuario ya existe, actualizar sus datos básicos; de lo contrario, crearlo (sincronizar usuario).
*   Validar si el usuario tiene el perfil de docente (en la tabla `Docente`), de lo contrario crearlo (sincronizar docente).
*   Asignar al docente al grupo académico correspondiente (actualizando la columna `docente` en la tabla `Grupo`).

---

## 🔍 Reglas de Negocio y Validaciones

### 1. Validaciones Propias de `usp_registrar_docente_en_grupo_usuario_no_existente`
*   **Validación de Consistencia del Grupo**: El grupo en el cual se asignará el docente debe existir previamente en el sistema y no tener un estado inactivo.

### 2. Procedimientos Utilizados y sus Validaciones

*   **`usp_validar_id_correlacion_esta_presente_interno`**
    *   Validación de Correlación.

*   **`usp_validar_usuario_existe_por_id_interno`**
    *   Validación de Existencia y Actividad del Usuario.

*   **`usp_sincronizar_usuario_interno`**
    *   Validación del Tipo de Documento.
    *   Validación de Unicidad (el correo y el número de identificación deben ser únicos).
    *   Validación de Formatos (nombres, primer apellido, correo y contraseña).

*   **`usp_sincronizar_docente_interno`**
    *   Validación del Perfil de Docente (busca perfil con código `'DO'`).
    *   Validación de Unicidad (el usuario no debe estar registrado previamente en la tabla `Docente`).

*   **`usp_registrar_docente_en_grupo_interno`**
    *   Validación de Existencia del Docente.
    *   Validación de Existencia del Grupo.
    *   Validación de Habilitación y Periodo Académico (el grupo debe pertenecer a un periodo académico activo).
    *   Validación de Cruces de Horario (el docente no debe tener asignado otro grupo en el mismo periodo académico con horarios coincidentes).
