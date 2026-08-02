# Script para desplegar la arquitectura modularizada /schema en Docker (Con soporte para subcarpetas)
param (
    [string]$ContainerName = "sql_server_asistencias",
    [string]$Password = "TuPasswordSeguro123"
)

Write-Host "Iniciando despliegue de arquitectura por objeto (/schema)..." -ForegroundColor Cyan

$schemaDir = Join-Path $PSScriptRoot "schema"

# 0. Asegurar que la base de datos existe
Write-Host "`nAsegurando base de datos 'gestionasistenciadb'..." -ForegroundColor Yellow
docker exec -i $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$Password" -C -Q "IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'gestionasistenciadb') CREATE DATABASE gestionasistenciadb;"

# 1. Aplicar Tablas
Write-Host "`nAplicando Tablas..." -ForegroundColor Yellow
Get-ChildItem -Path "$schemaDir\tables" -Filter "*.sql" -Recurse | Sort-Object Name | ForEach-Object {
    Get-Content -Path $_.FullName -Raw | docker exec -i $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$Password" -C
}

# 2. Aplicar Funciones
Write-Host "`nAplicando Funciones..." -ForegroundColor Yellow
Get-ChildItem -Path "$schemaDir\functions" -Filter "*.sql" -Recurse | Sort-Object Name | ForEach-Object {
    Get-Content -Path $_.FullName -Raw | docker exec -i $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$Password" -C
}

# 3. Aplicar Vistas (Doble pasada por dependencias)
Write-Host "`nAplicando Vistas (Ordenando dependencias)..." -ForegroundColor Yellow
1..2 | ForEach-Object {
    Get-ChildItem -Path "$schemaDir\views" -Filter "*.sql" -Recurse | Sort-Object Name | ForEach-Object {
        Get-Content -Path $_.FullName -Raw | docker exec -i $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$Password" -C
    }
}

# 4. Aplicar Procedimientos Almacenados (soporta internos, externos, etc.)
Write-Host "`nAplicando Procedimientos Almacenados..." -ForegroundColor Yellow
Get-ChildItem -Path "$schemaDir\stored-procedures" -Filter "*.sql" -Recurse | Sort-Object Name | ForEach-Object {
    Write-Host "Ejecutando: $($_.Name)" -ForegroundColor Gray
    Get-Content -Path $_.FullName -Raw | docker exec -i $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$Password" -C
}

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "¡Despliegue del esquema por objeto completado con éxito!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green