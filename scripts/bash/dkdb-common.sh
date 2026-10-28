#!/bin/bash
# Version: 0.2.1
# Common definitions of the devbox bash scripts that show information (dkdb-info.sh, dkdb-version.sh).
# Source it, do not run it:  . "$(dirname "${BASH_SOURCE[0]}")/dkdb-common.sh"; the script defines usage() and, for the manual, MAN_*.
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

# The state file written by the host scripts (Update-DevboxContainerState): the versions of the package
# and the Mutagen sessions as the host sees them. It can be out of date: it carries the time it was written.
DEVBOX_STATE_FILE="${DEVBOX_STATE_FILE:-$HOME/.devbox-state}"

# Colors (spec 01): green success, red warnings and errors, yellow the next step, cyan headings, gray
# the version line. Off when the output is not a terminal or NO_COLOR is set.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    c_green=$'\033[32m'; c_red=$'\033[31m'; c_yellow=$'\033[33m'; c_cyan=$'\033[36m'; c_gray=$'\033[90m'; c_off=$'\033[0m'
else
    c_green=''; c_red=''; c_yellow=''; c_cyan=''; c_gray=''; c_off=''
fi
ok() { printf '%s%s%s\n' "$c_green" "$*" "$c_off"; }
bad() { printf '%s%s%s\n' "$c_red" "$*" "$c_off"; }
next() { printf '%s%s%s\n' "$c_yellow" "$*" "$c_off"; }

# The layout of dkdb-info (same look as the host): SECTIONS in capitals and one color, PROPERTIES in capitals and
# another color followed by dots (at least two) up to the column of the values, VALUES in the color of what they
# are: host paths cyan, container paths magenta, the rest in the default color. A value wider than the terminal
# continues right under itself. Special words are badges (reverse video): MUTAGEN, MUTAGEN-SYNC, VOLUME-P9,
# READ-ONLY, READ-WRITE.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    c_section=$'\033[97m'; c_prop=$'\033[33m'; c_host=$'\033[36m'; c_container=$'\033[35m'
else
    c_section=''; c_prop=''; c_host=''; c_container=''
fi

info_width() {
    local columns="${COLUMNS:-}"
    [ -n "$columns" ] || columns="$(tput cols 2>/dev/null)"
    [ "${columns:-0}" -ge 40 ] 2>/dev/null || columns=80
    echo $((columns - 1))
}

info_section() {
    printf '\n%s%s%s' "$c_section" "${1^^}" "$c_off"
    [ -z "${2:-}" ] || printf ' %s%s%s' "$c_gray" "$2" "$c_off"
    echo
}

# The pieces of a value are arguments 'kind:color:text': kind t (text) or b (badge); color host, container, red,
# green, yellow or none.
info_color() {
    case "$1" in
        host) printf '%s' "$c_host" ;;
        container) printf '%s' "$c_container" ;;
        red) printf '%s' "$c_red" ;;
        green) printf '%s' "$c_green" ;;
        yellow) printf '%s' "$c_yellow" ;;
        *) printf '' ;;
    esac
}

# info_field LABEL LABEL_WIDTH INDENT PIECE...
info_field() {
    local label="${1^^}" label_width="$2" indent="$3" dots column=0 value_column room piece rest color text count token
    shift 3
    value_column=$((indent + label_width + 4))
    room=$(($(info_width) - value_column))
    [ "$room" -ge 10 ] || room=10
    # Always two dots at least; more when the label is shorter than the longest one of the block.
    dots=$((label_width - ${#label} + 2)); [ "$dots" -ge 2 ] || dots=2
    printf '%*s%s%s%s %s ' "$indent" '' "$c_prop" "$label" "$c_off" "$(printf '%*s' "$dots" '' | tr ' ' '.')"
    for piece in "$@"; do
        rest="${piece#*:}"; color="${rest%%:*}"; text="${rest#*:}"
        if [ "${piece%%:*}" = b ]; then
            token=" $text "
            if [ "$column" -gt 0 ] && [ $((column + 1 + ${#token})) -gt "$room" ]; then
                printf '\n%*s' "$value_column" ''; column=0
            fi
            if [ "$column" -gt 0 ]; then printf ' '; column=$((column + 1)); fi
            if [ -z "$c_off" ]; then
                printf '%s' "$token"
            else
                case "$color" in
                    red) printf '\033[30;41m%s\033[0m' "$token" ;;
                    green) printf '\033[30;42m%s\033[0m' "$token" ;;
                    yellow) printf '\033[30;43m%s\033[0m' "$token" ;;
                    *) printf '%s' "$token" ;;
                esac
            fi
            column=$((column + ${#token}))
            continue
        fi
        while [ -n "$text" ]; do
            if [ "$column" -ge "$room" ]; then printf '\n%*s' "$value_column" ''; column=0; fi
            count=$((room - column)); [ "$count" -le "${#text}" ] || count=${#text}
            printf '%s%s%s' "$(info_color "$color")" "${text:0:count}" "$c_off"
            column=$((column + count)); text="${text:count}"
        done
    done
    echo
}

# Version of a file: its '# Version: x.y.z' line (empty when absent).
file_version() { sed -n 's/^# Version: *//p' "$1" 2>/dev/null | head -n 1; }

# The first line of every script, like the PowerShell ones: name, own version, image version.
banner() {
    local own
    own="$(file_version "$1")"
    printf '%s%s %s (docker-devbox-ubuntu image %s)%s\n' "$c_gray" "$(basename "$1")" "${own:-unknown}" "${DEVBOX_IMAGE_VERSION:-unknown}" "$c_off"
}

# A value of the state file: key=value (empty when there is no file or no key).
state_get() { [ -r "$DEVBOX_STATE_FILE" ] && sed -n "s/^$1=//p" "$DEVBOX_STATE_FILE" | head -n 1; return 0; }
# The lines 'prefix|a|b|...' of the state file, without the prefix.
state_each() { [ -r "$DEVBOX_STATE_FILE" ] && grep "^$1|" "$DEVBOX_STATE_FILE" | sed "s/^$1|//"; return 0; }

# Same rule as the host scripts: compatible = same major.minor (0.x) or same major (1.0 and later).
version_compatible() {
    local re='^([0-9]+)\.([0-9]+)\.[0-9]+$' left_major left_minor right_major right_minor
    [[ $1 =~ $re ]] || return 1
    left_major="${BASH_REMATCH[1]}"; left_minor="${BASH_REMATCH[2]}"
    [[ $2 =~ $re ]] || return 1
    right_major="${BASH_REMATCH[1]}"; right_minor="${BASH_REMATCH[2]}"
    [ "$left_major" = "$right_major" ] || return 1
    [ "$left_major" != 0 ] || [ "$left_minor" = "$right_minor" ]
}

# Print a text wrapped and indented.
wrap_text() { printf '%s\n' "$2" | fold -s -w "$1" | sed 's/ *$//'; }

# The help of a script (-h, --help), same layout as the PowerShell ones: NAME, DESCRIPTION, USAGE, PARAMETERS,
# EXAMPLES and NOTES. Arguments: description, example description, then the notes.
show_help() {
    local description="$1" example="$2" name note
    shift 2
    name="$(basename "$0")"
    banner "$0"
    printf '\n%sNAME%s\n    %s%s%s\n' "$c_cyan" "$c_off" "$c_green" "$name" "$c_off"
    printf '\n%sDESCRIPTION%s\n' "$c_cyan" "$c_off"
    wrap_text 92 "$description" | sed 's/^/    /'
    printf '\n%sUSAGE%s\n    %sbash ~/devbox/bash/%s [-h | man]%s\n' "$c_cyan" "$c_off" "$c_green" "$name" "$c_off"
    printf '\n%sPARAMETERS%s\n' "$c_cyan" "$c_off"
    printf '    %s%-10s%s Show this help and exit.\n' "$c_green" "-h, --help" "$c_off"
    printf '    %s%-10s%s Show the manual (what the script does, step by step) and exit.\n' "$c_green" "man" "$c_off"
    printf '\n%sEXAMPLES%s\n    %sbash ~/devbox/bash/%s%s\n' "$c_cyan" "$c_off" "$c_green" "$name" "$c_off"
    wrap_text 88 "$example" | sed 's/^/        /'
    if [ "$#" -gt 0 ]; then
        printf '\n%sNOTES%s\n' "$c_cyan" "$c_off"
        for note in "$@"; do wrap_text 90 "$note" | sed '1s/^/    - /;2,$s/^/      /'; done
    fi
    printf '\n'
}

# The manual of a script (man): PURPOSE, REQUIREMENTS, WHAT IT DOES (numbered), WHAT IT CHANGES, WHAT IT NEVER DOES
# and NEXT STEP. The lists come from the arrays MAN_NEEDS, MAN_STEPS, MAN_CHANGES and MAN_NEVER, and the text from
# MAN_PURPOSE and MAN_NEXT, which the script defines.
show_manual() {
    local title item number mark list numbered
    banner "$0"
    printf '\n%sMANUAL%s\n    %s%s%s\n' "$c_cyan" "$c_off" "$c_green" "$(basename "$0")" "$c_off"
    printf '\n%sPURPOSE%s\n' "$c_cyan" "$c_off"
    wrap_text 92 "$MAN_PURPOSE" | sed 's/^/    /'
    for title in REQUIREMENTS:MAN_NEEDS:0 'WHAT IT DOES:MAN_STEPS:1' 'WHAT IT CHANGES:MAN_CHANGES:0' 'WHAT IT NEVER DOES:MAN_NEVER:0'; do
        list="${title#*:}"; numbered="${list#*:}"; list="${list%%:*}"; title="${title%%:*}"
        local -n items="$list"
        [ "${#items[@]}" -gt 0 ] || continue
        printf '\n%s%s%s\n' "$c_cyan" "$title" "$c_off"
        number=0
        for item in "${items[@]}"; do
            number=$((number + 1))
            if [ "$numbered" = 1 ]; then mark="$(printf '%2d.' "$number")"; else mark='  -'; fi
            wrap_text 84 "$item" | sed "1s/^/    $c_green$mark$c_off /;2,\$s/^/        /"
        done
        unset -n items
    done
    printf '\n%sNEXT STEP%s\n' "$c_cyan" "$c_off"
    wrap_text 92 "$MAN_NEXT" | sed "s/^/    $c_yellow/; s/\$/$c_off/"
    printf '\n'
}

# The arguments of a script: -h and --help (help), man (manual); anything else is an error.
handle_arguments() {
    local argument
    for argument in "$@"; do
        case "$argument" in
            -h|--help) usage; exit 0 ;;
            man) show_manual; exit 0 ;;
            *) bad "Unknown argument: $argument (use -h or man)."; exit 1 ;;
        esac
    done
}
