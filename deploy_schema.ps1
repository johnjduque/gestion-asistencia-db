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

# 3. Aplicar Vistas (Optimizadas dinámicamente)
Write-Host "`nAplicando Vistas (Resolviendo dependencias dinámicamente)..." -ForegroundColor Yellow
$views = Get-ChildItem -Path "$schemaDir\views" -Filter "*.sql" -Recurse
$pendingViews = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($v in $views) { $pendingViews.Add($v) }

$maxPasses = 15
$pass = 1
$progressMade = $true

while ($pendingViews.Count -gt 0 -and $progressMade -and $pass -le $maxPasses) {
    $progressMade = $false
    $failedThisPass = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($viewFile in $pendingViews) {
        $sqlResult = Get-Content -Path $viewFile.FullName -Raw | docker exec -i $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$Password" -C 2>&1
        if ($sqlResult -match "Msg \d+, Level \d+") {
            $failedThisPass.Add($viewFile)
        } else {
            $progressMade = $true
        }
    }
    $pendingViews = $failedThisPass
    $pass++
}

if ($pendingViews.Count -gt 0) {
    Write-Host "`n[ERROR] No se pudieron aplicar las siguientes vistas debido a errores reales o dependencias circulares:" -ForegroundColor Red
    foreach ($viewFile in $pendingViews) {
        Write-Host "  - $($viewFile.Name)" -ForegroundColor Red
        Get-Content -Path $viewFile.FullName -Raw | docker exec -i $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$Password" -C
    }
} else {
    Write-Host "¡Todas las vistas aplicadas correctamente!" -ForegroundColor Green
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