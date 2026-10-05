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
| `dkdb-container-start` | Menu of **stopped** `dkdb-` containers. For a Mutagen container it also makes sure the Mutagen daemon is running and synchronizes the projects (spec 08): the whole folder (default), nothing (`-SyncOff`) or only the folders given with `-SyncFolder <path>[,<path>...]` (incremental: run it again to add more). |
| `dkdb-container-stop` | Menu of **running** `dkdb-` containers. It never touches Mutagen (daemon or session). |
| `dkdb-container-connect` | Menu of **running** `dkdb-` containers; opens bash with `docker exec -it -u <user>`. It accepts the same sync parameters as `dkdb-container-start`. For a Mutagen container it first makes sure the daemon is running and creates or resumes the sync session, flushing only when it creates it (spec 08); the shell opens even if that fails. |
| `dkdb-container-delete` | Menu of **stopped** `dkdb-` containers (a running one must be stopped first); asks `[y/N]` confirmation because the container's home and installed AI client are lost; the host bind-mounted folders are not touched. For a Mutagen container it also terminates that container's Mutagen session (only that one, never the daemon), provided the daemon is running; otherwise `dkdb-mutagen-clean` removes it later. |
| `dkdb-mutagen-start` | Checks whether the Mutagen daemon is running and starts it if not (spec 08). |
| `dkdb-mutagen-stop` | Checks whether the Mutagen daemon is running; if so, flushes the running Mutagen containers and stops it. It is one daemon per user: all Mutagen sessions stop. |
| `dkdb-mutagen-status` | Menu of the `dkdb-` containers that use Mutagen (running or stopped); shows the state and conflicts of its session and, below, a progress summary (`So far X of Y files`) with whether it moved since the previous query (spec 08). |
| `dkdb-mutagen-clean` | Lists the orphan `dkdb-` Mutagen sessions (their container no longer exists) in a menu, with an option for all of them, and terminates the chosen ones after a `[y/N]` confirmation. The host folders are not touched. |
| `dkdb-verify` | Checks the installed package against `manifest.json`: every listed file must exist and have the version of the manifest; files that the manifest does not list are reported as notes. Exit code 1 when something is inconsistent. |
| `dkdb-mutagen-sync` | Menu of the **running** `dkdb-` containers that use Mutagen; without switches it synchronizes the whole projects folder (it asks `[y/N]` before replacing existing folder sessions), and with `-SyncFolder <path>[,<path>...]` it adds those folders to the synchronization (spec 08). |
| `dkdb-version` | Prints every version: the project and the image version of the manifest, each file (manifest against its header), PowerShell, Docker, Mutagen (against the minimum), each image and each container with its compatibility. Works without Docker for the first sections. |
| `dkdb-info` | Prints how everything is set up: shared root and folders, PATH, Docker, images, containers (state, user, volume type, mounts) and Mutagen (daemon and sessions with their progress). |

- **Location:** `scripts/ps1/`.
- **Help:** every script takes `-Help` and prints its usage (spec 01) through `Show-DevboxHelp`, before doing anything else.
- **Sync parameters:** `dkdb-container-start`, `dkdb-container-connect` and `dkdb-mutagen-sync` take `-SyncOff` (not in `dkdb-mutagen-sync`) and `-SyncFolder <path>[,<path>...]`. They are native PowerShell parameters with `[CmdletBinding(PositionalBinding = $false)]`, so PowerShell itself rejects unknown or stray arguments; `Get-DevboxSyncOptions` in the common file only normalizes them and rejects the contradiction `-SyncOff` with `-SyncFolder`. (The double-dash forms `--sync-off` and `--sync-folder` were dropped: Microsoft documents `--` only as the end-of-parameters token and nothing about `--name`.)
- **Version and integrity (spec 01):** every script prints its own version and the project version when it starts. `dkdb-image-create` and `dkdb-container-create` (they create things) check the installed package against `manifest.json` (`Assert-DevboxIntegrity`) and stop if it is inconsistent. `dkdb-image-create` tags the image with the image version (`image` in the manifest), never `latest`. `dkdb-container-create` uses the highest tag of `dkdb-<name>` that is compatible with the image version that the scripts expect; when there is none it uses the highest older tag with a warning, and stops only when no image of that name exists. After updating the scripts nothing that uses an image or a container created before is blocked. **`dkdb-container-start` and `dkdb-container-connect` are never blocked by versions**: an inconsistent package (`Assert-DevboxIntegrity -WarnOnly`) or an image whose version (`DEVBOX_IMAGE_VERSION`, read from the container environment) is not compatible with the one the scripts expect (`Test-DevboxContainerVersion`) only produces a warning and a `Next:` hint (rebuild the image and recreate the container); the container keeps working with the image it was created from. `dkdb-container-stop` and `dkdb-container-delete` never check versions.
- **Colors in `dkdb-container-connect`:** it passes `-e TERM=xterm-256color -e COLORTERM=truecolor` so the default Ubuntu `.bashrc` enables the colored prompt even when `docker exec` provides a plain `xterm`.
- **Bash volume:** `dkdb-container-create` mounts the folder `scripts\bash` that sits next to `scripts\ps1` (resolved by `Get-DevboxBashPath` in the common file) read-only. Nothing is copied.
- **Shared root:** never stored; `Get-DevboxRoot` (common file) deduces it from the script location, `<root>\devbox\scripts\ps1`, and stops with a message if the scripts are somewhere else. The default tools path is `<root>\tools` (`Get-DevboxDefaultToolsPath`).
- **Installation:** the scripts are installed and added to the user PATH by `install/install.ps1` (spec 07), so they can be called by name.
- All of them load the common file holding the prefix and `Select-DevboxItem`.
- `.ps1` files are ASCII with LF line endings; prompts and messages are in English.

## Consequences
- No script touches Docker resources that do not start with `dkdb-`. The only exception is `dkdb-mutagen-stop`: Mutagen has one daemon per user, so stopping it stops all your Mutagen sessions, not only the `dkdb-` ones.
- `dkdb-container-connect` does not start stopped containers: use `dkdb-container-start` first.
