param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# HU074: migracion 58 up -> down -> up con sqlcmd, y :r de migrations/.
#   HU074_MIG_UP_DOWN_UP     test_hu074_migracion.sql (transaccion revertida)
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_hu074_migracion.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/hu074_mig_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$failures = @()
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$copy = @(& docker cp (Join-Path $dbRoot 'migrations/.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy migrations: $($copy -join '; ')" }
$copy = @(& docker cp (Join-Path $PSScriptRoot 'test_hu074_migracion.sql') "${ContainerName}:$remoteDir/test_hu074_migracion.sql" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy test_hu074_migracion.sql: $($copy -join '; ')" }
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

function Invoke-Sqlcmd-File([string]$file) {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/$file")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines; Text = ($lines -join "`n") }
}

try {
    $r = Invoke-Sqlcmd-File 'test_hu074_migracion.sql'
    $missing = @(@('HU074_MIG_UP1_OK', 'HU074_MIG_DOWN_OK', 'HU074_MIG_UP2_OK', 'HU074_MIG_ROLLBACK_OK') | Where-Object { $r.Text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $r.ExitCode -eq 0) { Write-Host 'TEST_PASS:HU074_MIG_UP_DOWN_UP' }
    else { $failures += "HU074_MIG_UP_DOWN_UP missing $($missing -join ',') (exit $($r.ExitCode)): $(($r.Lines | Where-Object { $_ -match 'Msg |HU074_MIG|TEST' }) -join ' / ')" }
}
catch { $failures += "HU074_MIG_RUNNER $($_.Exception.Message)" }
finally { $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1 }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "TEST FAILED: $_" }
    exit 1
}
exit 0
