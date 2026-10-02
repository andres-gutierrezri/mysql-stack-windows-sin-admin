@echo off
rem ============================================================================
rem  tests\validate_project.cmd
rem  Pruebas de validacion en CMD puro (sin Pester, sin Administrador).
rem  Comprueba estructura, patrones prohibidos, configuracion por componente,
rem  marcadores de ayudantes embebidos y ejecuta los scripts en modo simulacion.
rem  Codigo de salida: 0 = todo correcto | N = numero de pruebas fallidas
rem  Autor: Ingeniero Andres Felipe Gutierrez Rivera
rem ============================================================================
setlocal EnableExtensions DisableDelayedExpansion
for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "PASS=0" & set "FAIL=0"

echo === Estructura ===
for %%F in (README.md LICENSE .gitignore .gitattributes .env.example requirements.txt config\stack.env
            src\powershell\MySQLStack.Common.ps1 src\powershell\Install-MySQLStack.ps1 src\powershell\Uninstall-MySQLStack.ps1
            src\powershell\Enable-ScriptExecution.ps1 src\powershell\Show-MySQLStackMenu.ps1
            src\cmd\install_mysql_stack.cmd src\cmd\uninstall_mysql_stack.cmd src\cmd\enable_script_execution.cmd src\cmd\mysql_stack_menu.cmd
            src\templates\mysql-console.cmd.tpl src\templates\start-mysql-server.cmd.tpl src\templates\stop-mysql-server.cmd.tpl
            tests\Validate.Tests.ps1 docs\ARQUITECTURA.md docs\REQUISITOS.md docs\PRUEBAS.md docs\LIMITACIONES.md docs\PUBLICACION_GIT.md docs\COMPONENTES_Y_MENU.md) do (
  if exist "%ROOT%\%%F" (call :ok "existe %%F") else (call :bad "falta %%F")
)

echo.
echo === Patrones que requieren Administrador (deben estar AUSENTES) ===
for %%P in ("mysqld.exe --install" "mysqld --install" "-Verb RunAs" "New-Service" "New-NetFirewallRule" "sc create" "reg add HKLM" "setx /M") do (
  findstr /S /I /L /C:%%P "%ROOT%\src\*.ps1" "%ROOT%\src\*.cmd" "%ROOT%\src\*.tpl" >nul 2>&1
  if errorlevel 1 (call :ok "ausente: %%~P") else (call :bad "presente: %%~P")
)

echo.
echo === Contrato de configuracion ===
findstr /B /C:"FALLBACK_ROOT_PASSWORD=1234567" "%ROOT%\config\stack.env" >nul && (call :ok "contrasena de respaldo 1234567") || (call :bad "contrasena de respaldo")
findstr /B /C:"STACK_ROOT_DEFAULT=C:\Programs" "%ROOT%\config\stack.env" >nul && (call :ok "ruta por defecto C:\Programs") || (call :bad "ruta por defecto")
findstr /B /C:"SRVLTS_VERSION=9.7.2" "%ROOT%\config\stack.env" >nul && (call :ok "servidor LTS 9.7.2") || (call :bad "servidor LTS 9.7.2")
findstr /B /C:"WB8_VERSION=8.0.47" "%ROOT%\config\stack.env" >nul && (call :ok "Workbench 8.0.47") || (call :bad "Workbench 8.0.47")
for %%I in (SRV WB NOTIF SRVLTS WB8) do (
  for %%K in (LABEL KIND URL MD5 FILE DIR LINK NEED_GB) do (
    findstr /B /C:"%%I_%%K=" "%ROOT%\config\stack.env" >nul && (call :ok "%%I_%%K definido") || (call :bad "%%I_%%K no definido")
  )
)
findstr /C:"-u root -p -h localhost -P %%MYSQL_PORT%% -D mysql" "%ROOT%\src\templates\mysql-console.cmd.tpl" >nul && (call :ok "comando de conexion solicitado") || (call :bad "comando de conexion")
findstr /C:"bind-address=127.0.0.1" "%ROOT%\src\cmd\install_mysql_stack.cmd" >nul && (call :ok "escucha solo en loopback") || (call :bad "loopback")
for %%H in (ENABLE FOREIGN XAMPPCHK STOPOWN PWSET PATHSET RENDER SHORTCUT) do (
  findstr /C:"::#PS:%%H:BEGIN" "%ROOT%\src\cmd\install_mysql_stack.cmd" >nul && findstr /C:"::#PS:%%H:END" "%ROOT%\src\cmd\install_mysql_stack.cmd" >nul && (call :ok "ayudante embebido %%H") || (call :bad "ayudante embebido %%H")
)
findstr /C:"xampp" "%ROOT%\src\cmd\install_mysql_stack.cmd" >nul && (call :ok "el instalador CMD trata la entrada de XAMPP en el PATH") || (call :bad "XAMPP en el PATH")

echo.
echo === Simulacion (sin cambios en el sistema) ===
call "%ROOT%\src\cmd\install_mysql_stack.cmd" /COMPONENTS:ALL /DRYRUN /NOPROMPT >"%TEMP%\mysqlstack_dry_install.log" 2>&1
call :rc_ok "install_mysql_stack.cmd /COMPONENTS:ALL /DRYRUN" %ERRORLEVEL%
call "%ROOT%\src\cmd\install_mysql_stack.cmd" /COMPONENTS:SRVLTS+WB8 /DRYRUN /NOPROMPT >"%TEMP%\mysqlstack_dry_install2.log" 2>&1
call :rc_ok "install_mysql_stack.cmd /COMPONENTS:SRVLTS+WB8 /DRYRUN" %ERRORLEVEL%
call "%ROOT%\src\cmd\uninstall_mysql_stack.cmd" /COMPONENTS:WB8 /DRYRUN /YES >"%TEMP%\mysqlstack_dry_uninstall.log" 2>&1
if errorlevel 1 (call :bad "uninstall_mysql_stack.cmd /COMPONENTS:WB8 /DRYRUN devolvio error") else (call :ok "uninstall_mysql_stack.cmd /COMPONENTS:WB8 /DRYRUN termina con 0")
call "%ROOT%\src\cmd\mysql_stack_menu.cmd" /ACTION:STATUS >"%TEMP%\mysqlstack_menu_status.log" 2>&1
if errorlevel 1 (call :bad "mysql_stack_menu.cmd /ACTION:STATUS devolvio error") else (call :ok "mysql_stack_menu.cmd /ACTION:STATUS termina con 0")
call "%ROOT%\src\cmd\install_mysql_stack.cmd" /COMPONENTS:NOEXISTE /DRYRUN >"%TEMP%\mysqlstack_dry_bad.log" 2>&1
if "%ERRORLEVEL%"=="50" (call :ok "un componente desconocido produce el codigo 50") else (call :bad "componente desconocido: se esperaba 50 y se obtuvo %ERRORLEVEL%")

echo.
echo Resultado: %PASS% correctas, %FAIL% fallidas. Registros en %TEMP%\mysqlstack_*.log
exit /b %FAIL%

:rc_ok
if "%~2"=="0" (call :ok "%~1 termina con 0") else if "%~2"=="10" (call :ok "%~1 informa requisitos no cumplidos - codigo 10 documentado") else if "%~2"=="20" (call :ok "%~1 informa conflicto - codigo 20 documentado") else (call :bad "%~1 devolvio %~2")
exit /b 0
:ok
echo   [PASS] %~1
set /a PASS+=1
exit /b 0
:bad
echo   [FAIL] %~1
set /a FAIL+=1
exit /b 0
