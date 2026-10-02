@echo off
rem ============================================================================
rem  enable_script_execution.cmd
rem  Habilita la ejecucion de scripts descargados de Internet dentro de un ZIP
rem  para la cuenta actual, SIN privilegios de Administrador.
rem    1) Set-ExecutionPolicy RemoteSigned en el ambito CurrentUser.
rem    2) Unblock-File sobre todo el proyecto (retira la marca Zone.Identifier).
rem  Uso: doble clic o  src\cmd\enable_script_execution.cmd
rem  Autor: Ingeniero Andres Felipe Gutierrez Rivera
rem ============================================================================
setlocal EnableExtensions DisableDelayedExpansion
for %%I in ("%~dp0..\..") do set "PROJECT=%%~fI"
echo Proyecto: %PROJECT%
echo.
echo Politica de ejecucion ANTES:
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ExecutionPolicy -List | Format-Table -AutoSize | Out-String | Write-Host"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force; Write-Host '[OK] CurrentUser = RemoteSigned' -ForegroundColor Green } catch { Write-Host ('[AVISO] ' + $_.Exception.Message) -ForegroundColor Yellow }; $f = Get-ChildItem -LiteralPath '%PROJECT%' -Recurse -File -Force; $f | Unblock-File; Write-Host ('[OK] ' + $f.Count + ' archivos desbloqueados') -ForegroundColor Green"
echo.
echo Politica de ejecucion AHORA:
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ExecutionPolicy -List | Format-Table -AutoSize | Out-String | Write-Host"
exit /b 0
