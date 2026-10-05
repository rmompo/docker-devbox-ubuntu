#!/bin/bash
# shellcheck disable=SC2034  # the MAN_* arrays are read by show_manual in dkdb-common.sh (through a nameref)
# Version: 0.1.0
# Show how this container is set up, seen from inside it: user, folders, mounts, AI client and the Mutagen sessions.
# Same layout as dkdb-info.ps1 on the host. It only reads. The Mutagen part comes from the state file that the host
# scripts write (~/.devbox-state): it can be out of date, and it says when it was written.
set -u
# shellcheck source=dkdb-common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dkdb-common.sh"

usage() {
    show_help 'Shows how this container is set up: user, image version, folders, mounts, AI client and, with Mutagen, the synchronization sessions as the host last reported them.' \
        'Prints the container, its folders, mounts and Mutagen sessions.' \
        'For the versions see dkdb-version.sh.' \
        'The Mutagen sessions come from ~/.devbox-state, written by the host (dkdb-container-connect, dkdb-mutagen-sync, dkdb-mutagen-status and dkdb-mutagen-stop refresh it).'
}
MAN_PURPOSE='Shows how this container is set up, in the same layout as dkdb-info on the host.'
MAN_NEEDS=('Nothing. The Mutagen part needs the state file ~/.devbox-state, which the host scripts write.')
MAN_STEPS=(
    'Prints the container name, user, image version, operating system, AI client and type of projects volume.'
    'Prints the folders ~/devbox/bash, ~/devbox/tools and ~/devbox/projects with their mount mode, in red when one does not exist.'
    'Lists the mounts under ~/devbox.'
    'With Mutagen, prints the daemon and the sessions (host folder <-> container folder, state, conflicts and last error) as the host last reported them, and says when; it warns in red when no Mutagen agent is connected, because the list may then be out of date.'
)
MAN_CHANGES=('Nothing: it only reads.')
MAN_NEVER=('Synchronizes, pauses or changes any session (that is done from the host).' 'Touches the host or Docker.')
MAN_NEXT='bash ~/devbox/bash/dkdb-version.sh shows every version; dkdb-mutagen-status on the host shows the details of a session.'
handle_arguments "$@"

banner "${BASH_SOURCE[0]}"

# A folder: label, path, note; red when it does not exist.
show_path() {
    local text
    text="$(printf '  %-16s %s' "$1" "$2")"
    [ -z "${3:-}" ] || text="$text  ($3)"
    if [ -e "$2" ]; then echo "$text"; else bad "$text  [does not exist]"; fi
}

home_devbox="$HOME/devbox"
user_name="$(id -un)"
sync_kind="${DEVBOX_SYNC:-}"

# --- Container ---
echo
echo 'Container'
os="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
image_version="${DEVBOX_IMAGE_VERSION:-}"
[ -n "$image_version" ] || image_version="$(cat /etc/devbox-image-version 2>/dev/null)"
printf '  %-16s %s\n' 'Name' "$(hostname)"
printf '  %-16s %s\n' 'User' "$user_name"
printf '  %-16s %s\n' 'Image version' "${image_version:-unknown}"
printf '  %-16s %s\n' 'System' "${os:-unknown}"
if command -v claude >/dev/null 2>&1 || [ -e "$HOME/.local/bin/claude" ]; then
    printf '  %-16s %s\n' 'AI client' 'Claude Code'
elif command -v copilot >/dev/null 2>&1 || [ -e "$HOME/.local/bin/copilot" ]; then
    printf '  %-16s %s\n' 'AI client' 'GitHub Copilot CLI'
else
    printf '  %-16s %s\n' 'AI client' 'none (bash ~/devbox/bash/dkdb-install-claudecode.sh or dkdb-install-ghcopilot-cli.sh)'
fi
if [ "$sync_kind" = mutagen ]; then
    printf '  %-16s %s\n' 'Projects' "Mutagen sync (${DEVBOX_SYNC_PATH:-unknown} <-> ~/devbox/projects)"
else
    printf '  %-16s %s\n' 'Projects' 'bind mount'
fi

# --- Folders and mounts ---
mode_of() {
    local options
    options="$(awk -v dir="$1" '$2 == dir { print $4; exit }' /proc/mounts 2>/dev/null)"
    case "$options" in
        '') echo 'not a mount' ;;
        ro|ro,*) echo 'read-only' ;;
        *) echo 'read/write' ;;
    esac
}
echo
echo 'Folders'
show_path 'Bash volume' "$home_devbox/bash" "$(mode_of "$home_devbox/bash"); the scripts of the package"
show_path 'Tools' "$home_devbox/tools" "$(mode_of "$home_devbox/tools"); shared tools"
if [ "$sync_kind" = mutagen ]; then
    show_path 'Projects' "$home_devbox/projects" 'synchronized by Mutagen'
else
    show_path 'Projects' "$home_devbox/projects" "$(mode_of "$home_devbox/projects")"
fi
mounts="$(awk -v prefix="$home_devbox/" 'index($2, prefix) == 1 { print $2 "|" $3 "|" $4 }' /proc/mounts 2>/dev/null)"
if [ -n "$mounts" ]; then
    echo
    echo 'Mounts'
    while IFS='|' read -r where kind options; do
        mode='read/write'
        case "$options" in ro|ro,*) mode='read-only' ;; esac
        printf '  %s (%s, %s)\n' "$where" "$kind" "$mode"
    done <<< "$mounts"
fi

# --- Mutagen (from the state file written by the host) ---
echo
echo 'Mutagen'
if [ "$sync_kind" != mutagen ]; then
    echo '  not used by this container (the projects folder is a Docker bind mount)'
elif [ ! -r "$DEVBOX_STATE_FILE" ]; then
    bad '  no state yet: run dkdb-container-connect or dkdb-mutagen-sync on the host to write it'
else
    daemon="$(state_get daemon)"
    updated="$(state_get updated)"
    echo "  As the host reported at $updated"
    case "$daemon" in
        running) ok '  Daemon           running' ;;
        stopped) echo '  Daemon           stopped (dkdb-mutagen-start, dkdb-mutagen-sync, or starting or connecting the container, start it)' ;;
        *) echo "  Daemon           ${daemon:-unknown}" ;;
    esac
    name="$(hostname)"
    count=0
    while IFS='|' read -r alpha beta state conflicts last_error; do
        [ -n "$alpha" ] || continue
        count=$((count + 1))
        text="  $name: $alpha <-> $beta [$state]"
        if [ -n "$last_error" ] || [ "${conflicts:-0}" -gt 0 ] 2>/dev/null; then
            bad "$text [conflicts: ${conflicts:-0}; last error: $last_error]"
        else
            echo "$text"
        fi
    done < <(state_each session)
    if [ "$count" -eq 0 ] && [ "$daemon" = running ]; then echo "  $name: no session yet (dkdb-mutagen-sync on the host creates it)"; fi
    if [ "$count" -gt 0 ]; then
        if pgrep -f mutagen-agent >/dev/null 2>&1; then
            echo '  Agent            a Mutagen agent is connected'
        else
            bad '  Agent            no Mutagen agent is connected: the list may be out of date (dkdb-mutagen-status on the host shows the real state)'
        fi
    fi
fi

echo
next 'Next: bash ~/devbox/bash/dkdb-version.sh shows every version; dkdb-mutagen-status on the host shows the details of a session.'
