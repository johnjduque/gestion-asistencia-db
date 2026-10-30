---
name: modelo-jerarquico-rbac
description: >-
  Estándar canónico del modelo jerárquico de custodia, delimitación de dominios y matriz de permisos RBAC para todos los procedimientos almacenados y vistas en gestionasistenciadb.
---

# Modelo Jerárquico de Custodia y Matriz de Permisos RBAC (`modelo-jerarquico-rbac`)

## 1. Principio de Delimitación de Dominio y Jerarquía Institucional

Esta documentación establece las reglas de arquitectura y custodia jerárquica para la base de datos `gestionasistenciadb`. Ningún procedimiento almacenado (`usp_*`) ni vista autorizada (`uv_auth_*`) debe violar los límites de custodia definidos para cada perfil institucional.

```
[INSTITUCIÓN]
    │
    ├── [ADMINISTRADOR DE INSTITUCIÓN] (AD)
    │      └── Alcance: Decanos, Facultades, Periodos Académicos e Institución.
    │          (NO interfiere en Grupos, Docentes en Grupos, Estudiantes ni Asistencias).
    │
    └── [FACULTAD] (DECANO - DE)
           │   └── Alcance: Programas Académicos y Coordinadores de su Facultad.
           │
           └── [PROGRAMA ACADÉMICO] (COORDINADOR - CD)
                  │   └── Alcance: Asignaturas, Plan de Estudio, Docentes, Grupos y Aprobación de Docentes en Grupos.
                  │
                  └── [GRUPO / ASIGNATURA] (DOCENTE - DO)
                         │   └── Alcance: Sesiones, Asistencias y Aprobación de Estudiantes en sus Grupos.
                         │
                         └── [ESTUDIANTE] (ES)
                                └── Alcance: Su propia identidad, consulta de sus horarios/asistencias y solicitudes de revisión.
```

---

## 2. Matriz de Permisos RBAC por Nivel Jerárquico

### A. Administrador (`AD`)
* **Dominio Permitido**: Gestión de **Decanos**, **Facultades**, **Periodos Académicos** e **Institución**.
* **Prohibición de Sobreachipamiento (Out of Scope)**: El Administrador **NO** debe ser incluido en la validación RBAC de procedimientos o endpoints pertenecientes a niveles inferiores de la jerarquía (ej. `usp_registrar_estudiante_en_grupo`, `usp_vincular_docente_programa`, `usp_registrar_asistencias_sesion`).

### B. Decano (`DE`)
* **Dominio Permitido**: Gestión de **Facultad a su cargo**, **Programas Académicos** y **Coordinadores**.
* **Delimitación**: Únicamente puede administrar y consultar entidades pertenecientes a la facultad donde figura como Decano titular.

### C. Coordinador (`CD`)
* **Dominio Permitido**: Gestión del **Programa Académico a su cargo**, sus **Asignaturas**, **Docentes** y **Grupos**. Incluye vincular docentes al programa (ej. `usp_vincular_docente_programa`) y gestionar asignaturas (ej. `usp_actualizar_asignatura`).
* **Delimitación RBAC**: Para `usp_vincular_docente_programa`, la validación RBAC exige que el ejecutor sea **COORDINADOR**, excluyendo explícitamente al Administrador, y que coordine el programa (titularidad).

### D. Docente (`DO`)
* **Dominio Permitido**: Gestión de sus **Grupos asignados**, dictado de **Sesiones**, toma de **Asistencias** y aprobación de solicitudes de inscripción/matrícula de estudiantes en sus grupos (ej. `usp_registrar_estudiante_en_grupo`, `usp_resolver_solicitud_ingreso_grupo`).
* **Delimitación**: Su alcance está estrictamente acotado a los grupos donde es docente titular.

### E. Estudiante (`ES`)
* **Dominio Permitido**: Consulta de sus **Horarios**, **Asistencias** individuales, **Revisiones** de asistencia y postulación autónoma (`usp_registrar_estudiante_en_grupo_autonomo`).

---

## 3. Reglas de Validación en Procedimientos Almacenados (`usp_*`)

1. **Validación Estricta de RBAC**: Todo procedimiento almacenado debe validar explícitamente `@idUsuarioEjecutor` utilizando `dbo.usp_validar_permiso_rbac_usuario_interno` con la lista exacta de perfiles permitidos para ese nivel.
2. **Ejemplo de Vinculación de Docente al Programa (`usp_vincular_docente_programa`)**:
   ```sql
   -- Exige que el ejecutor sea COORDINADOR (excluye explícitamente a ADMINISTRADOR)
   EXEC dbo.usp_validar_permiso_rbac_usuario_interno
       @idUsuario = @idUsuarioEjecutorDefecto,
       @codigoPerfilRequerido = 'COORDINADOR',
       @idCorrelacion = @idCorrelacionDefecto,
       @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
       @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
       @estadoResultado = @estadoResultado OUTPUT;
   ```
3. **Ejemplo de Aprobación/Registro de Estudiante en Grupo (`usp_registrar_estudiante_en_grupo`)**:
   ```sql
   -- Exige que el ejecutor sea DOCENTE o COORDINADOR (excluye explícitamente a ADMINISTRADOR)
   EXEC dbo.usp_validar_permiso_rbac_usuario_interno
       @idUsuario = @idUsuarioEjecutorDefecto,
       @codigoPerfilRequerido = 'DOCENTE,COORDINADOR',
       @idCorrelacion = @idCorrelacionDefecto,
       @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
       @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
       @estadoResultado = @estadoResultado OUTPUT;
   ```

---

## 4. Alternativas aceptadas y patrones vigentes (REC4, 2026-10-29)

Estas alternativas **no relajan** la seguridad: siempre exigen el ejecutor (`GEN_002`) y responden `SEC_001` o `SEC_002`.

1. **Titularidad validada dentro del propio SP.**
   - Cuando la titularidad depende de la propia entidad, el SP puede validarla con un JOIN propio en lugar de `usp_validar_titularidad_jerarquica_interno`.
   - Ejemplos: el docente titular del grupo (HU051, HU053-HU055) o "solo el propio usuario" (HU006 perfil).
   - Condiciones:
     - `@idUsuarioEjecutor` obligatorio;
     - el administrador fuera de los niveles inferiores;
     - "no existe" y "no es titular" indistinguibles cuando revelarlo filtraría información.
2. **SP interno de validación compartido.**
   - Si dos o más SP públicos repiten la misma secuencia (ejecutor, RBAC, existencia y titularidad), se extrae a un `usp_validar_*_interno` con el triplete OUTPUT y ambos lo invocan.
   - Ejemplo: `usp_validar_gestion_asignatura_coordinador_interno`, usado por `usp_actualizar_asignatura` y `usp_toggle_estado_asignatura` (REC2).
   - Evita la duplicación que rechaza SonarCloud.
3. **Ampliar perfiles.**
   - Para permitir otro nivel, se usa la lista de perfiles (`'COORDINADOR,DECANO'`) junto con la titularidad del nivel correspondiente (`PROGRAMA` o `FACULTAD`).
   - Nunca se agrega `ADMINISTRADOR` a operaciones de grupo, docente, estudiante o asistencia.
