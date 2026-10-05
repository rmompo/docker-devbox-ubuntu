# 07 - Installer

## Context
The scripts must be easy to get and to call from any folder, without cloning the repository.

## Reasoning
1. One file to download is simpler than a clone -> `install/install.ps1` fetches everything else.
2. A clone needs git; plain HTTPS does not -> files are downloaded one by one from `raw.githubusercontent.com`.
3. The file list must be known without an API -> a fixed list inside the script.
4. Scripts must run by name -> `scripts\ps1` is added to the user PATH (no admin rights needed).
5. A wrong path must never be created silently -> always check it, ask before creating, stop if it cannot be created.
6. Reinstalling overwrites files -> warn and ask first.

## Decision
- **Settings (top of `install.ps1`):** `$RepoUrl` (`https://github.com/rmompo/docker-devbox-ubuntu`), `$Branch` (`main`), `$DefaultInstallPath` (`C:\DataDocker\docker-devbox-ubuntu\`), `$Files`.
- **Install path:** asked with a default; `/` is normalized to `\`; it must be absolute and without commas. If it does not exist, the user is asked whether to create it; if it is declined or cannot be created, the installer stops.
- **Layout:** `<path>\scripts\bash`, `<path>\scripts\ps1`, `<path>\scripts\docker`.
- **Existing install:** warns that files are overwritten and asks `[y/N]`; files no longer in the repository are not deleted.
- **Download:** each file is saved as is (LF preserved); an error or an empty file stops the installer. `.ps1` files are unblocked (`Unblock-File`).
- **PATH:** `<path>\scripts\ps1` is appended to the user PATH (registry) without duplicates, and to the current session.
- **Execution policy:** if `Restricted` or `AllSigned`, a warning with the fix is printed; it is never changed.

## Consequences
- The repository must be public.
- `$Files` must be updated whenever a file is added, renamed or removed under `scripts/bash`, `scripts/ps1` or `scripts/docker`; otherwise it is not installed.
- Open terminals need to be reopened to see the new PATH.
- Updating = running `install.ps1` again.
