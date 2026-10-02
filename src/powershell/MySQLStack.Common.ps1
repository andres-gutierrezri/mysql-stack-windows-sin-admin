<#
.SYNOPSIS
    Biblioteca común (se carga con "dot-source") de los scripts PowerShell del proyecto.

.DESCRIPTION
    Contiene lo que comparten el instalador, el desinstalador y el menú:
      - salida por consola y errores con código de salida,
      - lectura de config\stack.env y definición de COMPONENTES,
      - resolución de la selección (SRV, WB, NOTIF, SRVLTS, WB8, ALL, LATEST, LTS),
      - manifiesto de estado por componente (con migración del formato v1),
      - PATH de usuario: el servidor se coloca ANTES de la entrada de XAMPP MySQL.

    No ejecuta nada por sí misma. Autor: Ingeniero Andrés Felipe Gutiérrez Rivera
#>

#region Salida por consola ------------------------------------------------------
function Write-Stage([string]$Text) { Write-Host ''; Write-Host "== $Text ==" -ForegroundColor Cyan }
function Write-Ok([string]$Text)    { Write-Host "  [OK]    $Text" -ForegroundColor Green }
function Write-Warn([string]$Text)  { Write-Host "  [AVISO] $Text" -ForegroundColor Yellow }
function Write-Bad([string]$Text)   { Write-Host "  [ERROR] $Text" -ForegroundColor Red }
function Write-Note([string]$Text)  { Write-Host "          $Text" -ForegroundColor Gray }

function New-StackError([int]$Code, [string]$Message) {
    $ex = New-Object System.InvalidOperationException($Message)
    $ex.Data['Code'] = $Code
    return $ex
}
#endregion

#region Configuración y componentes ----------------------------------------------
function Read-EnvFile {
    param([Parameter(Mandatory)][string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $text = $line.Trim()
        if ($text.Length -eq 0 -or $text.StartsWith('#')) { continue }
        $idx = $text.IndexOf('=')
        if ($idx -lt 1) { continue }
        $values[$text.Substring(0, $idx).Trim()] = $text.Substring($idx + 1).Trim()
    }
    return $values
}

# Orden canónico de instalación: servidores antes que sus clientes no es necesario, pero el orden es estable
function Get-ComponentIds { return @('SRV', 'WB', 'NOTIF', 'SRVLTS', 'WB8') }
function Get-ServerIds    { return @('SRV', 'SRVLTS') }

function Get-StackConfig {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $cfg = Read-EnvFile (Join-Path $ProjectRoot 'config\stack.env')
    $override = Read-EnvFile (Join-Path $ProjectRoot '.env')
    foreach ($k in @($override.Keys)) { $cfg[$k] = $override[$k] }
    $required = @('STACK_ROOT_DEFAULT', 'DEFAULT_PORT', 'DEFAULT_XPORT', 'FALLBACK_ROOT_PASSWORD')
    foreach ($id in Get-ComponentIds) {
        foreach ($f in 'LABEL', 'VERSION', 'KIND', 'URL', 'MD5', 'FILE', 'DIR', 'LINK', 'NEED_GB') { $required += "${id}_$f" }
    }
    foreach ($id in Get-ServerIds) { foreach ($f in 'FOLDER', 'DATADIR', 'SUFFIX') { $required += "${id}_$f" } }
    foreach ($k in $required) {
        if (-not $cfg.ContainsKey($k)) { throw (New-StackError 50 "Falta la clave '$k' en config\stack.env") }
    }
    return $cfg
}

# Une rutas de Windows por concatenación (sin validar la unidad: permite probar la lógica en cualquier SO)
function Join-WinPath([string]$Parent, [string]$Child) { return ($Parent.TrimEnd('\') + '\' + $Child) }

function Test-SafeInstallRoot([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    # Solo letras, dígitos, _ - . y \ : sin espacios ni & ^ % ! que rompen CMD
    if ($Path -notmatch '^[A-Za-z]:\\[A-Za-z0-9_\-\.\\]*$') { return $false }
    return ($Path.TrimEnd('\').Length -gt 3)   # nunca la raíz de una unidad
}

function Get-StackPaths([string]$Root) {
    $base = Join-WinPath $Root 'MySQL'
    return [ordered]@{
        Root      = $Root
        Base      = $base
        Launchers = (Join-WinPath $base 'launchers')
        Cache     = (Join-WinPath $base '_cache')
        Temp      = (Join-WinPath $base '_tmp')
        Logs      = (Join-WinPath $base 'logs')
        Manifest  = (Join-WinPath $base 'stack-manifest.env')
    }
}

# Devuelve el objeto de un componente con todas sus rutas ya resueltas
function Get-Component {
    param([hashtable]$Cfg, [string]$Id, [string]$Base)
    $none = { param($v) if ($v -eq 'NONE') { '' } else { $v } }   # centinela de valores vacíos
    $dataName = & $none $Cfg["${Id}_DATADIR"]
    return [pscustomobject]@{
        Id       = $Id
        Label    = $Cfg["${Id}_LABEL"]
        Version  = $Cfg["${Id}_VERSION"]
        Kind     = $Cfg["${Id}_KIND"]
        Url      = $Cfg["${Id}_URL"]
        Md5      = $Cfg["${Id}_MD5"]
        Folder   = (& $none $Cfg["${Id}_FOLDER"])
        File     = $Cfg["${Id}_FILE"]
        DirName  = $Cfg["${Id}_DIR"]
        Dir      = (Join-WinPath $Base $Cfg["${Id}_DIR"])
        DataName = $dataName
        DataDir  = $(if ($dataName) { Join-WinPath $Base $dataName } else { '' })
        Suffix   = (& $none $Cfg["${Id}_SUFFIX"])
        Link     = $Cfg["${Id}_LINK"]
        NeedGb   = [double]$Cfg["${Id}_NEED_GB"]
        IsServer = ($Cfg["${Id}_KIND"] -eq 'server')
    }
}

# Traduce la selección del usuario a una lista ordenada y sin duplicados de identificadores.
# Acepta: SRV WB NOTIF SRVLTS WB8, ALL/TODO/T, LATEST/ULTIMA/U, LTS/L y los números 1-5 del menú.
function Resolve-ComponentSelection {
    param([string[]]$Names)
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    $numbers = @{ '1' = 'SRV'; '2' = 'WB'; '3' = 'NOTIF'; '4' = 'SRVLTS'; '5' = 'WB8' }
    $tokens = @($Names | ForEach-Object { "$_" -split '[,;\s]+' } | Where-Object { $_ -ne '' })
    foreach ($raw in $tokens) {
        $t = $raw.Trim().ToUpperInvariant()
        switch -Regex ($t) {
            '^(ALL|TODO|TODOS|T)$'       { foreach ($i in Get-ComponentIds) { [void]$set.Add($i) } }
            '^(LATEST|ULTIMA|ÚLTIMA|U)$' { foreach ($i in 'SRV', 'WB', 'NOTIF') { [void]$set.Add($i) } }
            '^(LTS|L)$'                  { foreach ($i in 'SRVLTS', 'WB8') { [void]$set.Add($i) } }
            '^(SRV|WB|NOTIF|SRVLTS|WB8)$' { [void]$set.Add($t) }
            '^[1-5]$'                    { [void]$set.Add($numbers[$t]) }
            default { throw (New-StackError 50 "Componente desconocido: '$raw'. Use SRV, WB, NOTIF, SRVLTS, WB8, ALL, LATEST o LTS.") }
        }
    }
    return @(Get-ComponentIds | Where-Object { $set.Contains($_) })
}
#endregion

#region Manifiesto de estado (stack-manifest.env) -----------------------------------
# Claves: INSTALL_ROOT, BASE, CREATED_ROOT y, por componente, <ID>_INSTALLED, <ID>_PORT, <ID>_XPORT
function ConvertFrom-LegacyManifest([hashtable]$M) {
    # Formato v1 (un solo servidor): PORT, XPORT, NOTIFIER -> claves por componente
    if (-not $M.ContainsKey('SRV_INSTALLED') -and $M.ContainsKey('PORT')) {
        $M['SRV_INSTALLED'] = '1'; $M['SRV_PORT'] = $M['PORT']
        $M['SRV_XPORT'] = $(if ($M.ContainsKey('XPORT')) { $M['XPORT'] } else { '' })
        $M['WB_INSTALLED'] = '1'
        $M['NOTIF_INSTALLED'] = $(if ($M.ContainsKey('NOTIFIER')) { $M['NOTIFIER'] } else { '0' })
        foreach ($k in 'PORT', 'XPORT', 'NOTIFIER', 'PATH_ENTRY', 'SERVER_VERSION', 'WORKBENCH_VERSION', 'SHORTCUTS', 'INSTALLED_AT') { [void]$M.Remove($k) }
    }
    return $M
}

function Read-Manifest([string]$Path) { return (ConvertFrom-LegacyManifest (Read-EnvFile $Path)) }

function Save-Manifest {
    param([string]$Path, [hashtable]$Manifest)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $lines = @($Manifest.Keys | Sort-Object | ForEach-Object { "$_=$($Manifest[$_])" })
    Set-Content -LiteralPath $Path -Value $lines -Encoding Ascii
}

function Get-ComponentState([hashtable]$Manifest, [string]$Id) {
    return [pscustomobject]@{
        Installed = ($Manifest.ContainsKey("${Id}_INSTALLED") -and $Manifest["${Id}_INSTALLED"] -eq '1')
        Port      = $(if ($Manifest.ContainsKey("${Id}_PORT") -and $Manifest["${Id}_PORT"]) { [int]$Manifest["${Id}_PORT"] } else { 0 })
        XPort     = $(if ($Manifest.ContainsKey("${Id}_XPORT") -and $Manifest["${Id}_XPORT"]) { [int]$Manifest["${Id}_XPORT"] } else { 0 })
    }
}

function Set-ComponentInstalled {
    param([hashtable]$Manifest, [string]$Id, [int]$Port = 0, [int]$XPort = 0)
    $Manifest["${Id}_INSTALLED"] = '1'
    if ($Port -gt 0) { $Manifest["${Id}_PORT"] = "$Port" }
    if ($XPort -gt 0) { $Manifest["${Id}_XPORT"] = "$XPort" }
}

function Clear-ComponentState([hashtable]$Manifest, [string]$Id) {
    foreach ($k in "${Id}_INSTALLED", "${Id}_PORT", "${Id}_XPORT") { [void]$Manifest.Remove($k) }
}

# Servidor "primario": el que queda en el PATH. La versión más reciente tiene prioridad sobre la LTS.
function Get-PrimaryServerId([hashtable]$Manifest) {
    foreach ($id in 'SRV', 'SRVLTS') { if ((Get-ComponentState $Manifest $id).Installed) { return $id } }
    return ''
}
#endregion

#region PATH de usuario (prioridad sobre XAMPP) -------------------------------------------
function Get-XamppPathPattern { return '(?i)[\\/]xampp[\\/]mysql\s*[\\/]bin[\\/]?\s*$' }

function Test-PathHasPattern([string]$PathValue, [string]$Pattern) {
    foreach ($p in @($PathValue -split ';')) { if ($p.Trim() -match $Pattern) { return $true } }
    return $false
}

function Merge-PathEntry([string]$PathValue, [string]$Entry) {
    $parts = @($PathValue -split ';' | Where-Object { $_.Trim() -ne '' })
    $norm = $Entry.TrimEnd('\')
    foreach ($p in $parts) { if ($p.TrimEnd('\') -ieq $norm) { return ($parts -join ';') } }
    return (($parts + $Entry) -join ';')
}

function Remove-PathEntry([string]$PathValue, [string]$Entry) {
    $norm = $Entry.TrimEnd('\')
    $kept = @($PathValue -split ';' | Where-Object { $_.Trim() -ne '' -and $_.TrimEnd('\') -ine $norm })
    return ($kept -join ';')
}

<#
    Coloca $Entry en el PATH respetando la prioridad:
      1. Elimina $Entry y todas las $RemoveEntries (idempotente, sin distinguir mayúsculas ni '\' final).
      2. Si $BeforePattern coincide con alguna entrada, inserta $Entry JUSTO ANTES de la primera coincidencia.
      3. Si no hay coincidencia, la agrega al final.
    Con $Entry vacío solo elimina (uso del desinstalador).
#>
function Set-PathPriority {
    param([string]$PathValue, [string]$Entry = '', [string[]]$RemoveEntries = @(), [string]$BeforePattern = '')
    $drop = @($RemoveEntries) + @($Entry) | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.TrimEnd('\') }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($PathValue -split ';')) {
        if ($p.Trim() -eq '') { continue }
        $isOurs = $false
        foreach ($d in $drop) { if ($p.TrimEnd('\') -ieq $d) { $isOurs = $true; break } }
        if (-not $isOurs) { $parts.Add($p) }
    }
    if ($Entry -and $Entry.Trim() -ne '') {
        $at = -1
        if ($BeforePattern) { for ($i = 0; $i -lt $parts.Count; $i++) { if ($parts[$i].Trim() -match $BeforePattern) { $at = $i; break } } }
        if ($at -ge 0) { $parts.Insert($at, $Entry) } else { $parts.Add($Entry) }
    }
    return ($parts -join ';')
}

function Send-EnvironmentChange {
    try {
        if (-not ('MySqlStack.NativeMethods' -as [type])) {
            Add-Type -Namespace MySqlStack -Name NativeMethods -MemberDefinition '[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
        }
        $res = [UIntPtr]::Zero
        [void][MySqlStack.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$res)
    } catch { Write-Verbose 'No se pudo difundir el cambio de entorno.' }
}

function Get-UserPathRaw {
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $false)
    try { return [string]$k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    finally { $k.Close() }
}

function Set-UserPathRaw([string]$Value) {
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try { $k.SetValue('Path', $Value, [Microsoft.Win32.RegistryValueKind]::ExpandString) } finally { $k.Close() }
    Send-EnvironmentChange
}

# PATH del equipo (solo lectura): Windows lo antepone al del usuario, por eso no se puede "ganar" a XAMPP si está ahí
function Get-MachinePathRaw {
    try {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $false)
        if ($null -eq $k) { return '' }
        try { return [string]$k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } finally { $k.Close() }
    } catch { return '' }
}

<#
    Recalcula el PATH y MYSQL_TCP_PORT de usuario a partir del manifiesto:
      - quita las carpetas bin de TODOS los servidores del proyecto,
      - agrega la del servidor primario (SRV si está instalado; si no, SRVLTS),
      - si ya existe la entrada de XAMPP MySQL, la inserta ANTES de ella.
#>
function Update-UserEnvironment {
    param([hashtable]$Cfg, $Paths, [hashtable]$Manifest)
    $managed = @(Get-ServerIds | ForEach-Object { Join-WinPath (Join-WinPath $Paths.Base $Cfg["${_}_DIR"]) 'bin' })
    $primaryId = Get-PrimaryServerId $Manifest
    $raw = Get-UserPathRaw
    $pattern = Get-XamppPathPattern
    $xamppInUser = Test-PathHasPattern $raw $pattern

    if ($primaryId) {
        $bin = Join-WinPath (Join-WinPath $Paths.Base $Cfg["${primaryId}_DIR"]) 'bin'
        $new = Set-PathPriority -PathValue $raw -Entry $bin -RemoveEntries $managed -BeforePattern $pattern
        $port = (Get-ComponentState $Manifest $primaryId).Port
    } else {
        $bin = ''
        $new = Set-PathPriority -PathValue $raw -Entry '' -RemoveEntries $managed
        $port = 0
    }
    if ($new -ne $raw) { Set-UserPathRaw $new }

    if ($port -gt 0) { [Environment]::SetEnvironmentVariable('MYSQL_TCP_PORT', "$port", 'User'); $env:MYSQL_TCP_PORT = "$port" }
    else { [Environment]::SetEnvironmentVariable('MYSQL_TCP_PORT', $null, 'User'); $env:MYSQL_TCP_PORT = $null }
    if ($bin) { $env:Path = Merge-PathEntry $env:Path $bin }

    if ($bin) {
        if ($xamppInUser) { Write-Ok "PATH de usuario: $bin se colocó ANTES de la entrada de XAMPP MySQL." }
        else { Write-Ok "PATH de usuario += $bin (no hay entrada de XAMPP MySQL en el PATH de usuario)." }
        Write-Note "MYSQL_TCP_PORT=$port (servidor primario: $primaryId)"
    } else { Write-Ok 'PATH de usuario sin carpetas del proyecto (no queda ningún servidor instalado).' }

    if ($bin -and (Test-PathHasPattern (Get-MachinePathRaw) $pattern)) {
        Write-Warn 'XAMPP MySQL está en el PATH del EQUIPO, que Windows evalúa antes que el del usuario: "mysql" seguirá resolviendo a XAMPP.'
        Write-Note 'Sin Administrador no se puede cambiar. Use los lanzadores del escritorio o la ruta completa al mysql.exe de este proyecto.'
    }
    return [pscustomobject]@{ Primary = $primaryId; Bin = $bin; Port = $port; XamppInUserPath = $xamppInUser }
}
#endregion
