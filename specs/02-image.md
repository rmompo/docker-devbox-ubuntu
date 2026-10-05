# 02 - Docker image

## Context
The image must be lightweight and generic: it serves any container and any AI client, so it ships with no user and no client installed.

## Reasoning
1. Longest support and a recent git -> Ubuntu 26.04 LTS. It ships git 2.53, so `safe.directory` can use a `/path/*` pattern (supported since git 2.46) without a PPA; Ubuntu 22.04 (git 2.34.1) would not support that pattern.
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
- **Entrypoint (root):** if the user does not exist, create it with `useradd -m`, set its password equal to its name, add it to the `sudo` group (no `NOPASSWD`), give the user ownership of `/home/<user>/devbox` (non-recursive, so mounts are untouched) and hand the main process to that user with `gosu`. It is idempotent across restarts. Because Docker creates the home folder (mount targets) before the entrypoint runs, `useradd` skips `/etc/skel`; the entrypoint therefore copies any missing skel file (no overwrite) and chowns it, so `.bashrc` and its colors always exist. With `DEVBOX_SYNC=mutagen` it also creates (and chowns) `/home/<user>/devbox/projects`, and just before handing over it touches `/dev/shm/devbox-ready` (a tmpfs recreated at every start), which the host scripts wait for (spec 08).
- **The bash scripts by name:** the entrypoint appends a block to the user's `~/.bashrc` (once, idempotent, marked by a comment): `~/devbox/bash` goes on the PATH and every `dkdb-*.sh` (except `dkdb-common.sh`) also gets a shell function that runs it with `bash`, because a Windows mount may not keep the execute bit. So `dkdb-info.sh`, `dkdb-version.sh` and the AI client installers run by name in interactive shells. The messages keep the form `bash ~/devbox/bash/<script>`, which works in containers created from an older image too.
- **Git safe directory:** the entrypoint runs `git config --system --add safe.directory "/home/<user>/devbox/projects/*"` (once, idempotent). The projects mount is 9p and shows files as owned by root, which makes git fail with "dubious ownership" (and hides the branch in the Claude Code status line). The `/path/*` pattern needs git 2.46+; it is set at container start because the user, and so the path, is not known at build time. `'*'` is not used, so the ownership check stays active outside the projects mount. It is needed for the bind mount; with Mutagen the files belong to the container user and it is harmless.
- **Version and tag:** the image has its own version, the `image` field of `manifest.json`, bumped only when the `Dockerfile` or the `entrypoint.sh` change (rule in `CLAUDE.md`). `dkdb-image-create` builds `dkdb-<name>:<image version>`, never `latest`, and passes `--build-arg DEVBOX_IMAGE_VERSION=<image version>`. The `Dockerfile` keeps it as `ENV DEVBOX_IMAGE_VERSION` and as the label `org.opencontainers.image.version`, after the heavy layers so that a new version does not invalidate the apt cache. The entrypoint prints it in the container logs and writes it to `/etc/devbox-image-version`. Its messages follow the color convention of spec 01 (green: `User '<user>' created.` and `Container ready`; yellow: the `Next:` hint; red: errors such as a missing `DEVBOX_USER`), always on because they go to `docker logs`; `NO_COLOR` disables them. An image is compatible with the scripts when its version and the `image` version of the manifest share major.minor (0.x) or major (1.0 and later); a new project version does not change that.
- **User:** passed via an environment variable; the password is derived from the name, so no secret travels.

## Consequences
- Docker records the container's default user as root: `docker exec` must pass `-u <user>` (done by `dkdb-container-connect`).
- The image is somewhat larger because of `build-essential` (about 200 MB).
