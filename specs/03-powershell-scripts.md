# 03 - PowerShell scripts

## Context
Daily management of images and containers must be fast, without remembering Docker commands or full names.

## Reasoning
1. Every resource carries the prefix -> scripts can list them and offer them in a menu.
2. Picking from a list avoids typing errors -> common navigable menu (spec 01).
3. Each script does one thing -> one script per operation.
4. Destructive and create operations work on a single item at a time -> single selection.

## Decision

| Script | Behavior |
|---|---|
| `dkdb-image-create` | Asks only for the image name (default `devbox-ubuntu`, so `dkdb-devbox-ubuntu`; the prompt shows the version it will be tagged with) and builds `dkdb-<name>:<version>`. |
| `dkdb-image-delete` | Menu of `dkdb-` images; deletes the chosen one (single selection). |
| `dkdb-container-create` | Asks for the image (as `dkdb-image-create` does; the default is shown with the highest compatible version that will be used), container name, user and the host projects and tools paths (spec 04) and, if Mutagen is installed, the projects volume type (menu; spec 08); the `bash` volume is fixed. |
| `dkdb-container-start` | Menu of **stopped** `dkdb-` containers. For a Mutagen container the Mutagen daemon is always started and the synchronization menu is shown (spec 08): No sync (the first option and the default: existing sessions are paused), the folders already registered as sessions, All registered and Add... |
| `dkdb-container-stop` | Menu of **running** `dkdb-` containers. It never touches Mutagen (daemon or session). |
| `dkdb-container-connect` | Menu of **running** `dkdb-` containers; opens bash with `docker exec -it -u <user>`. For a Mutagen container it shows the same synchronization menu as `dkdb-container-start` before the shell; the shell opens even if the synchronization fails. |
| `dkdb-container-delete` | Menu of **stopped** `dkdb-` containers (a running one must be stopped first); asks `[y/N]` confirmation because the container's home and installed AI client are lost; the host bind-mounted folders are not touched. For a Mutagen container it also terminates that container's Mutagen session (only that one, never the daemon), provided the daemon is running; otherwise `dkdb-mutagen-clean` removes it later. |
| `dkdb-mutagen-start` | Checks whether the Mutagen daemon is running and starts it if not (spec 08). |
| `dkdb-mutagen-stop` | Checks whether the Mutagen daemon is running; if so, flushes the running Mutagen containers and stops it. It is one daemon per user: all Mutagen sessions stop. |
| `dkdb-mutagen-status` | Menu of the `dkdb-` containers that use Mutagen (running or stopped); shows the state and conflicts of its session and, below, a progress summary (`So far X of Y files`) with whether it moved since the previous query (spec 08). |
| `dkdb-mutagen-clean` | Lists the orphan `dkdb-` Mutagen sessions (their container no longer exists) in a menu, with an option for all of them, and terminates the chosen ones after a `[y/N]` confirmation. The host folders are not touched. |
| `dkdb-verify` | Checks the installed package against `manifest.json`: every listed file must exist and have the version of the manifest; files that the manifest does not list are reported as notes. Exit code 1 when something is inconsistent. |
| `dkdb-mutagen-sync` | Menu of the **running** `dkdb-` containers that use Mutagen, then the synchronization menu (spec 08). Choosing a folder adds it to the active ones (pausing the ones it covers); No sync pauses the sessions of the container. |
| `dkdb-version` | Prints every version: the project and the image version of the manifest, each file (manifest against its header), PowerShell, Docker, Mutagen (against the minimum), each image and each container with its compatibility. Works without Docker for the first sections. |
| `dkdb-info` | Prints how everything is set up: shared root and folders, PATH, Docker, images, containers (state, user, volume type, mounts) and Mutagen (daemon and sessions with their progress). |

- **Location:** `scripts/ps1/`.
- **Native programs:** Mutagen is run through `Invoke-DevboxNative` when its output is read: it captures standard output and error output separately, with the exit code, because in Windows PowerShell 5.1 the error lines of a program mixed in with `2>&1` become verbose error records (and can stop a script that sets `ErrorActionPreference` to `Stop`). `mutagen daemon start` is not run through it: the background daemon would keep the pipes open.
- **Help and manual:** every script takes `-Help` (its usage, through `Show-DevboxHelp`) and `-Man` (its manual, through `Show-DevboxMan`; spec 01), before doing anything else.
- **Synchronization menu:** `dkdb-container-start`, `dkdb-container-connect` and `dkdb-mutagen-sync` have no sync parameters, only `-Help` and `-Man`. For a Mutagen container they call `Invoke-DevboxSyncPick` (common file): No sync, the folders registered as sessions of the container, All registered and Add.... It returns Ok and Active; the hierarchy rules are in spec 08. The parameters are native PowerShell with `[CmdletBinding(PositionalBinding = $false)]`, so PowerShell itself rejects stray arguments. The menu needs an interactive console, as the container menus do.
- **Version and integrity (spec 01):** every script prints its own version and the project version when it starts. `dkdb-image-create` and `dkdb-container-create` (they create things) check the installed package against `manifest.json` (`Assert-DevboxIntegrity`) and stop if it is inconsistent. `dkdb-image-create` tags the image with the image version (`image` in the manifest), never `latest`. `dkdb-container-create` uses the highest tag of `dkdb-<name>` that is compatible with the image version that the scripts expect; when there is none it uses the highest older tag with a warning, and stops only when no image of that name exists. After updating the scripts nothing that uses an image or a container created before is blocked. **`dkdb-container-start` and `dkdb-container-connect` are never blocked by versions**: an inconsistent package (`Assert-DevboxIntegrity -WarnOnly`) or an image whose version (`DEVBOX_IMAGE_VERSION`, read from the container environment) is not compatible with the one the scripts expect (`Test-DevboxContainerVersion`) only produces a warning and a `Next:` hint (rebuild the image and recreate the container); the container keeps working with the image it was created from. `dkdb-container-stop` and `dkdb-container-delete` never check versions.
- **State file:** after the synchronization menu, `dkdb-container-connect`, `dkdb-mutagen-status` and `dkdb-mutagen-stop` call `Update-DevboxContainerState`, which writes `~/.devbox-state` inside the container for `dkdb-info.sh` and `dkdb-version.sh` (spec 05 and 08). A failure to write it is silent: it never blocks anything.
- **Colors in `dkdb-container-connect`:** it passes `-e TERM=xterm-256color -e COLORTERM=truecolor` so the default Ubuntu `.bashrc` enables the colored prompt even when `docker exec` provides a plain `xterm`.
- **Bash volume:** `dkdb-container-create` mounts the folder `scripts\bash` that sits next to `scripts\ps1` (resolved by `Get-DevboxBashPath` in the common file) read-only. Nothing is copied.
- **Shared root:** never stored; `Get-DevboxRoot` (common file) deduces it from the script location, `<root>\devbox\scripts\ps1`, and stops with a message if the scripts are somewhere else. The default tools path is `<root>\tools` (`Get-DevboxDefaultToolsPath`).
- **Installation:** the scripts are installed and added to the user PATH by `install/install.ps1` (spec 07), so they can be called by name.
- All of them load the common file holding the prefix and `Select-DevboxItem`.
- `.ps1` files are ASCII with LF line endings; prompts and messages are in English.

## Consequences
- No script touches Docker resources that do not start with `dkdb-`. The only exception is `dkdb-mutagen-stop`: Mutagen has one daemon per user, so stopping it stops all your Mutagen sessions, not only the `dkdb-` ones.
- `dkdb-container-connect` does not start stopped containers: use `dkdb-container-start` first.
