# Transacción: Agregar Estudiante

Documentación de la transacción para registrar el rol de estudiante a un usuario dentro de una institución.

## 📥 Parámetros de Entrada

| Parámetro | Tipo | Requerido | Descripción |
| :--- | :--- | :---: | :--- |
| `idCorrelacion` | `UUID` | Sí | Identificador de trazabilidad de la transacción |
| `idUsuario` | `UUID` | Sí | Identificador del usuario |
| `idInstitucion` | `UUID` | Sí | Identificador de la institución educativa |

---

## 📤 Parámetros de Salida

| Parámetro | Tipo | Descripción |
| :--- | :--- | :--- |
| `idCorrelacion` | `UUID` | Identificador de trazabilidad retornado |
| `mensajeUsuario` | `NVARCHAR` | Mensaje descriptivo para la interfaz de usuario |
| `mensajeTecnico` | `NVARCHAR` | Mensaje técnico de auditoría o error |
| `estado` | `BIT` | Estado de la transacción (`1` = Éxito, `0` = Fallo) |

---

## 📋 Reglas de Negocio y Validaciones

1. El perfil debe existir en el sistema.
2. El código del perfil debe ser el correcto.
3. El usuario debe existir.
4. El usuario debe estar en estado activo.
5. La institución debe existir.
6. La institución debe estar activa.
7. El usuario no debe estar agregado previamente como estudiante en la misma institución.

---

## 📊 Diagrama de Transacción (Mermaid)

```mermaid
flowchart LR
    subgraph Entrada ["Parámetros de Entrada"]
        In["idCorrelacion<br/>idUsuario<br/>idInstitucion"]
    end

    subgraph Proceso ["Transacción"]
        Tx["Agregar Estudiante"]
    end

    subgraph Salida ["Parámetros de Salida"]
        Out["idCorrelacion<br/>mensajeUsuario<br/>mensajeTecnico<br/>estado"]
    end

    In --> Tx --> Out

    subgraph Validaciones ["Reglas de Validación"]
        V1["1. El perfil existe"]
        V2["2. Código de perfil correcto"]
        V3["3. El usuario existe"]
        V4["4. El usuario está activo"]
        V5["5. La institución existe"]
        V6["6. La institución está activa"]
        V7["7. No registrado previa/ como estudiante en la institución"]
    end

    Tx --- Validaciones
```
