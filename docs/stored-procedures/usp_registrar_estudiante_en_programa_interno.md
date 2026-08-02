# Documentación: `usp_registrar_estudiante_en_programa_interno`

Este documento contiene la especificación y el flujo detallado de ejecución del procedimiento almacenado interno `usp_registrar_estudiante_en_programa_interno`.

---

## 📌 Descripción General

El procedimiento `usp_registrar_estudiante_en_programa_interno` se encarga de asociar a un estudiante con un programa académico específico en la tabla de relación `EstudiantePrograma`. Para asegurar la integridad referencial y de negocio, valida que ambos pertenezcan a la misma institución y que no exista una matrícula previa para ese programa.

### Parámetros de Entrada
| Parámetro | Tipo | Descripción |
| :--- | :--- | :--- |
| `@idEstudiante` | `UNIQUEIDENTIFIER` | ID del estudiante a registrar |
| `@idPrograma` | `UNIQUEIDENTIFIER` | ID del programa académico en el que se inscribirá |
| `@idCorrelacion` | `UNIQUEIDENTIFIER` | ID de trazabilidad/correlación de la transacción |

### Parámetros de Salida (Resultado del Query)
- `@mensajeUsuarioResultado` (`NVARCHAR(4000)`)
- `@mensajeTecnicoResultado` (`NVARCHAR(4000)`)
- `@estadoResultado` (`BIT`)

---

## 📊 Diagrama de Flujo de Ejecución (Mermaid)

```mermaid
flowchart TD
    Start([Inicio: Ejecución del Procedimiento]) --> V0[Validar ID de Correlación<br/>usp_validar_id_correlacion_esta_presente_interno]
    
    V0 --> CheckV0{¿Estado OK?}
    CheckV0 -- No --> ErrorExit([Retornar Resultado Error])
    CheckV0 -- Sí --> ObtenInst[Obtener Instituciones de Estudiante y Programa<br/>uv_estudiante y uv_programa]
    
    ObtenInst --> CheckNull{¿Instituciones Encontradas?}
    CheckNull -- No --> ErrNull[Mensaje: Fallo Datos institucionales NULL<br/>Estado = 0] --> ErrorExit
    CheckNull -- Sí --> CheckIntegridad{¿Pertenecen a la misma Institución?}
    
    CheckIntegridad -- No --> ErrIntegridad[Mensaje: Institución no coincide<br/>Estado = 0] --> ErrorExit
    CheckIntegridad -- Sí --> CheckMatricula{¿Ya existe en EstudiantePrograma?}
    
    CheckMatricula -- Sí --> MsgExiste[Mensaje: Ya se encuentra vinculado<br/>Estado = 1] --> ExitExito([Retornar Resultado Exitoso])
    CheckMatricula -- No --> RegProg[Insertar en EstudiantePrograma<br/>Generar NEWID]
    
    RegProg --> ExitExito
    
    %% Manejo Global de Excepciones
    subgraph CatchBlock [Manejo de Errores Inesperados]
        CATCH[BEGIN CATCH] --> ErrCrit[Capturar Error Crítico con ERROR_MESSAGE y ERROR_LINE] --> ErrorExit
    end
```

---

## 🔁 Resumen de Pasos de Orquestación

1. **Validación Inicial**: Verifica que exista `@idCorrelacion`.
2. **Obtención de Instituciones**:
   - Consulta `uv_estudiante` para obtener `idInstitucion` del estudiante.
   - Consulta `uv_programa` para obtener `idInstitucion` del programa y de la facultad relacionada.
3. **Validación de Consistencia**:
   - Si no se encuentran datos de institución para el estudiante o para el programa (retornan `NULL`), la validación falla.
   - Valida que la institución del estudiante sea igual a la del programa, y que la del programa coincida con la de la facultad.
4. **Verificación de Duplicados**:
   - Comprueba si existe un registro en `EstudiantePrograma` para el mismo estudiante y programa.
   - Si ya existe, finaliza con éxito (`@estadoResultado = 1`) indicando que ya está registrado para evitar errores por duplicidad.
5. **Registro de Matrícula**:
   - Realiza la inserción física en la tabla `EstudiantePrograma` asignando un nuevo identificador único (`NEWID()`).
