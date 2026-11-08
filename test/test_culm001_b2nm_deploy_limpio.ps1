# CULM-001 B2NM (B2NM-16): el esquema de schema/ se despliega sobre una BD VACIA y propia, en el orden de deploy_schema.ps1
# (tablas -> triggers -> funciones -> vistas -> SP -> seguridad -> semillas), y deja el estado posterior a la migracion 18:
# sin Asignatura.semestrePlanEstudio ni FK_Asignatura_SemestrePlanEstudio, con la tabla puente y el catalogo de caracter.
# Nunca toca la BD compartida. Credenciales: se leen de .env en cada ejecucion.
# Uso: .\test\test_culm001_b2nm_deploy_limpio.ps1 [-Database gestionasistenciadb_b2nm_clean]
param([string]$Database = 'gestionasistenciadb_b2nm_clean')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$map = @{}
Get-Content (Join-Path $root '.env') | ForEach-Object { if ($_ -match '^\s*([^#=]+)=(.*)$') { $map[$matches[1].Trim().TrimStart([char]0xFEFF)] = $matches[2].Trim() } }
$container = $map['SQL_CONTAINER_NAME']; $pw = $map['SQL_CONTAINER_PASSWORD']
if (-not $container -or -not $pw) { throw 'Falta SQL_CONTAINER_NAME o SQL_CONTAINER_PASSWORD en .env' }
if ($Database -eq 'gestionasistenciadb') { throw 'Esta prueba nunca se ejecuta contra la BD compartida.' }

function Invoke-Q([string]$db, [string]$query) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('b2nm_dl_' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $tmp -Value ("SET NOCOUNT ON;`r`n" + $query) -Encoding UTF8
    docker cp $tmp "${container}:/tmp/$([IO.Path]::GetFileName($tmp))" | Out-Null
    $out = docker exec $container /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -d $db -b -h -1 -W -i "/tmp/$([IO.Path]::GetFileName($tmp))" 2>&1
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { throw "SQL fallo: $out" }
    return ($out | Out-String).Trim()
}

Invoke-Q master "IF DB_ID(N'$Database') IS NOT NULL BEGIN ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$Database]; END; CREATE DATABASE [$Database];" | Out-Null

# Copia del esquema con el nombre de la BD sustituido, dentro del contenedor (ruta unica por ejecucion)
$stage = Join-Path ([IO.Path]::GetTempPath()) ('b2nm_schema_' + [Guid]::NewGuid().ToString('N'))
Copy-Item (Join-Path $root 'schema') $stage -Recurse
Get-ChildItem $stage -Filter *.sql -Recurse | ForEach-Object {
    (Get-Content $_.FullName -Raw -Encoding UTF8) -replace '\[gestionasistenciadb\]', "[$Database]" | Set-Content $_.FullName -Encoding UTF8
}
$dest = "/tmp/b2nm_schema_$([Guid]::NewGuid().ToString('N'))"
docker cp $stage "${container}:$dest" | Out-Null

function Apply([string]$dir, [bool]$tolerant) {
    $files = Get-ChildItem (Join-Path $stage $dir) -Filter *.sql -Recurse | Sort-Object Name
    $pending = @($files)
    $pass = 1
    while ($pending.Count -gt 0 -and $pass -le 15) {
        $failed = @()
        foreach ($f in $pending) {
            $rel = $f.FullName.Substring($stage.Length).Replace('\', '/')
            $out = docker exec $container /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -d $Database -b -i "$dest$rel" 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0 -or $out -match 'Msg \d+, Level 1[1-9]') {
                if ($tolerant) { $failed += $f } else { throw "Fallo $($f.Name): $out" }
            }
        }
        if ($failed.Count -eq $pending.Count) { throw "Dependencias sin resolver en ${dir}: $($failed.Name -join ', ')" }
        $pending = $failed; $pass++
    }
    if ($pending.Count -gt 0) { throw "Sin resolver en ${dir}: $($pending.Name -join ', ')" }
}
Apply 'tables' $false
if (Test-Path (Join-Path $stage 'triggers')) { Apply 'triggers' $false }
Apply 'functions' $false
Apply 'views' $true
Apply 'stored-procedures' $true
if (Test-Path (Join-Path $stage 'security')) { Apply 'security' $true }
Apply 'seed' $false

if ([int](Invoke-Q $Database "SELECT IIF(COL_LENGTH('dbo.Asignatura','semestrePlanEstudio') IS NULL,1,0)") -ne 1) { throw 'TEST FAILED: B2NM-16 la columna Asignatura.semestrePlanEstudio no debe existir en un despliegue limpio.' }
if ([int](Invoke-Q $Database "SELECT COUNT(*) FROM sys.foreign_keys WHERE name = 'FK_Asignatura_SemestrePlanEstudio'") -ne 0) { throw 'TEST FAILED: B2NM-16 el bloque 18 de FKs no debe existir.' }
if ([int](Invoke-Q $Database "SELECT COUNT(*) FROM sys.tables WHERE name IN ('AsignaturaPlanEstudio','CaracterAsignaturaPlan')") -ne 2) { throw 'TEST FAILED: B2NM-16 faltan la tabla puente o el catalogo de caracter.' }
if ([int](Invoke-Q $Database 'SELECT COUNT(*) FROM dbo.CaracterAsignaturaPlan') -ne 2) { throw 'TEST FAILED: B2NM-16 el catalogo de caracter debe tener OBL y OPT.' }
# B2NM-15 sobre el despliegue limpio
$compila = (Get-Content (Join-Path $PSScriptRoot 'test_culm001_b2nm_compilacion.sql') -Raw -Encoding UTF8) -replace '\[gestionasistenciadb\]', "[$Database]"
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'b2nm_dl_compila.sql'
Set-Content $tmp $compila -Encoding UTF8
docker cp $tmp "${container}:/tmp/b2nm_dl_compila.sql" | Out-Null
$out = docker exec $container /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -d $Database -b -i /tmp/b2nm_dl_compila.sql 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $out -notmatch 'TEST_PASS:CULM001_B2NM_COMPILACION') { throw "TEST FAILED: B2NM-15 en el despliegue limpio: $out" }
Remove-Item $stage -Recurse -ErrorAction SilentlyContinue
Invoke-Q master "ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$Database];" | Out-Null
Write-Host 'TEST_PASS:CULM001_B2NM_DEPLOY_LIMPIO'
