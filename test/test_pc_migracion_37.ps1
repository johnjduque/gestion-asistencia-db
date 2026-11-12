param (
    [string]$ContainerName = 'sql_server_asistencias',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# PC puntos de control: migracion 37 (ciclo de vida de la toma, reclamo por toma y calculo por tramos) con sqlcmd, variables y :r de migrations/.
#   PC_MIG_01_UP_DOWN_UP              test_pc_migracion_37.sql (transaccion revertida; down con CONFIRMAR_RETIRO_RECLAMO_TOMA = 1)
#   PC_MIG_02_DOWN_SIN_CONFIRMACION   test_pc_migracion_37_down_sin_confirmacion.sql (con un reclamo por toma y sin confirmacion el down
#                                     aborta con 50037 sin cambiar nada; la conexion termina en el error y nada se confirma)
# Componible (lib_componible.ps1, -Despues 37): el archivo se ejecuta tras bajar, dentro de su transaccion, las migraciones posteriores a la 37.
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo> por caso fallido.

$ErrorActionPreference = 'Stop'
if (-not $Password) { throw 'SQL password is required for test_pc_migracion_37.ps1.' }

$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$remoteDir = "/tmp/pcmig_$tag"
$dbRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib_componible.ps1')
$failures = @()
$null = & docker exec -u 0 $ContainerName mkdir -p "$remoteDir/migrations" 2>&1
$copy = @(& docker cp (Join-Path $dbRoot 'migrations/.') "${ContainerName}:$remoteDir/migrations" 2>&1)
if ($LASTEXITCODE -ne 0) { throw "could not copy migrations: $($copy -join '; ')" }
foreach ($f in @('test_pc_migracion_37.sql', 'test_pc_migracion_37_down_sin_confirmacion.sql')) {
    $copy = @(& docker cp (Join-Path $PSScriptRoot $f) "${ContainerName}:$remoteDir/$f" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "could not copy ${f}: $($copy -join '; ')" }
}
$null = & docker exec -u 0 $ContainerName chmod -R a+rX $remoteDir 2>&1

function Invoke-Sqlcmd-File([string]$file, [string]$confirmar) {
    $wrapper = "wrapper_$file"
    $preludio = ":setvar CONFIRMAR_RETIRO_RECLAMO_TOMA $confirmar"
    Send-TextToContainer -ContainerName $ContainerName -RemotePath "$remoteDir/$wrapper" -Text (New-ComposableWrapperText -DbRoot $dbRoot -RemoteMigrationsDir "$remoteDir/migrations" -Despues 37 -RemoteTestFile "$remoteDir/$file" -Preludio $preludio)
    $sqlArgs = @('exec', $ContainerName, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-d', 'gestionasistenciadb', '-U', 'sa', '-P', $Password,
                 '-C', '-I', '-h', '-1', '-W', '-s', '|', '-w', '65535', '-t', '600', '-v', "MIGDIR=$remoteDir/migrations", '-i', "$remoteDir/$wrapper")
    $lines = @(& docker @sqlArgs 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines; Text = ($lines -join "`n") }
}

try {
    $r = Invoke-Sqlcmd-File 'test_pc_migracion_37.sql' '1'
    $missing = @(@('MIG_PC_DOWN_OK', 'MIG_PC_UP1_OK', 'MIG_PC_UP2_OK', 'MIG_PC_DOWN_UP_OK', 'MIG_PC_ROLLBACK_OK') | Where-Object { $r.Text -notmatch "(?m)^$_$" })
    if ($missing.Count -eq 0 -and $r.ExitCode -eq 0) { Write-Output 'TEST_PASS:PC_MIG_01_UP_DOWN_UP' }
    else { $failures += "PC_MIG_01_UP_DOWN_UP missing $($missing -join ',') (exit $($r.ExitCode)): $(($r.Lines | Where-Object { $_ -match 'Msg |MIG_|TEST' }) -join ' / ')" }

    $s = Invoke-Sqlcmd-File 'test_pc_migracion_37_down_sin_confirmacion.sql' '0'
    if ($s.Text -match '(?m)^PC_DOWN_SIN_CONFIRMACION_FIXTURE_OK$' -and $s.Text -notmatch 'PC_DOWN_SIN_CONFIRMACION_NOT_ENFORCED' -and $s.Text -match '50037') { Write-Output 'TEST_PASS:PC_MIG_02_DOWN_SIN_CONFIRMACION' }
    else { $failures += "PC_MIG_02_DOWN_SIN_CONFIRMACION (exit $($s.ExitCode)): $(($s.Lines | Where-Object { $_ -match 'Msg |PC_DOWN|50037' }) -join ' / ')" }
}
catch { $failures += "PC_MIG_RUNNER $($_.Exception.Message)" }
finally { $null = & docker exec -u 0 $ContainerName rm -rf $remoteDir 2>&1 }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "TEST FAILED: $_" }
    exit 1
}
exit 0
