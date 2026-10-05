# 06 - Verifications and open items

## Verified (2026-09-25, historical: Ubuntu 22.04 / 24.04)

| Item | Result | Source |
|---|---|---|
| `ubuntu` user in the image | 22.04 does not ship it (a new user gets UID 1000); 24.04 does (`ubuntu`, UID 1000). No direct proof: Docker could not be run from WSL in this session. | Issues in poky-container and devcontainers/images |
| Copilot CLI without Node | Confirmed: `curl -fsSL https://gh.io/copilot-install \| bash`; installs into `$HOME/.local` (non-root), supports `PREFIX` and `VERSION`. | https://github.com/github/copilot-cli |
| Claude Code installer | Confirmed: `curl -fsSL https://claude.ai/install.sh \| bash`; launcher at `~/.local/bin/claude`; requires Ubuntu 20.04+ and 4 GB RAM; self-updates. | https://code.claude.com/docs/en/setup |
| `pipx` on 22.04 | Version 1.0.0, `universe` repository. | https://packages.ubuntu.com/jammy/pipx |

## Verified for Ubuntu 26.04 LTS (resolute)

| Item | Result | Source |
|---|---|---|
| Image | `ubuntu:26.04` exists on Docker Hub (updated 2026-09-18, about 41.6 MB, multi-arch). | https://hub.docker.com/v2/repositories/library/ubuntu/tags/26.04 |
| Versions | Python 3.14.3 (3.14.4 observed on 2026-10-05), git 2.53.0 (>= 2.46, so `safe.directory /path/*` works without a PPA). | https://packages.ubuntu.com/resolute/git , https://packages.ubuntu.com/resolute/python3 |
| Packages | `pipx` 1.8.0 (universe), `gosu` 1.19-1 (universe), `ripgrep` 15.1.0 (universe), `python-is-python3`, `iputils-ping` exist. `dnsutils` is only virtual -> use `bind9-dnsutils`. | packages.ubuntu.com/resolute |
| sudo | The `sudo` package is the classic sudo.ws 1.9.17; `sudo-rs` is only recommended, so it is not installed with `--no-install-recommends`. | https://packages.ubuntu.com/resolute/sudo |
| Changes | `rust-coreutils` default (`cp`, `mv`, `rm` still GNU), APT 3 (`apt-key` removed), glibc 2.43, GCC 15. | https://documentation.ubuntu.com/release-notes/26.04/summary-for-lts-users/ |

## Re-verified (2026-10-05)

| Item | Result | Source |
|---|---|---|
| Base image | `ubuntu:26.04` exists on Docker Hub (updated 2026-10-04, amd64, arm64, arm, ppc64le, riscv64, s390x). | https://hub.docker.com/v2/repositories/library/ubuntu/tags/26.04 |
| Release in a running devbox container | `Ubuntu 26.04.1 LTS (Resolute Raccoon)`, codename `resolute`, git 2.53.0, Python 3.14.4. | `/etc/os-release`, `git --version`, `python3 --version` inside the container |
| Dockerfile packages | Every package listed in the `Dockerfile` is installed in that container. | `dpkg -s` inside the container |
| Static checks | `pwsh` parse, PSScriptAnalyzer, `shellcheck` and `hadolint` pass; the remaining findings are intentional (Write-Host in interactive scripts, SC2016 for the literal `$HOME` written to `.bashrc`, DL3008 unpinned apt versions). | pwsh 7.6.6, PSScriptAnalyzer 1.25.0, shellcheck 0.11.0, hadolint 2.15.1 |

Reported by the project owner (not reproduced here): git "dubious ownership" on the 9p projects mount, because it shows files as owned by root while git runs as UID 1000. Git 2.46 added the `safe.directory = /path/*` pattern (https://git-scm.com/docs/git/2.46.0). Whether the pattern also matches repositories nested deeper than one level, or a repository at the mount root itself, is not verified.

Not verified yet (needs Windows and Docker Desktop): `install.ps1` end to end (download, PATH, execution policy), the read-only `bash` mount, the `tools` mount, the shared-root layout (`Get-DevboxRoot`, the installer creating `<root>\tools`, stale PATH entry removal), the image rebuilt with the `projects` rename, the entrypoint under rust-coreutils, whether the base image ships extra users, the installers of Claude Code and Copilot CLI on 26.04, `safe.directory` on the 9p mount, the version flow (`manifest.json` as the file list of the installer, the per-file integrity check and `dkdb-verify`, the version-tagged images and the highest compatible tag in `dkdb-container-create`, the blocking of `start` and `connect`, the build arg, the label and the entrypoint log), and Mutagen end to end: on-demand installation, the minimum version check (`mutagen version` output), `mutagen sync list --template` (used to list session names), the orphan clean-up, `uninstall.ps1`, the branch or tag prompt of `install.ps1`, session creation, `/dev/shm` being recreated at every container start, session behavior after rebooting the PC or stopping Docker Desktop, handling of case-only name differences, and the permission and ownership flags.

## To check during implementation (22.04 items are historical)
1. Confirm with Docker that `ubuntu:22.04` does not ship the `ubuntu` user.
2. Confirm the `universe` repository is enabled in the image for `pipx` (otherwise `pip install --user pipx`).
3. ~~Review the current `.gitattributes`~~ Done: it only contained `* text=auto`; replaced by `* text=auto eol=lf`.
4. Network exposure of the container: accepted. It is a local development container (password equal to the user name, weak by design) and it needs internet access; no network hardening is planned.

## Out of scope
Connecting VS Code (done manually via terminal and volumes) and `remoteUser` configuration.
