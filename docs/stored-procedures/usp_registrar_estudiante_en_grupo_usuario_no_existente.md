# Documentación: `usp_registrar_estudiante_en_grupo_usuario_no_existente`

Este documento contiene la especificación y el flujo detallado de ejecución del procedimiento almacenado orquestador `usp_registrar_estudiante_en_grupo_usuario_no_existente`.

---

## 📌 Descripción General

El procedimiento `usp_registrar_estudiante_en_grupo_usuario_no_existente` actúa como **orquestador principal** para dar de alta o actualizar a un usuario, asegurar su perfil como estudiante, enrolarlo en un grupo académico y registrarlo en su programa correspondiente.

### Parámetros de Entrada
| Parámetro | Tipo | Descripción |
| :--- | :--- | :--- |
| `@tipoIdIdentificacion` | `UNIQUEIDENTIFIER` | ID del tipo de identificación |
| `@numeroIdentificacion` | `INT` | Número de documento |
| `@primerApellido` | `NVARCHAR(255)` | Primer apellido |
| `@segundoApellido` | `NVARCHAR(255)` | Segundo apellido (opcional) |
| `@primerNombre` | `NVARCHAR(255)` | Primer nombre |
| `@segundoNombre` | `NVARCHAR(255)` | Segundo nombre (opcional) |
| `@correo` | `NVARCHAR(255)` | Correo electrónico institucional / personal |
| `@password` | `NVARCHAR(MAX)` | Contraseña del usuario |
| `@idGrupo` | `UNIQUEIDENTIFIER` | ID del grupo en el que se enrolará |
| `@idCorrelacion` | `UNIQUEIDENTIFIER` | ID de trazabilidad/correlación de la transacción |

### Parámetros de Salida (Resultado del Query)
- `@idUsuarioCreado` (`UNIQUEIDENTIFIER` / Interno)
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
    CheckV0 -- Sí --> BuscarUsuario[Buscar Usuario Existente por Correo o Identificación en uv_usuario]
    
    BuscarUsuario --> CheckUserExist{¿Existe Usuario?}
    
    %% Camino Usuario Existente
    CheckUserExist -- Sí --> ValUserExt[Validar Estado de Usuario<br/>usp_validar_usuario_existe_por_id_interno]
    ValUserExt --> CheckValUserExt{¿Estado OK?}
    CheckValUserExt -- No --> ErrorExit
    CheckValUserExt -- Sí --> UpdateUser[Actualizar Datos Básicos en Usuario] --> PasoEstudiante
    
    %% Camino Usuario Nuevo
    CheckUserExist -- No --> SincUser[Crear Usuario<br/>usp_sincronizar_usuario_interno]
    SincUser --> CheckSincUser{¿Estado OK?}
    CheckSincUser -- No --> ErrorExit
    CheckSincUser -- Sí --> GetNewUser[Obtener ID del Usuario Creado] --> PasoEstudiante
    
    %% Paso 2: Perfil Estudiante
    PasoEstudiante[Buscar Perfil de Estudiante en uv_estudiante_identidad] --> CheckEstExist{¿Existe Perfil?}
    CheckEstExist -- Sí --> SetMsgEst[Verificar Perfil Base de Estudiante] --> EnrolarGrupo
    CheckEstExist -- No --> SincEst[Crear Perfil de Estudiante<br/>usp_sincronizar_estudiante_interno]
    SincEst --> CheckSincEst{¿Estado OK?}
    CheckSincEst -- No --> ErrorExit
    CheckSincEst -- Sí --> GetNewEst[Obtener ID del Estudiante Creado] --> EnrolarGrupo
    
    %% Paso 3: Enrolar en Grupo
    EnrolarGrupo[Enrolar Estudiante en el Grupo<br/>usp_registrar_estudiante_en_grupo_interno] --> CheckEnrol{¿Estado OK?}
    CheckEnrol -- No --> ErrorExit
    CheckEnrol -- Sí --> BuscarProg[Buscar Programa Académico del Grupo]
    
    %% Paso 4: Programa Académico
    BuscarProg --> CheckProgExist{¿Programa Encontrado?}
    CheckProgExist -- No --> ErrProg[Mensaje: Trazabilidad rota para Grupo<br/>Estado = 0] --> ErrorExit
    CheckProgExist -- Sí --> RegProg[Registrar Estudiante en Programa<br/>usp_registrar_estudiante_en_programa_interno]
    
    RegProg --> CheckRegProg{¿Estado OK?}
    CheckRegProg -- No --> ErrorExit
    CheckRegProg -- Sí --> ExitExito([Retornar Resultado Exitoso: Estado = 1])
    
    %% Manejo Global de Excepciones
    subgraph CatchBlock [Manejo de Errores Inesperados]
        CATCH[BEGIN CATCH] --> ErrCrit[Capturar Error Crítico con ERROR_MESSAGE y ERROR_LINE] --> ErrorExit
    end
```

---

## 🔁 Resumen de Pasos de Orquestación

1. **Validación Inicial**: Verifica que exista `@idCorrelacion`.
2. **Gestión de Usuario**:
   - Si el usuario existe, valida su estado activo y actualiza nombres/apellidos.
   - Si no existe, invoca `usp_sincronizar_usuario_interno`.
3. **Gestión de Estudiante**:
   - Verifica existencia en `uv_estudiante_identidad`.
   - Si no existe, invoca `usp_sincronizar_estudiante_interno`.
4. **Enrolamiento en Grupo**:
   - Invoca `usp_registrar_estudiante_en_grupo_interno`.
5. **Asignación de Programa**:
   - Resuelve el programa académico correspondiente al grupo mediante `uv_grupo -> uv_asignatura -> uv_semestre_plan_estudio -> uv_plan_estudio`.
   - Invoca `usp_registrar_estudiante_en_programa_interno`.
