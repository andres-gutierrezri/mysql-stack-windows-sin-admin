#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pruebas de orquestación: ejecutan Invoke-Main (instalador) de principio a fin con TODAS las
    operaciones del sistema simuladas (descargas, servidores, registro, accesos directos).
    Verifican el flujo, los puertos, el manifiesto, el PATH y que instalar/desinstalar un componente
    no afecte a los demás. Funcionan en cualquier sistema operativo.
    Autor: Ingeniero Andrés Felipe Gutiérrez Rivera
#>

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path $Root 'src/powershell/Install-MySQLStack.ps1')

    # ---- Estado simulado -------------------------------------------------------------------
    $script:Mem = @{}              # manifiesto en memoria
    $script:Disk = @{}             # carpetas "existentes"
    $script:Calls = New-Object System.Collections.Generic.List[string]
    $script:UserPath = ''
    $script:Third = @()
    $script:Listening = @()

    # ---- Simulaciones de todo lo que toca el sistema ---------------------------------------------
    function Enable-ScriptExecution { param($ProjectRoot, [switch]$Plan) }
    function Get-PrerequisiteReport { param($Root, $Cfg, $Selected) return @([pscustomobject]@{ Name = 'x'; Status = 'OK'; Detail = 'simulado'; Critical = $true }) }
    function Find-ThirdPartyInstallations { param($Base) return @($script:Third) }
    function Get-ListeningPorts { return @($script:Listening) }
    function Test-PortBindable([int]$Port) { return $true }
    function Test-WritableRoot { param($Root, [switch]$Create) return $true }
    function Read-Manifest([string]$Path) { return (ConvertFrom-LegacyManifest ($script:Mem.Clone())) }
    function Save-Manifest { param([string]$Path, [hashtable]$Manifest) $script:Mem = $Manifest.Clone() }
    function Get-ComponentInstallState { param($Comp, [hashtable]$Manifest)
        $flag = (Get-ComponentState $Manifest $Comp.Id).Installed
        $exists = $script:Disk.ContainsKey($Comp.Id)
        if ($flag -and $exists) { return 'Installed' }; if ($flag -or $exists) { return 'Partial' }; return 'Absent' }
    function Stop-ProcessesInside([string]$Folder) { return 0 }
    function Install-ServerPackage { param($Paths, $Comp) $script:Disk[$Comp.Id] = $true; $script:Calls.Add("server:$($Comp.Id)") }
    function Install-WorkbenchZipPackage { param($Paths, $Comp) $script:Disk[$Comp.Id] = $true; $script:Calls.Add("wbzip:$($Comp.Id)") }
    function Install-MsiImagePackage { param($Paths, $Comp, [string]$ExeName, [switch]$Optional)
        if ($Comp.Id -eq 'NOTIF' -and $script:NotifierFails) { return $false }
        $script:Disk[$Comp.Id] = $true; $script:Calls.Add("msi:$($Comp.Id)"); return $true }
    function Write-MyIni { param($Comp, [int]$Port, [int]$XPort) $script:Calls.Add("ini:$($Comp.Id):${Port}:${XPort}") }
    function Initialize-DataDirectory { param($Comp) $script:Calls.Add("init:$($Comp.Id)") }
    function Start-MySqlServer { param($Comp, [int]$Port) $script:Calls.Add("start:$($Comp.Id):$Port") }
    function Read-RootPasswordChoice { return [pscustomobject]@{ Mode = 'Fallback'; Secure = $null } }
    function Set-RootPassword { param($Paths, [int]$Port, $Choice, [string]$Fallback) $script:Calls.Add("pw:$Port"); return 'fallback' }
    function New-LauncherFiles { param($Paths, $Comp, [int]$Port) $script:Calls.Add("launchers:$($Comp.Id)") }
    function New-ComponentShortcut { param($Paths, $Comp) $script:Calls.Add("lnk:$($Comp.Link)") }
    function Get-UserPathRaw { return $script:UserPath }
    function Set-UserPathRaw([string]$Value) { $script:UserPath = $Value }
    function Get-MachinePathRaw { return $script:MachinePath }
    function Start-Transcript { param($Path) }
    function Stop-Transcript { }
    function Remove-Item { param([Parameter(ValueFromRemainingArguments)]$a) }   # no borrar nada real

    function Reset-World {
        $script:Mem = @{}; $script:Disk = @{}; $script:Calls.Clear(); $script:UserPath = 'C:\Windows\system32;C:\Tools'
        $script:MachinePath = 'C:\Windows'; $script:Third = @(); $script:Listening = @(); $script:NotifierFails = $false
        $script:Components = @(); $script:InstallRoot = 'C:\Programs'; $script:Port = 0; $script:DryRun = [switch]$false
        $script:Force = [switch]$false; $script:SkipNotifier = [switch]$false; $script:FixPathOnly = [switch]$false
        [Environment]::SetEnvironmentVariable('MYSQL_TCP_PORT', $null, 'Process')
    }
    function New-Item { param([Parameter(ValueFromRemainingArguments)]$a) }       # no crear carpetas reales
    function Invoke-Scenario([scriptblock]$Setup) {
        Reset-World
        if ($Setup) { & $Setup }
        # Variables locales: Invoke-Main las ve por ámbito dinámico y tienen prioridad sobre los parámetros del script cargado
        $Components = $script:Components; $InstallRoot = $script:InstallRoot; $Port = $script:Port
        $DryRun = $script:DryRun; $Force = $script:Force; $SkipNotifier = $script:SkipNotifier; $FixPathOnly = $script:FixPathOnly
        $BlankPassword = [switch]$false; $NoPrompt = [switch]$true
        $out = Invoke-Main *>&1 | Out-String
        return $out
    }
    $script:Port = 0
}

Describe 'Instalación individual y en conjunto' {
    It 'LATEST (por defecto): servidor 26.7 en 3306, Workbench 26.7 y Notifier; PATH al final' {
        $out = Invoke-Scenario { }
        $Mem['SRV_INSTALLED'] | Should -Be '1'; $Mem['SRV_PORT'] | Should -Be '3306'; $Mem['SRV_XPORT'] | Should -Be '33060'
        $Mem['WB_INSTALLED'] | Should -Be '1'; $Mem['NOTIF_INSTALLED'] | Should -Be '1'
        $Mem.ContainsKey('SRVLTS_INSTALLED') | Should -BeFalse; $Mem.ContainsKey('WB8_INSTALLED') | Should -BeFalse
        $UserPath | Should -Be 'C:\Windows\system32;C:\Tools;C:\Programs\MySQL\server\bin'
        $out | Should -Match 'INSTALACIÓN COMPLETADA'
        ($Calls -join ',') | Should -Match 'pw:3306'
    }
    It 'solo el servidor LTS: toma 3306, es el primario y no instala nada más' {
        Invoke-Scenario { $script:Components = @('SRVLTS') } | Out-Null
        $Mem['SRVLTS_INSTALLED'] | Should -Be '1'; $Mem['SRVLTS_PORT'] | Should -Be '3306'
        $Mem.ContainsKey('SRV_INSTALLED') | Should -BeFalse
        $UserPath | Should -Match 'MySQL\\server-9\.7-lts\\bin$'
        $env:MYSQL_TCP_PORT | Should -Be '3306'
        @($Calls | Where-Object { $_ -like 'lnk:*' }).Count | Should -Be 1
    }
    It 'solo Workbench 8.0.47: no toca servidores, PATH ni contraseña' {
        Invoke-Scenario { $script:Components = @('WB8') } | Out-Null
        $Mem['WB8_INSTALLED'] | Should -Be '1'
        @($Calls | Where-Object { $_ -like 'server:*' -or $_ -like 'start:*' -or $_ -like 'pw:*' }).Count | Should -Be 0
        $UserPath | Should -Be 'C:\Windows\system32;C:\Tools'
        ($Calls -join ',') | Should -Match 'lnk:MySQL Workbench 8\.0\.47'
    }
    It 'ALL: instala los cinco; el segundo servidor recibe otro puerto y la misma contraseña se aplica a ambos' {
        Invoke-Scenario { $script:Components = @('ALL') } | Out-Null
        foreach ($id in Get-ComponentIds) { $Mem["${id}_INSTALLED"] | Should -Be '1' -Because $id }
        $Mem['SRV_PORT'] | Should -Be '3306'
        [int]$Mem['SRVLTS_PORT'] | Should -BeGreaterThan 3306
        $Mem['SRVLTS_PORT'] | Should -Not -Be $Mem['SRV_PORT']
        $Mem['SRVLTS_XPORT'] | Should -Not -Be $Mem['SRV_XPORT']
        @($Calls | Where-Object { $_ -like 'pw:*' }).Count | Should -Be 2
        @($Calls | Where-Object { $_ -like 'lnk:*' }).Count | Should -Be 5
        @($Calls | Where-Object { $_ -like 'launchers:*' }).Count | Should -Be 2
        @($UserPath -split ';' | Where-Object { $_ -like '*MySQL*' }).Count | Should -Be 1 -Because 'solo el servidor primario va en el PATH'
        $UserPath | Should -Match 'MySQL\\server\\bin$'
    }
    It 'LTS completo: servidor 9.7.2 + Workbench 8.0.47' {
        Invoke-Scenario { $script:Components = @('LTS') } | Out-Null
        $Mem['SRVLTS_INSTALLED'] | Should -Be '1'; $Mem['WB8_INSTALLED'] | Should -Be '1'
        $Mem.ContainsKey('SRV_INSTALLED') | Should -BeFalse
    }
}

Describe 'Convivencia con lo ya instalado (sin conflictos)' {
    It 'instalar el LTS con el servidor reciente ya instalado: no lo toca y usa otro puerto' {
        $out = Invoke-Scenario {
            $script:Mem = @{ SRV_INSTALLED = '1'; SRV_PORT = '3306'; SRV_XPORT = '33060'; WB_INSTALLED = '1' }
            $script:Disk = @{ SRV = $true; WB = $true }
            $script:UserPath = 'C:\Tools;C:\Programs\MySQL\server\bin'
            $script:Components = @('SRVLTS')
        }
        $Mem['SRV_PORT'] | Should -Be '3306'; $Mem['SRV_INSTALLED'] | Should -Be '1'
        $Mem['SRVLTS_PORT'] | Should -Not -Be '3306'
        ($Calls -join ',') | Should -Not -Match 'server:SRV(,|$)'
        $UserPath | Should -Be 'C:\Tools;C:\Programs\MySQL\server\bin' -Because 'el primario sigue siendo SRV y su PATH no cambia'
        $out | Should -Match 'Otros componentes del proyecto ya instalados'
    }
    It 'instalar el servidor reciente con el LTS ya instalado: se convierte en el primario del PATH' {
        Invoke-Scenario {
            $script:Mem = @{ SRVLTS_INSTALLED = '1'; SRVLTS_PORT = '3306'; SRVLTS_XPORT = '33060' }
            $script:Disk = @{ SRVLTS = $true }
            $script:UserPath = 'C:\Tools;C:\Programs\MySQL\server-9.7-lts\bin'
            $script:Components = @('SRV')
        } | Out-Null
        $Mem['SRV_PORT'] | Should -Not -Be '3306' -Because '3306 está reservado por el LTS instalado'
        $UserPath | Should -Be 'C:\Tools;C:\Programs\MySQL\server\bin'
        $env:MYSQL_TCP_PORT | Should -Be $Mem['SRV_PORT']
    }
    It 'instalar "todo" cuando ya está todo: no hace nada' {
        $out = Invoke-Scenario {
            foreach ($id in Get-ComponentIds) { $script:Mem["${id}_INSTALLED"] = '1'; $script:Disk[$id] = $true }
            $script:Mem['SRV_PORT'] = '3306'; $script:Mem['SRVLTS_PORT'] = '3307'; $script:Components = @('ALL')
        }
        $out | Should -Match 'No hay nada que instalar'
        $Calls.Count | Should -Be 0
    }
    It 'instalar "todo" con parte instalada: instala solo lo que falta' {
        Invoke-Scenario {
            $script:Mem = @{ SRV_INSTALLED = '1'; SRV_PORT = '3306'; SRV_XPORT = '33060'; WB_INSTALLED = '1' }
            $script:Disk = @{ SRV = $true; WB = $true }
            $script:Components = @('ALL')
        } | Out-Null
        ($Calls | Where-Object { $_ -like 'server:*' -or $_ -like 'wbzip:*' -or $_ -like 'msi:*' }) -join ',' | Should -Be 'msi:NOTIF,server:SRVLTS,msi:WB8'
    }
    It '-Force reinstala un componente instalado' {
        Invoke-Scenario {
            $script:Mem = @{ WB_INSTALLED = '1' }; $script:Disk = @{ WB = $true }
            $script:Components = @('WB'); $script:Force = [switch]$true
        } | Out-Null
        ($Calls -join ',') | Should -Match 'wbzip:WB'
    }
    It 'una instalación incompleta (carpeta sin manifiesto) se reinstala' {
        $out = Invoke-Scenario { $script:Disk = @{ WB = $true }; $script:Components = @('WB') }
        $out | Should -Match 'incompleta'
        ($Calls -join ',') | Should -Match 'wbzip:WB'
    }
    It 'con XAMPP o MySQL de terceros, el primer servidor no usa 3306' {
        Invoke-Scenario { $script:Components = @('SRV'); $script:Third = @([pscustomobject]@{ Kind = 'XAMPP'; Name = 'C:\xampp'; Detail = 'Carpeta existente' }) } | Out-Null
        $Mem['SRV_PORT'] | Should -Not -Be '3306'
    }
    It 'si el puerto 3306 está ocupado por otro programa, usa uno libre' {
        Invoke-Scenario { $script:Components = @('SRV'); $script:Listening = @(3306, 3307) } | Out-Null
        $Mem['SRV_PORT'] | Should -Be '3308'
    }
    It '-SkipNotifier excluye Notifier; si falla la extracción de Notifier el resto se instala' {
        Invoke-Scenario { $script:SkipNotifier = [switch]$true } | Out-Null
        $Mem.ContainsKey('NOTIF_INSTALLED') | Should -BeFalse; $Mem['SRV_INSTALLED'] | Should -Be '1'
        $out = Invoke-Scenario { $script:NotifierFails = $true }
        $Mem.ContainsKey('NOTIF_INSTALLED') | Should -BeFalse; $Mem['SRV_INSTALLED'] | Should -Be '1'; $Mem['WB_INSTALLED'] | Should -Be '1'
        $out | Should -Match 'No quedaron instalados: MySQL Notifier'
    }
}

Describe 'PATH y XAMPP durante la instalación' {
    It 'con C:\xampp\mysql\bin en el PATH de usuario, el servidor queda inmediatamente antes' {
        $out = Invoke-Scenario { $script:Components = @('SRV'); $script:UserPath = 'C:\Windows\system32;C:\xampp\mysql\bin;C:\Tools' }
        $UserPath | Should -Be 'C:\Windows\system32;C:\Programs\MySQL\server\bin;C:\xampp\mysql\bin;C:\Tools'
        $out | Should -Match 'ANTES de la entrada de XAMPP'
    }
    It 'si XAMPP está en el PATH del equipo, avisa que no se puede superar sin Administrador' {
        $out = Invoke-Scenario { $script:Components = @('SRV'); $script:MachinePath = 'C:\Windows;C:\xampp\mysql\bin' }
        $out | Should -Match 'PATH del EQUIPO'
    }
    It '-FixPathOnly reordena si XAMPP se agregó después' {
        $out = Invoke-Scenario {
            $script:Mem = @{ SRV_INSTALLED = '1'; SRV_PORT = '3306' }
            $script:UserPath = 'C:\xampp\mysql\bin;C:\Programs\MySQL\server\bin'
            $script:FixPathOnly = [switch]$true
        }
        $UserPath | Should -Be 'C:\Programs\MySQL\server\bin;C:\xampp\mysql\bin'
    }
}

Describe 'Simulación y selección' {
    It '-DryRun no instala nada ni modifica el manifiesto ni el PATH' {
        $out = Invoke-Scenario { $script:Components = @('ALL'); $script:DryRun = [switch]$true }
        $Calls.Count | Should -Be 0; $Mem.Count | Should -Be 0; $UserPath | Should -Be 'C:\Windows\system32;C:\Tools'
        $out | Should -Match 'Simulación completada'
        $out | Should -Match 'Servidor primario \(PATH\): SRV'
        $out | Should -Match 'mysql -u root -p -h localhost -P 3306 -D mysql'
    }
    It 'un componente desconocido termina con el código 50' {
        try { Invoke-Scenario { $script:Components = @('NOPE') } | Out-Null; throw 'no lanzó' } catch { $_.Exception.Data['Code'] | Should -Be 50 }
    }
}
