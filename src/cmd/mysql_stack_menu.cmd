@echo off
rem ============================================================================
rem  mysql_stack_menu.cmd
rem  Menu para instalar y desinstalar, individualmente o en conjunto, los
rem  componentes de MySQL en Windows 11 sin privilegios de Administrador.
rem  Delega en install_mysql_stack.cmd y uninstall_mysql_stack.cmd (independientes).
rem
rem  Uso interactivo:   mysql_stack_menu.cmd
rem  Uso no interactivo: mysql_stack_menu.cmd /ACTION:INSTALL /COMPONENTS:SRVLTS+WB8
rem   /ACTION:  INSTALL | UNINSTALL | STATUS | FIXPATH
rem   Cualquier otra opcion (/DRYRUN /FORCE /YES /KEEPDATA /BLANK /NOPROMPT /PORT:n /ROOT:r)
rem   se transmite al script que corresponda.
rem  Seleccion: numeros 1-5 separados por + o coma, nombres, o T=todo U=ultima L=LTS.
rem  Autor: Ingeniero Andres Felipe Gutierrez Rivera
rem ============================================================================
setlocal EnableExtensions DisableDelayedExpansion
set "HERE=%~dp0"
for %%I in ("%~dp0..\..") do set "PROJECT=%%~fI"
set "ALL_IDS=SRV WB NOTIF SRVLTS WB8"
set "ACTION=" & set "COMPS=" & set "ROOT_ARG=" & set "PASS="

:parse_args
if "%~1"=="" goto :args_done
set "A=%~1"
if /I "%A:~0,8%"=="/ACTION:" (set "ACTION=%A:~8%" & shift & goto :parse_args)
if /I "%A:~0,12%"=="/COMPONENTS:" (set "COMPS=%A:~12%" & shift & goto :parse_args)
if /I "%A:~0,6%"=="/ROOT:" set "ROOT_ARG=%A:~6%"
if "%A:~0,1%"=="/" (set "PASS=%PASS% %A%") else (set "COMPS=%COMPS% %A%")
shift
goto :parse_args
:args_done

call :load_env "%PROJECT%\config\stack.env"
if defined ROOT_ARG (set "ROOT=%ROOT_ARG%") else (set "ROOT=%STACK_ROOT_DEFAULT%")
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "BASE=%ROOT%\MySQL"
if exist "%BASE%\stack-manifest.env" if not defined ROOT_ARG (
  call :load_env "%BASE%\stack-manifest.env"
  if defined INSTALL_ROOT set "ROOT=%INSTALL_ROOT%"
  set "BASE=%ROOT%\MySQL"
)

call :migrate_v1
if defined ACTION goto :run_action
:menu
cls
echo === MySQL Stack para Windows 11 ^(sin Administrador^) ===
call :status
echo.
echo   1^) Instalar        2^) Desinstalar        3^) Reordenar PATH ^(XAMPP^)        0^) Salir
set "OP="
set /p "OP=Opcion: "
if "%OP%"=="1" goto :do_install
if "%OP%"=="2" goto :do_uninstall
if "%OP%"=="3" goto :do_fixpath
if "%OP%"=="0" exit /b 0
goto :menu

:do_install
call :ask_components INSTALAR
if not defined CHOICE goto :menu
call "%HERE%install_mysql_stack.cmd" "/COMPONENTS:%CHOICE%" %PASS%
echo Codigo de salida: %ERRORLEVEL%
pause
goto :menu

:do_uninstall
call :ask_components DESINSTALAR
if not defined CHOICE goto :menu
call "%HERE%uninstall_mysql_stack.cmd" "/COMPONENTS:%CHOICE%" %PASS%
echo Codigo de salida: %ERRORLEVEL%
pause
goto :menu

:do_fixpath
call "%HERE%install_mysql_stack.cmd" /FIXPATH
pause
goto :menu

:run_action
if /I "%ACTION%"=="STATUS" (call :status & exit /b 0)
if /I "%ACTION%"=="FIXPATH" (call "%HERE%install_mysql_stack.cmd" /FIXPATH & exit /b %ERRORLEVEL%)
if /I "%ACTION%"=="INSTALL" (
  if not defined COMPS set "COMPS=LATEST"
  call :normalize
  call "%HERE%install_mysql_stack.cmd" "/COMPONENTS:%COMPS%" %PASS%
  exit /b %ERRORLEVEL%
)
if /I "%ACTION%"=="UNINSTALL" (
  if not defined COMPS set "COMPS=ALL"
  call :normalize
  call "%HERE%uninstall_mysql_stack.cmd" "/COMPONENTS:%COMPS%" %PASS%
  exit /b %ERRORLEVEL%
)
echo   [ERROR] Accion desconocida: %ACTION%. Use INSTALL, UNINSTALL, STATUS o FIXPATH.
exit /b 50

:normalize
set "COMPS=%COMPS:,= %"
set "COMPS=%COMPS:;= %"
set "COMPS=%COMPS: =+%"
exit /b 0

:ask_components
echo.
echo Componentes a %~1 ^(separe con + o coma^):
echo   1 = Servidor 26.7.0   2 = Workbench 26.7.0   3 = Notifier 1.1.8
echo   4 = Servidor 9.7.2 LTS   5 = Workbench 8.0.47
echo   U = ultima version ^(1,2,3^)   L = LTS ^(4,5^)   T = TODO   0 = volver
set "CHOICE="
set "IN="
set /p "IN=Seleccion: "
if not defined IN exit /b 0
if "%IN%"=="0" exit /b 0
echo %IN%| findstr /R /C:"^[0-9A-Za-z,+ ]*$" >nul
if errorlevel 1 (echo   [AVISO] Seleccion no valida. Ejemplos: 1  -  1+3  -  U  -  T & pause & exit /b 0)
set "CHOICE=%IN%"
set "CHOICE=%CHOICE:,=+%"
set "CHOICE=%CHOICE: =+%"
exit /b 0

:status
echo.
echo Estado de los componentes
set "N=0"
for %%C in (%ALL_IDS%) do call :status_line %%C
exit /b 0

:status_line
set /a N+=1
call set "I=%%%~1_INSTALLED%%"
call set "L=%%%~1_LABEL%%"
call set "K=%%%~1_KIND%%"
call set "P=%%%~1_PORT%%"
set "MARK=[ ]"
if "%I%"=="1" set "MARK=[X]"
set "EXTRA="
if "%I%"=="1" if /I "%K%"=="server" (
  netstat -an | findstr /R /C:":%P% .*LISTENING" >nul
  if errorlevel 1 (set "EXTRA=  puerto %P% - detenido") else (set "EXTRA=  puerto %P% - en ejecucion")
)
echo   %N%^) %MARK% %L%%EXTRA%
exit /b 0

:migrate_v1
if defined SRV_INSTALLED exit /b 0
if not defined PORT exit /b 0
set "SRV_INSTALLED=1"
set "SRV_PORT=%PORT%"
set "WB_INSTALLED=1"
set "NOTIF_INSTALLED=0"
if defined NOTIFIER set "NOTIF_INSTALLED=%NOTIFIER%"
set "PORT=" & set "XPORT=" & set "NOTIFIER="
exit /b 0

:load_env
if not exist "%~1" exit /b 0
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~1") do set "%%A=%%B"
exit /b 0
