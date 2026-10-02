#Requires -Version 5.1
<#
.SYNOPSIS
    Habilita la ejecución de scripts descargados de Internet dentro de un comprimido
    (ZIP) para la cuenta actual, SIN privilegios de Administrador.

.DESCRIPTION
    1. Establece la política de ejecución en RemoteSigned para el ámbito CurrentUser.
    2. Retira la marca de origen web (Zone.Identifier) de todos los archivos del proyecto
       con Unblock-File. Windows etiqueta los archivos extraídos de un ZIP descargado;
       sin este paso, RemoteSigned los bloquearía por no estar firmados.

    Úselo ANTES del instalador si PowerShell rechaza ejecutar Install-MySQLStack.ps1
    ("el archivo no está firmado digitalmente"). Alternativa equivalente en CMD:
        src\cmd\enable_script_execution.cmd

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\src\powershell\Enable-ScriptExecution.ps1

.NOTES
    Autor: Ingeniero Andrés Felipe Gutiérrez Rivera
    Si una directiva de grupo (MachinePolicy/UserPolicy) fija la política, CurrentUser no prevalece.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Write-Host 'Política de ejecución antes del cambio:' -ForegroundColor Cyan
Get-ExecutionPolicy -List | Format-Table -AutoSize | Out-String | Write-Host

try {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Host '[OK] CurrentUser = RemoteSigned' -ForegroundColor Green
} catch {
    Write-Host "[AVISO] No se pudo cambiar la política: $($_.Exception.Message)" -ForegroundColor Yellow
}

$files = Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Force
$files | Unblock-File
Write-Host "[OK] $($files.Count) archivos desbloqueados en $projectRoot" -ForegroundColor Green

Write-Host 'Política efectiva ahora:' -ForegroundColor Cyan
Get-ExecutionPolicy -List | Format-Table -AutoSize | Out-String | Write-Host
exit 0
