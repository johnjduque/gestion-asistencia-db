param (
    [string]$ContainerName,
    [string]$Password
)

# Cargar variables de entorno desde archivo .env si existe
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            [System.Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim())
        }
    }
}

if (-not $ContainerName) {
    $ContainerName = if ($env:SQL_CONTAINER_NAME) { $env:SQL_CONTAINER_NAME } else { "sql_server_asistencias" }
}
if (-not $Password) {
    $Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } elseif ($env:MSSQL_SA_PASSWORD) { $env:MSSQL_SA_PASSWORD } else { "AsistenciasDB2026!" }
}

Write-Host "Ejecutando suite de pruebas y generando resumen..." -ForegroundColor Cyan

# Copiar test_suite.sql al contenedor para evitar corrupción de codificación por tubería
$testSuitePath = Join-Path $PSScriptRoot "test_suite.sql"
docker cp "$testSuitePath" "${ContainerName}:/tmp/test_suite.sql"

# Ejecutar el script original apuntando al archivo en el contenedor y capturar el output
$output = docker exec $ContainerName /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P "$Password" -C -y 0 -Y 0 -i /tmp/test_suite.sql 2>&1
$outputStr = $output -join "`n"

# Evaluar cada camino usando expresiones regulares sobre el output crudo
# usp_registrar_estudiante_en_grupo_usuario_no_existente
$u_c1 = $outputStr -match "correlacion.*no.*presente.*0"
$u_c2 = $outputStr -match "RESULTADO: PASO.*Estudiante creado"
$u_c3 = $outputStr -match "RESULTADO: PASO.*Usuario preexistente"
$u_c4 = $outputStr -match "numero.*identificacion.*obligatorio.*0"
$u_c5 = $outputStr -match "cruce.*horario.*0"
$u_c6 = $outputStr -match "No existe.*grupo.*identificador.*0"
$u_c7 = $outputStr -match "identificador.*grupo.*no.*valido.*0"

# usp_generar_sesiones_grupo
$g_c1 = $outputStr -match "RESULTADO: PASO.*Sesiones generadas"
$g_c2 = $outputStr -match "No existe.*grupo.*identificador.*0"
$g_c3 = $outputStr -match "horarios.*configurados.*0" -or $outputStr -match "no se encontraron.*Horario.*0"

# usp_registrar_asistencia_estudiante
$r_c1 = $outputStr -match "RESULTADO: PASO.*Asistencia registrada unitaria"
$r_c2 = $outputStr -match "RESULTADO: PASO.*Asistencia actualizada unitaria"
$r_c3 = $outputStr -match "no.*matriculado.*grupo.*0" -or $outputStr -match "no encontrado.*0"

# usp_registrar_asistencia_estudiante_autonomo
$a_c1 = $outputStr -match "RESULTADO: PASO.*Auto-registro exitoso"
$a_c2 = $outputStr -match "verificac.*incorrecto.*0"
$a_c3 = $outputStr -match "no est.*matriculado.*0" -or $outputStr -match "no est.*inscrito.*0"

# usp_registrar_asistencias_sesion
$m_c1 = $outputStr -match "RESULTADO: PASO.*Carga masiva JSON exitosa"
$m_c2 = $outputStr -match "no est.*matriculado.*0" -or $outputStr -match "no est.*inscrito.*0"

# usp_registrar_docente_en_grupo_usuario_no_existente
$d_c1 = $outputStr -match "correlacion.*no.*presente.*0"
$d_c2 = $outputStr -match "RESULTADO: PASO.*Docente creado"
$d_c3 = $outputStr -match "RESULTADO: PASO.*Usuario preexistente"
$d_c4 = $outputStr -match "numero.*identificacion.*obligatorio.*0"
$d_c5 = $outputStr -match "cruce.*horario.*0"
$d_c6 = $outputStr -match "No existe.*grupo.*identificador.*0"
$d_c7 = $outputStr -match "identificador.*grupo.*no.*valido.*0"

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "             RESULTADOS RESUMIDOS DE PRUEBAS" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

function Report-Method ($methodName) {
    Write-Host "`n[$methodName]" -ForegroundColor Cyan
}

function Report-Path ($pathName, $passed) {
    Write-Host "  - ${pathName}: " -NoNewline
    if ($passed) {
        Write-Host "PASO" -ForegroundColor Green
    } else {
        Write-Host "FALLO" -ForegroundColor Red
    }
}

# 1. usp_registrar_estudiante_en_grupo_usuario_no_existente
Report-Method "usp_registrar_estudiante_en_grupo_usuario_no_existente"
Report-Path "Camino 1: IdCorrelacion Ausente / Vacio" $u_c1
Report-Path "Camino 2: Happy Path (Registro Completo)" $u_c2
Report-Path "Camino 3: Usuario Preexistente" $u_c3
Report-Path "Camino 4: Fallo Sincronizacion (Campos Nulos)" $u_c4
Report-Path "Camino 5: Fallo por Cruce de Horario" $u_c5
Report-Path "Camino 6: Fallo por Grupo Inexistente" $u_c6
Report-Path "Camino 7: Captura de error en CATCH" $u_c7

# 2. usp_generar_sesiones_grupo
Report-Method "usp_generar_sesiones_grupo"
Report-Path "Camino 1: Happy Path (Generar Sesiones)" $g_c1
Report-Path "Camino 2: Fallo por Grupo Inexistente" $g_c2
Report-Path "Camino 3: Fallo por Grupo sin Horarios" $g_c3

# 3. usp_registrar_asistencia_estudiante
Report-Method "usp_registrar_asistencia_estudiante"
Report-Path "Camino 1: Happy Path (Registro Unitario)" $r_c1
Report-Path "Camino 2: Happy Path (Actualizacion de Estado)" $r_c2
Report-Path "Camino 3: Fallo por Matricula Inexistente" $r_c3

# 4. usp_registrar_asistencia_estudiante_autonomo
Report-Method "usp_registrar_asistencia_estudiante_autonomo"
Report-Path "Camino 1: Happy Path (Auto-registro con codigo)" $a_c1
Report-Path "Camino 2: Fallo por Codigo de Verificacion Incorrecto" $a_c2
Report-Path "Camino 3: Fallo por Estudiante no Matriculado" $a_c3

# 5. usp_registrar_asistencias_sesion
Report-Method "usp_registrar_asistencias_sesion"
Report-Path "Camino 1: Happy Path (Carga JSON Masiva)" $m_c1
Report-Path "Camino 2: Fallo por Estudiante No Matriculado en JSON" $m_c2

# 6. usp_registrar_docente_en_grupo_usuario_no_existente
Report-Method "usp_registrar_docente_en_grupo_usuario_no_existente"
Report-Path "Camino 1: IdCorrelacion Ausente / Vacio" $d_c1
Report-Path "Camino 2: Happy Path (Registro Completo)" $d_c2
Report-Path "Camino 3: Usuario Preexistente" $d_c3
Report-Path "Camino 4: Fallo Sincronizacion (Campos Nulos)" $d_c4
Report-Path "Camino 5: Fallo por Cruce de Horario" $d_c5
Report-Path "Camino 6: Fallo por Grupo Inexistente" $d_c6
Report-Path "Camino 7: Captura de error en CATCH" $d_c7

Write-Host "`n========================================================" -ForegroundColor Green
