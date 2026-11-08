param (
    [string]$ContainerName = 'sqlserver',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# CULM-001 D.2 (CONTRACT §3.2 D2-13, §14.2 D-RB-01): casos que necesitan sqlcmd con variables y :r de migrations/.
#   CULM001_D2_13_UP_DOWN_UP             test_culm001_d2_migraciones.sql (transaccion revertida; down con confirmacion)
#   CULM001_D2_13_DOWN_SIN_CONFIRMACION  test_culm001_d2_down_sin_confirmacion.sql (el down aborta con 50021 sin CONFIRMAR_COLAPSO_SOPORTES=1)
#   CULM001_D_RB_01_ORDEN_DE_DOWN        test_culm001_d_rollback.sql (con la 21 aplicada, el down de la 20 aborta con 50020)
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_culm001_d2.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/culm001_d2_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$failures = @()
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations/fixtures" 2>&1
$copy = @(& docker cp (Join-Path $dbRoot 'migrations/.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy migrations: $($copy -join '; ')" }
$copy = @(& docker cp (Join-Path $PSScriptRoot 'fixtures/culm001_d2_fixture.sql') "${ContainerName}:$remoteDir/migrations/fixtures/culm001_d2_fixture.sql" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy fixture: $($copy -join '; ')" }
foreach ($f in @('test_culm001_d2_migraciones.sql', 'test_culm001_d2_down_sin_confirmacion.sql', 'test_culm001_d_rollback.sql')) {
    $copy = @(& docker cp (Join-Path $PSScriptRoot $f) "${ContainerName}:$remoteDir/$f" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "could not copy ${f}: $($copy -join '; ')" }
}
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

function Invoke-Sqlcmd-File([string]$file, [string]$confirmar = '0') {
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", "CONFIRMAR_COLAPSO_SOPORTES=$confirmar", '-i', "$remoteDir/$file")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines; Text = ($lines -join "`n") }
}

try {
    $r = Invoke-Sqlcmd-File 'test_culm001_d2_migraciones.sql' '1'
    $missing = @(@('MIG_D2_UP0_OK', 'MIG_D2_DOWN_OK', 'MIG_D2_UP1_OK', 'MIG_D2_DOWN_UP_OK', 'MIG_D2_UP2_OK', 'MIG_D2_ROLLBACK_OK') | Where-Object { $r.Text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $r.ExitCode -eq 0) { Write-Host 'TEST_PASS:CULM001_D2_13_UP_DOWN_UP' }
    else { $failures += "CULM001_D2_13_UP_DOWN_UP missing $($missing -join ',') (exit $($r.ExitCode)): $(($r.Lines | Where-Object { $_ -match 'Msg |MIG_|TEST' }) -join ' / ')" }

    $s = Invoke-Sqlcmd-File 'test_culm001_d2_down_sin_confirmacion.sql' '0'
    if ($s.Text -match '(?m)^DOWN_SIN_CONFIRMACION_FIXTURE_OK$' -and $s.Text -notmatch 'DOWN_SIN_CONFIRMACION_NOT_ENFORCED' -and $s.Text -match '50021') { Write-Host 'TEST_PASS:CULM001_D2_13_DOWN_SIN_CONFIRMACION' }
    else { $failures += "CULM001_D2_13_DOWN_SIN_CONFIRMACION (exit $($s.ExitCode)): $(($s.Lines | Where-Object { $_ -match 'Msg |DOWN_SIN|CULM001|50021' }) -join ' / ')" }

    $g = Invoke-Sqlcmd-File 'test_culm001_d_rollback.sql' '0'
    if ($g.Text -match '(?m)^RB01_UP21_OK$' -and $g.Text -notmatch 'RB01_NOT_ENFORCED' -and $g.Text -match '50020') { Write-Host 'TEST_PASS:CULM001_D_RB_01_ORDEN_DE_DOWN' }
    else { $failures += "CULM001_D_RB_01_ORDEN_DE_DOWN (exit $($g.ExitCode)): $(($g.Lines | Where-Object { $_ -match 'Msg |RB01|CULM001|50020' }) -join ' / ')" }
}
catch { $failures += "CULM001_D2_RUNNER $($_.Exception.Message)" }
finally { $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1 }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "TEST FAILED: $_" }
    exit 1
}
exit 0
