#!/bin/bash
# shellcheck disable=SC2034  # the MAN_* arrays are read by show_manual in dkdb-common.sh (through a nameref)
# Version: 0.1.0
# Install the tools that the devbox scripts need and that an image may not have (for example an image older
# than the scripts). Run it inside the container: bash ~/devbox/bash/dkdb-install-tools.sh
set -u
# shellcheck source=dkdb-common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dkdb-common.sh"

# The groups of tools: name, description and the 'command:package' pairs.
GROUPS_ORDER=(base keyring)
declare -A GROUP_TEXT=(
    [base]='Basic tools of the installers and the scripts: curl, git and jq.'
    [keyring]='GNOME keyring for programs that keep credentials in the Secret Service (D-Bus): dbus-daemon, gnome-keyring-daemon, secret-tool and script.'
)
declare -A GROUP_TOOLS=(
    [base]='curl:curl git:git jq:jq'
    [keyring]='dbus-daemon:dbus gnome-keyring-daemon:gnome-keyring secret-tool:libsecret-tools script:bsdutils'
)

warn() { printf '%s%s%s\n' "$c_red" "$*" "$c_off" >&2; }

usage() {
    local name cyan green off
    name="$(basename "$0")"
    cyan="$c_cyan"; green="$c_green"; off="$c_off"
    banner "$0"
    printf '\n%sNAME%s\n    %s%s%s\n' "$cyan" "$off" "$green" "$name" "$off"
    printf '\n%sDESCRIPTION%s\n' "$cyan" "$off"
    wrap_text 92 'Checks the tools that the devbox scripts need and installs the missing ones with apt (as root, or with sudo). It is for images that do not have them all, for example one older than the scripts. Without arguments it handles every group.' | sed 's/^/    /'
    printf '\n%sUSAGE%s\n    %sbash ~/devbox/bash/%s [check] [base] [keyring] [-h | man]%s\n' "$cyan" "$off" "$green" "$name" "$off"
    printf '\n%sPARAMETERS%s\n' "$cyan" "$off"
    printf '    %s%-10s%s Only report what is missing; install nothing (exit code 1 if something is missing).\n' "$green" "check" "$off"
    local group
    for group in "${GROUPS_ORDER[@]}"; do
        printf '    %s%-10s%s %s\n' "$green" "$group" "$off" "${GROUP_TEXT[$group]}"
    done
    printf '    %s%-10s%s Show this help and exit.\n' "$green" "-h, --help" "$off"
    printf '    %s%-10s%s Show the manual (what the script does, step by step) and exit.\n' "$green" "man" "$off"
    printf '\n%sEXAMPLES%s\n' "$cyan" "$off"
    printf '    %sbash ~/devbox/bash/%s%s\n        Installs whatever is missing, in every group.\n' "$green" "$name" "$off"
    printf '    %sbash ~/devbox/bash/%s check%s\n        Lists what is missing and installs nothing.\n' "$green" "$name" "$off"
    printf '    %sbash ~/devbox/bash/%s keyring%s\n        Installs only the keyring tools.\n' "$green" "$name" "$off"
    printf '\n%sNOTES%s\n' "$cyan" "$off"
    wrap_text 90 'Installing needs root or sudo; sudo asks for the password of the container user (the same as its name).' | sed '1s/^/    - /;2,$s/^/      /'
    wrap_text 90 'The keyring group installs about 90 packages (it pulls the D-Bus session and the GNOME crypto libraries); that is why it is not part of the image.' | sed '1s/^/    - /;2,$s/^/      /'
    wrap_text 90 'It only installs packages; nothing is removed and no configuration is changed.' | sed '1s/^/    - /;2,$s/^/      /'
    printf '\n'
}
MAN_PURPOSE='Makes sure the tools that the devbox scripts need are installed, installing the missing ones with apt.'
MAN_NEEDS=(
    'Run it inside the container (dkdb-container-connect opens a shell).'
    'Internet access to the Ubuntu mirrors.'
    'Root, or sudo with the password of the container user, to install.'
)
MAN_STEPS=(
    'Reads the groups from the arguments (base, keyring); without arguments it uses all of them.'
    'For each group checks, with command -v, the command of every tool and collects the packages that are missing.'
    'With check it only prints what is missing and exits with 1 when something is.'
    'Otherwise runs apt-get update and apt-get install --no-install-recommends for the missing packages, with sudo when it is not root.'
    'Checks the commands again and reports, in green or red, what is now available.'
)
MAN_CHANGES=('Installs the missing Ubuntu packages (apt).')
MAN_NEVER=(
    'Removes packages or changes configuration files.'
    'Installs anything that is already present, or touches the host or other containers.'
    'Installs an AI client (use dkdb-install-claudecode.sh or dkdb-install-ghcopilot-cli.sh).'
)
MAN_NEXT='Run the script that needed the tools; bash ~/devbox/bash/dkdb-install-tools.sh check confirms that nothing is missing.'

check_only=0
selected=()
for argument in "$@"; do
    case "$argument" in
        -h|--help) usage; exit 0 ;;
        man) show_manual; exit 0 ;;
        check) check_only=1 ;;
        *)
            if [ -n "${GROUP_TOOLS[$argument]+x}" ]; then selected+=("$argument")
            else warn "Unknown argument: $argument (groups: ${GROUPS_ORDER[*]}; also check, -h, man)."; exit 1; fi ;;
    esac
done
[ "${#selected[@]}" -gt 0 ] || selected=("${GROUPS_ORDER[@]}")

banner "${BASH_SOURCE[0]}"

# Print the packages of a group that are missing (one per line, without repeats).
missing_packages() {
    local pair
    for pair in ${GROUP_TOOLS[$1]}; do
        command -v "${pair%%:*}" >/dev/null 2>&1 || printf '%s\n' "${pair#*:}"
    done | sort -u
}

missing=()
for group in "${selected[@]}"; do
    list="$(missing_packages "$group")"
    if [ -z "$list" ]; then
        ok "  $group: all the tools are present."
    else
        echo "  $group: missing packages: $(echo "$list" | tr '\n' ' ')"
        while IFS= read -r package; do missing+=("$package"); done <<< "$list"
    fi
done

if [ "${#missing[@]}" -eq 0 ]; then
    ok "Nothing to install."
    next "Next: run the script that needed the tools."
    exit 0
fi
if [ "$check_only" = 1 ]; then
    warn "Missing: ${missing[*]}"
    next "Next: bash ~/devbox/bash/$(basename "$0") installs them."
    exit 1
fi

if [ "$(id -u)" -eq 0 ]; then apt_cmd=(apt-get)
elif command -v sudo >/dev/null 2>&1; then apt_cmd=(sudo apt-get)
else warn "Error: installing needs root or sudo, and sudo was not found."; exit 1; fi

echo "Installing: ${missing[*]} (sudo may ask for the password of the container user) ..."
"${apt_cmd[@]}" update -qq || { warn "Error: apt-get update failed."; exit 1; }
"${apt_cmd[@]}" install -y --no-install-recommends "${missing[@]}" >/dev/null || { warn "Error: apt-get install failed."; exit 1; }

failed=0
for group in "${selected[@]}"; do
    left="$(missing_packages "$group")"
    if [ -z "$left" ]; then ok "  $group: ready."
    else warn "  $group: still missing: $(echo "$left" | tr '\n' ' ')"; failed=1; fi
done
if [ "$failed" -ne 0 ]; then exit 1; fi
ok "Tools installed."
next "Next: run the script that needed the tools."
