param (
    [string]$ContainerName = 'sql_server_asistencias',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# CULM-001 C.1 (CONTRACT §2.13.1): casos que requieren sqlcmd con variables y :r de migrations/ (C-DB-60, migracion 19) o varias
# conexiones concurrentes (C-DB-46 dos resolutores, C-DB-50 motor, resolucion, cierre). Cada caso deja la BD como estaba
# (transaccion revertida o fixture propio con limpieza). Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo>.
$ErrorActionPreference = 'Stop'
if (-not $Password) {
    $envFile = Join-Path (Split-Path -Parent $PSScriptRoot) '.env'
    if (Test-Path $envFile) { Get-Content $envFile | ForEach-Object { if ($_ -match '^\s*SQL_CONTAINER_PASSWORD=(.*)$') { $Password = $matches[1].Trim() } } }
}
if (-not $Password) { throw 'SQL password is required for test_culm001_c.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/culm001_c_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$null = & docker cp (Join-Path $dbRoot 'migrations/19_culm001_c_cancelacion_inasistencia_up.sql') "${ContainerName}:$remoteDir/migrations/" 2>&1
$null = & docker cp (Join-Path $dbRoot 'migrations/19_culm001_c_cancelacion_inasistencia_down.sql') "${ContainerName}:$remoteDir/migrations/" 2>&1
$null = & docker cp (Join-Path $PSScriptRoot 'test_culm001_c_migraciones.sql') "${ContainerName}:$remoteDir/test_culm001_c_migraciones.sql" 2>&1
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1
$failures = @()

function Get-NormalizedHashNoUsado([string]$text) {
    $stripped = ($text -replace "[\r\n\t ]", '')
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($stripped)
    return ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes))).Replace('-', '')
}

# ---------------------------------------------------------------------------------------------------------------
# C-DB-60: migracion 19 up -> up, up -> down -> up (transaccion revertida) y SP restaurados con el texto literal del down
# ---------------------------------------------------------------------------------------------------------------
try {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-b', '-h', '-1', '-W', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/test_culm001_c_migraciones.sql")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    $text = $lines -join "`n"
    if ($LASTEXITCODE -ne 0 -or $text -notmatch 'TEST_PASS:CULM001_C_MIG_19_UP_DOWN_UP') {
        $failures += 'C-DB-60'
        Write-Output "TEST FAILED: C-DB-60 migracion 19: $(($lines | Select-Object -Last 4) -join ' | ')"
    }
    else {
        Write-Output 'TEST_PASS:CULM001_C_MIG_19_UP_DOWN_UP'
    }
}
catch { $failures += 'C-DB-60'; Write-Output "TEST FAILED: C-DB-60 $($_.Exception.Message)" }

$null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1
if ($failures.Count -gt 0) { exit 1 }
