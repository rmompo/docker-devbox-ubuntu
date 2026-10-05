# docker-ubuntu-devbox

A lightweight Ubuntu Docker image, managed with PowerShell scripts, for running an AI client (Claude Code, GitHub Copilot CLI) inside an isolated environment.

## Overview

| # | Piece | What it is |
|---|-------|------------|
| 1 | Image | Minimal Ubuntu 26.04 LTS with generic development tools and Python 3. No user and no AI client. |
| 2 | Container | The user is created when the container is created (not in the image); the main process runs as that user. **One AI client per container.** |
| 3 | PowerShell scripts | Create and delete images; create, start, stop, connect to and delete containers. |
| 4 | Installer | `install/install.ps1`, the only file you download. It installs the rest. |
| 5 | Volumes | `proyectos` (your projects) and `bash` (AI client installers, read-only). Optionally, `proyectos` can be synchronized with [Mutagen](https://mutagen.io) instead of a bind mount. |

Conventions:

1. **Prefix `dkdb`:** every image, container and user is named `dkdb-<name>`.
2. **Language:** documentation, scripts, messages and comments are in English.

## Requirements

1. Windows with PowerShell 5.1 or newer.
2. Docker Desktop, running.
3. Internet access (the installer downloads from GitHub, and the AI clients download their own installers).

## Installation

### 1. Host (Windows)

In PowerShell, download the installer to a temp folder and run it:

```powershell
$dir = Join-Path $env:TEMP 'devbox-install'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
iwr -UseBasicParsing 'https://raw.githubusercontent.com/rmompo/docker-devbox-ubuntu/main/install/install.ps1' -OutFile "$dir\install.ps1"
powershell -ExecutionPolicy Bypass -File "$dir\install.ps1"
```

It asks for the install path (default `C:\DataDocker\docker-devbox-ubuntu\`, created on confirmation), downloads `scripts\{bash,ps1,docker}` (asking before overwriting an existing install) and adds `scripts\ps1` to your user PATH. Then **open a new terminal**.

- Update: run the installer again.
- Scripts blocked by the execution policy: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`.

Then, in a new PowerShell terminal, create the image and a container, and open a shell in it:

```powershell
dkdb-image-create
dkdb-container-create
dkdb-container-start
dkdb-container-connect
```

### 2. Guest (Docker container)

Inside the container (opened with `dkdb-container-connect`), install one AI client (one per container):

```bash
bash ~/devbox/bash/dkdb-install-claudecode.sh       # Claude Code
bash ~/devbox/bash/dkdb-install-ghcopilot-cli.sh    # GitHub Copilot CLI
```

## Usage

From any folder, in a new terminal:

| # | Command | What it does |
|---|---------|--------------|
| 1 | `dkdb-image-create` | Builds the image `dkdb-<name>`. |
| 2 | `dkdb-container-create` | Creates a container (asks for image, container name, user and projects path). |
| 3 | `dkdb-container-start` | Starts a stopped container. |
| 4 | `dkdb-container-connect` | Opens a shell in a running container. |
| 5 | `dkdb-container-stop` | Stops a running container. |
| 6 | `dkdb-container-delete` | Deletes a stopped container (asks for confirmation). |
| 7 | `dkdb-image-delete` | Deletes an image. |
| 8 | `dkdb-mutagen-start` | Starts the Mutagen daemon if it is not running (optional Mutagen). |
| 9 | `dkdb-mutagen-stop` | Stops the Mutagen daemon if it is running (stops all Mutagen sessions). |

Containers created before the `bash` volume existed still mount the old `resources` folder; recreate them.

## Volumes

| # | Host | Inside the container | Mode |
|---|------|----------------------|------|
| 1 | Projects path, asked by `dkdb-container-create` (default `C:\Localfiles\proyectos\`) | `~/devbox/proyectos` | read/write |
| 2 | `<install path>\scripts\bash` (default: `C:\DataDocker\docker-devbox-ubuntu\scripts\bash`) | `~/devbox/bash` | read-only |

The `bash` path is not asked: it is the `scripts\bash` folder next to the scripts, so it follows the install path you chose (the default install path gives the value shown above). The projects path must already exist; nothing is created for you.

**Mutagen (optional):** `dkdb-container-create` asks whether the projects volume is a Docker bind mount or a Mutagen sync. If you pick Mutagen and it is not installed, the script asks before downloading it (about 100 MB, checksum verified, into `<install path>\mutagen`). With Mutagen, `~/devbox/proyectos` is a folder inside the container, kept in sync with the host projects path (everything, including `.git`; only symbolic links are ignored), and `dkdb-container-start` creates or resumes the session. Nothing else has to be run. Mutagen is third-party and is downloaded from its official release (MIT, with SSPL-licensed parts); see [spec 08](specs/08-mutagen.md).

## Repository layout

```
install/    install.ps1, the single-file installer
scripts/
  docker/   Dockerfile and entrypoint.sh
  ps1/      PowerShell scripts (dkdb-*.ps1)
  bash/     AI client installers
specs/      Project specifications
```

When you add, rename or remove a file under `scripts/`, update the `$Files` list in `install/install.ps1`; otherwise the installer will not download it.

## Methodology (CoT)

Each spec follows the pattern **Context -> Reasoning -> Decision -> Consequences**. Every decision was validated one by one with the project owner before being written down.

## Specs

| # | Spec | Content |
|---|------|---------|
| 01 | [Global conventions](specs/01-conventions.md) | Prefix, naming, language, encoding, LF, menus |
| 02 | [Docker image](specs/02-image.md) | Base, packages, colors, entrypoint |
| 03 | [PowerShell scripts](specs/03-powershell-scripts.md) | Image and container management |
| 04 | [Volumes and user](specs/04-volumes-user.md) | Host paths, mounts, user, sudo |
| 05 | [AI client installation](specs/05-ai-clients.md) | Bash scripts for Claude Code and Copilot CLI |
| 06 | [Verifications and open items](specs/06-verifications.md) | Checks already done and items still to validate |
| 07 | [Installer](specs/07-installer.md) | install.ps1: download, install path, PATH |
| 08 | [Mutagen](specs/08-mutagen.md) | Optional projects sync (avoids slow 9p mounts) |
