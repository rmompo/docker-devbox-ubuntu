#!/bin/bash
# Version: 0.2.0
# Install Claude Code (latest) in this container.
# Rule: one AI client per container. Run with: bash dkdb-install-claudecode.sh
set -euo pipefail

# Message colors (spec 01): success (something was done correctly) in green, warnings and errors in red,
# the natural next step in yellow. Other messages keep the default color.
if [ -t 1 ]; then c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_off=$'\033[0m'; else c_green=''; c_yellow=''; c_off=''; fi
if [ -t 2 ]; then c_red=$'\033[31m'; else c_red=''; fi
ok() { printf '%s%s%s\n' "$c_green" "$*" "$c_off"; }
warn() { printf '%s%s%s\n' "$c_red" "$*" "$c_off" >&2; }
next() { printf '%s%s%s\n' "$c_yellow" "$*" "$c_off"; }
# Help (-h, --help) and manual (man): same layout as the dkdb-* scripts (spec 01).
usage() {
    local cyan green off
    if [ -t 1 ]; then cyan=$'\033[36m'; green=$'\033[32m'; off=$'\033[0m'; else cyan=''; green=''; off=''; fi
    printf '\n%sNAME%s\n    %s%s%s\n' "$cyan" "$off" "$green" "$(basename "$0")" "$off"
    printf '\n%sDESCRIPTION%s\n' "$cyan" "$off"
    printf '%s\n' "Installs Claude Code (latest) in this container with its official installer, and puts ~/.local/bin on the PATH." | fold -s -w 92 | sed 's/ *$//; s/^/    /'
    printf '\n%sUSAGE%s\n    %sbash ~/devbox/bash/%s [-h | man]%s\n' "$cyan" "$off" "$green" "$(basename "$0")" "$off"
    printf '\n%sPARAMETERS%s\n' "$cyan" "$off"
    printf '    %s%-10s%s Show this help and exit.\n' "$green" "-h, --help" "$off"
    printf '    %s%-10s%s Show the manual (what the script does, step by step) and exit.\n' "$green" "man" "$off"
    printf '\n%sEXAMPLES%s\n    %sbash ~/devbox/bash/%s%s\n        Installs Claude Code.\n' "$cyan" "$off" "$green" "$(basename "$0")" "$off"
    printf '\n%sNOTES%s\n' "$cyan" "$off"
    printf '%s\n' "One AI client per container: it refuses to install if GitHub Copilot CLI is already here." | fold -s -w 90 | sed '1s/^/    - /;2,$s/^/      /'
    printf '%s\n' "Run it inside the container (dkdb-container-connect opens a shell)." | fold -s -w 90 | sed '1s/^/    - /;2,$s/^/      /'
    printf '%s\n' "It downloads about 240 MB and shows no progress bar." | fold -s -w 90 | sed '1s/^/    - /;2,$s/^/      /'
    printf '\n'
}
# Manual (man): what the script does, in colors (same layout as the dkdb-* scripts, spec 01).
manual() {
    local cyan green yellow off
    if [ -t 1 ]; then cyan=$'\033[36m'; green=$'\033[32m'; yellow=$'\033[33m'; off=$'\033[0m'; else cyan=''; green=''; yellow=''; off=''; fi
    item() { printf '%s\n' "$2" | fold -s -w 84 | sed "1s/^/    $green$1$off /;2,\$s/^/        /; s/ *\$//"; }
    printf '\n%sMANUAL%s\n    %s%s%s\n' "$cyan" "$off" "$green" "$(basename "$0")" "$off"
    printf '\n%sPURPOSE%s\n' "$cyan" "$off"
    printf '%s\n' 'Installs Claude Code (latest) in this container with its official installer. One AI client per container.' | fold -s -w 92 | sed 's/ *$//; s/^/    /'
    printf '\n%sREQUIREMENTS%s\n' "$cyan" "$off"
    item '  -' 'Run it inside the container (dkdb-container-connect opens a shell).'
    item '  -' 'Internet access (it downloads about 240 MB).'
    item '  -' 'No other AI client installed here.'
    printf '\n%sWHAT IT DOES%s\n' "$cyan" "$off"
    item ' 1.' 'Refuses, in red, when GitHub Copilot CLI is already installed.'
    item ' 2.' 'Downloads and runs the official installer from claude.ai (no progress bar is shown; it can take a few minutes).'
    item ' 3.' 'Adds ~/.local/bin to the PATH in ~/.bashrc, once.'
    printf '\n%sWHAT IT CHANGES%s\n' "$cyan" "$off"
    item '  -' 'Claude Code under ~/.local, and one line in ~/.bashrc.'
    printf '\n%sWHAT IT NEVER DOES%s\n' "$cyan" "$off"
    item '  -' 'Installs a second AI client.'
    item '  -' 'Touches the host or other containers.'
    printf '\n%sNEXT STEP%s\n' "$cyan" "$off"
    printf '%s\n' 'Open a new shell (or run: source ~/.bashrc) and run: claude' | fold -s -w 92 | sed "s/ *\$//; s/^/    $yellow/; s/\$/$off/"
    printf '\n'
}
for argument in "$@"; do
    case "$argument" in
        -h|--help) usage; exit 0 ;;
        man) manual; exit 0 ;;
        *) warn "Unknown argument: $argument (use -h or man)."; exit 1 ;;
    esac
done
script_version="$(sed -n 's/^# Version: *//p' "$0" | head -n 1)"
echo "$(basename "$0") ${script_version:-unknown} (docker-devbox-ubuntu image ${DEVBOX_IMAGE_VERSION:-unknown})"

# Refuse to install if the other client is already present.
if command -v copilot >/dev/null 2>&1 || [ -e "$HOME/.local/bin/copilot" ]; then
    warn "GitHub Copilot CLI is already installed here."
    warn "Use another container to install Claude Code."
    exit 1
fi

echo "Downloading and installing Claude Code (about 240 MB, it can take a few minutes; no progress bar is shown)..."
curl -fsSL https://claude.ai/install.sh | bash

# Make sure ~/.local/bin is on the PATH (idempotent).
line='export PATH="$HOME/.local/bin:$PATH"'
if ! grep -qxF "$line" "$HOME/.bashrc" 2>/dev/null; then
    echo "$line" >> "$HOME/.bashrc"
fi

ok "Claude Code installed."
next "Next: open a new shell (or run: source ~/.bashrc) and run: claude"
