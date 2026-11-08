param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# CULM-001 D.9-a (CONTRACT §11.2, D-RB-03): migracion 28 up->down->up con sqlcmd, variables y :r de migrations/.
#   CULM001_D9_MIG_UP_DOWN_UP     test_culm001_d9_migraciones.sql (transaccion revertida)
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_culm001_d9.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/culm001_d9_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$failures = @()
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$copy = @(& docker cp (Join-Path $dbRoot 'migrations/.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy migrations: $($copy -join '; ')" }
foreach ($f in @('test_culm001_d9_migraciones.sql')) {
    $copy = @(& docker cp (Join-Path $PSScriptRoot $f) "${ContainerName}:$remoteDir/$f" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "could not copy ${f}: $($copy -join '; ')" }
}
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

function Invoke-Sqlcmd-File([string]$file) {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/$file")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines; Text = ($lines -join "`n") }
}

try {
    $r = Invoke-Sqlcmd-File 'test_culm001_d9_migraciones.sql'
    $missing = @(@('MIG_D9_DOWN_OK', 'MIG_D9_UP1_OK', 'MIG_D9_UP2_OK', 'MIG_D9_DOWN_UP_OK', 'MIG_D9_ROLLBACK_OK') | Where-Object { $r.Text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $r.ExitCode -eq 0) { Write-Host 'TEST_PASS:CULM001_D9_MIG_UP_DOWN_UP' }
    else { $failures += "CULM001_D9_MIG_UP_DOWN_UP missing $($missing -join ',') (exit $($r.ExitCode)): $(($r.Lines | Where-Object { $_ -match 'Msg |MIG_|TEST' }) -join ' / ')" }

}
catch { $failures += "CULM001_D9_RUNNER $($_.Exception.Message)" }
finally { $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1 }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "TEST FAILED: $_" }
    exit 1
}
exit 0
