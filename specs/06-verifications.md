# 06 - Verifications and open items

## Verified (2026-09-25)

| Item | Result | Source |
|---|---|---|
| `ubuntu` user in the image | 22.04 does not ship it (a new user gets UID 1000); 24.04 does (`ubuntu`, UID 1000). No direct proof: Docker could not be run from WSL in this session. | Issues in poky-container and devcontainers/images |
| Copilot CLI without Node | Confirmed: `curl -fsSL https://gh.io/copilot-install \| bash`; installs into `$HOME/.local` (non-root), supports `PREFIX` and `VERSION`. | https://github.com/github/copilot-cli |
| Claude Code installer | Confirmed: `curl -fsSL https://claude.ai/install.sh \| bash`; launcher at `~/.local/bin/claude`; requires Ubuntu 20.04+ and 4 GB RAM; self-updates. | https://code.claude.com/docs/en/setup |
| `pipx` on 22.04 | Version 1.0.0, `universe` repository. | https://packages.ubuntu.com/jammy/pipx |

## Verified for Ubuntu 26.04 LTS (resolute), branch `feature/ubuntu26`

| Item | Result | Source |
|---|---|---|
| Image | `ubuntu:26.04` exists on Docker Hub (updated 2026-09-18, about 41.6 MB, multi-arch). | https://hub.docker.com/v2/repositories/library/ubuntu/tags/26.04 |
| Versions | Python 3.14.3, git 2.53.0 (>= 2.46, so `safe.directory /path/*` works without a PPA). | https://packages.ubuntu.com/resolute/git , https://packages.ubuntu.com/resolute/python3 |
| Packages | `pipx` 1.8.0 (universe), `gosu` 1.19-1 (universe), `ripgrep` 15.1.0 (universe), `python-is-python3`, `iputils-ping` exist. `dnsutils` is only virtual -> use `bind9-dnsutils`. | packages.ubuntu.com/resolute |
| sudo | The `sudo` package is the classic sudo.ws 1.9.17; `sudo-rs` is only recommended, so it is not installed with `--no-install-recommends`. | https://packages.ubuntu.com/resolute/sudo |
| Changes | `rust-coreutils` default (`cp`, `mv`, `rm` still GNU), APT 3 (`apt-key` removed), glibc 2.43, GCC 15. | https://documentation.ubuntu.com/release-notes/26.04/summary-for-lts-users/ |

Reported by the project owner (not reproduced here): git "dubious ownership" on the 9p projects mount, because it shows files as owned by root while git runs as UID 1000 (see `solve.md`). Git 2.46 added the `safe.directory = /path/*` pattern (https://git-scm.com/docs/git/2.46.0). Whether the pattern also matches repositories nested deeper than one level, or a repository at the mount root itself, is not verified.

Not verified yet (needs Windows, Docker and a public repository): `install.ps1` end to end (download, PATH, execution policy), the read-only `bash` mount, and: image build, entrypoint under rust-coreutils, whether the base image ships extra users, installers of Claude Code and Copilot CLI on 26.04, and `safe.directory` on the 9p mount.

## To check during implementation (22.04 items are historical)
1. Confirm with Docker that `ubuntu:22.04` does not ship the `ubuntu` user.
2. Confirm the `universe` repository is enabled in the image for `pipx` (otherwise `pip install --user pipx`).
3. ~~Review the current `.gitattributes`~~ Done: it only contained `* text=auto`; replaced by `* text=auto eol=lf`.
4. Handle network exposure of the container (password is weak by design).

## Out of scope
Connecting VS Code (done manually via terminal and volumes) and `remoteUser` configuration.
