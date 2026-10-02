#Requires -Version 5.1
<#
.SYNOPSIS
    Menú para instalar y desinstalar, individualmente o en conjunto, los componentes de MySQL.

.DESCRIPTION
    Muestra el estado actual (lee el manifiesto) y delega el trabajo en Install-MySQLStack.ps1 y
    Uninstall-MySQLStack.ps1, que siguen siendo independientes. Como cada componente tiene su propia
    carpeta, datos, puerto, lanzadores y acceso directo, instalar o desinstalar uno no afecta a los demás.

    Selección de componentes (separe con comas): números 1-5, nombres (SRV, WB, NOTIF, SRVLTS, WB8)
    o atajos: T = todo | U = última versión (1,2,3) | L = LTS (4,5).

.PARAMETER Action      Install | Uninstall | Status | FixPath. Vacío = menú interactivo.
.PARAMETER Components  Selección no interactiva (con -Action).
.PARAMETER DryRun / Force / KeepData / Yes / BlankPassword / NoPrompt / Port / InstallRoot
               Se transmiten a los scripts de instalación o desinstalación que correspondan.

.EXAMPLE
    .\Show-MySQLStackMenu.ps1
    .\Show-MySQLStackMenu.ps1 -Action Install -Components SRVLTS,WB8
    .\Show-MySQLStackMenu.ps1 -Action Uninstall -Components ALL -Yes

.NOTES
    Autor: Ingeniero Andrés Felipe Gutiérrez Rivera
#>
[CmdletBinding()]
param(
    [ValidateSet('', 'Install', 'Uninstall', 'Status', 'FixPath')][string]$Action = '',
    [string[]]$Components = @(),
    [string]$InstallRoot = '',
    [ValidateRange(0, 65535)][int]$Port = 0,
    [switch]$BlankPassword,
    [switch]$NoPrompt,
    [switch]$KeepData,
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'MySQLStack.Common.ps1')

function Get-StackSnapshot {
    param([hashtable]$Cfg, [string]$Root)
    $paths = Get-StackPaths $Root
    $manifest = Read-Manifest $paths.Manifest
    $listening = @()
    try { $listening = @([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | ForEach-Object { $_.Port }) } catch { Write-Verbose 'No se pudo leer los puertos.' }
    $rows = foreach ($id in Get-ComponentIds) {
        $c = Get-Component -Cfg $Cfg -Id $id -Base $paths.Base
        $s = Get-ComponentState $manifest $id
        [pscustomobject]@{
            Id = $id; Label = $c.Label; Installed = $s.Installed; IsServer = $c.IsServer; Port = $s.Port; Dir = $c.Dir
            Running = ($c.IsServer -and $s.Installed -and $s.Port -gt 0 -and ($listening -contains $s.Port))
        }
    }
    return [pscustomobject]@{ Paths = $paths; Manifest = $manifest; Rows = @($rows) }
}

function Show-Status($Snapshot) {
    Write-Host ''
    Write-Host 'Estado de los componentes' -ForegroundColor Cyan
    $n = 0
    foreach ($r in $Snapshot.Rows) {
        $n++
        $mark = if ($r.Installed) { '[X]' } else { '[ ]' }
        $extra = ''
        if ($r.IsServer -and $r.Installed) { $extra = "  puerto $($r.Port)  " + $(if ($r.Running) { '(en ejecución)' } else { '(detenido)' }) }
        $color = if ($r.Installed) { 'Green' } else { 'Gray' }
        Write-Host ("  {0}) {1} {2}{3}" -f $n, $mark, $r.Label, $extra) -ForegroundColor $color
    }
    $prim = Get-PrimaryServerId $Snapshot.Manifest
    Write-Host $(if ($prim) { "  Servidor primario del PATH: $prim" } else { '  Servidor primario del PATH: (ninguno)' }) -ForegroundColor Gray
}

function Read-ComponentChoice([string]$Verb) {
    Write-Host ''
    Write-Host "Componentes a $Verb (separe con comas):" -ForegroundColor White
    Write-Host '  1 = Servidor 26.7.0   2 = Workbench 26.7.0   3 = Notifier 1.1.8'
    Write-Host '  4 = Servidor 9.7.2 LTS   5 = Workbench 8.0.47'
    Write-Host '  U = última versión (1,2,3)   L = LTS (4,5)   T = TODO   0 = volver'
    while ($true) {
        $in = Read-Host 'Selección'
        if ([string]::IsNullOrWhiteSpace($in) -or $in.Trim() -eq '0') { return @() }
        try { return @(Resolve-ComponentSelection @($in)) }
        catch { Write-Warn 'Selección no válida. Ejemplos: 1   |   1,3   |   U   |   T'; }
    }
}

function Invoke-Child {
    param([string]$ScriptName, [string[]]$Ids, [switch]$IsUninstall)
    $args2 = @{ Components = $Ids }
    if ($InstallRoot) { $args2.InstallRoot = $InstallRoot }
    if ($DryRun) { $args2.DryRun = $true }
    if ($IsUninstall) { if ($KeepData) { $args2.KeepData = $true }; if ($Yes) { $args2.Yes = $true } }
    else {
        if ($Port -gt 0) { $args2.Port = $Port }
        if ($BlankPassword) { $args2.BlankPassword = $true }
        if ($NoPrompt) { $args2.NoPrompt = $true }
        if ($Force) { $args2.Force = $true }
    }
    $global:LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot $ScriptName) @args2 | Out-Host
    return [int]$LASTEXITCODE
}

function Invoke-Menu {
    $cfg = Get-StackConfig -ProjectRoot $script:ProjectRoot
    $root = if ($InstallRoot) { $InstallRoot.TrimEnd('\') } else { $cfg['STACK_ROOT_DEFAULT'].TrimEnd('\') }
    $m0 = Read-Manifest (Get-StackPaths $root).Manifest
    if ($m0.ContainsKey('BASE') -and -not $InstallRoot) { $root = Split-Path -Parent $m0['BASE'] }

    if ($Action) {
        switch ($Action) {
            'Status'  { Show-Status (Get-StackSnapshot $cfg $root); return 0 }
            'FixPath' {
                $a = @{ FixPathOnly = $true }; if ($InstallRoot) { $a.InstallRoot = $InstallRoot }
                $global:LASTEXITCODE = 0; & (Join-Path $PSScriptRoot 'Install-MySQLStack.ps1') @a | Out-Host; return [int]$LASTEXITCODE
            }
            'Install'   { $ids = @(Resolve-ComponentSelection $(if ($Components.Count -gt 0) { $Components } else { @('LATEST') })); return (Invoke-Child 'Install-MySQLStack.ps1' $ids) }
            'Uninstall' { $ids = @(Resolve-ComponentSelection $(if ($Components.Count -gt 0) { $Components } else { @('ALL') })); return (Invoke-Child 'Uninstall-MySQLStack.ps1' $ids -IsUninstall) }
        }
    }

    while ($true) {
        Write-Host ''
        Write-Host '=== MySQL Stack para Windows 11 (sin Administrador) ===' -ForegroundColor White
        Show-Status (Get-StackSnapshot $cfg $root)
        Write-Host ''
        Write-Host '  1) Instalar        2) Desinstalar        3) Reordenar PATH (XAMPP)        0) Salir'
        $op = (Read-Host 'Opción').Trim()
        switch ($op) {
            '1' {
                $ids = Read-ComponentChoice 'INSTALAR'
                if ($ids.Count -gt 0) { $rc = Invoke-Child 'Install-MySQLStack.ps1' $ids; Write-Host "Código de salida: $rc" -ForegroundColor Gray; [void](Read-Host 'ENTER para continuar') }
            }
            '2' {
                $ids = Read-ComponentChoice 'DESINSTALAR'
                if ($ids.Count -gt 0) { $rc = Invoke-Child 'Uninstall-MySQLStack.ps1' $ids -IsUninstall; Write-Host "Código de salida: $rc" -ForegroundColor Gray; [void](Read-Host 'ENTER para continuar') }
            }
            '3' {
                $a = @{ FixPathOnly = $true }; if ($InstallRoot) { $a.InstallRoot = $InstallRoot }
                & (Join-Path $PSScriptRoot 'Install-MySQLStack.ps1') @a | Out-Host; [void](Read-Host 'ENTER para continuar')
            }
            '0' { return 0 }
            default { Write-Warn 'Opción no válida.' }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { exit (Invoke-Menu) }
    catch {
        $code = 1
        if ($_.Exception.Data -and $_.Exception.Data.Contains('Code')) { $code = [int]$_.Exception.Data['Code'] }
        Write-Bad $_.Exception.Message; exit $code
    }
}
