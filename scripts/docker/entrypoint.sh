#!/bin/bash
# Container entrypoint (runs as root).
# Creates the user given in DEVBOX_USER (password = user name, sudo with
# password), then hands the main process over to that user.
set -euo pipefail

if [ -z "${DEVBOX_USER:-}" ]; then
    echo "entrypoint: DEVBOX_USER is not set" >&2
    exit 1
fi

if ! id "$DEVBOX_USER" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --groups sudo "$DEVBOX_USER"
    echo "${DEVBOX_USER}:${DEVBOX_USER}" | chpasswd
fi

user_home="/home/${DEVBOX_USER}"

# Docker creates the mount target folders (and so the home) before this
# script runs, and useradd then skips copying /etc/skel. Copy any missing
# skel file (no overwrite) so .bashrc and its colors are always present.
cp -rn /etc/skel/. "$user_home/" || true
chown "${DEVBOX_USER}:${DEVBOX_USER}" "$user_home"
# Bash globbing instead of parsing "ls": it does not depend on the ls
# implementation (Ubuntu 26.04 ships rust-coreutils).
shopt -s dotglob nullglob
for skel_entry in /etc/skel/*; do
    chown -R "${DEVBOX_USER}:${DEVBOX_USER}" "${user_home}/${skel_entry##*/}"
done
shopt -u dotglob nullglob

# Own the parent folder of the mounts (non-recursive: mounts are untouched).
mkdir -p "${user_home}/devbox"
chown "${DEVBOX_USER}:${DEVBOX_USER}" "${user_home}/devbox"

# The projects mount (9p on Docker Desktop) shows every file as owned by root,
# so git reports "dubious ownership" for the user. Trust only the repositories
# under the projects mount instead of using '*'. The "/path/*" pattern needs
# git 2.46 or newer (Ubuntu 26.04 ships 2.53). Added once (idempotent).
safe_dir="${user_home}/devbox/proyectos/*"
if ! git config --system --get-all safe.directory 2>/dev/null | grep -qxF "$safe_dir"; then
    git config --system --add safe.directory "$safe_dir"
fi

exec gosu "$DEVBOX_USER" "$@"
