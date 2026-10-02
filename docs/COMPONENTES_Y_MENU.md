# Componentes, convivencia y menú

## 1. Los cinco componentes

| ID | Producto | Tipo de paquete | Carpeta (bajo `C:\Programs\MySQL\`) | Datos | Acceso directo del escritorio |
|---|---|---|---|---|---|
| `SRV` | MySQL Community Server **26.7.0** (la más reciente, Innovation) | ZIP *noinstall* | `server\` | `data\` | MySQL Community Server 26.7.0 |
| `WB` | MySQL Workbench **26.7.0** (la más reciente) | ZIP portable | `workbench\` | — | MySQL Workbench 26.7.0 |
| `NOTIF` | MySQL Notifier 1.1.8 (EOL) | MSI → imagen administrativa | `notifier\` | — | MySQL Notifier |
| `SRVLTS` | MySQL Community Server **9.7.2 LTS** | ZIP *noinstall* | `server-9.7-lts\` | `data-9.7-lts\` | MySQL Community Server 9.7.2 LTS |
| `WB8` | MySQL Workbench **8.0.47** | MSI → imagen administrativa | `workbench-8.0.47\` | — | MySQL Workbench 8.0.47 |

Grupos: **`ALL`** (los cinco) · **`LATEST`** = `SRV`+`WB`+`NOTIF` (valor por defecto) · **`LTS`** = `SRVLTS`+`WB8`.

> Verificación del 2026-10-02 con los paquetes oficiales: 9.7.2 (ZIP, 342 737 674 bytes) y Workbench 8.0.47 (MSI, 267 698 176 bytes) se descargaron y su **MD5 coincide con el publicado por Oracle**. Workbench 8.0.47 solo se distribuye como MSI (24 044 archivos, 1,2 GB extraídos, ruta interna más larga 163 caracteres → 198 con la carpeta de destino).

## 2. Por qué no hay conflictos entre ellos

| Recurso | Cómo se evita el choque |
|---|---|
| Carpetas | Una por componente. Las pruebas verifican que ninguna contenga a otra (`server` vs `server-9.7-lts`). |
| Datos | Cada servidor usa su propio `datadir` y su propio `mysql-error.log`. |
| Puertos | El primer servidor toma 3306 si no hay otros MySQL/XAMPP/WAMP; el segundo lo ve como «otra instalación» y toma el primer puerto libre desde 3307. Los puertos del protocolo X también son distintos (33060, 33061…). Los puertos de servidores ya instalados quedan **reservados** aunque estén detenidos. |
| `my.ini` | Uno por servidor, dentro de su carpeta. `mysql.exe` lee el `my.ini` de su propio `basedir`, así que cada cliente usa el puerto de su servidor. |
| Lanzadores | `mysql-console.cmd`, `start-mysql-server.cmd`, `stop-mysql-server.cmd` (SRV) y los mismos con sufijo `-lts` (SRVLTS). |
| Accesos directos | Nombres distintos (con versión). |
| Procesos | Al reinstalar o desinstalar solo se detienen los procesos **dentro de la carpeta del componente** (comparación con `\` final: `server` no «contiene» a `server-9.7-lts`). |
| Estado | `stack-manifest.env` guarda, por componente, `<ID>_INSTALLED`, `<ID>_PORT` y `<ID>_XPORT`; instalar o desinstalar uno solo modifica sus propias claves. |
| Contraseña de root | Se pide **una vez** por ejecución y se aplica a los servidores **recién inicializados**. Si un servidor conserva datos anteriores (reinstalación), no se toca su contraseña. |

### Servidor «primario» y variables de entorno

`PATH` y `MYSQL_TCP_PORT` apuntan a **un solo** servidor para que `mysql -u root -p -h localhost -P <puerto> -D mysql` sea inequívoco:

1. Si `SRV` está instalado → es el primario.
2. Si no, y `SRVLTS` está instalado → es el primario.
3. Si no hay ninguno → se limpian ambas variables.

El otro servidor se usa con su lanzador del escritorio o con la ruta completa, por ejemplo  
`C:\Programs\MySQL\server-9.7-lts\bin\mysql.exe -u root -p -h localhost -P 3307 -D mysql`.  
Al desinstalar el primario, el PATH pasa automáticamente al otro (si existe).

## 3. PATH y XAMPP

Al agregar la variable de entorno **de la cuenta local** (`HKCU\Environment`, valor `Path`):

- Si el PATH de usuario ya contiene la entrada de XAMPP MySQL, la carpeta del servidor se inserta **inmediatamente antes**:

  ```
  C:\Programs\MySQL\server\bin;C:\xampp\mysql\bin
  ```
- Si el servidor ya estaba **después** de XAMPP, se reubica antes. Si XAMPP no está, se agrega al final.
- La operación es idempotente y conserva el resto del PATH (incluidas entradas `%VAR%` sin expandir).
- El reconocimiento es por patrón (`…\xampp\mysql\bin`, sin distinguir mayúsculas, con o sin `\` final, en cualquier unidad).

> **Nota sobre la ruta de su enunciado:** `C:\xampp\mysql \bin` (con un espacio antes de `\bin`) no es una ruta válida de XAMPP; la carpeta real es `C:\xampp\mysql\bin`, que es la que el patrón reconoce.

> **Limitación de Windows (sin Administrador no se puede resolver):** el sistema evalúa el PATH **del equipo antes que el del usuario**. Si XAMPP está en el PATH del equipo, `mysql` seguirá resolviendo a XAMPP aunque el servidor del proyecto esté antes en el PATH de usuario. El instalador lo **detecta y avisa**; use los accesos directos o la ruta completa.

Si instala XAMPP **después**, ejecute la opción «Reordenar PATH» del menú (o `Install-MySQLStack.ps1 -FixPathOnly` / `install_mysql_stack.cmd /FIXPATH`).

## 4. Menú

```powershell
.\src\powershell\Show-MySQLStackMenu.ps1                       # interactivo
.\src\powershell\Show-MySQLStackMenu.ps1 -Action Status
.\src\powershell\Show-MySQLStackMenu.ps1 -Action Install   -Components SRVLTS,WB8
.\src\powershell\Show-MySQLStackMenu.ps1 -Action Uninstall -Components ALL -Yes
```
```bat
src\cmd\mysql_stack_menu.cmd
src\cmd\mysql_stack_menu.cmd /ACTION:STATUS
src\cmd\mysql_stack_menu.cmd /ACTION:INSTALL /COMPONENTS:SRVLTS+WB8
src\cmd\mysql_stack_menu.cmd /ACTION:UNINSTALL /COMPONENTS:ALL /YES
```

Pantalla interactiva (ejemplo):

```
=== MySQL Stack para Windows 11 (sin Administrador) ===
Estado de los componentes
  1) [X] MySQL Community Server 26.7.0  puerto 3306  (en ejecución)
  2) [X] MySQL Workbench 26.7.0
  3) [ ] MySQL Notifier 1.1.8
  4) [X] MySQL Community Server 9.7.2 LTS  puerto 3307  (detenido)
  5) [ ] MySQL Workbench 8.0.47
  1) Instalar    2) Desinstalar    3) Reordenar PATH (XAMPP)    0) Salir
```

Selección (separada por comas en PowerShell; con `+` o con comas **entre comillas** en CMD, porque la coma es separador de argumentos de `cmd.exe`):

| Entrada | Significado |
|---|---|
| `1`…`5` o `SRV`, `WB`, `NOTIF`, `SRVLTS`, `WB8` | Componente individual |
| `U` / `LATEST` | 1, 2 y 3 |
| `L` / `LTS` | 4 y 5 |
| `T` / `ALL` | Todo |
| `1,5` · `SRV+WB8` | Combinaciones libres |

Comportamiento:

- **Instalar** un componente que ya está instalado → se **omite** (idempotente); `-Force` / `/FORCE` lo reinstala. «Instalar todo» instala solo lo que falta.
- **Desinstalar** actúa solo sobre lo seleccionado e instalado, pide confirmación (`SI`) salvo `-Yes` / `/YES`, y con `-KeepData` / `/KEEPDATA` conserva las bases de datos.
- Cuando se desinstala el último componente se elimina `C:\Programs\MySQL` (y `C:\Programs` si el instalador la creó y quedó vacía).
- Todo acepta `-DryRun` / `/DRYRUN` para ver el plan sin cambios.

## 5. Compatibilidad entre Workbench y servidores

| Cliente | Servidores que soporta oficialmente |
|---|---|
| Workbench **26.7** | MySQL 8.4 LTS y posteriores, 9.7 LTS y 26.7 |
| Workbench **8.0.47** | El manual lo describe como desarrollado y probado con MySQL **8.0**; indica que puede conectarse a 8.4 y superiores, pero que **algunas funciones podrían no operar** |

Por tanto, el par «LTS» (`SRVLTS` 9.7.2 + `WB8` 8.0.47) lo es por su fecha y soporte, no porque Oracle certifique esa combinación; si necesita garantía, use Workbench 26.7 contra el servidor 9.7.2 LTS (`SRVLTS` + `WB`).
