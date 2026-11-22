#!/bin/bash
# Version: 0.6.1
# Common definitions of the devbox bash scripts that show information (dkdb-info.sh, dkdb-version.sh).
# Source it, do not run it:  . "$(dirname "${BASH_SOURCE[0]}")/dkdb-common.sh"; the script defines usage() and, for the manual, MAN_*.
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

# The state file written by the host scripts (Update-DevboxContainerState): the versions of the package
# and the Mutagen sessions as the host sees them. It can be out of date: it carries the time it was written.
DEVBOX_STATE_FILE="${DEVBOX_STATE_FILE:-$HOME/.devbox-state}"

# Colors of the output (spec 01; same table as dkdb-common.ps1): ONE table, every script uses these variables.
# Messages: green success, red warnings and errors, yellow the next step. Sides: cyan a path of the host,
# magenta a path of the container; the row of a menu under the pointer is cyan too (selected). Text roles: a title (headings of -h and man), a section (SECTIONS of dkdb-info
# and dkdb-version), a label (a PROPERTY in capitals), a name (a script, command, parameter or file) and a note
# (version line, hints) and a bold white (script) for the scripts named in a Next line. Off when the output is not a terminal or NO_COLOR is set. The scripts that are not part
# of this file load it too (. dkdb-common.sh) instead of defining their own colors.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    c_green=$'\033[32m'; c_red=$'\033[31m'; c_yellow=$'\033[33m'; c_gray=$'\033[90m'; c_off=$'\033[0m'
    c_host=$'\033[36m'; c_container=$'\033[35m'; c_selected=$'\033[36m'
    c_title=$'\033[97m'; c_section=$'\033[97m'; c_label=$'\033[33m'; c_name=$'\033[33m'
    c_script=$'\033[1;97m'
    # Badges (reverse video, black text): the number of the background color of each one.
    badge_readonly=42; badge_readwrite=41; badge_mutagen=41; badge_sync=43; badge_volume=41; badge_compatible=42; badge_incompatible=41
else
    c_green=''; c_red=''; c_yellow=''; c_gray=''; c_off=''
    c_host=''; c_container=''; c_selected=''
    c_title=''; c_section=''; c_label=''; c_name=''
    c_script=''
    badge_readonly=''; badge_readwrite=''; badge_mutagen=''; badge_sync=''; badge_volume=''; badge_compatible=''; badge_incompatible=''
fi
ok() { message_text 1 "$c_green" "$*"; }
bad() { message_text 1 "$c_red" "$*"; }
warn() { message_text 2 "$c_red" "$*" >&2; }
# The natural next step in yellow; a script named in it (dkdb-<name>.ps1 or .sh) is written in bold white.
next() {
    local text="$*" rest out="" re='dkdb-[a-z0-9-]+\.(ps1|sh)'
    # On a terminal the text is wrapped at the words first (the bold codes would count as characters).
    if [ -t 1 ]; then info_width > /dev/null; text="$(wrap_text "$(info_width)" "$text")"; fi
    rest="$text"
    while [[ "$rest" =~ $re ]]; do
        out+="${rest%%"${BASH_REMATCH[0]}"*}${c_script}${BASH_REMATCH[0]}${c_off}${c_yellow}"
        rest="${rest#*"${BASH_REMATCH[0]}"}"
    done
    printf '%s%s%s%s\n' "$c_yellow" "$out" "$rest" "$c_off"
}

# The layout of dkdb-info and dkdb-version (same look as the host): SECTIONS in capitals and one color, PROPERTIES in
# capitals and another color followed by dots (at least two) up to the column of the values, VALUES in the color of
# what they are: host paths cyan, container paths magenta, the rest in the default color. A value wider than the
# terminal continues right under itself. Special words are badges (reverse video): MUTAGEN, MUTAGEN-SYNC,
# VOLUME-P9, READ-ONLY, READ-WRITE, COMPATIBLE, NOT-COMPATIBLE.

# The usable width of the terminal (one less than the window, 80 when it cannot be known). COLUMNS is only set in
# some shells and tput answers 80 when its output is a pipe, so the size is asked to the terminal itself through
# stderr, stdin or /dev/tty. Read once per run.
info_width() {
    if [ -z "${info_width_cache:-}" ]; then
        local columns="${COLUMNS:-}"
        # Each try may fail (no terminal): "|| columns=''" keeps set -e and pipefail of the scripts that source this file
        # from ending them, and the redirection of /dev/tty goes after 2>/dev/null so that its error is not printed.
        [ -n "$columns" ] || columns="$(stty size <&2 2>/dev/null | awk '{print $2}')" || columns=''
        [ -n "$columns" ] || columns="$(stty size <&0 2>/dev/null | awk '{print $2}')" || columns=''
        [ -n "$columns" ] || columns="$(stty size 2>/dev/null </dev/tty | awk '{print $2}')" || columns=''
        [ -n "$columns" ] || columns="$(tput cols 2>/dev/null)" || columns=''
        [ "${columns:-0}" -ge 40 ] 2>/dev/null || columns=80
        info_width_cache=$((columns - 1))
    fi
    echo "$info_width_cache"
}
info_width > /dev/null

info_section() {
    local line
    printf '\n%s%s%s' "$c_section" "${1^^}" "$c_off"
    if [ -z "${2:-}" ]; then echo; return; fi
    if [ $((${#1} + 1 + ${#2})) -le "$(info_width)" ]; then
        printf ' %s%s%s\n' "$c_gray" "$2" "$c_off"
        return
    fi
    # The note does not fit next to the title: it goes below, indented and wrapped at the words.
    echo
    while IFS= read -r line; do printf '  %s%s%s\n' "$c_gray" "$line" "$c_off"; done <<< "$(wrap_text 200 "$2" 2)"
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
# A badge (reverse video) for a role: readonly, readwrite, mutagen, sync, volume, compatible or incompatible.
# Plain text when the output is not a terminal.
badge() {
    local code="badge_$1" text="${2:-}"
    code="${!code:-}"
    if [ -z "$c_off" ] || [ -z "$code" ]; then printf '%s' "$text"; else printf '\033[30;%sm%s\033[0m' "$code" "$text"; fi
}

info_field() {
    local label="${1^^}" label_width="$2" indent="$3" dots column=0 value_column room piece rest color text count token cut chunk shown i
    shift 3
    value_column=$((indent + label_width + 4))
    room=$(($(info_width) - value_column))
    [ "$room" -ge 10 ] || room=10
    # Always two dots at least; more when the label is shorter than the longest one of the block.
    dots=$((label_width - ${#label} + 2)); [ "$dots" -ge 2 ] || dots=2
    printf '%*s%s%s%s %s ' "$indent" '' "$c_label" "$label" "$c_off" "$(printf '%*s' "$dots" '' | tr ' ' '.')"
    for piece in "$@"; do
        rest="${piece#*:}"; color="${rest%%:*}"; text="${rest#*:}"
        if [ "${piece%%:*}" = b ]; then
            token=" $text "
            if [ "$column" -gt 0 ] && [ $((column + 1 + ${#token})) -gt "$room" ]; then
                printf '\n%*s' "$value_column" ''; column=0
            fi
            if [ "$column" -gt 0 ]; then printf ' '; column=$((column + 1)); fi
            printf '%s' "$(badge "$color" "$token")"
            column=$((column + ${#token}))
            continue
        fi
        while [ -n "$text" ]; do
            if [ "$column" -ge "$room" ]; then printf '\n%*s' "$value_column" ''; column=0; fi
            [ "$column" -gt 0 ] || text="${text# }"
            [ -n "$text" ] || break
            count=$((room - column)); cut=$count
            if [ "${#text}" -gt "$count" ]; then
                # Too long for the line: break after the last space, / or \ that fits (not too early); without one,
                # a text that fits on a line of its own goes down whole, and a longer one is cut at the edge.
                cut=0
                for ((i = count; i > count / 3 && i > 0; i--)); do
                    case "${text:i-1:1}" in ' ' | '/' | '\') cut=$i; break ;; esac
                done
                if [ "$cut" -eq 0 ]; then
                    if [ "$column" -gt 0 ] && [ "${#text}" -le "$room" ]; then printf '\n%*s' "$value_column" ''; column=0; continue; fi
                    cut=$count
                fi
            fi
            chunk="${text:0:cut}"; text="${text:cut}"
            # Text left: the line ends here (without the space it broke at) and the rest starts on a new line.
            if [ -n "$text" ]; then shown="${chunk%"${chunk##*[! ]}"}"; else shown="$chunk"; fi
            printf '%s%s%s' "$(info_color "$color")" "$shown" "$c_off"
            column=$((column + ${#chunk}))
            if [ -n "$text" ]; then column=$room; fi
        done
    done
    echo
}

# --- Interactive menus (spec 01): same behavior as the PowerShell ones ---
# A screen of its own per menu (menu_header), Up/Down to move, Enter to select, Esc to go back (the hint says what Esc
# does), and after an option that printed something wait_key keeps it on the screen until a key is pressed. The menus
# come back until Esc; the scripts only offer them on a terminal (is_interactive), with arguments they run as always.
is_interactive() { [ -t 0 ] && [ -t 1 ]; }

# menu_header SCRIPT PATH: clears the screen and draws the version line of the script and the path of the menu.
menu_header() {
    printf '\033[2J\033[H'
    banner "$1"
    [ -z "${2:-}" ] || printf '%s%s%s\n' "$c_title" "$2" "$c_off"
    echo
}

wait_key() {
    printf '\n%sPress any key (Enter, for example) to return to the menu%s' "$c_gray" "$c_off"
    IFS= read -rsn1 _ || true
    echo
}

# select_item TITLE ESCAPE_ACTION ITEM...: ESCAPE_ACTION (back or exit) is what the hint says that Esc does. The index
# of the chosen item is left in MENU_INDEX; the return status is 1 when Esc is pressed.
select_item() {
    local title="$1" escape_action="$2" index=0 count key rest i
    shift 2
    local items=("$@")
    count=${#items[@]}
    [ "$count" -gt 0 ] || return 1
    printf '%s\n%s(Up/Down: move, Enter: select, Esc: %s)%s\n' "$title" "$c_gray" "$escape_action" "$c_off"
    printf '\033[?25l'
    while true; do
        for ((i = 0; i < count; i++)); do
            printf '\r\033[2K'
            if [ "$i" -eq "$index" ]; then printf '%s> %s%s\n' "$c_selected" "${items[$i]}" "$c_off"; else printf '  %s\n' "${items[$i]}"; fi
        done
        printf '\033[%dA' "$count"
        IFS= read -rsn1 key || key=$'\033'
        if [ "$key" = $'\033' ]; then IFS= read -rsn2 -t 0.05 rest || rest=''; key+="$rest"; fi
        case "$key" in
            $'\033[A') index=$(((index - 1 + count) % count)) ;;
            $'\033[B') index=$(((index + 1) % count)) ;;
            '') MENU_INDEX=$index; printf '\033[%dB\033[?25h' "$count"; return 0 ;;
            $'\033') printf '\033[%dB\033[?25h' "$count"; return 1 ;;
        esac
    done
}

# Version of a file: its '# Version: x.y.z' line (empty when absent).
file_version() { sed -n 's/^# Version: *//p' "$1" 2>/dev/null | head -n 1; }

# The first line of every script, like the PowerShell ones: name, own version, image version.
banner() {
    local own text line
    own="$(file_version "$1")"
    text="$(basename "$1") ${own:-unknown} (docker-devbox-ubuntu image ${DEVBOX_IMAGE_VERSION:-unknown})"
    if [ -t 1 ]; then text="$(wrap_text "$(info_width)" "$text")"; fi
    while IFS= read -r line; do printf '%s%s%s\n' "$c_gray" "$line" "$c_off"; done <<< "$text"
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

# Print a text wrapped at WIDTH columns, or less when the screen is narrower: wrap_text WIDTH TEXT [INDENT], where
# INDENT is what the caller adds in front of every line afterwards.
wrap_text() {
    local width="$1" room=$(($(info_width) - ${3:-0}))
    [ "$room" -ge 20 ] || room=20
    [ "$width" -le "$room" ] || width="$room"
    printf '%s\n' "$2" | fold -s -w "$width" | sed 's/ *$//'
}

# One parameter of a help: show_parameter NAME TEXT [WIDTH]. The name takes WIDTH characters (10 by default) and the
# text, wrapped at the words, continues under itself.
show_parameter() {
    local width="${3:-10}"
    wrap_text 80 "$2" $((width + 5)) | sed "1s/^/    $c_name$(printf '%-*s' "$width" "$1")$c_off /;2,\$s/^/$(printf '%*s' $((width + 5)) '')/"
}

# A message of ok, bad or warn in a color: message_text FD COLOR TEXT. When the output (file descriptor FD) is a
# terminal it is wrapped at the words to its width; otherwise it is printed as it is.
message_text() {
    local color="$2" text="$3" line
    if [ -t "$1" ]; then text="$(wrap_text "$(info_width)" "$text")"; fi
    while IFS= read -r line; do printf '%s%s%s\n' "$color" "$line" "$c_off"; done <<< "$text"
}

# The help of a script (-h, --help), same layout as the PowerShell ones: NAME, DESCRIPTION, USAGE, PARAMETERS,
# EXAMPLES and NOTES. Arguments: description, example description, then the notes.
show_help() {
    local description="$1" example="$2" name note
    shift 2
    name="$(basename "$0")"
    banner "$0"
    printf '\n%sNAME%s\n    %s%s%s\n' "$c_title" "$c_off" "$c_name" "$name" "$c_off"
    printf '\n%sDESCRIPTION%s\n' "$c_title" "$c_off"
    wrap_text 92 "$description" 4 | sed 's/^/    /'
    printf '\n%sUSAGE%s\n    %sbash ~/devbox/bash/%s [-h | man]%s\n' "$c_title" "$c_off" "$c_name" "$name" "$c_off"
    printf '\n%sPARAMETERS%s\n' "$c_title" "$c_off"
    show_parameter '-h, --help' 'Show this help and exit.'
    show_parameter man 'Show the manual (what the script does, step by step) and exit.'
    printf '\n%sEXAMPLES%s\n    %sbash ~/devbox/bash/%s%s\n' "$c_title" "$c_off" "$c_name" "$name" "$c_off"
    wrap_text 88 "$example" 8 | sed 's/^/        /'
    if [ "$#" -gt 0 ]; then
        printf '\n%sNOTES%s\n' "$c_title" "$c_off"
        for note in "$@"; do wrap_text 90 "$note" 6 | sed '1s/^/    - /;2,$s/^/      /'; done
    fi
    printf '\n'
}

# The manual of a script (man): PURPOSE, REQUIREMENTS, WHAT IT DOES (numbered), WHAT IT CHANGES, WHAT IT NEVER DOES
# and NEXT STEP. The lists come from the arrays MAN_NEEDS, MAN_STEPS, MAN_CHANGES and MAN_NEVER, and the text from
# MAN_PURPOSE and MAN_NEXT, which the script defines.
show_manual() {
    local title item number mark list numbered
    banner "$0"
    printf '\n%sMANUAL%s\n    %s%s%s\n' "$c_title" "$c_off" "$c_name" "$(basename "$0")" "$c_off"
    printf '\n%sPURPOSE%s\n' "$c_title" "$c_off"
    wrap_text 92 "$MAN_PURPOSE" 4 | sed 's/^/    /'
    for title in REQUIREMENTS:MAN_NEEDS:0 'WHAT IT DOES:MAN_STEPS:1' 'WHAT IT CHANGES:MAN_CHANGES:0' 'WHAT IT NEVER DOES:MAN_NEVER:0'; do
        list="${title#*:}"; numbered="${list#*:}"; list="${list%%:*}"; title="${title%%:*}"
        local -n items="$list"
        [ "${#items[@]}" -gt 0 ] || continue
        printf '\n%s%s%s\n' "$c_title" "$title" "$c_off"
        number=0
        for item in "${items[@]}"; do
            number=$((number + 1))
            if [ "$numbered" = 1 ]; then mark="$(printf '%2d.' "$number")"; else mark='  -'; fi
            wrap_text 84 "$item" 8 | sed "1s/^/    $c_name$mark$c_off /;2,\$s/^/        /"
        done
        unset -n items
    done
    printf '\n%sNEXT STEP%s\n' "$c_title" "$c_off"
    wrap_text 92 "$MAN_NEXT" 4 | sed "s/^/    $c_yellow/; s/\$/$c_off/"
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
