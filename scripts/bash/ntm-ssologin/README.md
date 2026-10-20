# Version: 0.1.2
# ntm-ssologin: ia4d en el contenedor

Prepara un contenedor devbox con Claude Code para usar **ia4d (ntm GenAI Suite)**: llavero para el instalador,
login, instalación y renovación de credenciales. Es exclusivo de los contenedores de ntm con Claude Code.
En el repo de devbox vive en **`scripts/bash/ntm-ssologin/`**, y en el contenedor se ve en
**`~/devbox/bash/ntm-ssologin/`** (dentro de `scripts/bash/`, que el contenedor ve en solo lectura como `~/devbox/bash/`).

> Resumen: `bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh` la primera vez · `claude` como siempre · `bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh renew` si llevas
> **más de 5 días sin usar claude** o ia4d pide autenticarse · `bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh status` para comprobar.

---

## 1. Contenido de la carpeta

| Fichero | Qué es |
|---|---|
| `dkdb-ntm-ssologin-ia4d.sh` | Script principal (idempotente): `all`, `status`, `setup`, `login`, `renew`, `install`. `-h` y `man` para la ayuda. |
| `dkdb-ntm-ssologin-keyring-run.sh` | Ejecuta un comando dentro de una sesión D-Bus con el llavero desbloqueado (lo necesita el instalador). `setup` lo instala como `~/.local/bin/dkdb-keyring-run`. |
| `README.md` | Este manual. |

Las herramientas que faltan las instala `~/devbox/bash/dkdb-install-tools.sh` (un nivel por encima de esta carpeta; grupos `base` y `keyring`), que `dkdb-ntm-ssologin-ia4d.sh` ejecuta solo cuando detecta que faltan.

El instalador de ia4d (`ia4d-installer-linux`, o su `ia4d-installer-linux-x64-<versión>.tar.gz`) **no va en el repo**:
se deja en **`~/devbox/tools/iagentic/`**, donde lo busca el script por defecto. También vale junto a la carpeta del script o
indicándolo con `IA4D_INSTALLER=/ruta`. Si solo está el `tar.gz`, el script lo extrae en esa misma carpeta, que debe ser
escribible.

---

## 2. Cómo funciona ia4d: dos sesiones distintas

| Sesión | Dónde | Dura | Quién la usa | Se renueva |
|---|---|---|---|---|
| **Plugins** | `~/.ia4d/.infra-token` (acceso) y `~/.ia4d/.infra-refresh-token` | acceso 1 h · refresh **5 días** | Plugins y hooks de ia4d dentro de Claude Code | **Sola:** en cada inicio de sesión de claude, el plugin `ia4d-optimization-core` renueva el token de acceso con el refresh token, que rota en cada renovación |
| **Instalador** | Llavero (Secret Service por D-Bus), servicio `ia4d`: `jwt_token`, `refresh_token`, ... | 1 h | `ia4d-installer-linux` (`whoami`, `install`) | No: el instalador vuelve a pedir login cuando lo necesita |

Las dos sesiones se crean juntas con el **login**. Después de una hora, `whoami` dice `✖ expirada`. **Es normal y no
afecta a claude.**

**Por qué hace falta un llavero.** El instalador guarda su sesión con `go-keyring`: en Linux usa el Secret Service por
D-Bus y en Windows el *Administrador de credenciales*. Un contenedor no tiene ninguno de los dos, así que
`dkdb-keyring-run`:

1. Arranca un `dbus-daemon` privado.
2. Arranca `gnome-keyring-daemon` y desbloquea `~/.local/share/keyrings/login.keyring` con `DKDB_KEYRING_PASS`
   (por defecto `devbox`).
3. Ejecuta el comando.
4. Al salir, cierra el bus.

Claude Code **no** necesita el llavero.

**Por qué no se copia nada del host.**
- En Windows no hay ninguna sesión de ia4d.
- El backend **revoca toda la familia de tokens** si dos sitios usan el mismo refresh token (detección de reuso).
  Copiar o sincronizar `~/.ia4d/.infra-*` entre máquinas rompe la sesión de las dos.

**El login.** `login --device-code` **no funciona**: Microsoft responde `AADSTS7000218`, porque la aplicación es de
cliente confidencial. El login válido es el **SSO bridge** de ntm (las direcciones de la plataforma y del bridge las muestra el instalador al arrancar:
`▶ Plataforma: ...` y `▶ SSO bridge: ...`):

```
ia4d-installer login ──> muestra https://<sso-bridge>/cli-auth?port=NNNNN y espera en localhost:NNNNN
navegador (Windows) ──> login Microsoft ──> redirige a http://localhost:NNNNN/callback?access_token=...
```

Ese `localhost` es el de Windows y no el del contenedor, así que el navegador muestra un error. `dkdb-ntm-ssologin-ia4d.sh login`
pide esa URL (sin mostrarla al pegarla) y se la entrega al instalador con `curl`.

---

## 3. Primera vez (contenedor nuevo o recreado)

Requisitos: el contenedor con Claude Code instalado (`dkdb-install-claudecode.sh`), la VPN o red de ntm
(para llegar a la plataforma y al SSO bridge) y el instalador de ia4d en `~/devbox/tools/iagentic/`.

```bash
bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh
```

Qué hace `all` (el comando por defecto), en orden:

1. **setup**: comprueba los paquetes y, si faltan, los instala con `dkdb-install-tools.sh` (`sudo apt-get`; pedirá tu contraseña). `login`, `renew` e `install` hacen esta comprobación antes de empezar.
   Después instala `dkdb-keyring-run` y prueba el llavero.
2. **login**, si la sesión del instalador no es válida:
   1. Muestra una URL `https://<sso-bridge>/cli-auth?port=NNNNN`.
   2. Ábrela en el navegador de Windows y entra con tu cuenta de ntm. Si sale un aviso de certificado, acéptalo: es una IP interna.
   3. Al final el navegador dará error al abrir `http://localhost:NNNNN/callback?...`. **Es lo esperado.**
   4. Copia la dirección completa de la barra, pégala en la terminal (no se ve al pegar) y pulsa Enter. Hazlo sin
      demorarte, porque el instalador no espera indefinidamente.
   5. Debe salir `Autenticado como ...`.
3. **install**: ejecuta el instalador de ia4d dentro del llavero. Si hace preguntas, respóndelas.
4. **status**: resumen en verde, amarillo o rojo.

Después, `claude`.

---

## 4. Uso diario

- `claude` como siempre. No hace falta nada más.
- Comprobar el estado: `bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh status`.
  - **Plugins**: válida hasta una fecha. Es lo que importa. Rojo = hay que renovar.
  - **Installer**: suele salir en amarillo como "expired". Es normal.
  - Termina con código 1 si algo está en rojo.
  - No muestra nombre, email, rol ni grupos, así que la salida se puede copiar en un ticket.

---

## 5. Renovar las credenciales

El refresh token de los plugins dura **5 días** y rota con el uso. Hay que renovar cuando:

- llevas **más de 5 días sin abrir claude**, o `status` muestra `Plugins ... expired` o `no session`;
- ia4d muestra mensajes como `Vuelve a autenticarte: ia4d-installer login`. En este contenedor eso equivale a
  `bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh login` (o `renew`);
- lo indica el equipo de ia4d (por ejemplo, tras cambios de grupos o de rol).

```bash
# cierra antes las sesiones de claude abiertas
bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh renew      # logout + login (URL -> pegar callback)
bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh status
```

`login` sin `renew`:
- no hace nada si la sesión del instalador aún es válida (`Ya autenticado`);
- si ha caducado, hace el login completo.

---

## 6. Actualizar o ejecutar el instalador de ia4d

Cuando llegue una versión nueva (`ia4d-installer-linux-x64-<versión>.tar.gz`):

```bash
cd ~/devbox/tools/iagentic
tar -xzf ia4d-installer-linux-x64-<versión>.tar.gz --exclude='._*'   # sobrescribe ia4d-installer-linux
bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh install                               # hace login antes si hace falta
```

Para ejecutarlo a mano, siempre dentro del llavero:

```bash
cd ~/devbox/tools/iagentic
dkdb-keyring-run ./ia4d-installer-linux           # instalación / actualización
dkdb-keyring-run ./ia4d-installer-linux whoami    # sesión del instalador
dkdb-keyring-run ./ia4d-installer-linux logout    # cerrar sesión
```

> **Atención:** el instalador **no tiene `--help`**. Una opción que no reconoce **lanza la instalación completa**.
> Usa solo los subcomandos conocidos: `login`, `logout`, `whoami`, `install [plugin]`, `uninstall <plugin>` y `policy`.
>
> El instalador vacía `~/.ia4d/` en algunas ejecuciones (conserva `.env*`) y modifica `~/.claude/`:
> `settings.json`, plugins y el marketplace `ia4d-expert-agents-marketplace`.
>
> Un `login` hecho a mano fuera de `dkdb-ntm-ssologin-ia4d.sh` necesita llevar el callback con `curl` desde otra terminal
> (copia la URL `http://localhost:NNNNN/callback?...` de la barra del navegador y ejecuta `curl` con ella dentro del
> contenedor mientras el instalador espera). Mejor usa `dkdb-ntm-ssologin-ia4d.sh login`.

---

## 7. Host y Mutagen

**No hay que sincronizar `~/.claude`, `~/.ia4d` ni `~/.local/share/keyrings` con Windows:**

- **Windows no usa nada de esto.** No hay Claude Code nativo ni sesión de ia4d en el host.
- **El refresh token rota con detección de reuso.** Una copia en otro sitio puede revocar la sesión.
- **El instalador vacía `~/.ia4d`.** Mutagen se detiene entonces por seguridad (`halted-on-root-emptied`).
- **`~/.claude` lleva rutas Linux** (`/home/dkdb-claudecode/...`) y credenciales (`.credentials.json`).

Una vez, en el host (PowerShell):

```powershell
mutagen sync list                                  # localiza las sesiones de .claude y .ia4d
mutagen sync terminate <sesión-de-.claude>         # terminate no borra ficheros de ningún lado
mutagen sync terminate <sesión-de-.ia4d>
# Si Windows no usa Claude Code: borra las copias del host (contienen credenciales)
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude", "$env:USERPROFILE\.ia4d"
```

Si esas sesiones las crea la configuración de los scripts del host (`dkdb-mutagen-sync`, `dkdb-container-connect`),
quítalas también de ahí para que no vuelvan a crearse.

**Coste de no sincronizar:** si se **recrea** el contenedor se pierden el llavero, `~/.ia4d` y `~/.claude`. Basta con
volver a ejecutar `bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh` (un login y la instalación).

---

## 8. Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `whoami` dice `✖ expirada` | La sesión del instalador dura 1 h | Normal. Mira `status` → `Plugins` |
| `No hay sesión activa` en `whoami` lanzado a mano | Se ejecutó fuera del llavero | `dkdb-keyring-run ./ia4d-installer-linux whoami` |
| `status`: `Plugins ... expired` / `no session` | Más de 5 días sin renovar, o `~/.ia4d` vaciado | `bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh renew` |
| ia4d dice `Vuelve a autenticarte: ia4d-installer login` | Refresh token caducado o revocado | `bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh renew` |
| `Keyring: the self-test failed` | Llavero creado con otra contraseña | `DKDB_KEYRING_PASS=<la de entonces>`, o borra `~/.local/share/keyrings/*` y haz `renew` |
| `AADSTS7000218` | Se usó `login --device-code` | Usar `bash ~/devbox/bash/ntm-ssologin/dkdb-ntm-ssologin-ia4d.sh login` (SSO bridge) |
| `The installer stopped waiting` | Pasó demasiado tiempo entre la URL y el callback | Repetir y pegar el callback enseguida |
| La URL del bridge no abre | Sin VPN o red de ntm | Conectar la VPN y repetir |
| `Missing packages ... sudo` | Contenedor de una imagen sin los paquetes | Escribir la contraseña de sudo; `bash ~/devbox/bash/dkdb-install-tools.sh check` lista lo que falta |
| Procesos `<defunct>` (`dbus-daemon`, `gnome-keyring-d`) | El contenedor no tiene init en el PID 1 | Inofensivos; para evitarlos, crear el contenedor con `docker run --init` |

---

## 9. Seguridad

- **Llavero:** está cifrado con `DKDB_KEYRING_PASS` (por defecto `devbox`). Es una contraseña conocida: protege el
  fichero en reposo, no frente a alguien con acceso al contenedor. **No la cambies** una vez creado el llavero.
- **Callback:** la URL lleva el `access_token`. `dkdb-ntm-ssologin-ia4d.sh` la lee sin mostrarla, no la guarda en el historial ni en
  ficheros y se la pasa a `curl` por la entrada estándar (no aparece en `ps`). Fuera del contenedor queda en el historial
  del navegador y, si lo tienes activo, en el historial del portapapeles de Windows (Win+V). Caduca en 1 h.
  Si alguna vez la pegas a mano en un `curl`, limpia el historial (`history -c`).
- **Ficheros con tokens:** `~/.ia4d/.infra-*` tienen permisos `0600`. **No los copies a otra máquina**: la detección
  de reuso revoca la sesión.

---

## 10. Qué toca cada comando

| Comando | Cambia |
|---|---|
| `setup` | Paquetes (`dkdb-install-tools.sh`, sudo apt), `~/.local/bin/dkdb-keyring-run`, el llavero (una entrada de prueba que borra) |
| `login` / `renew` | Llavero (servicio `ia4d`) y `~/.ia4d/.infra-*` |
| `install` | `~/.ia4d/` y `~/.claude/` (lo hace el instalador de ia4d) |
| `status` | Nada (solo lee) |

Nunca toca el host, Mutagen ni otros contenedores.

---

## 11. Limitaciones conocidas

- El flujo completo de `login` con el script (URL, callback y `curl`) requiere el navegador, así que no se ha probado de
  punta a punta; sí se probaron la extracción de la URL, el rechazo de callbacks incorrectos y el mismo flujo a mano.
- No se sabe si cada renovación da un refresh token con 5 días nuevos o si la familia tiene una caducidad absoluta;
  `status` muestra la fecha real.
- No se sabe cuánto espera el instalador el callback: si tardas, repite el login.
- El instalador no tiene `--help` y no se sabe qué pregunta en modo interactivo; por eso `install` lo ejecuta en primer plano.

---

## 12. Para quien mantenga esta carpeta

- No escribas el nombre de la empresa (usa `ntm`) ni direcciones de servidores (IPs, hosts o rutas de la API) en ningún
  fichero de la carpeta: el instalador las muestra al arrancar.
- No imprimas ni guardes tokens ni callbacks; no muestres nombre, email, rol ni grupos (`redact` en `dkdb-ntm-ssologin-ia4d.sh`).
- Los scripts siguen el spec 01 del devbox: ASCII, inglés, LF, `# Version:`, `-h` y `man`, y colores verde (éxito), rojo
  (avisos y errores) y amarillo (siguiente paso). Si cambias el comportamiento, sube `# Version:` y actualiza este manual.
- `~/devbox/bash` es de solo lectura dentro del contenedor: los cambios se hacen en el repo del host.
- No ejecutes `ia4d-installer-linux` con opciones desconocidas (lanza la instalación).
- Para inspeccionar el llavero sin mostrar secretos: `dkdb-keyring-run secret-tool search --all service ia4d | grep -v '^secret ='`.
