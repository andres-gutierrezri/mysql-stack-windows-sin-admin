# Pruebas de validación

## Ejecución

```powershell
# PowerShell (Pester 5)
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester -Path .\tests -Output Detailed

# Análisis estático
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path .\src\powershell -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

```bat
:: CMD puro
tests\validate_project.cmd
echo %ERRORLEVEL%
```

> Windows 11 trae Pester 3.4: no sirve para estas pruebas; instale Pester 5 como se indica.

## Cobertura

| Archivo | Grupo | Qué verifica |
|---|---|---|
| `Validate.Tests.ps1` | Estructura | Existencia de todos los archivos obligatorios |
| | Sintaxis y codificación | AST de cada `.ps1` y de **cada bloque PowerShell embebido en los `.cmd`**; BOM en `.ps1`; ASCII + CRLF en `.cmd`/`.tpl`; etiquetas `.cmd` sin duplicados y sin referencias rotas; ausencia del patrón `if (…) & otro` |
| | Seguridad | Ausencia de `mysqld --install`, `RunAs`, `New-Service`, reglas de firewall, escritura en `HKLM`, `setx /M`, `sc create`; `HKLM` solo en lectura |
| | Configuración | Claves de los cinco componentes, MD5 de 32 hex, URL HTTPS de MySQL, versiones 9.7.2 y 8.0.47, sin valores vacíos, configuración incompleta → código 50 |
| | Aislamiento | Carpetas y datos únicos y sin contención, sufijos y accesos directos distintos, `server` vs `server-9.7-lts`, `my.ini` por servidor |
| | Selección | `ALL`, `LATEST`, `LTS`, `T/U/L`, números, orden canónico, duplicados, desconocido → 50 |
| | PATH y XAMPP | Inserción **antes** de `C:\xampp\mysql\bin` (mayúsculas, barra final, otra unidad), reubicación, idempotencia, cambio SRV→LTS, solo-eliminar, `%VAR%`, PATH vacío, patrón que no coincide con otras carpetas XAMPP |
| | Estado | Servidor primario (SRV > SRVLTS), desinstalar uno no altera a los demás, migración del manifiesto v1, guardar/leer |
| | Funciones puras y puertos | Escapes SQL/opciones, rutas seguras, enlace real de loopback, 3306 → 3307, dos servidores en secuencia, error 20 |
| | Contrato PS ↔ CMD | Comando de conexión, plantillas por servidor, 10 etapas en ambos, mismos componentes/grupos, ayudantes con `BEGIN/END` |
| | **Paridad del PATH** | El helper `PATHSET` de `install_mysql_stack.cmd` y de `uninstall_mysql_stack.cmd` produce **el mismo PATH** que `Set-PathPriority` en 8 casos (registro simulado) |
| | Contraseña de root | `PWSET` con varios servidores (respaldo, en blanco, fallo) y `Set-RootPassword` con cliente `mysql` simulado; sin temporales con secretos |
| | Desinstalador | `Test-SafeRemovalTarget` y `Test-SafeChildTarget` |
| | Integración (Windows, `-Tag Integration`) | `-DryRun` de instalador PS/CMD, desinstalador y menú; **no modifican el sistema** |
| `Orchestration.Tests.ps1` | Orquestación completa | Ejecuta `Invoke-Main` con todo el sistema simulado: instalación individual (`SRV`, `SRVLTS`, `WB8`), `LATEST`, `LTS`, `ALL`; el segundo servidor recibe otro puerto y se le aplica la misma contraseña; convivencia con lo ya instalado; omisión de lo instalado; `-Force`; instalación incompleta; XAMPP/terceros y puerto ocupado; `-SkipNotifier` y fallo de Notifier; PATH antes de XAMPP; aviso por XAMPP en el PATH del equipo; `-FixPathOnly`; `-DryRun` sin efectos; componente desconocido |
| `validate_project.cmd` | CMD puro | Estructura, patrones prohibidos, claves por componente, ayudantes embebidos y simulaciones (`/DRYRUN`) de instalador, desinstalador y menú, código 50 ante un componente desconocido |

## Resultados obtenidos al construir el proyecto

Ejecutados en **PowerShell 7.4.6 sobre Linux** (no había Windows disponible):

| Verificación | Resultado |
|---|---|
| Pester (`Validate.Tests.ps1` + `Orchestration.Tests.ps1`) | **146 correctas, 0 fallidas, 4 omitidas** (las 4 son de integración y solo corren en Windows) |
| PSScriptAnalyzer (`PSScriptAnalyzerSettings.psd1`) | 0 hallazgos |
| AST de los 5 `.ps1`, de la suite y de todos los bloques embebidos en los `.cmd` | Sin errores |
| Paquetes oficiales | Descargados; MD5 de **servidor 26.7.0, servidor 9.7.2, Workbench 26.7.0, Workbench 8.0.47 y Notifier 1.1.8 coinciden** con los publicados por Oracle |
| Estructura de los paquetes | Carpetas internas, ejecutables y longitud máxima de ruta inspeccionadas (Workbench 8.0.47: 24 044 archivos, 198 caracteres como máximo con la raíz por defecto) |
| Tablas de los MSI de Notifier y Workbench 8.0.47 | `LaunchCondition` `Privileged` y `ALLUSERS=1`; ausentes en `AdminExecuteSequence`; todos los archivos de Workbench cuelgan de `INSTALLDIR` |

Las pruebas encontraron y corrigieron, durante el desarrollo: un parámetro `[string]` que convertía `$null` en `''` (se perdía `--skip-password`), un reemplazo textual que dañó el flujo del CMD, comparaciones de prefijo `server` / `server-9.7-lts`, y la reasignación de contraseña a un servidor reinstalado con datos existentes.

**No se ejecutó nada en un Windows 11 real ni en un `cmd.exe` real.** Antes de usarlo, realice esta lista de comprobación manual en una cuenta estándar:

1. `Invoke-Pester -Path .\tests -Tag Integration` y `tests\validate_project.cmd`.
2. `Install-MySQLStack.ps1 -Components ALL -DryRun` y revisar el informe de requisitos y los puertos.
3. Instalar `SRV`, comprobar `mysql -u root -p -h localhost -P 3306 -D mysql`; luego instalar `SRVLTS` y comprobar que usa otro puerto y que el primero sigue funcionando.
4. Instalar `WB8` y comprobar que la extracción `msiexec /a` produce `MySQLWorkbench.exe` y que abre (sin Administrador). Hacer lo mismo con `NOTIF`.
5. Con `C:\xampp\mysql\bin` en el PATH de usuario: instalar y verificar con `echo %PATH%` (en una consola nueva) que `C:\Programs\MySQL\server\bin` queda **antes**. Repetirlo con XAMPP en el PATH del equipo y comprobar el aviso.
6. Abrir los accesos directos del escritorio de cada componente.
7. Desinstalar `SRV` y comprobar que el PATH pasa a `server-9.7-lts\bin` y que el LTS sigue operativo; desinstalar el resto y verificar que `PATH`, `MYSQL_TCP_PORT` y `C:\Programs\MySQL` desaparecen.
8. Repetir las variantes con los scripts CMD y con el menú (`mysql_stack_menu.cmd`).
