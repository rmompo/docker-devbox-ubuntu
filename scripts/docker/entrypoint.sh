#!/bin/bash
# Version: 0.1.1
# Container entrypoint (runs as root).
# Creates the user given in DEVBOX_USER (password = user name, sudo with
# password), then hands the main process over to that user.
set -euo pipefail

# Message colors (spec 01): warnings and errors in red (only when stderr is a terminal; in the
# container logs there are no colors).
if [ -t 2 ]; then c_red=$'\033[31m'; c_off=$'\033[0m'; else c_red=''; c_off=''; fi
warn() { printf '%s%s%s\n' "$c_red" "$*" "$c_off" >&2; }
script_version="$(sed -n 's/^# Version: *//p' "$0" | head -n 1)"
echo "$(basename "$0") ${script_version:-unknown} (docker-devbox-ubuntu ${DEVBOX_VERSION:-unknown})"
echo "${DEVBOX_VERSION:-unknown}" > /etc/devbox-version

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

exec gosu "$DEVBOX_USER" "$@"
