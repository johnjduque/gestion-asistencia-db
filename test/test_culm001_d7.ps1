param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# CULM-001 D.7 (CONTRACT D §8.2 D7-03): up -> down -> up de la migracion 26 (necesita sqlcmd con variables y :r de migrations/).
#   CULM001_D7_03_UP_DOWN_UP     test_culm001_d7_migraciones.sql (transaccion revertida)
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_culm001_d7.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/culm001_d7_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$failures = @()
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$copy = @(& docker cp (Join-Path $dbRoot 'migrations/.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy migrations: $($copy -join '; ')" }
$copy = @(& docker cp (Join-Path $PSScriptRoot 'test_culm001_d7_migraciones.sql') "${ContainerName}:$remoteDir/test_culm001_d7_migraciones.sql" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy test_culm001_d7_migraciones.sql: $($copy -join '; ')" }
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

try {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/test_culm001_d7_migraciones.sql")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    $exit = $LASTEXITCODE
    $text = ($lines -join "`n")
    $missing = @(@('MIG_D7_UP1_OK', 'MIG_D7_UP2_OK', 'MIG_D7_DOWN_OK', 'MIG_D7_DOWN_UP_OK', 'MIG_D7_ROLLBACK_OK') | Where-Object { $text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $exit -eq 0) { Write-Host 'TEST_PASS:CULM001_D7_03_UP_DOWN_UP' }
    else { $failures += "CULM001_D7_03_UP_DOWN_UP missing $($missing -join ',') (exit $exit): $(($lines | Where-Object { $_ -match 'Msg |MIG_|TEST' }) -join ' / ')" }
}
catch { $failures += "CULM001_D7_RUNNER $($_.Exception.Message)" }
finally { $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1 }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "TEST FAILED: $_" }
    exit 1
}
exit 0
