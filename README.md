# Gestión de Asistencias - Base de Datos (gestionasistenciadb) 🗄️

![DB Quality Gate CI/CD](https://github.com/johnjduque/gestion-asistencia-db/actions/workflows/ci.yml/badge.svg?branch=develop)

Este repositorio contiene el diseño lógico, la estructura y los objetos programables de la base de datos para el **Sistema de Gestión de Asistencias**. El entorno de desarrollo está completamente dockerizado para garantizar que todos los miembros del equipo trabajen sobre la misma versión del motor de bases de datos de forma idéntica.

---

## 🛠️ Stack Tecnológico
* **Motor:** SQL Server 2022+ (Compatibilidad Nivel 160)
* **Entorno Local:** Docker & Docker Desktop
* **IDE Recomendado:** VS Code / Antigravity IDE con extensión *SQL Server (mssql)* o Azure Data Studio / SSMS 21.
* **Control de Versiones:** Git + GitHub / Azure DevOps

---

## 📁 Arquitectura Universal del Esquema (`/schema`)

El proyecto utiliza un **enfoque modular por objetos**. En lugar de crear archivos de parches sueltos (`fix-*.sql`), cada objeto de la base de datos se mantiene en un archivo `.sql` individual bajo la carpeta `schema/`:

```text
/schema
├── /tables/              <-- Un archivo por cada Tabla (ej. Usuario.sql, Grupo.sql)
├── /functions/           <-- Un archivo por cada Función UFN (ej. ufn_validar_correo.sql)
├── /views/               <-- Un archivo por cada Vista (ej. uv_usuario.sql)
└── /stored-procedures/   <-- Un archivo por cada Procedimiento Almacenado (ej. usp_sincronizar_usuario_interno.sql)
```

### 💡 Flujo de Modificación
1. Edita directamente el archivo del objeto que necesites modificar (por ejemplo `schema/stored-procedures/usp_sincronizar_usuario_interno.sql`).
2. Ejecuta el script universal `.\deploy_schema.ps1` para compilar los cambios en tu entorno local.

---

## ⚙️ Guía de Despliegue y Pruebas Locales (Paso a Paso)

### 1. Prerrequisitos
* [Docker Desktop](https://www.docker.com/products/docker-desktop/) ejecutándose.

### 2. Levantar el Contenedor de SQL Server
Si aún no tienes el contenedor activo, créalo ejecutando el siguiente comando en PowerShell:

```powershell
docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=TuPasswordSeguro123" -p 1433:1433 --name sql_server_asistencias -d mcr.microsoft.com/mssql/server:2022-latest
```

---

## 🚀 Comandos de Despliegue y Pruebas

### 🔹 Desplegar todo el Esquema Modular (`deploy_schema.ps1`)
Para compilar y aplicar todas las tablas, funciones, vistas y procedimientos almacenados en la base de datos en Docker, ejecuta:

```powershell
.\deploy_schema.ps1
```

### 🔹 Ejecutar la Suite de Pruebas Automáticas (`test_suite.sql`)
Para validar los 6 caminos del orquestador (`usp_registrar_estudiante_en_grupo_usuario_no_existente`), ejecuta el siguiente comando en PowerShell:

```powershell
Get-Content -Path .\test_suite.sql -Raw | docker exec -i sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "TuPasswordSeguro123" -C -y 35 -Y 35
```

### 🔹 Reiniciar y Limpiar la Base de Datos desde Cero
Si deseas simular una instalación fresca y verificar el esquema completo:

```powershell
# 1. Recrear Base de Datos Vacía en Docker
docker exec -i sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "TuPasswordSeguro123" -C -d master -Q "ALTER DATABASE gestionasistenciadb SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE gestionasistenciadb; CREATE DATABASE gestionasistenciadb;"

# 2. Desplegar todo el esquema
.\deploy_schema.ps1

# 3. Correr Pruebas
Get-Content -Path .\test_suite.sql -Raw | docker exec -i sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "TuPasswordSeguro123" -C -y 35 -Y 35
```
