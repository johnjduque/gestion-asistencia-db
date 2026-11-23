param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# INT-004: migracion 74 up -> down -> up con sqlcmd, y :r de migrations/.
#   INT004_MIG74_UP_DOWN_UP     test_int004_migracion_74.sql (transaccion revertida)
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_int004_migracion_74.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/int004_mig74_mig_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$failures = @()
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$copy = @(& docker cp (Join-Path $dbRoot 'migrations/.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy migrations: $($copy -join '; ')" }
$copy = @(& docker cp (Join-Path $PSScriptRoot 'test_int004_migracion_74.sql') "${ContainerName}:$remoteDir/test_int004_migracion_74.sql" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy test_int004_migracion_74.sql: $($copy -join '; ')" }
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

function Invoke-Sqlcmd-File([string]$file) {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/$file")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines; Text = ($lines -join "`n") }
}

try {
    $r = Invoke-Sqlcmd-File 'test_int004_migracion_74.sql'
    $missing = @(@('INT004_MIG74_UP1_OK', 'INT004_MIG74_DOWN_OK', 'INT004_MIG74_UP2_OK', 'INT004_MIG74_ROLLBACK_OK') | Where-Object { $r.Text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $r.ExitCode -eq 0) { Write-Host 'TEST_PASS:INT004_MIG74_UP_DOWN_UP' }
    else { $failures += "INT004_MIG74_UP_DOWN_UP missing $($missing -join ',') (exit $($r.ExitCode)): $(($r.Lines | Where-Object { $_ -match 'Msg |INT004_MIG74|TEST' }) -join ' / ')" }
}
catch { $failures += "INT004_MIG74_RUNNER $($_.Exception.Message)" }
finally { $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1 }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "TEST FAILED: $_" }
    exit 1
}
exit 0
