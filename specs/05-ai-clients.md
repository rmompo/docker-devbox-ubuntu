# 05 - AI client installation

## Context
One AI client (Claude Code or GitHub Copilot CLI) is installed inside the container. Installation uses bash scripts from the read-only `bash` volume.

## Reasoning
1. The image is generic -> the client is installed afterwards, per container.
2. Owner's rule: **one client per container**; for another client, create another container.
3. The scripts live on the host (volume) -> they can be edited without rebuilding the image.
4. Files are created on Windows -> they must be LF and UTF-8; Windows does not keep the execute bit -> run them with `bash script.sh`.
5. Node is excluded from the image -> Copilot CLI is installed with its standalone installer, which does not need it.
6. Both clients install into `~/.local/bin` -> make sure it is on the PATH.

## Decision
- **Source of truth:** `scripts/bash/` in the repository (versioned in git).
- **Installed copy:** `<install path>\scripts\bash\`, downloaded by `install.ps1` (spec 07) and mounted read-only inside the container at `/home/<user>/devbox/bash/`. To update, re-run `install.ps1`.
- **Claude Code:** `curl -fsSL https://claude.ai/install.sh | bash` (latest version; leaves `~/.local/bin/claude`).
- **Copilot CLI:** `curl -fsSL https://gh.io/copilot-install | bash` (no Node needed; installs into `$HOME/.local` for non-root users).
- **PATH:** each script appends `~/.local/bin` to `.bashrc` idempotently.
- **Exclusivity check:** before installing, the script looks for the other client (`claude` or `copilot`, on the PATH or in `~/.local/bin`). If found, it installs nothing, prints that another container must be used, and exits with an error code. If the client is the same one, it continues (reinstall or update).
- **Language:** script comments and messages are in English.

## Consequences
- Depends on two third-party installers; if they change, the scripts need review.
- The one-client rule is enforced by the script, not by Docker.
