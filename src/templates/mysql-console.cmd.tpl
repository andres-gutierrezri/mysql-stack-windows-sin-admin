@echo off
title @@LABEL@@ - consola
set "MYSQL_BASE=@@BASE@@"
set "MYSQL_PORT=@@PORT@@"
set "MYSQL_BIN=%MYSQL_BASE%\@@SRVDIR@@\bin"
netstat -an -p tcp | findstr /R /C:":%MYSQL_PORT% .*LISTENING" >nul
if not errorlevel 1 goto :ready
echo Iniciando @@LABEL@@ en el puerto %MYSQL_PORT%...
powershell -NoProfile -Command "Start-Process -FilePath '%MYSQL_BIN%\mysqld.exe' -ArgumentList '--defaults-file=%MYSQL_BASE%\@@SRVDIR@@\my.ini' -WindowStyle Hidden"
for /L %%i in (1,1,45) do (
  netstat -an -p tcp | findstr /R /C:":%MYSQL_PORT% .*LISTENING" >nul && goto :ready
  timeout /t 1 /nobreak >nul
)
echo No fue posible iniciar el servidor. Revise %MYSQL_BASE%\@@DATADIR@@\mysql-error.log
pause
exit /b 1
:ready
echo Conectando: mysql -u root -p -h localhost -P %MYSQL_PORT% -D mysql
"%MYSQL_BIN%\mysql.exe" -u root -p -h localhost -P %MYSQL_PORT% -D mysql
