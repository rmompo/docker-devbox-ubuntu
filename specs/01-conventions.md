# 01 - Global conventions

## Context
Several scripts and the image share names, encoding and ways of interacting with the user. It is best to fix these once.

## Reasoning
1. Scripts must find the project's resources on their own -> a common prefix lets them filter without touching foreign resources.
2. Filtering by plain `dkdb` would also match `dkdbfoo` -> filter by `dkdb-`, with the hyphen.
3. The prefix may change (it already changed twice) -> define it in a single file loaded by every script (file names carry the prefix too, see "Script names").
4. Files are used from both Linux and Windows -> everything is UTF-8 without BOM and LF; a BOM breaks `#!/bin/bash`.
5. Windows PowerShell 5.1 reads a BOM-less `.ps1` as ANSI and corrupts non-ASCII characters -> `.ps1` files are pure ASCII, so no BOM is needed and the PowerShell version does not matter.
6. The project owner wants everything in English -> documentation, scripts, prompts, messages and comments are English, which is also naturally ASCII.
7. Users must pick from lists -> a dependency-free, reusable navigable menu.

## Decision
- **Language:** English for documentation, scripts, prompts, messages and comments.
- **Prefix:** `dkdb`, defined in one common place. Image, container and user are named `dkdb-<input>`; default input value: `devbox-ubuntu`, so the image, the container and the user are `dkdb-devbox-ubuntu` by default.
- **Prompts:** the default is displayed with the prefix (`Image name [dkdb-devbox-ubuntu:0.1.0]:` for images, which also show the version that will be built or used), but the user types only the own part, without prefix or version; the script always prepends `dkdb-`. Typing the prefix yourself would produce `dkdb-dkdb-...`.
- **Length:** `dkdb-` takes 5 characters; the typed text allows up to 27 (Linux limits user names to 32).
- **Filtering:** always by `dkdb-`.
- **Encoding:** UTF-8 without BOM and LF for every file. A BOM would only be used in a `.ps1` that needs non-ASCII characters (currently none).
- **`.gitattributes`:** `* text=auto eol=lf` (replaces the initial `* text=auto`).
- **Script names:** every file under `scripts/ps1/` and `scripts/bash/` is named `dkdb-<name>` so that, once `scripts\ps1` is on the PATH, commands cannot be confused with others. File names cannot use `$DevboxPrefix`: changing the prefix also means renaming these files.
- **Repository layout:** `install/`, `scripts/docker/`, `scripts/ps1/`, `scripts/bash/`, `specs/`.
- **Version and integrity:** `manifest.json` in the repository root is the inventory of the package: `version` (semantic versioning, starting at `0.1.0`) and `files`, the version of every file the installer downloads (and of `install/install.ps1`). Each listed file carries `# Version: x.y.z` in its first lines; manifest and header must match (checked by `Get-DevboxIntegrity`: existence and version; no hashes). Installed as `<root>\devbox\manifest.json`. Every `dkdb-*.ps1`, `install.ps1`, `uninstall.ps1`, the bash installers and the entrypoint print their own version and the project version when they start (`Show-DevboxVersion -Script $PSCommandPath` in the common file). The bash scripts take the project version from the image environment (`DEVBOX_VERSION`; `unknown` in an older image). Rules for bumping versions are in `CLAUDE.md`, which is mandatory.
- **Menu:** common function `Select-DevboxItem`, navigation only: up/down arrows, Enter confirms, Esc cancels. No numbers. ASCII, no external modules.

## Consequences
- Changing the prefix means editing one line plus renaming the `dkdb-*` files and updating their references (scripts, installer file lists, docs).
- The menu needs an interactive console; it does not work without a keyboard.
