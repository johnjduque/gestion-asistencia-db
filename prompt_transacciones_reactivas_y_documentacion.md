Actúa como Arquitecto de Base de Datos Senior experto en T-SQL, Diseño Orientado al Dominio (DDD) y Análisis de Requerimientos.

Tu tarea es auditar, refactorizar y documentar los procedimientos almacenados que generaste recientemente, asegurando que cumplan con el paradigma de "Transacciones Reactivas" y que estén 100% alineados con la documentación oficial del proyecto.

📂 CONTEXTO Y DOCUMENTACIÓN
Por favor, lee y analiza los siguientes archivos del entorno para entender las entidades, las historias y el alcance:
- @ModeloEntidadRelacion.md
- @6_Entregable.md
- @Plan_de_Trabajo_Historias_de_Usuario.md
- @transaccion-procedimiento.md
- @image_d84b62.png (Toma esta imagen como la meta visual de lo que queremos lograr al documentar).

⚙️ EL PARADIGMA: "TRANSACCIONES REACTIVAS" Y DELEGACIÓN
En este proyecto, NO creamos registros de forma aislada o "por crear". Toda transacción es reactiva y orientada a cumplir un flujo de negocio completo. 

Toma como estándar de oro el procedimiento `usp_registrar_estudiante_en_grupo_usuario_no_existente`. 
* Entradas: Recibe datos biográficos, credenciales y los identificadores clave (`@idTipoIdIdentificacion`, `@numeroIdentificacion`, `@correo`, `@idGrupo`, `@idCorrelacion`, etc.).
* Salidas: Retorna siempre un resultset estandarizado (`idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`).
* Lógica Reactiva (Reglas de Negocio): Para poder matricular al estudiante, este orquestador garantiza el cumplimiento de 12 reglas:
  1. Que el estudiante exista.
  2. Que el estudiante esté activo.
  3. Si el estudiante existe y está activo -> SE ACTUALIZA (Upsert).
  4. Si el estudiante no existe -> SE CREA.
  5. Se asocia el usuario a la tabla/rol estudiante.
  6. Se inscribe el estudiante al grupo.
  7. Que el grupo exista.
  8. Que el grupo esté habilitado para el semestre.
  9. Que el grupo no haya superado el tamaño máximo.
  10. Que el horario del grupo no se cruce con otro del mismo estudiante.
  11. Que el estudiante no esté ya matriculado en ese mismo grupo.
  12. Vinculación del estudiante al programa académico del grupo.

Aunque el orquestador principal NO programa físicamente todas estas 12 reglas en su propio cuerpo, su responsabilidad es asegurar que TODO el flujo se cumpla delegando de forma reactiva en otros procedimientos internos (ej. validaciones de cruce de horarios, validaciones de cupo, sincronización de usuario). 

📝 AUDITORÍA DE DOCUMENTACIÓN Y ALINEACIÓN (¡NUEVA REGLA CRÍTICA!)
Antes de modificar o generar cualquier línea de código, debes realizar una auditoría documental:
1. Verifica si las transacciones que codificaste ya se encuentran documentadas en el archivo `@transaccion-procedimiento.md`.
2. Si ya están documentadas: Compara la documentación con tu código. ¿El código cumple estrictamente con las reglas allí descritas? Si no es así, corrige el código para que obedezca a la documentación, o indícame si la documentación necesita un ajuste porque falta una regla de negocio vital.
3. Si NO están documentadas: Debes generar la documentación técnica para esos nuevos procedimientos utilizando el mismo modelo de `@transaccion-procedimiento.md`.

🎯 ESTRUCTURA OBLIGATORIA PARA LA DOCUMENTACIÓN:
Para poder generar a futuro diagramas de bloque precisos (como el de la imagen de referencia `image_d84b62.png`), TODA documentación que generes o valides debe contener obligatoriamente estos 3 elementos:
- **Entradas:** Lista de parámetros de entrada (ej. `@idEstudiante`, `@idGrupo`, `@idCorrelacion`).
- **Salidas:** El resultset estándar unificado (`idCorrelacion`, `mensajeUsuarioResultado`, `mensajeTecnicoResultado`, `estadoResultado`).
- **Reglas de Negocio / Validaciones:** Una lista numerada, clara y secuencial con todas las condiciones que el procedimiento (o sus internos) deben validar antes de completar la transacción (ej. 1. Que el grupo exista, 2. Que el grupo no supere el tamaño máximo, 3. Que no haya cruce de horarios, etc.).

🚀 INSTRUCCIONES DE EJECUCIÓN:
1. Analiza tus procedimientos previos bajo la lupa de "Transacciones Reactivas" y refactoriza los que sean simples CRUDs planos.
2. Cruza tus procedimientos con `@transaccion-procedimiento.md`.
3. Entrégame tu diagnóstico: ¿Qué procedimientos estaban desalineados con la documentación?
4. Entrégame el Código T-SQL refactorizado.
5. Entrégame la Documentación en formato Markdown (Entradas, Salidas, Reglas de Negocio) para aquellos procedimientos que no estaban documentados, lista para ser añadida a `@transaccion-procedimiento.md`.
