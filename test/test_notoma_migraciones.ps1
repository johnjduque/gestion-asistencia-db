param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD,
    [string]$Database = 'gestionasistenciadb'
)

# NOTOMA-001: migracion 57 up -> down -> up con sqlcmd y la variable MIGDIR (copia de migrations/).
#   NOTOMA_MIG_UP_DOWN_UP     test_notoma_migraciones.sql (transaccion revertida)
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.
# -Database existe solo para correr la prueba contra una base temporal (los .sql traen USE [gestionasistenciadb] y se copian con el nombre cambiado).

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_notoma_migraciones.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/notoma_mig_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$failures = @()
$stage = $null
$migSource = Join-Path $dbRoot 'migrations'
$testSource = Join-Path $PSScriptRoot 'test_notoma_migraciones.sql'
if ($Database -ne 'gestionasistenciadb') {
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) "notoma_mig_$tag"
    New-Item -ItemType Directory -Path "$stage/migrations" -Force | Out-Null
    foreach ($f in Get-ChildItem $migSource -Filter '5*_*.sql') {
        $texto = [System.IO.File]::ReadAllText($f.FullName).Replace('[gestionasistenciadb]', "[$Database]")
        [System.IO.File]::WriteAllText((Join-Path "$stage/migrations" $f.Name), $texto, (New-Object System.Text.UTF8Encoding($false)))
    }
    $migSource = Join-Path $stage 'migrations'
    $testSource = Join-Path $stage 'test_notoma_migraciones.sql'
    [System.IO.File]::WriteAllText($testSource, [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'test_notoma_migraciones.sql')), (New-Object System.Text.UTF8Encoding($false)))
}
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$copy = @(& docker cp (Join-Path $migSource '.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy migrations: $($copy -join '; ')" }
$copy = @(& docker cp $testSource "${ContainerName}:$remoteDir/test_notoma_migraciones.sql" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy test_notoma_migraciones.sql: $($copy -join '; ')" }
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

function Invoke-Sqlcmd-File([string]$file) {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', $Database, '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/$file")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines; Text = ($lines -join "`n") }
}

try {
    $r = Invoke-Sqlcmd-File 'test_notoma_migraciones.sql'
    $missing = @(@('NOTOMA_MIG_DOWN_OK', 'NOTOMA_MIG_UP1_OK', 'NOTOMA_MIG_UP2_OK', 'NOTOMA_MIG_ROLLBACK_OK') | Where-Object { $r.Text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $r.ExitCode -eq 0) { Write-Host 'TEST_PASS:NOTOMA_MIG_UP_DOWN_UP' }
    else { $failures += "NOTOMA_MIG_UP_DOWN_UP missing $($missing -join ',') (exit $($r.ExitCode)): $(($r.Lines | Where-Object { $_ -match 'Msg |NOTOMA_MIG|TEST' }) -join ' / ')" }
}
catch { $failures += "NOTOMA_MIG_RUNNER $($_.Exception.Message)" }
finally {
    $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1
    if ($stage -and (Test-Path $stage)) { Remove-Item $stage -Recurse -Force }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "TEST FAILED: $_" }
    exit 1
}
exit 0
