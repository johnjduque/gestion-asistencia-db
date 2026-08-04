$Password = "TuPasswordSeguro123"
$output = Get-Content -Path .\test_suite.sql -Raw | docker exec -i sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -d gestionasistenciadb -U sa -P "$Password" -C -y 0 -Y 0 2>&1
$outputStr = $output -join "`n"
$outputStr | Out-File -FilePath .\scratch\sql_output.txt -Encoding utf8
