#Requires -Version 5.1
<#
.SYNOPSIS
    Desinstala componentes de MySQL instalados con Install-MySQLStack.ps1: individualmente o
    todos, sin afectar a los que no se seleccionen (sin privilegios de Administrador).

.DESCRIPTION
    Por cada componente seleccionado e instalado: detiene SUS procesos, elimina su acceso directo,
    sus lanzadores, su carpeta y (servidores) su directorio de datos, y actualiza el manifiesto.
    Después recalcula el PATH de usuario: si se desinstala el servidor más reciente y queda el LTS,
    el LTS pasa a ser el servidor primario del PATH. Cuando no queda ningún componente se elimina
    <raíz>\MySQL completa (salvo los datos si se usa -KeepData).

    No toca otras instalaciones de MySQL, XAMPP ni WampServer, ni la configuración de usuario de
    Workbench en %APPDATA%.

.PARAMETER Components  SRV, WB, NOTIF, SRVLTS, WB8, ALL (por defecto), LATEST, LTS
.PARAMETER InstallRoot Raíz usada al instalar (por defecto C:\Programs o la del manifiesto).
.PARAMETER KeepData    Conserva los directorios de datos (bases de datos).
.PARAMETER Yes         No pide confirmación.
.PARAMETER DryRun      Muestra qué se haría sin modificar nada.

.NOTES
    Autor: Ingeniero Andrés Felipe Gutiérrez Rivera
    Códigos de salida: 0 OK | 1 cancelado | 20 ruta no segura | 40 error al eliminar
#>
[CmdletBinding()]
param(
    [string[]]$Components = @('ALL'),
    [string]$InstallRoot = '',
    [switch]$KeepData,
    [switch]$Yes,
    [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'MySQLStack.Common.ps1')

# Protección: solo se elimina exactamente <raíz>\MySQL, nunca una raíz de unidad ni otra carpeta
function Test-SafeRemovalTarget([string]$Target, [string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Target) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $t = $Target.TrimEnd('\'); $r = $Root.TrimEnd('\')
    if ($r.Length -le 3) { return $false }
    return ($t -ieq ($r + '\MySQL'))
}

# Protección para subcarpetas: debe ser <base>\<nombre> y el nombre debe estar en la lista permitida
function Test-SafeChildTarget([string]$Target, [string]$Base, [string[]]$AllowedNames) {
    if ([string]::IsNullOrWhiteSpace($Target) -or [string]::IsNullOrWhiteSpace($Base)) { return $false }
    $t = $Target.TrimEnd('\'); $b = $Base.TrimEnd('\')
    if (-not $t.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $name = $t.Substring($b.Length + 1)
    if ($name.Contains('\') -or $name -eq '') { return $false }
    return @($AllowedNames | Where-Object { $_ -ieq $name }).Count -gt 0
}

function Test-PathInside([string]$FilePath, [string]$Folder) {
    if ([string]::IsNullOrWhiteSpace($FilePath) -or [string]::IsNullOrWhiteSpace($Folder)) { return $false }
    return $FilePath.StartsWith(($Folder.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-Uninstall {
    $cfg = Get-StackConfig -ProjectRoot $script:ProjectRoot
    $root = if ($InstallRoot) { $InstallRoot.TrimEnd('\') } else { $cfg['STACK_ROOT_DEFAULT'].TrimEnd('\') }
    $paths = Get-StackPaths $root
    $manifest = Read-Manifest $paths.Manifest
    if ($manifest.ContainsKey('BASE') -and -not $InstallRoot) {
        $paths = Get-StackPaths (Split-Path -Parent $manifest['BASE']); $root = $paths.Root
    }
    $base = $paths.Base
    if (-not (Test-SafeRemovalTarget $base $root)) { Write-Bad "Ruta no segura para eliminar: $base"; exit 20 }

    $ids = @(Resolve-ComponentSelection $Components)
    $selected = @($ids | ForEach-Object { Get-Component -Cfg $cfg -Id $_ -Base $base })
    $present = @($selected | Where-Object { (Get-ComponentState $manifest $_.Id).Installed -or (Test-Path -LiteralPath $_.Dir) })
    $absent = @($selected | Where-Object { $_ -notin $present })

    Write-Host ("Selección: " + (($selected | ForEach-Object { $_.Label }) -join ' | ')) -ForegroundColor White
    foreach ($c in $absent) { Write-Note "$($c.Label): no está instalado (se omite)." }
    if ($DryRun) { Write-Host 'SIMULACIÓN: no se modificará nada.' -ForegroundColor White }
    if ($present.Count -eq 0) { Write-Ok 'Nada que desinstalar entre los componentes seleccionados.'; return }

    $keepers = @(Get-ComponentIds | Where-Object { $_ -notin $ids } | Where-Object { (Get-ComponentState $manifest $_).Installed })
    if ($keepers.Count -gt 0) { Write-Ok ("Se conservarán sin cambios: " + ($keepers -join ', ')) }

    if (-not $Yes -and -not $DryRun) {
        $withData = @($present | Where-Object { $_.IsServer })
        $list = ($present | ForEach-Object { $_.Label }) -join ', '
        $msg = if ($KeepData -or $withData.Count -eq 0) { "Se eliminarán: $list." } else { "Se eliminarán: $list INCLUYENDO LAS BASES DE DATOS de los servidores." }
        Write-Warn $msg
        if ((Read-Host 'Escriba SI para continuar') -cne 'SI') { Write-Host 'Cancelado.'; exit 1 }
    }

    $allowed = @(Get-ComponentIds | ForEach-Object { $cfg["${_}_DIR"]; $cfg["${_}_DATADIR"] } | Where-Object { $_ -and $_ -ne 'NONE' })

    Write-Stage '1/5 Deteniendo procesos de los componentes seleccionados'
    foreach ($c in $present) {
        $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $e = ''; try { $e = [string]$_.Path } catch { Write-Verbose 'Proceso sin ruta.' }; Test-PathInside $e $c.Dir })
        if ($procs.Count -eq 0) { Write-Ok "$($c.Label): sin procesos en ejecución."; continue }
        if ($DryRun) { $procs | ForEach-Object { Write-Note "Detendría $($c.Label): $($_.ProcessName) (PID $($_.Id))" }; continue }
        $port = (Get-ComponentState $manifest $c.Id).Port
        if ($KeepData -and $c.IsServer -and $port -gt 0) {
            Write-Note "Apagado ordenado de $($c.Label) (se solicitará la contraseña de root si la tiene)..."
            try { & (Join-Path $c.Dir 'bin\mysqladmin.exe') -u root -p -h 127.0.0.1 -P $port shutdown } catch { Write-Verbose 'Apagado ordenado fallido.' }
            Start-Sleep -Seconds 3
        }
        $procs | Where-Object { -not $_.HasExited } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
        Write-Ok "$($c.Label): procesos detenidos."
    }
    if (-not $DryRun) { Start-Sleep -Seconds 2 }

    Write-Stage '2/5 Accesos directos y lanzadores'
    $desktop = [Environment]::GetFolderPath('Desktop')
    foreach ($c in $present) {
        $names = @($c.Link)
        if ($c.Id -eq 'SRV' -or $c.Id -eq 'WB') {   # nombres de la versión 1 del proyecto
            $legacy = @($cfg['LEGACY_LINKS'] -split '\|')
            $names += $(if ($c.Id -eq 'SRV') { $legacy[0] } else { $legacy[1] })
        }
        foreach ($n in $names | Where-Object { $_ }) {
            $lnk = Join-Path $desktop "$n.lnk"
            if (Test-Path -LiteralPath $lnk) {
                if ($DryRun) { Write-Note "Eliminaría $lnk" } else { Remove-Item -LiteralPath $lnk -Force; Write-Ok "Acceso directo eliminado: $n" }
            }
        }
        if ($c.IsServer) {
            foreach ($n in 'mysql-console', 'start-mysql-server', 'stop-mysql-server') {
                $f = Join-Path $paths.Launchers ("$n$($c.Suffix).cmd")
                if (Test-Path -LiteralPath $f) { if ($DryRun) { Write-Note "Eliminaría $f" } else { Remove-Item -LiteralPath $f -Force } }
            }
        }
    }

    Write-Stage '3/5 Carpetas de los componentes'
    foreach ($c in $present) {
        $targets = @($c.Dir)
        if ($c.IsServer -and -not $KeepData) { $targets += $c.DataDir }
        foreach ($t in $targets | Where-Object { $_ }) {
            if (-not (Test-Path -LiteralPath $t)) { continue }
            if (-not (Test-SafeChildTarget $t $base $allowed)) { Write-Bad "Ruta no segura, no se elimina: $t"; exit 20 }
            if ($DryRun) { Write-Note "Eliminaría $t"; continue }
            try { Remove-Item -LiteralPath $t -Recurse -Force; Write-Ok "Eliminado: $t" }
            catch { Write-Bad "No se pudo eliminar $t (¿archivos en uso?): $($_.Exception.Message)"; exit 40 }
        }
        if ($KeepData -and $c.IsServer) { Write-Ok "Datos conservados: $($c.DataDir)" }
        if (-not $DryRun) { Clear-ComponentState $manifest $c.Id }
    }

    Write-Stage '4/5 PATH y variables de usuario'
    if ($DryRun) {
        $presentIds = @($present | ForEach-Object { $_.Id })
        $after = @(Get-ServerIds | Where-Object { (Get-ComponentState $manifest $_).Installed -and $_ -notin $presentIds })
        Write-Note ("El servidor primario del PATH pasaría a: " + $(if ($after.Count -gt 0) { $after[0] } else { '(ninguno: se limpia PATH y MYSQL_TCP_PORT)' }))
    } else {
        [void](Update-UserEnvironment -Cfg $cfg -Paths $paths -Manifest $manifest)
    }

    Write-Stage '5/5 Carpeta base'
    $remaining = @(Get-ComponentIds | Where-Object { (Get-ComponentState $manifest $_).Installed })
    if ($DryRun) { Write-Note $(if ($remaining.Count -eq 0 -and $keepers.Count -eq 0) { "Eliminaría $base si no quedan componentes." } else { "La carpeta $base se conserva (quedan componentes)." }) }
    elseif ($remaining.Count -gt 0) { Save-Manifest -Path $paths.Manifest -Manifest $manifest; Write-Ok "La carpeta $base se conserva (quedan: $($remaining -join ', '))." }
    elseif (Test-Path -LiteralPath $base) {
        $created = $manifest.ContainsKey('CREATED_ROOT') -and $manifest['CREATED_ROOT'] -eq '1'
        try {
            if ($KeepData) {
                $dataNames = @(Get-ServerIds | ForEach-Object { $cfg["${_}_DATADIR"] })   # los servidores siempre tienen DATADIR
                Get-ChildItem -LiteralPath $base -Force | Where-Object { $_.Name -notin $dataNames } | Remove-Item -Recurse -Force
                Write-Ok "Eliminado todo salvo los directorios de datos en $base"
            } else {
                Remove-Item -LiteralPath $base -Recurse -Force
                Write-Ok "Eliminado: $base"
                if ($created -and (Test-Path -LiteralPath $root) -and -not (Get-ChildItem -LiteralPath $root -Force | Select-Object -First 1)) {
                    Remove-Item -LiteralPath $root -Force; Write-Ok "Carpeta vacía eliminada: $root"
                } else { Write-Ok "La carpeta $root se conserva." }
            }
        } catch { Write-Bad "No se pudo eliminar por completo: $($_.Exception.Message)"; exit 40 }
    }

    Write-Host ''
    Write-Host 'DESINSTALACIÓN COMPLETADA' -ForegroundColor Green
    Write-Note 'La configuración de usuario de Workbench/Notifier en %APPDATA% no se borra (puede ser compartida con otras instalaciones); elimínela manualmente si lo desea.'
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-Uninstall; exit 0 }
    catch {
        $code = 40
        if ($_.Exception.Data -and $_.Exception.Data.Contains('Code')) { $code = [int]$_.Exception.Data['Code'] }
        Write-Bad $_.Exception.Message; exit $code
    }
}
