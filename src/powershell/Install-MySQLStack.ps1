#Requires -Version 5.1
<#
.SYNOPSIS
    Instala componentes de MySQL en Windows 11 desde una cuenta local SIN privilegios de
    Administrador: individualmente o en conjunto, y sin conflictos entre sí.

.DESCRIPTION
    COMPONENTES (-Components):
      SRV     MySQL Community Server 26.7.0 (la más reciente)    -> <raíz>\MySQL\server
      WB      MySQL Workbench 26.7.0 (la más reciente)           -> <raíz>\MySQL\workbench
      NOTIF   MySQL Notifier 1.1.8 (fuera de ciclo de vida)      -> <raíz>\MySQL\notifier
      SRVLTS  MySQL Community Server 9.7.2 LTS                   -> <raíz>\MySQL\server-9.7-lts
      WB8     MySQL Workbench 8.0.47                             -> <raíz>\MySQL\workbench-8.0.47
    GRUPOS: ALL (todo) | LATEST (SRV,WB,NOTIF; valor por defecto) | LTS (SRVLTS,WB8)

    Cada componente usa su propia carpeta, su propio directorio de datos, su propio puerto
    y sus propios lanzadores y accesos directos; por eso conviven sin conflictos.

    Etapas: 1 habilitar scripts · 2 requisitos · 3 MySQL previo · 4 XAMPP/WampServer · 5 puertos ·
            6 carpeta · 7 descarga e instalación · 8 configuración e inicio · 9 contraseña de root ·
            10 PATH (antes de XAMPP), lanzadores y accesos directos.

    Los servidores se ejecutan como PROCESO DE USUARIO (no como servicio de Windows), porque
    registrar un servicio exige privilegios de Administrador.

.PARAMETER Components   Lista separada por comas. Ej.: SRV,WB8  |  ALL  |  LTS
.PARAMETER InstallRoot  Carpeta raíz. Por defecto C:\Programs (se crea la subcarpeta MySQL).
.PARAMETER Port         Puerto deseado para el PRIMER servidor de la ejecución. 0 = automático.
.PARAMETER BlankPassword Deja la contraseña de root en blanco sin preguntar.
.PARAMETER NoPrompt     No interactivo: contraseña de respaldo (1234567) salvo -BlankPassword.
.PARAMETER SkipNotifier Excluye MySQL Notifier de la selección.
.PARAMETER FixPathOnly  Solo recalcula el PATH de usuario (p. ej. si instaló XAMPP después).
.PARAMETER DryRun       Solo comprueba y planifica; no descarga ni modifica nada.
.PARAMETER Force        Reinstala los componentes ya instalados y continúa pese a avisos.

.NOTES
    Autor : Ingeniero Andrés Felipe Gutiérrez Rivera
    Códigos de salida: 0 OK | 10 requisitos | 20 conflictos/puertos | 30 descarga | 40 instalación | 50 configuración
#>
[CmdletBinding()]
param(
    [string[]]$Components = @(),
    [string]$InstallRoot = '',
    [ValidateRange(0, 65535)][int]$Port = 0,
    [switch]$BlankPassword,
    [switch]$NoPrompt,
    [switch]$SkipNotifier,
    [switch]$FixPathOnly,
    [switch]$DryRun,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'MySQLStack.Common.ps1')

#region Etapa 1: ejecución de scripts -----------------------------------------
function Enable-ScriptExecution {
    param([string]$ProjectRoot, [switch]$Plan)
    $list = Get-ExecutionPolicy -List
    $gpo = @($list | Where-Object { ($_.Scope -eq 'MachinePolicy' -or $_.Scope -eq 'UserPolicy') -and $_.ExecutionPolicy -ne 'Undefined' })
    if ($gpo.Count -gt 0) { Write-Warn 'Una directiva de grupo define la política de ejecución; puede prevalecer sobre CurrentUser.' }
    $current = [string](Get-ExecutionPolicy -Scope CurrentUser)
    if ($Plan) {
        Write-Note "DryRun: se establecería RemoteSigned en CurrentUser (actual: $current) y Unblock-File en el proyecto."
        return
    }
    if ($current -notin 'RemoteSigned', 'Unrestricted', 'Bypass') {
        try {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
            Write-Ok 'Política de ejecución CurrentUser = RemoteSigned (no requiere Administrador).'
        } catch { Write-Warn "No se pudo cambiar la política: $($_.Exception.Message)" }
    } else { Write-Ok "Política CurrentUser ya permite scripts locales ($current)." }
    Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
    Write-Ok 'Archivos del proyecto desbloqueados (marca de origen web retirada).'
    Write-Note ("Política efectiva: " + (Get-ExecutionPolicy))
}
#endregion

#region Utilidades puras (probadas en tests) -----------------------------------
# Escapa una cadena para un literal SQL entre comillas simples (\ y ')
function ConvertTo-SqlString([string]$Value) { return $Value.Replace('\', '\\').Replace("'", "''") }

# Escapa un valor para un archivo de opciones de MySQL entre comillas dobles
function ConvertTo-OptionValue([string]$Value) { return $Value.Replace('\', '\\').Replace('"', '\"') }

function Format-MyIni {
    param([string]$ServerDir, [string]$DataDir, [int]$Port, [int]$XPort)
    $b = $ServerDir.Replace('\', '/'); $d = $DataDir.Replace('\', '/')
    return @"
[client]
port=$Port
default-character-set=utf8mb4

[mysql]
default-character-set=utf8mb4

[mysqld]
basedir=$b
datadir=$d
port=$Port
bind-address=127.0.0.1
mysqlx-port=$XPort
mysqlx-bind-address=127.0.0.1
character-set-server=utf8mb4
log-error=$d/mysql-error.log
"@
}

# ¿La ruta del ejecutable está DENTRO de la carpeta? (compara con '\' final: "server" no contiene a "server-9.7-lts")
function Test-PathInside([string]$FilePath, [string]$Folder) {
    if ([string]::IsNullOrWhiteSpace($FilePath) -or [string]::IsNullOrWhiteSpace($Folder)) { return $false }
    return $FilePath.StartsWith(($Folder.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)
}
#endregion

#region Etapa 2: requisitos ----------------------------------------------------
function New-Check([string]$Name, [string]$Status, [string]$Detail, [bool]$Critical = $true) {
    return [pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail; Critical = $Critical }
}

function Test-IsElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-VCRuntimeState {
    $installed = $false; $version = ''
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
        if (Test-Path $key) {
            $p = Get-ItemProperty $key
            if ($p.PSObject.Properties['Installed'] -and $p.Installed -eq 1) {
                $installed = $true
                if ($p.PSObject.Properties['Version']) { $version = [string]$p.Version }
            }
        }
    } catch { Write-Verbose 'No se pudo leer la clave del runtime VC++.' }
    $sys = Join-Path $env:SystemRoot 'System32'
    $missing = @(@('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll') | Where-Object { -not (Test-Path (Join-Path $sys $_)) })
    return [pscustomobject]@{ Registry = $installed; Version = $version; MissingDlls = $missing }
}

function Test-WritableRoot {
    param([string]$Root, [switch]$Create)
    try {
        if ($Create) {
            if (-not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
            $probeDir = $Root
        } else {
            $probeDir = [IO.Path]::GetPathRoot($Root)   # sin crear nada: se sondea la raíz de la unidad
        }
        $probe = Join-Path $probeDir (".mysqlstack_probe_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $probe -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $probe -Force
        return $true
    } catch { return $false }
}

function Get-PrerequisiteReport {
    param([string]$Root, [hashtable]$Cfg, [object[]]$Selected)
    $r = New-Object System.Collections.Generic.List[object]

    $build = [Environment]::OSVersion.Version.Build
    if ($env:OS -ne 'Windows_NT') { $r.Add((New-Check 'Sistema operativo' 'FAIL' 'No es Windows.')) }
    elseif ($build -ge 22000) { $r.Add((New-Check 'Sistema operativo' 'OK' "Windows 11 (compilación $build)")) }
    else { $r.Add((New-Check 'Sistema operativo' 'FAIL' "Se requiere Windows 11 (compilación >= 22000); detectada $build")) }

    if ([Environment]::Is64BitOperatingSystem -and [Environment]::Is64BitProcess) { $r.Add((New-Check 'Arquitectura' 'OK' 'SO y PowerShell de 64 bits')) }
    else { $r.Add((New-Check 'Arquitectura' 'FAIL' 'Se requiere PowerShell de 64 bits sobre Windows x64.')) }
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64')) {
        $r.Add((New-Check 'ARM64' 'WARN' 'Equipo ARM64: los binarios x64 se ejecutan por emulación.' $false))
    }

    $r.Add((New-Check 'Windows PowerShell' $(if ($PSVersionTable.PSVersion -ge [version]'5.1') { 'OK' } else { 'FAIL' }) "Versión $($PSVersionTable.PSVersion)"))
    $mode = [string]$ExecutionContext.SessionState.LanguageMode
    $r.Add((New-Check 'Modo de lenguaje' $(if ($mode -eq 'FullLanguage') { 'OK' } else { 'FAIL' }) "$mode (ConstrainedLanguage indica WDAC/AppLocker estricto)"))

    if (Test-IsElevated) { $r.Add((New-Check 'Cuenta' 'WARN' 'Sesión elevada: se recomienda una cuenta estándar para validar el escenario sin Administrador.' $false)) }
    else { $r.Add((New-Check 'Cuenta' 'OK' 'Cuenta estándar (sin elevación), como se requiere.')) }
    if ($env:USERDOMAIN -ne $env:COMPUTERNAME) { $r.Add((New-Check 'Tipo de cuenta' 'WARN' "Dominio '$($env:USERDOMAIN)': las directivas de dominio pueden restringir la ejecución." $false)) }
    else { $r.Add((New-Check 'Tipo de cuenta' 'OK' 'Cuenta local.')) }

    $vc = Get-VCRuntimeState
    if ($vc.Registry -and $vc.MissingDlls.Count -eq 0) { $r.Add((New-Check 'Runtime Visual C++ x64' 'OK' "Presente (versión $($vc.Version))")) }
    elseif ($vc.MissingDlls.Count -eq 0) { $r.Add((New-Check 'Runtime Visual C++ x64' 'OK' 'DLL de sistema presentes (sin clave de registro).')) }
    else { $r.Add((New-Check 'Runtime Visual C++ x64' 'FAIL' ("Faltan: " + ($vc.MissingDlls -join ', ') + '. Instalar vc_redist.x64.exe requiere Administrador.'))) }

    $needsNet = @($Selected | Where-Object { $_.Id -in 'NOTIF', 'WB8' }).Count -gt 0
    $net = 0
    try { $net = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Stop).Release } catch { Write-Verbose '.NET Framework no detectado.' }
    if ($net -ge 379893) { $r.Add((New-Check '.NET Framework 4.5.2+' 'OK' "Release $net" $false)) }
    else { $r.Add((New-Check '.NET Framework 4.5.2+' $(if ($needsNet) { 'WARN' } else { 'OK' }) 'No detectado: MySQL Notifier y Workbench 8.0 lo requieren.' $false)) }

    if (Test-SafeInstallRoot $Root) { $r.Add((New-Check 'Ruta de instalación' 'OK' $Root)) }
    else { $r.Add((New-Check 'Ruta de instalación' 'FAIL' "Ruta no válida o con caracteres especiales: '$Root'")) }
    if (Test-WritableRoot -Root $Root) { $r.Add((New-Check 'Permiso de escritura' 'OK' "Se pueden crear carpetas en $([IO.Path]::GetPathRoot($Root))")) }
    else { $r.Add((New-Check 'Permiso de escritura' 'FAIL' "El usuario no puede crear carpetas en $([IO.Path]::GetPathRoot($Root))")) }
    try {
        $freeGb = [math]::Round(([IO.DriveInfo]::new([IO.Path]::GetPathRoot($Root)).AvailableFreeSpace) / 1GB, 1)
        $need = [double](($Selected | Measure-Object -Property NeedGb -Sum).Sum)
        $r.Add((New-Check 'Espacio en disco' $(if ($freeGb -ge $need) { 'OK' } else { 'FAIL' }) "$freeGb GB libres (mínimo $need GB para la selección)"))
    } catch { $r.Add((New-Check 'Espacio en disco' 'WARN' 'No se pudo medir.' $false)) }

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    $r.Add((New-Check 'curl.exe' $(if ($curl) { 'OK' } else { 'WARN' }) $(if ($curl) { $curl.Source } else { 'No encontrado: se usará .NET WebClient.' }) $false))
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    $r.Add((New-Check 'tar.exe' $(if ($tar) { 'OK' } else { 'WARN' }) $(if ($tar) { $tar.Source } else { 'No encontrado: se usará Expand-Archive (más lento).' }) $false))
    $msi = Get-Command msiexec.exe -ErrorAction SilentlyContinue
    $r.Add((New-Check 'msiexec.exe' $(if ($msi) { 'OK' } else { 'WARN' }) $(if ($msi) { 'Disponible (Notifier y Workbench 8.0)' } else { 'No encontrado: Notifier y Workbench 8.0 no podrán extraerse.' }) $false))

    if ($curl -and $Selected.Count -gt 0) {
        $code = ''
        try { $code = (& $curl.Source -s -I -L --max-time 20 -o NUL -w '%{http_code}' $Selected[0].Url) } catch { Write-Verbose 'Fallo de curl en la prueba de red.' }
        if ($code -eq '200') { $r.Add((New-Check 'Conectividad a cdn.mysql.com' 'OK' 'HTTP 200')) }
        else { $r.Add((New-Check 'Conectividad a cdn.mysql.com' 'FAIL' "Respuesta '$code'. Revise proxy/firewall corporativo.")) }
    }

    try {
        $fw = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { $_.Enabled })
        $r.Add((New-Check 'Firewall de Windows' 'OK' ("Perfiles activos: " + ($fw.Name -join ', ') + ". mysqld escucha solo en 127.0.0.1: no genera aviso.") $false))
    } catch { $r.Add((New-Check 'Firewall de Windows' 'WARN' 'No se pudo consultar; mysqld escuchará solo en 127.0.0.1.' $false)) }
    if (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2') { $r.Add((New-Check 'AppLocker' 'WARN' 'Hay directivas AppLocker: podrían bloquear ejecutables en el perfil o en C:\Programs.' $false)) }
    if (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers') { $r.Add((New-Check 'Directivas de restricción de software' 'WARN' 'Detectadas; podrían bloquear la ejecución.' $false)) }
    $r.Add((New-Check 'Servicio de Windows' 'WARN' 'Sin Administrador no se puede registrar un servicio: mysqld se ejecutará como proceso de usuario (no inicia con el sistema).' $false))
    return $r
}
#endregion

#region Etapas 3-4: instalaciones de terceros, XAMPP y WampServer -------------------
# Detecta SOLO software ajeno al proyecto (las instalaciones propias se controlan con el manifiesto)
function Find-ThirdPartyInstallations {
    param([string]$Base)
    $found = New-Object System.Collections.Generic.List[object]
    $add = { param($kind, $name, $detail) $found.Add([pscustomobject]@{ Kind = $kind; Name = $name; Detail = $detail }) }

    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($k in $keys) {
        Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties['DisplayName'] } | ForEach-Object {
            $n = [string]$_.DisplayName
            if ($n -match '^MySQL|MariaDB') { & $add 'MySQL' $n 'Programa instalado (registro)' }
            elseif ($n -match 'XAMPP') { & $add 'XAMPP' $n 'Programa instalado (registro)' }
            elseif ($n -match 'Wamp') { & $add 'WAMP' $n 'Programa instalado (registro)' }
        }
    }
    foreach ($d in @("$env:ProgramFiles\MySQL", "${env:ProgramFiles(x86)}\MySQL", "$env:ProgramData\MySQL")) {
        if ($d -and (Test-Path -LiteralPath $d)) { & $add 'MySQL' $d 'Carpeta existente' }
    }
    foreach ($drive in [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' }) {
        $rootDir = $drive.RootDirectory.FullName
        if (Test-Path -LiteralPath (Join-Path $rootDir 'xampp')) { & $add 'XAMPP' (Join-Path $rootDir 'xampp') 'Carpeta existente' }
        foreach ($w in 'wamp64', 'wamp') { if (Test-Path -LiteralPath (Join-Path $rootDir $w)) { & $add 'WAMP' (Join-Path $rootDir $w) 'Carpeta existente' } }
    }
    Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(MySQL|MariaDB)' -or $_.DisplayName -match 'MySQL' } |
        ForEach-Object { & $add 'MySQL' $_.Name "Servicio ($($_.Status))" }
    Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^wamp' } |
        ForEach-Object { & $add 'WAMP' $_.Name "Servicio ($($_.Status))" }
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(mysqld|mysqld-nt|MySQLNotifier|MySQLWorkbench|MySQL Workbench)$' } | ForEach-Object {
        $exe = ''; try { $exe = [string]$_.Path } catch { Write-Verbose 'Proceso sin ruta accesible.' }
        if (-not (Test-PathInside $exe $Base)) { & $add 'MySQL' $_.ProcessName "Proceso en ejecución (PID $($_.Id))" }
    }
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(xampp-control|httpd)$' } |
        ForEach-Object { & $add 'XAMPP' $_.ProcessName "Proceso en ejecución (PID $($_.Id))" }
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^wampmanager' } |
        ForEach-Object { & $add 'WAMP' $_.ProcessName "Proceso en ejecución (PID $($_.Id))" }
    if ($env:MYSQL_HOME) { & $add 'MySQL' 'MYSQL_HOME' "Variable de entorno = $env:MYSQL_HOME" }
    return $found
}

# Estado de un componente propio: Installed (manifiesto + carpeta) | Partial (carpeta sin manifiesto) | Absent
function Get-ComponentInstallState {
    param($Comp, [hashtable]$Manifest)
    $flag = (Get-ComponentState $Manifest $Comp.Id).Installed
    $exists = Test-Path -LiteralPath $Comp.Dir
    if ($flag -and $exists) { return 'Installed' }
    if ($exists -or $flag) { return 'Partial' }
    return 'Absent'
}
#endregion

#region Etapa 5: puertos ------------------------------------------------------------------
function Get-ListeningPorts {
    return @([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() |
        ForEach-Object { $_.Port } | Sort-Object -Unique)
}

function Test-PortBindable([int]$Port) {
    try {
        $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
        $l.Start(); $l.Stop(); return $true
    } catch { return $false }
}

function Select-MySqlPorts {
    param([int]$Requested, [bool]$HasConflicts, [int]$DefaultPort, [int]$DefaultXPort, [int[]]$Listening = @())
    $taken = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($p in $Listening) { [void]$taken.Add($p) }
    $isFree = { param([int]$p) (-not $taken.Contains($p)) -and (Test-PortBindable $p) }

    $classic = 0; $reason = ''
    if ($Requested -gt 0) {
        if (& $isFree $Requested) { $classic = $Requested; $reason = 'puerto solicitado' }
        else { throw (New-StackError 20 "El puerto solicitado $Requested no está disponible.") }
    } elseif ((-not $HasConflicts) -and (& $isFree $DefaultPort)) {
        $classic = $DefaultPort; $reason = 'sin otras instalaciones: puerto por defecto'
    } else {
        foreach ($c in ($DefaultPort + 1)..3399) { if (& $isFree $c) { $classic = $c; break } }
        if ($classic -eq 0) { throw (New-StackError 20 'No se encontró un puerto libre en el rango 3307-3399.') }
        $reason = 'otras instalaciones o puerto ocupado: puerto alternativo'
    }

    $x = 0
    $candidates = if ($HasConflicts) { ($DefaultXPort + 1)..($DefaultXPort + 200) } else { $DefaultXPort..($DefaultXPort + 200) }
    foreach ($c in $candidates) { if ($c -ne $classic -and (& $isFree $c)) { $x = $c; break } }
    if ($x -eq 0) { throw (New-StackError 20 'No se encontró un puerto libre para el protocolo X.') }
    return [pscustomobject]@{ Port = $classic; XPort = $x; Reason = $reason }
}
#endregion

#region Etapa 7: descarga, verificación y extracción ----------------------------------------
function Get-VerifiedFile {
    param([string]$Url, [string]$Dest, [string]$Md5, [string]$Label)
    if (Test-Path -LiteralPath $Dest) {
        if ((Get-FileHash -LiteralPath $Dest -Algorithm MD5).Hash -ieq $Md5) { Write-Ok "$Label ya descargado y verificado (caché)."; return }
        Remove-Item -LiteralPath $Dest -Force
    }
    Write-Note "Descargando $Label ..."
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $p = Start-Process -FilePath $curl.Source -Wait -PassThru -NoNewWindow `
            -ArgumentList @('-L', '--fail', '--retry', '3', '--retry-delay', '3', '--progress-bar', '-o', "`"$Dest`"", "`"$Url`"")
        if ($p.ExitCode -ne 0) { throw (New-StackError 30 "curl terminó con código $($p.ExitCode) al descargar $Label.") }
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        (New-Object Net.WebClient).DownloadFile($Url, $Dest)
    }
    $actual = (Get-FileHash -LiteralPath $Dest -Algorithm MD5).Hash
    if ($actual -ine $Md5) {
        Remove-Item -LiteralPath $Dest -Force
        throw (New-StackError 30 "MD5 incorrecto en $Label (esperado $Md5, obtenido $actual). Archivo eliminado.")
    }
    Write-Ok "$Label descargado y verificado (MD5)."
}

function Expand-ZipArchive {
    param([string]$Zip, [string]$Dest)
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tar) {
        $p = Start-Process -FilePath $tar.Source -Wait -PassThru -NoNewWindow -ArgumentList @('-xf', "`"$Zip`"", '-C', "`"$Dest`"")
        if ($p.ExitCode -eq 0) { return }
        Write-Warn 'tar.exe falló; se usa Expand-Archive.'
    }
    Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force
}

function Invoke-Native {
    # Ejecuta un binario capturando salida sin que PS 5.1 convierta stderr en error terminante
    param([string]$File, [string[]]$Arguments, [string]$StdInFile = '')
    $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
    try {
        $sp = @{ FilePath = $File; ArgumentList = $Arguments; Wait = $true; PassThru = $true; NoNewWindow = $true
                 RedirectStandardOutput = $out; RedirectStandardError = $err }
        if ($StdInFile) { $sp.RedirectStandardInput = $StdInFile }
        $proc = Start-Process @sp
        return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            StdOut   = [string](Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue)
            StdErr   = [string](Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)
        }
    } finally { Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue }
}

function Stop-ProcessesInside([string]$Folder) {
    $stopped = 0
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $exe = ''; try { $exe = [string]$_.Path } catch { Write-Verbose 'Proceso sin ruta accesible.' }
        if (Test-PathInside $exe $Folder) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; $stopped++ }
    }
    if ($stopped -gt 0) { Start-Sleep -Seconds 2 }
    return $stopped
}

function Install-ServerPackage {
    param($Paths, $Comp)
    $zip = Join-Path $Paths.Cache $Comp.File
    Get-VerifiedFile -Url $Comp.Url -Dest $zip -Md5 $Comp.Md5 -Label $Comp.Label
    $tmp = Join-Path $Paths.Temp $Comp.Id
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Write-Note "Extrayendo $($Comp.Label)..."
    Expand-ZipArchive -Zip $zip -Dest $tmp
    $inner = Join-Path $tmp $Comp.Folder
    if (-not (Test-Path (Join-Path $inner 'bin\mysqld.exe'))) { throw (New-StackError 40 "El ZIP no contiene $($Comp.Folder)\bin\mysqld.exe") }
    if (Test-Path $Comp.Dir) { Remove-Item $Comp.Dir -Recurse -Force }   # el directorio de datos está fuera de esta carpeta
    Move-Item -LiteralPath $inner -Destination $Comp.Dir
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    $v = Invoke-Native -File (Join-Path $Comp.Dir 'bin\mysqld.exe') -Arguments @('--version')
    if ($v.ExitCode -ne 0) { throw (New-StackError 40 "mysqld.exe no se ejecuta (¿runtime VC++ o directiva de ejecución?): $($v.StdErr)") }
    Write-Ok ("$($Comp.Label) instalado: " + $v.StdOut.Trim())
}

function Install-WorkbenchZipPackage {
    param($Paths, $Comp)
    $zip = Join-Path $Paths.Cache $Comp.File
    Get-VerifiedFile -Url $Comp.Url -Dest $zip -Md5 $Comp.Md5 -Label $Comp.Label
    if (Test-Path $Comp.Dir) { Remove-Item $Comp.Dir -Recurse -Force }
    Write-Note "Extrayendo $($Comp.Label)..."
    Expand-ZipArchive -Zip $zip -Dest $Comp.Dir
    if (-not (Test-Path (Join-Path $Comp.Dir 'MySQL Workbench.exe'))) { throw (New-StackError 40 "No se encontró 'MySQL Workbench.exe' tras extraer.") }
    Write-Ok "$($Comp.Label) instalado."
}

# Extrae un MSI como "imagen administrativa" (msiexec /a) en una carpeta de usuario y mueve la carpeta del ejecutable.
# Los MSI de Notifier y de Workbench 8.0 declaran la condición 'Privileged', que NO está en la secuencia administrativa.
function Install-MsiImagePackage {
    param($Paths, $Comp, [string]$ExeName, [switch]$Optional)
    $msi = Join-Path $Paths.Cache $Comp.File
    Get-VerifiedFile -Url $Comp.Url -Dest $msi -Md5 $Comp.Md5 -Label $Comp.Label
    $img = Join-Path $Paths.Temp "$($Comp.Id)-image"
    if (Test-Path $img) { Remove-Item $img -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $img | Out-Null
    $log = Join-Path $Paths.Logs "$($Comp.Id)-msiexec.log"
    Write-Note "Extrayendo $($Comp.Label) con msiexec /a (puede tardar varios minutos)..."
    $p = Start-Process -FilePath msiexec.exe -Wait -PassThru -ArgumentList @('/a', "`"$msi`"", '/qn', "TARGETDIR=`"$img`"", '/L*v', "`"$log`"")
    $exe = Get-ChildItem -LiteralPath $img -Recurse -Filter $ExeName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) {
        Remove-Item $img -Recurse -Force -ErrorAction SilentlyContinue
        $msg = "No se pudo extraer $($Comp.Label) sin Administrador (msiexec código $($p.ExitCode)). Detalle: $log"
        if ($Optional) { Write-Warn $msg; return $false }
        throw (New-StackError 40 $msg)
    }
    if (Test-Path $Comp.Dir) { Remove-Item $Comp.Dir -Recurse -Force }
    Move-Item -LiteralPath $exe.Directory.FullName -Destination $Comp.Dir
    Remove-Item $img -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "$($Comp.Label) extraído."
    return $true
}
#endregion

#region Etapas 8-9: servidor y contraseña ---------------------------------------------------------
function Wait-TcpPort {
    param([int]$Port, [int]$TimeoutSec, $Process)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($Process -and $Process.HasExited) { return $false }
        try { $c = New-Object System.Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $Port); $c.Close(); return $true }
        catch { Start-Sleep -Seconds 1 }
    }
    return $false
}

function Write-MyIni {
    param($Comp, [int]$Port, [int]$XPort)
    $text = Format-MyIni -ServerDir $Comp.Dir -DataDir $Comp.DataDir -Port $Port -XPort $XPort
    [IO.File]::WriteAllText((Join-WinPath $Comp.Dir 'my.ini'), $text, (New-Object Text.ASCIIEncoding))
}

function Initialize-DataDirectory {
    param($Comp)
    if (Test-Path (Join-Path $Comp.DataDir 'mysql')) { Write-Ok "Directorio de datos de $($Comp.Label) ya inicializado (se conserva)."; return }
    New-Item -ItemType Directory -Force -Path $Comp.DataDir | Out-Null
    $ini = Join-Path $Comp.Dir 'my.ini'
    $r = Invoke-Native -File (Join-Path $Comp.Dir 'bin\mysqld.exe') -Arguments @("--defaults-file=`"$ini`"", '--initialize-insecure', '--console')
    if ($r.ExitCode -ne 0) { throw (New-StackError 50 "Falló --initialize-insecure en $($Comp.Label) (código $($r.ExitCode)): $($r.StdErr)") }
    Write-Ok "Directorio de datos de $($Comp.Label) inicializado (root sin contraseña temporal)."
}

function Start-MySqlServer {
    param($Comp, [int]$Port)
    $ini = Join-Path $Comp.Dir 'my.ini'
    $proc = Start-Process -FilePath (Join-Path $Comp.Dir 'bin\mysqld.exe') -ArgumentList @("--defaults-file=`"$ini`"") -WindowStyle Hidden -PassThru
    if (-not (Wait-TcpPort -Port $Port -TimeoutSec 60 -Process $proc)) {
        $logFile = Join-Path $Comp.DataDir 'mysql-error.log'
        $tail = if (Test-Path $logFile) { (Get-Content $logFile -Tail 15) -join [Environment]::NewLine } else { '(sin registro)' }
        throw (New-StackError 50 "$($Comp.Label) no quedó escuchando en el puerto $Port.$([Environment]::NewLine)$tail")
    }
    Write-Ok "$($Comp.Label) en ejecución (PID $($proc.Id)) escuchando en 127.0.0.1:$Port"
}

function ConvertTo-PlainText([securestring]$Secure) {
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function Read-RootPasswordChoice {
    if ($BlankPassword) { return [pscustomobject]@{ Mode = 'Blank'; Secure = $null } }
    if ($NoPrompt) { return [pscustomobject]@{ Mode = 'Fallback'; Secure = $null } }
    while ($true) {
        $s1 = Read-Host 'Contraseña para el usuario root de MySQL (ENTER = en blanco)' -AsSecureString
        if ($s1.Length -eq 0) {
            $ans = Read-Host '¿Confirma dejar la contraseña EN BLANCO? (s/N)'
            if ($ans -match '^(s|si|sí|y|yes)$') { return [pscustomobject]@{ Mode = 'Blank'; Secure = $null } }
            continue
        }
        $s2 = Read-Host 'Repita la contraseña' -AsSecureString
        if ((ConvertTo-PlainText $s1) -ceq (ConvertTo-PlainText $s2)) { return [pscustomobject]@{ Mode = 'Custom'; Secure = $s1 } }
        Write-Warn 'Las contraseñas no coinciden. Intente de nuevo.'
    }
}

function Remove-SecretFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $len = (Get-Item -LiteralPath $Path).Length
        [IO.File]::WriteAllBytes($Path, (New-Object byte[] ([int]$len)))   # sobrescribe con ceros
    } catch { Write-Verbose 'No se pudo sobrescribir el archivo temporal.' }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Invoke-MySqlClient {
    # Ejecuta SQL como root. $CurrentPassword = $null => cuenta sin contraseña (--skip-password)
    # CurrentPassword va SIN tipo: un [string] convertiría $null en '' y se perdería la distinción "sin contraseña"
    param($Paths, [int]$Port, [string]$Sql, [AllowNull()]$CurrentPassword = $null)
    $cnf = Join-Path $env:TEMP ("msq_" + [guid]::NewGuid().ToString('N') + '.cnf')
    $sqlFile = Join-Path $env:TEMP ("msq_" + [guid]::NewGuid().ToString('N') + '.sql')
    try {
        $cfgText = "[client]`r`nuser=root`r`n"
        if ($null -ne $CurrentPassword) { $cfgText += 'password="' + (ConvertTo-OptionValue $CurrentPassword) + "`"`r`n" }
        [IO.File]::WriteAllText($cnf, $cfgText, (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($sqlFile, $Sql, (New-Object Text.UTF8Encoding($false)))
        $argsList = @("--defaults-extra-file=`"$cnf`"", '--protocol=TCP', '--host=127.0.0.1', "--port=$Port")
        if ($null -eq $CurrentPassword) { $argsList += '--skip-password' }
        return Invoke-Native -File (Join-Path $Paths.Server 'bin\mysql.exe') -Arguments $argsList -StdInFile $sqlFile
    } finally { Remove-SecretFile $cnf; Remove-SecretFile $sqlFile }
}

function Set-RootPassword {
    # $Paths necesita la clave Server (carpeta del servidor). Devuelve 'blank' | 'custom' | 'fallback'
    param($Paths, [int]$Port, $Choice, [string]$Fallback)
    if ($Choice.Mode -eq 'Blank') {
        $t = Invoke-MySqlClient -Paths $Paths -Port $Port -Sql 'SELECT 1;'
        if ($t.ExitCode -ne 0) { throw (New-StackError 50 "No se pudo conectar como root: $($t.StdErr)") }
        return 'blank'
    }
    if ($Choice.Mode -eq 'Custom') {
        $plain = ConvertTo-PlainText $Choice.Secure
        $sql = "ALTER USER 'root'@'localhost' IDENTIFIED BY '" + (ConvertTo-SqlString $plain) + "'; FLUSH PRIVILEGES;"
        $r = Invoke-MySqlClient -Paths $Paths -Port $Port -Sql $sql
        if ($r.ExitCode -eq 0) { return 'custom' }
        Write-Warn "No fue posible asignar la contraseña indicada ($($r.StdErr.Trim())). Se usará la de respaldo."
    }
    $sqlFb = "ALTER USER 'root'@'localhost' IDENTIFIED BY '" + (ConvertTo-SqlString $Fallback) + "'; FLUSH PRIVILEGES;"
    $r2 = Invoke-MySqlClient -Paths $Paths -Port $Port -Sql $sqlFb
    if ($r2.ExitCode -ne 0) { throw (New-StackError 50 "No se pudo asignar ninguna contraseña a root: $($r2.StdErr)") }
    return 'fallback'
}
#endregion

#region Etapa 10: lanzadores y accesos directos -------------------------------------------------------
function New-LauncherFiles {
    param($Paths, $Comp, [int]$Port)
    New-Item -ItemType Directory -Force -Path $Paths.Launchers | Out-Null
    $tplDir = Join-Path $script:ProjectRoot 'src\templates'
    foreach ($n in 'mysql-console', 'start-mysql-server', 'stop-mysql-server') {
        $txt = (Get-Content -LiteralPath (Join-Path $tplDir "$n.cmd.tpl") -Raw -Encoding UTF8).
            Replace('@@BASE@@', $Paths.Base).Replace('@@PORT@@', "$Port").Replace('@@SRVDIR@@', $Comp.DirName).
            Replace('@@DATADIR@@', $Comp.DataName).Replace('@@LABEL@@', $Comp.Label)
        Set-Content -LiteralPath (Join-Path $Paths.Launchers ("$n$($Comp.Suffix).cmd")) -Value $txt -Encoding Ascii
    }
}

function New-DesktopShortcut {
    param([string]$Name, [string]$Target, [string]$Arguments = '', [string]$WorkDir, [string]$Icon = '', [string]$Description = '')
    $desktop = [Environment]::GetFolderPath('Desktop')
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut((Join-Path $desktop "$Name.lnk"))
    $lnk.TargetPath = $Target
    $lnk.Arguments = $Arguments
    $lnk.WorkingDirectory = $WorkDir
    $lnk.Description = $Description
    if ($Icon) { $lnk.IconLocation = $Icon }
    $lnk.Save()
}

function New-ComponentShortcut {
    param($Paths, $Comp)
    switch ($Comp.Kind) {
        'server' {
            New-DesktopShortcut -Name $Comp.Link -Target (Join-Path $Paths.Launchers "mysql-console$($Comp.Suffix).cmd") -WorkDir $Paths.Base `
                -Icon "$(Join-Path $Comp.Dir 'bin\mysql.exe'),0" -Description "Inicia $($Comp.Label) si está detenido y abre la consola del cliente"
        }
        'wbzip'    { New-DesktopShortcut -Name $Comp.Link -Target (Join-Path $Comp.Dir 'MySQL Workbench.exe') -WorkDir $Comp.Dir -Description $Comp.Label }
        'wbmsi'    { New-DesktopShortcut -Name $Comp.Link -Target (Join-Path $Comp.Dir 'MySQLWorkbench.exe') -WorkDir $Comp.Dir -Description $Comp.Label }
        'notifier' { New-DesktopShortcut -Name $Comp.Link -Target (Join-Path $Comp.Dir 'MySQLNotifier.exe') -WorkDir $Comp.Dir -Description $Comp.Label }
    }
}
#endregion

#region Orquestación ---------------------------------------------------------------------------------------
function Invoke-Main {
    $cfg = Get-StackConfig -ProjectRoot $script:ProjectRoot
    $root = if ($InstallRoot) { $InstallRoot } elseif ($cfg.ContainsKey('INSTALL_ROOT') -and $cfg['INSTALL_ROOT']) { $cfg['INSTALL_ROOT'] } else { $cfg['STACK_ROOT_DEFAULT'] }
    $root = $root.TrimEnd('\')
    $paths = Get-StackPaths $root
    $manifest = Read-Manifest $paths.Manifest

    if ($FixPathOnly) {
        Write-Stage 'PATH de usuario (prioridad sobre XAMPP MySQL)'
        [void](Update-UserEnvironment -Cfg $cfg -Paths $paths -Manifest $manifest)
        return
    }

    $skipNotifier = $SkipNotifier.IsPresent -or ($cfg.ContainsKey('SKIP_NOTIFIER') -and $cfg['SKIP_NOTIFIER'] -eq '1')
    $requestedPort = if ($Port -gt 0) { $Port } elseif ($cfg.ContainsKey('MYSQL_PORT') -and [int]$cfg['MYSQL_PORT'] -gt 0) { [int]$cfg['MYSQL_PORT'] } else { 0 }
    $names = if ($Components.Count -gt 0) { $Components } else { @('LATEST') }
    $ids = @(Resolve-ComponentSelection $names)
    if ($skipNotifier) { $ids = @($ids | Where-Object { $_ -ne 'NOTIF' }) }
    if ($ids.Count -eq 0) { throw (New-StackError 50 'La selección de componentes quedó vacía.') }
    $selected = @($ids | ForEach-Object { Get-Component -Cfg $cfg -Id $_ -Base $paths.Base })

    $mode = if ($DryRun) { ' (SIMULACIÓN: no se modificará nada)' } else { '' }
    Write-Host "MySQL Stack para Windows 11 sin Administrador$mode" -ForegroundColor White
    Write-Host ("Selección: " + (($selected | ForEach-Object { $_.Label }) -join ' | ')) -ForegroundColor White

    Write-Stage '1/10 Habilitar ejecución de scripts descargados'
    Enable-ScriptExecution -ProjectRoot $script:ProjectRoot -Plan:$DryRun

    Write-Stage '2/10 Requisitos mínimos del sistema'
    $report = Get-PrerequisiteReport -Root $root -Cfg $cfg -Selected $selected
    foreach ($c in $report) {
        switch ($c.Status) { 'OK' { Write-Ok "$($c.Name): $($c.Detail)" } 'WARN' { Write-Warn "$($c.Name): $($c.Detail)" } default { Write-Bad "$($c.Name): $($c.Detail)" } }
    }
    $fails = @($report | Where-Object { $_.Status -eq 'FAIL' -and $_.Critical })
    if ($fails.Count -gt 0) { throw (New-StackError 10 "Hay $($fails.Count) requisito(s) crítico(s) sin cumplir. Corrija y reintente.") }

    Write-Stage '3/10 Instalaciones previas de MySQL / Workbench / Notifier'
    $third = @(Find-ThirdPartyInstallations -Base $paths.Base)
    $mysqlPrev = @($third | Where-Object { $_.Kind -eq 'MySQL' })
    if ($mysqlPrev.Count -eq 0) { Write-Ok 'No se detectaron otras instalaciones de MySQL ajenas al proyecto.' } else { $mysqlPrev | ForEach-Object { Write-Warn "$($_.Name): $($_.Detail)" } }
    $toInstall = New-Object System.Collections.Generic.List[object]
    foreach ($c in $selected) {
        $st = Get-ComponentInstallState -Comp $c -Manifest $manifest
        if ($st -eq 'Installed' -and -not $Force) { Write-Ok "$($c.Label): ya instalado (se omite; use -Force para reinstalar)."; continue }
        if ($st -eq 'Partial') { Write-Warn "$($c.Label): instalación incompleta previa; se reinstalará." }
        if ($st -eq 'Installed') { Write-Warn "$($c.Label): se reinstalará (-Force)." }
        $toInstall.Add($c)
    }
    $others = @(Get-ComponentIds | Where-Object { $_ -notin $ids } | Where-Object { (Get-ComponentState $manifest $_).Installed })
    if ($others.Count -gt 0) { Write-Ok ("Otros componentes del proyecto ya instalados (no se tocan): " + ($others -join ', ')) }

    Write-Stage '4/10 XAMPP y WampServer'
    $stacks = @($third | Where-Object { $_.Kind -eq 'XAMPP' -or $_.Kind -eq 'WAMP' })
    if ($stacks.Count -eq 0) { Write-Ok 'No se detectaron XAMPP ni WampServer.' } else { $stacks | ForEach-Object { Write-Warn "$($_.Kind): $($_.Name) - $($_.Detail)" } }
    if (Test-PathHasPattern (Get-UserPathRaw) (Get-XamppPathPattern)) { Write-Note 'El PATH de usuario contiene XAMPP MySQL: el servidor del proyecto se colocará ANTES de esa entrada.' }

    if ($toInstall.Count -eq 0) { Write-Stage 'Resultado'; Write-Ok 'No hay nada que instalar: todos los componentes seleccionados ya están instalados.'; return }

    Write-Stage '5/10 Disponibilidad de puertos'
    $assigned = @{}      # Id -> objeto de puertos
    $reserved = New-Object System.Collections.Generic.List[int]
    $ownServers = 0
    foreach ($sid in Get-ServerIds) {
        $isTarget = @($toInstall | Where-Object { $_.Id -eq $sid }).Count -gt 0
        $s = Get-ComponentState $manifest $sid
        if ((-not $isTarget) -and $s.Installed) { $ownServers++; if ($s.Port) { $reserved.Add($s.Port) }; if ($s.XPort) { $reserved.Add($s.XPort) } }
    }
    $firstServer = $true
    foreach ($c in @($toInstall | Where-Object { $_.IsServer })) {
        $hasConflicts = (($mysqlPrev.Count + $stacks.Count + $ownServers) -gt 0)
        $req = if ($firstServer) { $requestedPort } else { 0 }
        $listening = @(Get-ListeningPorts) + @($reserved)
        $p = Select-MySqlPorts -Requested $req -HasConflicts $hasConflicts -DefaultPort ([int]$cfg['DEFAULT_PORT']) -DefaultXPort ([int]$cfg['DEFAULT_XPORT']) -Listening $listening
        $assigned[$c.Id] = $p; $reserved.Add($p.Port); $reserved.Add($p.XPort); $ownServers++; $firstServer = $false
        Write-Ok "$($c.Label): puerto MySQL $($p.Port) ($($p.Reason)) | protocolo X $($p.XPort)"
    }
    if ($assigned.Count -eq 0) { Write-Note 'La selección no incluye servidores: no se asignan puertos.' }

    if ($DryRun) {
        Write-Stage 'Plan (DryRun)'
        foreach ($c in $toInstall) {
            $extra = if ($c.IsServer) { " | puerto $($assigned[$c.Id].Port) | datos $($c.DataDir)" } else { '' }
            Write-Note "Instalaría $($c.Label) en $($c.Dir)$extra"
            Write-Note "   acceso directo: $($c.Link)"
        }
        $prim = if (@($toInstall | Where-Object { $_.Id -eq 'SRV' }).Count -gt 0 -or (Get-ComponentState $manifest 'SRV').Installed) { 'SRV' } elseif (@($toInstall | Where-Object { $_.Id -eq 'SRVLTS' }).Count -gt 0 -or (Get-ComponentState $manifest 'SRVLTS').Installed) { 'SRVLTS' } else { '' }
        if ($prim) {
            $pp = if ($assigned.ContainsKey($prim)) { $assigned[$prim].Port } else { (Get-ComponentState $manifest $prim).Port }
            Write-Note "Servidor primario (PATH): $prim | conexión: mysql -u root -p -h localhost -P $pp -D mysql"
        }
        Write-Ok 'Simulación completada sin cambios.'
        return
    }

    Write-Stage "6/10 Carpeta de instalación ($root)"
    $createdRoot = -not (Test-Path -LiteralPath $root)
    if (-not (Test-WritableRoot -Root $root -Create)) { throw (New-StackError 10 "No se pudo crear/escribir en $root") }
    foreach ($d in $paths.Base, $paths.Cache, $paths.Temp, $paths.Logs) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    Write-Ok "Carpeta lista: $($paths.Base)"
    try { Start-Transcript -Path (Join-WinPath $paths.Logs ("install-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')) -Append | Out-Null } catch { Write-Verbose 'Sin transcripción.' }
    if ($createdRoot -and -not $manifest.ContainsKey('CREATED_ROOT')) { $manifest['CREATED_ROOT'] = '1' }
    $manifest['INSTALL_ROOT'] = $root; $manifest['BASE'] = $paths.Base

    Write-Stage '7/10 Descarga, verificación e instalación de paquetes'
    $ready = New-Object System.Collections.Generic.List[object]
    foreach ($c in $toInstall) {
        if ((Stop-ProcessesInside $c.Dir) -gt 0) { Write-Warn "Procesos de $($c.Label) detenidos antes de reinstalar." }
        $ok = $true
        switch ($c.Kind) {
            'server'   { Install-ServerPackage -Paths $paths -Comp $c }
            'wbzip'    { Install-WorkbenchZipPackage -Paths $paths -Comp $c }
            'wbmsi'    { Install-MsiImagePackage -Paths $paths -Comp $c -ExeName 'MySQLWorkbench.exe' | Out-Null }
            'notifier' { $ok = [bool](Install-MsiImagePackage -Paths $paths -Comp $c -ExeName 'MySQLNotifier.exe' -Optional) }
        }
        if ($ok) { $ready.Add($c) } else { Write-Warn "$($c.Label) no quedó instalado (ver docs/LIMITACIONES.md)." }
    }

    Write-Stage '8/10 Configuración e inicio de los servidores'
    $startedServers = New-Object System.Collections.Generic.List[object]
    foreach ($c in @($ready | Where-Object { $_.IsServer })) {
        $pp = $assigned[$c.Id]
        Write-MyIni -Comp $c -Port $pp.Port -XPort $pp.XPort
        Write-Ok "$($c.Label): my.ini generado (escucha solo en 127.0.0.1)."
        Initialize-DataDirectory -Comp $c
        Start-MySqlServer -Comp $c -Port $pp.Port
        Set-ComponentInstalled -Manifest $manifest -Id $c.Id -Port $pp.Port -XPort $pp.XPort
        Save-Manifest -Path $paths.Manifest -Manifest $manifest
        $startedServers.Add($c)
    }
    foreach ($c in @($ready | Where-Object { -not $_.IsServer })) {
        Set-ComponentInstalled -Manifest $manifest -Id $c.Id
        Save-Manifest -Path $paths.Manifest -Manifest $manifest
    }

    if ($startedServers.Count -gt 0) {
        Write-Stage '9/10 Contraseña de root'
        if ($startedServers.Count -gt 1) { Write-Note 'La misma contraseña se aplicará a todos los servidores instalados en esta ejecución.' }
        $choice = Read-RootPasswordChoice
        foreach ($c in $startedServers) {
            $applied = Set-RootPassword -Paths @{ Server = $c.Dir } -Port $assigned[$c.Id].Port -Choice $choice -Fallback $cfg['FALLBACK_ROOT_PASSWORD']
            switch ($applied) {
                'blank'    { Write-Ok "$($c.Label): root sin contraseña (según su elección)." }
                'custom'   { Write-Ok "$($c.Label): contraseña de root establecida." }
                'fallback' { Write-Warn "$($c.Label): root usa la contraseña de respaldo '$($cfg['FALLBACK_ROOT_PASSWORD'])'. CÁMBIELA cuanto antes (ALTER USER)." }
            }
        }
    } else { Write-Stage '9/10 Contraseña de root'; Write-Note 'No se instalaron servidores en esta ejecución.' }

    Write-Stage '10/10 PATH, lanzadores y accesos directos'
    foreach ($c in $startedServers) { New-LauncherFiles -Paths $paths -Comp $c -Port $assigned[$c.Id].Port }
    foreach ($c in $ready) { New-ComponentShortcut -Paths $paths -Comp $c; Write-Ok "Acceso directo: $($c.Link)" }
    [void](Update-UserEnvironment -Cfg $cfg -Paths $paths -Manifest $manifest)
    Save-Manifest -Path $paths.Manifest -Manifest $manifest
    Remove-Item $paths.Temp -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host 'INSTALACIÓN COMPLETADA' -ForegroundColor Green
    foreach ($c in $startedServers) {
        $pp = $assigned[$c.Id].Port
        $cmd = if ($c.Id -eq (Get-PrimaryServerId $manifest)) { "mysql -u root -p -h localhost -P $pp -D mysql" } else { "`"$(Join-WinPath $c.Dir 'bin\mysql.exe')`" -u root -p -h localhost -P $pp -D mysql" }
        Write-Host "  $($c.Label): $cmd"
        Write-Host "     detener: $(Join-WinPath $paths.Launchers ("stop-mysql-server$($c.Suffix).cmd"))"
    }
    Write-Host '  Abra una NUEVA consola para ver el PATH actualizado.'
    $failedOptional = @($toInstall | Where-Object { $_ -notin $ready })
    if ($failedOptional.Count -gt 0) { Write-Warn ("No quedaron instalados: " + (($failedOptional | ForEach-Object { $_.Label }) -join ', ')) }
    try { Stop-Transcript | Out-Null } catch { Write-Verbose 'Sin transcripción activa.' }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-Main; exit 0 }
    catch {
        $code = 1
        if ($_.Exception.Data -and $_.Exception.Data.Contains('Code')) { $code = [int]$_.Exception.Data['Code'] }
        Write-Bad $_.Exception.Message
        try { Stop-Transcript | Out-Null } catch { Write-Verbose 'Sin transcripción activa.' }
        exit $code
    }
}
#endregion
