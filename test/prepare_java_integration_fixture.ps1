param(
    [Parameter(Mandatory = $true)] [string]$ContainerName,
    [Parameter(Mandatory = $true)] [string]$AdminPassword
)

$ErrorActionPreference = 'Stop'
$database = 'gestionasistenciadb'
$fixture = Join-Path $PSScriptRoot 'fixtures/maint_003g_attendance_fixture.sql'
$targetSql = @"
SET NOCOUNT ON;
IF DB_NAME() <> N'$database' OR CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) NOT LIKE N'%Developer Edition%'
    THROW 52210, 'BLOCKED - Java integration fixtures require the local Developer database.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_parametro WHERE grupo = N'OPERACION' AND clave = N'AMBIENTE' AND UPPER(valor) IN (N'PRODUCCION', N'PROD', N'PRODUCTION'))
    THROW 52211, 'BLOCKED - OPERACION/AMBIENTE declares a production database.', 1;
SELECT CONCAT(DB_NAME(), '|', CONVERT(varchar(80), SERVERPROPERTY('Edition')));
"@
$targetCheck = @(docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd `
    -S localhost -d $database -U sa -P $AdminPassword -C -b -h -1 -W -Q $targetSql 2>&1)
if ($LASTEXITCODE -ne 0 -or ($targetCheck -join '').Trim() -notmatch '^gestionasistenciadb\|Developer Edition') {
    throw 'BLOCKED - unsafe database target: Java integration fixtures require gestionasistenciadb on Developer Edition.'
}

docker cp $fixture "$($ContainerName):/tmp/maint_003g_attendance_fixture.sql" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not copy the MAINT-003G fixture into the isolated container.' }

$output = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd `
    -S localhost -d $database -U sa -P $AdminPassword -C -b -h -1 -W `
    -i /tmp/maint_003g_attendance_fixture.sql 2>&1
if ($LASTEXITCODE -ne 0) { throw 'MAINT-003G Java integration fixture failed.' }

if (($output | Out-String) -notmatch 'TEST_FIXTURE_READY\|session=[0-9A-Fa-f-]{36}\|rows=2') {
    throw 'MAINT-003G fixture did not produce its readiness evidence.'
}

Write-Host 'TEST_PASS:MAINT_003G_JAVA_ATTENDANCE_FIXTURE'

# MAINT-003H: datos para que los 3 escenarios dependientes de datos se EJECUTEN (sin tocar los tests ni sus Assumptions)
$fixtureData = Join-Path $PSScriptRoot 'fixtures/maint_003h_failsafe_data_fixture.sql'
docker cp $fixtureData "$($ContainerName):/tmp/maint_003h_failsafe_data_fixture.sql" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not copy the MAINT-003H data fixture into the isolated container.' }
$outputData = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd `
    -S localhost -d $database -U sa -P $AdminPassword -C -b -h -1 -W `
    -i /tmp/maint_003h_failsafe_data_fixture.sql 2>&1
if ($LASTEXITCODE -ne 0) { throw "MAINT-003H data fixture failed: $($outputData | Out-String)" }
if (($outputData | Out-String) -notmatch 'TEST_FIXTURE_READY\|maint003h\|multi=1\|empty=1\|horarios=[1-9]') {
    throw 'MAINT-003H data fixture did not produce its readiness evidence.'
}
Write-Host 'TEST_PASS:MAINT_003H_JAVA_DATA_FIXTURE'

# VAL-PRU-04 (oleada 3): 12 estudiantes del directorio del primer administrador (CoreViewQueriesJpaParityIT pagina 3 x 5)
$fixtureDirectorio = Join-Path $PSScriptRoot 'fixtures/val_pru04_directorio_estudiantes_fixture.sql'
docker cp $fixtureDirectorio "$($ContainerName):/tmp/val_pru04_directorio_estudiantes_fixture.sql" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not copy the VAL-PRU-04 directory fixture into the isolated container.' }
$outputDirectorio = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd `
    -S localhost -d $database -U sa -P $AdminPassword -C -b -h -1 -W `
    -i /tmp/val_pru04_directorio_estudiantes_fixture.sql 2>&1
if ($LASTEXITCODE -ne 0) { throw "VAL-PRU-04 directory fixture failed: $($outputDirectorio | Out-String)" }
if (($outputDirectorio | Out-String) -notmatch 'TEST_FIXTURE_READY\|valpru04\|estudiantesDirectorio=12') {
    throw 'VAL-PRU-04 directory fixture did not produce its readiness evidence.'
}
Write-Host 'TEST_PASS:VAL_PRU04_JAVA_DIRECTORY_FIXTURE'
