param (
    [string]$ContainerName = 'sql_server_asistencias',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# VAL F12-12 (oleada 3): prueba de la tarea scripts/migrar.ps1 y del registro dbo.MigracionAplicada.
# Usa una BD temporal propia (qa_migrar_<tag>) y migraciones sinteticas en una carpeta temporal; nunca toca gestionasistenciadb.
#   VAL_F1212_01_ESTADO_SOLO_LECTURA     Estado sin registro: lista pendientes, no crea la tabla ni ejecuta nada; ignora *_down y NN < 5.
#   VAL_F1212_02_APLICA_Y_REGISTRA       Aplicar: ejecuta las pendientes en orden y registra version, nombre, archivo, checksum y modo.
#   VAL_F1212_03_SALTA_APLICADAS         Aplicar otra vez: no reejecuta nada; una nueva se aplica sola.
#   VAL_F1212_04_FALLA_NO_REGISTRA       Una migracion que falla devuelve 1 y no queda registrada.
#   VAL_F1212_05_DERIVA_DETIENE          Un archivo aplicado que cambia (checksum) detiene la tarea sin aplicar nada.
#   VAL_F1212_06_BASELINE_SIN_EJECUTAR   Baseline registra sin ejecutar (una migracion que fallaria queda como BASELINE).
#   VAL_F1212_07_INVENTARIO_REAL         El inventario de migrations/ del repositorio se lee sin errores ni nombres duplicados.
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo>.
$ErrorActionPreference = 'Stop'
$dbRoot = Split-Path -Parent $PSScriptRoot
if (-not $Password) {
    $envFile = Join-Path $dbRoot '.env'
    if (Test-Path $envFile) { Get-Content $envFile | ForEach-Object { if ($_ -match '^\s*SQL_CONTAINER_PASSWORD=(.*)$') { $Password = $matches[1].Trim() } } }
}
if (-not $Password) { throw 'SQL password is required for test_val_migrar.ps1.' }

$migrar = Join-Path $dbRoot 'scripts/migrar.ps1'
$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$db = "qa_migrar_$tag"
$dir = Join-Path ([System.IO.Path]::GetTempPath()) "qa_migrar_$tag"
$failures = @()

function Invoke-Master([string]$Query, [string]$Database = 'master') {
    $out = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d $Database -U sa -P $Password -C -b -h -1 -W -Q "SET NOCOUNT ON; $Query" 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    if ($LASTEXITCODE -ne 0) { throw "SQL fallo: $(($out | Select-Object -Last 3) -join ' | ')" }
    return , $out
}
function Invoke-Db([string]$Query) { return Invoke-Master $Query $db }
function Invoke-Migrar([string]$Modo, [string]$Dir = $dir) {
    $out = @(& $migrar -Modo $Modo -ContainerName $ContainerName -Password $Password -Database $db -MigrationsDir $Dir *>&1 | ForEach-Object { "$_" })
    return [pscustomobject]@{ Rc = $LASTEXITCODE; Out = $out; Text = ($out -join "`n") }
}
function Write-Mig([string]$Name, [string]$Body) { [System.IO.File]::WriteAllText((Join-Path $dir $Name), $Body, [System.Text.UTF8Encoding]::new($false)) }
function Assert-Case([string]$Id, [bool]$Ok, [string]$Why, $Run) {
    if ($Ok) { Write-Output "TEST_PASS:$Id" }
    else {
        $script:failures += $Id
        $tail = if ($Run) { ($Run.Out | Select-Object -Last 4) -join ' | ' } else { '' }
        Write-Output "TEST FAILED: $Id $Why $tail"
    }
}

try {
    $null = Invoke-Master "CREATE DATABASE [$db];"
    $null = New-Item -ItemType Directory -Path $dir -Force
    Write-Mig '03_qa_legado.sql' "RAISERROR('legado: no debe ejecutarse', 16, 1);"
    Write-Mig '05_qa_uno_up.sql' ":on error exit`nCREATE TABLE dbo.QaUno (n INT NOT NULL);`nGO`nINSERT INTO dbo.QaUno (n) VALUES (1);`nGO`n"
    Write-Mig '05_qa_uno_down.sql' "RAISERROR('down: no debe ejecutarse', 16, 1);"
    Write-Mig '06_qa_dos.sql' ":on error exit`nINSERT INTO dbo.QaUno (n) VALUES (2);`nGO`n"

    # 01: Estado es de solo lectura
    $r = Invoke-Migrar 'Estado'
    $tabla = (Invoke-Db "SELECT IIF(OBJECT_ID('dbo.MigracionAplicada', 'U') IS NULL, 0, 1);") -join ''
    Assert-Case 'VAL_F1212_01_ESTADO_SOLO_LECTURA' ($r.Rc -eq 0 -and $tabla -eq '0' -and $r.Text -match 'MIGRAR_REGISTRO_AUSENTE' -and
        $r.Text -match 'MIGRAR_PENDIENTE 05_qa_uno' -and $r.Text -match 'MIGRAR_PENDIENTE 06_qa_dos' -and $r.Text -notmatch 'qa_legado' -and
        $r.Text -match 'MIGRAR_RESUMEN modo=Estado total=2 registradas=0 pendientes=2 deriva=0 aplicadas=0') 'Estado no es de solo lectura o no lista lo esperado.' $r

    # 02: Aplicar ejecuta en orden y registra
    $r = Invoke-Migrar 'Aplicar'
    $filas = (Invoke-Db 'SELECT STRING_AGG(CONVERT(VARCHAR(10), n), '','') WITHIN GROUP (ORDER BY n) FROM dbo.QaUno;') -join ''
    $reg = (Invoke-Db "SELECT STRING_AGG(CONCAT(version, ':', nombre, ':', archivo, ':', modo, ':', checksumSha256), ',') WITHIN GROUP (ORDER BY version) FROM dbo.MigracionAplicada WHERE aplicadaEnUtc <= SYSUTCDATETIME() AND duracionMs IS NOT NULL;") -join ''
    $sha05 = (& { $b = [System.IO.File]::ReadAllBytes((Join-Path $dir '05_qa_uno_up.sql')); ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($b)).Replace('-', '')).ToLowerInvariant() })
    Assert-Case 'VAL_F1212_02_APLICA_Y_REGISTRA' ($r.Rc -eq 0 -and $filas -eq '1,2' -and
        $reg -eq "5:05_qa_uno:05_qa_uno_up.sql:APLICADA:$sha05,6:06_qa_dos:06_qa_dos.sql:APLICADA:$((Invoke-Db "SELECT checksumSha256 FROM dbo.MigracionAplicada WHERE nombre = '06_qa_dos';") -join '')" -and
        $r.Text -match 'aplicadas=2') "Aplicar no dejo las filas 1,2 y el registro esperado (filas=$filas)." $r

    # 03: una segunda corrida salta lo aplicado; una nueva se aplica sola
    $r1 = Invoke-Migrar 'Aplicar'
    Write-Mig '07_qa_tres_up.sql' ":on error exit`nINSERT INTO dbo.QaUno (n) VALUES (3);`nGO`n"
    $r2 = Invoke-Migrar 'Aplicar'
    $filas = (Invoke-Db 'SELECT STRING_AGG(CONVERT(VARCHAR(10), n), '','') WITHIN GROUP (ORDER BY n) FROM dbo.QaUno;') -join ''
    Assert-Case 'VAL_F1212_03_SALTA_APLICADAS' ($r1.Rc -eq 0 -and $r1.Text -match 'aplicadas=0' -and $r1.Text -match 'MIGRAR_APLICADA 05_qa_uno' -and
        $r2.Rc -eq 0 -and $r2.Text -match 'MIGRAR_APLICADA_AHORA 07_qa_tres' -and $r2.Text -match 'aplicadas=1' -and $filas -eq '1,2,3') "Reejecuto o no aplico solo la nueva (filas=$filas)." $r2

    # 04: una migracion que falla no se registra
    Write-Mig '08_qa_falla_up.sql' ":on error exit`nINSERT INTO dbo.QaUno (n) VALUES (4);`nGO`nRAISERROR('falla a proposito', 16, 1);`nGO`n"
    $r = Invoke-Migrar 'Aplicar'
    $reg = (Invoke-Db "SELECT COUNT(*) FROM dbo.MigracionAplicada WHERE nombre = '08_qa_falla';") -join ''
    Assert-Case 'VAL_F1212_04_FALLA_NO_REGISTRA' ($r.Rc -eq 1 -and $r.Text -match 'MIGRAR_FALLO 08_qa_falla' -and $reg -eq '0') 'La migracion fallida quedo registrada o la tarea no devolvio 1.' $r
    Remove-Item (Join-Path $dir '08_qa_falla_up.sql')
    $null = Invoke-Db 'DELETE FROM dbo.QaUno WHERE n = 4;'

    # 05: deriva (archivo aplicado modificado) detiene sin aplicar
    Write-Mig '09_qa_nueva_up.sql' ":on error exit`nINSERT INTO dbo.QaUno (n) VALUES (9);`nGO`n"
    $original = [System.IO.File]::ReadAllText((Join-Path $dir '06_qa_dos.sql'))
    Write-Mig '06_qa_dos.sql' ($original + "-- cambio posterior`n")
    $r = Invoke-Migrar 'Aplicar'
    $nueve = (Invoke-Db 'SELECT COUNT(*) FROM dbo.QaUno WHERE n = 9;') -join ''
    Assert-Case 'VAL_F1212_05_DERIVA_DETIENE' ($r.Rc -eq 1 -and $r.Text -match 'MIGRAR_DERIVA 06_qa_dos' -and $nueve -eq '0') 'La deriva no detuvo la tarea o se aplico la pendiente.' $r
    Write-Mig '06_qa_dos.sql' $original
    Remove-Item (Join-Path $dir '09_qa_nueva_up.sql')

    # 06: Baseline registra sin ejecutar
    Write-Mig '10_qa_baseline_up.sql' "RAISERROR('baseline: no debe ejecutarse', 16, 1);"
    $r1 = Invoke-Migrar 'Baseline'
    $r2 = Invoke-Migrar 'Estado'
    $modo = (Invoke-Db "SELECT CONCAT(modo, ':', ISNULL(CONVERT(VARCHAR(10), duracionMs), 'NULL')) FROM dbo.MigracionAplicada WHERE nombre = '10_qa_baseline';") -join ''
    Assert-Case 'VAL_F1212_06_BASELINE_SIN_EJECUTAR' ($r1.Rc -eq 0 -and $modo -eq 'BASELINE:NULL' -and $r2.Rc -eq 0 -and $r2.Text -match 'MIGRAR_BASELINE 10_qa_baseline' -and
        $r2.Text -match 'pendientes=0') "Baseline no registro sin ejecutar (modo=$modo)." $r1

    # 07: inventario real de migrations/ (solo Estado sobre la BD temporal: no ejecuta ninguna migracion real)
    $null = Invoke-Db 'DROP TABLE dbo.MigracionAplicada;'
    $r = Invoke-Migrar 'Estado' (Join-Path $dbRoot 'migrations')
    $esperadas = @(Get-ChildItem (Join-Path $dbRoot 'migrations') -Filter '*.sql' | Where-Object { $_.Name -notmatch '_down\.sql$' -and $_.Name -match '^(\d+)_' -and [int]$Matches[1] -ge 5 }).Count
    Assert-Case 'VAL_F1212_07_INVENTARIO_REAL' ($r.Rc -eq 0 -and $r.Text -match "MIGRAR_RESUMEN modo=Estado total=$esperadas registradas=0 pendientes=$esperadas" -and $esperadas -gt 30) "El inventario real no coincide (esperadas=$esperadas)." $r
}
catch {
    $failures += 'VAL_F1212_RUNNER'
    Write-Output "TEST FAILED: VAL_F1212_RUNNER $($_.Exception.Message)"
}
finally {
    try { $null = Invoke-Master "IF DB_ID(N'$db') IS NOT NULL BEGIN ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db]; END;" } catch { Write-Output "TEST FAILED: VAL_F1212_CLEANUP $($_.Exception.Message)" }
    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failures.Count -gt 0) { exit 1 }
exit 0
