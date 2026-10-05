# 02 - Docker image

## Context
The image must be lightweight and generic: it serves any container and any AI client, so it ships with no user and no client installed.

## Reasoning
1. Longest support and a recent git -> Ubuntu 26.04 LTS (branch `feature/ubuntu26`). Ubuntu 22.04 (git 2.34.1, standard support ends April 2027) was the previous choice and remains selectable through the `ARG`. 26.04 ships git 2.53, so `safe.directory` can use a `/path/*` pattern (supported since git 2.46) without a PPA.
2. Allow a later migration -> version kept in an `ARG UBUNTU_VERSION`.
3. The user depends on the container (name, mounts) -> it is not created in the image; an entrypoint creates it at start.
4. Size -> `--no-install-recommends` and clean the apt cache.
5. This is a development machine and Python 3 is required -> include Python and `build-essential`.
6. Only generic development tools or tools useful for AI -> Node and other languages are left out.
7. Python 3.14 on 26.04 blocks global `pip` (PEP 668) -> include `python3-venv` and `pipx`; use virtual environments or pipx.
8. 26.04 uses `rust-coreutils` (`cp`, `mv`, `rm` stay GNU) -> the entrypoint avoids parsing `ls` and uses bash globbing.
9. In 26.04 the `sudo` package is still the classic sudo (`sudo-rs` is only a recommended package); with `--no-install-recommends` it is not installed, so sudo behaves as before.
10. `dnsutils` is only a virtual package in 26.04 -> install the real one, `bind9-dnsutils`.

## Decision
- **Location:** the Docker files (`Dockerfile`, entrypoint script) live in `scripts/docker/`.
- **Base:** `ubuntu:26.04` (configurable via `ARG UBUNTU_VERSION`).
- **Base packages:** `ca-certificates`, `curl`, `wget`, `nano`, `git`, `sudo`, `gosu`, `zip`, `unzip`, `less`.
- **Recommended:** `jq`, `openssh-client`, `procps`, `bash-completion`, `gnupg`, `xz-utils`, `ripgrep`, `rsync`, `htop`, `iproute2`, `bind9-dnsutils`, `make`.
- **Python:** `python3`, `python3-pip`, `python3-venv`, `pipx`, `python-is-python3`.
- **Build tools:** `build-essential`.
- **Optional:** `tree`, `iputils-ping`.
- **Excluded:** Node and any language other than Python.
- **Environment:** `LANG=C.UTF-8`.
- **Bash colors:** adjust `/etc/skel/.bashrc` (`force_color_prompt=yes`, colored `ls` and `grep` aliases). Every new user is born with them.
- **Entrypoint (root):** if the user does not exist, create it with `useradd -m`, set its password equal to its name, add it to the `sudo` group (no `NOPASSWD`), give the user ownership of `/home/<user>/devbox` (non-recursive, so mounts are untouched) and hand the main process to that user with `gosu`. It is idempotent across restarts. Because Docker creates the home folder (mount targets) before the entrypoint runs, `useradd` skips `/etc/skel`; the entrypoint therefore copies any missing skel file (no overwrite) and chowns it, so `.bashrc` and its colors always exist.
- **Git safe directory:** the entrypoint runs `git config --system --add safe.directory "/home/<user>/devbox/proyectos/*"` (once, idempotent). The projects mount is 9p and shows files as owned by root, which makes git fail with "dubious ownership" (and hides the branch in the Claude Code status line). The `/path/*` pattern needs git 2.46+; it is set at container start because the user, and so the path, is not known at build time. `'*'` is not used, so the ownership check stays active outside the projects mount.
- **User:** passed via an environment variable; the password is derived from the name, so no secret travels.

## Consequences
- Docker records the container's default user as root: `docker exec` must pass `-u <user>` (done by `container-connect`).
- The image is somewhat larger because of `build-essential` (about 200 MB).
