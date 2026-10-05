# docker-ubuntu-devbox

A lightweight Ubuntu Docker image, managed with PowerShell scripts, for installing an AI client (Claude Code, GitHub Copilot CLI, etc.) inside an isolated environment.

## Overview

- **Image:** minimal Ubuntu 26.04 LTS with generic development tools and Python 3. It ships with no user and no AI client.
- **Container:** the user is created when the container is created (not in the image); the main process runs as that user.
- **Installer:** `install/install.ps1` is the only file to download; it fetches `scripts/` from the repository, adds `scripts\ps1` to the user PATH.
- **PowerShell scripts:** create and delete images; create, start, stop and connect to containers.
- **AI clients:** installed inside the container with bash scripts from the mounted `bash` volume. **One client per container.**
- **Volumes:** `proyectos` (host projects) and `bash` (`<install path>\scripts\bash`, read-only) mounted inside the container.
- **Prefix (critical):** `dkdb`. Every name (image, container, user) is `dkdb-<name>`.
- **Language:** documentation, scripts, messages and comments are all written in English.

## Repository layout

```
install/    install.ps1: the single-file installer
scripts/
  docker/   Dockerfile and entrypoint.sh
  ps1/      PowerShell scripts (image-*, container-*, common.ps1)
  bash/     AI client installers, mounted read-only into the container
specs/      Project specifications
```

## Quick start

Download only `install/install.ps1` (the repository must be public) and run it; it asks for the install path (default `C:\DataDocker\docker-devbox-ubuntu\`). Then, in a new terminal:

```powershell
image-create       # build dkdb-<name>
container-create   # create a container (mounts proyectos and scripts\bash)
container-start
container-connect  # then, inside: bash ~/devbox/bash/install-claudecode.sh
container-stop
container-delete   # stopped containers only
image-delete
```

Re-run `install.ps1` to update the scripts.

## Methodology (CoT)

Each spec follows the pattern **Context -> Reasoning -> Decision -> Consequences**. Every decision was validated one by one with the project owner before being written down here.

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
