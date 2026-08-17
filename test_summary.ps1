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
    $ContainerName = if ($env:SQL_CONTAINER_NAME) { $env:SQL_CONTAINER_NAME } else { "sqlserver" }
}
if (-not $Password) {
    $Password = if ($env:SQL_CONTAINER_PASSWORD) { $env:SQL_CONTAINER_PASSWORD } else { "Rionegro2233+" }
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
$u_c1 = $outputStr -match "CAMINO 1[\s\S]*?RESULTADO: PASO" -or $outputStr -match "correlacion.*no.*presente.*0"
$u_c2 = $outputStr -match "CAMINO 2[\s\S]*?RESULTADO: PASO"
$u_c3 = $outputStr -match "CAMINO 3[\s\S]*?RESULTADO: PASO"
$u_c4 = $outputStr -match "CAMINO 4[\s\S]*?RESULTADO: PASO"
$u_c5 = $outputStr -match "CAMINO 5[\s\S]*?RESULTADO: PASO"
$u_c6 = $outputStr -match "CAMINO 6[\s\S]*?RESULTADO: PASO"
$u_c7 = $outputStr -match "CAMINO 7[\s\S]*?RESULTADO: PASO"

# usp_generar_sesiones_grupo
$g_c1 = $outputStr -match "PRUEBAS DE: usp_generar_sesiones_grupo[\s\S]*?CAMINO 1[\s\S]*?RESULTADO: PASO"
$g_c2 = $outputStr -match "PRUEBAS DE: usp_generar_sesiones_grupo[\s\S]*?CAMINO 2[\s\S]*?RESULTADO: PASO"
$g_c3 = $outputStr -match "PRUEBAS DE: usp_generar_sesiones_grupo[\s\S]*?CAMINO 3[\s\S]*?RESULTADO: PASO"

# usp_registrar_asistencia_estudiante
$r_c1 = $outputStr -match "PRUEBAS DE: usp_registrar_asistencia_estudiante[\s\S]*?CAMINO 1[\s\S]*?RESULTADO: PASO"
$r_c2 = $outputStr -match "PRUEBAS DE: usp_registrar_asistencia_estudiante[\s\S]*?CAMINO 2[\s\S]*?RESULTADO: PASO"
$r_c3 = $outputStr -match "PRUEBAS DE: usp_registrar_asistencia_estudiante[\s\S]*?CAMINO 3[\s\S]*?RESULTADO: PASO"

# usp_registrar_asistencia_estudiante_autonomo
$a_c1 = $outputStr -match "PRUEBAS DE: usp_registrar_asistencia_estudiante_autonomo[\s\S]*?CAMINO 1[\s\S]*?RESULTADO: PASO"
$a_c2 = $outputStr -match "PRUEBAS DE: usp_registrar_asistencia_estudiante_autonomo[\s\S]*?CAMINO 2[\s\S]*?RESULTADO: PASO"
$a_c3 = $outputStr -match "PRUEBAS DE: usp_registrar_asistencia_estudiante_autonomo[\s\S]*?CAMINO 3[\s\S]*?RESULTADO: PASO"

# usp_registrar_asistencias_sesion
$m_c1 = $outputStr -match "PRUEBAS DE: usp_registrar_asistencias_sesion[\s\S]*?CAMINO 1[\s\S]*?RESULTADO: PASO"
$m_c2 = $outputStr -match "PRUEBAS DE: usp_registrar_asistencias_sesion[\s\S]*?CAMINO 2[\s\S]*?RESULTADO: PASO"

# usp_registrar_docente_en_grupo_usuario_no_existente
$d_c1 = $outputStr -match "SUITE DE PRUEBAS COMPLETAS: usp_registrar_docente_en_grupo_usuario_no_existente[\s\S]*?CAMINO 1[\s\S]*?RESULTADO: PASO" -or $outputStr -match "CAMINO 1: Validacion de ID Correlacion Ausente/Vacio[\s\S]*?RESULTADO: PASO"
$d_c2 = $outputStr -match "SUITE DE PRUEBAS COMPLETAS: usp_registrar_docente_en_grupo_usuario_no_existente[\s\S]*?CAMINO 2[\s\S]*?RESULTADO: PASO" -or $outputStr -match "CAMINO 2: Happy Path[\s\S]*?RESULTADO: PASO"
$d_c3 = $outputStr -match "SUITE DE PRUEBAS COMPLETAS: usp_registrar_docente_en_grupo_usuario_no_existente[\s\S]*?CAMINO 3[\s\S]*?RESULTADO: PASO" -or $outputStr -match "CAMINO 3: Usuario Preexistente[\s\S]*?RESULTADO: PASO"
$d_c4 = $outputStr -match "SUITE DE PRUEBAS COMPLETAS: usp_registrar_docente_en_grupo_usuario_no_existente[\s\S]*?CAMINO 4[\s\S]*?RESULTADO: PASO" -or $outputStr -match "CAMINO 4: Fallo en Sincronizar Usuario[\s\S]*?RESULTADO: PASO"
$d_c5 = $outputStr -match "SUITE DE PRUEBAS COMPLETAS: usp_registrar_docente_en_grupo_usuario_no_existente[\s\S]*?CAMINO 5[\s\S]*?RESULTADO: PASO" -or $outputStr -match "CAMINO 5: Fallo por Cruce de Horario[\s\S]*?RESULTADO: PASO"
$d_c6 = $outputStr -match "SUITE DE PRUEBAS COMPLETAS: usp_registrar_docente_en_grupo_usuario_no_existente[\s\S]*?CAMINO 6[\s\S]*?RESULTADO: PASO" -or $outputStr -match "CAMINO 6: Fallo por Grupo Inexistente[\s\S]*?RESULTADO: PASO"
$d_c7 = $outputStr -match "SUITE DE PRUEBAS COMPLETAS: usp_registrar_docente_en_grupo_usuario_no_existente[\s\S]*?CAMINO 7[\s\S]*?RESULTADO: PASO" -or $outputStr -match "CAMINO 7: Captura de error en CATCH[\s\S]*?RESULTADO: PASO"

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
