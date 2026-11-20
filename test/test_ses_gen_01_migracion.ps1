param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# SES-GEN-01: migración 64 up -> down -> up en una transaccion revertida.
# Salida: TEST_PASS:SES_GEN_01_MIG_UP_DOWN_UP cuando los cuatro estados de la migracion pasan.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_ses_gen_01_migracion.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/ses_gen_01_mig_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$failures = @()
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$copy = @(& docker cp (Join-Path $dbRoot 'migrations/.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy SES-GEN-01 migrations: $($copy -join '; ')" }
$copy = @(& docker cp (Join-Path $PSScriptRoot 'test_ses_gen_01_migracion.sql') "${ContainerName}:$remoteDir/test_ses_gen_01_migracion.sql" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy test_ses_gen_01_migracion.sql: $($copy -join '; ')" }
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

try {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/test_ses_gen_01_migracion.sql")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    $exitCode = $LASTEXITCODE
    $text = $lines -join "`n"
    $markers = @('SES_GEN_01_MIG_DOWN_OK', 'SES_GEN_01_MIG_UP1_OK', 'SES_GEN_01_MIG_UP2_OK', 'SES_GEN_01_MIG_ROLLBACK_OK')
    $missing = @($markers | Where-Object { $text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $exitCode -eq 0) { Write-Host 'TEST_PASS:SES_GEN_01_MIG_UP_DOWN_UP' }
    else { $failures += "SES_GEN_01_MIG_UP_DOWN_UP missing $($missing -join ',') (exit $exitCode): $(($lines | Where-Object { $_ -match 'Msg |SES_GEN_01_MIG|TEST' }) -join ' / ')" }
}
catch { $failures += "SES_GEN_01_MIG_RUNNER $($_.Exception.Message)" }
finally { $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1 }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "TEST FAILED: $_" }
    exit 1
}
exit 0
