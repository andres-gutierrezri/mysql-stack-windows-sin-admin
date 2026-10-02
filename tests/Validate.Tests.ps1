#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pruebas de validación del proyecto mysql-stack-windows-sin-admin (Pester 5).
    Ejecución (sin Administrador):
        Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
        Invoke-Pester -Path .\tests -Output Detailed
    Las pruebas de la etiqueta 'Integration' solo corren en Windows y no modifican el sistema (-DryRun).
    Autor: Ingeniero Andrés Felipe Gutiérrez Rivera
#>

BeforeDiscovery {
    $script:IsWin = ($env:OS -eq 'Windows_NT')
}

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:InstallPs1 = Join-Path $Root 'src/powershell/Install-MySQLStack.ps1'
    $script:UninstallPs1 = Join-Path $Root 'src/powershell/Uninstall-MySQLStack.ps1'
    $script:MenuPs1 = Join-Path $Root 'src/powershell/Show-MySQLStackMenu.ps1'
    $script:SourceFiles = Get-ChildItem -Path (Join-Path $Root 'src') -Recurse -File
    $script:CmdFiles = Get-ChildItem -Path (Join-Path $Root 'src/cmd') -Filter *.cmd
    # Se cargan las funciones SIN ejecutar el flujo principal (guarda $MyInvocation.InvocationName)
    . $script:InstallPs1
    $script:Cfg = Get-StackConfig -ProjectRoot $Root
    $script:FakeBase = 'C:\Programs\MySQL'
}

Describe 'Estructura del proyecto' {
    It 'contiene el archivo <_>' -ForEach @(
        'README.md', 'LICENSE', '.gitignore', '.gitattributes', '.env.example', 'requirements.txt', 'config/stack.env',
        'src/powershell/MySQLStack.Common.ps1', 'src/powershell/Install-MySQLStack.ps1', 'src/powershell/Uninstall-MySQLStack.ps1',
        'src/powershell/Enable-ScriptExecution.ps1', 'src/powershell/Show-MySQLStackMenu.ps1',
        'src/cmd/install_mysql_stack.cmd', 'src/cmd/uninstall_mysql_stack.cmd', 'src/cmd/enable_script_execution.cmd', 'src/cmd/mysql_stack_menu.cmd',
        'src/templates/mysql-console.cmd.tpl', 'src/templates/start-mysql-server.cmd.tpl', 'src/templates/stop-mysql-server.cmd.tpl',
        'tests/Validate.Tests.ps1', 'tests/validate_project.cmd',
        'docs/ARQUITECTURA.md', 'docs/REQUISITOS.md', 'docs/PRUEBAS.md', 'docs/LIMITACIONES.md', 'docs/PUBLICACION_GIT.md', 'docs/COMPONENTES_Y_MENU.md'
    ) {
        Join-Path $Root $_ | Should -Exist
    }
}

Describe 'Sintaxis y codificación' {
    It 'el script <_> no tiene errores de sintaxis' -ForEach @(
        'src/powershell/MySQLStack.Common.ps1', 'src/powershell/Install-MySQLStack.ps1', 'src/powershell/Uninstall-MySQLStack.ps1',
        'src/powershell/Enable-ScriptExecution.ps1', 'src/powershell/Show-MySQLStackMenu.ps1', 'tests/Validate.Tests.ps1'
    ) {
        $errs = $null; $tok = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $_), [ref]$tok, [ref]$errs)
        $errs.Count | Should -Be 0
    }
    It 'los .ps1 tienen BOM UTF-8 (Windows PowerShell 5.1 lee mal UTF-8 sin BOM)' {
        foreach ($f in $SourceFiles | Where-Object Extension -eq '.ps1') {
            $b = [IO.File]::ReadAllBytes($f.FullName)[0..2]
            ($b -join ',') | Should -Be '239,187,191' -Because $f.Name
        }
    }
    It 'los .cmd y .tpl son ASCII puro con saltos CRLF' {
        foreach ($f in $SourceFiles | Where-Object { $_.Extension -in '.cmd', '.tpl' }) {
            $bytes = [IO.File]::ReadAllBytes($f.FullName)
            @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0 -Because "$($f.Name) debe ser ASCII"
            $text = [Text.Encoding]::ASCII.GetString($bytes)
            ([regex]::Matches($text, "(?<!`r)`n")).Count | Should -Be 0 -Because "$($f.Name) debe usar CRLF"
        }
    }
    It 'las etiquetas de cada .cmd no se repiten y todo goto/call apunta a una etiqueta existente' {
        foreach ($f in $CmdFiles) {
            $t = Get-Content $f.FullName -Raw
            $labels = @([regex]::Matches($t, '(?m)^:([A-Za-z_]\w*)\s*$') | ForEach-Object { $_.Groups[1].Value })
            @($labels | Group-Object | Where-Object Count -gt 1).Count | Should -Be 0 -Because "$($f.Name): etiquetas duplicadas"
            $refs = @([regex]::Matches($t, '(?i)\b(?:goto|call)\s+:([A-Za-z_]\w*)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
            @($refs | Where-Object { $_ -notin $labels }).Count | Should -Be 0 -Because "$($f.Name): referencias sin etiqueta"
        }
    }
    It 'ningún .cmd usa "if (...) & otro" (el segundo comando se ejecutaría siempre)' {
        foreach ($f in $CmdFiles) {
            foreach ($line in (Get-Content $f.FullName)) {
                if ($line.TrimStart() -match '^(rem|::)') { continue }
                $line | Should -Not -Match '\)\s*&\s*(set|call|echo)\b' -Because "$($f.Name): $line"
            }
        }
    }
}

Describe 'Seguridad: nada requiere Administrador' {
    It 'ningún script contiene el patrón prohibido <_>' -ForEach @(
        'mysqld(\.exe)?"?\s+--install', '-Verb\s+RunAs', 'Set-ExecutionPolicy[^\r\n]*LocalMachine', 'New-Service\b', 'New-NetFirewallRule',
        '\bsc(\.exe)?\s+(create|config)\b', 'reg\s+add\s+"?HKLM', 'setx\s+[^\r\n]*/M\b', '\brunas\b', 'Set-ItemProperty\s+[^\r\n]*HKLM:'
    ) {
        $pattern = $_
        foreach ($f in $SourceFiles | Where-Object { $_.Extension -in '.ps1', '.cmd', '.tpl' }) {
            (Select-String -Path $f.FullName -Pattern $pattern -Quiet) | Should -BeFalse -Because "$($f.Name) no debe usar '$pattern'"
        }
    }
    It 'solo se abre el registro del equipo (HKLM) en modo de solo lectura' {
        foreach ($f in $SourceFiles | Where-Object { $_.Extension -in '.ps1', '.cmd' }) {
            foreach ($m in [regex]::Matches((Get-Content $f.FullName -Raw), "LocalMachine\.OpenSubKey\([^)]*\)")) {
                $m.Value | Should -Match '\$false' -Because "$($f.Name): $($m.Value)"
            }
        }
    }
    It 'el servidor se configura para escuchar solo en loopback (PowerShell y CMD)' {
        Format-MyIni -ServerDir 'C:\Programs\MySQL\server' -DataDir 'C:\Programs\MySQL\data' -Port 3306 -XPort 33060 | Should -Match 'bind-address=127\.0\.0\.1'
        Select-String -Path (Join-Path $Root 'src/cmd/install_mysql_stack.cmd') -Pattern 'bind-address=127\.0\.0\.1' -Quiet | Should -BeTrue
    }
}

Describe 'Configuración compartida (config/stack.env)' {
    It 'define las claves globales <_>' -ForEach @('STACK_ROOT_DEFAULT', 'DEFAULT_PORT', 'DEFAULT_XPORT', 'FALLBACK_ROOT_PASSWORD') { $Cfg.ContainsKey($_) | Should -BeTrue }
    It 'el componente <_> define todas sus claves' -ForEach @('SRV', 'WB', 'NOTIF', 'SRVLTS', 'WB8') {
        foreach ($f in 'LABEL', 'VERSION', 'KIND', 'URL', 'MD5', 'FILE', 'DIR', 'LINK', 'NEED_GB') { $Cfg.ContainsKey("${_}_$f") | Should -BeTrue -Because "${_}_$f" }
    }
    It 'las sumas MD5 tienen 32 caracteres hexadecimales y las URL son HTTPS de dominios de MySQL' {
        foreach ($id in Get-ComponentIds) {
            $Cfg["${id}_MD5"] | Should -Match '^[0-9a-f]{32}$' -Because $id
            $Cfg["${id}_URL"] | Should -Match '^https://(cdn|downloads|dev)\.mysql\.com/' -Because $id
        }
    }
    It 'las versiones fijadas son las solicitadas' {
        $Cfg['SRVLTS_VERSION'] | Should -Be '9.7.2'
        $Cfg['WB8_VERSION'] | Should -Be '8.0.47'
        $Cfg['SRV_VERSION'] | Should -Be '26.7.0'
        $Cfg['WB_VERSION'] | Should -Be '26.7.0'
        $Cfg['SRVLTS_URL'] | Should -Match '9\.7\.2'
        $Cfg['WB8_URL'] | Should -Match '8\.0\.47'
    }
    It 'la ruta por defecto es C:\Programs, el puerto 3306 y la contraseña de respaldo 1234567' {
        $Cfg['STACK_ROOT_DEFAULT'] | Should -Be 'C:\Programs'
        $Cfg['DEFAULT_PORT'] | Should -Be '3306'
        $Cfg['FALLBACK_ROOT_PASSWORD'] | Should -Be '1234567'
    }
    It 'ningún valor queda vacío (en CMD una línea "CLAVE=" es ambigua; se usa NONE)' {
        $raw = Get-Content (Join-Path $Root 'config/stack.env') | Where-Object { $_ -match '^[A-Z0-9_]+=' }
        @($raw | Where-Object { $_ -match '=\s*$' }).Count | Should -Be 0
    }
    It 'Get-StackConfig rechaza una configuración incompleta' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('cfg_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp 'config') -Force | Out-Null
        Set-Content (Join-Path $tmp 'config/stack.env') 'DEFAULT_PORT=3306'
        try { Get-StackConfig -ProjectRoot $tmp; throw 'no lanzó' } catch { $_.Exception.Data['Code'] | Should -Be 50 } finally { Remove-Item $tmp -Recurse -Force }
    }
}

Describe 'Aislamiento entre componentes (sin conflictos)' {
    BeforeAll { $script:Comps = @(Get-ComponentIds | ForEach-Object { Get-Component -Cfg $Cfg -Id $_ -Base $FakeBase }) }
    It 'son cinco componentes en un orden estable' { (Get-ComponentIds) -join ',' | Should -Be 'SRV,WB,NOTIF,SRVLTS,WB8' }
    It 'cada componente tiene una carpeta distinta' { @($Comps.Dir | Sort-Object -Unique).Count | Should -Be 5 }
    It 'carpetas y directorios de datos no se superponen ni se contienen' {
        $all = @($Comps | ForEach-Object { $_.Dir; $_.DataDir } | Where-Object { $_ })
        @($all | Sort-Object -Unique).Count | Should -Be $all.Count
        foreach ($a in $all) { foreach ($b in $all) { if ($a -ne $b) { Test-PathInside $a $b | Should -BeFalse -Because "$a dentro de $b" } } }
    }
    It 'cada servidor tiene su propio directorio de datos, sufijo de lanzadores y acceso directo' {
        $srv = @($Comps | Where-Object IsServer)
        $srv.Count | Should -Be 2
        @($srv.DataDir | Sort-Object -Unique).Count | Should -Be 2
        @($srv.Suffix | Sort-Object -Unique).Count | Should -Be 2
        @($Comps.Link | Sort-Object -Unique).Count | Should -Be 5
    }
    It 'Test-PathInside distingue "server" de "server-9.7-lts" (prefijo textual engañoso)' {
        Test-PathInside 'C:\Programs\MySQL\server-9.7-lts\bin\mysqld.exe' 'C:\Programs\MySQL\server' | Should -BeFalse
        Test-PathInside 'C:\Programs\MySQL\server\bin\mysqld.exe' 'C:\Programs\MySQL\server' | Should -BeTrue
    }
    It 'my.ini de cada servidor apunta a su propia carpeta, datos y puertos' {
        $a = Format-MyIni -ServerDir 'C:\Programs\MySQL\server' -DataDir 'C:\Programs\MySQL\data' -Port 3306 -XPort 33060
        $b = Format-MyIni -ServerDir 'C:\Programs\MySQL\server-9.7-lts' -DataDir 'C:\Programs\MySQL\data-9.7-lts' -Port 3307 -XPort 33061
        $a | Should -Match 'basedir=C:/Programs/MySQL/server\r?\n'
        $a | Should -Match 'datadir=C:/Programs/MySQL/data\r?\n'
        $b | Should -Match 'basedir=C:/Programs/MySQL/server-9\.7-lts'
        $b | Should -Match 'datadir=C:/Programs/MySQL/data-9\.7-lts'
        $b | Should -Match 'port=3307'
    }
}

Describe 'Selección de componentes' {
    It '<_> se resuelve correctamente' -ForEach @(
        @{ In = 'ALL'; Out = 'SRV,WB,NOTIF,SRVLTS,WB8' }, @{ In = 'LATEST'; Out = 'SRV,WB,NOTIF' }, @{ In = 'LTS'; Out = 'SRVLTS,WB8' },
        @{ In = 'srv'; Out = 'SRV' }, @{ In = 'WB8,SRV'; Out = 'SRV,WB8' }, @{ In = '3, 1 1'; Out = 'SRV,NOTIF' },
        @{ In = 'T'; Out = 'SRV,WB,NOTIF,SRVLTS,WB8' }, @{ In = 'U'; Out = 'SRV,WB,NOTIF' }, @{ In = 'L'; Out = 'SRVLTS,WB8' }, @{ In = '4,5'; Out = 'SRVLTS,WB8' }
    ) { (Resolve-ComponentSelection @($In)) -join ',' | Should -Be $Out }
    It 'un componente desconocido produce el error 50' {
        try { Resolve-ComponentSelection @('NOPE'); throw 'no lanzó' } catch { $_.Exception.Data['Code'] | Should -Be 50 }
    }
    It 'instalar uno no incluye a los demás (sin efectos laterales entre componentes)' {
        foreach ($id in Get-ComponentIds) { @(Resolve-ComponentSelection @($id)).Count | Should -Be 1 }
    }
}

Describe 'PATH de usuario: el servidor va ANTES de XAMPP MySQL' {
    BeforeAll {
        $script:Pat = Get-XamppPathPattern
        $script:Srv = 'C:\Programs\MySQL\server\bin'; $script:Lts = 'C:\Programs\MySQL\server-9.7-lts\bin'
        $script:Managed = @($Srv, $Lts)
    }
    It 'si existe C:\xampp\mysql\bin, inserta el servidor justo antes' {
        Set-PathPriority -PathValue 'C:\A;C:\xampp\mysql\bin;C:\B' -Entry $Srv -RemoveEntries $Managed -BeforePattern $Pat |
            Should -Be 'C:\A;C:\Programs\MySQL\server\bin;C:\xampp\mysql\bin;C:\B'
    }
    It 'reconoce XAMPP con mayúsculas, barra final y en otra unidad' {
        Set-PathPriority -PathValue 'C:\A;D:\XAMPP\MySQL\bin\' -Entry $Srv -RemoveEntries $Managed -BeforePattern $Pat | Should -Be 'C:\A;C:\Programs\MySQL\server\bin;D:\XAMPP\MySQL\bin\'
    }
    It 'si ya estaba DESPUÉS de XAMPP, lo reubica antes' {
        Set-PathPriority -PathValue 'C:\xampp\mysql\bin;C:\Programs\MySQL\server\bin;C:\B' -Entry $Srv -RemoveEntries $Managed -BeforePattern $Pat |
            Should -Be 'C:\Programs\MySQL\server\bin;C:\xampp\mysql\bin;C:\B'
    }
    It 'sin XAMPP lo agrega al final' {
        Set-PathPriority -PathValue 'C:\A;C:\B' -Entry $Srv -RemoveEntries $Managed -BeforePattern $Pat | Should -Be 'C:\A;C:\B;C:\Programs\MySQL\server\bin'
    }
    It 'es idempotente' {
        $once = Set-PathPriority -PathValue 'C:\A;C:\xampp\mysql\bin' -Entry $Srv -RemoveEntries $Managed -BeforePattern $Pat
        Set-PathPriority -PathValue $once -Entry $Srv -RemoveEntries $Managed -BeforePattern $Pat | Should -Be $once
    }
    It 'al cambiar de servidor primario (SRV -> LTS) no deja duplicados ni al otro servidor' {
        Set-PathPriority -PathValue 'C:\A;C:\Programs\MySQL\server\bin;C:\xampp\mysql\bin' -Entry $Lts -RemoveEntries $Managed -BeforePattern $Pat |
            Should -Be 'C:\A;C:\Programs\MySQL\server-9.7-lts\bin;C:\xampp\mysql\bin'
    }
    It 'al desinstalar solo quita las entradas del proyecto' {
        Set-PathPriority -PathValue 'C:\A;C:\Programs\MySQL\server\bin;C:\Programs\MySQL\server-9.7-lts\bin;C:\xampp\mysql\bin' -Entry '' -RemoveEntries $Managed |
            Should -Be 'C:\A;C:\xampp\mysql\bin'
    }
    It 'conserva las variables %VAR% sin expandirlas y tolera un PATH vacío' {
        Set-PathPriority -PathValue '%SystemRoot%\system32;C:\xampp\mysql\bin' -Entry $Srv -RemoveEntries $Managed -BeforePattern $Pat |
            Should -Be '%SystemRoot%\system32;C:\Programs\MySQL\server\bin;C:\xampp\mysql\bin'
        Set-PathPriority -PathValue '' -Entry $Srv -RemoveEntries $Managed -BeforePattern $Pat | Should -Be $Srv
    }
    It 'el patrón de XAMPP no coincide con otras carpetas de XAMPP' {
        foreach ($other in 'C:\xampp\php', 'C:\xampp\mysql\data', 'C:\xampp', 'C:\xampp\apache\bin') { Test-PathHasPattern $other $Pat | Should -BeFalse -Because $other }
        Test-PathHasPattern 'C:\xampp\mysql\bin' $Pat | Should -BeTrue
    }
    It 'Merge-PathEntry y Remove-PathEntry siguen siendo idempotentes' {
        $p = Merge-PathEntry 'C:\A;C:\B' $Srv
        Merge-PathEntry $p 'c:\programs\mysql\server\bin\' | Should -Be $p
        Remove-PathEntry $p $Srv | Should -Be 'C:\A;C:\B'
    }
}

Describe 'Servidor primario y manifiesto' {
    It 'la versión más reciente tiene prioridad sobre la LTS' {
        $m = @{}; Set-ComponentInstalled $m 'SRVLTS' 3307 33061; Get-PrimaryServerId $m | Should -Be 'SRVLTS'
        Set-ComponentInstalled $m 'SRV' 3306 33060; Get-PrimaryServerId $m | Should -Be 'SRV'
        Clear-ComponentState $m 'SRV'; Get-PrimaryServerId $m | Should -Be 'SRVLTS'
        Clear-ComponentState $m 'SRVLTS'; Get-PrimaryServerId $m | Should -Be ''
    }
    It 'desinstalar un componente no altera el estado de los demás' {
        $m = @{}; foreach ($id in Get-ComponentIds) { Set-ComponentInstalled $m $id 3306 33060 }
        Clear-ComponentState $m 'WB8'
        (Get-ComponentState $m 'WB8').Installed | Should -BeFalse
        foreach ($id in 'SRV', 'WB', 'NOTIF', 'SRVLTS') { (Get-ComponentState $m $id).Installed | Should -BeTrue -Because $id }
    }
    It 'migra el manifiesto v1 (PORT/XPORT/NOTIFIER) al formato por componente' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('mf_' + [guid]::NewGuid().ToString('N') + '.env')
        Set-Content $tmp @('BASE=C:\Programs\MySQL', 'PORT=3306', 'XPORT=33060', 'NOTIFIER=0', 'CREATED_ROOT=1', 'SERVER_VERSION=26.7.0')
        $m = Read-Manifest $tmp; Remove-Item $tmp
        (Get-ComponentState $m 'SRV').Port | Should -Be 3306
        (Get-ComponentState $m 'WB').Installed | Should -BeTrue
        (Get-ComponentState $m 'NOTIF').Installed | Should -BeFalse
        $m.ContainsKey('PORT') | Should -BeFalse
    }
    It 'Save-Manifest y Read-Manifest conservan los datos' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('mf_' + [guid]::NewGuid().ToString('N') + '.env')
        $m = @{ CREATED_ROOT = '1' }; Set-ComponentInstalled $m 'SRVLTS' 3310 33099
        Save-Manifest $tmp $m; $r = Read-Manifest $tmp; Remove-Item $tmp
        $r['CREATED_ROOT'] | Should -Be '1'
        (Get-ComponentState $r 'SRVLTS').Port | Should -Be 3310
        (Get-ComponentState $r 'SRVLTS').XPort | Should -Be 33099
    }
}

Describe 'Funciones puras del instalador' {
    It 'ConvertTo-SqlString escapa comilla simple y barra invertida' { ConvertTo-SqlString "a'b\c" | Should -Be "a''b\\c" }
    It 'ConvertTo-OptionValue escapa comilla doble y barra invertida' { ConvertTo-OptionValue 'a"b\c' | Should -Be 'a\"b\\c' }
    It 'Test-SafeInstallRoot acepta C:\Programs y rechaza rutas peligrosas' {
        Test-SafeInstallRoot 'C:\Programs' | Should -BeTrue
        foreach ($bad in 'C:\', 'C:', 'C:\Program Files', 'C:\a&b', 'C:\x%y', 'D:\x!y', '', 'relativa\ruta') { Test-SafeInstallRoot $bad | Should -BeFalse -Because $bad }
    }
    It 'Get-StackPaths agrupa todo bajo la carpeta MySQL de la raíz' {
        $p = Get-StackPaths 'C:\Programs'
        $p.Base | Should -Match 'MySQL$'
        foreach ($k in 'Launchers', 'Cache', 'Logs', 'Manifest') { $p[$k] | Should -BeLike "$($p.Base)*" }
    }
    It 'Read-EnvFile ignora comentarios y líneas vacías' {
        $f = Join-Path ([IO.Path]::GetTempPath()) ("t_" + [guid]::NewGuid().ToString('N') + '.env')
        Set-Content -Path $f -Value @('# comentario', '', 'A=1', ' B = dos ', 'C=x=y')
        $r = Read-EnvFile $f; Remove-Item $f
        $r['A'] | Should -Be '1'; $r['B'] | Should -Be 'dos'; $r['C'] | Should -Be 'x=y'; $r.Count | Should -Be 3
    }
    It 'New-StackError conserva el código de salida' { (New-StackError 20 'x').Data['Code'] | Should -Be 20 }
}

Describe 'Selección de puertos' {
    It 'Test-PortBindable devuelve falso para un puerto realmente ocupado' {
        $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
        $l.Start()
        try { Test-PortBindable ([int]$l.LocalEndpoint.Port) | Should -BeFalse } finally { $l.Stop() }
    }
    It 'con conflictos nunca usa 3306 ni 33060' {
        $r = Select-MySqlPorts -Requested 0 -HasConflicts $true -DefaultPort 3306 -DefaultXPort 33060 -Listening @()
        $r.Port | Should -BeGreaterThan 3306
        $r.XPort | Should -Not -Be 33060
        $r.XPort | Should -Not -Be $r.Port
    }
    It 'si 3306 está ocupado elige 3307 aunque no haya otras instalaciones' {
        (Select-MySqlPorts -Requested 0 -HasConflicts $false -DefaultPort 3306 -DefaultXPort 33060 -Listening @(3306)).Port | Should -Be 3307
    }
    It 'sin conflictos y con 3306 libre usa 3306 y 33060' {
        $r = Select-MySqlPorts -Requested 0 -HasConflicts $false -DefaultPort 3306 -DefaultXPort 33060 -Listening @()
        $r.Port | Should -Be 3306; $r.XPort | Should -Be 33060
    }
    It 'omite puertos ocupados al buscar alternativos' {
        (Select-MySqlPorts -Requested 0 -HasConflicts $true -DefaultPort 3306 -DefaultXPort 33060 -Listening @(3307, 3308, 3309)).Port | Should -Be 3310
    }
    It 'dos servidores instalados en secuencia reciben puertos distintos (el segundo ve al primero como conflicto)' {
        $first = Select-MySqlPorts -Requested 0 -HasConflicts $false -DefaultPort 3306 -DefaultXPort 33060 -Listening @()
        $second = Select-MySqlPorts -Requested 0 -HasConflicts $true -DefaultPort 3306 -DefaultXPort 33060 -Listening @($first.Port, $first.XPort)
        $first.Port | Should -Be 3306
        $second.Port | Should -Not -Be $first.Port
        $second.XPort | Should -Not -Be $first.XPort
    }
    It 'un puerto solicitado y ocupado produce el error 20' {
        try { Select-MySqlPorts -Requested 3400 -HasConflicts $false -DefaultPort 3306 -DefaultXPort 33060 -Listening @(3400); throw 'no lanzó' }
        catch { $_.Exception.Data['Code'] | Should -Be 20 }
    }
    It 'respeta un puerto solicitado libre' {
        (Select-MySqlPorts -Requested 3456 -HasConflicts $true -DefaultPort 3306 -DefaultXPort 33060 -Listening @()).Port | Should -Be 3456
    }
}

Describe 'Plantillas y contrato entre scripts PowerShell y CMD' {
    It 'la consola usa exactamente el comando solicitado y las plantillas están parametrizadas' {
        $t = Get-Content (Join-Path $Root 'src/templates/mysql-console.cmd.tpl') -Raw
        $t | Should -Match '-u root -p -h localhost -P %MYSQL_PORT% -D mysql'
        foreach ($tok in '@@BASE@@', '@@PORT@@', '@@SRVDIR@@', '@@DATADIR@@', '@@LABEL@@') { $t | Should -Match $tok }
    }
    It 'los lanzadores generados para cada servidor apuntan a su carpeta, datos y puerto' {
        foreach ($case in @(@{ Id = 'SRV'; Port = 3306 }, @{ Id = 'SRVLTS'; Port = 3307 })) {
            $c = Get-Component -Cfg $Cfg -Id $case.Id -Base $FakeBase
            $t = (Get-Content (Join-Path $Root 'src/templates/start-mysql-server.cmd.tpl') -Raw).
                Replace('@@BASE@@', $FakeBase).Replace('@@PORT@@', "$($case.Port)").Replace('@@SRVDIR@@', $c.DirName).Replace('@@DATADIR@@', $c.DataName).Replace('@@LABEL@@', $c.Label)
            $t | Should -Match ([regex]::Escape("\$($c.DirName)\bin\mysqld.exe"))
            $t | Should -Match ([regex]::Escape("\$($c.DataName)\mysql-error.log"))
            $t | Should -Match "MYSQL_PORT=$($case.Port)"
            $t | Should -Not -Match '@@'
        }
    }
    It 'ambos instaladores documentan el comando de conexión final' {
        foreach ($f in 'src/powershell/Install-MySQLStack.ps1', 'src/cmd/install_mysql_stack.cmd') {
            Select-String -Path (Join-Path $Root $f) -Pattern 'mysql -u root -p -h localhost -P' -Quiet | Should -BeTrue -Because $f
        }
    }
    It 'cada ayudante PowerShell embebido en los .cmd tiene marcadores BEGIN y END y es sintácticamente válido' {
        foreach ($f in $CmdFiles) {
            $txt = Get-Content $f.FullName -Raw
            $used = [regex]::Matches($txt, 'MS_HELPER=([A-Z]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
            foreach ($h in $used) {
                $txt | Should -Match "::#PS:${h}:BEGIN" -Because "$($f.Name): falta BEGIN de $h"
                $txt | Should -Match "::#PS:${h}:END"   -Because "$($f.Name): falta END de $h"
            }
            foreach ($m in [regex]::Matches($txt, '(?s)#PS:([A-Z]+):BEGIN(.*?)#PS:\1:END')) {
                $code = [regex]::Replace($m.Groups[2].Value, '(?m)^::', '')
                $errs = $null; $tok = $null
                [void][System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tok, [ref]$errs)
                $errs.Count | Should -Be 0 -Because "$($f.Name) bloque $($m.Groups[1].Value)"
            }
        }
    }
    It 'los instaladores implementan las 10 etapas' {
        foreach ($f in 'src/powershell/Install-MySQLStack.ps1', 'src/cmd/install_mysql_stack.cmd') {
            $txt = Get-Content (Join-Path $Root $f) -Raw
            foreach ($n in 1..10) { $txt | Should -Match "$n/10" -Because "$f etapa $n" }
        }
    }
    It 'PowerShell y CMD aceptan los mismos componentes y grupos' {
        $cmd = Get-Content (Join-Path $Root 'src/cmd/install_mysql_stack.cmd') -Raw
        foreach ($id in 'SRV', 'WB', 'NOTIF', 'SRVLTS', 'WB8') { $cmd | Should -Match "\b$id\b" }
        foreach ($g in 'ALL', 'LATEST', 'LTS') { $cmd | Should -Match "\b$g\b" }
        foreach ($f in $CmdFiles | Where-Object Name -in 'install_mysql_stack.cmd', 'uninstall_mysql_stack.cmd') { (Get-Content $f.FullName -Raw) | Should -Match '/COMPONENTS:' }
    }
}

Describe 'Los ayudantes PATHSET de los .cmd equivalen a Set-PathPriority (registro simulado)' {
    BeforeAll {
        $script:PathCases = @(
            @{ Raw = 'C:\A;C:\xampp\mysql\bin;C:\B'; Add = 'C:\Programs\MySQL\server\bin' },
            @{ Raw = 'C:\A;D:\XAMPP\MySQL\bin\'; Add = 'C:\Programs\MySQL\server\bin' },
            @{ Raw = 'C:\xampp\mysql\bin;C:\Programs\MySQL\server\bin;C:\B'; Add = 'C:\Programs\MySQL\server\bin' },
            @{ Raw = 'C:\A;C:\B'; Add = 'C:\Programs\MySQL\server\bin' },
            @{ Raw = 'C:\A;C:\Programs\MySQL\server\bin;C:\xampp\mysql\bin'; Add = 'C:\Programs\MySQL\server-9.7-lts\bin' },
            @{ Raw = '%SystemRoot%\system32;C:\xampp\mysql\bin'; Add = 'C:\Programs\MySQL\server\bin' },
            @{ Raw = 'C:\A;C:\Programs\MySQL\server\bin;C:\Programs\MySQL\server-9.7-lts\bin;C:\xampp\mysql\bin'; Add = '' },
            @{ Raw = ''; Add = 'C:\Programs\MySQL\server\bin' }
        )
        $script:Remove = 'C:\Programs\MySQL\server\bin;C:\Programs\MySQL\server-9.7-lts\bin'
    }
    It '<_> produce el mismo PATH que la función de PowerShell' -ForEach @('install_mysql_stack.cmd', 'uninstall_mysql_stack.cmd') {
        $file = Join-Path $Root "src/cmd/$_"
        $txt = Get-Content $file -Raw
        $m = [regex]::Match($txt, '(?s)#PS:PATHSET:BEGIN(.*?)#PS:PATHSET:END')
        $m.Success | Should -BeTrue
        $code = [regex]::Replace($m.Groups[1].Value, '(?m)^::', '')
        $code = [regex]::Replace($code, "\[Microsoft\.Win32\.Registry\]::CurrentUser\.OpenSubKey\([^)]*\)", '$global:FakeKey')
        $code = [regex]::Replace($code, "\[Microsoft\.Win32\.Registry\]::LocalMachine\.OpenSubKey\([^)]*\)", '$null')
        $global:FakeKey = New-Object psobject
        $global:FakeKey | Add-Member ScriptMethod GetValue { param($n, $d, $o) $global:FakePath }
        $global:FakeKey | Add-Member ScriptMethod SetValue { param($n, $v, $k) $global:FakePath = $v }
        $global:FakeKey | Add-Member ScriptMethod Close { }
        foreach ($case in $PathCases) {
            $global:FakePath = $case.Raw
            $env:MS_ADD = $case.Add; $env:MS_PORT = '3306'; $env:MS_REMOVE = $Remove
            & ([scriptblock]::Create($code)) *> $null
            $expected = Set-PathPriority -PathValue $case.Raw -Entry $case.Add -RemoveEntries ($Remove -split ';') -BeforePattern (Get-XamppPathPattern)
            $global:FakePath | Should -Be $expected -Because "$_ con PATH '$($case.Raw)'"
        }
        Remove-Item Env:MS_ADD, Env:MS_PORT, Env:MS_REMOVE -ErrorAction SilentlyContinue
        Remove-Variable FakeKey, FakePath -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'Ayudante PWSET del CMD (varios servidores, cliente mysql simulado)' -Skip:$IsWin {
    BeforeAll {
        $script:Fake = Join-Path ([IO.Path]::GetTempPath()) ('fakepw_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $Fake 'bin') | Out-Null
        $script:CallLog = Join-Path $Fake 'calls.log'
        $stub = @'
#!/bin/bash
LOG="$(dirname "$0")/../calls.log"
echo "ARGS: $*" >> "$LOG"
sql=$(cat); echo "SQL: $sql" >> "$LOG"
case "$sql" in *FAIL_ME*) exit 1;; esac
exit 0
'@
        $script:Exe = Join-Path $Fake 'bin/mysql.exe'
        [IO.File]::WriteAllText($Exe, ($stub -replace "`r", ''))
        chmod +x $Exe
        $txt = Get-Content (Join-Path $Root 'src/cmd/install_mysql_stack.cmd') -Raw
        $m = [regex]::Match($txt, '(?s)#PS:PWSET:BEGIN(.*?)#PS:PWSET:END')
        $script:PwScript = Join-Path $Fake 'pwset.ps1'
        [IO.File]::WriteAllText($PwScript, [regex]::Replace($m.Groups[1].Value, '(?m)^::', ''))
        $script:Pwsh = (Get-Process -Id $PID).Path
    }
    AfterAll { Remove-Item $Fake -Recurse -Force -ErrorAction SilentlyContinue }
    BeforeEach { Remove-Item $CallLog -ErrorAction SilentlyContinue }

    It 'modo fallback: aplica 1234567 a TODOS los servidores y devuelve 0' {
        $env:TEMP = $Fake; $env:MS_FALLBACK = '1234567'; $env:MS_PWMODE = 'fallback'; $env:MS_TARGETS = "$Exe|3306;$Exe|3307"
        & $Pwsh -NoProfile -File $PwScript *> $null
        $LASTEXITCODE | Should -Be 0
        $log = Get-Content $CallLog -Raw
        $log | Should -Match '--port=3306'; $log | Should -Match '--port=3307'
        ([regex]::Matches($log, "IDENTIFIED BY '1234567'")).Count | Should -Be 2
    }
    It 'modo blank: solo comprueba la conexión (SELECT 1) en cada servidor' {
        $env:TEMP = $Fake; $env:MS_PWMODE = 'blank'; $env:MS_TARGETS = "$Exe|3306;$Exe|3307"
        & $Pwsh -NoProfile -File $PwScript *> $null
        $LASTEXITCODE | Should -Be 0
        ([regex]::Matches((Get-Content $CallLog -Raw), 'SELECT 1;')).Count | Should -Be 2
        (Get-Content $CallLog -Raw) | Should -Not -Match 'ALTER USER'
    }
    It 'si un servidor falla devuelve 1' {
        $env:TEMP = $Fake; $env:MS_FALLBACK = 'FAIL_ME'; $env:MS_PWMODE = 'fallback'; $env:MS_TARGETS = "$Exe|3306"
        & $Pwsh -NoProfile -File $PwScript *> $null
        $LASTEXITCODE | Should -Be 1
    }
}

Describe 'Asignación de la contraseña de root (cliente mysql simulado)' -Skip:$IsWin {
    BeforeAll {
        $script:Fake2 = Join-Path ([IO.Path]::GetTempPath()) ('fakemysql_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $Fake2 'server/bin'), (Join-Path $Fake2 'tmp') | Out-Null
        $script:CallLog2 = Join-Path $Fake2 'calls.log'
        $stub = @'
#!/bin/bash
LOG="$(dirname "$0")/../../calls.log"
echo "ARGS: $*" >> "$LOG"
sql=$(cat); echo "SQL: $sql" >> "$LOG"
case "$sql" in *FAIL_ME*) echo "ERROR 1819" >&2; exit 1;; esac
exit 0
'@
        $exe = Join-Path $Fake2 'server/bin/mysql.exe'
        [IO.File]::WriteAllText($exe, ($stub -replace "`r", ''))
        chmod +x $exe
        $script:OldTemp = $env:TEMP; $env:TEMP = (Join-Path $Fake2 'tmp')
        $script:FakePaths = @{ Server = (Join-Path $Fake2 'server') }
    }
    AfterAll { $env:TEMP = $OldTemp; Remove-Item $Fake2 -Recurse -Force -ErrorAction SilentlyContinue }
    BeforeEach { Remove-Item $CallLog2 -ErrorAction SilentlyContinue }

    It 'escapa comilla simple y barra invertida en el ALTER USER' {
        $sec = ConvertTo-SecureString -String ("p'a" + [char]34 + "s" + [char]92 + "s") -AsPlainText -Force
        Set-RootPassword -Paths $FakePaths -Port 3307 -Choice ([pscustomobject]@{ Mode = 'Custom'; Secure = $sec }) -Fallback '1234567' | Should -Be 'custom'
        $esperado = "IDENTIFIED BY 'p''a" + [char]34 + "s" + [char]92 + [char]92 + "s'"
        (Get-Content $CallLog2 -Raw) | Should -Match ([regex]::Escape($esperado))
    }
    It 'usa --skip-password mientras root no tiene contraseña' {
        Set-RootPassword -Paths $FakePaths -Port 3307 -Choice ([pscustomobject]@{ Mode = 'Blank'; Secure = $null }) -Fallback '1234567' | Should -Be 'blank'
        (Get-Content $CallLog2 -Raw) | Should -Match '--skip-password'
    }
    It 'si el servidor rechaza la contraseña indicada aplica el respaldo 1234567' {
        $sec = ConvertTo-SecureString -String 'FAIL_ME' -AsPlainText -Force
        Set-RootPassword -Paths $FakePaths -Port 3307 -Choice ([pscustomobject]@{ Mode = 'Custom'; Secure = $sec }) -Fallback '1234567' 3>$null | Should -Be 'fallback'
        (Get-Content $CallLog2 -Raw) | Should -Match "IDENTIFIED BY '1234567'"
    }
    It 'no deja archivos temporales con secretos' {
        $sec = ConvertTo-SecureString -String 'Secreta1' -AsPlainText -Force
        [void](Set-RootPassword -Paths $FakePaths -Port 3307 -Choice ([pscustomobject]@{ Mode = 'Custom'; Secure = $sec }) -Fallback '1234567')
        @(Get-ChildItem $env:TEMP -Filter 'msq_*').Count | Should -Be 0
    }
}

Describe 'Protección del desinstalador' {
    BeforeAll { . $script:UninstallPs1 }
    It 'Test-SafeRemovalTarget solo acepta exactamente la carpeta MySQL de la raíz' {
        Test-SafeRemovalTarget 'C:\Programs\MySQL' 'C:\Programs' | Should -BeTrue
        foreach ($t in @(@('C:\Programs', 'C:\Programs'), @('C:\', 'C:\'), @('C:\Windows', 'C:\Programs'), @('C:\Programs\MySQL\server', 'C:\Programs'), @('C:\MySQL', 'C:\'))) {
            Test-SafeRemovalTarget $t[0] $t[1] | Should -BeFalse -Because ($t -join ' | ')
        }
    }
    It 'Test-SafeChildTarget solo acepta carpetas permitidas directamente bajo la base' {
        $allowed = @('server', 'data', 'server-9.7-lts', 'data-9.7-lts', 'workbench', 'workbench-8.0.47', 'notifier')
        foreach ($ok in 'server', 'server-9.7-lts', 'data-9.7-lts', 'workbench-8.0.47') { Test-SafeChildTarget "C:\Programs\MySQL\$ok" 'C:\Programs\MySQL' $allowed | Should -BeTrue -Because $ok }
        foreach ($bad in 'C:\Programs\MySQL', 'C:\Programs\MySQL\logs', 'C:\Programs\MySQL\server\bin', 'C:\Windows\server', 'C:\Programs\MySQL2\server', 'C:\Programs\MySQL\..\server') {
            Test-SafeChildTarget $bad 'C:\Programs\MySQL' $allowed | Should -BeFalse -Because $bad
        }
    }
    It 'todas las carpetas de componentes de la configuración están permitidas' {
        $allowed = @(Get-ComponentIds | ForEach-Object { $Cfg["${_}_DIR"]; $Cfg["${_}_DATADIR"] } | Where-Object { $_ -and $_ -ne 'NONE' })
        foreach ($id in Get-ComponentIds) { Test-SafeChildTarget (Join-WinPath 'C:\Programs\MySQL' $Cfg["${id}_DIR"]) 'C:\Programs\MySQL' $allowed | Should -BeTrue -Because $id }
    }
}

Describe 'Integración en Windows (simulación, no modifica el sistema)' -Tag 'Integration' -Skip:(-not $IsWin) {
    It 'Install-MySQLStack.ps1 -DryRun -Components ALL termina con 0 o con un código de requisitos documentado' {
        $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$InstallPs1`"", '-Components', 'ALL', '-DryRun', '-NoPrompt') -Wait -PassThru -NoNewWindow
        $p.ExitCode | Should -BeIn @(0, 10, 20)
    }
    It 'install_mysql_stack.cmd /COMPONENTS:SRVLTS+WB8 /DRYRUN termina con 0 o con un código documentado' {
        $cmd = Join-Path $Root 'src\cmd\install_mysql_stack.cmd'
        $p = Start-Process cmd.exe -ArgumentList @('/c', "`"$cmd`"", '/COMPONENTS:SRVLTS+WB8', '/DRYRUN', '/NOPROMPT') -Wait -PassThru -NoNewWindow
        $p.ExitCode | Should -BeIn @(0, 10, 20)
    }
    It 'Uninstall-MySQLStack.ps1 -Components WB8 -DryRun -Yes no modifica nada y termina con 0' {
        $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$UninstallPs1`"", '-Components', 'WB8', '-DryRun', '-Yes') -Wait -PassThru -NoNewWindow
        $p.ExitCode | Should -Be 0
    }
    It 'el menú en modo Status termina con 0' {
        $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$MenuPs1`"", '-Action', 'Status') -Wait -PassThru -NoNewWindow
        $p.ExitCode | Should -Be 0
    }
}
