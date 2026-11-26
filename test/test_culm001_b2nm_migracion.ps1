# CULM-001 B2NM (B2NM-12, DEC-025): secuencia completa de las migraciones 17 y 18 sobre una BD PROPIA restaurada desde un backup COPY_ONLY del
# esquema A+B. Nunca toca la BD compartida. Credenciales: se leen de .env en cada ejecucion (no se escriben en ningun archivo).
# Uso: .\test\test_culm001_b2nm_migracion.ps1 -Backup /var/opt/mssql/data/b2nm_copy.bak [-Database gestionasistenciadb_b2nm_mig]
param(
    [Parameter(Mandatory = $true)][string]$Backup,
    [string]$Database = 'gestionasistenciadb_b2nm_mig'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
$map = @{}
Get-Content $envFile | ForEach-Object { if ($_ -match '^\s*([^#=]+)=(.*)$') { $map[$matches[1].Trim().TrimStart([char]0xFEFF)] = $matches[2].Trim() } }
$container = $map['SQL_CONTAINER_NAME']
$pw = $map['SQL_CONTAINER_PASSWORD']
if (-not $container -or -not $pw) { throw 'Falta SQL_CONTAINER_NAME o SQL_CONTAINER_PASSWORD en .env' }
if ($Database -eq 'gestionasistenciadb') { throw 'Esta prueba nunca se ejecuta contra la BD compartida.' }

function Invoke-Sql([string]$db, [string]$query) {
    # La consulta viaja en un archivo: el paso de comillas a docker/sqlcmd por linea de comandos no es fiable en PowerShell 5.1.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('b2nm_q_' + [Guid]::NewGuid().ToString('N') + '.sql')
    Set-Content -Path $tmp -Value ("SET NOCOUNT ON;`r`n" + $query) -Encoding UTF8
    docker cp $tmp "${container}:/tmp/$([IO.Path]::GetFileName($tmp))" | Out-Null
    $out = docker exec $container /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -d $db -b -h -1 -W -i "/tmp/$([IO.Path]::GetFileName($tmp))" 2>&1
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { throw "SQL fallo: $out :: $query" }
    return ($out | Out-String).Trim()
}
function Invoke-File([string]$db, [string]$path, [switch]$ExpectError, [int]$ErrorNumber = 0) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("b2nm_mig_" + [IO.Path]::GetFileName($path))
    (Get-Content $path -Raw -Encoding UTF8) -replace '\[gestionasistenciadb\]', "[$db]" | Set-Content $tmp -Encoding UTF8
    docker cp $tmp "${container}:/tmp/$([IO.Path]::GetFileName($tmp))" | Out-Null
    $out = docker exec $container /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $pw -C -d $db -b -i "/tmp/$([IO.Path]::GetFileName($tmp))" 2>&1 | Out-String
    $failed = $LASTEXITCODE -ne 0
    if ($ExpectError) {
        if (-not $failed) { throw "Se esperaba error $ErrorNumber en $path" }
        if ($ErrorNumber -and $out -notmatch "Msg $ErrorNumber") { throw "Se esperaba Msg $ErrorNumber en $path; salida: $out" }
    } elseif ($failed) { throw "Fallo $path`n$out" }
}
function Assert-True([bool]$cond, [string]$msg) { if (-not $cond) { throw "TEST FAILED: $msg" } }
function Restore-Db([string]$name) {
    Invoke-Sql master "IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END" | Out-Null
    Invoke-Sql master "RESTORE DATABASE [$name] FROM DISK='$Backup' WITH MOVE 'gestionasistenciadb' TO '/var/opt/mssql/data/$name.mdf', MOVE 'gestionasistenciadb_log' TO '/var/opt/mssql/data/${name}_log.ldf'" | Out-Null
}
function Estado([string]$db) {
    $col = [int](Invoke-Sql $db "SELECT IIF(COL_LENGTH('Asignatura','semestrePlanEstudio') IS NULL,0,1)")
    $fk = [int](Invoke-Sql $db "SELECT COUNT(*) FROM sys.foreign_keys WHERE name='FK_Asignatura_SemestrePlanEstudio'")
    $nulos = if ($col -eq 1) { [int](Invoke-Sql $db "SELECT is_nullable FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Asignatura') AND name='semestrePlanEstudio'") } else { -1 }
    $tc = [int](Invoke-Sql $db 'SELECT @@TRANCOUNT')
    Assert-True ($tc -eq 0) '@@TRANCOUNT debe ser 0 tras cada paso'
    return @{ Columna = $col; FK = $fk; Nullable = $nulos }
}
$m = Join-Path $root 'migrations'
$up17 = Join-Path $m '17_culm001_b2nm_asignatura_plan_up.sql'; $dn17 = Join-Path $m '17_culm001_b2nm_asignatura_plan_down.sql'
$up18 = Join-Path $m '18_culm001_b2nm_retirar_semestre_plan_up.sql'; $dn18 = Join-Path $m '18_culm001_b2nm_retirar_semestre_plan_down.sql'
$compila = Join-Path $PSScriptRoot 'test_culm001_b2nm_compilacion.sql'

Restore-Db $Database
$totalAsig = [int](Invoke-Sql $Database 'SELECT COUNT(*) FROM dbo.Asignatura')

# 1. 17 up
Invoke-File $Database $up17
$e = Estado $Database
Assert-True ([int](Invoke-Sql $Database 'SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio') -eq $totalAsig) 'paso 1: vinculos = asignaturas'
Assert-True ($e.Columna -eq 1 -and $e.FK -eq 1 -and $e.Nullable -eq 1) 'paso 1: columna presente y NULL, FK presente'
Invoke-File $Database $compila

# 2. crear una asignatura con los SP nuevos (la columna queda NULL) y cambiar el caracter del vinculo de una existente
$coord = Invoke-Sql $Database "SELECT TOP 1 c.usuario FROM dbo.Coordinador c JOIN dbo.Programa p ON p.coordinador = c.id ORDER BY p.id"
$plan = Invoke-Sql $Database 'SELECT TOP 1 pe.id FROM dbo.PlanEstudio pe ORDER BY pe.id'
$area = Invoke-Sql $Database 'SELECT TOP 1 codigo FROM dbo.Area ORDER BY id'
$sem = Invoke-Sql $Database "SELECT TOP 1 s.numero FROM dbo.SemestrePlanEstudio spe JOIN dbo.Semestre s ON s.id = spe.semestre WHERE spe.planEstudio = '$plan'"
$q = "DECLARE @c UNIQUEIDENTIFIER = NEWID(), @a UNIQUEIDENTIFIER = NEWID(); EXEC dbo.usp_crear_asignatura @idAsignatura = @a, @codigo = N'MIG-B2NM', @nombre = N'Migracion B2NM', @creditos = 3, @idPlanEstudio = '$plan', @semestreNumero = $sem, @nombreArea = N'$area', @nombreComponente = N'ESP', @idCorrelacion = @c, @idUsuarioEjecutor = '$coord';"
$null = Invoke-Sql $Database $q
Assert-True ([int](Invoke-Sql $Database "SELECT COUNT(*) FROM dbo.Asignatura WHERE codigo = N'MIG-B2NM' AND semestrePlanEstudio IS NULL") -eq 1) 'paso 2: la asignatura nueva queda con la columna NULL'
Assert-True ([int](Invoke-Sql $Database "SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio ape JOIN dbo.Asignatura a ON a.id = ape.asignatura WHERE a.codigo = N'MIG-B2NM'") -eq 1) 'paso 2: la asignatura nueva tiene su vinculo'
$null = Estado $Database

# 3. 17 up repetido: sin cambios
$antes = Invoke-Sql $Database 'SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio'
Invoke-File $Database $up17
Assert-True ((Invoke-Sql $Database 'SELECT COUNT(*) FROM dbo.AsignaturaPlanEstudio') -eq $antes) 'paso 3: 17 up repetido no cambia nada'
$null = Estado $Database

# 6 (antes de aplicar 18 en la BD principal). Fallo forzado de la 18 sobre una copia: THROW 52901, columna y FK intactas
$copia = "${Database}_f"
Invoke-Sql master "BACKUP DATABASE [$Database] TO DISK='/var/opt/mssql/data/${copia}.bak' WITH COPY_ONLY, INIT" | Out-Null
Invoke-Sql master "IF DB_ID(N'$copia') IS NOT NULL BEGIN ALTER DATABASE [$copia] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$copia]; END; RESTORE DATABASE [$copia] FROM DISK='/var/opt/mssql/data/${copia}.bak' WITH MOVE 'gestionasistenciadb' TO '/var/opt/mssql/data/$copia.mdf', MOVE 'gestionasistenciadb_log' TO '/var/opt/mssql/data/${copia}_log.ldf'" | Out-Null
Invoke-Sql $copia "DELETE FROM dbo.AsignaturaPlanEstudio WHERE asignatura = (SELECT TOP 1 id FROM dbo.Asignatura WHERE codigo = N'MIG-B2NM')" | Out-Null
Invoke-File $copia $up18 -ExpectError -ErrorNumber 52901
$ec = Estado $copia
Assert-True ($ec.Columna -eq 1 -and $ec.FK -eq 1) 'paso 6: tras 52901 la columna y la FK quedan intactas'
Invoke-Sql master "ALTER DATABASE [$copia] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$copia]" | Out-Null

# 4. 18 up y 5. repetido
Invoke-File $Database $up18
$e = Estado $Database
Assert-True ($e.Columna -eq 0 -and $e.FK -eq 0) 'paso 4: columna y FK eliminadas'
Invoke-File $Database $compila
Invoke-File $Database $up18
$null = Estado $Database

# 9. 17 down sin la columna: THROW 52903 sin cambios
Invoke-File $Database $dn17 -ExpectError -ErrorNumber 52903
Assert-True ([int](Invoke-Sql $Database 'SELECT COUNT(*) FROM sys.tables WHERE name = ''AsignaturaPlanEstudio''') -eq 1) 'paso 9: 52903 no cambia nada'

# 10. un vinculo adicional (inactivo) -> 52902 en ambos down
Invoke-Sql $Database "INSERT INTO dbo.AsignaturaPlanEstudio (id, asignatura, semestrePlanEstudio, caracter, estaActivo, fechaVinculacionUtc, fechaDesvinculacionUtc) SELECT TOP 1 NEWID(), ape.asignatura, spe2.id, ape.caracter, 0, '2020-01-01', '2020-02-01' FROM dbo.AsignaturaPlanEstudio ape CROSS JOIN (SELECT TOP 1 id FROM dbo.SemestrePlanEstudio ORDER BY id DESC) spe2 WHERE spe2.id <> ape.semestrePlanEstudio" | Out-Null
$extra = [int](Invoke-Sql $Database 'SELECT COUNT(*) FROM (SELECT asignatura FROM dbo.AsignaturaPlanEstudio GROUP BY asignatura HAVING COUNT(*) > 1) x')
if ($extra -gt 0) {
    Invoke-File $Database $dn18 -ExpectError -ErrorNumber 52902
    Invoke-Sql $Database "DELETE FROM dbo.AsignaturaPlanEstudio WHERE estaActivo = 0" | Out-Null
}

# 7. 18 down y 8. 17 down
Invoke-File $Database $dn18
$e = Estado $Database
Assert-True ($e.Columna -eq 1 -and $e.FK -eq 1 -and $e.Nullable -eq 1) 'paso 7: 18 down restaura la columna NULL y la FK'
Invoke-File $Database $dn17
$e = Estado $Database
Assert-True ($e.Columna -eq 1 -and $e.Nullable -eq 0) 'paso 8: 17 down deja la columna NOT NULL'
Assert-True ([int](Invoke-Sql $Database "SELECT COUNT(*) FROM dbo.Asignatura WHERE codigo = N'MIG-B2NM' AND semestrePlanEstudio IS NOT NULL") -eq 1) 'paso 8: la asignatura creada en el paso 2 recupera su semestre'
Invoke-File $Database $compila

# 11. 17 up -> 18 up otra vez
Invoke-File $Database $up17
Invoke-File $Database $up18
$e = Estado $Database
Assert-True ($e.Columna -eq 0) 'paso 11: 17 up -> 18 up sin errores'
Invoke-File $Database $compila
Invoke-Sql master "ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$Database]" | Out-Null
Write-Host 'TEST_PASS:CULM001_B2NM_MIGRACION'
