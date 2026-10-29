# Regenera docs/catalogos/catalogo-mensajes.md desde los seeds (schema/seed/*.sql).
# Fuente de verdad: los MERGE sobre CatalogoMensajeUsuario y CatalogoMensajeTecnico. El documento es derivado:
# no se edita a mano; se vuelve a generar cuando se agrega o cambia un seed de mensajes.
#   ./scripts/generar-catalogo-mensajes.ps1            -> escribe el documento
#   ./scripts/generar-catalogo-mensajes.ps1 -Check     -> exit 1 si el documento no coincide con los seeds
param([switch]$Check, [string]$OutFile)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$seedDir = Join-Path $root 'schema/seed'
$outFile = if ($OutFile) { $OutFile } else { Join-Path $root 'docs/catalogos/catalogo-mensajes.md' }

$tupla = [regex]"^\s*\(\s*N?'(?<codigo>[^']+)'\s*,\s*N?'(?<tipo>[^']+)'\s*,\s*N?'(?<severidad>[^']+)'\s*,\s*N?'(?<contenido>(?:[^']|'')*)'\s*\)"
$mensajes = [ordered]@{}

foreach ($archivo in Get-ChildItem -Path $seedDir -Filter '*.sql' | Sort-Object Name) {
    $tabla = $null
    foreach ($linea in Get-Content -Path $archivo.FullName -Encoding UTF8) {
        if ($linea -match 'MERGE\s+INTO\s+\[?dbo\]?\.\[?(CatalogoMensajeUsuario|CatalogoMensajeTecnico)\]?') {
            $tabla = $Matches[1]
            continue
        }
        if ($linea -match '^\s*\)\s*AS\s+Source') {
            $tabla = $null
            continue
        }
        if (-not $tabla) { continue }
        $m = $tupla.Match($linea)
        if (-not $m.Success) { continue }
        $codigo = $m.Groups['codigo'].Value
        if (-not $mensajes.Contains($codigo)) {
            $mensajes[$codigo] = [ordered]@{ tipo = ''; severidad = ''; usuario = ''; tecnico = ''; seed = $archivo.Name }
        }
        $texto = $m.Groups['contenido'].Value.Replace("''", "'").Replace('|', '\|')
        if ($tabla -eq 'CatalogoMensajeUsuario') {
            $mensajes[$codigo].usuario = $texto
            $mensajes[$codigo].tipo = $m.Groups['tipo'].Value
            $mensajes[$codigo].severidad = $m.Groups['severidad'].Value
        } else {
            $mensajes[$codigo].tecnico = $texto
            if (-not $mensajes[$codigo].tipo) { $mensajes[$codigo].tipo = $m.Groups['tipo'].Value }
        }
    }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('---')
[void]$sb.AppendLine('status: active')
[void]$sb.AppendLine('type: catalog')
[void]$sb.AppendLine('scope: database')
[void]$sb.AppendLine('owner: database-team')
[void]$sb.AppendLine('generated-by: scripts/generar-catalogo-mensajes.ps1')
[void]$sb.AppendLine('---')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# Catálogo de mensajes')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> Documento **generado** desde `schema/seed/*.sql` (MERGE sobre `CatalogoMensajeUsuario` y `CatalogoMensajeTecnico`). No editar a mano: agregue o cambie el seed y ejecute `./scripts/generar-catalogo-mensajes.ps1`. Verificación: `./scripts/generar-catalogo-mensajes.ps1 -Check`.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Uso en SP: `EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = ''<CODIGO>'', @p_param1 = ...`. Los marcadores `{}` / `{0}` se reemplazan con los parámetros. El mensaje técnico se entrega como `DBCODE=<CODIGO>|<texto>` (ver `docs/contracts/DB_BASELINE_CONTRACT.md`).')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Total de códigos: **$($mensajes.Count)**.")
[void]$sb.AppendLine('')

$grupos = $mensajes.Keys | Group-Object { ($_ -split '_')[0] } | Sort-Object Name
foreach ($g in $grupos) {
    [void]$sb.AppendLine("## $($g.Name)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Código | Tipo | Severidad | Mensaje usuario | Mensaje técnico | Seed |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|')
    foreach ($codigo in ($g.Group | Sort-Object)) {
        $x = $mensajes[$codigo]
        [void]$sb.AppendLine("| ``$codigo`` | $($x.tipo) | $($x.severidad) | $($x.usuario) | $($x.tecnico) | ``$($x.seed)`` |")
    }
    [void]$sb.AppendLine('')
}

$contenido = $sb.ToString().Replace("`r`n", "`n")
if ($Check) {
    $actual = if (Test-Path $outFile) { (Get-Content -Path $outFile -Raw -Encoding UTF8).Replace("`r`n", "`n") } else { '' }
    if ($actual -ne $contenido) {
        Write-Host 'CATALOGO_MENSAJES_DESACTUALIZADO: ejecute ./scripts/generar-catalogo-mensajes.ps1'
        exit 1
    }
    Write-Host "CATALOGO_MENSAJES_OK codigos=$($mensajes.Count)"
    exit 0
}
[System.IO.File]::WriteAllText($outFile, $contenido, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "CATALOGO_MENSAJES_GENERADO codigos=$($mensajes.Count) archivo=$outFile"
