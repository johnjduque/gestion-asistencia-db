param (
    [string]$Password = "TuPasswordSeguro123"
)

Write-Host "Ejecutando suite de pruebas y generando resumen..." -ForegroundColor Cyan

# Ejecutar el script original y capturar todo el output
$output = Get-Content -Path .\test_suite.sql -Raw | docker exec -i sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P "$Password" -C -y 0 -Y 0 2>&1

$outputStr = $output -join "`n"

# Evaluar cada camino usando expresiones regulares sobre el output crudo
$c1 = $outputStr -match "El identificador de correlacion no.*0"
$c2 = $outputStr -match "RESULTADO: PASO.*Estudiante creado"
$c3 = $outputStr -match "RESULTADO: PASO.*Usuario preexistente"
$c4 = $outputStr -match "El numero de identificacion es obli.*0"
$c5 = $outputStr -match "Existe un cruce de horario.*0"
$c6 = $outputStr -match "No existe un grupo con el identific.*0"
$c7 = $outputStr -match "El identificador del grupo no es va.*0"

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "             RESULTADOS RESUMIDOS DE PRUEBAS" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

function Report-Test ($name, $passed) {
    Write-Host "  - ${name}: " -NoNewline
    if ($passed) {
        Write-Host "PASO" -ForegroundColor Green
    } else {
        Write-Host "FALLO" -ForegroundColor Red
    }
}

Report-Test "Camino 1: IdCorrelacion Ausente / Vacio" $c1
Report-Test "Camino 2: Happy Path (Registro Completo)" $c2
Report-Test "Camino 3: Usuario Preexistente" $c3
Report-Test "Camino 4: Fallo Sincronizacion (Campos Nulos)" $c4
Report-Test "Camino 5: Fallo por Cruce de Horario" $c5
Report-Test "Camino 6: Fallo por Grupo Inexistente" $c6
Report-Test "Camino 7: Captura de error en CATCH" $c7

Write-Host "========================================================" -ForegroundColor Green
