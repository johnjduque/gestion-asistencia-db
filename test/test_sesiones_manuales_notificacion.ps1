param (
    [string]$ContainerName = 'sql_server_asistencias',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# CULM-001 / DEC-064: migracion 29 (sesiones manuales) up->down->up con sqlcmd, variables y :r de migrations/.
#   SMN_MIG_UP_DOWN_UP     test_sesiones_manuales_notificacion_migraciones.sql (transaccion revertida)
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_sesiones_manuales_notificacion.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/smn_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
$failures = @()
. (Join-Path $PSScriptRoot 'lib_componible.ps1')
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$copy = @(& docker cp (Join-Path $dbRoot 'migrations/.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy migrations: $($copy -join '; ')" }
foreach ($f in @('test_sesiones_manuales_notificacion_migraciones.sql')) {
    $copy = @(& docker cp (Join-Path $PSScriptRoot $f) "${ContainerName}:$remoteDir/$f" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "could not copy ${f}: $($copy -join '; ')" }
}
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

# Componible (lib_componible.ps1): el archivo se ejecuta tras bajar, dentro de su transaccion, las migraciones posteriores a la 29.
function Invoke-Sqlcmd-File([string]$file) {
    $wrapper = "wrapper_$file"
    Send-TextToContainer -ContainerName $ContainerName -RemotePath "$remoteDir/$wrapper" -Text (New-ComposableWrapperText -DbRoot $dbRoot -RemoteMigrationsDir "$remoteDir/migrations" -Despues 29 -RemoteTestFile "$remoteDir/$file")
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/$wrapper")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines; Text = ($lines -join "`n") }
}

try {
    $r = Invoke-Sqlcmd-File 'test_sesiones_manuales_notificacion_migraciones.sql'
    $missing = @(@('MIG_SMN_DOWN_OK', 'MIG_SMN_UP1_OK', 'MIG_SMN_UP2_OK', 'MIG_SMN_DOWN_UP_OK', 'MIG_SMN_ROLLBACK_OK') | Where-Object { $r.Text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $r.ExitCode -eq 0) { Write-Host 'TEST_PASS:SMN_MIG_UP_DOWN_UP' }
    else { $failures += "SMN_MIG_UP_DOWN_UP missing $($missing -join ',') (exit $($r.ExitCode)): $(($r.Lines | Where-Object { $_ -match 'Msg |MIG_|TEST' }) -join ' / ')" }

}
catch { $failures += "SMN_RUNNER $($_.Exception.Message)" }
finally { $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1 }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "TEST FAILED: $_" }
    exit 1
}
exit 0
