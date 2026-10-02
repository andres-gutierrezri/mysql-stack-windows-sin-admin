@echo off
set "MYSQL_BASE=@@BASE@@"
set "MYSQL_PORT=@@PORT@@"
echo Deteniendo @@LABEL@@ ^(puerto %MYSQL_PORT%^)...
"%MYSQL_BASE%\@@SRVDIR@@\bin\mysqladmin.exe" -u root -p -h 127.0.0.1 -P %MYSQL_PORT% shutdown
