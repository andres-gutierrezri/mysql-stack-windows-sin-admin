# Publicación en GitHub y GitLab (comando por comando)

Cuentas del autor: **GitHub** `https://github.com/andres-gutierrezri` · **GitLab** `https://gitlab.com/andres.gutierrezri`
Nombre del repositorio sugerido: `mysql-stack-windows-sin-admin`

> Git for Windows puede instalarse **sin Administrador** (instalador con opción «Only for me» o MinGit portable).

## 1. Repositorio local

```powershell
cd C:\ruta\a\mysql-stack-windows-sin-admin
git init
```

## 2. Identidad de usuario (solo para este repositorio)

```powershell
git config user.name  "Andrés Felipe Gutiérrez Rivera"
git config user.email "felipe.gutierrezri@gmail.com"
git config core.autocrlf false      # .gitattributes ya fija CRLF/LF por tipo de archivo
git config --list --local
```

## 3. Primera confirmación

```powershell
git status                          # .env y descargas NO deben aparecer (están en .gitignore)
git add .
git commit -m "feat: proyecto inicial mysql-stack-windows-sin-admin"
```

## 4. Crear los repositorios remotos (interfaz web)

- **GitHub:** icono «+» → *New repository* → nombre `mysql-stack-windows-sin-admin` → **sin** README, `.gitignore` ni licencia (ya existen) → *Create repository*.
- **GitLab:** *New project* → *Create blank project* → mismo nombre → desmarcar *Initialize repository with a README* → *Create project*.

## 5. Vincular el remoto y publicar la rama principal

```powershell
git branch -M main
git remote add origin https://github.com/andres-gutierrezri/mysql-stack-windows-sin-admin.git
git push -u origin main
```

## 6. Doble remoto (GitHub + GitLab)

**Opción A – remotos separados (más transparente):**

```powershell
git remote add gitlab https://gitlab.com/andres.gutierrezri/mysql-stack-windows-sin-admin.git
git push -u gitlab main
# en adelante:
git push origin main ; git push gitlab main
```

**Opción B – un solo `git push` a ambos:** la primera orden con `--push` reemplaza la URL de envío por defecto, por eso se añaden las dos.

```powershell
git remote set-url --add --push origin https://github.com/andres-gutierrezri/mysql-stack-windows-sin-admin.git
git remote set-url --add --push origin https://gitlab.com/andres.gutierrezri/mysql-stack-windows-sin-admin.git
git remote -v
git push origin main                # publica en ambos
```

## 7. Autenticación

### 7.1 SSH (recomendada)

```powershell
ssh-keygen -t ed25519 -C "felipe.gutierrezri@gmail.com"
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | Set-Clipboard
```

- GitHub: *Settings → SSH and GPG keys → New SSH key* → pegar.
- GitLab: *Preferences → SSH Keys* → pegar.

```powershell
ssh -T git@github.com
ssh -T git@gitlab.com
git remote set-url origin git@github.com:andres-gutierrezri/mysql-stack-windows-sin-admin.git
git remote set-url gitlab git@gitlab.com:andres.gutierrezri/mysql-stack-windows-sin-admin.git
```

> El servicio `ssh-agent` de Windows requiere Administrador para habilitarse; sin él, Git pedirá la frase de la clave en cada operación (o genere la clave con frase vacía solo en equipos personales).

### 7.2 Token de acceso personal (PAT) por HTTPS

- GitHub: *Settings → Developer settings → Personal access tokens → Fine-grained tokens* → permiso *Contents: Read and write* sobre este repositorio.
- GitLab: *Preferences → Access tokens* → alcances `read_repository` y `write_repository`.
- Al hacer `git push`, Git Credential Manager (incluido en Git for Windows) abrirá el inicio de sesión o pedirá usuario y **token como contraseña**.
- **Nunca** escriba el token en el repositorio, en `.env` ni en la URL del remoto.

## 8. Buenas prácticas

### 8.1 Ramificación (Git Flow)

```powershell
git switch -c develop main
git push -u origin develop
git switch -c feature/lts-9-7 develop        # trabajo nuevo
git switch develop ; git merge --no-ff feature/lts-9-7
git switch -c release/1.0.0 develop          # estabilización
git switch main    ; git merge --no-ff release/1.0.0
git switch develop ; git merge --no-ff release/1.0.0
git switch -c hotfix/1.0.1 main              # corrección urgente
```

Ramas: `main` (versiones publicadas), `develop` (integración), `feature/*`, `release/*`, `hotfix/*`.

### 8.2 Conventional Commits

```
feat(install): selecciona puerto alternativo si hay XAMPP
fix(cmd): corrige expansión de %UP% dentro de bucles for
docs(readme): agrega sección de limitaciones
test(ps): cubre Merge-PathEntry con PATH vacío
chore(config): actualiza URL y MD5 de MySQL 9.7.3 LTS
refactor(ps)!: renombra parámetros   # "!" = cambio incompatible
```

### 8.3 Versionado semántico (SemVer) y etiquetas

```powershell
git switch main
git tag -a v1.0.0 -m "Primera versión estable"
git push origin v1.0.0                       # con doble push-url, publica en ambos
git push origin --tags
```

`MAYOR.MENOR.PARCHE`: MAYOR = cambios incompatibles (parámetros, estructura), MENOR = funciones compatibles, PARCHE = correcciones.
