# Requisitos y verificaciones previas

Todas las verificaciones se ejecutan **sin Administrador** (lectura de registro, sondas de escritura, `netstat`, conexiones HTTP).

## Condiciones evaluadas (etapa 2)

| Condición | Criterio | ¿Bloquea? | Cómo se resuelve si falla |
|---|---|---|---|
| Sistema operativo | Windows 11, compilación ≥ 22000 | Sí | Usar Windows 11 |
| Arquitectura | Windows x64 y consola de 64 bits | Sí | Abrir PowerShell/CMD de 64 bits |
| PowerShell | ≥ 5.1 (solo `.ps1`) | Sí | Incluido en Windows 11 |
| Modo de lenguaje | `FullLanguage` (no *Constrained*) | Sí | Indica WDAC/AppLocker estricto: pedir excepción a TI |
| **Runtime Visual C++ x64** | Clave `…\VC\Runtimes\x64` y `vcruntime140.dll`, `vcruntime140_1.dll`, `msvcp140.dll` | Sí | `vc_redist.x64.exe` **exige Administrador**: pedir a TI o usar un equipo que ya lo tenga |
| .NET Framework 4.5.2+ | `Release` ≥ 379893 | No (aviso si se selecciona Notifier o Workbench 8.0.47) | Incluido en Windows 11 |
| Ruta de instalación | `^[A-Za-z]:\[A-Za-z0-9_.\-\\]+$`, sin espacios ni `& ^ % !` | Sí | Elegir otra ruta |
| Permiso de escritura | Crear y borrar una carpeta de sondeo en la raíz de la unidad | Sí | Por defecto Windows permite a «Usuarios autenticados» crear carpetas en `C:\`; si no, elegir otra unidad con `-InstallRoot` |
| Espacio libre | ≥ suma de `<ID>_NEED_GB` de los componentes **seleccionados** (servidor 3 GB, Workbench 26.7 3 GB, Workbench 8.0.47 4 GB, Notifier 1 GB) | Sí | Liberar espacio |
| `curl.exe` / `tar.exe` / `msiexec.exe` | En `System32` desde Windows 10 1803 | curl: sí en CMD · tar: no · msiexec: solo si se selecciona Notifier o Workbench 8.0.47 | PowerShell usa `WebClient`/`Expand-Archive` como respaldo |
| Red | HTTP 200 a `cdn.mysql.com` | Sí | Revisar proxy/firewall corporativo |
| Firewall de Windows | Informativo; `mysqld` solo escucha en `127.0.0.1` | No | — |
| AppLocker / Restricción de software | Claves de directiva en `HKLM\SOFTWARE\Policies` | No (aviso) | Si bloquean `mysqld.exe`, la prueba `--version` de la etapa 7 lo revela |
| Servicio de Windows | Informativo: no se puede crear sin Administrador | No | Usar los lanzadores |
| Cuenta | Aviso si está elevada o es de dominio | No | — |

## Detección de instalaciones previas (etapas 3 y 4)

**Ajeno al proyecto** (provoca puerto alternativo; no impide instalar):

| Producto | Señales |
|---|---|
| MySQL / MariaDB / Workbench / Notifier de terceros | Claves *Uninstall* (HKLM, WOW6432Node, HKCU), carpetas `Program Files\MySQL`, `ProgramData\MySQL`, servicios `MySQL*`/`MariaDB*`, procesos `mysqld`, `MySQLNotifier`, `MySQLWorkbench` **fuera de `C:\Programs\MySQL`**, variable `MYSQL_HOME` |
| XAMPP | Carpeta `\xampp` en las unidades fijas, procesos `xampp-control`, `httpd`, y la entrada `…\xampp\mysql\bin` en el PATH de usuario |
| WampServer | Carpetas `\wamp64` / `\wamp`, servicios `wamp*`, proceso `wampmanager` |

**Propio del proyecto** (por componente, a partir del manifiesto y de la carpeta):

| Estado | Significado | Acción |
|---|---|---|
| Instalado | Marca en el manifiesto **y** carpeta existente | Se omite (`-Force` / `/FORCE` lo reinstala) |
| Incompleto | Carpeta sin marca, o marca sin carpeta | Se reinstala |
| Ausente | Ninguna de las dos | Se instala |

> En el CMD solo se exploran las unidades C–H para XAMPP/WAMP; la versión PowerShell recorre todas las unidades fijas.

## Regla de puertos (etapa 5, por servidor)

1. Puerto solicitado (`-Port` / `/PORT:n` / `MYSQL_PORT`) → solo para el **primer** servidor de la ejecución; debe estar libre o error 20.
2. **Sin** otras instalaciones (ni de terceros, ni otro servidor del proyecto instalado o seleccionado antes) y 3306 libre → **3306**.
3. En otro caso → el primer puerto libre de **3307–3399**.
4. Puerto del protocolo X: 33060 si es posible; con conflictos, el primero libre desde 33061.
5. Los puertos de los servidores del proyecto ya instalados (aunque estén detenidos) y los asignados antes en la misma ejecución quedan **reservados**.

PowerShell, además de consultar los puertos en escucha, **intenta enlazar** el puerto en loopback antes de elegirlo.

## Requisitos de desarrollo y pruebas

`requirements.txt` (Pester ≥ 5.5, PSScriptAnalyzer ≥ 1.22) se instala sin Administrador con `-Scope CurrentUser`. El instalador **no** requiere módulos.
