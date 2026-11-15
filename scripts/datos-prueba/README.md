# Datos de prueba variados (laboratorio local)

Conjunto consolidado para probar todos los roles: 73 usuarios (1 administrador, 5 decanos, 10 coordinadores, 16
asignaciones de docente, 42 estudiantes), 4 facultades, 7 programas, 22 asignaturas (9 compartidas), 40 grupos
(34 en 2026-2 y 6 en 2026-1) con horarios sin cruces, historial de asistencia hasta la fecha de carga, alertas,
revisiones de cancelación, reclamos, un retiro y solicitudes de sesión. Directorio de usuarios: [USUARIOS.md](USUARIOS.md).

## Recrear desde cero

1. Respaldar la base y detener el backend (`docker stop asis-app-backend`): con él conectado no se puede borrar la base.
2. Borrar `gestionasistenciadb` y desplegar el esquema: `.\deploy_schema.ps1 -ContainerName sql_server_asistencias -Password <sa>`.
3. Ejecutar en orden, con `sqlcmd -f 65001`: `01_estructura.sql`, `02_sesiones.sql`, `03_asistencia.sql`, `04_flujos.sql`.
4. Arrancar el backend (`docker start asis-app-backend`).
5. Seguridad (desde `GestioAsistenciaBackend`, con el Python de Windows y la variable `ASISTENCIAS_DATASET_PASSWORD`
   con la contraseña común de `AGENTS.md`, sección 7):
   `python -X utf8 infra/security-baseline/scripts/provision_asistencias.py dataset-users <ruta>/usuarios_datos_prueba.json`

Los `.sql`, `usuarios_datos_prueba.json` y `USUARIOS.md` se generan con `python -X utf8 generar_datos_prueba.py`
(identificadores deterministas). `festivos.txt` son los festivos nacionales 2026-2027 que carga el backend.

## Notas

- El historial de 2026-2 depende de la fecha de carga: se registran las sesiones vencidas a ese momento. La última
  sesión de *Gestión de la Calidad* y de *Mercadeo* queda sin toma a propósito (cumplimiento del docente).
- Las acciones hechas aquí con los SP no generan correos (el backend los encola al actuar desde la aplicación).
- 2026-1 terminó sin cierre masivo: sirve para probar el cierre (Alejandro Pineda supera el 20 % y quedaría en CI).
