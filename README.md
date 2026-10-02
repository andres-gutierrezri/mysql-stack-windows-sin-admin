# mysql-stack-windows-sin-admin

Instalación automatizada de **MySQL Community Server**, **MySQL Workbench** y **MySQL Notifier** en **Windows 11** desde una **cuenta local sin privilegios de Administrador**, con scripts equivalentes en **PowerShell** y **CMD**, un **menú** para instalar y desinstalar componentes de forma individual o conjunta, verificaciones previas y pruebas de validación.

![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![MySQL Server](https://img.shields.io/badge/Server-26.7.0%20%7C%209.7.2%20LTS-4479A1?logo=mysql&logoColor=white)
![Workbench](https://img.shields.io/badge/Workbench-26.7.0%20%7C%208.0.47-00758F)
![Notifier](https://img.shields.io/badge/Notifier-1.1.8%20(EOL)-lightgrey)
![Licencia](https://img.shields.io/badge/licencia-MIT-green)

> ⚠️ **Lea antes [`docs/LIMITACIONES.md`](docs/LIMITACIONES.md).** Puntos clave: MySQL Notifier y Workbench 8.0 son productos sin mantenimiento cuyos MSI exigen Administrador (se extraen sin instalar); los servidores corren como proceso de usuario (sin servicio de Windows); y el proyecto se validó con análisis estático, pruebas unitarias y de orquestación con el sistema simulado, **no en un Windows 11 real**.

## Tabla de contenidos

1. [Qué hace](#qué-hace)
2. [Componentes](#componentes)
3. [Requisitos previos](#requisitos-previos)
4. [Instalación paso a paso](#instalación-paso-a-paso)
5. [Menú de instalación y desinstalación](#menú-de-instalación-y-desinstalación)
6. [Entorno virtual y dependencias](#entorno-virtual-y-dependencias)
7. [Configuración de variables de entorno (PATH y XAMPP)](#configuración-de-variables-de-entorno-path-y-xampp)
8. [Migraciones y datos iniciales](#migraciones-y-datos-iniciales)
9. [Ejecución](#ejecución)
10. [Pruebas](#pruebas)
11. [Desinstalación](#desinstalación)
12. [Estructura del proyecto](#estructura-del-proyecto)
13. [Documentación adicional](#documentación-adicional)
14. [Autor](#autor)
15. [Licencia](#licencia)

## Qué hace

| # | Etapa | Resultado |
|---|---|---|
| 1 | Habilita scripts descargados | `RemoteSigned` en `CurrentUser` + `Unblock-File` |
| 2 | Verifica requisitos | SO, runtime VC++, firewall/directivas, permisos, disco, red, servicio |
| 3 | Busca MySQL previo | Registro, carpetas, servicios, procesos; estado de cada componente propio |
| 4 | Busca XAMPP / WampServer | Carpetas, servicios, procesos y entrada de XAMPP en el PATH |
| 5 | Elige puertos | 3306 si no hay conflictos; si no, 3307 o superior (distintos por servidor) |
| 6 | Crea `C:\Programs` | Instala en `C:\Programs\MySQL\…` |
| 7 | Descarga y verifica (MD5) | Solo los componentes seleccionados, desde servidores oficiales de Oracle |
| 8 | Configura e inicia | `my.ini`, datadir y `mysqld` en `127.0.0.1`, por servidor |
| 9 | Contraseña de root | Se **solicita**; ENTER = en blanco; respaldo `1234567` |
| 10 | PATH y accesos directos | Servidor primario **antes de XAMPP**, `MYSQL_TCP_PORT`, un acceso directo por componente |

Conexión resultante: `mysql -u root -p -h localhost -P <puerto> -D mysql`

## Componentes

| ID | Producto | Carpeta | Acceso directo |
|---|---|---|---|
| `SRV` | MySQL Community Server **26.7.0** (la más reciente) | `C:\Programs\MySQL\server` | MySQL Community Server 26.7.0 |
| `WB` | MySQL Workbench **26.7.0** (la más reciente) | `…\workbench` | MySQL Workbench 26.7.0 |
| `NOTIF` | MySQL Notifier 1.1.8 | `…\notifier` | MySQL Notifier |
| `SRVLTS` | MySQL Community Server **9.7.2 LTS** | `…\server-9.7-lts` | MySQL Community Server 9.7.2 LTS |
| `WB8` | MySQL Workbench **8.0.47** | `…\workbench-8.0.47` | MySQL Workbench 8.0.47 |

Grupos: `ALL` · `LATEST` (`SRV`+`WB`+`NOTIF`, valor por defecto) · `LTS` (`SRVLTS`+`WB8`). Cada componente tiene su propia carpeta, datos, puerto, lanzadores y acceso directo, por lo que **conviven sin conflictos** y se instalan o desinstalan por separado. Detalle en [`docs/COMPONENTES_Y_MENU.md`](docs/COMPONENTES_Y_MENU.md).

## Requisitos previos

| Requisito | Detalle |
|---|---|
| Windows 11 x64 | Compilación ≥ 22000, cuenta **local** estándar |
| Visual C++ Redistributable x64 | Debe estar presente (instalarlo requiere Administrador). Ver [`docs/REQUISITOS.md`](docs/REQUISITOS.md) |
| Windows PowerShell 5.1+ | Incluido. Los CMD usan además `curl.exe`, `tar.exe`, `msiexec`, `certutil`, `netstat` (incluidos) |
| Internet | Acceso HTTPS a `cdn.mysql.com` |
| Espacio | Suma por componente: servidores 3 GB c/u, Workbench 26.7 3 GB, Workbench 8.0 4 GB, Notifier 1 GB (todo ≈ 14 GB) |
| Permiso | Poder crear carpetas en `C:\` (predeterminado en Windows) |

Para **desarrollo y pruebas** (opcional): Pester ≥ 5.5 y PSScriptAnalyzer ≥ 1.22 (`requirements.txt`).

## Instalación paso a paso

**1. Obtenga el proyecto** (ZIP de GitHub/GitLab o `git clone`) y extráigalo, p. ej., en `C:\Users\<usuario>\Downloads\mysql-stack-windows-sin-admin`.

**2. Habilite la ejecución de scripts descargados** (el ZIP descargado marca los archivos como bloqueados):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\powershell\Enable-ScriptExecution.ps1
```
```bat
src\cmd\enable_script_execution.cmd
```

**3. Simulación (no modifica nada):**

```powershell
.\src\powershell\Install-MySQLStack.ps1 -Components ALL -DryRun
```
```bat
src\cmd\install_mysql_stack.cmd /COMPONENTS:ALL /DRYRUN
```

**4. Instalación real** (sin `-Components`/`/COMPONENTS:` se instala `LATEST`):

```powershell
.\src\powershell\Install-MySQLStack.ps1                          # última versión: SRV + WB + NOTIF
.\src\powershell\Install-MySQLStack.ps1 -Components SRVLTS,WB8   # solo LTS
.\src\powershell\Install-MySQLStack.ps1 -Components ALL          # los cinco
```
```bat
src\cmd\install_mysql_stack.cmd
src\cmd\install_mysql_stack.cmd /COMPONENTS:SRVLTS+WB8
src\cmd\install_mysql_stack.cmd /COMPONENTS:ALL
```

**Opciones:**

| PowerShell | CMD | Efecto |
|---|---|---|
| `-Components SRV,WB8` | `/COMPONENTS:SRV+WB8` | Componentes o grupos (en CMD separe con `+`, o con coma entre comillas) |
| `-InstallRoot C:\Programs` | `/ROOT:C:\Programs` | Carpeta raíz (sin espacios ni `& ^ % !`) |
| `-Port 3310` | `/PORT:3310` | Puerto del **primer** servidor de la ejecución (error si está ocupado) |
| `-BlankPassword` | `/BLANK` | root sin contraseña, sin preguntar |
| `-NoPrompt` | `/NOPROMPT` | No interactivo (contraseña de respaldo `1234567`) |
| `-SkipNotifier` | `/SKIPNOTIFIER` | Excluye Notifier |
| `-Force` | `/FORCE` | Reinstala los componentes ya instalados |
| `-FixPathOnly` | `/FIXPATH` | Solo recalcula el PATH (p. ej. si instaló XAMPP después) |
| `-DryRun` | `/DRYRUN` | Solo comprueba y planifica |

## Menú de instalación y desinstalación

```powershell
.\src\powershell\Show-MySQLStackMenu.ps1
```
```bat
src\cmd\mysql_stack_menu.cmd
```

Muestra el estado de los cinco componentes (instalado, puerto, en ejecución) y permite **instalar** o **desinstalar** uno, varios o todos: números `1`–`5`, nombres, `U` (última), `L` (LTS) o `T` (todo). También hay modo no interactivo (`-Action Install|Uninstall|Status|FixPath`, o `/ACTION:`). Instalar algo ya instalado se omite; desinstalar uno no afecta a los demás.

## Entorno virtual y dependencias

El proyecto **no usa Python**, por lo que `venv`/`virtualenv` y `pip install -r requirements.txt` **no aplican**. El equivalente en PowerShell, solo para pruebas y sin Administrador:

```powershell
Install-Module Pester          -MinimumVersion 5.5.0  -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -MinimumVersion 1.22.0 -Scope CurrentUser -Force
```

## Configuración de variables de entorno (PATH y XAMPP)

- **Del proyecto** (`config/stack.env`): componentes, versiones, URL, MD5, puertos y contraseña de respaldo. Opcionalmente copie `.env.example` a `.env` para sobrescribir `INSTALL_ROOT`, `MYSQL_PORT` y `SKIP_NOTIFIER`. **No guarde contraseñas** en `.env`.
- **Del sistema (ámbito de la cuenta local, sin Administrador):**
  - `PATH` += `C:\Programs\MySQL\server\bin` del **servidor primario** (el más reciente; si no está, el LTS). Solo uno, para que `mysql` sea inequívoco.
  - **Si el PATH de usuario ya contiene la entrada de XAMPP MySQL, el servidor se inserta justo antes:** `C:\Programs\MySQL\server\bin;C:\xampp\mysql\bin`.
  - `MYSQL_TCP_PORT` = puerto del servidor primario.
- Abra una **nueva** consola para ver los cambios.
- ⚠️ Si XAMPP está en el PATH **del equipo** (no del usuario), Windows lo evalúa primero y no se puede superar sin Administrador; el instalador lo detecta y avisa.

## Migraciones y datos iniciales

No hay migraciones. El instalador inicializa cada *datadir* con `mysqld --initialize-insecure` y aplica la contraseña elegida a los servidores **recién inicializados**. Si un directorio de datos ya existe, **se conserva** junto con su contraseña actual.

## Ejecución

```bat
mysql -u root -p -h localhost -P 3306 -D mysql
```

Use el puerto que informó el instalador. Para el servidor que no es el primario use su acceso directo o la ruta completa, p. ej. `C:\Programs\MySQL\server-9.7-lts\bin\mysql.exe -u root -p -h localhost -P 3307 -D mysql`. Iniciar/detener: `C:\Programs\MySQL\launchers\start-mysql-server.cmd` y `stop-mysql-server.cmd` (con sufijo `-lts` para el LTS).

## Pruebas

```powershell
Invoke-Pester -Path .\tests -Output Detailed
```
```bat
tests\validate_project.cmd
```

Detalle y lista de comprobación manual en [`docs/PRUEBAS.md`](docs/PRUEBAS.md).

## Desinstalación

```powershell
.\src\powershell\Uninstall-MySQLStack.ps1                              # todo (pide confirmación)
.\src\powershell\Uninstall-MySQLStack.ps1 -Components WB8              # solo un componente
.\src\powershell\Uninstall-MySQLStack.ps1 -Components LTS -KeepData    # conserva las bases de datos
.\src\powershell\Uninstall-MySQLStack.ps1 -DryRun
```
```bat
src\cmd\uninstall_mysql_stack.cmd
src\cmd\uninstall_mysql_stack.cmd /COMPONENTS:WB8
src\cmd\uninstall_mysql_stack.cmd /COMPONENTS:LTS /KEEPDATA
src\cmd\uninstall_mysql_stack.cmd /DRYRUN
```

Por componente: detiene sus procesos, elimina su acceso directo, lanzadores, carpeta y (servidores) sus datos, y recalcula el PATH (si queda el otro servidor, pasa a ser el primario). Al desinstalar el último se elimina `C:\Programs\MySQL`. No toca otras instalaciones de MySQL, XAMPP ni WampServer.

## Estructura del proyecto

```
mysql-stack-windows-sin-admin/
├── src/
│   ├── powershell/   MySQLStack.Common.ps1 (biblioteca) · Install-MySQLStack.ps1 · Uninstall-MySQLStack.ps1
│   │                 Show-MySQLStackMenu.ps1 · Enable-ScriptExecution.ps1
│   ├── cmd/          install_mysql_stack.cmd · uninstall_mysql_stack.cmd · mysql_stack_menu.cmd · enable_script_execution.cmd
│   └── templates/    lanzadores (.tpl) que se renderizan por servidor
├── config/           stack.env (componentes, versiones, URL y MD5 fijados)
├── tests/            Validate.Tests.ps1 · Orchestration.Tests.ps1 (Pester 5) · validate_project.cmd
├── docs/             ARQUITECTURA · COMPONENTES_Y_MENU · REQUISITOS · PRUEBAS · LIMITACIONES · PUBLICACION_GIT
├── .env.example · .gitignore · .gitattributes · requirements.txt
├── PSScriptAnalyzerSettings.psd1
├── LICENSE
└── README.md
```

## Documentación adicional

- [Componentes, convivencia y menú](docs/COMPONENTES_Y_MENU.md)
- [Arquitectura y decisiones](docs/ARQUITECTURA.md)
- [Requisitos y verificaciones](docs/REQUISITOS.md)
- [Pruebas de validación](docs/PRUEBAS.md)
- [Limitaciones y riesgos](docs/LIMITACIONES.md)
- [Publicación en GitHub y GitLab](docs/PUBLICACION_GIT.md)

## Autor

**Ingeniero Andrés Felipe Gutiérrez Rivera**

- GitHub: <https://github.com/andres-gutierrezri>
- GitLab: <https://gitlab.com/andres.gutierrezri>
- LinkedIn: <https://www.linkedin.com/in/felipe-gutierrezri>

## Licencia

[MIT](LICENSE). MySQL, MySQL Workbench y MySQL Notifier son productos de Oracle bajo sus propias licencias; este repositorio **no redistribuye** sus binarios, los descarga desde los servidores oficiales.
