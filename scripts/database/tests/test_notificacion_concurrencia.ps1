#Requires -Version 5.1
<#
.SYNOPSIS
  TEST_PLAN §1.7: Prueba de concurrencia de reserva de notificaciones outbox.
  Carga 200 PENDIENTE; lanza 4 sesiones simultaneas que ejecutan
  usp_reservar_notificaciones_salientes(@lote=50) con instancias distintas.
  Esperado: union de filas devueltas = 200, interseccion vacia (ninguna fila
  devuelta dos veces), sin bloqueos prolongados (READPAST), todas las filas
  en RESERVADA con su dueno correcto. Cero residuos al finalizar.
#>
param(
    [string]$ContainerName = 'sql_server_asistencias',
    [string]$Password = $(if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } else { $env:MSSQL_SA_PASSWORD }),
    [string]$Database = 'gestionasistenciadb'
)
$ErrorActionPreference = 'Stop'
if (-not $Password) {
    $envFile = Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) '.env'
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
                $parts = $line.Split('=', 2)
                [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim())
            }
        }
        $Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } else { $env:MSSQL_SA_PASSWORD }
    }
}
if (-not $Password) { throw 'SQL password is required: pass -Password or set SQL_CONTAINER_PASSWORD/MSSQL_SA_PASSWORD.' }

function Invoke-Sql([string]$Query) {
    $localFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $localFile -Value $Query -Encoding utf8
    $remoteFile = "/tmp/concurrencia_$([guid]::NewGuid().ToString('N')).sql"
    docker cp $localFile "${ContainerName}:${remoteFile}" | Out-Null
    Remove-Item -Path $localFile -Force -ErrorAction SilentlyContinue
    $out = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d $Database -U sa -P $Password -C -b -h -1 -W -i $remoteFile 2>&1
    $code = $LASTEXITCODE
    docker exec -u 0 $ContainerName rm -f $remoteFile | Out-Null
    if ($code -ne 0) { throw "sqlcmd fallo: $($out -join '; ')" }
    return @($out | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
}

$tag = "CONC_" + [guid]::NewGuid().ToString('N').Substring(0, 8)

Write-Host "Iniciando prueba de concurrencia NOTIF-001 ($tag)..."

# 1. Cargar 200 filas en estado PENDIENTE
$setupSql = @"
SET NOCOUNT ON;
DECLARE @idPendiente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE');
IF @idPendiente IS NULL THROW 53901, 'Estado PENDIENTE no encontrado.', 1;

DECLARE @i INT = 1;
WHILE @i <= 200
BEGIN
    INSERT INTO dbo.NotificacionSaliente (
        id, tipo, asunto, mensaje, destinatarios, datos, idEstado, intentos, creadoEn, proximoIntentoEn, idCorrelacion
    ) VALUES (
        NEWID(), '$tag', N'Asunto', N'Mensaje', N'[{"rol":"E","idUsuario":"' + CONVERT(NVARCHAR(36), NEWID()) + N'"}]', N'{}',
        @idPendiente, 0, DATEADD(MILLISECOND, @i * 10, SYSUTCDATETIME()), SYSUTCDATETIME(), NEWID()
    );
    SET @i = @i + 1;
END;
SELECT COUNT(*) FROM dbo.NotificacionSaliente WHERE tipo = '$tag';
"@

$inserted = @(Invoke-Sql $setupSql)
if ($inserted.Count -eq 0 -or [int]$inserted[0] -ne 200) {
    throw "No se pudieron insertar 200 filas de prueba: $($inserted -join '; ')"
}
Write-Host "200 filas PENDIENTE insertadas."

try {
    # 2. Lanzar 4 workers simultaneos
    $workers = @('worker-1', 'worker-2', 'worker-3', 'worker-4')
    $workerJobs = @()

    foreach ($instancia in $workers) {
        $workerSql = @"
SET NOCOUNT ON;
EXEC dbo.usp_reservar_notificaciones_salientes
    @lote = 50,
    @leaseSegundos = 60,
    @instancia = N'$instancia',
    @idCorrelacion = '$([guid]::NewGuid())';
"@
        $localF = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $localF -Value $workerSql -Encoding utf8
        $remoteF = "/tmp/worker_${instancia}_$([guid]::NewGuid().ToString('N')).sql"
        docker cp $localF "${ContainerName}:${remoteF}" | Out-Null
        Remove-Item -Path $localF -Force -ErrorAction SilentlyContinue

        $jobScript = {
            param($cn, $pw, $db, $rf)
            $out = docker exec $cn /opt/mssql-tools18/bin/sqlcmd -S localhost -d $db -U sa -P $pw -C -b -h -1 -W -s '|' -i $rf 2>&1
            $code = $LASTEXITCODE
            docker exec $cn rm -f $rf | Out-Null
            if ($code -ne 0) { throw "Worker fallo: $($out -join '; ')" }
            return @($out | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        }
        $workerJobs += Start-Job -ScriptBlock $jobScript -ArgumentList $ContainerName, $Password, $Database, $remoteF
    }

    $allIds = [System.Collections.Generic.List[string]]::new()
    foreach ($j in $workerJobs) {
        $lines = @(Receive-Job -Job $j -Wait)
        foreach ($line in $lines) {
            $parts = $line.Split('|')
            if ($parts.Count -gt 0 -and $parts[0] -match '^[0-9a-fA-F-]{36}$') {
                $allIds.Add($parts[0].ToUpper())
            }
        }
    }

    Write-Host "Total de IDs devueltos por los 4 trabajadores: $($allIds.Count)"
    if ($allIds.Count -ne 200) {
        throw "TEST FAILED CONCURRENCIA: Se esperaban 200 IDs devueltos en total, hubo $($allIds.Count)."
    }

    $distinctIds = @($allIds | Select-Object -Unique)
    Write-Host "Total de IDs unicos: $($distinctIds.Count)"
    if ($distinctIds.Count -ne 200) {
        throw "TEST FAILED CONCURRENCIA: Interseccion no vacia. Hubo $(200 - $distinctIds.Count) duplicados."
    }

    # Verificar que las 200 filas quedaron en RESERVADA
    $verifSql = @"
SET NOCOUNT ON;
SELECT COUNT(*) FROM dbo.NotificacionSaliente
WHERE tipo = '$tag'
  AND idEstado = (SELECT id FROM dbo.EstadoNotificacion WHERE codigo = 'RESERVADA')
  AND reservadoPor IN ('worker-1', 'worker-2', 'worker-3', 'worker-4')
  AND intentos = 1;
"@
    $verif = @(Invoke-Sql $verifSql)
    if ($verif.Count -eq 0 -or [int]$verif[0] -ne 200) {
        throw "TEST FAILED CONCURRENCIA: No todas las filas estan en RESERVADA con intentos=1: $($verif -join '; ')"
    }

    Write-Host "TEST_PASS:NOTIF_CONCURRENCY"
}
finally {
    $cleanupSql = "SET NOCOUNT ON; DELETE FROM dbo.NotificacionSaliente WHERE tipo = '$tag';"
    Invoke-Sql $cleanupSql | Out-Null
    Write-Host "Limpieza completada. Cero residuos."
}
