# CULM-001 F3 - Utilidades para pruebas de migracion COMPONIBLES (dot-source desde test_culm001_*.ps1).
#
# Las pruebas up/down/up de cada paquete se escribieron cuando ese paquete era el ultimo. En una BD con los paquetes posteriores
# desplegados (como la que deja deploy_schema.ps1 en CI), el down de la migracion N restauraria textos que dependen de objetos que
# cambiaron los paquetes posteriores, o chocaria con las proteccion de rollback (D-RB-01/D-RB-02: no se revierte N si un paquete
# posterior sigue aplicado). El orden real de rollback retira primero los paquetes posteriores, asi que la prueba hace lo mismo:
# DENTRO de la transaccion que revierte al final, aplica el down de cada migracion con numero mayor que N, de la mas nueva a la mas
# antigua. Las migraciones se descubren por nombre: una migracion nueva no obliga a tocar las pruebas. Las aserciones del paquete
# probado no cambian y la BD queda como estaba (ROLLBACK).

function Get-DownChainText {
    param (
        [Parameter(Mandatory)][string]$DbRoot,
        [Parameter(Mandatory)][string]$RemoteMigrationsDir,
        [Parameter(Mandatory)][int]$Despues
    )
    $files = @(Get-ChildItem (Join-Path $DbRoot 'migrations') -Filter '*_down.sql' |
        Where-Object { $_.Name -match '^(\d+)_' -and [int]$Matches[1] -gt $Despues } |
        Sort-Object { [int]($_.Name -split '_')[0] } -Descending)
    # Confirmaciones destructivas en 0: nunca colapsan datos (sin soportes/tomas multiples el down no las necesita)
    $lines = @(':setvar CONFIRMAR_COLAPSO_SOPORTES 0')
    foreach ($f in $files) { $lines += ":r $RemoteMigrationsDir/$($f.Name)"; $lines += 'GO' }
    return ($lines -join "`n")
}

function New-ComposableWrapperText {
    param (
        [Parameter(Mandatory)][string]$DbRoot,
        [Parameter(Mandatory)][string]$RemoteMigrationsDir,
        [Parameter(Mandatory)][int]$Despues,
        [Parameter(Mandatory)][string]$RemoteTestFile,
        [string]$Preludio = ''
    )
    $chain = Get-DownChainText -DbRoot $DbRoot -RemoteMigrationsDir $RemoteMigrationsDir -Despues $Despues
    return @"
:on error exit
:setvar CONFIRMAR_COLAPSO 0
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
$chain
$Preludio
:r $RemoteTestFile
"@
}

function Send-TextToContainer {
    param (
        [Parameter(Mandatory)][string]$ContainerName,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$Text
    )
    $local = Join-Path ([System.IO.Path]::GetTempPath()) "componible_$([guid]::NewGuid().ToString('N')).sql"
    Set-Content -Path $local -Value $Text -Encoding utf8
    $copy = @(& docker cp $local "${ContainerName}:$RemotePath" 2>&1)
    $exit = $LASTEXITCODE
    Remove-Item -Path $local -Force -ErrorAction SilentlyContinue
    if ($exit -ne 0) { throw "could not copy composable wrapper to ${RemotePath}: $($copy -join '; ')" }
    $null = & docker exec -u 0 $ContainerName chmod a+r $RemotePath 2>&1
}
