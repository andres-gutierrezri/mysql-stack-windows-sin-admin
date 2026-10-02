@echo off
rem ============================================================================
rem  install_mysql_stack.cmd
rem  Instala componentes de MySQL en Windows 11 desde una cuenta local SIN
rem  privilegios de Administrador: individualmente o en conjunto, sin conflictos.
rem
rem  Componentes (/COMPONENTS:...):
rem    SRV     MySQL Community Server 26.7.0 (la mas reciente)
rem    WB      MySQL Workbench 26.7.0 (la mas reciente)
rem    NOTIF   MySQL Notifier 1.1.8 (fuera de ciclo de vida)
rem    SRVLTS  MySQL Community Server 9.7.2 LTS
rem    WB8     MySQL Workbench 8.0.47
rem  Grupos: ALL | LATEST (SRV+WB+NOTIF, por defecto) | LTS (SRVLTS+WB8)
rem  Separe los componentes con + o con coma entre comillas: "/COMPONENTS:SRV,WB8"
rem
rem  Uso: install_mysql_stack.cmd [/COMPONENTS:lista] [/DRYRUN] [/NOPROMPT] [/BLANK]
rem                               [/SKIPNOTIFIER] [/FORCE] [/PORT:n] [/ROOT:ruta] [/FIXPATH]
rem   /DRYRUN        Solo comprueba y planifica; no descarga ni modifica nada.
rem   /NOPROMPT      Sin preguntas: contrasena de respaldo (1234567) salvo /BLANK.
rem   /BLANK         Contrasena de root en blanco.
rem   /FORCE         Reinstala los componentes ya instalados.
rem   /PORT:n        Puerto deseado para el PRIMER servidor de la ejecucion.
rem   /FIXPATH       Solo recalcula el PATH de usuario (p. ej. si instalo XAMPP despues).
rem
rem  Codigos de salida: 0 OK | 10 requisitos | 20 conflictos/puertos | 30 descarga
rem                     40 instalacion | 50 configuracion
rem  Autor: Ingeniero Andres Felipe Gutierrez Rivera
rem
rem  Nota tecnica: lo que CMD no puede hacer (leer una contrasena oculta, editar PATH
rem  conservando REG_EXPAND_SZ, crear accesos directos) se delega a bloques PowerShell
rem  EMBEBIDOS al final de este archivo, ejecutados en memoria con powershell -Command.
rem  Las subrutinas no terminan el script: fijan DIE_CODE y DIE_MSG y el flujo
rem  principal hace "goto :die".
rem ============================================================================
setlocal EnableExtensions DisableDelayedExpansion
set "MS_SELF=%~f0"
for %%I in ("%~dp0..\..") do set "PROJECT=%%~fI"
set "ALL_IDS=SRV WB NOTIF SRVLTS WB8"
set "SERVER_IDS=SRV SRVLTS"
set "DRYRUN=0" & set "NOPROMPT=0" & set "BLANK=0" & set "SKIPNOTIFIER=0" & set "FORCE=0" & set "FIXPATH=0"
set "REQ_PORT=0" & set "ROOT_ARG=" & set "COMPS="
set "FAILS=0" & set "WARNS=0" & set "CREATED_ROOT=0" & set "DIE_CODE=" & set "DIE_MSG="

:parse_args
if "%~1"=="" goto :args_done
set "A=%~1"
if /I "%A%"=="/DRYRUN" set "DRYRUN=1"
if /I "%A%"=="/NOPROMPT" set "NOPROMPT=1"
if /I "%A%"=="/BLANK" set "BLANK=1"
if /I "%A%"=="/SKIPNOTIFIER" set "SKIPNOTIFIER=1"
if /I "%A%"=="/FORCE" set "FORCE=1"
if /I "%A%"=="/FIXPATH" set "FIXPATH=1"
if /I "%A:~0,12%"=="/COMPONENTS:" set "COMPS=%A:~12%"
if /I "%A:~0,6%"=="/PORT:" set "REQ_PORT=%A:~6%"
if /I "%A:~0,6%"=="/ROOT:" set "ROOT_ARG=%A:~6%"
if not "%A:~0,1%"=="/" set "COMPS=%COMPS% %A%"
shift
goto :parse_args
:args_done

rem --- Configuracion compartida (config\stack.env y .env opcional) -------------
if not exist "%PROJECT%\config\stack.env" (set "DIE_CODE=50" & set "DIE_MSG=No se encuentra config\stack.env" & goto :die)
call :load_env "%PROJECT%\config\stack.env"
call :load_env "%PROJECT%\.env"
if defined ROOT_ARG (set "ROOT=%ROOT_ARG%") else if defined INSTALL_ROOT (set "ROOT=%INSTALL_ROOT%") else (set "ROOT=%STACK_ROOT_DEFAULT%")
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
if "%REQ_PORT%"=="0" if defined MYSQL_PORT set "REQ_PORT=%MYSQL_PORT%"
if "%SKIP_NOTIFIER%"=="1" set "SKIPNOTIFIER=1"
set "BASE=%ROOT%\MySQL"
set "LAUNCH=%BASE%\launchers" & set "CACHE=%BASE%\_cache" & set "TMPD=%BASE%\_tmp"
set "LOGS=%BASE%\logs" & set "MANIFEST=%BASE%\stack-manifest.env"

rem --- Estado previo (manifiesto) y migracion del formato v1 -------------------
call :load_env "%MANIFEST%"
call :migrate_v1

if "%FIXPATH%"=="1" (
  echo.
  echo == PATH de usuario ^(prioridad sobre XAMPP MySQL^) ==
  call :update_path
  exit /b 0
)

rem --- Seleccion de componentes -------------------------------------------------
if not defined COMPS set "COMPS=LATEST"
set "COMPS=%COMPS:,= %"
set "COMPS=%COMPS:+= %"
set "COMPS=%COMPS:;= %"
for %%T in (%COMPS%) do call :select_token %%T
if defined DIE_CODE goto :die
if "%SKIPNOTIFIER%"=="1" set "SEL_NOTIF="
set "SEL_COUNT=0" & set "SEL_TEXT="
for %%C in (%ALL_IDS%) do call :append_sel %%C
if %SEL_COUNT% EQU 0 (set "DIE_CODE=50" & set "DIE_MSG=La seleccion de componentes quedo vacia." & goto :die)

echo MySQL Stack para Windows 11 sin Administrador
if "%DRYRUN%"=="1" echo ^(SIMULACION: no se modificara nada^)
echo Seleccion: %SEL_TEXT%

rem ============================ ETAPA 1 =======================================
echo.
echo == 1/10 Habilitar ejecucion de scripts descargados ==
if "%DRYRUN%"=="1" (
  echo           DryRun: se establecera RemoteSigned en CurrentUser y Unblock-File en el proyecto.
) else (
  set "MS_ROOT=%PROJECT%" & set "MS_HELPER=ENABLE"
  call :ps_run
  if errorlevel 1 (call :say AVISO "No se pudo ajustar la politica de ejecucion; continuando.") else (call :say OK "Politica CurrentUser = RemoteSigned y archivos desbloqueados.")
)

rem ============================ ETAPA 2 =======================================
echo.
echo == 2/10 Requisitos minimos del sistema ==
set "VERSTR="
for /f "tokens=2 delims=[]" %%A in ('ver') do set "VERSTR=%%A"
set "BUILD=0"
for /f "tokens=2,3,4 delims=. " %%a in ("%VERSTR%") do set /a "BUILD=%%c" 2>nul
if %BUILD% GEQ 22000 (call :say OK "Windows 11 - compilacion %BUILD%") else (call :say FALLO "Se requiere Windows 11 compilacion 22000 o superior - detectada %BUILD%")
if /I "%PROCESSOR_ARCHITECTURE%"=="AMD64" (call :say OK "Windows x64 con CMD de 64 bits") else (call :say FALLO "Use CMD de 64 bits sobre Windows x64")
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" call :say AVISO "Equipo ARM64: los binarios x64 se ejecutan por emulacion"
fltmc >nul 2>&1 && call :say AVISO "Sesion elevada: se recomienda cuenta estandar para validar el escenario sin Administrador"
fltmc >nul 2>&1 || call :say OK "Cuenta estandar sin elevacion"
if /I "%USERDOMAIN%"=="%COMPUTERNAME%" (call :say OK "Cuenta local") else (call :say AVISO "Cuenta de dominio %USERDOMAIN%: las directivas pueden restringir la ejecucion")

set "VC_DLL=1"
for %%F in (vcruntime140.dll vcruntime140_1.dll msvcp140.dll) do if not exist "%SystemRoot%\System32\%%F" set "VC_DLL=0"
if "%VC_DLL%"=="1" (call :say OK "Runtime Visual C++ x64 presente") else (call :say FALLO "Falta el runtime Visual C++ x64 - instalar vc_redist.x64.exe requiere Administrador")

set "NETREL=0"
for /f "tokens=3" %%R in ('reg query "HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" /v Release 2^>nul ^| findstr /C:"Release"') do set /a "NETREL=%%R" 2>nul
if %NETREL% GEQ 379893 (call :say OK ".NET Framework 4.5.2 o superior") else (call :say AVISO ".NET Framework 4.5.2 no detectado: Notifier y Workbench 8.0 lo requieren")

echo %ROOT%| findstr /R /C:"^[A-Za-z]:\\[A-Za-z0-9_.\\-][A-Za-z0-9_.\\-]*$" >nul
if errorlevel 1 (call :say FALLO "Ruta no valida: use letras, digitos, guion, guion bajo y punto, sin espacios") else (call :say OK "Ruta de instalacion: %ROOT%")
set "PROBE=%ROOT:~0,3%.mysqlstack_probe_%RANDOM%"
md "%PROBE%" >nul 2>&1
if exist "%PROBE%" (rd "%PROBE%" >nul 2>&1 & call :say OK "Permiso de escritura en %ROOT:~0,3%") else (call :say FALLO "El usuario no puede crear carpetas en %ROOT:~0,3%")
set /a "NEED_GB=0"
set "FIRST_URL="
for %%C in (%ALL_IDS%) do call :sum_need %%C
set "FREEGB=0"
for /f "usebackq" %%G in (`powershell -NoProfile -Command "[int][math]::Floor((New-Object IO.DriveInfo '%ROOT:~0,1%').AvailableFreeSpace/1GB)" 2^>nul`) do set "FREEGB=%%G"
if %FREEGB% GEQ %NEED_GB% (call :say OK "Espacio libre: %FREEGB% GB - minimo %NEED_GB% GB para la seleccion") else (call :say FALLO "Espacio insuficiente: %FREEGB% GB - minimo %NEED_GB% GB para la seleccion")

where curl.exe >nul 2>&1 && (call :say OK "curl.exe disponible") || (call :say FALLO "curl.exe no encontrado - requerido en el instalador CMD")
where tar.exe >nul 2>&1 && (call :say OK "tar.exe disponible") || (call :say AVISO "tar.exe no encontrado: se usara Expand-Archive via PowerShell")
where msiexec.exe >nul 2>&1 && (call :say OK "msiexec.exe disponible") || (call :say AVISO "msiexec.exe no encontrado: Notifier y Workbench 8.0 no podran extraerse")
set "HTTPCODE=000"
for /f %%C in ('curl.exe -s -I -L --max-time 20 -o NUL -w "%%{http_code}" "%FIRST_URL%" 2^>nul') do set "HTTPCODE=%%C"
if "%HTTPCODE%"=="200" (call :say OK "Conectividad a cdn.mysql.com - HTTP 200") else (call :say FALLO "Sin acceso a cdn.mysql.com - respuesta %HTTPCODE%. Revise proxy o firewall")

call :say OK "Firewall: mysqld escuchara solo en 127.0.0.1, sin avisos del firewall"
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\SrpV2" >nul 2>&1 && call :say AVISO "Directivas AppLocker detectadas: podrian bloquear ejecutables"
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers" >nul 2>&1 && call :say AVISO "Directivas de restriccion de software detectadas"
call :say AVISO "Servicio de Windows: sin Administrador mysqld corre como proceso de usuario - no inicia con el sistema"
if %FAILS% GTR 0 (set "DIE_CODE=10" & set "DIE_MSG=Hay %FAILS% requisitos criticos sin cumplir. Corrija y reintente." & goto :die)

rem ============================ ETAPAS 3 y 4 ==================================
echo.
echo == 3/10 Instalaciones previas de MySQL / Workbench / Notifier ==
set "THIRD_PREV=0" & set "STACK_PREV=0" & set "TODO_COUNT=0" & set "OTHERS_TEXT="
for %%K in ("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall") do (
  for /f "delims=" %%L in ('reg query %%K /s /v DisplayName 2^>nul ^| findstr /I /R /C:"REG_SZ *MySQL" /C:"REG_SZ *MariaDB"') do call :found MYSQL "%%L"
)
if exist "%ProgramFiles%\MySQL" call :found MYSQL "%ProgramFiles%\MySQL"
if exist "%ProgramFiles(x86)%\MySQL" call :found MYSQL "%ProgramFiles(x86)%\MySQL"
if exist "%ProgramData%\MySQL" call :found MYSQL "%ProgramData%\MySQL"
sc query state= all 2>nul | findstr /I /R /C:"SERVICE_NAME: *MySQL" /C:"SERVICE_NAME: *MariaDB" >nul && call :found MYSQL "Servicio de Windows MySQL/MariaDB"
if defined MYSQL_HOME call :found MYSQL "Variable MYSQL_HOME=%MYSQL_HOME%"
set "MS_BASE=%BASE%" & set "MS_HELPER=FOREIGN"
call :ps_run
if errorlevel 1 call :found MYSQL "Proceso MySQL en ejecucion ajeno a este proyecto"
if %THIRD_PREV% EQU 0 call :say OK "No se detectaron otras instalaciones de MySQL ajenas al proyecto"

for %%C in (%ALL_IDS%) do call :classify %%C
if defined OTHERS_TEXT call :say OK "Otros componentes del proyecto ya instalados - no se tocan:%OTHERS_TEXT%"

echo.
echo == 4/10 XAMPP y WampServer ==
for %%D in (C D E F G H) do (
  if exist "%%D:\xampp" call :found STACK "XAMPP en %%D:\xampp"
  if exist "%%D:\wamp64" call :found STACK "WampServer en %%D:\wamp64"
  if exist "%%D:\wamp" call :found STACK "WampServer en %%D:\wamp"
)
sc query state= all 2>nul | findstr /I /R /C:"SERVICE_NAME: *wamp" >nul && call :found STACK "Servicio de WampServer"
if %STACK_PREV% EQU 0 call :say OK "No se detectaron XAMPP ni WampServer"
set "MS_HELPER=XAMPPCHK"
call :ps_run
if errorlevel 1 call :say OK "El PATH de usuario contiene XAMPP MySQL: el servidor del proyecto se colocara ANTES de esa entrada"

if %TODO_COUNT% EQU 0 (
  echo.
  echo == Resultado ==
  call :say OK "No hay nada que instalar: todos los componentes seleccionados ya estan instalados."
  exit /b 0
)

rem ============================ ETAPA 5 =======================================
echo.
echo == 5/10 Disponibilidad de puertos ==
set "RESERVED=," & set "OWN_SRV=0" & set "FIRST_SRV=1"
for %%C in (%SERVER_IDS%) do call :reserve_existing %%C
for %%C in (%SERVER_IDS%) do call :choose_if_todo %%C
if defined DIE_CODE goto :die

if "%DRYRUN%"=="1" (
  echo.
  echo == Plan DryRun ==
  for %%C in (%ALL_IDS%) do call :plan_line %%C
  call :compute_primary
  if defined P_BIN echo           Servidor primario ^(PATH^): %P_ID% - conexion: mysql -u root -p -h localhost -P %P_PORT% -D mysql
  call :say OK "Simulacion completada sin cambios."
  exit /b 0
)

rem ============================ ETAPA 6 =======================================
echo.
echo == 6/10 Carpeta de instalacion ^(%ROOT%^) ==
if not exist "%ROOT%" (md "%ROOT%" && set "CREATED_ROOT=1")
for %%D in ("%BASE%" "%CACHE%" "%TMPD%" "%LOGS%") do if not exist %%D md %%D
if not exist "%BASE%" (set "DIE_CODE=10" & set "DIE_MSG=No se pudo crear %BASE%" & goto :die)
call :mf_set INSTALL_ROOT "%ROOT%"
call :mf_set BASE "%BASE%"
if "%CREATED_ROOT%"=="1" call :mf_set CREATED_ROOT 1
call :say OK "Carpeta lista: %BASE%"

rem ============================ ETAPA 7 =======================================
echo.
echo == 7/10 Descarga, verificacion e instalacion de paquetes ==
for %%C in (%ALL_IDS%) do call :install_component %%C
if defined DIE_CODE goto :die

rem ============================ ETAPA 8 =======================================
echo.
echo == 8/10 Configuracion e inicio de los servidores ==
set "PW_TARGETS="
for %%C in (%SERVER_IDS%) do call :configure_server %%C
if defined DIE_CODE goto :die
for %%C in (%ALL_IDS%) do call :register_client %%C

rem ============================ ETAPA 9 =======================================
echo.
echo == 9/10 Contrasena de root ==
if not defined PW_TARGETS (
  echo           No se instalaron servidores en esta ejecucion.
) else (
  set "MS_FALLBACK=%FALLBACK_ROOT_PASSWORD%"
  set "MS_PWMODE=prompt"
  if "%NOPROMPT%"=="1" set "MS_PWMODE=fallback"
  if "%BLANK%"=="1" set "MS_PWMODE=blank"
  set "MS_TARGETS=%PW_TARGETS%"
  set "MS_HELPER=PWSET"
  call :ps_run
  if errorlevel 1 (set "DIE_CODE=50" & set "DIE_MSG=No se pudo asignar contrasena a root." & goto :die)
)

rem ============================ ETAPA 10 ======================================
echo.
echo == 10/10 PATH, lanzadores y accesos directos ==
if not exist "%LAUNCH%" md "%LAUNCH%"
for %%C in (%ALL_IDS%) do call :finish_component %%C
if defined DIE_CODE goto :die
call :update_path
if exist "%TMPD%" rd /s /q "%TMPD%" >nul 2>&1

echo.
echo INSTALACION COMPLETADA
for %%C in (%SERVER_IDS%) do call :summary_server %%C
echo   Abra una NUEVA consola para ver el PATH actualizado.
exit /b 0

rem ============================================================================
rem  SUBRUTINAS
rem ============================================================================
:die
echo   [ERROR] %DIE_MSG%
exit /b %DIE_CODE%

:fail
rem %1 = codigo  %2 = mensaje   (no termina el script: el flujo principal hace goto :die)
set "DIE_CODE=%~1"
set "DIE_MSG=%~2"
exit /b 1

:say
rem %1 = OK|AVISO|FALLO   %2 = texto
if /I "%~1"=="AVISO" set /a WARNS+=1
if /I "%~1"=="FALLO" set /a FAILS+=1
setlocal EnableDelayedExpansion
set "T=%~2"
if /I "%~1"=="OK" echo   [OK]    !T!
if /I "%~1"=="AVISO" echo   [AVISO] !T!
if /I "%~1"=="FALLO" echo   [ERROR] !T!
endlocal
exit /b 0

:found
rem %1 = MYSQL|STACK   %2 = descripcion
if /I "%~1"=="MYSQL" set /a THIRD_PREV+=1
if /I "%~1"=="STACK" set /a STACK_PREV+=1
setlocal EnableDelayedExpansion
set "T=%~2"
echo   [AVISO] !T!
endlocal
exit /b 0

:load_env
if not exist "%~1" exit /b 0
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~1") do set "%%A=%%B"
exit /b 0

:migrate_v1
rem Formato v1 (un solo servidor): PORT, XPORT, NOTIFIER -> claves por componente
if defined SRV_INSTALLED exit /b 0
if not defined PORT exit /b 0
set "SRV_INSTALLED=1"
set "SRV_PORT=%PORT%"
if defined XPORT set "SRV_XPORT=%XPORT%"
set "WB_INSTALLED=1"
set "NOTIF_INSTALLED=0"
if defined NOTIFIER set "NOTIF_INSTALLED=%NOTIFIER%"
if "%DRYRUN%"=="0" if exist "%MANIFEST%" (
  call :mf_set SRV_INSTALLED 1
  call :mf_set SRV_PORT %PORT%
  call :mf_set WB_INSTALLED 1
  call :mf_set NOTIF_INSTALLED %NOTIF_INSTALLED%
  call :mf_del PORT
  call :mf_del XPORT
  call :mf_del NOTIFIER
)
set "PORT=" & set "XPORT=" & set "NOTIFIER="
exit /b 0

:mf_set
rem %1 clave  %2 valor   (reescribe el manifiesto sin la clave y la agrega al final)
if not exist "%BASE%" exit /b 0
if exist "%MANIFEST%" (findstr /V /B /C:"%~1=" "%MANIFEST%" > "%MANIFEST%.tmp") else (type nul > "%MANIFEST%.tmp")
>>"%MANIFEST%.tmp" echo %~1=%~2
move /y "%MANIFEST%.tmp" "%MANIFEST%" >nul
exit /b 0

:mf_del
if not exist "%MANIFEST%" exit /b 0
findstr /V /B /C:"%~1=" "%MANIFEST%" > "%MANIFEST%.tmp"
move /y "%MANIFEST%.tmp" "%MANIFEST%" >nul
exit /b 0

:select_token
rem %1 = ALL | LATEST | LTS | SRV | WB | NOTIF | SRVLTS | WB8 | T | U | L | 1..5
rem OJO: "if cond (bloque) & otro" ejecuta "otro" SIEMPRE; por eso TOK_OK va DENTRO de cada bloque.
set "TK=%~1"
set "TOK_OK=0"
if /I "%TK%"=="ALL" (for %%X in (%ALL_IDS%) do (set "SEL_%%X=1" & set "TOK_OK=1"))
if /I "%TK%"=="TODO" (for %%X in (%ALL_IDS%) do (set "SEL_%%X=1" & set "TOK_OK=1"))
if /I "%TK%"=="T" (for %%X in (%ALL_IDS%) do (set "SEL_%%X=1" & set "TOK_OK=1"))
if /I "%TK%"=="LATEST" (set "SEL_SRV=1" & set "SEL_WB=1" & set "SEL_NOTIF=1" & set "TOK_OK=1")
if /I "%TK%"=="U" (set "SEL_SRV=1" & set "SEL_WB=1" & set "SEL_NOTIF=1" & set "TOK_OK=1")
if /I "%TK%"=="LTS" (set "SEL_SRVLTS=1" & set "SEL_WB8=1" & set "TOK_OK=1")
if /I "%TK%"=="L" (set "SEL_SRVLTS=1" & set "SEL_WB8=1" & set "TOK_OK=1")
if "%TK%"=="1" (set "SEL_SRV=1" & set "TOK_OK=1")
if "%TK%"=="2" (set "SEL_WB=1" & set "TOK_OK=1")
if "%TK%"=="3" (set "SEL_NOTIF=1" & set "TOK_OK=1")
if "%TK%"=="4" (set "SEL_SRVLTS=1" & set "TOK_OK=1")
if "%TK%"=="5" (set "SEL_WB8=1" & set "TOK_OK=1")
for %%X in (%ALL_IDS%) do if /I "%TK%"=="%%X" (set "SEL_%%X=1" & set "TOK_OK=1")
if "%TOK_OK%"=="0" call :fail 50 "Componente desconocido: %TK%. Use SRV, WB, NOTIF, SRVLTS, WB8, ALL, LATEST o LTS."
exit /b 0

:append_sel
call set "S=%%SEL_%~1%%"
if not "%S%"=="1" exit /b 0
set /a SEL_COUNT+=1
call set "L=%%%~1_LABEL%%"
if defined SEL_TEXT (set "SEL_TEXT=%SEL_TEXT%, %L%") else (set "SEL_TEXT=%L%")
exit /b 0

:sum_need
call set "S=%%SEL_%~1%%"
if not "%S%"=="1" exit /b 0
call set "N=%%%~1_NEED_GB%%"
set /a NEED_GB+=%N%
if not defined FIRST_URL call set "FIRST_URL=%%%~1_URL%%"
exit /b 0

:load_comp
rem Carga en variables C_* los datos del componente %1 (NONE = vacio)
set "C_ID=%~1"
call set "C_LABEL=%%%~1_LABEL%%"
call set "C_KIND=%%%~1_KIND%%"
call set "C_URL=%%%~1_URL%%"
call set "C_MD5=%%%~1_MD5%%"
call set "C_FOLDER=%%%~1_FOLDER%%"
call set "C_FILE=%%%~1_FILE%%"
call set "C_DIR=%%%~1_DIR%%"
call set "C_DATADIR=%%%~1_DATADIR%%"
call set "C_SUFFIX=%%%~1_SUFFIX%%"
call set "C_LINK=%%%~1_LINK%%"
if /I "%C_FOLDER%"=="NONE" set "C_FOLDER="
if /I "%C_DATADIR%"=="NONE" set "C_DATADIR="
if /I "%C_SUFFIX%"=="NONE" set "C_SUFFIX="
set "C_PATH=%BASE%\%C_DIR%"
set "C_DATA="
if defined C_DATADIR set "C_DATA=%BASE%\%C_DATADIR%"
exit /b 0

:classify
rem Decide si el componente %1 se instala: Installed (se omite salvo /FORCE) | Partial | Absent
call set "S=%%SEL_%~1%%"
call set "I=%%%~1_INSTALLED%%"
call set "L=%%%~1_LABEL%%"
call set "D=%%%~1_DIR%%"
if not "%S%"=="1" (
  if "%I%"=="1" set "OTHERS_TEXT=%OTHERS_TEXT% %~1"
  exit /b 0
)
set "HAVE_DIR=0"
if exist "%BASE%\%D%\" set "HAVE_DIR=1"
if "%I%"=="1" if "%HAVE_DIR%"=="1" if "%FORCE%"=="0" (
  call :say OK "%L%: ya instalado - se omite; use /FORCE para reinstalar"
  exit /b 0
)
if "%I%"=="1" if "%HAVE_DIR%"=="1" call :say AVISO "%L%: se reinstalara - /FORCE"
if not "%I%"=="1" if "%HAVE_DIR%"=="1" call :say AVISO "%L%: instalacion incompleta previa - se reinstalara"
set "TODO_%~1=1"
set /a TODO_COUNT+=1
exit /b 0

:reserve_existing
rem Reserva los puertos de servidores propios ya instalados que NO se reinstalan
call set "I=%%%~1_INSTALLED%%"
call set "T=%%TODO_%~1%%"
if not "%I%"=="1" exit /b 0
if "%T%"=="1" exit /b 0
set /a OWN_SRV+=1
call set "P=%%%~1_PORT%%"
call set "XP=%%%~1_XPORT%%"
set "RESERVED=%RESERVED%%P%,%XP%,"
exit /b 0

:choose_if_todo
call set "T=%%TODO_%~1%%"
if not "%T%"=="1" exit /b 0
if defined DIE_CODE exit /b 1
call :choose_ports %~1
exit /b %ERRORLEVEL%

:port_ok
rem Devuelve 0 si el puerto %1 esta libre (no escucha y no esta reservado), 1 si no
netstat -an | findstr /R /C:":%~1 .*LISTENING" >nul
if not errorlevel 1 exit /b 1
echo %RESERVED%| findstr /C:",%~1," >nul
if not errorlevel 1 exit /b 1
exit /b 0

:choose_ports
rem Elige puerto clasico y puerto del protocolo X para el servidor %1
call :load_comp %~1
set "PORT_SEL=" & set "XPORT_SEL=" & set "PORT_WHY="
set /a "CONFL=THIRD_PREV+STACK_PREV+OWN_SRV"
set "REQ=0"
if "%FIRST_SRV%"=="1" set "REQ=%REQ_PORT%"
if not "%REQ%"=="0" call :port_ok %REQ%
if not "%REQ%"=="0" if errorlevel 1 (call :fail 20 "El puerto solicitado %REQ% no esta disponible." & exit /b 1)
if not "%REQ%"=="0" (set "PORT_SEL=%REQ%" & set "PORT_WHY=puerto solicitado")
if not defined PORT_SEL if %CONFL% EQU 0 call :port_ok %DEFAULT_PORT%
if not defined PORT_SEL if %CONFL% EQU 0 if not errorlevel 1 (set "PORT_SEL=%DEFAULT_PORT%" & set "PORT_WHY=sin otras instalaciones: puerto por defecto")
if not defined PORT_SEL for /L %%P in (3307,1,3399) do if not defined PORT_SEL (call :port_ok %%P && set "PORT_SEL=%%P")
if not defined PORT_SEL (call :fail 20 "No hay puerto libre en el rango 3307-3399." & exit /b 1)
if not defined PORT_WHY set "PORT_WHY=otras instalaciones o puerto ocupado: puerto alternativo"
set /a "XS=DEFAULT_XPORT"
if %CONFL% GTR 0 set /a "XS=DEFAULT_XPORT+1"
set /a "XE=DEFAULT_XPORT+200"
for /L %%P in (%XS%,1,%XE%) do if not defined XPORT_SEL if not "%%P"=="%PORT_SEL%" (call :port_ok %%P && set "XPORT_SEL=%%P")
if not defined XPORT_SEL (call :fail 20 "No hay puerto libre para el protocolo X." & exit /b 1)
set "NEWPORT_%~1=%PORT_SEL%"
set "NEWXPORT_%~1=%XPORT_SEL%"
set "RESERVED=%RESERVED%%PORT_SEL%,%XPORT_SEL%,"
set /a OWN_SRV+=1
set "FIRST_SRV=0"
call :say OK "%C_LABEL%: puerto MySQL %PORT_SEL% - %PORT_WHY% - protocolo X %XPORT_SEL%"
exit /b 0

:plan_line
call set "T=%%TODO_%~1%%"
if not "%T%"=="1" exit /b 0
call :load_comp %~1
echo           Instalaria %C_LABEL% en %C_PATH%
echo              acceso directo: %C_LINK%
if /I "%C_KIND%"=="server" call echo              puerto %%NEWPORT_%~1%% - datos %C_DATA%
exit /b 0

:compute_primary
rem Servidor primario del PATH: SRV si esta instalado (o se va a instalar); si no, SRVLTS
set "P_ID=" & set "P_BIN=" & set "P_PORT="
call :primary_of SRV
if not defined P_ID call :primary_of SRVLTS
exit /b 0

:primary_of
call set "I=%%%~1_INSTALLED%%"
call set "T=%%TODO_%~1%%"
call set "D=%%%~1_DIR%%"
call set "NP=%%NEWPORT_%~1%%"
call set "OP=%%%~1_PORT%%"
if not "%I%"=="1" if not "%T%"=="1" exit /b 0
set "P_ID=%~1"
set "P_BIN=%BASE%\%D%\bin"
set "P_PORT=%OP%"
if defined NP set "P_PORT=%NP%"
exit /b 0

:download_verify
rem %1 url  %2 destino  %3 md5  %4 etiqueta
if exist "%~2" (
  call :md5_of "%~2"
  if /I "%MD5_ACTUAL%"=="%~3" (call :say OK "%~4 ya descargado y verificado - cache" & exit /b 0)
  del /q "%~2"
)
echo           Descargando %~4 ...
curl.exe -L --fail --retry 3 --retry-delay 3 --progress-bar -o "%~2" "%~1"
if errorlevel 1 (call :fail 30 "curl fallo al descargar %~4" & exit /b 1)
call :md5_of "%~2"
if /I not "%MD5_ACTUAL%"=="%~3" (del /q "%~2" & call :fail 30 "MD5 incorrecto en %~4 - esperado %~3 - obtenido %MD5_ACTUAL%" & exit /b 1)
call :say OK "%~4 descargado y verificado - MD5"
exit /b 0

:md5_of
set "MD5_ACTUAL="
for /f "delims=" %%H in ('certutil -hashfile "%~1" MD5 ^| findstr /R /C:"^[0-9a-fA-F ][0-9a-fA-F ]*$"') do set "MD5_ACTUAL=%%H"
set "MD5_ACTUAL=%MD5_ACTUAL: =%"
exit /b 0

:unzip
rem %1 zip  %2 destino
if not exist "%~2" md "%~2"
where tar.exe >nul 2>&1 && (tar -xf "%~1" -C "%~2" & if not errorlevel 1 exit /b 0)
powershell -NoProfile -Command "Expand-Archive -LiteralPath '%~1' -DestinationPath '%~2' -Force"
exit /b %ERRORLEVEL%

:install_component
call set "T=%%TODO_%~1%%"
if not "%T%"=="1" exit /b 0
if defined DIE_CODE exit /b 1
call :load_comp %~1
set "MS_BASE=%C_PATH%" & set "MS_HELPER=STOPOWN"
call :ps_run
if /I "%C_KIND%"=="server" call :inst_server
if /I "%C_KIND%"=="wbzip" call :inst_wbzip
if /I "%C_KIND%"=="wbmsi" call :inst_msi MySQLWorkbench.exe 0
if /I "%C_KIND%"=="notifier" call :inst_msi MySQLNotifier.exe 1
exit /b %ERRORLEVEL%

:inst_server
call :download_verify "%C_URL%" "%CACHE%\%C_FILE%" "%C_MD5%" "%C_LABEL%"
if errorlevel 1 exit /b 1
if exist "%TMPD%\%C_ID%" rd /s /q "%TMPD%\%C_ID%"
echo           Extrayendo %C_LABEL%...
call :unzip "%CACHE%\%C_FILE%" "%TMPD%\%C_ID%"
if not exist "%TMPD%\%C_ID%\%C_FOLDER%\bin\mysqld.exe" (call :fail 40 "El ZIP de %C_LABEL% no contiene bin\mysqld.exe" & exit /b 1)
if exist "%C_PATH%" rd /s /q "%C_PATH%"
move "%TMPD%\%C_ID%\%C_FOLDER%" "%C_PATH%" >nul
if errorlevel 1 (call :fail 40 "No se pudo mover %C_LABEL% a %C_PATH%" & exit /b 1)
rd /s /q "%TMPD%\%C_ID%" >nul 2>&1
"%C_PATH%\bin\mysqld.exe" --version >nul 2>&1
if errorlevel 1 (call :fail 40 "mysqld.exe no se ejecuta - verifique runtime VC++ o directivas de ejecucion" & exit /b 1)
set "OK_%C_ID%=1"
call :say OK "%C_LABEL% instalado"
exit /b 0

:inst_wbzip
call :download_verify "%C_URL%" "%CACHE%\%C_FILE%" "%C_MD5%" "%C_LABEL%"
if errorlevel 1 exit /b 1
if exist "%C_PATH%" rd /s /q "%C_PATH%"
echo           Extrayendo %C_LABEL%...
call :unzip "%CACHE%\%C_FILE%" "%C_PATH%"
if not exist "%C_PATH%\MySQL Workbench.exe" (call :fail 40 "No se encontro MySQL Workbench.exe tras extraer" & exit /b 1)
set "OK_%C_ID%=1"
call :say OK "%C_LABEL% instalado"
exit /b 0

:inst_msi
rem %1 = ejecutable a localizar  %2 = 1 si el componente es opcional (un fallo no detiene todo)
rem Los MSI de Notifier y Workbench 8.0 exigen Administrador ('Privileged'); esa condicion no esta en la
rem secuencia administrativa, por eso se extraen como imagen administrativa (msiexec /a) a una carpeta de usuario.
set "OPTIONAL=%~2"
call :download_verify "%C_URL%" "%CACHE%\%C_FILE%" "%C_MD5%" "%C_LABEL%"
if errorlevel 1 (if "%OPTIONAL%"=="1" (set "DIE_CODE=" & set "DIE_MSG=" & call :say AVISO "%C_LABEL% no se pudo descargar; se continua sin el" & exit /b 0) else exit /b 1)
set "IMG=%TMPD%\%C_ID%-image"
if exist "%IMG%" rd /s /q "%IMG%"
md "%IMG%"
echo           Extrayendo %C_LABEL% con msiexec /a ^(puede tardar varios minutos^)...
start "" /wait msiexec.exe /a "%CACHE%\%C_FILE%" /qn TARGETDIR="%IMG%" /L*v "%LOGS%\%C_ID%-msiexec.log"
set "NEXE="
for /r "%IMG%" %%F in (%~1) do if exist "%%F" set "NEXE=%%F"
if not defined NEXE (
  rd /s /q "%IMG%" >nul 2>&1
  if "%OPTIONAL%"=="1" (call :say AVISO "No se pudo extraer %C_LABEL% sin Administrador - ver %LOGS%\%C_ID%-msiexec.log" & exit /b 0)
  call :fail 40 "No se pudo extraer %C_LABEL% sin Administrador - ver %LOGS%\%C_ID%-msiexec.log"
  exit /b 1
)
for %%D in ("%NEXE%") do set "NDIR=%%~dpD"
if exist "%C_PATH%" rd /s /q "%C_PATH%"
move "%NDIR:~0,-1%" "%C_PATH%" >nul
if errorlevel 1 (call :fail 40 "No se pudo mover %C_LABEL% a %C_PATH%" & exit /b 1)
rd /s /q "%IMG%" >nul 2>&1
set "OK_%C_ID%=1"
call :say OK "%C_LABEL% extraido"
exit /b 0

:configure_server
rem my.ini, directorio de datos, arranque y registro en el manifiesto del servidor %1
call set "OKF=%%OK_%~1%%"
if not "%OKF%"=="1" exit /b 0
if defined DIE_CODE exit /b 1
call :load_comp %~1
call set "PORT_N=%%NEWPORT_%~1%%"
call set "XPORT_N=%%NEWXPORT_%~1%%"
set "FRESH=0"
set "INI=%C_PATH%\my.ini"
set "SRVF=%C_PATH:\=/%"
set "DATAF=%C_DATA:\=/%"
(
  echo [client]
  echo port=%PORT_N%
  echo default-character-set=utf8mb4
  echo.
  echo [mysql]
  echo default-character-set=utf8mb4
  echo.
  echo [mysqld]
  echo basedir=%SRVF%
  echo datadir=%DATAF%
  echo port=%PORT_N%
  echo bind-address=127.0.0.1
  echo mysqlx-port=%XPORT_N%
  echo mysqlx-bind-address=127.0.0.1
  echo character-set-server=utf8mb4
  echo log-error=%DATAF%/mysql-error.log
) > "%INI%"
call :say OK "%C_LABEL%: my.ini generado - escucha solo en 127.0.0.1"
if exist "%C_DATA%\mysql" (
  call :say OK "%C_LABEL%: directorio de datos ya inicializado - se conserva"
) else (
  if not exist "%C_DATA%" md "%C_DATA%"
  "%C_PATH%\bin\mysqld.exe" --defaults-file="%INI%" --initialize-insecure --console > "%LOGS%\initialize-%C_ID%.log" 2>&1
  if errorlevel 1 (call :fail 50 "Fallo --initialize-insecure en %C_LABEL%. Revise %LOGS%\initialize-%C_ID%.log" & exit /b 1)
  call :say OK "%C_LABEL%: directorio de datos inicializado"
  set "FRESH=1"
)
powershell -NoProfile -Command "Start-Process -FilePath '%C_PATH%\bin\mysqld.exe' -ArgumentList '--defaults-file=%INI%' -WindowStyle Hidden"
set "TRY=0"
:wait_up
call :port_listening %PORT_N%
if not errorlevel 1 goto :up_ok
set /a TRY+=1
if %TRY% GEQ 60 (call :fail 50 "%C_LABEL% no quedo escuchando en el puerto %PORT_N%. Revise %C_DATA%\mysql-error.log" & exit /b 1)
timeout /t 1 /nobreak >nul
goto :wait_up
:up_ok
call :say OK "%C_LABEL%: mysqld en ejecucion - 127.0.0.1:%PORT_N%"
set "%~1_INSTALLED=1"
set "%~1_PORT=%PORT_N%"
set "%~1_XPORT=%XPORT_N%"
call :mf_set %~1_INSTALLED 1
call :mf_set %~1_PORT %PORT_N%
call :mf_set %~1_XPORT %XPORT_N%
if "%FRESH%"=="1" if defined PW_TARGETS set "PW_TARGETS=%PW_TARGETS%;%C_PATH%\bin\mysql.exe|%PORT_N%"
if "%FRESH%"=="1" if not defined PW_TARGETS set "PW_TARGETS=%C_PATH%\bin\mysql.exe|%PORT_N%"
if not "%FRESH%"=="1" call :say OK "%C_LABEL%: datos existentes - se conserva la contrasena actual de root"
exit /b 0

:port_listening
rem Devuelve 0 si algo escucha en el puerto %1
netstat -an | findstr /R /C:":%~1 .*LISTENING" >nul
exit /b %ERRORLEVEL%

:register_client
rem Registra Workbench y Notifier (no son servidores) como instalados
call set "OKF=%%OK_%~1%%"
if not "%OKF%"=="1" exit /b 0
call :load_comp %~1
if /I "%C_KIND%"=="server" exit /b 0
set "%~1_INSTALLED=1"
call :mf_set %~1_INSTALLED 1
exit /b 0

:finish_component
rem Lanzadores (servidores) y acceso directo en el escritorio del componente %1
call set "OKF=%%OK_%~1%%"
if not "%OKF%"=="1" exit /b 0
call :load_comp %~1
if /I "%C_KIND%"=="server" call :make_launchers %~1
set "MS_LNK_NAME=%C_LINK%"
set "MS_LNK_WORKDIR=%C_PATH%"
set "MS_LNK_ICON="
if /I "%C_KIND%"=="server" (
  set "MS_LNK_TARGET=%LAUNCH%\mysql-console%C_SUFFIX%.cmd"
  set "MS_LNK_WORKDIR=%BASE%"
  set "MS_LNK_ICON=%C_PATH%\bin\mysql.exe,0"
)
if /I "%C_KIND%"=="wbzip" set "MS_LNK_TARGET=%C_PATH%\MySQL Workbench.exe"
if /I "%C_KIND%"=="wbmsi" set "MS_LNK_TARGET=%C_PATH%\MySQLWorkbench.exe"
if /I "%C_KIND%"=="notifier" set "MS_LNK_TARGET=%C_PATH%\MySQLNotifier.exe"
set "MS_HELPER=SHORTCUT"
call :ps_run
call :say OK "Acceso directo: %C_LINK%"
exit /b 0

:make_launchers
call set "PORT_N=%%%~1_PORT%%"
set "MS_BASE=%BASE%" & set "MS_PORT=%PORT_N%" & set "MS_SRVDIR=%C_DIR%" & set "MS_DATADIR=%C_DATADIR%" & set "MS_LABEL=%C_LABEL%"
set "MS_HELPER=RENDER"
for %%N in (mysql-console start-mysql-server stop-mysql-server) do (
  set "MS_TPL=%PROJECT%\src\templates\%%N.cmd.tpl"
  set "MS_OUT=%LAUNCH%\%%N%C_SUFFIX%.cmd"
  call :ps_run
)
exit /b 0

:update_path
rem Recalcula PATH y MYSQL_TCP_PORT de usuario: el servidor primario va ANTES de la entrada de XAMPP MySQL
set "P_ID=" & set "P_BIN=" & set "P_PORT="
if "%SRV_INSTALLED%"=="1" (set "P_ID=SRV" & set "P_BIN=%BASE%\%SRV_DIR%\bin" & set "P_PORT=%SRV_PORT%")
if not defined P_ID if "%SRVLTS_INSTALLED%"=="1" (set "P_ID=SRVLTS" & set "P_BIN=%BASE%\%SRVLTS_DIR%\bin" & set "P_PORT=%SRVLTS_PORT%")
set "MS_ADD=%P_BIN%"
set "MS_PORT=%P_PORT%"
set "MS_REMOVE=%BASE%\%SRV_DIR%\bin;%BASE%\%SRVLTS_DIR%\bin"
set "MS_HELPER=PATHSET"
call :ps_run
exit /b 0

:summary_server
call set "I=%%%~1_INSTALLED%%"
call set "T=%%TODO_%~1%%"
if not "%I%"=="1" exit /b 0
if not "%T%"=="1" exit /b 0
call :load_comp %~1
call set "PORT_N=%%%~1_PORT%%"
if /I "%P_ID%"=="%~1" (echo   %C_LABEL%: mysql -u root -p -h localhost -P %PORT_N% -D mysql) else (echo   %C_LABEL%: "%C_PATH%\bin\mysql.exe" -u root -p -h localhost -P %PORT_N% -D mysql)
echo      detener: %LAUNCH%\stop-mysql-server%C_SUFFIX%.cmd
exit /b 0

:ps_run
rem Ejecuta en memoria el bloque PowerShell embebido cuyo nombre esta en %MS_HELPER%
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:MS_SELF); $m=[regex]::Match($t,'(?s)#PS:'+$env:MS_HELPER+':BEGIN(.*?)#PS:'+$env:MS_HELPER+':END'); $c=[regex]::Replace($m.Groups[1].Value,'(?m)^::',''); & ([scriptblock]::Create($c))"
exit /b %ERRORLEVEL%

rem ============================================================================
rem  BLOQUES POWERSHELL EMBEBIDOS (las lineas empiezan por "::" para que CMD las ignore)
rem ============================================================================
exit /b 0

::#PS:ENABLE:BEGIN
::$ErrorActionPreference = 'Stop'
::try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force } catch { Write-Host "  [AVISO] $($_.Exception.Message)" -ForegroundColor Yellow }
::Get-ChildItem -LiteralPath $env:MS_ROOT -Recurse -File -Force -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
::$p = [string](Get-ExecutionPolicy -Scope CurrentUser)
::if ($p -in 'RemoteSigned','Unrestricted','Bypass') { exit 0 } else { exit 1 }
::#PS:ENABLE:END

::#PS:FOREIGN:BEGIN
::$b = $env:MS_BASE.TrimEnd('\') + '\'
::$n = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(mysqld|mysqld-nt|MySQLNotifier|MySQLWorkbench|MySQL Workbench)$' } | Where-Object { $p = ''; try { $p = [string]$_.Path } catch { }; -not $p.StartsWith($b, [StringComparison]::OrdinalIgnoreCase) }).Count
::exit ([math]::Min($n, 100))
::#PS:FOREIGN:END

::#PS:XAMPPCHK:BEGIN
::$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $false)
::try { $raw = [string]$k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } finally { $k.Close() }
::$has = $false
::foreach ($p in $raw -split ';') { if ($p.Trim() -match '(?i)[\\/]xampp[\\/]mysql\s*[\\/]bin[\\/]?\s*$') { $has = $true } }
::if ($has) { exit 1 } else { exit 0 }
::#PS:XAMPPCHK:END

::#PS:STOPOWN:BEGIN
::$base = $env:MS_BASE.TrimEnd('\') + '\'
::Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $e = ''; try { $e = [string]$_.Path } catch { }; if ($e.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } }
::#PS:STOPOWN:END

::#PS:PWSET:BEGIN
::$ErrorActionPreference = 'Stop'
::$fb = $env:MS_FALLBACK; $mode = $env:MS_PWMODE
::$targets = @($env:MS_TARGETS -split ';' | Where-Object { $_ } | ForEach-Object { $a = $_ -split '\|'; [pscustomobject]@{ Exe = $a[0]; Port = [int]$a[1] } })
::function Get-Plain([securestring]$s) { $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s); try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) } }
::function Invoke-Sql($mysql, $port, $sql) {
::  $id = [guid]::NewGuid().ToString('N')
::  $cnf = Join-Path $env:TEMP "msq_$id.cnf"; $sq = Join-Path $env:TEMP "msq_$id.sql"
::  $o = Join-Path $env:TEMP "msq_$id.out"; $e = Join-Path $env:TEMP "msq_$id.err"
::  try {
::    $enc = New-Object Text.UTF8Encoding($false)
::    [IO.File]::WriteAllText($cnf, "[client]`r`nuser=root`r`n", $enc); [IO.File]::WriteAllText($sq, $sql, $enc)
::    $a = @("--defaults-extra-file=`"$cnf`"", '--protocol=TCP', '--host=127.0.0.1', "--port=$port", '--skip-password')
::    $p = Start-Process -FilePath $mysql -ArgumentList $a -Wait -PassThru -NoNewWindow -RedirectStandardInput $sq -RedirectStandardOutput $o -RedirectStandardError $e
::    return $p.ExitCode
::  } finally {
::    foreach ($f in $cnf,$sq,$o,$e) { if (Test-Path $f) { try { [IO.File]::WriteAllBytes($f, (New-Object byte[] ((Get-Item $f).Length))) } catch {}; Remove-Item $f -Force -ErrorAction SilentlyContinue } }
::  }
::}
::function Esc([string]$v) { $v.Replace('\','\\').Replace("'","''") }
::function Apply-All([string]$pw, [string]$label) {
::  $worst = 0
::  foreach ($t in $targets) {
::    $rc = Invoke-Sql $t.Exe $t.Port ("ALTER USER 'root'@'localhost' IDENTIFIED BY '" + (Esc $pw) + "'; FLUSH PRIVILEGES;")
::    if ($rc -ne 0) { Write-Host "  [ERROR] No se pudo asignar contrasena en el puerto $($t.Port)" -ForegroundColor Red; $worst = 1 }
::    elseif ($label -eq 'fallback') { Write-Host "  [AVISO] Puerto $($t.Port): root usa la contrasena de respaldo $fb - CAMBIELA cuanto antes con ALTER USER" -ForegroundColor Yellow }
::    else { Write-Host "  [OK]    Puerto $($t.Port): contrasena de root establecida" -ForegroundColor Green }
::  }
::  return $worst
::}
::function Blank-All() {
::  $worst = 0
::  foreach ($t in $targets) {
::    if ((Invoke-Sql $t.Exe $t.Port 'SELECT 1;') -ne 0) { Write-Host "  [ERROR] No se pudo conectar como root en el puerto $($t.Port)" -ForegroundColor Red; $worst = 1 }
::    else { Write-Host "  [OK]    Puerto $($t.Port): root sin contrasena - segun su eleccion" -ForegroundColor Green }
::  }
::  return $worst
::}
::if ($mode -eq 'blank') { exit (Blank-All) }
::if ($mode -eq 'fallback') { exit (Apply-All $fb 'fallback') }
::while ($true) {
::  $s1 = Read-Host 'Contrasena para el usuario root de MySQL (ENTER = en blanco)' -AsSecureString
::  if ($s1.Length -eq 0) {
::    $ans = Read-Host 'Confirma dejar la contrasena EN BLANCO? (s/N)'
::    if ($ans -match '^(s|si|y|yes)$') { exit (Blank-All) }
::    continue
::  }
::  $s2 = Read-Host 'Repita la contrasena' -AsSecureString
::  $p1 = Get-Plain $s1
::  if ($p1 -ceq (Get-Plain $s2)) { exit (Apply-All $p1 'custom') }
::  Write-Host '  [AVISO] Las contrasenas no coinciden. Intente de nuevo.' -ForegroundColor Yellow
::}
::#PS:PWSET:END

::#PS:PATHSET:BEGIN
::$ErrorActionPreference = 'Stop'
::$add = $env:MS_ADD; $port = $env:MS_PORT
::$remove = @($env:MS_REMOVE -split ';' | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') })
::$pattern = '(?i)[\\/]xampp[\\/]mysql\s*[\\/]bin[\\/]?\s*$'
::$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
::try {
::  $raw = [string]$k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
::  $drop = @($remove) + @($add) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
::  $parts = New-Object System.Collections.Generic.List[string]
::  foreach ($p in $raw -split ';') {
::    if ($p.Trim() -eq '') { continue }
::    $ours = $false; foreach ($d in $drop) { if ($p.TrimEnd('\') -ieq $d) { $ours = $true; break } }
::    if (-not $ours) { $parts.Add($p) }
::  }
::  $xamppUser = $false; foreach ($p in $parts) { if ($p.Trim() -match $pattern) { $xamppUser = $true } }
::  if ($add) {
::    $at = -1
::    for ($i = 0; $i -lt $parts.Count; $i++) { if ($parts[$i].Trim() -match $pattern) { $at = $i; break } }
::    if ($at -ge 0) { $parts.Insert($at, $add) } else { $parts.Add($add) }
::  }
::  $new = $parts -join ';'
::  if ($new -ne $raw) { $k.SetValue('Path', $new, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
::} finally { $k.Close() }
::if ($port) { [Environment]::SetEnvironmentVariable('MYSQL_TCP_PORT', $port, 'User') } else { [Environment]::SetEnvironmentVariable('MYSQL_TCP_PORT', $null, 'User') }
::if ($add) {
::  if ($xamppUser) { Write-Host "  [OK]    PATH de usuario: $add se coloco ANTES de la entrada de XAMPP MySQL." -ForegroundColor Green }
::  else { Write-Host "  [OK]    PATH de usuario += $add (no hay entrada de XAMPP MySQL en el PATH de usuario)." -ForegroundColor Green }
::  Write-Host "          MYSQL_TCP_PORT=$port"
::  $mk = $null
::  try { $mk = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $false) } catch { }
::  if ($mk) { $mp = [string]$mk.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); $mk.Close()
::    foreach ($p in $mp -split ';') { if ($p.Trim() -match $pattern) { Write-Host '  [AVISO] XAMPP MySQL esta en el PATH del EQUIPO, que Windows evalua antes que el del usuario: "mysql" seguira resolviendo a XAMPP. Use los lanzadores o la ruta completa.' -ForegroundColor Yellow; break } } }
::} else { Write-Host '  [OK]    PATH de usuario sin carpetas del proyecto - no queda ningun servidor instalado.' -ForegroundColor Green }
::#PS:PATHSET:END

::#PS:RENDER:BEGIN
::$txt = [IO.File]::ReadAllText($env:MS_TPL).Replace('@@BASE@@', $env:MS_BASE).Replace('@@PORT@@', $env:MS_PORT).Replace('@@SRVDIR@@', $env:MS_SRVDIR).Replace('@@DATADIR@@', $env:MS_DATADIR).Replace('@@LABEL@@', $env:MS_LABEL)
::[IO.File]::WriteAllText($env:MS_OUT, $txt, [Text.Encoding]::ASCII)
::#PS:RENDER:END

::#PS:SHORTCUT:BEGIN
::$ws = New-Object -ComObject WScript.Shell
::$lnk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) ($env:MS_LNK_NAME + '.lnk')))
::$lnk.TargetPath = $env:MS_LNK_TARGET
::$lnk.WorkingDirectory = $env:MS_LNK_WORKDIR
::if ($env:MS_LNK_ICON) { $lnk.IconLocation = $env:MS_LNK_ICON }
::$lnk.Save()
::#PS:SHORTCUT:END
