param (
    [string]$ContainerName = 'sql_server_asistencias',
    [string]$Password = $env:MSSQL_SA_PASSWORD
)

# VAL-migrar-detectar: prueba de scripts/migrar.ps1 -Modo Detectar y -Modo Baseline -SoloDetectadas (base vieja sin registro).
# Usa dos BD temporales propias (qa_mdet_full_<tag> y qa_mdet_s16_<tag>); nunca toca gestionasistenciadb.
#   - full: despliegue limpio del schema/ actual (como deploy_schema.ps1, con el nombre de la base cambiado).
#   - s16:  despliegue del schema/ del commit 8f18b76 de develop (ultimo antes de la migracion 17: tiene 05..16 y 20). Es el
#           estado de una base local que se quedo atras (el caso que resuelve docs/runbooks/ACTUALIZAR_BD_LOCAL_EXISTENTE.md).
#   VAL_MDET_01_MARCADORES_COMPLETOS     Cada migracion administrada tiene marcadores en scripts/migrar-marcadores.json y no sobra ninguna.
#   VAL_MDET_02_DESPLIEGUE_LIMPIO_TODAS  Un despliegue limpio sale con todas APLICADA_DETECTADA; Detectar no escribe en el registro.
#   VAL_MDET_03_ESTADO_16_CLASIFICA      La base del estado 16: 05..16 detectadas, 20 y 36 detectadas fuera de orden, el resto AUSENTE,
#                                        ninguna PARCIAL; Detectar no crea dbo.MigracionAplicada.
#   VAL_MDET_04_PARCIAL_BLOQUEA          Con una migracion a medias, Detectar la marca PARCIAL (con lo que falta) y -SoloDetectadas no
#                                        registra nada (ni crea el registro) y devuelve 1.
#   VAL_MDET_05_SOLO_DETECTADAS_REGISTRA -SoloDetectadas registra como BASELINE solo el tramo contiguo detectado (05..16); 20 y 36
#                                        quedan PENDIENTE.
#   VAL_MDET_06_APLICAR_EN_ORDEN         -Modo Aplicar ejecuta las pendientes en orden de version (17, 18, 19, 20, 21, ...), aunque haya
#                                        registradas posteriores a una pendiente, y Estado queda en pendientes=0 deriva=0.
#   VAL_MDET_07_TRAS_APLICAR_TODAS       Despues de Aplicar, Detectar da todas APLICADA_DETECTADA.
#   VAL_MDET_08_REAPLICAR_PARCIALES      Con -ReaplicarParciales la PARCIAL no detiene: queda PENDIENTE y se registra solo el tramo previo.
# Salida: TEST_PASS:<ID> por caso aprobado y TEST FAILED: <ID> <motivo>.
$ErrorActionPreference = 'Stop'
$dbRoot = Split-Path -Parent $PSScriptRoot
if (-not $Password) {
    $envFile = Join-Path $dbRoot '.env'
    if (Test-Path $envFile) { Get-Content $envFile | ForEach-Object { if ($_ -match '^\s*SQL_CONTAINER_PASSWORD=(.*)$') { $Password = $matches[1].Trim() } } }
}
if (-not $Password) { throw 'SQL password is required for test_val_migrar_detectar.ps1.' }

$commitEstado16 = '8f18b76'   # develop antes del merge de la migracion 17 (PR #113)
$migrar = Join-Path $dbRoot 'scripts/migrar.ps1'
$tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
$dbFull = "qa_mdet_full_$tag"
$dbS16 = "qa_mdet_s16_$tag"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "qa_mdet_$tag"
$failures = @()

function Invoke-Sql([string]$Query, [string]$Database = 'master') {
    $out = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d $Database -U sa -P $Password -C -b -h -1 -W -Q "SET NOCOUNT ON; $Query" 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    if ($LASTEXITCODE -ne 0) { throw "SQL fallo: $(($out | Select-Object -Last 3) -join ' | ')" }
    return , $out
}
function Invoke-Migrar([string]$Database, [hashtable]$Extra) {
    $out = @(& $migrar -ContainerName $ContainerName -Password $Password -Database $Database @Extra *>&1 | ForEach-Object { "$_" })
    return [pscustomobject]@{ Rc = $LASTEXITCODE; Out = $out; Text = ($out -join "`n") }
}
function Assert-Case([string]$Id, [bool]$Ok, [string]$Why, $Run) {
    if ($Ok) { Write-Output "TEST_PASS:$Id" }
    else {
        $script:failures += $Id
        $tail = if ($Run) { ($Run.Out | Select-Object -Last 6) -join ' | ' } else { '' }
        Write-Output "TEST FAILED: $Id $Why $tail"
    }
}
function Deploy-Schema([string]$SchemaDir, [string]$Database) {
    # Mismo orden que deploy_schema.ps1 (tablas -> triggers -> funciones -> vistas -> SP -> seguridad -> semillas) sobre una base
    # propia: copia de schema/ con [gestionasistenciadb] cambiado. Vistas, SP y seguridad en pasadas tolerantes (dependencias).
    $null = Invoke-Sql "CREATE DATABASE [$Database];"
    $stage = Join-Path $tmp "stage_$Database"
    Copy-Item $SchemaDir $stage -Recurse
    Get-ChildItem $stage -Filter '*.sql' -Recurse | ForEach-Object {
        # Conserva la marca BOM: sin ella sqlcmd lee el archivo con otra pagina de codigos y cambia las tildes.
        $b = [System.IO.File]::ReadAllBytes($_.FullName)
        $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
        $t = [System.IO.File]::ReadAllText($_.FullName)
        if ($t.Contains('[gestionasistenciadb]')) { [System.IO.File]::WriteAllText($_.FullName, $t.Replace('[gestionasistenciadb]', "[$Database]"), [System.Text.UTF8Encoding]::new($bom)) }
    }
    $dest = "/tmp/qa_mdet_${tag}_$Database"
    $null = & docker cp $stage "${ContainerName}:$dest" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "No se pudo copiar el esquema de $Database al contenedor." }
    try {
        foreach ($dir in 'tables', 'triggers', 'functions', 'views', 'stored-procedures', 'security', 'seed') {
            if (-not (Test-Path (Join-Path $stage $dir))) { continue }
            $tolerante = $dir -in 'views', 'stored-procedures', 'security'
            $pendientes = @(Get-ChildItem (Join-Path $stage $dir) -Filter '*.sql' -Recurse | Sort-Object Name)
            for ($pasada = 1; $pendientes.Count -gt 0 -and $pasada -le 15; $pasada++) {
                $fallidos = @()
                foreach ($f in $pendientes) {
                    $rel = $f.FullName.Substring($stage.Length).Replace('\', '/')
                    $out = & docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $Password -C -d $Database -b -i "$dest$rel" 2>&1 | Out-String
                    if ($LASTEXITCODE -ne 0 -or $out -match 'Msg \d+, Level 1[1-9]') {
                        if ($tolerante) { $fallidos += $f } else { throw "Despliegue de ${Database}: fallo $($f.Name): $(($out -split "`n" | Select-Object -Last 3) -join ' ')" }
                    }
                }
                if ($fallidos.Count -eq $pendientes.Count) { throw "Despliegue de ${Database}: sin resolver en ${dir}: $($fallidos.Name -join ', ')" }
                $pendientes = $fallidos
            }
            if ($pendientes.Count) { throw "Despliegue de ${Database}: sin resolver en ${dir}: $($pendientes.Name -join ', ')" }
        }
    }
    finally { $null = & docker exec -u 0 $ContainerName rm -rf $dest 2>&1 }
}
function Get-Estados($Run) {
    $e = @{}
    foreach ($l in $Run.Out) {
        if ($l -match '^MIGRAR_DETECTAR_([A-Z_]+) (\S+) marcadores=') {
            $estado = $Matches[1]; $nombre = $Matches[2]   # antes del segundo -match, que reescribe $Matches
            if ($l -match 'fuera_de_orden=1') { $estado += '+FUERA' }
            $e[$nombre] = $estado
        }
    }
    return $e
}

try {
    $null = New-Item -ItemType Directory -Path $tmp -Force
    $inventario = @(Get-ChildItem (Join-Path $dbRoot 'migrations') -Filter '*.sql' | Where-Object { $_.Name -notmatch '_down\.sql$' -and $_.Name -match '^(\d+)_' -and [int]$Matches[1] -ge 5 } |
        ForEach-Object { [pscustomobject]@{ Version = [int]($_.Name.Split('_')[0]); Nombre = ($_.Name -replace '(_up)?\.sql$', '') } } | Sort-Object Version, Nombre)
    $total = $inventario.Count

    # 01: archivo de marcadores completo y sin sobrantes
    $json = [System.IO.File]::ReadAllText((Join-Path $dbRoot 'scripts/migrar-marcadores.json')) | ConvertFrom-Json
    $claves = @($json.migraciones.PSObject.Properties | ForEach-Object { $_.Name })
    $faltan = @($inventario.Nombre | Where-Object { $_ -notin $claves })
    $sobran = @($claves | Where-Object { $_ -notin $inventario.Nombre })
    $vacias = @($json.migraciones.PSObject.Properties | Where-Object { @($_.Value).Count -eq 0 } | ForEach-Object { $_.Name })
    Assert-Case 'VAL_MDET_01_MARCADORES_COMPLETOS' ($total -gt 30 -and -not $faltan.Count -and -not $sobran.Count -and -not $vacias.Count) "faltan=[$($faltan -join ',')] sobran=[$($sobran -join ',')] vacias=[$($vacias -join ',')]" $null

    # 02: despliegue limpio del schema/ actual: todas detectadas; Detectar no escribe en el registro
    Deploy-Schema (Join-Path $dbRoot 'schema') $dbFull
    $filasAntes = (Invoke-Sql 'SELECT COUNT(*) FROM dbo.MigracionAplicada;' $dbFull) -join ''
    $r = Invoke-Migrar $dbFull @{ Modo = 'Detectar' }
    $filasDespues = (Invoke-Sql 'SELECT COUNT(*) FROM dbo.MigracionAplicada;' $dbFull) -join ''
    $ultima = $inventario[-1]
    Assert-Case 'VAL_MDET_02_DESPLIEGUE_LIMPIO_TODAS' ($r.Rc -eq 0 -and $filasAntes -eq '0' -and $filasDespues -eq '0' -and
        $r.Text -match "MIGRAR_DETECTAR_RESUMEN total=$total detectadas=$total ausentes=0 parciales=0 sin_marcadores=0 contigua_hasta=$($ultima.Version) \($($ultima.Nombre)\)") 'El despliegue limpio no sale completo o Detectar escribio.' $r
    $null = Invoke-Sql "ALTER DATABASE [$dbFull] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$dbFull];"

    # 03: base del estado 16 (schema/ de develop antes de la migracion 17)
    $tar = Join-Path $tmp 'estado16.tar'
    & git -C $dbRoot archive --format=tar -o $tar $commitEstado16 schema 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "No se pudo leer schema/ del commit $commitEstado16 (el clon necesita la historia de develop: fetch-depth 0)." }
    $viejo = Join-Path $tmp 'estado16'
    $null = New-Item -ItemType Directory -Path $viejo -Force
    & tar -xf $tar -C $viejo
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo extraer schema/ del estado 16.' }
    Deploy-Schema (Join-Path $viejo 'schema') $dbS16
    $r = Invoke-Migrar $dbS16 @{ Modo = 'Detectar' }
    $e = Get-Estados $r
    $registro = (Invoke-Sql "SELECT IIF(OBJECT_ID('dbo.MigracionAplicada', 'U') IS NULL, 0, 1);" $dbS16) -join ''
    $malas = @()
    foreach ($m in $inventario) {
        $esperado = if ($m.Version -le 16) { 'APLICADA_DETECTADA' } elseif ($m.Version -in 20, 36) { 'APLICADA_DETECTADA+FUERA' } else { 'AUSENTE' }
        if ($e[$m.Nombre] -ne $esperado) { $malas += "$($m.Nombre)=$($e[$m.Nombre])" }
    }
    $hasta16 = @($inventario | Where-Object { $_.Version -le 16 })
    Assert-Case 'VAL_MDET_03_ESTADO_16_CLASIFICA' ($r.Rc -eq 0 -and -not $malas.Count -and $registro -eq '0' -and $r.Text -match 'parciales=0' -and
        $r.Text -match "contigua_hasta=16 \($($hasta16[-1].Nombre)\)") "Clasificacion inesperada: $($malas -join ', ') registro=$registro" $r

    # 04: una migracion a medias (una tabla de la 19 sin el resto) bloquea -SoloDetectadas
    $null = Invoke-Sql 'CREATE TABLE dbo.TipoAlertaInasistencia (id INT NOT NULL);' $dbS16
    $r1 = Invoke-Migrar $dbS16 @{ Modo = 'Detectar' }
    $r2 = Invoke-Migrar $dbS16 @{ Modo = 'Baseline'; SoloDetectadas = $true }
    $registro = (Invoke-Sql "SELECT IIF(OBJECT_ID('dbo.MigracionAplicada', 'U') IS NULL, 0, 1);" $dbS16) -join ''
    # 08 (con la misma PARCIAL): -ReaplicarParciales no se detiene; registra solo el tramo contiguo anterior y deja la 19 PENDIENTE.
    $r3 = Invoke-Migrar $dbS16 @{ Modo = 'Baseline'; SoloDetectadas = $true; ReaplicarParciales = $true }
    $reg8 = (Invoke-Sql "IF OBJECT_ID('dbo.MigracionAplicada', 'U') IS NOT NULL SELECT CONCAT(nombre, ':', modo) FROM dbo.MigracionAplicada ORDER BY version, nombre;" $dbS16)
    $null = Invoke-Sql "DROP TABLE IF EXISTS dbo.MigracionAplicada; DROP TABLE dbo.TipoAlertaInasistencia;" $dbS16
    Assert-Case 'VAL_MDET_04_PARCIAL_BLOQUEA' ($r1.Rc -eq 0 -and $r1.Text -match 'MIGRAR_DETECTAR_PARCIAL 19_culm001_c_cancelacion_inasistencia marcadores=1/' -and
        $r1.Text -match 'falta: tabla dbo.AlertaInasistencia' -and $r2.Rc -eq 1 -and $r2.Text -match 'MIGRAR_FALLO migraciones PARCIAL: 19_culm001_c_cancelacion_inasistencia' -and
        $registro -eq '0') "La PARCIAL no bloqueo el registro (registro=$registro)." $r2
    $esperado8 = @($inventario | Where-Object { $_.Version -le 16 } | ForEach-Object { "$($_.Nombre):BASELINE" })
    Assert-Case 'VAL_MDET_08_REAPLICAR_PARCIALES' ($r3.Rc -eq 0 -and $r3.Text -match 'MIGRAR_PARCIALES_PENDIENTES 19_culm001_c_cancelacion_inasistencia' -and
        $r3.Text -match 'MIGRAR_PENDIENTE 19_culm001_c_cancelacion_inasistencia' -and ($reg8 -join ',') -eq ($esperado8 -join ',')) "Registro con -ReaplicarParciales: $($reg8 -join ',')" $r3

    # 05: -SoloDetectadas registra solo el tramo contiguo
    $r = Invoke-Migrar $dbS16 @{ Modo = 'Baseline'; SoloDetectadas = $true }
    $reg = (Invoke-Sql "SELECT CONCAT(nombre, ':', modo) FROM dbo.MigracionAplicada ORDER BY version, nombre;" $dbS16)
    $esperado = @($hasta16 | ForEach-Object { "$($_.Nombre):BASELINE" })
    Assert-Case 'VAL_MDET_05_SOLO_DETECTADAS_REGISTRA' ($r.Rc -eq 0 -and ($reg -join ',') -eq ($esperado -join ',') -and
        $r.Text -match 'MIGRAR_DETECTADA_FUERA_DE_ORDEN 20_culm001_d1_plazo_justificacion' -and $r.Text -match 'MIGRAR_DETECTADA_FUERA_DE_ORDEN 36_hu177_retiro_recuperacion_clave' -and
        $r.Text -match 'MIGRAR_PENDIENTE 20_culm001_d1_plazo_justificacion') "Registro inesperado: $($reg -join ',')" $r

    # 06: Aplicar en orden de version (hueco: 17 pendiente y 16 registrada; 20 pendiente entre 19 y 21) hasta pendientes=0
    $r = Invoke-Migrar $dbS16 @{ Modo = 'Aplicar' }
    $orden = @($r.Out | Where-Object { $_ -match '^MIGRAR_APLICADA_AHORA (\S+)' } | ForEach-Object { ($_ -split ' ')[1] })
    $esperado = @($inventario | Where-Object { $_.Version -gt 16 } | ForEach-Object { $_.Nombre })
    $estado = Invoke-Migrar $dbS16 @{ Modo = 'Estado' }
    Assert-Case 'VAL_MDET_06_APLICAR_EN_ORDEN' ($r.Rc -eq 0 -and ($orden -join ',') -eq ($esperado -join ',') -and $estado.Rc -eq 0 -and
        $estado.Text -match "MIGRAR_RESUMEN modo=Estado total=$total registradas=$total pendientes=0 deriva=0") "Orden aplicado: $($orden -join ',')" $r

    # 07: tras Aplicar, todas detectadas
    $r = Invoke-Migrar $dbS16 @{ Modo = 'Detectar' }
    Assert-Case 'VAL_MDET_07_TRAS_APLICAR_TODAS' ($r.Rc -eq 0 -and $r.Text -match "detectadas=$total ausentes=0 parciales=0") 'Tras Aplicar no salen todas detectadas.' $r
}
catch {
    $failures += 'VAL_MDET_RUNNER'
    Write-Output "TEST FAILED: VAL_MDET_RUNNER $($_.Exception.Message)"
}
finally {
    foreach ($d in $dbFull, $dbS16) {
        try { $null = Invoke-Sql "IF DB_ID(N'$d') IS NOT NULL BEGIN ALTER DATABASE [$d] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$d]; END;" } catch { Write-Output "TEST FAILED: VAL_MDET_CLEANUP $($_.Exception.Message)" }
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failures.Count -gt 0) { exit 1 }
exit 0
