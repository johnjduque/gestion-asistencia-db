# Índice de Documentación: Base de Datos (`gestionasistenciadb`) 📚

Este archivo sirve como punto de partida e índice de navegación para toda la documentación técnica de la base de datos de Gestión de Asistencias.

---

## 🗂️ Estructura de Documentación

La documentación se organiza de la siguiente manera:

```text
/docs
├── README.md                      <-- Este índice de navegación
├── 6_Entegas.md                   <-- Listado de entregables e historias de usuario
├── prioridades-desarrollo.md      <-- Análisis de prioridades e impacto de HUs
├── DiagramaDeClases.md            <-- Modelo de clases
├── DiagramaDeDominio.md           <-- Modelo de dominio
├── ModeloEntidadRelacion.md       <-- Estructura de tablas y relaciones
├── /stored-procedures/            <-- Documentación detallada de SPs
│   ├── usp_registrar_estudiante_en_grupo_usuario_no_existente.md
│   └── usp_registrar_estudiante_en_programa_interno.md
└── Transaccion_*.md               <-- Flujos de transacciones lógicas
```

---

## 📋 Entregables e Historias de Usuario

*   [**Listado de Entregas e Historias de Usuario**](6_Entegas.md): Listado completo de todas las historias de usuario del sistema (HU001 a HU167) con enlaces a los detalles de las primeras 5 historias (HU001 a HU005) creadas en su respectiva carpeta.
*   [**Prioridades e Impacto de Desarrollo**](prioridades-desarrollo.md): Análisis de impacto de negocio y dependencias técnicas para establecer la hoja de ruta de desarrollo de las historias de usuario.

---

## ⚙️ Procedimientos Almacenados (Orquestadores)

Procedimientos almacenados que encapsulan flujos y lógica de negocio específica en la base de datos:

*   [**`usp_registrar_estudiante_en_grupo_usuario_no_existente`**](stored-procedures/usp_registrar_estudiante_en_grupo_usuario_no_existente.md): Orquestador principal para registrar o actualizar a un usuario, asegurar su perfil de estudiante y enrolarlo en un grupo.
*   [**`usp_registrar_estudiante_en_programa_interno`**](stored-procedures/usp_registrar_estudiante_en_programa_interno.md): Procedimiento que vincula a un estudiante con un programa académico, validando consistencia institucional y controlando duplicados.

---

## 🔄 Transacciones y Flujos de Negocio

Especificación de transacciones lógicas del sistema:

*   [**Transacción: Agregar Estudiante**](Transaccion_AgregarEstudiante.md)
*   [**Transacción: Matricular Estudiante en un Grupo**](Transaccion_MatricularEstudianteEnUnGrupo.md)
*   [**Transacción: Registrar Asistencia de Estudiante a Clase Específica**](Transaccion_RegistrarAsistenciaEstudianteClaseEspecifica.md)
*   [**Transacción: Registrar Docente en Grupo (Usuario No Existente)**](Transaccion_RegistrarDocenteEnGrupoUsuarioNoExistente.md)
*   [**Transacción: Registrar Estudiante en Grupo (Usuario No Existente)**](Transaccion_RegistrarEstudianteEnGrupoUsuarioNoExistente.md)
*   [**Transacción: Registrar Usuario**](Transaccion_RegistrarUsuario.md)

---

## 📊 Modelos y Diagramas de Diseño

Documentación de diseño estructural de la base de datos y la aplicación:

*   [**Diagrama de Clases**](DiagramaDeClases.md)
*   [**Diagrama de Dominio**](DiagramaDeDominio.md)
*   [**Modelo Entidad-Relación**](ModeloEntidadRelacion.md)
