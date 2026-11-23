# AUD-BD M-9: paridad entre los ids TEST_PASS que emiten las pruebas y los que exige test_summary.ps1 ($criticalIds / $resultIds).
# Solo lectura: no necesita SQL Server ni Docker.
#   ./scripts/check-test-summary-parity.ps1            -> informe (exit 0)
#   ./scripts/check-test-summary-parity.ps1 -Check     -> exit 1 si test_summary.ps1 exige ids que ninguna prueba emite ni menciona (ids fantasma)
#   ./scripts/check-test-summary-parity.ps1 -Strict    -> ademas exit 1 si hay ids emitidos validos sin exigir (salvo la lista scripts/test-summary-parity-allowlist.txt)
#   ./scripts/check-test-summary-parity.ps1 -Listar    -> imprime las listas completas
# Fuentes de ids emitidos: PRINT 'TEST_PASS:<ID>' de los .sql que test_suite.sql incluye con :r, y TEST_PASS:<ID> literal de test/*.ps1.
# Un id solo cuenta para el gate si cumple [A-Z0-9_]+ (la regex de test_summary.ps1); los demas (con guion o minusculas) se informan aparte.
param([switch]$Check, [switch]$Strict, [switch]$Listar)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$summaryText = Get-Content -Path (Join-Path $root 'test_summary.ps1') -Raw -Encoding UTF8
$suiteText = Get-Content -Path (Join-Path $root 'test_suite.sql') -Raw -Encoding UTF8

function Get-IdsLiterales([string]$bloque) {
    @([regex]::Matches($bloque, "'([A-Z0-9_]{3,})'") | ForEach-Object { $_.Groups[1].Value })
}

# Requeridos: bloque $criticalIds = @( ... ) y $resultIds = @( ... )
$requeridos = New-Object System.Collections.Generic.HashSet[string]
foreach ($nombre in 'criticalIds', 'resultIds') {
    $m = [regex]::Match($summaryText, "(?s)\`$$nombre\s*=\s*@\((.*?')\s*\)")
    if (-not $m.Success) { Write-Host "PARIDAD_ERROR: no se encontro `$$nombre en test_summary.ps1"; exit 2 }
    foreach ($id in Get-IdsLiterales $m.Groups[1].Value) { [void]$requeridos.Add($id) }
}

# Emitidos por los .sql incluidos en test_suite.sql
$incluidos = @([regex]::Matches($suiteText, '(?m)^:r\s+/tmp/test/(\S+\.sql)') | ForEach-Object { $_.Groups[1].Value })
$emitidos = New-Object System.Collections.Generic.HashSet[string]
$noReconocidos = New-Object System.Collections.Generic.HashSet[string]
$prefijosDinamicos = New-Object System.Collections.Generic.HashSet[string]
$archivoDe = @{}
foreach ($f in $incluidos) {
    $path = Join-Path $root "test/$f"
    if (-not (Test-Path $path)) { Write-Host "PARIDAD_ERROR: test_suite.sql incluye $f pero no existe"; exit 2 }
    foreach ($linea in Get-Content -Path $path -Encoding UTF8) {
        $m = [regex]::Match($linea, "PRINT\s+N?'TEST_PASS:([^']*)'")
        if (-not $m.Success) {
            # PRINT armado con CONCAT/+: el prefijo literal tras TEST_PASS: cubre los ids que construye
            $d = [regex]::Match($linea, "TEST_PASS:([A-Z0-9_]+)")
            if ($d.Success) { [void]$prefijosDinamicos.Add($d.Groups[1].Value) }
            continue
        }
        $id = $m.Groups[1].Value
        if ($id -cmatch '^[A-Z0-9_]+$') { [void]$emitidos.Add($id); if (-not $archivoDe.ContainsKey($id)) { $archivoDe[$id] = $f } }
        else { [void]$noReconocidos.Add("$f::$id") }
    }
}
# Emitidos por los runners .ps1 de test/
foreach ($ps in Get-ChildItem (Join-Path $root 'test') -Filter '*.ps1') {
    foreach ($m in [regex]::Matches((Get-Content $ps.FullName -Raw -Encoding UTF8), "TEST_PASS:([A-Z0-9_]+)")) {
        $id = $m.Groups[1].Value
        if ($id.Length -ge 3) { [void]$emitidos.Add($id); if (-not $archivoDe.ContainsKey($id)) { $archivoDe[$id] = $ps.Name } }
    }
}

# Exigidos que el gate emite por otro camino: el id aparece como palabra en alguna prueba (test/*.sql, test/*.ps1, scripts/*.ps1) o en el resto de
# test_summary.ps1 (fuera de los bloques de ids), p.ej. TEST_RESULT_BEGIN:<ID>, ids armados por un bucle o gates propios del resumen.
$resto = [regex]::Replace($summaryText, "(?s)\`$(criticalIds|resultIds)\s*=\s*@\((.*?')\s*\)", '')
$otrosTextos = New-Object System.Text.StringBuilder
[void]$otrosTextos.AppendLine($resto)
foreach ($f in @(Get-ChildItem (Join-Path $root 'test') -File) + @(Get-ChildItem $PSScriptRoot -Filter '*.ps1')) {
    if ($f.Name -eq 'check-test-summary-parity.ps1') { continue }
    [void]$otrosTextos.AppendLine((Get-Content $f.FullName -Raw -Encoding UTF8))
}
$otros = $otrosTextos.ToString()
$mencionados = New-Object System.Collections.Generic.HashSet[string]
foreach ($id in $requeridos) { if (@($prefijosDinamicos | Where-Object { $id.StartsWith($_) }).Count -gt 0) { [void]$mencionados.Add($id); continue }; if ($otros -cmatch "(?<![A-Z0-9_])$([regex]::Escape($id))(?![A-Z0-9_])") { [void]$mencionados.Add($id) } }

# Degenerados: demasiado cortos o terminados en guion bajo (prefijo de un id armado por concatenacion)
$degenerados = @($emitidos | Where-Object { $_.Length -lt 4 -or $_.EndsWith('_') })
$reales = @($emitidos | Where-Object { $_ -notin $degenerados })
$sinExigir = @($reales | Where-Object { -not $requeridos.Contains($_) } | Sort-Object)
$fantasma = @($requeridos | Where-Object { $_ -notin $emitidos -and -not $mencionados.Contains($_) } | Sort-Object)
$exigidosPorOtroCamino = @($requeridos | Where-Object { $_ -notin $emitidos -and $mencionados.Contains($_) }).Count

$permitidos = @()
$allowFile = Join-Path $PSScriptRoot 'test-summary-parity-allowlist.txt'
if (Test-Path $allowFile) { $permitidos = @(Get-Content $allowFile -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }) }
$sinExigirNuevos = @($sinExigir | Where-Object { $_ -notin $permitidos })

Write-Host "PARIDAD_SUITE_ARCHIVOS_INCLUIDOS=$($incluidos.Count)"
Write-Host "PARIDAD_IDS_EMITIDOS=$($emitidos.Count)"
Write-Host "PARIDAD_IDS_DEGENERADOS=$($degenerados.Count)"
Write-Host "PARIDAD_IDS_NO_RECONOCIDOS_POR_EL_GATE=$($noReconocidos.Count)"
Write-Host "PARIDAD_IDS_EXIGIDOS=$($requeridos.Count)"
Write-Host "PARIDAD_EMITIDOS_SIN_EXIGIR=$($sinExigir.Count) (fuera de la lista permitida: $($sinExigirNuevos.Count))"
Write-Host "PARIDAD_EXIGIDOS_EMITIDOS_POR_OTRO_CAMINO=$exigidosPorOtroCamino"
Write-Host "PARIDAD_EXIGIDOS_SIN_EMITIR=$($fantasma.Count)"
if ($Listar -or $fantasma.Count) {
    if ($fantasma.Count) { Write-Host "EXIGIDOS_SIN_EMITIR: $($fantasma -join ', ')" }
}
if ($Listar) {
    Write-Host "DEGENERADOS: $($degenerados -join ', ')"
    Write-Host 'EMITIDOS_SIN_EXIGIR:'
    $sinExigir | ForEach-Object { Write-Host "  $_ ($($archivoDe[$_]))" }
}
if ($Check -and $fantasma.Count) { Write-Host 'PARIDAD_FALLA: ids exigidos que ninguna prueba emite'; exit 1 }
if ($Strict -and $sinExigirNuevos.Count) { Write-Host 'PARIDAD_FALLA: ids emitidos sin exigir en test_summary.ps1'; exit 1 }
Write-Host 'PARIDAD_OK'
exit 0
