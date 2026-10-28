#!/bin/bash
# shellcheck disable=SC2034  # the MAN_* arrays are read by show_manual in dkdb-common.sh (through a nameref)
# Version: 0.3.0
# Show how this container is set up, seen from inside it: user, folders, mounts, AI client, published ports and the
# Mutagen sessions.
# Same layout as dkdb-info.ps1 on the host. It only reads. The ports and the Mutagen part come from the state file
# that the host scripts write (~/.devbox-state): it can be out of date, and it says when it was written.
set -u
# shellcheck source=dkdb-common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dkdb-common.sh"

usage() {
    show_help 'Shows how this container is set up: user, image version, folders, mounts, AI client, published ports and, with Mutagen, the synchronization sessions as the host last reported them.' \
        'Prints the container, its folders, mounts, published ports and Mutagen sessions.' \
        'For the versions see dkdb-version.sh.' \
        'Layout (same as dkdb-info on the host): SECTIONS in capitals, PROPERTIES in capitals followed by dots up to the values, values wrapped to the width of the terminal. Host paths are cyan and container paths magenta. Special words are shown in reverse video: MUTAGEN (red), MUTAGEN-SYNC (yellow), VOLUME-P9 (red), READ-ONLY (green) and READ-WRITE (red).' \
        'The published ports and the Mutagen sessions come from ~/.devbox-state, written by the host (dkdb-container-connect, dkdb-mutagen-sync, dkdb-mutagen-status and dkdb-mutagen-stop refresh it).'
}
MAN_PURPOSE='Shows how this container is set up, in the same layout as dkdb-info on the host.'
MAN_NEEDS=('Nothing. The ports and the Mutagen part need the state file ~/.devbox-state, which the host scripts write.')
MAN_STEPS=(
    'Prints the container name, user, image version, operating system, AI client and type of projects volume.'
    'Prints the folders ~/devbox/bash, ~/devbox/tools and ~/devbox/projects with their mount mode, in red when one does not exist.'
    'Lists the mounts under ~/devbox.'
    'Prints the published ports (host ip:port -> container port) as the host last reported them: they are fixed when the container is created, and the container cannot see them by itself.'
    'With Mutagen, prints the daemon and the sessions (host folder <-> container folder, state, conflicts and last error) as the host last reported them, and says when; it warns in red when no Mutagen agent is connected, because the list may then be out of date.'
)
MAN_CHANGES=('Nothing: it only reads.')
MAN_NEVER=('Synchronizes, pauses or changes any session (that is done from the host).' 'Touches the host or Docker.')
MAN_NEXT='bash ~/devbox/bash/dkdb-version.sh shows every version; dkdb-mutagen-status on the host shows the details of a session.'
handle_arguments "$@"

banner "${BASH_SOURCE[0]}"

home_devbox="$HOME/devbox"
user_name="$(id -un)"
sync_kind="${DEVBOX_SYNC:-}"

# A folder of the container with its mode (badge) and a note; red note when it does not exist.
show_path() {
    local label="$1" path="$2" mode="$3" note="${4:-}" pieces
    pieces=("t:container:$path")
    case "$mode" in
        read-only) pieces+=('b:green:READ-ONLY') ;;
        read/write) pieces+=('b:red:READ-WRITE') ;;
        '') ;;
        *) pieces+=("t:none: ($mode)") ;;
    esac
    [ -z "$note" ] || pieces+=("t:none: $note")
    [ -e "$path" ] || pieces+=('t:red: [does not exist]')
    info_field "$label" 11 2 "${pieces[@]}"
}

# --- Container ---
info_section 'Container'
os="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
image_version="${DEVBOX_IMAGE_VERSION:-}"
[ -n "$image_version" ] || image_version="$(cat /etc/devbox-image-version 2>/dev/null)"
info_field 'Name' 13 2 "t:none:$(hostname)"
info_field 'User' 13 2 "t:none:$user_name"
info_field 'Image version' 13 2 "t:none:${image_version:-unknown}"
info_field 'System' 13 2 "t:none:${os:-unknown}"
if command -v claude >/dev/null 2>&1 || [ -e "$HOME/.local/bin/claude" ]; then
    info_field 'AI client' 13 2 't:none:Claude Code'
elif command -v copilot >/dev/null 2>&1 || [ -e "$HOME/.local/bin/copilot" ]; then
    info_field 'AI client' 13 2 't:none:GitHub Copilot CLI'
else
    info_field 'AI client' 13 2 't:none:none (bash ~/devbox/bash/dkdb-install-claudecode.sh or dkdb-install-ghcopilot-cli.sh)'
fi
if [ "$sync_kind" = mutagen ]; then
    info_field 'Volume' 13 2 'b:yellow:MUTAGEN-SYNC'
    info_field 'Projects' 13 2 "t:host:${DEVBOX_SYNC_PATH:-unknown}" 't:none: <-> ' 't:container:~/devbox/projects' 'b:red:MUTAGEN'
else
    info_field 'Volume' 13 2 'b:red:VOLUME-P9'
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
info_section 'Folders'
show_path 'Bash volume' "$home_devbox/bash" "$(mode_of "$home_devbox/bash")" 'the scripts of the package'
show_path 'Tools' "$home_devbox/tools" "$(mode_of "$home_devbox/tools")" 'shared tools'
if [ "$sync_kind" = mutagen ]; then
    show_path 'Projects' "$home_devbox/projects" '' 'synchronized by Mutagen'
else
    show_path 'Projects' "$home_devbox/projects" "$(mode_of "$home_devbox/projects")"
fi
mounts="$(awk -v prefix="$home_devbox/" 'index($2, prefix) == 1 { print $2 "|" $3 "|" $4 }' /proc/mounts 2>/dev/null)"
if [ -n "$mounts" ]; then
    info_section 'Mounts'
    while IFS='|' read -r where kind options; do
        case "$options" in
            ro|ro,*) info_field 'Mount' 5 2 "t:container:$where" "t:none: ($kind)" 'b:green:READ-ONLY' ;;
            *) info_field 'Mount' 5 2 "t:container:$where" "t:none: ($kind)" 'b:red:READ-WRITE' ;;
        esac
    done <<< "$mounts"
fi

# --- Published ports (from the state file written by the host; spec 09) ---
# A container cannot see its own published ports: the host reports them as ports=<count> and port|ip|host|container/proto.
info_section 'Ports'
if [ ! -r "$DEVBOX_STATE_FILE" ]; then
    info_field 'Ports' 5 2 't:red:no state yet: run dkdb-container-connect on the host to write it'
else
    ports_count="$(state_get ports)"
    if [ -z "$ports_count" ]; then
        info_field 'Ports' 5 2 't:none:not reported yet (the host scripts that wrote the state file are older than the ports; dkdb-container-connect refreshes it)'
    elif [ "$ports_count" = 0 ]; then
        info_field 'Ports' 5 2 't:none:none published (Docker cannot add ports to an existing container; create a new one)'
    else
        while IFS='|' read -r bind_ip host_port target; do
            [ -n "$host_port" ] || continue
            info_field 'Port' 5 2 "t:host:$bind_ip:$host_port" 't:none: -> ' "t:container:$target"
        done < <(state_each port)
    fi
fi

# --- Mutagen (from the state file written by the host) ---
info_section 'Mutagen'
if [ "$sync_kind" != mutagen ]; then
    echo '  not used by this container (the projects folder is a Docker bind mount)'
elif [ ! -r "$DEVBOX_STATE_FILE" ]; then
    info_field 'State' 10 2 't:red:no state yet: run dkdb-container-connect or dkdb-mutagen-sync on the host to write it'
else
    daemon="$(state_get daemon)"
    updated="$(state_get updated)"
    info_field 'Reported' 10 2 "t:none:as the host reported at $updated"
    case "$daemon" in
        running) info_field 'Daemon' 10 2 't:green:running' ;;
        stopped) info_field 'Daemon' 10 2 't:red:stopped (dkdb-mutagen-start, dkdb-mutagen-sync, or starting or connecting the container, start it)' ;;
        *) info_field 'Daemon' 10 2 "t:none:${daemon:-unknown}" ;;
    esac
    name="$(hostname)"
    count=0
    echo "  $name"
    while IFS='|' read -r alpha beta state conflicts last_error; do
        [ -n "$alpha" ] || continue
        count=$((count + 1))
        pieces=("t:host:$alpha" 't:none: <-> ' "t:container:$beta" "t:none: [$state]")
        if [ -n "$last_error" ] || [ "${conflicts:-0}" -gt 0 ] 2>/dev/null; then
            pieces+=("t:red: [conflicts: ${conflicts:-0}; last error: $last_error]")
        fi
        info_field 'Session' 10 4 "${pieces[@]}"
    done < <(state_each session)
    if [ "$count" -eq 0 ] && [ "$daemon" = running ]; then info_field 'Session' 10 4 't:none:none yet (dkdb-mutagen-sync on the host creates it)'; fi
    if [ "$count" -gt 0 ]; then
        if pgrep -f mutagen-agent >/dev/null 2>&1; then
            info_field 'Agent' 10 2 't:none:a Mutagen agent is connected'
        else
            info_field 'Agent' 10 2 't:red:no Mutagen agent is connected: the list may be out of date (dkdb-mutagen-status on the host shows the real state)'
        fi
    fi
fi

echo
next 'Next: bash ~/devbox/bash/dkdb-version.sh shows every version; dkdb-mutagen-status on the host shows the details of a session.'
