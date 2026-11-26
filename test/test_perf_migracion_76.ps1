param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# SKILLS-BD lote 16: migracion 76 (indice cubriente de DetalleAsistencia) up -> down -> up con sqlcmd, y :r de migrations/, y las
# pistas de rendimiento de los KPI y del registro por QR.
#   PERF_HINTS_KPI              test_perf_migracion_76.sql (pistas en sus SP)
#   PERF_MIG76_UP_DOWN_UP       test_perf_migracion_76.sql (transaccion revertida)
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_perf_migracion_76.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/perf_mig76_mig_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$failures = @()
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$copy = @(& docker cp (Join-Path $dbRoot 'migrations/.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy migrations: $($copy -join '; ')" }
$copy = @(& docker cp (Join-Path $PSScriptRoot 'test_perf_migracion_76.sql') "${ContainerName}:$remoteDir/test_perf_migracion_76.sql" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy test_perf_migracion_76.sql: $($copy -join '; ')" }
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

function Invoke-Sqlcmd-File([string]$file) {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/$file")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines; Text = ($lines -join "`n") }
}

try {
    $r = Invoke-Sqlcmd-File 'test_perf_migracion_76.sql'
    $detalle = ($r.Lines | Where-Object { $_ -match 'Msg |PERF_|TEST' }) -join ' / '
    if ($r.Text -match '(?m)^PERF_HINTS_OK$') { Write-Host 'TEST_PASS:PERF_HINTS_KPI' }
    else { $failures += "PERF_HINTS_KPI (exit $($r.ExitCode)): $detalle" }
    $missing = @(@('PERF_MIG76_UP1_OK', 'PERF_MIG76_DOWN_OK', 'PERF_MIG76_UP2_OK', 'PERF_MIG76_ROLLBACK_OK') | Where-Object { $r.Text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $r.ExitCode -eq 0) { Write-Host 'TEST_PASS:PERF_MIG76_UP_DOWN_UP' }
    else { $failures += "PERF_MIG76_UP_DOWN_UP missing $($missing -join ',') (exit $($r.ExitCode)): $detalle" }
}
catch { $failures += "PERF_MIG76_RUNNER $($_.Exception.Message)" }
finally { $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1 }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "TEST FAILED: $_" }
    exit 1
}
exit 0
