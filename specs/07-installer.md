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
- **Settings (top of `install.ps1`):** `$RepoUrl` (`https://github.com/rmompo/docker-devbox-ubuntu`), `$DefaultBranch` (`main`), `$DefaultRootPath` (`C:\shared\`). There is no file list in the script: the list is `manifest.json`.
- **Shared root:** asked once with a default; `/` is normalized to `\`; it must be absolute and without commas. If it does not exist, the user is asked whether to create it; if it is declined or cannot be created, the installer stops. It is **not stored**: the scripts deduce it from their own location (`Get-DevboxRoot`, spec 03).
- **Manifest and version:** `manifest.json` is downloaded first and lands in `<root>\devbox\`. The installer then downloads exactly the files in its `files` section (`install/install.ps1` itself is not downloaded: it was downloaded by hand, and only its version is compared with the manifest, with a warning when it differs). After each download the `# Version:` header of the file must equal the manifest entry, otherwise the installer stops (a partial or mixed download, for example because GitHub caches raw files for a few minutes). It prints `Version: <version>` and repeats it in the final message. Before overwriting, it reads the previous manifest: when the major.minor (0.x) or major (1.0 and later) changed, it tells the user to rebuild the images and recreate the containers.
- **Layout:** `<root>\devbox\scripts\{bash,ps1,docker}` (and `<root>\devbox\install\`, where the installer is downloaded, and `<root>\devbox\mutagen\`, spec 08) plus `<root>\tools\` for the shared tools (spec 04), which the installer creates when missing.
- **Existing install:** warns that files are overwritten and asks `[y/N]`; files no longer in the repository are not deleted (except the old names listed below).
- **Download:** each file is saved as is (LF preserved); an error or an empty file stops the installer. `.ps1` files are unblocked (`Unblock-File`).
- **Branch or tag:** asked with `main` as default (letters, digits, `.`, `_`, `-` and `/` only); it lets you test a branch before merging it. The README downloads `install.ps1` itself from `main`.
- **Uninstaller:** `install/uninstall.ps1` is listed in the manifest and lands in `<root>\devbox\install\`. It removes the PATH entries, `<root>\devbox\scripts` and `<root>\devbox\mutagen` after a `[y/N]` confirmation (stopping the Mutagen daemon first, also after confirmation). It keeps `install`, `tools`, projects, containers and images.
- **PATH:** `<root>\devbox\scripts\ps1` is appended to the user PATH (registry) without duplicates, and to the current session. Other user PATH entries that contain `dkdb-common.ps1` (a previous installation, for example in another root) are listed and removed only after a `[y/N]` confirmation; their files are not deleted.
- **Final message:** reminds the user to make sure Docker Engine is running (Docker Desktop started and ready), then to open a new terminal and run `dkdb-image-create`.
- **Execution policy:** if `Restricted` or `AllSigned`, a warning with the fix is printed; it is never changed.

## Consequences
- The repository must be public.
- The installer does not install Mutagen: `dkdb-container-create` does it on demand (spec 08).
- The manifest must be updated whenever a file is added, renamed, removed or changed under `scripts/` or `install/` (rules in `CLAUDE.md`); otherwise the file is not installed or the integrity check fails.
- Open terminals need to be reopened to see the new PATH.
- Updating = running `install.ps1` again. Changing the root = running it with the new root; containers created before keep their old host paths and must be recreated.
