@echo off
rem ============================================================================
rem  uninstall_mysql_stack.cmd
rem  Desinstala componentes de MySQL instalados con install_mysql_stack.cmd:
rem  individualmente o todos, sin afectar a los no seleccionados (sin Administrador).
rem
rem  Uso: uninstall_mysql_stack.cmd [/COMPONENTS:lista] [/YES] [/KEEPDATA] [/DRYRUN] [/ROOT:ruta]
rem   /COMPONENTS:  SRV WB NOTIF SRVLTS WB8 | ALL (por defecto) | LATEST | LTS
rem                 Separe con + o con coma entre comillas: "/COMPONENTS:SRV,WB8"
rem   /YES          No pide confirmacion.
rem   /KEEPDATA     Conserva los directorios de datos (bases de datos).
rem   /DRYRUN       Muestra lo que se haria sin modificar nada.
rem
rem  Por cada componente: detiene SUS procesos, elimina su acceso directo, lanzadores,
rem  carpeta y (servidores) su directorio de datos. Despues recalcula el PATH: si se
rem  desinstala el servidor mas reciente y queda el LTS, el LTS pasa a ser el primario.
rem  No toca otras instalaciones de MySQL, XAMPP ni WampServer.
rem  Codigos de salida: 0 OK | 1 cancelado | 20 ruta no segura | 40 error al eliminar | 50 seleccion
rem  Autor: Ingeniero Andres Felipe Gutierrez Rivera
rem ============================================================================
setlocal EnableExtensions DisableDelayedExpansion
set "MS_SELF=%~f0"
for %%I in ("%~dp0..\..") do set "PROJECT=%%~fI"
set "ALL_IDS=SRV WB NOTIF SRVLTS WB8"
set "SERVER_IDS=SRV SRVLTS"
set "YES=0" & set "KEEPDATA=0" & set "DRYRUN=0" & set "ROOT_ARG=" & set "COMPS="
set "DIE_CODE=" & set "DIE_MSG=" & set "CREATED_ROOT=0"

:parse_args
if "%~1"=="" goto :args_done
set "A=%~1"
if /I "%A%"=="/YES" set "YES=1"
if /I "%A%"=="/KEEPDATA" set "KEEPDATA=1"
if /I "%A%"=="/DRYRUN" set "DRYRUN=1"
if /I "%A:~0,12%"=="/COMPONENTS:" set "COMPS=%A:~12%"
if /I "%A:~0,6%"=="/ROOT:" set "ROOT_ARG=%A:~6%"
if not "%A:~0,1%"=="/" set "COMPS=%COMPS% %A%"
shift
goto :parse_args
:args_done

if not exist "%PROJECT%\config\stack.env" (echo   [ERROR] No se encuentra config\stack.env & exit /b 50)
call :load_env "%PROJECT%\config\stack.env"
if defined ROOT_ARG (set "ROOT=%ROOT_ARG%") else (set "ROOT=%STACK_ROOT_DEFAULT%")
if not defined ROOT set "ROOT=C:\Programs"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "BASE=%ROOT%\MySQL"
if exist "%BASE%\stack-manifest.env" (
  call :load_env "%BASE%\stack-manifest.env"
  if not defined ROOT_ARG if defined INSTALL_ROOT set "ROOT=%INSTALL_ROOT%"
)
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "BASE=%ROOT%\MySQL"
set "LAUNCH=%BASE%\launchers" & set "MANIFEST=%BASE%\stack-manifest.env"
call :migrate_v1

rem --- Proteccion: solo se elimina exactamente <raiz>\MySQL y nunca una unidad ---
if "%ROOT:~3%"=="" (echo   [ERROR] Ruta no segura para eliminar & exit /b 20)
if /I not "%BASE%"=="%ROOT%\MySQL" (echo   [ERROR] Ruta no segura para eliminar & exit /b 20)

if not defined COMPS set "COMPS=ALL"
set "COMPS=%COMPS:,= %"
set "COMPS=%COMPS:+= %"
set "COMPS=%COMPS:;= %"
for %%T in (%COMPS%) do call :select_token %%T
if defined DIE_CODE (echo   [ERROR] %DIE_MSG% & exit /b %DIE_CODE%)

set "PRESENT_COUNT=0" & set "PRESENT_TEXT=" & set "KEEP_TEXT=" & set "HAS_SERVER=0"
for %%C in (%ALL_IDS%) do call :detect %%C
if "%DRYRUN%"=="1" echo SIMULACION: no se modificara nada.
if %PRESENT_COUNT% EQU 0 (
  echo   [OK]    Nada que desinstalar entre los componentes seleccionados.
  exit /b 0
)
echo Se desinstalara:%PRESENT_TEXT%
if defined KEEP_TEXT echo   [OK]    Se conservaran sin cambios:%KEEP_TEXT%

if "%YES%"=="0" if "%DRYRUN%"=="0" (
  if "%KEEPDATA%"=="1" (echo   [AVISO] Los directorios de datos se conservaran.) else if "%HAS_SERVER%"=="1" (echo   [AVISO] Se eliminaran LAS BASES DE DATOS de los servidores seleccionados.)
  set "ANS="
  set /p "ANS=Escriba SI para continuar: "
)
if "%YES%"=="0" if "%DRYRUN%"=="0" if not "%ANS%"=="SI" (echo Cancelado. & exit /b 1)

echo.
echo == 1/5 Deteniendo procesos de los componentes seleccionados ==
for %%C in (%ALL_IDS%) do call :stop_comp %%C

echo.
echo == 2/5 Accesos directos y lanzadores ==
for %%C in (%ALL_IDS%) do call :remove_links %%C

echo.
echo == 3/5 Carpetas de los componentes ==
for %%C in (%ALL_IDS%) do call :remove_dirs %%C
if defined DIE_CODE (echo   [ERROR] %DIE_MSG% & exit /b %DIE_CODE%)

echo.
echo == 4/5 PATH y variables de usuario ==
if "%DRYRUN%"=="1" (
  echo           El servidor primario del PATH pasaria a otro instalado, o se limpiaria PATH y MYSQL_TCP_PORT.
) else (
  call :update_path
)

echo.
echo == 5/5 Carpeta base ==
set "REMAINING=0"
for %%C in (%ALL_IDS%) do call :count_remaining %%C
if "%DRYRUN%"=="1" (
  echo           Se eliminaria %BASE% solo si no quedan componentes.
  goto :done
)
if %REMAINING% GTR 0 (
  echo   [OK]    La carpeta %BASE% se conserva - quedan componentes instalados.
  goto :done
)
if not exist "%BASE%" goto :done
if "%KEEPDATA%"=="1" (
  for /d %%D in ("%BASE%\*") do if /I not "%%~nxD"=="%SRV_DATADIR%" if /I not "%%~nxD"=="%SRVLTS_DATADIR%" rd /s /q "%%D"
  del /q "%BASE%\*" >nul 2>&1
  echo   [OK]    Eliminado todo salvo los directorios de datos en %BASE%
  goto :done
)
rd /s /q "%BASE%"
if exist "%BASE%" (echo   [ERROR] No se pudo eliminar por completo - hay archivos en uso & exit /b 40)
echo   [OK]    Eliminado: %BASE%
if "%CREATED_ROOT%"=="1" (
  rd "%ROOT%" >nul 2>&1
  if exist "%ROOT%" (echo   [OK]    La carpeta %ROOT% se conserva - no esta vacia) else (echo   [OK]    Carpeta vacia eliminada: %ROOT%)
) else (
  echo   [OK]    La carpeta %ROOT% se conserva
)

:done
echo.
echo DESINSTALACION COMPLETADA
echo   La configuracion de usuario de Workbench y Notifier en %%APPDATA%% no se borra - puede ser compartida con otras instalaciones.
exit /b 0

rem ============================================================================
rem  SUBRUTINAS
rem ============================================================================
:fail
set "DIE_CODE=%~1"
set "DIE_MSG=%~2"
exit /b 1

:load_env
if not exist "%~1" exit /b 0
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~1") do set "%%A=%%B"
exit /b 0

:migrate_v1
if defined SRV_INSTALLED exit /b 0
if not defined PORT exit /b 0
set "SRV_INSTALLED=1"
set "SRV_PORT=%PORT%"
if defined XPORT set "SRV_XPORT=%XPORT%"
set "WB_INSTALLED=1"
set "NOTIF_INSTALLED=0"
if defined NOTIFIER set "NOTIF_INSTALLED=%NOTIFIER%"
set "PORT=" & set "XPORT=" & set "NOTIFIER="
exit /b 0

:mf_del
if not exist "%MANIFEST%" exit /b 0
findstr /V /B /C:"%~1=" "%MANIFEST%" > "%MANIFEST%.tmp"
move /y "%MANIFEST%.tmp" "%MANIFEST%" >nul
exit /b 0

:select_token
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

:load_comp
set "C_ID=%~1"
call set "C_LABEL=%%%~1_LABEL%%"
call set "C_KIND=%%%~1_KIND%%"
call set "C_DIR=%%%~1_DIR%%"
call set "C_DATADIR=%%%~1_DATADIR%%"
call set "C_SUFFIX=%%%~1_SUFFIX%%"
call set "C_LINK=%%%~1_LINK%%"
if /I "%C_DATADIR%"=="NONE" set "C_DATADIR="
if /I "%C_SUFFIX%"=="NONE" set "C_SUFFIX="
set "C_PATH=%BASE%\%C_DIR%"
set "C_DATA="
if defined C_DATADIR set "C_DATA=%BASE%\%C_DATADIR%"
exit /b 0

:detect
rem Marca PRESENT_<ID> si el componente seleccionado esta instalado; si no esta seleccionado pero si instalado, lo anota como conservado
call set "S=%%SEL_%~1%%"
call set "I=%%%~1_INSTALLED%%"
call set "D=%%%~1_DIR%%"
call set "L=%%%~1_LABEL%%"
call set "K=%%%~1_KIND%%"
set "HAVE_DIR=0"
if defined D if exist "%BASE%\%D%\" set "HAVE_DIR=1"
if not "%S%"=="1" (
  if "%I%"=="1" set "KEEP_TEXT=%KEEP_TEXT% %~1"
  exit /b 0
)
if not "%I%"=="1" if "%HAVE_DIR%"=="0" (
  echo           %L%: no esta instalado ^(se omite^).
  exit /b 0
)
set "PRESENT_%~1=1"
set /a PRESENT_COUNT+=1
set "PRESENT_TEXT=%PRESENT_TEXT% %~1"
if /I "%K%"=="server" set "HAS_SERVER=1"
exit /b 0

:stop_comp
call set "P=%%PRESENT_%~1%%"
if not "%P%"=="1" exit /b 0
call :load_comp %~1
call set "PORT_N=%%%~1_PORT%%"
if "%DRYRUN%"=="1" (echo           Detendria los procesos de %C_LABEL% & exit /b 0)
if "%KEEPDATA%"=="1" if /I "%C_KIND%"=="server" if defined PORT_N if exist "%C_PATH%\bin\mysqladmin.exe" (
  echo           Apagado ordenado de %C_LABEL% - se solicitara la contrasena de root si la tiene
  "%C_PATH%\bin\mysqladmin.exe" -u root -p -h 127.0.0.1 -P %PORT_N% shutdown
  timeout /t 3 /nobreak >nul
)
set "MS_BASE=%C_PATH%" & set "MS_HELPER=STOPOWN"
call :ps_run
timeout /t 2 /nobreak >nul
echo   [OK]    %C_LABEL%: procesos detenidos
exit /b 0

:remove_links
call set "P=%%PRESENT_%~1%%"
if not "%P%"=="1" exit /b 0
call :load_comp %~1
set "NAMES=%C_LINK%"
rem nombres de la version 1 del proyecto
if "%~1"=="SRV" set "NAMES=%C_LINK%|MySQL Community Server"
if "%~1"=="WB" set "NAMES=%C_LINK%|MySQL Workbench"
if "%DRYRUN%"=="1" (echo           Eliminaria el acceso directo %C_LINK% & goto :links_launchers)
set "MS_LINKS=%NAMES%" & set "MS_HELPER=RMLNK"
call :ps_run
echo   [OK]    Acceso directo eliminado: %C_LINK%
:links_launchers
if /I not "%C_KIND%"=="server" exit /b 0
if "%DRYRUN%"=="1" (echo           Eliminaria los lanzadores de %C_LABEL% & exit /b 0)
del /q "%LAUNCH%\mysql-console%C_SUFFIX%.cmd" "%LAUNCH%\start-mysql-server%C_SUFFIX%.cmd" "%LAUNCH%\stop-mysql-server%C_SUFFIX%.cmd" >nul 2>&1
exit /b 0

:remove_dirs
call set "P=%%PRESENT_%~1%%"
if not "%P%"=="1" exit /b 0
if defined DIE_CODE exit /b 1
call :load_comp %~1
if not defined C_DIR (call :fail 20 "Configuracion invalida: %~1 no define su carpeta" & exit /b 1)
if "%DRYRUN%"=="1" (
  echo           Eliminaria %C_PATH%
  if /I "%C_KIND%"=="server" if "%KEEPDATA%"=="0" echo           Eliminaria %C_DATA%
  exit /b 0
)
if exist "%C_PATH%" (
  rd /s /q "%C_PATH%"
  if exist "%C_PATH%" (call :fail 40 "No se pudo eliminar %C_PATH% - hay archivos en uso" & exit /b 1)
  echo   [OK]    Eliminado: %C_PATH%
)
if /I "%C_KIND%"=="server" if "%KEEPDATA%"=="0" if defined C_DATA if exist "%C_DATA%" (
  rd /s /q "%C_DATA%"
  if exist "%C_DATA%" (call :fail 40 "No se pudo eliminar %C_DATA% - hay archivos en uso" & exit /b 1)
  echo   [OK]    Eliminado: %C_DATA%
)
if /I "%C_KIND%"=="server" if "%KEEPDATA%"=="1" echo   [OK]    Datos conservados: %C_DATA%
set "%~1_INSTALLED="
set "%~1_PORT="
set "%~1_XPORT="
call :mf_del %~1_INSTALLED
call :mf_del %~1_PORT
call :mf_del %~1_XPORT
exit /b 0

:count_remaining
call set "I=%%%~1_INSTALLED%%"
if "%I%"=="1" set /a REMAINING+=1
exit /b 0

:update_path
set "P_ID=" & set "P_BIN=" & set "P_PORT="
if "%SRV_INSTALLED%"=="1" (set "P_ID=SRV" & set "P_BIN=%BASE%\%SRV_DIR%\bin" & set "P_PORT=%SRV_PORT%")
if not defined P_ID if "%SRVLTS_INSTALLED%"=="1" (set "P_ID=SRVLTS" & set "P_BIN=%BASE%\%SRVLTS_DIR%\bin" & set "P_PORT=%SRVLTS_PORT%")
set "MS_ADD=%P_BIN%"
set "MS_PORT=%P_PORT%"
set "MS_REMOVE=%BASE%\%SRV_DIR%\bin;%BASE%\%SRVLTS_DIR%\bin"
set "MS_HELPER=PATHSET"
call :ps_run
exit /b 0

:ps_run
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:MS_SELF); $m=[regex]::Match($t,'(?s)#PS:'+$env:MS_HELPER+':BEGIN(.*?)#PS:'+$env:MS_HELPER+':END'); $c=[regex]::Replace($m.Groups[1].Value,'(?m)^::',''); & ([scriptblock]::Create($c))"
exit /b %ERRORLEVEL%

exit /b 0

::#PS:STOPOWN:BEGIN
::$base = $env:MS_BASE.TrimEnd('\') + '\'
::Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $e = ''; try { $e = [string]$_.Path } catch { }; if ($e.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } }
::#PS:STOPOWN:END

::#PS:RMLNK:BEGIN
::$d = [Environment]::GetFolderPath('Desktop')
::foreach ($n in $env:MS_LINKS -split '\|') { if ($n) { $l = Join-Path $d ($n + '.lnk'); if (Test-Path -LiteralPath $l) { Remove-Item -LiteralPath $l -Force } } }
::#PS:RMLNK:END

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
::} else { Write-Host '  [OK]    PATH de usuario sin carpetas del proyecto - no queda ningun servidor instalado.' -ForegroundColor Green }
::#PS:PATHSET:END
