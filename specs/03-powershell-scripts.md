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
| `dkdb-image-create` | Asks only for the image name (default `devbox-ubuntu`, so `dkdb-devbox-ubuntu`) and builds `dkdb-<name>`. |
| `dkdb-image-delete` | Menu of `dkdb-` images; deletes the chosen one (single selection). |
| `dkdb-container-create` | Asks for the image (as `dkdb-image-create` does), container name, user and the host projects and tools paths (spec 04) and, if Mutagen is installed, the projects volume type (menu; spec 08); the `bash` volume is fixed. |
| `dkdb-container-start` | Menu of **stopped** `dkdb-` containers. For a Mutagen container it also makes sure the Mutagen daemon is running and creates or resumes the sync session (spec 08). |
| `dkdb-container-stop` | Menu of **running** `dkdb-` containers. It never touches Mutagen (daemon or session). |
| `dkdb-container-connect` | Menu of **running** `dkdb-` containers; opens bash with `docker exec -it -u <user>`. For a Mutagen container it first makes sure the daemon is running and creates or resumes the sync session, flushing only when it creates it (spec 08); the shell opens even if that fails. |
| `dkdb-container-delete` | Menu of **stopped** `dkdb-` containers (a running one must be stopped first); asks `[y/N]` confirmation because the container's home and installed AI client are lost; the host bind-mounted folders are not touched. For a Mutagen container it also terminates that container's Mutagen session (only that one, never the daemon), provided the daemon is running; otherwise `dkdb-mutagen-clean` removes it later. |
| `dkdb-mutagen-start` | Checks whether the Mutagen daemon is running and starts it if not (spec 08). |
| `dkdb-mutagen-stop` | Checks whether the Mutagen daemon is running; if so, flushes the running Mutagen containers and stops it. It is one daemon per user: all Mutagen sessions stop. |
| `dkdb-mutagen-status` | Menu of the `dkdb-` containers that use Mutagen (running or stopped); shows the state and conflicts of its session (spec 08). |
| `dkdb-mutagen-clean` | Lists the orphan `dkdb-` Mutagen sessions (their container no longer exists) in a menu, with an option for all of them, and terminates the chosen ones after a `[y/N]` confirmation. The host folders are not touched. |

- **Location:** `scripts/ps1/`.
- **Colors in `dkdb-container-connect`:** it passes `-e TERM=xterm-256color -e COLORTERM=truecolor` so the default Ubuntu `.bashrc` enables the colored prompt even when `docker exec` provides a plain `xterm`.
- **Bash volume:** `dkdb-container-create` mounts the folder `scripts\bash` that sits next to `scripts\ps1` (resolved by `Get-DevboxBashPath` in the common file) read-only. Nothing is copied.
- **Shared root:** never stored; `Get-DevboxRoot` (common file) deduces it from the script location, `<root>\devbox\scripts\ps1`, and stops with a message if the scripts are somewhere else. The default tools path is `<root>\tools` (`Get-DevboxDefaultToolsPath`).
- **Installation:** the scripts are installed and added to the user PATH by `install/install.ps1` (spec 07), so they can be called by name.
- All of them load the common file holding the prefix and `Select-DevboxItem`.
- `.ps1` files are ASCII with LF line endings; prompts and messages are in English.

## Consequences
- No script touches Docker resources that do not start with `dkdb-`. The only exception is `dkdb-mutagen-stop`: Mutagen has one daemon per user, so stopping it stops all your Mutagen sessions, not only the `dkdb-` ones.
- `dkdb-container-connect` does not start stopped containers: use `dkdb-container-start` first.
