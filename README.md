# docker-devbox-ubuntu

A lightweight Ubuntu Docker image, managed with PowerShell scripts, for running an AI client (Claude Code, GitHub Copilot CLI) inside an isolated environment.

## Overview

| # | Piece | What it is |
|---|-------|------------|
| 1 | Image | Minimal Ubuntu 26.04 LTS with generic development tools and Python 3. No user and no AI client. |
| 2 | Container | The user is created when the container is created (not in the image); the main process runs as that user. **One AI client per container.** |
| 3 | PowerShell scripts | Create and delete images; create, start, stop, connect to and delete containers; manage the optional Mutagen sync (daemon, status, clean-up). |
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

It asks for the **shared root** (default `C:\shared\`, created on confirmation) and the **branch or tag** to download (default `main`), downloads `scripts\{bash,ps1,docker}` into `<root>\devbox\` plus `uninstall.ps1` into `<root>\devbox\install\` (asking before overwriting an existing install), creates `<root>\tools\` and adds `<root>\devbox\scripts\ps1` to your user PATH (offering to remove the PATH entries of a previous installation). Then **open a new terminal**.

- Update: run the installer again.
- Uninstall: run `C:\shared\devbox\install\uninstall.ps1` (it keeps `tools`, your projects, containers and images).
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
| 3 | `dkdb-container-start` | Starts a stopped container. For a Mutagen container the projects are **not** synchronized by default: add `-SyncAll` (everything) or `-SyncFolder <path>[,<path>...]` (only those folders). |
| 4 | `dkdb-container-connect` | Opens a shell in a running container; the same sync parameters as `dkdb-container-start`. |
| 5 | `dkdb-container-stop` | Stops a running container. |
| 6 | `dkdb-container-delete` | Deletes a stopped container (asks for confirmation). |
| 7 | `dkdb-image-delete` | Deletes an image. |
| 8 | `dkdb-mutagen-start` | Starts the Mutagen daemon if it is not running (optional Mutagen). |
| 9 | `dkdb-mutagen-stop` | Stops the Mutagen daemon if it is running (stops all Mutagen sessions). |
| 10 | `dkdb-mutagen-status` | Shows the sync state, conflicts and progress (`So far X of Y files`, and whether it moved since the previous query) of a Mutagen container (menu). |
| 11 | `dkdb-mutagen-clean` | Terminates leftover Mutagen sessions (container deleted outside the scripts, or daemon stopped at that time; menu, asks first). |
| 12 | `dkdb-verify` | Checks the installed package against `manifest.json`. |
| 13 | `dkdb-mutagen-sync` | Synchronizes the projects of a running Mutagen container (menu): everything with `-SyncAll`, or only the folders of `-SyncFolder <path>[,<path>...]`, added one call at a time. One of them is required. |
| 14 | `dkdb-version` | Shows every version: the project, each file, the tools, the images and the containers. |
| 15 | `dkdb-info` | Shows how everything is set up: folders, PATH, Docker, images, containers, volumes and Mutagen. |

### Synchronization with Mutagen

Three levels, from the most to the least conservative, because the last one can take very long:

| # | Level | Parameter | What happens |
|---|-------|-----------|--------------|
| 1 | Nothing (the default) | none, or `-SyncOff` | The Mutagen daemon is started and the sessions that already exist are **paused**. Nothing is created and nothing is synchronized. |
| 2 | Some folders | `-SyncFolder <path>[,<path>...]` | Only those folders are synchronized, added to the ones already synchronized. |
| 3 | Everything | `-SyncAll` | The whole projects folder. |

```powershell
dkdb-container-start                            # level 1: starts the container and the daemon, nothing is synchronized
dkdb-container-start -SyncFolder repo1          # level 2: only repo1
dkdb-mutagen-sync -SyncFolder repo2             # add repo2 to the synchronized folders
dkdb-container-connect -SyncFolder repo3,repo4  # add repo3 and repo4 and open a shell
dkdb-mutagen-sync -SyncAll                      # level 3: synchronize everything
```

A very large projects folder can make the full first synchronization slow or fail; adding folders one by one avoids that.

1. The three parameters exclude each other. `dkdb-mutagen-sync` has no default: without `-SyncFolder` or `-SyncAll` it shows its usage and does nothing.
2. A folder path is relative to the projects folder (or absolute inside it) and must exist. Several folders go in one comma-separated list; to add more later, run the command again.
3. **Sessions:** each folder has its own Mutagen session, named from the container and the folder, so starting and stopping the container with the same `-SyncFolder` reuses the same session; a different folder adds one more, and `-SyncAll` adds the whole-folder session. Stopping a container never touches Mutagen, and deleting it terminates its sessions.
4. A level-2 run resumes or creates only the folders you name; other existing sessions stay as they are (paused or not). To keep several folders going, name them all.
5. A folder inside one already synchronized is skipped; one that contains synchronized folders is refused (terminate those sessions first); with the whole-folder session active nothing is added; `-SyncAll` with only folder sessions asks before replacing them (the files are not touched).

### Help

Every script prints its usage with `-Help` (the bash installers also with `-h` and `--help`), with or without other parameters, and does nothing else:

```powershell
dkdb-container-start -Help
dkdb-mutagen-sync -Help
& "C:\shared\devbox\install\install.ps1" -Help
```

Problems? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Version and integrity

`manifest.json` lists the project version, the image version and every file with its own version (each file also carries a `# Version: x.y.z` line). It is installed as `<root>\devbox\manifest.json`, and:

1. Every script prints its own version and the project version when it starts.
2. `install.ps1` downloads the manifest first and then exactly the files it lists, checking that each file has the version the manifest says (a mixed or partial download stops the installation). When an update changes the major.minor version (0.x), it tells you to rebuild the images and recreate the containers.
3. `dkdb-verify` checks the installed package against the manifest. `dkdb-image-create` and `dkdb-container-create`, which create things, stop if the package is inconsistent. `dkdb-container-start` and `dkdb-container-connect` only warn: **a version bump never blocks the use of an existing container.**
4. Images have their own version (`image` in the manifest, bumped only when the `Dockerfile` or the entrypoint change, so a new project version never touches them) and are tagged with it (`dkdb-<name>:<image version>`, never `latest`). `dkdb-container-create` uses the highest tag that is compatible with the scripts (same major.minor in 0.x, same major from 1.0) with the image version the scripts expect; when only older images exist it uses the highest of them with a warning. `start` and `connect` show the version of the image the container was created from and, when it is not compatible with the scripts, only warn: the container keeps working with its image, and you update it by rebuilding the image and recreating the container when you want.

## Folders

Host (default values; the shared root is chosen once by `install.ps1`):

```
C:\shared\                       shared root
  devbox\
    manifest.json                 project version and the version of every file
    install\                     install.ps1 (downloaded by hand) and uninstall.ps1
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
manifest.json       Project version and the version of every file (the installer's file list)
install/    install.ps1 (the single-file installer) and uninstall.ps1
scripts/
  docker/   Dockerfile and entrypoint.sh
  ps1/      PowerShell scripts (dkdb-*.ps1)
  bash/     AI client installers
specs/      Project specifications
TROUBLESHOOTING.md   Typical problems and fixes
LICENSE              Unlicense (public domain)
```

When you add, rename or remove a file under `scripts/` or `install/`, update `manifest.json`: the installer downloads exactly the files it lists (see `CLAUDE.md`).

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

## License

This is free and unencumbered software released into the public domain, under the [Unlicense](LICENSE). Third-party tools that the scripts download, such as Mutagen, keep their own licenses.

**Disclaimer:** this project is provided "as is", without warranty of any kind, including security. The author accepts no liability whatsoever for its use, copying, modification or forking. Use it at your own risk. The container is meant for local development and uses a weak password by design.
