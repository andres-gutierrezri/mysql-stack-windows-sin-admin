# Arquitectura

## Principios de diseño

| Principio | Aplicación |
|---|---|
| **DRY** | Componentes, versiones, URL, sumas MD5, puertos y contraseña de respaldo viven en `config/stack.env`, leído por PowerShell y CMD. Los lanzadores se generan desde `src/templates/*.tpl`. Lo que comparten los scripts PowerShell (componentes, manifiesto, PATH) está en `MySQLStack.Common.ps1`. |
| **KISS** | Un instalador, un desinstalador y un menú por lenguaje; sin dependencias externas (solo herramientas de Windows 11: `curl.exe`, `tar.exe`, `msiexec`, `certutil`, `netstat`, `reg`). |
| **SOLID (SRP)** | Cada función hace una cosa (`Select-MySqlPorts`, `Set-PathPriority`, `Get-VerifiedFile`, `Write-MyIni`…) y las puras se prueban de forma aislada. El menú no instala: delega en los scripts de instalación y desinstalación, que siguen siendo independientes. |
| **Mínimo privilegio** | Nada escribe en `HKLM` (solo se lee), no crea servicios, no abre puertos externos, no usa `RunAs`. Las pruebas lo verifican por patrones. |
| **Aislamiento por componente** | Cada componente tiene su carpeta, datos, puerto, lanzadores, acceso directo y claves de estado. Ninguna operación sobre uno toca a otro. |

## Modelo de componentes

`config/stack.env` define cinco componentes con las mismas claves: `<ID>_LABEL, _VERSION, _KIND, _URL, _MD5, _FILE, _DIR, _LINK, _NEED_GB` y, para servidores, `_FOLDER, _DATADIR, _SUFFIX` (los valores vacíos se escriben `NONE`).

| `KIND` | Qué instala | Cómo |
|---|---|---|
| `server` | MySQL Community Server | ZIP *noinstall* → carpeta propia + `my.ini` + `datadir` propio |
| `wbzip` | Workbench 26.7 | ZIP portable extraído en su carpeta |
| `wbmsi` | Workbench 8.0.47 | MSI → imagen administrativa (`msiexec /a`) → se mueve la carpeta del ejecutable |
| `notifier` | Notifier 1.1.8 | Ídem `wbmsi` (opcional: un fallo no detiene la instalación) |

Estado en `C:\Programs\MySQL\stack-manifest.env` (ASCII, `CLAVE=VALOR`, legible por PowerShell y CMD): `INSTALL_ROOT`, `BASE`, `CREATED_ROOT` y, por componente, `<ID>_INSTALLED`, `<ID>_PORT`, `<ID>_XPORT`. El formato de la versión 1 (`PORT`, `XPORT`, `NOTIFIER`) se migra automáticamente.

## Flujo (10 etapas, idéntico en PowerShell y CMD)

```
1 Habilitar ejecución ─► 2 Requisitos ─► 3 Estado/MySQL previo ─► 4 XAMPP/WAMP ─► 5 Puertos
                                                                                     │
10 PATH(antes de XAMPP)+accesos ◄─ 9 Contraseña ◄─ 8 my.ini/init/start ◄─ 7 Instala ◄─ 6 C:\Programs
```

| # | Etapa | PowerShell | CMD |
|---|---|---|---|
| 1 | Política `RemoteSigned` (CurrentUser) + `Unblock-File` | `Enable-ScriptExecution` | helper `ENABLE` |
| 2 | Requisitos mínimos (espacio = suma de los seleccionados) | `Get-PrerequisiteReport` | bloque «ETAPA 2» |
| 3 | Terceros + estado de cada componente (se omite lo ya instalado) | `Find-ThirdPartyInstallations`, `Get-ComponentInstallState` | `:found`, `:classify`, helper `FOREIGN` |
| 4 | XAMPP, WampServer y entrada de XAMPP en el PATH | ídem | bloque «ETAPA 4», helper `XAMPPCHK` |
| 5 | Puertos por servidor (reserva los de los ya instalados) | `Select-MySqlPorts` | `:choose_ports`, `:port_ok` |
| 6 | Carpeta de instalación | `Test-WritableRoot -Create` | bloque «ETAPA 6» |
| 7 | Descarga, MD5 e instalación por componente | `Install-ServerPackage`, `Install-WorkbenchZipPackage`, `Install-MsiImagePackage` | `:install_component` → `:inst_server`, `:inst_wbzip`, `:inst_msi` |
| 8 | `my.ini`, datos, arranque y manifiesto por servidor | `Write-MyIni`, `Initialize-DataDirectory`, `Start-MySqlServer` | `:configure_server` |
| 9 | Contraseña de root (una vez; solo servidores con datos nuevos) | `Read-RootPasswordChoice`, `Set-RootPassword` | helper `PWSET` |
| 10 | Lanzadores, accesos directos y PATH | `New-LauncherFiles`, `New-ComponentShortcut`, `Update-UserEnvironment` | `:finish_component`, `:update_path` (helper `PATHSET`) |

## Convivencia sin conflictos

Ver [`COMPONENTES_Y_MENU.md`](COMPONENTES_Y_MENU.md). Resumen: carpetas, datos, puertos, `my.ini`, lanzadores y accesos directos distintos; solo se detienen procesos **dentro de la carpeta del componente** (comparación con `\` final para que `server` no «contenga» a `server-9.7-lts`); y el PATH/`MYSQL_TCP_PORT` siempre reflejan un único **servidor primario** recalculado a partir del manifiesto tras cada instalación o desinstalación.

## PATH respecto de XAMPP

`Set-PathPriority` (y su copia en el helper `PATHSET` de los `.cmd`, verificada por una prueba de equivalencia): (1) elimina las carpetas `bin` de ambos servidores del proyecto, (2) busca la primera entrada que coincida con `…\xampp\mysql\bin` y (3) inserta el servidor primario inmediatamente antes; sin XAMPP lo agrega al final. Opera sobre el valor **crudo** de `HKCU\Environment\Path` (sin expandir `%VAR%`) y lo escribe como `REG_EXPAND_SZ`.

## Diseño del CMD

- **Ayudantes PowerShell embebidos.** CMD puro no puede leer una contraseña oculta, editar el PATH conservando `REG_EXPAND_SZ` ni crear `.lnk`. Los `.cmd` incluyen al final bloques PowerShell con prefijo `::` (CMD los ignora). `:ps_run` extrae el bloque por nombre con una expresión regular y lo ejecuta **en memoria** con `powershell -Command`, sin depender de la política de ejecución ni de los `.ps1`. Los datos se pasan por variables de entorno `MS_*`, nunca por línea de comandos.
- **Las subrutinas no terminan el script.** `exit /b` solo sale de la subrutina; por eso fijan `DIE_CODE`/`DIE_MSG` mediante `:fail` y el flujo principal hace `goto :die`. Cada subrutina de componente empieza con `if defined DIE_CODE exit /b 1`.
- **Datos por componente.** Sin expansión retardada: `call set "V=%%%~1_KEY%%"` lee `<ID>_KEY`; `:load_comp` vuelca los datos del componente a variables `C_*` (`NONE` → vacío).
- **Trampa evitada:** en `if cond (bloque) & otro`, «otro» se ejecuta **siempre**; por eso los indicadores (`TOK_OK`) van dentro del bloque. Una prueba rechaza ese patrón en todos los `.cmd`.
- Manifiesto sin PowerShell: `:mf_set`/`:mf_del` reescriben el archivo con `findstr /V /B`.

## Disposición en disco

```
C:\Programs\MySQL\
├── server\  · data\                 SRV   (26.7.0)
├── server-9.7-lts\ · data-9.7-lts\  SRVLTS (9.7.2 LTS)
├── workbench\                       WB    (26.7.0)
├── workbench-8.0.47\                WB8
├── notifier\                        NOTIF
├── launchers\                       mysql-console[-lts].cmd · start-mysql-server[-lts].cmd · stop-mysql-server[-lts].cmd
├── logs\ · _cache\ · _tmp\
└── stack-manifest.env
```

Se usa la subcarpeta `MySQL` bajo `C:\Programs` para que la desinstalación elimine **exactamente** una carpeta propia y nunca contenido ajeno. Las eliminaciones pasan por `Test-SafeRemovalTarget` (solo `<raíz>\MySQL`) y `Test-SafeChildTarget` (solo carpetas de la lista permitida directamente bajo la base).

## Decisiones técnicas

| Decisión | Motivo |
|---|---|
| `bind-address=127.0.0.1` y `mysqlx-bind-address=127.0.0.1` | Evita el aviso del Firewall (que exigiría elevación) y expone el servidor solo localmente. |
| Sin servicio de Windows | `mysqld --install` requiere Administrador. Cada servidor es un proceso de usuario iniciado por sus lanzadores. |
| `my.ini` dentro de la carpeta de cada servidor y `--defaults-file` explícito | El cliente lee el `my.ini` de su propio `basedir`; los servidores no comparten configuración. |
| `MYSQL_TCP_PORT` = puerto del primario | Cuando el puerto no es 3306, `mysql -u root -p` funciona aunque se omita `-P`. |
| `--initialize-insecure` + `ALTER USER` | Permite fijar, en blanco o con valor, la contraseña elegida sin contraseña temporal. |
| Contraseña por `.cnf` temporal sobrescrito y borrado | Evita exponerla en la línea de comandos. |
| `tar.exe` antes que `Expand-Archive` | `Expand-Archive` de Windows PowerShell 5.1 es muy lento con ~350 MB. |
| `Start-Process -Redirect*` en lugar de `&` | En PS 5.1, `stderr` redirigido de un binario nativo se convierte en error terminante. |
| `Join-WinPath` en la lógica de orquestación | Concatenación pura: se puede probar en cualquier sistema operativo (`Join-Path` exige que exista la unidad). |
| `.ps1` con BOM UTF-8 y CRLF; `.cmd`/`.tpl` ASCII con CRLF | PS 5.1 lee mal UTF-8 sin BOM; `cmd.exe` falla con etiquetas y `goto` en archivos LF. Lo fija `.gitattributes`. |

## Códigos de salida

`0` correcto · `10` requisitos · `20` conflictos/puertos/ruta no segura · `30` descarga/MD5 · `40` instalación/eliminación · `50` configuración o selección inválida · desinstalador: `1` cancelado.
