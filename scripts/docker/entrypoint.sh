#!/bin/bash
# Version: 0.1.2
# Container entrypoint (runs as root).
# Creates the user given in DEVBOX_USER (password = user name, sudo with
# password), then hands the main process over to that user.
set -euo pipefail

# Message colors (spec 01): success in green, warnings and errors in red, the natural next step in
# yellow. The output goes to the container logs (docker logs, read in a terminal), so the colors
# are always on; NO_COLOR disables them.
if [ -z "${NO_COLOR:-}" ]; then
    c_green=$'\033[32m'; c_red=$'\033[31m'; c_yellow=$'\033[33m'; c_off=$'\033[0m'
else
    c_green=''; c_red=''; c_yellow=''; c_off=''
fi
ok() { printf '%s%s%s\n' "$c_green" "$*" "$c_off"; }
warn() { printf '%s%s%s\n' "$c_red" "$*" "$c_off" >&2; }
next() { printf '%s%s%s\n' "$c_yellow" "$*" "$c_off"; }

script_version="$(sed -n 's/^# Version: *//p' "$0" | head -n 1)"
echo "$(basename "$0") ${script_version:-unknown} (docker-devbox-ubuntu image ${DEVBOX_IMAGE_VERSION:-unknown})"
echo "${DEVBOX_IMAGE_VERSION:-unknown}" > /etc/devbox-image-version

if [ -z "${DEVBOX_USER:-}" ]; then
    warn "entrypoint: DEVBOX_USER is not set"
    exit 1
fi

if ! id "$DEVBOX_USER" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --groups sudo "$DEVBOX_USER"
    echo "${DEVBOX_USER}:${DEVBOX_USER}" | chpasswd
    ok "User '${DEVBOX_USER}' created."
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

# With Mutagen (DEVBOX_SYNC=mutagen) there is no projects bind mount: the folder
# lives in the container and Mutagen synchronizes it with the host.
if [ "${DEVBOX_SYNC:-}" = "mutagen" ]; then
    mkdir -p "${user_home}/devbox/projects"
    chown "${DEVBOX_USER}:${DEVBOX_USER}" "${user_home}/devbox/projects"
fi

# The projects mount (9p on Docker Desktop) shows every file as owned by root,
# so git reports "dubious ownership" for the user. Trust only the repositories
# under the projects mount instead of using '*'. The "/path/*" pattern needs
# git 2.46 or newer (Ubuntu 26.04 ships 2.53). Added once (idempotent).
safe_dir="${user_home}/devbox/projects/*"
if ! git config --system --get-all safe.directory 2>/dev/null | grep -qxF "$safe_dir"; then
    git config --system --add safe.directory "$safe_dir"
fi

# Ready marker for the host scripts (/dev/shm is a tmpfs recreated at every start).
touch /dev/shm/devbox-ready
ok "Container ready (user ${DEVBOX_USER})."
next "Next: dkdb-container-connect opens a shell in this container."

exec gosu "$DEVBOX_USER" "$@"
