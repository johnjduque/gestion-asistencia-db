param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# Migracion 77 (parametros tecnicos no editables) up -> down -> up con sqlcmd, y :r de migrations/.
#   PARAM_MIG77_UP_DOWN_UP      test_param_migracion_77.sql (transaccion revertida)
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_param_migracion_77.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/param_mig77_mig_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$failures = @()
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$copy = @(& docker cp (Join-Path $dbRoot 'migrations/.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy migrations: $($copy -join '; ')" }
$copy = @(& docker cp (Join-Path $PSScriptRoot 'test_param_migracion_77.sql') "${ContainerName}:$remoteDir/test_param_migracion_77.sql" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy test_param_migracion_77.sql: $($copy -join '; ')" }
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

function Invoke-Sqlcmd-File([string]$file) {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/$file")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines; Text = ($lines -join "`n") }
}

try {
    $r = Invoke-Sqlcmd-File 'test_param_migracion_77.sql'
    $missing = @(@('PARAM_MIG77_UP1_OK', 'PARAM_MIG77_DOWN_OK', 'PARAM_MIG77_UP2_OK', 'PARAM_MIG77_ROLLBACK_OK') | Where-Object { $r.Text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $r.ExitCode -eq 0) { Write-Host 'TEST_PASS:PARAM_MIG77_UP_DOWN_UP' }
    else { $failures += "PARAM_MIG77_UP_DOWN_UP missing $($missing -join ',') (exit $($r.ExitCode)): $(($r.Lines | Where-Object { $_ -match 'Msg |PARAM_MIG77|TEST' }) -join ' / ')" }
}
catch { $failures += "PARAM_MIG77_RUNNER $($_.Exception.Message)" }
finally { $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1 }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "TEST FAILED: $_" }
    exit 1
}
exit 0
