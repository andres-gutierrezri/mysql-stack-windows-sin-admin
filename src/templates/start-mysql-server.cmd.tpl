@echo off
set "MYSQL_BASE=@@BASE@@"
set "MYSQL_PORT=@@PORT@@"
netstat -an -p tcp | findstr /R /C:":%MYSQL_PORT% .*LISTENING" >nul
if not errorlevel 1 (
  echo @@LABEL@@ ya esta en ejecucion en el puerto %MYSQL_PORT%.
  exit /b 0
)
powershell -NoProfile -Command "Start-Process -FilePath '%MYSQL_BASE%\@@SRVDIR@@\bin\mysqld.exe' -ArgumentList '--defaults-file=%MYSQL_BASE%\@@SRVDIR@@\my.ini' -WindowStyle Hidden"
for /L %%i in (1,1,45) do (
  netstat -an -p tcp | findstr /R /C:":%MYSQL_PORT% .*LISTENING" >nul && (echo @@LABEL@@ iniciado en el puerto %MYSQL_PORT%. & exit /b 0)
  timeout /t 1 /nobreak >nul
)
echo No fue posible iniciar el servidor. Revise %MYSQL_BASE%\@@DATADIR@@\mysql-error.log
exit /b 1
