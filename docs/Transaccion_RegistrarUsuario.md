# Transacción: Registrar Usuario

Documentación de la transacción para el registro de un nuevo usuario en el sistema.

## 📥 Parámetros de Entrada

| Parámetro | Tipo | Requerido | Descripción |
| :--- | :--- | :---: | :--- |
| `idCorrelacion` | `UUID` | Sí | Identificador de trazabilidad de la transacción |
| `idTipoIdIdentificacion` | `UUID` | Sí | Tipo de documento de identidad del usuario |
| `numeroIdentificacion` | `INT` | Sí | Número de documento de identidad |
| `primerApellido` | `NVARCHAR` | Sí | Primer apellido |
| `segundoApellido` | `NVARCHAR` | No | Segundo apellido |
| `primerNombre` | `NVARCHAR` | Sí | Primer nombre |
| `segundoNombre` | `NVARCHAR` | No | Segundo nombre |
| `correo` | `NVARCHAR` | Sí | Correo electrónico |
| `password` | `NVARCHAR` | Sí | Contraseña de acceso |

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

1. El usuario no debe existir en el sistema.
2. El correo no debe estar registrado con otro usuario.
3. El tipo de identificación debe existir.
4. Los campos obligatorios (`primerNombre`, `primerApellido`, `numeroIdentificacion`, `correo`, `password`) deben estar diligenciados.
5. El formato del correo debe cumplir con una estructura válida.
6. La contraseña debe cumplir con las condiciones mínimas de seguridad.

---

## 📊 Diagrama de Transacción (Mermaid)

```mermaid
flowchart LR
    subgraph Entrada ["Parámetros de Entrada"]
        In["idCorrelacion<br/>idTipoIdIdentificacion<br/>numeroIdentificacion<br/>primerApellido<br/>segundoApellido<br/>primerNombre<br/>segundoNombre<br/>correo<br/>password"]
    end

    subgraph Proceso ["Transacción"]
        Tx["Registrar Usuario"]
    end

    subgraph Salida ["Parámetros de Salida"]
        Out["idCorrelacion<br/>mensajeUsuario<br/>mensajeTecnico<br/>estado"]
    end

    In --> Tx --> Out

    subgraph Validaciones ["Reglas de Validación"]
        V1["1. El usuario no existe"]
        V2["2. Correo no duplicado"]
        V3["3. Tipo identificación existe"]
        V4["4. Campos obligatorios diligenciados"]
        V5["5. Formato de correo válido"]
        V6["6. Contraseña cumple condiciones mínimas"]
    end

    Tx --- Validaciones
```
