# Limitaciones, riesgos y decisiones a tener en cuenta

## 1. Productos sin mantenimiento: MySQL Notifier y Workbench 8.0

- **Notifier** está fuera de ciclo de vida; MySQL Installer ya no lo ofrece y solo existe el MSI independiente **1.1.8** en los archivos históricos. **Workbench 8.0** está obsoleto: Oracle declaró que Workbench 26.7 lo reemplaza y que no tendrá nuevas versiones. 8.0.47 es la última.
- Ambos MSI declaran la condición `Privileged` (**exigen Administrador**) y `ALLUSERS=1`. Se analizaron sus tablas: esa condición **no forma parte de la secuencia administrativa**, por lo que el proyecto los extrae como *imagen administrativa* (`msiexec /a … TARGETDIR=`) a una carpeta de usuario. Es un método de **mejor esfuerzo, no verificado en Windows real**: al ser una extracción, no se crean entradas de registro, asociaciones de archivos (`.mwb`, `.sql`) ni se ejecutan las acciones personalizadas (p. ej., precompilar Python en Workbench 8.0).
- Si la extracción de Notifier falla, el instalador avisa y continúa; si falla la de Workbench 8.0.47, se detiene con el código 40.
- **Notifier monitorea servicios de Windows.** Como `mysqld` corre como proceso de usuario (sin servicio), **no podrá iniciar/detener ni mostrar el estado de ese servidor**. Se instala solo para cumplir el requisito; use los lanzadores del escritorio.
- Workbench 8.0.47 y Notifier requieren .NET Framework 4.5.2 o superior y el runtime de Visual C++ 2019.

## 2. Convivencia de versiones

- **Workbench 8.0.47 con servidores 9.7/26.7:** su manual indica que se desarrolló con MySQL 8.0 y que puede conectarse a 8.4 o superiores con **funciones que podrían no operar**. Workbench 26.7 sí soporta oficialmente 8.4 LTS, 9.7 LTS y 26.7. El grupo `LTS` (servidor 9.7.2 + Workbench 8.0.47) es por fecha y soporte, no una combinación certificada.
- **Configuración de usuario compartida:** Workbench 8.0 guarda conexiones y ajustes en `%APPDATA%\MySQL\Workbench`. Su documentación **no define una opción para cambiar esa carpeta**, por lo que no se aísla; la ubicación que usa Workbench 26.7 no se verificó. El desinstalador **no borra** `%APPDATA%` (podría contener datos de otra instalación de Workbench).
- **Un solo servidor en el PATH:** el primario (el más reciente; si no, el LTS). El otro se usa con su acceso directo o su ruta completa.
- **Una contraseña por ejecución:** si instala dos servidores en la misma ejecución, la misma contraseña se aplica a ambos. Un servidor con datos preexistentes conserva su contraseña.
- **`-Port` / `/PORT:`** se aplica solo al **primer** servidor de la ejecución; el segundo se asigna automáticamente.
- Dos servidores en marcha consumen memoria y CPU; el proyecto no los arranca al iniciar sesión.

## 3. Sin Administrador

- **Sin servicio de Windows**: los servidores no inician con el sistema ni sobreviven al cierre de sesión. Para arrancar uno al iniciar sesión copie su `start-mysql-server*.cmd` (o un acceso directo) a `shell:startup`.
- **Runtime de Visual C++**: si falta, instalarlo requiere Administrador; el instalador se detiene con el código 10.
- La documentación oficial de MySQL 9.7 indica iniciar sesión como administrador para el método ZIP. Ejecutar `mysqld.exe` como proceso de usuario es una inferencia técnica coherente con el paquete *noinstall*, **no una configuración respaldada por Oracle**.
- **MySQL Configurator** (incluido en el ZIP) no se usa: su compatibilidad sin elevación no se verificó.
- Directivas corporativas (AppLocker, WDAC, GPO de política de ejecución) pueden anular el procedimiento.

## 4. PATH y XAMPP

- Solo se modifica el PATH **de usuario** (`HKCU\Environment`). Windows evalúa el PATH **del equipo antes que el del usuario**: si `C:\xampp\mysql\bin` está en el PATH del equipo, `mysql` seguirá resolviendo a XAMPP. El instalador lo detecta y avisa; sin Administrador no hay solución.
- El reconocimiento de XAMPP es por patrón de ruta (`…\xampp\mysql\bin`). Una carpeta XAMPP en el disco que **no** esté en el PATH no genera ninguna acción de orden.
- Si XAMPP se agrega al PATH **después** de instalar, use «Reordenar PATH» del menú (`-FixPathOnly` / `/FIXPATH`).

## 5. Versiones

- «Última versión» del servidor es hoy **26.7.0 Innovation** (calendario trimestral, soporte corto); **9.7.2 LTS** se ofrece como componente independiente.
- **Workbench 26.7** es una reescritura (Electron + MySQL Shell) que reemplaza a la línea 8.0; el anuncio advierte que faltan funciones de la 8.0 (p. ej., el modelado EER no figura entre las funciones listadas).
- URL y MD5 están fijados al 2026-10-02. Si Oracle publica nuevas versiones, actualice `config/stack.env` (un MD5 incorrecto aborta con el código 30).

## 6. Seguridad

- **Contraseña de respaldo `1234567`** (requisito del proyecto): es débil. Solo se aplica si la contraseña indicada no puede asignarse o en modo `-NoPrompt`. Los servidores solo escuchan en `127.0.0.1`, pero **cámbiela** (`ALTER USER 'root'@'localhost' IDENTIFIED BY '…';`).
- **Contraseña en blanco** (opción permitida): cualquier proceso de su sesión podría conectarse como `root`.
- **MD5** solo detecta corrupción de descarga, no manipulación maliciosa. Para verificación criptográfica use las firmas GnuPG que Oracle publica con Gpg4win.
- La contraseña llega al cliente mediante un `.cnf` temporal en `%TEMP%`, sobrescrito con ceros y borrado; nunca por línea de comandos.

## 7. Comportamiento del sistema y compatibilidad

- Los accesos directos se crean en la carpeta de escritorio real del usuario (respeta OneDrive).
- `-h localhost` usa TCP en Windows, por eso `-P <puerto>` se respeta.
- Cada `mysql.exe` lee el `my.ini` de su propio `basedir` (según el manual de MySQL), por lo que cada cliente usa el puerto de su servidor. Un `C:\my.ini` o `%WINDIR%\my.ini` ajeno se lee antes y lo sobrescriben los del proyecto.
- Rutas largas: Workbench 8.0.47 llega a 198 caracteres con la raíz por defecto; con raíces más largas podría superarse el límite de 260 caracteres.
- Una instalación detenida de otro MySQL/XAMPP/WAMP **también** hace que se elija un puerto alternativo (no se puede saber si arrancará después).
- **Migración desde la versión 1 del proyecto:** el manifiesto de un solo servidor se convierte automáticamente; los accesos directos antiguos («MySQL Community Server», «MySQL Workbench») se eliminan al desinstalar. Los lanzadores `mysql-console.cmd` etc. conservan sus nombres para el servidor 26.7.
- El instalador **CMD nunca se ejecutó en un `cmd.exe` real**: se revisó etiqueta por etiqueta, se probó cada ayudante PowerShell embebido (incluida su equivalencia con la función de PowerShell), pero la lógica puramente CMD (bucles, `call`, expansión de variables) solo se validó por revisión estática.
