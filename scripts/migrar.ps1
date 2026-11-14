# VAL F12-12 (oleada 3): tarea de migracion (12-factor, procesos administrativos).
#
# Aplica las migraciones de migrations/ en orden y las registra en dbo.MigracionAplicada (version, nombre, archivo, checksum,
# modo, aplicadaEnUtc, aplicadaPor, duracionMs). Una migracion ya registrada se salta; si su archivo cambio despues de aplicado
# (checksum distinto) la tarea se detiene sin aplicar nada (deriva). Ver docs/work-items/VAL-oleada3-bd-pendientes/PLAN.md.
#
#   ./scripts/migrar.ps1                       # -Modo Estado: solo lectura; lista APLICADA / BASELINE / PENDIENTE / DERIVA
#   ./scripts/migrar.ps1 -Modo Aplicar         # aplica las pendientes en orden y registra cada una (modo APLICADA)
#   ./scripts/migrar.ps1 -Modo Baseline        # registra sin ejecutar (modo BASELINE) las migraciones hasta -HastaVersion;
#                                              # para una base creada con deploy_schema.ps1, que ya contiene su efecto
#   ./scripts/migrar.ps1 -Modo Detectar        # solo lectura: busca en la base el efecto de cada migracion (marcadores de
#                                              # scripts/migrar-marcadores.json) y la clasifica APLICADA_DETECTADA / AUSENTE /
#                                              # PARCIAL. No usa ni crea dbo.MigracionAplicada.
#   ./scripts/migrar.ps1 -Modo Baseline -SoloDetectadas
#                                              # para una base vieja sin registro (o con registro incompleto): registra como
#                                              # BASELINE solo las que Detectar da por aplicadas, sin ejecutar nada. Si alguna
#                                              # sale PARCIAL no registra nada (decide una persona). Despues: -Modo Aplicar.
#
# VAL-migrar-detectar (docs/work-items/VAL-migrar-detectar/PLAN.md):
#   - Con -SoloDetectadas solo se registra el tramo contiguo de detectadas desde la primera migracion; una detectada despues de
#     una ausente queda PENDIENTE para que -Modo Aplicar la re-ejecute en su orden (las de solo retiro y las de CREATE OR ALTER
#     son idempotentes). -IncluirFueraDeOrden registra tambien esas (solo si una persona lo decide).
#   - Una PARCIAL detiene -SoloDetectadas sin registrar nada. Si una persona reviso las lineas 'falta:' y decide re-ejecutar esas
#     migraciones, -ReaplicarParciales las deja PENDIENTE (con todo lo que va despues de la primera) en vez de detenerse. Caso tipico:
#     una base mantenida con deploy_schema.ps1, que crea tablas nuevas pero no borra objetos retirados por una migracion.
#   - -HastaVersion limita tambien -Modo Aplicar (aplica solo las pendientes con version <= HastaVersion).
#
# Migraciones administradas: archivos NN_nombre_up.sql y los antiguos de un solo archivo NN_nombre.sql con NN >= -VersionMinima
# (5 por defecto). Los *_down.sql no se aplican aqui (reversion manual: ejecutar el down y borrar la fila de MigracionAplicada).
# 01..04 son cargas iniciales y alineaciones anteriores al esquema por objeto; deploy_schema.ps1 y schema/seed/ las reemplazan.
# Orden: version numerica y luego nombre. Las pendientes se aplican en ese orden aunque haya registradas posteriores.
# Las migraciones usan sqlcmd con :on error exit y algunas :r $(MIGDIR)/../schema/..., por eso se copian migrations/ y schema/
# al contenedor y se pasa MIGDIR.
#
# Credenciales: igual que deploy_schema.ps1 y test_summary.ps1 (-Password, o SQL_CONTAINER_PASSWORD / MSSQL_SA_PASSWORD desde
# .env o el entorno). Nunca se imprimen.
# Salida estable: MIGRAR_<ESTADO> <nombre> por migracion y MIGRAR_RESUMEN ... al final (Detectar: MIGRAR_DETECTAR_<ESTADO> y
# MIGRAR_DETECTAR_RESUMEN). Codigo 0 si todo bien; 1 si hay deriva, una migracion falla, la base no es la esperada, faltan
# marcadores o (-SoloDetectadas) hay alguna PARCIAL.
# -Database, -MigrationsDir y -Marcadores existen para las pruebas (test/test_val_migrar.ps1 y test/test_val_migrar_detectar.ps1,
# bases temporales); en uso normal se dejan por defecto. Con una -Database distinta de gestionasistenciadb, -Modo Aplicar ejecuta
# una copia de migrations/ y schema/ con USE [gestionasistenciadb] cambiado por la base indicada (nunca toca la compartida).
param (
    [ValidateSet('Estado', 'Aplicar', 'Baseline', 'Detectar')][string]$Modo = 'Estado',
    [string]$ContainerName,
    [string]$Password,
    [string]$Database = 'gestionasistenciadb',
    [string]$MigrationsDir,
    [string]$Marcadores,
    [int]$VersionMinima = 5,
    [int]$HastaVersion = [int]::MaxValue,
    [switch]$SoloDetectadas,
    [switch]$IncluirFueraDeOrden,
    [switch]$ReaplicarParciales
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $MigrationsDir) { $MigrationsDir = Join-Path $root 'migrations' }
if (-not $Marcadores) { $Marcadores = Join-Path $PSScriptRoot 'migrar-marcadores.json' }
if ($SoloDetectadas -and $Modo -ne 'Baseline') { throw '-SoloDetectadas solo se usa con -Modo Baseline.' }
if ($IncluirFueraDeOrden -and -not $SoloDetectadas) { throw '-IncluirFueraDeOrden solo se usa con -Modo Baseline -SoloDetectadas.' }
if ($ReaplicarParciales -and -not $SoloDetectadas) { throw '-ReaplicarParciales solo se usa con -Modo Baseline -SoloDetectadas.' }

$envFile = Join-Path $root '.env'
if ((-not $Password -or -not $ContainerName) -and (Test-Path $envFile)) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $parts = $line.Split('=', 2)
            [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim())
        }
    }
}
if (-not $ContainerName) { $ContainerName = if ($env:SQL_CONTAINER_NAME) { $env:SQL_CONTAINER_NAME } else { 'sql_server_asistencias' } }
if (-not $Password) { $Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } elseif ($env:MSSQL_SA_PASSWORD) { $env:MSSQL_SA_PASSWORD } else { $null } }
if (-not $Password) { throw "SQL password is required. Create a local '.env' file from '.env.template', set SQL_CONTAINER_PASSWORD/MSSQL_SA_PASSWORD, or pass -Password." }
if ($Password -ceq 'CHANGE_ME') { throw "SQL password is still the 'CHANGE_ME' placeholder." }
if ($Database -notmatch '^[A-Za-z0-9_]+$') { throw "Nombre de base invalido: $Database" }

function Get-NormalizedSha256([string]$Path) {
    # Igual que scripts/freeze-manifest.ps1: SHA-256 del contenido con CRLF normalizado a LF.
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $ms = [System.IO.MemoryStream]::new()
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 13 -and ($i + 1) -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { continue }
        $ms.WriteByte($bytes[$i])
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return ([System.BitConverter]::ToString($sha.ComputeHash($ms.ToArray())).Replace('-', '')).ToLowerInvariant()
}

function Invoke-SqlQuery([string]$Query) {
    $out = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d $Database -U sa -P $Password -C -b -h -1 -W -s '|' -Q "SET NOCOUNT ON; $Query" 2>&1 |
        ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    if ($LASTEXITCODE -ne 0) { throw "Consulta fallida: $(($out | Select-Object -Last 3) -join ' | ')" }
    return , $out
}

function Invoke-SqlScript([string]$Sql, [string]$Prefijo) {
    # Ejecuta un lote largo desde archivo (la linea de comandos de Windows no admite consultas tan largas).
    $tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $local = Join-Path ([System.IO.Path]::GetTempPath()) "${Prefijo}_$tag.sql"
    [System.IO.File]::WriteAllText($local, $Sql, [System.Text.UTF8Encoding]::new($false))
    try {
        $null = & docker cp $local "${ContainerName}:/tmp/${Prefijo}_$tag.sql" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "No se pudo copiar ${Prefijo} al contenedor." }
        $out = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d $Database -U sa -P $Password -C -b -h -1 -W -i "/tmp/${Prefijo}_$tag.sql" 2>&1 |
            ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        if ($LASTEXITCODE -ne 0) { throw "Lote ${Prefijo} fallido: $(($out | Select-Object -Last 3) -join ' | ')" }
        return , $out
    }
    finally {
        Remove-Item $local -ErrorAction SilentlyContinue
        $null = & docker exec -u 0 $ContainerName rm -f "/tmp/${Prefijo}_$tag.sql" 2>&1
    }
}

# 1. Inventario de migraciones administradas
$migraciones = @(Get-ChildItem -Path $MigrationsDir -Filter '*.sql' -File | ForEach-Object {
    if ($_.Name -match '_down\.sql$') { return }
    if ($_.Name -notmatch '^(\d+)_([a-z0-9_]+?)(_up)?\.sql$') { return }
    $version = [int]$Matches[1]
    if ($version -lt $VersionMinima) { return }
    $nombre = $_.Name -replace '(_up)?\.sql$', ''
    [pscustomobject]@{ Version = $version; Nombre = $nombre; Archivo = $_.Name; Ruta = $_.FullName; Checksum = (Get-NormalizedSha256 $_.FullName) }
} | Sort-Object Version, Nombre)
$duplicadas = @($migraciones | Group-Object Nombre | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
if ($duplicadas.Count) { throw "Migraciones con el mismo nombre (archivo up y archivo unico a la vez): $($duplicadas -join ', ')" }

# 2. Base esperada
$precheck = (Invoke-SqlQuery "SELECT CONCAT(DB_NAME(), '|', CONVERT(varchar(80), SERVERPROPERTY('Edition')));") -join ''
if ($precheck -notmatch "^$Database\|") { throw "BLOCKED - base inesperada: $precheck" }

# 2.1 Deteccion por marcadores (VAL-migrar-detectar). Solo lectura: un SELECT por marcador, sin tablas temporales (evita
#     conflictos de intercalacion con tempdb) y sin escribir nada.
function ConvertTo-SqlLiteral([string]$Texto) { return "N'" + $Texto.Replace("'", "''") + "'" }

function Get-SentenciaMarcador($c, [int]$i) {
    # Devuelve un lote que imprime '<i>|1' si el objeto o dato existe y '<i>|0' si no.
    $nombreSeguro = '^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+){0,2}$'
    if ($c.PSObject.Properties['tabla'] -and -not $c.PSObject.Properties['donde']) {
        if ($c.tabla -notmatch $nombreSeguro) { throw "Marcador invalido (tabla): $($c.tabla)" }
        return "SELECT CONCAT('$i|', IIF(OBJECT_ID($(ConvertTo-SqlLiteral $c.tabla), N'U') IS NULL, 0, 1));"
    }
    if ($c.PSObject.Properties['columna']) {
        if ($c.columna -notmatch '^[A-Za-z0-9_]+\.[A-Za-z0-9_]+\.[A-Za-z0-9_]+$') { throw "Marcador invalido (columna): $($c.columna)" }
        $p = $c.columna.Split('.')
        return "SELECT CONCAT('$i|', IIF(COL_LENGTH($(ConvertTo-SqlLiteral "$($p[0]).$($p[1])"), $(ConvertTo-SqlLiteral $p[2])) IS NULL, 0, 1));"
    }
    if ($c.PSObject.Properties['indice']) {
        if ($c.indice -notmatch '^[A-Za-z0-9_]+\.[A-Za-z0-9_]+\.[A-Za-z0-9_]+$') { throw "Marcador invalido (indice): $($c.indice)" }
        $p = $c.indice.Split('.')
        return "SELECT CONCAT('$i|', IIF(EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID($(ConvertTo-SqlLiteral "$($p[0]).$($p[1])")) AND name = $(ConvertTo-SqlLiteral $p[2])), 1, 0));"
    }
    if ($c.PSObject.Properties['restriccion']) {
        if ($c.restriccion -notmatch '^[A-Za-z0-9_]+$') { throw "Marcador invalido (restriccion): $($c.restriccion)" }
        return "SELECT CONCAT('$i|', IIF(EXISTS (SELECT 1 FROM sys.objects WHERE name = $(ConvertTo-SqlLiteral $c.restriccion) AND type IN ('C', 'D', 'F', 'PK', 'UQ')), 1, 0));"
    }
    if ($c.PSObject.Properties['objeto'] -and -not $c.PSObject.Properties['contiene']) {
        if ($c.objeto -notmatch $nombreSeguro) { throw "Marcador invalido (objeto): $($c.objeto)" }
        return "SELECT CONCAT('$i|', IIF(OBJECT_ID($(ConvertTo-SqlLiteral $c.objeto)) IS NULL, 0, 1));"
    }
    if ($c.PSObject.Properties['objeto'] -and $c.PSObject.Properties['contiene']) {
        # Definicion de un modulo (SP, vista, funcion) que contiene un texto de una sola linea que trae la migracion.
        if ($c.objeto -notmatch $nombreSeguro) { throw "Marcador invalido (definicion): $($c.objeto)" }
        if ([string]::IsNullOrWhiteSpace($c.contiene) -or $c.contiene -match '[\r\n]') { throw "Marcador invalido (contiene) en $($c.objeto)" }
        return "SELECT CONCAT('$i|', IIF(CHARINDEX($(ConvertTo-SqlLiteral $c.contiene), ISNULL(OBJECT_DEFINITION(OBJECT_ID($(ConvertTo-SqlLiteral $c.objeto))), N'')) > 0, 1, 0));"
    }
    if ($c.PSObject.Properties['tabla'] -and $c.PSObject.Properties['donde']) {
        # Fila de catalogo: predicado SQL del archivo de marcadores (archivo del repositorio, no entrada de usuario). Si la tabla
        # o una columna no existe, el error de compilacion del lote dinamico se captura y cuenta como ausente.
        if ($c.tabla -notmatch $nombreSeguro) { throw "Marcador invalido (fila): $($c.tabla)" }
        $consulta = "SELECT CONCAT('$i|', IIF(EXISTS (SELECT 1 FROM $($c.tabla) WHERE $($c.donde)), 1, 0));"
        return "BEGIN TRY EXEC ($(ConvertTo-SqlLiteral $consulta)); END TRY BEGIN CATCH SELECT '$i|0'; END CATCH;"
    }
    throw "Marcador sin tipo reconocido: $($c | ConvertTo-Json -Compress)"
}

function Get-DescripcionMarcador($c) {
    $existe = -not ($c.PSObject.Properties['existe'] -and $c.existe -eq $false)
    $neg = if ($existe) { '' } else { 'NO ' }
    if ($c.PSObject.Properties['donde']) { return "${neg}fila $($c.tabla) WHERE $($c.donde)" }
    if ($c.PSObject.Properties['contiene']) { return "${neg}definicion $($c.objeto) contiene '$($c.contiene)'" }
    foreach ($t in 'tabla', 'columna', 'indice', 'restriccion', 'objeto') { if ($c.PSObject.Properties[$t]) { return "${neg}$t $($c.$t)" } }
    return ($c | ConvertTo-Json -Compress)
}

function Invoke-Deteccion {
    # Clasifica cada migracion del inventario: APLICADA_DETECTADA (todos los marcadores), AUSENTE (ninguno), PARCIAL (algunos),
    # SIN_MARCADORES (la migracion no tiene entrada en el archivo: es un error del repositorio).
    if (-not (Test-Path $Marcadores)) { throw "No existe el archivo de marcadores: $Marcadores" }
    $datos = [System.IO.File]::ReadAllText($Marcadores) | ConvertFrom-Json
    $porNombre = @{}
    foreach ($p in $datos.migraciones.PSObject.Properties) { $porNombre[$p.Name] = @($p.Value) }
    $sentencias = [System.Collections.Generic.List[string]]::new()
    $indice = @()
    foreach ($m in $migraciones) {
        if (-not $porNombre.ContainsKey($m.Nombre)) { continue }
        foreach ($c in $porNombre[$m.Nombre]) {
            $i = $indice.Count
            $sentencias.Add((Get-SentenciaMarcador $c $i))
            $existe = -not ($c.PSObject.Properties['existe'] -and $c.existe -eq $false)
            $indice += [pscustomobject]@{ Nombre = $m.Nombre; Existe = $existe; Descripcion = (Get-DescripcionMarcador $c) }
        }
    }
    $presentes = @{}
    if ($sentencias.Count) {
        $salida = Invoke-SqlScript ("SET NOCOUNT ON;`n" + ($sentencias -join "`n") + "`n") 'migrar_detectar'
        foreach ($l in $salida) { if ($l -match '^(\d+)\|([01])$') { $presentes[[int]$Matches[1]] = ($Matches[2] -eq '1') } }
    }
    $resultado = @()
    foreach ($m in $migraciones) {
        $mios = @(for ($i = 0; $i -lt $indice.Count; $i++) { if ($indice[$i].Nombre -eq $m.Nombre) { $i } })
        if (-not $mios.Count) { $resultado += [pscustomobject]@{ Migracion = $m; Estado = 'SIN_MARCADORES'; Ok = 0; Total = 0; Faltan = @(); SoloRetiro = $false }; continue }
        $faltan = @()
        foreach ($i in $mios) {
            if (-not $presentes.ContainsKey($i)) { throw "La deteccion no devolvio el marcador $i ($($indice[$i].Descripcion))." }
            if ($presentes[$i] -ne $indice[$i].Existe) { $faltan += $indice[$i].Descripcion }
        }
        $ok = $mios.Count - $faltan.Count
        $estado = if ($ok -eq $mios.Count) { 'APLICADA_DETECTADA' } elseif ($ok -eq 0) { 'AUSENTE' } else { 'PARCIAL' }
        $soloRetiro = -not @($mios | Where-Object { $indice[$_].Existe }).Count
        $resultado += [pscustomobject]@{ Migracion = $m; Estado = $estado; Ok = $ok; Total = $mios.Count; Faltan = $faltan; SoloRetiro = $soloRetiro }
    }
    # Tramo contiguo: desde la primera migracion, mientras todas esten detectadas.
    $contigua = $null
    foreach ($r in $resultado) { if ($r.Estado -eq 'APLICADA_DETECTADA') { $r | Add-Member -NotePropertyName Contigua -NotePropertyValue $true; $contigua = $r } else { break } }
    foreach ($r in $resultado) { if (-not $r.PSObject.Properties['Contigua']) { $r | Add-Member -NotePropertyName Contigua -NotePropertyValue $false } }
    foreach ($r in $resultado) {
        $extra = if ($r.Estado -eq 'APLICADA_DETECTADA' -and -not $r.Contigua) { ' fuera_de_orden=1' } else { '' }
        $retiro = if ($r.SoloRetiro) { ' solo_retiro=1' } else { '' }
        Write-Host "MIGRAR_DETECTAR_$($r.Estado) $($r.Migracion.Nombre) marcadores=$($r.Ok)/$($r.Total)$retiro$extra"
        if ($r.Estado -eq 'PARCIAL') { foreach ($f in $r.Faltan) { Write-Host "  falta: $f" } }
    }
    $hasta = if ($contigua) { "$($contigua.Migracion.Version) ($($contigua.Migracion.Nombre))" } else { 'ninguna' }
    $cuenta = { param($e) @($resultado | Where-Object { $_.Estado -eq $e }).Count }
    Write-Host ("MIGRAR_DETECTAR_RESUMEN total=$($resultado.Count) detectadas=$(& $cuenta 'APLICADA_DETECTADA') ausentes=$(& $cuenta 'AUSENTE') " +
        "parciales=$(& $cuenta 'PARCIAL') sin_marcadores=$(& $cuenta 'SIN_MARCADORES') contigua_hasta=$hasta")
    return , $resultado
}

if ($Modo -eq 'Detectar') {
    $existe = ((Invoke-SqlQuery "SELECT IIF(OBJECT_ID('dbo.MigracionAplicada', 'U') IS NULL, 0, 1);") -join '') -eq '1'
    Write-Host "MIGRAR_DETECTAR_BASE $Database registro=$(if ($existe) { 'presente' } else { 'ausente' }) (Detectar no lo usa ni lo modifica)"
    $det = Invoke-Deteccion
    if (@($det | Where-Object { $_.Estado -eq 'SIN_MARCADORES' }).Count) { Write-Host 'MIGRAR_FALLO hay migraciones sin marcadores en scripts/migrar-marcadores.json.'; exit 1 }
    exit 0
}

$detectadas = $null
if ($SoloDetectadas) {
    # Antes de crear o escribir el registro: si algo esta a medias no se registra nada.
    $det = Invoke-Deteccion
    $sin = @($det | Where-Object { $_.Estado -eq 'SIN_MARCADORES' })
    $parciales = @($det | Where-Object { $_.Estado -eq 'PARCIAL' })
    if ($sin.Count) { Write-Host "MIGRAR_FALLO sin marcadores: $(($sin | ForEach-Object { $_.Migracion.Nombre }) -join ', '). No se registra nada."; exit 1 }
    if ($parciales.Count -and $ReaplicarParciales) {
        Write-Host "MIGRAR_PARCIALES_PENDIENTES $(($parciales | ForEach-Object { $_.Migracion.Nombre }) -join ', ') (-ReaplicarParciales: quedan PENDIENTE y -Modo Aplicar las re-ejecuta en su orden)"
    }
    elseif ($parciales.Count) {
        Write-Host "MIGRAR_FALLO migraciones PARCIAL: $(($parciales | ForEach-Object { $_.Migracion.Nombre }) -join ', '). No se registra nada; una persona debe revisar la salida de -Modo Detectar."
        exit 1
    }
    $detectadas = @{}
    foreach ($r in $det) {
        if ($r.Estado -ne 'APLICADA_DETECTADA') { continue }
        if ($r.Contigua -or $IncluirFueraDeOrden) { $detectadas[$r.Migracion.Nombre] = $true }
        else { Write-Host "MIGRAR_DETECTADA_FUERA_DE_ORDEN $($r.Migracion.Nombre) (queda PENDIENTE: -Modo Aplicar la re-ejecuta en su orden)" }
    }
}

# 3. Registro
function Initialize-Registro {
    # Crea dbo.MigracionAplicada con el DDL de schema/tables/MigracionAplicada.sql (idempotente) en la base destino.
    $ddl = [System.IO.File]::ReadAllText((Join-Path $root 'schema/tables/MigracionAplicada.sql'))
    $ddl = $ddl -replace '(?im)^\s*USE\s+\[gestionasistenciadb\];\s*$', ''
    $tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $local = Join-Path ([System.IO.Path]::GetTempPath()) "migracion_aplicada_$tag.sql"
    [System.IO.File]::WriteAllText($local, $ddl, [System.Text.UTF8Encoding]::new($false))
    try {
        $null = & docker cp $local "${ContainerName}:/tmp/migracion_aplicada_$tag.sql" 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo copiar el DDL del registro al contenedor.' }
        $out = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d $Database -U sa -P $Password -C -b -i "/tmp/migracion_aplicada_$tag.sql" 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "No se pudo crear dbo.MigracionAplicada: $(($out | Select-Object -Last 3) -join ' | ')" }
    }
    finally {
        Remove-Item $local -ErrorAction SilentlyContinue
        $null = & docker exec -u 0 $ContainerName rm -f "/tmp/migracion_aplicada_$tag.sql" 2>&1
    }
}

$existeRegistro = ((Invoke-SqlQuery "SELECT IIF(OBJECT_ID('dbo.MigracionAplicada', 'U') IS NULL, 0, 1);") -join '') -eq '1'
if ($Modo -ne 'Estado' -and -not $existeRegistro) { Initialize-Registro; $existeRegistro = $true }
$registradas = @{}
if ($existeRegistro) {
    foreach ($fila in (Invoke-SqlQuery 'SELECT CONCAT(nombre, ''|'', checksumSha256, ''|'', modo) FROM dbo.MigracionAplicada ORDER BY version, nombre;')) {
        $p = $fila.Split('|')
        if ($p.Count -eq 3) { $registradas[$p[0]] = [pscustomobject]@{ Checksum = $p[1]; Modo = $p[2] } }
    }
}
else { Write-Host 'MIGRAR_REGISTRO_AUSENTE dbo.MigracionAplicada (se crea con -Modo Aplicar o -Modo Baseline, o con deploy_schema.ps1)' }

# 4. Clasificacion
$deriva = @(); $pendientes = @()
foreach ($m in $migraciones) {
    if ($registradas.ContainsKey($m.Nombre)) {
        $r = $registradas[$m.Nombre]
        if ($r.Checksum -ne $m.Checksum) { $deriva += $m; Write-Host "MIGRAR_DERIVA $($m.Nombre) registrado=$($r.Checksum.Substring(0, 12)) archivo=$($m.Checksum.Substring(0, 12))" }
        else { Write-Host "MIGRAR_$($r.Modo) $($m.Nombre)" }
    }
    else { $pendientes += $m; Write-Host "MIGRAR_PENDIENTE $($m.Nombre)" }
}
$sinArchivo = @($registradas.Keys | Where-Object { $_ -notin $migraciones.Nombre })
foreach ($n in $sinArchivo) { Write-Host "MIGRAR_REGISTRADA_SIN_ARCHIVO $n" }

if ($deriva.Count) {
    Write-Host "MIGRAR_RESUMEN modo=$Modo total=$($migraciones.Count) registradas=$($registradas.Count) pendientes=$($pendientes.Count) deriva=$($deriva.Count) aplicadas=0"
    Write-Host 'MIGRAR_FALLO deriva: un archivo ya aplicado cambio. No se aplica nada; revisar y corregir el registro a mano.'
    exit 1
}

function Add-Registro($m, [string]$modoRegistro, $duracionMs) {
    if ($m.Nombre -notmatch '^[a-z0-9_]+$' -or $m.Archivo -notmatch '^[a-z0-9_]+\.sql$' -or $m.Checksum -notmatch '^[0-9a-f]{64}$') { throw "Valores no validos para registrar $($m.Nombre)" }
    $dur = if ($null -eq $duracionMs) { 'NULL' } else { [string][int]$duracionMs }
    $null = Invoke-SqlQuery ("INSERT INTO dbo.MigracionAplicada (version, nombre, archivo, checksumSha256, modo, duracionMs) " +
        "VALUES ($($m.Version), '$($m.Nombre)', '$($m.Archivo)', '$($m.Checksum)', '$modoRegistro', $dur);")
}

function Copy-ConBaseCambiada([string]$Origen, [string]$Destino) {
    # Copia los .sql cambiando [gestionasistenciadb] por la base de la prueba; conserva la marca BOM de cada archivo.
    $null = New-Item -ItemType Directory -Path $Destino -Force
    Copy-Item -Path (Join-Path $Origen '*') -Destination $Destino -Recurse -Force
    Get-ChildItem -Path $Destino -Filter '*.sql' -File -Recurse | ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $texto = [System.IO.File]::ReadAllText($_.FullName)
        if ($texto -match '\[gestionasistenciadb\]') {
            [System.IO.File]::WriteAllText($_.FullName, $texto.Replace('[gestionasistenciadb]', "[$Database]"), [System.Text.UTF8Encoding]::new($bom))
        }
    }
}

$aplicadas = 0
if ($Modo -eq 'Baseline') {
    foreach ($m in @($pendientes | Where-Object { $_.Version -le $HastaVersion })) {
        if ($null -ne $detectadas -and -not $detectadas.ContainsKey($m.Nombre)) { continue }
        Add-Registro $m 'BASELINE' $null
        $aplicadas++
        Write-Host "MIGRAR_REGISTRADA_BASELINE $($m.Nombre)"
    }
}
elseif ($Modo -eq 'Aplicar' -and @($pendientes | Where-Object { $_.Version -le $HastaVersion }).Count) {
    $tag = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $remote = "/tmp/migrar_$tag"
    $stage = $null
    try {
        $origenMig = $MigrationsDir; $origenSchema = Join-Path $root 'schema'
        if ($Database -ne 'gestionasistenciadb') {
            $stage = Join-Path ([System.IO.Path]::GetTempPath()) "migrar_$tag"
            Copy-ConBaseCambiada $MigrationsDir (Join-Path $stage 'migrations')
            Copy-ConBaseCambiada (Join-Path $root 'schema') (Join-Path $stage 'schema')
            $origenMig = Join-Path $stage 'migrations'; $origenSchema = Join-Path $stage 'schema'
        }
        $null = & docker exec -u 0 $ContainerName mkdir -p "$remote/migrations" "$remote/schema" 2>&1
        $null = & docker cp (Join-Path $origenMig '.') "${ContainerName}:$remote/migrations" 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo copiar migrations/ al contenedor.' }
        $null = & docker cp (Join-Path $origenSchema '.') "${ContainerName}:$remote/schema" 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo copiar schema/ al contenedor.' }
        $null = & docker exec -u 0 $ContainerName chmod -R a+rX $remote 2>&1
        foreach ($m in @($pendientes | Where-Object { $_.Version -le $HastaVersion })) {
            $reloj = [System.Diagnostics.Stopwatch]::StartNew()
            $out = @(& docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d $Database -U sa -P $Password -C -b -I -t 1800 `
                    -v "MIGDIR=$remote/migrations" -i "$remote/migrations/$($m.Archivo)" 2>&1 | ForEach-Object { "$_" })
            $rc = $LASTEXITCODE
            $reloj.Stop()
            if ($rc -ne 0) {
                Write-Host "MIGRAR_FALLO $($m.Nombre) rc=$rc"
                $out | Select-Object -Last 6 | ForEach-Object { Write-Host "  $_" }
                Write-Host "MIGRAR_RESUMEN modo=$Modo total=$($migraciones.Count) registradas=$($registradas.Count + $aplicadas) pendientes=$($pendientes.Count - $aplicadas) deriva=0 aplicadas=$aplicadas"
                exit 1
            }
            Add-Registro $m 'APLICADA' $reloj.ElapsedMilliseconds
            $aplicadas++
            Write-Host "MIGRAR_APLICADA_AHORA $($m.Nombre) ms=$($reloj.ElapsedMilliseconds)"
        }
    }
    finally {
        $null = & docker exec -u 0 $ContainerName rm -rf $remote 2>&1
        if ($stage) { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

$restantes = if ($Modo -eq 'Estado') { $pendientes.Count } else { $pendientes.Count - $aplicadas }
Write-Host "MIGRAR_RESUMEN modo=$Modo total=$($migraciones.Count) registradas=$($registradas.Count + $aplicadas) pendientes=$restantes deriva=0 aplicadas=$aplicadas"
exit 0
