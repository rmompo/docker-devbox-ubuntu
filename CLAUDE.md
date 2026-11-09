# CLAUDE.md

Instructions for working on this repository (docker-devbox-ubuntu). The design lives in `specs/`; read the relevant spec before changing a script.

## Versioning and integrity (MANDATORY)

`manifest.json` is the single inventory of the package: the project `version` and, in `files`, every file that the installer downloads with the version of each one. Every file listed there carries its own version in a `# Version: x.y.z` line in its first lines (`.ps1`, `.sh`, `Dockerfile`).

**These rules are MANDATORY; follow them in every change, without being asked:**

1. **Changing a listed file means bumping its version.** Raise the `# Version:` line of the file and its entry in `manifest.json` in the same change. Patch (0.1.0 -> 0.1.1) for fixes and wording; minor (0.1.0 -> 0.2.0) for a change of behavior. They must always be equal.
2. **Adding, renaming or removing a file under `scripts/` or `install/`** means adding, renaming or removing its entry in `manifest.json` `files` and giving a new file its `# Version:` line. The installer downloads exactly the files of that list, and `install/dkdb-install.ps1` is listed too (the first download is by hand; `dkdb-update` replaces it afterwards).
3. **Bump the image version** (`image` in `manifest.json`) **whenever `scripts/docker/Dockerfile` or `scripts/docker/entrypoint.sh` change** (bump their own `# Version:` too). Only those two files define the image: a change to `dkdb-image-create.ps1` or a new project version does not change it. A change of the image is also critical (next rule).
4. **Bump the project version** (`version` in `manifest.json`) **in every change that touches a listed file**, in the same change as the file version of rule 1: the last number (0.16.0 -> 0.16.1) for an ordinary change, and the middle number (0.16.1 -> 0.17.0) **when the change affects the project critically** (see below). A change that only touches documentation (README, specs, CLAUDE.md, TROUBLESHOOTING) does not bump it.
5. **A version bump must never block the use of an existing container.** `dkdb-container-start` and `dkdb-container-connect` (and every script that uses a container that already exists) may only warn about versions, never stop; the container keeps working with the image it was created from. Creating a container from an image older than the scripts only warns too (it refuses only when no image of that name exists), and a feature that depends on the image (for example the ready marker of the entrypoint) must have a fallback for older images. Only a damaged package (`dkdb-image-create`, `dkdb-container-create`) may refuse to continue. Do not add a version or integrity check that blocks the use of existing containers or images.
6. **Before finishing, run the integrity check and fix everything it reports** (no errors, no notes):

   ```bash
   pwsh -NoProfile -Command ". ./scripts/ps1/dkdb-common.ps1; \$r = Get-DevboxIntegrity -Base (Get-Location).Path; \$r.Errors; \$r.Notes"
   ```

   It compares every listed file with `manifest.json` (existence and version) and reports files under `scripts/` or `install/` that the manifest does not list.

### When a change is critical (bump the project version)

A change is critical when, after it, users must act (reinstall, rebuild the image, recreate containers) or when something they rely on changes. Typical cases:

1. Image changes: `Dockerfile`, `entrypoint.sh`, base Ubuntu version, installed packages.
2. Volume or path changes: folder layout, mount targets such as `~/devbox/projects`, `~/devbox/tools`, `~/devbox/bash`, default host paths, the shared root layout.
3. Installer changes: `dkdb-install.ps1`, `dkdb-uninstall.ps1`, what is installed or where, the PATH handling.
4. Renaming, adding or removing a `dkdb-*` script, or changing what a script does in a way users notice.
5. Default names (image, container, user) or the `dkdb` prefix.
6. Mutagen behavior: session naming, sync mode, flags, minimum version, lifecycle in start, stop, connect or delete.

Not critical (only the last number of the project, plus the file version of rule 1): comments, message wording, colors, refactors without a visible effect. Documentation-only changes do not bump anything.

How to bump the project while it is `0.x`: the last number (0.1.0 -> 0.1.1) in every change to a script or another listed file (fixes, wording, colors, refactors) and the middle number (0.1.0 -> 0.2.0) for a critical change, which also resets the last one. From `1.0.0` on, follow semantic versioning (major for breaking changes). **Images are compatible with the scripts when the image version and the `image` version of the manifest share major.minor (0.x) or major (1.0 and later)**; the project version does not take part, so only a change of the image asks users to rebuild it and recreate containers. If it is unclear whether a change is critical, ask the owner before deciding. After an image bump, say in the final message that the image must be rebuilt (`dkdb-image-create`) and the containers recreated.

## Conventions to keep

1. Documentation, scripts, prompts, messages and comments are in English.
2. `.ps1` files are pure ASCII; every file is UTF-8 without BOM and LF.
3. Every file under `scripts/ps1/` and `scripts/bash/` is named `dkdb-<name>`.
4. Message colors in every script: green only for success (something was done correctly), red for warnings and errors, yellow for the natural next step, default color for anything else (spec 01). Use the helpers (`Write-DevboxSuccess`, `Write-DevboxWarning`, `Write-DevboxNext`; `ok`, `warn`, `next` in bash) instead of raw `-ForegroundColor`. Every other color (titles, labels, badges, host and container paths, states) comes from the table of colors at the top of `dkdb-common.ps1` / `dkdb-common.sh` (spec 01): never write a color name in a script; add a role to the table instead.
5. Every script that ends successfully prints a yellow `Next: ...` line with the natural next step (spec 01); keep the flow up to date when a script is added or changed.
6. What to synchronize with Mutagen is chosen only in the menu of `Invoke-DevboxSyncPick` (`dkdb-container-start`, `dkdb-container-connect`, `dkdb-mutagen-sync`); there are no `-Sync*` parameters and `Keep (no changes)` is the first option and the default, `None (pause all)` the second; the menu never terminates sessions. Do not invent double-dash switches (native PowerShell parameters with `[CmdletBinding(PositionalBinding = $false)]`). Read the output of native programs with `Invoke-DevboxNative`, never with `2>&1` (Windows PowerShell 5.1 differs from 7; test with 5.1 behavior in mind). Document every new script in the README and in spec 03 (a script that is only in the manifest is not documented).
7. Every script supports `-Help` and `-Man` (spec 01): `[switch]$Man` and `[switch]$Help` in a `[CmdletBinding(PositionalBinding = $false)] param(...)` block and, right after loading the common file, an `if ($Help) { Show-DevboxHelp ...; exit 0 }` with the description, usage, parameters, examples and notes, and an `if ($Man) { Show-DevboxMan ...; exit 0 }` with the purpose, requirements, steps, changes, what it never does and the next step. Keep both up to date when parameters or behavior change; each platform uses its own forms: PowerShell `-Help` and `-Man`; the bash scripts have a `usage` function (`-h`, `--help`) and a `manual` function (`man`).
8. `dkdb-info` and `dkdb-version` exist in PowerShell (host) and bash (container): keep the output of both in the same layout, and when the state file written by `Update-DevboxContainerState` changes, update the bash readers (`dkdb-common.sh`, `dkdb-info.sh`, `dkdb-version.sh`).
9. Never commit unless the owner asks for it.
