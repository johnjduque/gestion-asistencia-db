# Índice de Transacciones y Procedimientos Almacenados 🔄

Este documento contiene el listado y clasificación de todas las transacciones lógicas y procedimientos almacenados (tanto orquestadores como internos) relacionados con la gestión de asistencia y enrolamiento.

---

## 📋 Listado de Transacciones

| Transacción / Procedimiento | Tipo | Descripción | Código SQL |
| :--- | :--- | :--- | :--- |
| [**Registrar Asistencia Estudiante**](usp_registrar_asistencia_estudiante.md) | Orquestador | Registra o modifica de manera individual o por evento la asistencia de un estudiante inscrito a una sesión de clase específica. | [Ver SQL](../../schema/stored-procedures/usp_registrar_asistencia_estudiante.sql) |
| [**Registrar Asistencia Estudiante (Autónomo)**](usp_registrar_asistencia_estudiante_autonomo.md) | Orquestador | Permite que un estudiante registre su asistencia en una sesión de clase específica de forma autónoma con código de verificación. | [Ver SQL](../../schema/stored-procedures/usp_registrar_asistencia_estudiante_autonomo.sql) |
| [**Registrar Docente en Grupo (Usuario No Existente)**](usp_registrar_docente_en_grupo_usuario_no_existente.md) | Orquestador | Da de alta o actualiza a un usuario, asegura su rol de docente y lo asigna como docente titular de un grupo académico. | [Ver SQL](../../schema/stored-procedures/usp_registrar_docente_en_grupo_usuario_no_existente.sql) |
| [**Registrar Estudiante en Grupo Interno**](usp_registrar_estudiante_en_grupo_interno.md) | Interno / Flujo | Inscribe formalmente a un estudiante activo en un grupo académico, validando cupos disponibles y cruces de horarios. | [Ver SQL](../../schema/stored-procedures/usp_registrar_estudiante_en_grupo_interno.sql) |
| [**Registrar Estudiante en Grupo (Usuario No Existente)**](usp_registrar_estudiante_en_grupo_usuario_no_existente.md) | Orquestador | Da de alta o actualiza a un usuario, asegura su rol de estudiante y lo enrola tanto en un grupo como en su programa académico. | [Ver SQL](../../schema/stored-procedures/usp_registrar_estudiante_en_grupo_usuario_no_existente.sql) |
| [**Sincronizar Estudiante Interno**](usp_sincronizar_estudiante_interno.md) | Interno | Crea o asegura el rol de estudiante para un usuario dentro de la institución educativa. | [Ver SQL](../../schema/stored-procedures/usp_sincronizar_estudiante_interno.sql) |
| [**Sincronizar Usuario Interno**](usp_sincronizar_usuario_interno.md) | Interno | Crea o actualiza la información básica de un usuario (datos personales y de contacto) en el sistema. | [Ver SQL](../../schema/stored-procedures/usp_sincronizar_usuario_interno.sql) |
| [**Sincronizar Asistencia Estudiante Interno**](internos/usp_sincronizar_asistencia_estudiante_interno.md) | Interno (Aux) | Registra o actualiza el estado de asistencia de un estudiante de manera individual, previniendo duplicidades. | [Ver SQL](../../schema/stored-procedures/usp_sincronizar_asistencia_estudiante_interno.sql) |
| [**Validar Estudiante Grupo Exista Interno**](internos/usp_validar_estudiante_grupo_exista_interno.md) | Interno (Validación) | Valida la existencia y vigencia de la relación entre el estudiante y el grupo (matrícula activa). | [Ver SQL](../../schema/stored-procedures/usp_validar_estudiante_grupo_exista_interno.sql) |
| [**Validar Estudiante Pertenece a Grupo de Sesión Interno**](internos/usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno.md) | Interno (Validación) | Valida que un estudiante cuente con matrícula activa en el grupo correspondiente a una sesión de clase. | [Ver SQL](../../schema/stored-procedures/usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno.sql) |
| [**Validar ID de Correlación Está Presente**](internos/usp_validar_id_correlacion_esta_presente_interno.md) | Interno (Validación) | Garantiza que el identificador de correlación esté presente y sea válido para asegurar la trazabilidad de la transacción. | [Ver SQL](../../schema/stored-procedures/usp_validar_id_correlacion_esta_presente_interno.sql) |
| [**Validar Sesión Exista por ID Interno**](internos/usp_validar_sesion_exista_por_id_interno.md) | Interno (Validación) | Valida la existencia, vigencia y actividad de una sesión de clase específica por su ID. | [Ver SQL](../../schema/stored-procedures/usp_validar_sesion_exista_por_id_interno.sql) |

---

Posibles procedimientos a agregar: 
- usp_registrar_docente_en_grupo_usuario_no_existente
- usp_registrar_grupo_docente_no_existente
- usp_registrar_