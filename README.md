# docker-devbox-ubuntu

A lightweight Ubuntu Docker image, managed with PowerShell scripts, for running an AI client (Claude Code, GitHub Copilot CLI) inside an isolated environment.

## Overview

| # | Piece | What it is |
|---|-------|------------|
| 1 | Image | Minimal Ubuntu 26.04 LTS with generic development tools and Python 3. No user and no AI client. |
| 2 | Container | The user is created when the container is created (not in the image); the main process runs as that user. **One AI client per container.** |
| 3 | PowerShell scripts | Create and delete images; create, start, stop, connect to and delete containers; start and stop the optional Mutagen daemon. |
| 4 | Installer | `install/install.ps1`, the only file you download. It installs the rest. |
| 5 | Volumes | `projects` (your projects), `tools` (shared tools such as Maven or JDKs) and `bash` (AI client installers, read-only). Optionally, `projects` can be synchronized with [Mutagen](https://mutagen.io) instead of a bind mount. |

Conventions:

1. **Prefix `dkdb`:** every image, container and user is named `dkdb-<name>`.
2. **Language:** documentation, scripts, messages and comments are in English.

## Requirements

1. Windows with PowerShell 5.1 or newer.
2. Docker Desktop, running.
3. Internet access (the installer downloads from GitHub, and the AI clients download their own installers).

## Installation

### 1. Host (Windows)

In PowerShell, download the installer to `C:\shared\devbox\install\` and run it:

```powershell
$dir = 'C:\shared\devbox\install'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
iwr -UseBasicParsing 'https://raw.githubusercontent.com/rmompo/docker-devbox-ubuntu/main/install/install.ps1' -OutFile "$dir\install.ps1"
powershell -ExecutionPolicy Bypass -File "$dir\install.ps1"
```

It asks for the **shared root** (default `C:\shared\`, created on confirmation), downloads `scripts\{bash,ps1,docker}` into `<root>\devbox\` (asking before overwriting an existing install), creates `<root>\tools\` and adds `<root>\devbox\scripts\ps1` to your user PATH (offering to remove the PATH entries of a previous installation). Then **open a new terminal**.

- Update: run the installer again.
- Change the shared root: run the installer with the new root and recreate your containers (they keep the host paths they were created with).
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
| 2 | `dkdb-container-create` | Creates a container (asks for image, container name, user, projects path, tools path and the projects volume type: Docker bind mount or Mutagen). |
| 3 | `dkdb-container-start` | Starts a stopped container. |
| 4 | `dkdb-container-connect` | Opens a shell in a running container. |
| 5 | `dkdb-container-stop` | Stops a running container. |
| 6 | `dkdb-container-delete` | Deletes a stopped container (asks for confirmation). |
| 7 | `dkdb-image-delete` | Deletes an image. |
| 8 | `dkdb-mutagen-start` | Starts the Mutagen daemon if it is not running (optional Mutagen). |
| 9 | `dkdb-mutagen-stop` | Stops the Mutagen daemon if it is running (stops all Mutagen sessions). |

Containers created with an older layout (`~/devbox/proyectos`, `~/devbox/resources`, or without the `bash` volume) must be recreated, and the image rebuilt with `dkdb-image-create` (the entrypoint changed).

## Folders

Host (default values; the shared root is chosen once by `install.ps1`):

```
C:\shared\                       shared root
  devbox\
    install\                     where install.ps1 is downloaded
    scripts\
      ps1\                       added to the user PATH (Windows)
      bash\                      AI client installers -> ~/devbox/bash (read-only)
      docker\                    Dockerfile and entrypoint.sh
    mutagen\                     Mutagen, only if you choose it (never mounted in a container)
  tools\                         shared tools (Maven, JDKs...) -> ~/devbox/tools
C:\LocalFiles\proyectos\         your projects -> ~/devbox/projects
```

Inside the container:

| # | Host (default) | Inside the container | Mode |
|---|----------------|----------------------|------|
| 1 | Projects path, asked by `dkdb-container-create` (default `C:\LocalFiles\proyectos\`) | `~/devbox/projects` | read/write |
| 2 | Tools path, asked by `dkdb-container-create` (default `<root>\tools`, that is `C:\shared\tools`): tools such as Maven or JDKs, installed once and shared by every container | `~/devbox/tools` | read/write |
| 3 | `<root>\devbox\scripts\bash` (default `C:\shared\devbox\scripts\bash`) | `~/devbox/bash` | read-only |

The `bash` path is not asked, and the default tools path is not stored anywhere: both are deduced from where the scripts are, so they follow the shared root you chose. The projects and tools paths must already exist (the installer creates the default tools folder); nothing else is created for you.

**Mutagen (optional):** `dkdb-container-create` asks whether the projects volume is a Docker bind mount or a Mutagen sync. If you pick Mutagen and it is not installed, the script asks before downloading it (about 100 MB, checksum verified, into `<root>\devbox\mutagen`). With Mutagen, `~/devbox/projects` is a folder inside the container, kept in sync with the host projects path (everything, including `.git`; only symbolic links are ignored), and `dkdb-container-start` creates or resumes the session. Nothing else has to be run. `dkdb-mutagen-start` and `dkdb-mutagen-stop` check and start or stop the Mutagen daemon by hand (stopping it stops all your Mutagen sessions). `tools` is never synchronized: it stays a bind mount. Mutagen is third-party and is downloaded from its official release (MIT, with SSPL-licensed parts); see [spec 08](specs/08-mutagen.md).

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
| 07 | [Installer](specs/07-installer.md) | install.ps1: shared root, download, PATH |
| 08 | [Mutagen](specs/08-mutagen.md) | Optional projects sync (avoids slow 9p mounts) |
