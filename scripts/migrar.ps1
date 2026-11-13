# VAL F12-12 (oleada 3): tarea de migracion (12-factor, procesos administrativos).
#
# Aplica las migraciones de migrations/ en orden y las registra en dbo.MigracionAplicada (version, nombre, archivo, checksum,
# modo, aplicadaEnUtc, aplicadaPor, duracionMs). Una migracion ya registrada se salta; si su archivo cambio despues de aplicado
# (checksum distinto) la tarea se detiene sin aplicar nada (deriva). Ver docs/work-items/VAL-oleada3-bd-pendientes/PLAN.md.
#
#   ./scripts/migrar.ps1                       # -Modo Estado: solo lectura; lista APLICADA / BASELINE / PENDIENTE / DERIVA
#   ./scripts/migrar.ps1 -Modo Aplicar         # aplica las pendientes en orden y registra cada una (modo APLICADA)
#   ./scripts/migrar.ps1 -Modo Baseline        # registra sin ejecutar (modo BASELINE) las migraciones hasta -HastaVersion;
#                                              # para una base creada con deploy_schema.ps1, que ya contiene su efecto
#
# Migraciones administradas: archivos NN_nombre_up.sql y los antiguos de un solo archivo NN_nombre.sql con NN >= -VersionMinima
# (5 por defecto). Los *_down.sql no se aplican aqui (reversion manual: ejecutar el down y borrar la fila de MigracionAplicada).
# 01..04 son cargas iniciales y alineaciones anteriores al esquema por objeto; deploy_schema.ps1 y schema/seed/ las reemplazan.
# Orden: version numerica y luego nombre. Las migraciones usan sqlcmd con :on error exit y algunas :r $(MIGDIR)/../schema/...,
# por eso se copian migrations/ y schema/ al contenedor y se pasa MIGDIR.
#
# Credenciales: igual que deploy_schema.ps1 y test_summary.ps1 (-Password, o SQL_CONTAINER_PASSWORD / MSSQL_SA_PASSWORD desde
# .env o el entorno). Nunca se imprimen.
# Salida estable: MIGRAR_<ESTADO> <nombre> por migracion y MIGRAR_RESUMEN ... al final. Codigo 0 si todo bien; 1 si hay deriva,
# una migracion falla o la base no es la esperada.
# -Database y -MigrationsDir existen para la prueba de la tarea (test/test_val_migrar.ps1, base temporal); en uso normal se
# dejan por defecto (gestionasistenciadb y migrations/).
param (
    [ValidateSet('Estado', 'Aplicar', 'Baseline')][string]$Modo = 'Estado',
    [string]$ContainerName,
    [string]$Password,
    [string]$Database = 'gestionasistenciadb',
    [string]$MigrationsDir,
    [int]$VersionMinima = 5,
    [int]$HastaVersion = [int]::MaxValue
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $MigrationsDir) { $MigrationsDir = Join-Path $root 'migrations' }

$envFile = Join-Path $root '.env'
if ((-not $Password -or -not $ContainerName) -and (Test-Path $envFile)) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $parts = $line.Split('=', 2)
            [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim())
        }
    }
}
if (-not $ContainerName) { $ContainerName = if ($env:SQL_CONTAINER_NAME) { $env:SQL_CONTAINER_NAME } else { 'sql_server_asistencias' } }
if (-not $Password) { $Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } elseif ($env:MSSQL_SA_PASSWORD) { $env:MSSQL_SA_PASSWORD } else { $null } }
if (-not $Password) { throw "SQL password is required. Create a local '.env' file from '.env.template', set SQL_CONTAINER_PASSWORD/MSSQL_SA_PASSWORD, or pass -Password." }
if ($Password -ceq 'CHANGE_ME') { throw "SQL password is still the 'CHANGE_ME' placeholder." }
if ($Database -notmatch '^[A-Za-z0-9_]+$') { throw "Nombre de base invalido: $Database" }

function Get-NormalizedSha256([string]$Path) {
    # Igual que scripts/freeze-manifest.ps1: SHA-256 del contenido con CRLF normalizado a LF.
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $ms = [System.IO.MemoryStream]::new()
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 13 -and ($i + 1) -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { continue }
        $ms.WriteByte($bytes[$i])
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return ([System.BitConverter]::ToString($sha.ComputeHash($ms.ToArray())).Replace('-', '')).ToLowerInvariant()
}

function Invoke-SqlQuery([string]$Query) {
    $out = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d $Database -U sa -P $Password -C -b -h -1 -W -s '|' -Q "SET NOCOUNT ON; $Query" 2>&1 |
        ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    if ($LASTEXITCODE -ne 0) { throw "Consulta fallida: $(($out | Select-Object -Last 3) -join ' | ')" }
    return , $out
}

# 1. Inventario de migraciones administradas
$migraciones = @(Get-ChildItem -Path $MigrationsDir -Filter '*.sql' -File | ForEach-Object {
    if ($_.Name -match '_down\.sql$') { return }
    if ($_.Name -notmatch '^(\d+)_([a-z0-9_]+?)(_up)?\.sql$') { return }
    $version = [int]$Matches[1]
    if ($version -lt $VersionMinima) { return }
    $nombre = $_.Name -replace '(_up)?\.sql$', ''
    [pscustomobject]@{ Version = $version; Nombre = $nombre; Archivo = $_.Name; Ruta = $_.FullName; Checksum = (Get-NormalizedSha256 $_.FullName) }
} | Sort-Object Version, Nombre)
$duplicadas = @($migraciones | Group-Object Nombre | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
if ($duplicadas.Count) { throw "Migraciones con el mismo nombre (archivo up y archivo unico a la vez): $($duplicadas -join ', ')" }

# 2. Base esperada y registro
$precheck = (Invoke-SqlQuery "SELECT CONCAT(DB_NAME(), '|', CONVERT(varchar(80), SERVERPROPERTY('Edition')));") -join ''
if ($precheck -notmatch "^$Database\|") { throw "BLOCKED - base inesperada: $precheck" }

function Initialize-Registro {
    # Crea dbo.MigracionAplicada con el DDL de schema/tables/MigracionAplicada.sql (idempotente) en la base destino.
    $ddl = [System.IO.File]::ReadAllText((Join-Path $root 'schema/tables/MigracionAplicada.sql'))
    $ddl = $ddl -replace '(?im)^\s*USE\s+\[gestionasistenciadb\];\s*$', ''
    $tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $local = Join-Path ([System.IO.Path]::GetTempPath()) "migracion_aplicada_$tag.sql"
    [System.IO.File]::WriteAllText($local, $ddl, [System.Text.UTF8Encoding]::new($false))
    try {
        $null = & docker cp $local "${ContainerName}:/tmp/migracion_aplicada_$tag.sql" 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo copiar el DDL del registro al contenedor.' }
        $out = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d $Database -U sa -P $Password -C -b -i "/tmp/migracion_aplicada_$tag.sql" 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "No se pudo crear dbo.MigracionAplicada: $(($out | Select-Object -Last 3) -join ' | ')" }
    }
    finally {
        Remove-Item $local -ErrorAction SilentlyContinue
        $null = & docker exec -u 0 $ContainerName rm -f "/tmp/migracion_aplicada_$tag.sql" 2>&1
    }
}

$existeRegistro = ((Invoke-SqlQuery "SELECT IIF(OBJECT_ID('dbo.MigracionAplicada', 'U') IS NULL, 0, 1);") -join '') -eq '1'
if ($Modo -ne 'Estado' -and -not $existeRegistro) { Initialize-Registro; $existeRegistro = $true }
$registradas = @{}
if ($existeRegistro) {
    foreach ($fila in (Invoke-SqlQuery 'SELECT CONCAT(nombre, ''|'', checksumSha256, ''|'', modo) FROM dbo.MigracionAplicada ORDER BY version, nombre;')) {
        $p = $fila.Split('|')
        if ($p.Count -eq 3) { $registradas[$p[0]] = [pscustomobject]@{ Checksum = $p[1]; Modo = $p[2] } }
    }
}
else { Write-Host 'MIGRAR_REGISTRO_AUSENTE dbo.MigracionAplicada (se crea con -Modo Aplicar o -Modo Baseline, o con deploy_schema.ps1)' }

# 3. Clasificacion
$deriva = @(); $pendientes = @()
foreach ($m in $migraciones) {
    if ($registradas.ContainsKey($m.Nombre)) {
        $r = $registradas[$m.Nombre]
        if ($r.Checksum -ne $m.Checksum) { $deriva += $m; Write-Host "MIGRAR_DERIVA $($m.Nombre) registrado=$($r.Checksum.Substring(0, 12)) archivo=$($m.Checksum.Substring(0, 12))" }
        else { Write-Host "MIGRAR_$($r.Modo) $($m.Nombre)" }
    }
    else { $pendientes += $m; Write-Host "MIGRAR_PENDIENTE $($m.Nombre)" }
}
$sinArchivo = @($registradas.Keys | Where-Object { $_ -notin $migraciones.Nombre })
foreach ($n in $sinArchivo) { Write-Host "MIGRAR_REGISTRADA_SIN_ARCHIVO $n" }

if ($deriva.Count) {
    Write-Host "MIGRAR_RESUMEN modo=$Modo total=$($migraciones.Count) registradas=$($registradas.Count) pendientes=$($pendientes.Count) deriva=$($deriva.Count) aplicadas=0"
    Write-Host 'MIGRAR_FALLO deriva: un archivo ya aplicado cambio. No se aplica nada; revisar y corregir el registro a mano.'
    exit 1
}

function Add-Registro($m, [string]$modoRegistro, $duracionMs) {
    if ($m.Nombre -notmatch '^[a-z0-9_]+$' -or $m.Archivo -notmatch '^[a-z0-9_]+\.sql$' -or $m.Checksum -notmatch '^[0-9a-f]{64}$') { throw "Valores no validos para registrar $($m.Nombre)" }
    $dur = if ($null -eq $duracionMs) { 'NULL' } else { [string][int]$duracionMs }
    $null = Invoke-SqlQuery ("INSERT INTO dbo.MigracionAplicada (version, nombre, archivo, checksumSha256, modo, duracionMs) " +
        "VALUES ($($m.Version), '$($m.Nombre)', '$($m.Archivo)', '$($m.Checksum)', '$modoRegistro', $dur);")
}

$aplicadas = 0
if ($Modo -eq 'Baseline') {
    foreach ($m in @($pendientes | Where-Object { $_.Version -le $HastaVersion })) {
        Add-Registro $m 'BASELINE' $null
        $aplicadas++
        Write-Host "MIGRAR_REGISTRADA_BASELINE $($m.Nombre)"
    }
}
elseif ($Modo -eq 'Aplicar' -and $pendientes.Count) {
    $tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $remote = "/tmp/migrar_$tag"
    try {
        $null = & docker exec -u 0 $ContainerName mkdir -p "$remote/migrations" "$remote/schema" 2>&1
        $null = & docker cp (Join-Path $MigrationsDir '.') "${ContainerName}:$remote/migrations" 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo copiar migrations/ al contenedor.' }
        $null = & docker cp (Join-Path $root 'schema/.') "${ContainerName}:$remote/schema" 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo copiar schema/ al contenedor.' }
        $null = & docker exec -u 0 $ContainerName chmod -R a+rX $remote 2>&1
        foreach ($m in $pendientes) {
            $reloj = [System.Diagnostics.Stopwatch]::StartNew()
            $out = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d $Database -U sa -P $Password -C -b -I -t 1800 `
                    -v "MIGDIR=$remote/migrations" -i "$remote/migrations/$($m.Archivo)" 2>&1 | ForEach-Object { "$_" })
            $rc = $LASTEXITCODE
            $reloj.Stop()
            if ($rc -ne 0) {
                Write-Host "MIGRAR_FALLO $($m.Nombre) rc=$rc"
                $out | Select-Object -Last 6 | ForEach-Object { Write-Host "  $_" }
                Write-Host "MIGRAR_RESUMEN modo=$Modo total=$($migraciones.Count) registradas=$($registradas.Count + $aplicadas) pendientes=$($pendientes.Count - $aplicadas) deriva=0 aplicadas=$aplicadas"
                exit 1
            }
            Add-Registro $m 'APLICADA' $reloj.ElapsedMilliseconds
            $aplicadas++
            Write-Host "MIGRAR_APLICADA_AHORA $($m.Nombre) ms=$($reloj.ElapsedMilliseconds)"
        }
    }
    finally { $null = & docker exec -u 0 $ContainerName rm -rf $remote 2>&1 }
}

$restantes = if ($Modo -eq 'Estado') { $pendientes.Count } else { $pendientes.Count - $aplicadas }
Write-Host "MIGRAR_RESUMEN modo=$Modo total=$($migraciones.Count) registradas=$($registradas.Count + $aplicadas) pendientes=$restantes deriva=0 aplicadas=$aplicadas"
exit 0
