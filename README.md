# Gestión de Asistencias - Base de Datos (gestionasistenciadb) 🗄️

Este repositorio contiene el diseño lógico, la estructura y los objetos programables de la base de datos para el **Sistema de Gestión de Asistencias**. El entorno de desarrollo está completamente dockerizado para garantizar que todos los miembros del equipo trabajen sobre la misma versión del motor de bases de datos de forma idéntica.

## 🛠️ Stack Tecnológico
* **Motor:** SQL Server 2022+ (Compatibilidad Nivel 160)
* **Entorno Local:** Docker & Docker Desktop
* **IDE Recomendado:** SQL Server Management Studio (SSMS) 21 o Azure Data Studio
* **Control de Versiones:** Git + GitHub / Azure DevOps

---

## 🚀 Arquitectura y Componentes del Script

El archivo principal `gestionasistenciadb.sql` inicializa la base de datos completa, estructurada de la siguiente manera:

* **Estructura Base:** `32 Tablas` principales que gestionan el núcleo del negocio (ej. `Usuario`, `Docente`, `PlanEstudio`, `TipoIdentificacion`, `EstudianteGrupo`, etc.).
* **Capa de Abstracción:** `25 Vistas (Views)` que exponen la información de manera limpia (ej. `uv_usuario`, `uv_plan_estudio`, `uv_tipo_identificacion`, etc.).
* **Lógica de Negocio:** `6 Procedimientos Almacenados (Stored Procedures)` para operaciones transaccionales y validaciones complejas (ej. `usp_sincronizar_estudiante_interno`, `usp_validar_estudiante_exista_por_id`, entre otros).
* **Funciones Auxiliares:** `4 Funciones (UFN)` enfocadas en el manejo robusto de excepciones y mensajería estructurada (ej. `ufn_obtener_detalle_error`, `ufn_obtener_mensaje`).

---

## ⚙️ Guía de Despliegue Local (Paso a Paso)

Sigue estas instrucciones para clonar el repositorio y levantar la base de datos en tu entorno local.

### 1. Prerrequisitos
Asegúrate de tener instalado y ejecutándose:
* [Docker Desktop](https://www.docker.com/products/docker-desktop/)
* [SSMS 21](https://learn.microsoft.com/sql/ssms/download-sql-server-management-studio-ssms) o VS Code con la extensión *SQL Server (mssql)*.

### 2. Levantar el Contenedor de SQL Server
Si aún no tienes un contenedor activo, puedes crear uno ejecutando el siguiente comando en tu terminal (reemplaza `TuPasswordSeguro123` por tu contraseña local):

```bash
docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=TuPasswordSeguro123" \
   -p 1433:1433 --name sql_server_asistencias \
   -d [mcr.microsoft.com/mssql/server:2022-latest](https://mcr.microsoft.com/mssql/server:2022-latest)
