# Gestión de Asistencias - Base de Datos (gestionasistenciadb) 🗄️

Este repositorio contiene el diseño lógico, la estructura y los objetos programables de la base de datos para el **Sistema de Gestión de Asistencias**. El entorno de desarrollo está completamente dockerizado para garantizar que todos los miembros del equipo trabajen sobre la misma versión del motor de bases de datos de forma idéntica.

## 🛠️ Stack Tecnológico
* **Motor:** SQL Server 2022+ (Compatibilidad Nivel 160)
* **Entorno Local:** Docker & Docker Desktop
* **IDE Recomendado:** SQL Server Management Studio (SSMS) 21 o Azure Data Studio
* **Control de Versiones:** Git + GitHub / Azure DevOps

---

## 🚀 Metodología de Migraciones (Estructura del Proyecto)

Para evitar conflictos en Git y garantizar un orden estricto de despliegue, el proyecto sigue un **enfoque basado en la organización de scripts** bajo la carpeta `migrations/`.

Los archivos ubicados dentro de la carpeta `migrations/` son:

* **Estructura Base (`gestionasistenciadb.sql`):** Inicializa las tablas base, tipos, vistas y procedimientos iniciales del sistema.
* **Ajustes y Parches (`fix-ajuste-*.sql`):** Modificaciones incrementales aplicadas sobre los procedimientos almacenados y la lógica de negocio.

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
   -d mcr.microsoft.com/mssql/server:2022-latest
```

### 3. Aplicar las Migraciones en Orden
Conéctate a tu servidor local de base de datos y ejecuta los scripts ubicados dentro de la carpeta `migrations/` en orden cronológico para garantizar que no existan errores de dependencias de objetos.
