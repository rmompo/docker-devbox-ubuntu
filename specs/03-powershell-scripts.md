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
| `image-create` | Asks only for the image name (default `ubuntu`) and builds `dkdb-<name>`. |
| `image-delete` | Menu of `dkdb-` images; deletes the chosen one (single selection). |
| `container-create` | Asks for the image (as `image-create` does), container name, user and the host projects path (spec 04); the `bash` volume is fixed. |
| `container-start` | Menu of **stopped** `dkdb-` containers. |
| `container-stop` | Menu of **running** `dkdb-` containers. |
| `container-delete` | Menu of **stopped** `dkdb-` containers (a running one must be stopped first); asks `[y/N]` confirmation because the container's home and installed AI client are lost; the host bind-mounted folders are not touched. |
| `container-connect` | Menu of **running** `dkdb-` containers; opens bash with `docker exec -it -u <user>`. |

- **Location:** `scripts/ps1/`.
- **Colors in `container-connect`:** it passes `-e TERM=xterm-256color -e COLORTERM=truecolor` so the default Ubuntu `.bashrc` enables the colored prompt even when `docker exec` provides a plain `xterm`.
- **Bash volume:** `container-create` mounts the folder `scripts\bash` that sits next to `scripts\ps1` (resolved by `Get-DevboxBashPath` in the common file) read-only. Nothing is copied.
- **Installation:** the scripts are installed and added to the user PATH by `install/install.ps1` (spec 07), so they can be called by name.
- All of them load the common file holding the prefix and `Select-DevboxItem`.
- `.ps1` files are ASCII with LF line endings; prompts and messages are in English.

## Consequences
- No script touches resources that do not start with `dkdb-`.
- `container-connect` does not start stopped containers: use `container-start` first.
